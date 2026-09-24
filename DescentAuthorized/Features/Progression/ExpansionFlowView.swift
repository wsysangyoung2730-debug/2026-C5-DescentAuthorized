import SwiftUI

/// Shared playable flow; artwork can be replaced without changing progression.
struct ExpansionFlowView: View {
    @EnvironmentObject private var gameSession: GameSessionStore
    @EnvironmentObject private var appSettings: AppSettings
    @Environment(\.isGlyphInputSuspended) private var inheritedInputSuspension
    @ObservedObject var sceneController: RealitySceneController
    @Binding var retryLoadingPresentation: SceneRetryLoadingPresentation?
    let onExit: () -> Void
    let onRestartBattle: () -> Void
    @State private var showsBag = false
    @Binding var learningInputActive: Bool
    @State private var practiceSpell: SpellID?
    @State private var showsPractice = false

    var body: some View {
        if let current = gameSession.progress.expansion {
            if current.isLowerFloor {
                LowerFloorFlowView(current: current, sceneController: sceneController,
                    retryLoadingPresentation: $retryLoadingPresentation,
                    learningInputActive: $learningInputActive, onExit: onExit,
                    onRestartBattle: onRestartBattle)
            } else {
            ZStack {
                if gameSession.presentation.floorSceneID == nil && !current.stage.isBattle {
                    ExpansionBackdropView(floorNumber: current.floorNumber, isBoss: current.showsBoss)
                }
                content(current)
                    .environment(\.isGlyphInputSuspended, inheritedInputSuspension || combatGuide != nil)
                if let guide = combatGuide { ExpansionCombatGuideView(guide: guide) }
            }
            .task(id: current.stage) {
                synchronizeScene(current)
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--expansion-exploration-diagnostics"),
                   ExpansionPreviewSupport.floor != nil {
                    await sceneController.runExpansionExplorationDiagnostics(isBattle: current.stage.isBattle)
                }
                #endif
            }
            .onChange(of: inheritedInputSuspension) { _, suspended in
                sceneController.setActorMotionSuspended(suspended || combatGuide != nil)
            }
            .onChange(of: appSettings.graphicsQuality) { _, _ in
                prefetchNextScene(current)
            }
            .onChange(of: combatGuide != nil) { _, showing in
                sceneController.setActorMotionSuspended(showing || inheritedInputSuspension)
            }
            .onDisappear { sceneController.setActorMotionSuspended(false) }
            .sheet(isPresented: $showsPractice) {
                if let practiceSpell { SpellPracticeSheet(spell: SpellCatalog.spell(practiceSpell)) }
            }
            }
        }
    }

    private func synchronizeScene(_ current: ExpansionProgress) {
        prefetchNextScene(current)
        let hidden: [ExpansionStage] = [.sealedDoor, .reward, .descent, .learnDebuff, .complete]
        // Initialize entry before the first frame; InvestigationFlow then owns
        // the transition from exploration to the locked enemy reveal.
        if current.stage == .entrance || current.stage == .preparation {
            let completed = ExpansionInvestigationCatalog.isComplete(
                floor: current.floorNumber, readRecordIDs: gameSession.progress.readRecordIDs
            )
            sceneController.setEnemyPreviewVisible(completed)
            sceneController.setLimitedCameraInteractionEnabled(!completed)
        } else {
            sceneController.setEnemyPreviewVisible(!hidden.contains(current.stage))
            sceneController.setLimitedCameraInteractionEnabled(current.stage.isBattle)
        }
        sceneController.setActorMotionSuspended(inheritedInputSuspension || combatGuide != nil)
        switch current.stage {
        case .preparation, .bossPreparation, .entrance:
            sceneController.prepareExpansionActor()
        case .residualBattle, .bossBattle:
            sceneController.playExpansionActorMotion("appear")
        case .residualDefeated, .bossDefeated:
            sceneController.playExpansionActorMotion("death")
        default: break
        }
    }

    // Prepare during reading/selection, never begin speculative work during combat.
    private func prefetchNextScene(_ current: ExpansionProgress) {
        let next: FloorSceneID?
        switch (current.floorNumber, current.stage) {
        case (7, .sealedDoor): next = .floor07CoordinateAdministrator
        case (6, .sealedDoor): next = .floor06CausalityAdministrator
        case (5, .sealedDoor): next = .floor05OriginalMemoryAdministrator
        case (7, .reward), (7, .descent): next = .floor06CausalityResidue
        case (6, .reward), (6, .descent): next = .floor05MemoryOmissionResidue
        default: next = nil
        }
        if let next { sceneController.prefetchRoom(sceneID: next, quality: appSettings.graphicsQuality) }
    }

