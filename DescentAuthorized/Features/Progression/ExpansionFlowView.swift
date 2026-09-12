import SwiftUI

/// Shared playable flow; artwork can be replaced without changing progression.
struct ExpansionFlowView: View {
    @EnvironmentObject private var gameSession: GameSessionStore
    @EnvironmentObject private var appSettings: AppSettings
    @Environment(\.isGlyphInputSuspended) private var inheritedInputSuspension
    @ObservedObject var sceneController: RealitySceneController
    @Binding var retryLoadingPresentation: SceneRetryLoadingPresentation?
    let onExit: () -> Void
    @State private var showsBag = true
    @State private var learningInputActive = false
    @State private var practiceSpell: SpellID?
    @State private var showsPractice = false

    var body: some View {
        if let current = gameSession.progress.expansion {
            ZStack {
                if !current.stage.isBattle {
                    ExpansionBackdropView(floorNumber: current.floorNumber, isBoss: current.showsBoss)
                }
                content(current)
                    .environment(\.isGlyphInputSuspended, inheritedInputSuspension || combatGuide != nil)
                if let guide = combatGuide { ExpansionCombatGuideView(guide: guide) }
            }
            .sheet(isPresented: $showsPractice) {
                if let practiceSpell { SpellPracticeSheet(spell: SpellCatalog.spell(practiceSpell)) }
            }
        }
    }

    private var combatGuide: ExpansionCombatGuide? {
        ExpansionCombatGuide.current(progress: gameSession.progress, battle: gameSession.battleState, events: gameSession.latestEvents)
    }

    @ViewBuilder
    private func content(_ current: ExpansionProgress) -> some View {
        switch current.stage {
        case .entrance:
            procedure(title: "제\(current.floorNumber)층 · \(current.areaName)",
                detail: "관측 잔류체를 처리하고 봉인 해제로 관리자 구역을 개방하세요.",
                button: "들어가기", enabled: ExpansionEnemyCatalog.enemy(floor: current.floorNumber, isBoss: false) != nil) {
                gameSession.send(.advanceExpansion)
            }
        case .preparation, .bossPreparation:
            if showsBag {
                LoadoutPreparationView(onBegin: { gameSession.send(.advanceExpansion) }, onCancel: { showsBag = false })
            } else {
                procedure(title: current.showsBoss ? "관리자 구역" : "잔류체 구역", detail: "전투 전에 주문 구성을 확인하세요.", button: "출전 준비") { showsBag = true }
            }
        case .residualBattle, .bossBattle:
            BattleView(realityController: sceneController, restartLoadingPresentation: $retryLoadingPresentation)
        case .residualDefeated:
            procedure(title: "잔류체 무력화", detail: "생명력 회복 완료 · 현재 HP \(gameSession.progress.playerHP)\n관리자 구역의 봉인이 남아 있습니다.", button: "봉인문으로") {
                gameSession.send(.advanceExpansion)
            }
        case .sealedDoor:
            VStack(spacing: 14) {
                Text("관리자 구역 · 봉인 해제").font(.title2.weight(.semibold)).foregroundStyle(DAColor.gold)
                Text("배웠던 봉인 해제 문양을 재현하세요.").foregroundStyle(DAColor.body)
                GlyphCastingPanel(spell: SpellCatalog.sealRelease, inputPreference: appSettings.inputPreference,
                    availableMana: 100, availableStrokes: 2, erasureZones: [], onCast: { submission in
                        if submission.evaluation.succeeded { gameSession.send(.releaseExpansionSeal(submission.evaluation.grade)) }
                    })
                    .frame(maxWidth: 640)
            }
            .padding(28).background(.black.opacity(0.66))
        case .bossDefeated:
            procedure(title: "관리자 무력화", detail: "관리 권한을 회수했습니다. 주문 기록 세 가지 중 하나를 선택하세요.", button: "보상 기록 열기") {
                gameSession.send(.advanceExpansion)
            }
        case .reward:
            RewardSelectionView(floorNumber: current.floorNumber, sceneController: sceneController,
                isLearningInputActive: $learningInputActive)
        case .descent:
            DescentSealProcedureView(configuration: .expansion(floorNumber: current.floorNumber),
                initialCompletedStages: current.descentStage,
                onStageApproved: { gameSession.sendChecked(.approveExpansionStage($0)) },
                onApproved: { gameSession.send(.advanceExpansion) })
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

    private func procedure(title: String, detail: String, button: String, enabled: Bool = true,
        action: @escaping () -> Void) -> some View {
        VStack(spacing: 20) {
            Spacer()
            VStack(spacing: 16) {
                Text(title).font(.system(size: 30, weight: .semibold, design: .serif)).foregroundStyle(DAColor.gold)
                Text(detail).font(.callout).foregroundStyle(DAColor.body).multilineTextAlignment(.center)
                Button(button, action: action).buttonStyle(.borderedProminent).tint(DAColor.magic)
                    .controlSize(.large).disabled(!enabled)
            }
            .padding(28).frame(maxWidth: 650)
            .background(.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(DAColor.gold.opacity(0.35)))
            Spacer().frame(height: 44)
        }.padding(24)
    }
}
