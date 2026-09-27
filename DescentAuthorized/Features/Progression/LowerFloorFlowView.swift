import SwiftUI

/// Lower-floor progression uses the same installed 3D room and shared gameplay panels.
struct LowerFloorFlowView: View {
    @EnvironmentObject private var gameSession: GameSessionStore
    @EnvironmentObject private var appSettings: AppSettings
    @Environment(\.isGlyphInputSuspended) private var inputSuspended
    let current: ExpansionProgress
    @ObservedObject var sceneController: RealitySceneController
    @Binding var retryLoadingPresentation: SceneRetryLoadingPresentation?
    @Binding var learningInputActive: Bool
    let onExit: () -> Void
    let onRestartBattle: () -> Void
    @State private var showsBag = false
    @State private var selectedRecord: ExpansionInvestigationRecord?

    var body: some View {
        ZStack {
            if gameSession.presentation.floorSceneID == nil {
                ExpansionBackdropView(floorNumber: current.floorNumber,
                    isBoss: current.showsBoss, residualIndex: current.residualIndex)
            }
            content
        }
        .task(id: "\(current.floorNumber)-\(current.residualIndex)-\(current.stage.rawValue)") { synchronizeScene() }
        .onChange(of: gameSession.progress.readRecordIDs) { _, _ in synchronizeScene() }
        .onChange(of: appSettings.graphicsQuality) { _, _ in prefetchNextScene() }
        .onChange(of: inputSuspended) { _, value in sceneController.setActorMotionSuspended(value) }
        .onDisappear { learningInputActive = false; sceneController.setActorMotionSuspended(false) }
        .onChange(of: current.stage) { _, _ in
            selectedRecord = nil
            showsBag = false
        }
        .onChange(of: current.floorNumber) { _, _ in
            selectedRecord = nil
            showsBag = false
        }
    }

    @ViewBuilder private var content: some View {
        switch current.stage {
        case .entrance, .residualInvestigation:
            if showsBag { loadout } else { investigation }
        case .preparation, .bossPreparation, .residualEncounter, .bossEncounter:
            if showsBag { loadout } else { entryPanel }
        case .residualDefeated, .bossDefeated:
            let dialogues = LowerFloorNarrativeCatalog.encounter(current)
            storyPanel(title: dialogues.first?.speaker ?? current.areaName,
                subtitle: "집행 종료", body: dialogues.map(\.text).joined(separator: "\n\n"),
                button: "계속하기", action: advance)
        case .residualBattle, .bossBattle:
            BattleView(realityController: sceneController,
                restartLoadingPresentation: $retryLoadingPresentation, onRestartBattle: onRestartBattle)
        case .residualGate, .sealedDoor:
            ZStack {
                if gameSession.presentation.floorSceneID == nil {
                    Image("GateSealMechanism").resizable().scaledToFit().opacity(0.45)
                }
                GateSealInteractionView(title: current.stage == .residualGate ? "잔류체 B 구역 · 중앙문 봉인 해제" : "관리자 구역 · 중간문 봉인 해제",
                    instruction: "핵심점을 한 번의 획으로 이어 중앙문을 해제하십시오.",
                    spell: SpellCatalog.middleDoor(floor: current.floorNumber, residualTransfer: current.stage == .residualGate), inputPreference: appSettings.inputPreference,
                    availableMana: 100, availableStrokes: 2, presentation: GateSealGlyphPresentation()) { submission in
                        guard submission.evaluation.succeeded else { return }
                        gameSession.send(.releaseExpansionSeal(submission.evaluation.grade))
                    }
            }
        case .recordReward, .reward:
            if gameSession.progress.currentRewardCandidates.isEmpty {
                storyPanel(title: "기록 열람 완료", subtitle: "중복 없는 보상",
                    body: "이 지점에서 받을 수 있는 주문을 모두 습득했습니다. 기존 주문은 그대로 보관됩니다.",
                    button: "다음 절차로", action: advance)
            } else {
                RewardSelectionView(floorNumber: current.floorNumber, sceneController: sceneController,
                    isLearningInputActive: $learningInputActive)
            }
        case .finalRecord:
            storyPanel(title: "최초 승인자의 기록", subtitle: "제1층 · 최종 기록",
                body: "봉인을 유지하겠다는 서약은 강요된 것이 아니었다.\n기억을 잃더라도, 그 책임을 다음 사람에게 넘기지 않겠다고 내가 서명했다.\n\n이제 출구의 세 승인란만이 남아 있다.",
                button: "기록을 받아들이고 출구로", action: advance)
        case .descent:
            DescentDoorSceneView(configuration: .expansion(floorNumber: current.floorNumber),
                sceneController: sceneController, retryLoadingPresentation: $retryLoadingPresentation)
        case .complete:
            storyPanel(title: "다음 탑 · 제10층", subtitle: "하강 권한 인계 완료",
                body: "출구 너머는 바깥이 아니었다.\n낯선 탑의 접수실. 익숙한 승인 절차가 기다리고 있었다.\n\n“이전 탑의 유지 기록을 확인했습니다. 인계를 시작합니다.”\n\n이 탑의 여정이 완료되었습니다. 구간 선택에서 기록과 전투를 다시 확인할 수 있습니다.",
                button: "타이틀로", action: onExit)
        case .learnDebuff:
            EmptyView() // This stage is valid only on 6F.
        }
    }

    private func prefetchNextScene() {
        if let next = FinalSceneContract.nextRoom(for: current) {
            sceneController.prefetchRoom(sceneID: next, quality: appSettings.graphicsQuality)
        }
    }