    private var combatGuide: ExpansionCombatGuide? {
        ExpansionCombatGuide.current(progress: gameSession.progress, battle: gameSession.battleState, events: gameSession.latestCommandEvents)
    }

    @ViewBuilder
    private func content(_ current: ExpansionProgress) -> some View {
        switch current.stage {
        case .residualInvestigation, .recordReward, .finalRecord:
            EmptyView() // LowerFloorFlowView owns these durable stages.
        case .entrance, .preparation:
            InvestigationFlow(
                sceneController: sceneController,
                configuration: .expansion(floor: current.floorNumber),
                hasCompletedInvestigation: ExpansionInvestigationCatalog.isComplete(
                    floor: current.floorNumber, readRecordIDs: gameSession.progress.readRecordIDs
                ),
                hasCompletedPostInvestigation: current.floorNumber != 6
                    || gameSession.progress.learnedSpells.contains(.outputReduction),
                restoresEnemyOnDisappear: false,
                postInvestigationContent: { _ in
                    Color.clear.task {
                        gameSession.send(.advanceExpansion)
                    }
                }
            ) {
                if showsBag {
                    LoadoutPreparationView(onBegin: {
                        showsBag = false
                        gameSession.send(.advanceExpansion)
                    }, onCancel: { showsBag = false })
                } else {
                    FloorEntrancePanel(
                        configuration: .expansionPreparation(floorNumber: current.floorNumber,
                            areaName: current.areaName, isBoss: false),
                        action: {
                            if current.stage == .entrance {
                                gameSession.send(.advanceExpansion)
                            }
                            showsBag = true
                        }
                    )
                }
            }
        case .bossPreparation:
            if showsBag {
                LoadoutPreparationView(onBegin: { gameSession.send(.advanceExpansion) }, onCancel: { showsBag = false })
            } else {
                FloorEntrancePanel(
                    configuration: .expansionPreparation(
                        floorNumber: current.floorNumber,
                        areaName: current.areaName,
                        isBoss: true
                    ),
                    action: { showsBag = true }
                )
            }
        case .residualBattle, .bossBattle:
            BattleView(realityController: sceneController, restartLoadingPresentation: $retryLoadingPresentation, onRestartBattle: onRestartBattle)
        case .residualEncounter, .bossEncounter, .residualDefeated, .bossDefeated:
            // The shared narrative presentation owns these stages, just as on 8F.
            EmptyView()
        case .sealedDoor:
            GateSealInteractionView(
                title: SpellCatalog.sealRelease.name,
                instruction: "금색 핵심점을 따라 해제 문양을 완성하십시오.",
                spell: SpellCatalog.sealRelease,
                inputPreference: appSettings.inputPreference,
                availableMana: 100,
                availableStrokes: 2,
                presentation: GateSealGlyphPresentation()
            ) { submission in
                guard submission.evaluation.succeeded else { return }
                gameSession.send(.releaseExpansionSeal(submission.evaluation.grade))
            }
        case .reward:
            RewardSelectionView(floorNumber: current.floorNumber, sceneController: sceneController,
                isLearningInputActive: $learningInputActive)
        case .descent:
            DescentDoorSceneView(configuration: .expansion(floorNumber: current.floorNumber),
                sceneController: sceneController, retryLoadingPresentation: $retryLoadingPresentation)
        case .learnDebuff:
            ScrollSpellLearningView(spell: SpellCatalog.spell(.outputReduction),
                sourceCode: "제6층 · 출력 저하 기록",
                discoveryText: "적의 다음 타격을 약화시키는 디버프 주문입니다. 문양을 익힌 뒤 출전 가방에서 사용 여부를 선택하세요.",
                presentation: .standard, tutorialSequence: nil, failureMechanic: nil) { grade in
                    gameSession.send(.learnExpansionDebuff(grade))
                }
        case .complete:
            VStack(spacing: 20) {
                Spacer()
                Text("제4층 하강 권한 승인").font(.largeTitle.weight(.semibold)).foregroundStyle(DAColor.gold)
                Text("5층까지의 승인 절차를 완료했습니다.").foregroundStyle(DAColor.body)
                Text("획득한 주문은 시험 각인에서 계속 연습할 수 있습니다.").font(.callout).foregroundStyle(DAColor.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(SpellID.allCases.filter(gameSession.progress.learnedSpells.contains), id: \.self) { id in
                            Button(SpellCatalog.spell(id).name) { practiceSpell = id; showsPractice = true }
                                .buttonStyle(.bordered).tint(DAColor.gold)
                        }
                    }.padding(.horizontal, 24)
                }
                Button("타이틀로", action: onExit).buttonStyle(.borderedProminent).tint(DAColor.magic)
                Spacer()
            }
            .padding(24).background(.black.opacity(0.82))
        }
    }

}