    private func synchronizeScene() {
        prefetchNextScene()
        guard gameSession.presentation.floorSceneID != nil else { return }
        let visible: [ExpansionStage] = [.preparation, .residualEncounter, .residualBattle,
            .bossPreparation, .bossEncounter, .bossBattle, .residualDefeated, .bossDefeated]
        let records = ExpansionInvestigationCatalog.records(for: current.floorNumber)
        let record = current.stage == .residualInvestigation ? records.last : records.first
        let investigated = [.entrance, .residualInvestigation].contains(current.stage)
            && record.map { gameSession.progress.readRecordIDs.contains($0.id) } == true
        sceneController.setEnemyPreviewVisible(visible.contains(current.stage) || investigated)
        sceneController.setLimitedCameraInteractionEnabled(current.stage.isBattle)
        sceneController.setActorMotionSuspended(inputSuspended)
        if [.entrance, .residualInvestigation, .preparation, .bossPreparation].contains(current.stage) {
            sceneController.prepareExpansionActor()
        }
        if current.stage.isBattle { sceneController.playExpansionActorMotion("appear") }
        if [.residualDefeated, .bossDefeated].contains(current.stage) { sceneController.playExpansionActorMotion("death") }
    }

    private var enemy: EnemyDefinition? {
        ExpansionEnemyCatalog.enemy(floor: current.floorNumber,
            isBoss: current.showsBoss, residualIndex: current.residualIndex)
    }

    private var loadout: some View {
        LoadoutPreparationView(onBegin: {
            gameSession.send(.beginPreparedLowerBattle)
        }, onCancel: { showsBag = false })
    }

    private var entryPanel: some View {
        FloorEntrancePanel(configuration: .lowerPreparation(current: current)) { showsBag = true }
    }

    private var investigation: some View {
        let followup = current.stage == .residualInvestigation
        let records = ExpansionInvestigationCatalog.records(for: current.floorNumber)
        let visible = followup ? Array(records.suffix(1)) : Array(records.prefix(1))
        let read = visible.allSatisfy { gameSession.progress.readRecordIDs.contains($0.id) }
        return HStack(spacing: 26) {
            VStack(alignment: .leading, spacing: 18) {
                Text("제\(current.floorNumber)층 · \(current.areaName)")
                    .font(.title2.weight(.semibold)).foregroundStyle(DAColor.gold)
                Text(followup ? "다른 조사 구역에서 남은 집행을 추적하십시오." : "남겨진 기록을 열람하여 첫 번째 잔류체를 확인하십시오.")
                    .foregroundStyle(DAColor.body)
                ForEach(visible, id: \.id) { record in
                    Button {
                        selectedRecord = record
                        gameSession.send(.readRecord(record.id))
                    } label: {
                        HStack(spacing: 16) {
                            Image(gameSession.progress.readRecordIDs.contains(record.id)
                                  ? "InvestigationAnchorCompleted" : "InvestigationAnchorAvailable")
                                .resizable().scaledToFit().frame(width: 54, height: 54)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(record.title).font(.headline).foregroundStyle(DAColor.gold)
                                Text(record.detection).font(.callout).foregroundStyle(DAColor.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(DAColor.gold)
                        }
                        .padding(16)
                        .background(.black.opacity(0.8))
                        .overlay {
                            Rectangle().stroke(DAColor.gold.opacity(0.5))
                                .allowsHitTesting(false)
                        }
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                Text("잔류체 \(followup ? "A 처치 → B 조사" : "A → B") · 순차 전투")
                    .font(.caption).foregroundStyle(DAColor.secondary)
            }.frame(maxWidth: .infinity)
            if read {
                entryPanel.frame(maxWidth: .infinity)
            } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(selectedRecord?.title ?? (read ? visible.first?.title : "조사 기록" ) ?? "조사 기록")
                        .font(.title2.weight(.semibold)).foregroundStyle(DAColor.gold)
                    Text(selectedRecord?.body ?? (read ? visible.first?.body : "빛나는 기록을 선택하여 열람하십시오.") ?? "")
                        .font(.system(size: 20, design: .serif)).lineSpacing(8)
                        .foregroundStyle(DAColor.body)
                }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(.black.opacity(0.92))
            .overlay {
                Rectangle().stroke(DAColor.gold.opacity(0.4))
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity)
            }
        }
        .padding(36)
        .background(.black.opacity(0.45))
    }

    private func storyPanel(title: String, subtitle: String, body: String,
                            button: String, action: @escaping () -> Void) -> some View {
        HStack {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 20) {
                Text(subtitle).font(.callout).foregroundStyle(DAColor.secondary)
                Text(title).font(.system(size: 30, weight: .semibold, design: .serif)).foregroundStyle(DAColor.gold)
                Rectangle().fill(DAColor.gold.opacity(0.4)).frame(height: 1)
                ScrollView {
                    Text(body).font(.system(size: 20, design: .serif)).lineSpacing(10)
                        .foregroundStyle(DAColor.body).frame(maxWidth: .infinity, alignment: .leading)
                }
                actionButton(button, action: action)
            }
            .padding(30).frame(maxWidth: 530)
            .background(.black.opacity(0.9))
            .overlay {
                Rectangle().stroke(DAColor.gold.opacity(0.55))
                    .allowsHitTesting(false)
            }
        }.padding(32)
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.title3.weight(.semibold)).foregroundStyle(DAColor.gold)
                .padding(.horizontal, 28).padding(.vertical, 14).frame(maxWidth: .infinity)
                .background {
                    Image("Floor9EntryButtonPlate").resizable().scaledToFill()
                        .allowsHitTesting(false)
                }
                .clipped()
                // Clipping the artwork does not clip its hit region. Keep the
                // disabled preparation button from covering the record above it.
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func advance() { gameSession.send(.advanceExpansion) }
}

