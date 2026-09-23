import SwiftUI

/// The lower floors use approved portrait artwork and the shared gameplay panels.
/// No transition depends on a RealityKit scene, actor, or reward animation being ready.
struct LowerFloorFlowView: View {
    @EnvironmentObject private var gameSession: GameSessionStore
    @EnvironmentObject private var appSettings: AppSettings
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
            ExpansionBackdropView(floorNumber: current.floorNumber,
                isBoss: current.showsBoss, residualIndex: current.residualIndex)
            content
        }
        .onDisappear { learningInputActive = false }
    }

    @ViewBuilder private var content: some View {
        switch current.stage {
        case .entrance, .residualInvestigation:
            investigation
        case .preparation, .bossPreparation:
            if showsBag {
                LoadoutPreparationView(onBegin: advance, onCancel: { showsBag = false })
            } else {
                storyPanel(title: enemy?.name ?? current.areaName,
                    subtitle: current.showsBoss ? "관리자 심사" : "잔류체 \(current.residualIndex + 1) / 2",
                    body: "턴당 3획 · 마나 150\n출전 주문 최대 6개 / 금서 최대 2개\n\n적 체력 \(enemy?.maxHP ?? 0)\n첫 예고: \(enemy?.pattern.first?.name ?? "대기")",
                    button: "출전 가방 준비") { showsBag = true }
            }
        case .residualEncounter, .bossEncounter, .residualDefeated, .bossDefeated:
            let dialogues = LowerFloorNarrativeCatalog.encounter(current)
            storyPanel(title: dialogues.first?.speaker ?? current.areaName,
                subtitle: current.stage.isEncounter ? "조우 기록" : "집행 종료",
                body: dialogues.map(\.text).joined(separator: "\n\n"),
                button: current.stage.isEncounter ? "전투 시작" : "계속하기", action: advance)
        case .residualBattle, .bossBattle:
            BattleView(realityController: sceneController,
                restartLoadingPresentation: $retryLoadingPresentation, onRestartBattle: onRestartBattle)
        case .sealedDoor:
            ZStack {
                Image("GateSealMechanism").resizable().scaledToFit().opacity(0.45)
                GateSealInteractionView(title: "관리자 구역 · 중간문 봉인 해제",
                    instruction: "두 잔류체의 집행을 마쳤습니다. 봉인을 해제하여 옆 통로로 진입하십시오.",
                    spell: SpellCatalog.sealRelease, inputPreference: appSettings.inputPreference,
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
            LowerFloorDescentView(current: current)
        case .complete:
            storyPanel(title: "다음 탑 · 제10층", subtitle: "하강 권한 인계 완료",
                body: "출구 너머는 바깥이 아니었다.\n낯선 탑의 접수실. 익숙한 승인 절차가 기다리고 있었다.\n\n“이전 탑의 유지 기록을 확인했습니다. 인계를 시작합니다.”\n\n이 탑의 여정이 완료되었습니다. 구간 선택에서 기록과 전투를 다시 확인할 수 있습니다.",
                button: "타이틀로", action: onExit)
        case .learnDebuff:
            EmptyView() // This stage is valid only on 6F.
        }
    }

    private var enemy: EnemyDefinition? {
        ExpansionEnemyCatalog.enemy(floor: current.floorNumber,
            isBoss: current.showsBoss, residualIndex: current.residualIndex)
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
                        }.padding(16).background(.black.opacity(0.8))
                            .overlay(Rectangle().stroke(DAColor.gold.opacity(0.5)))
                    }.buttonStyle(.plain)
                }
                Text("잔류체 \(followup ? "A 처치 → B 조사" : "A → B") · 순차 전투")
                    .font(.caption).foregroundStyle(DAColor.secondary)
                actionButton(followup ? "두 번째 잔류체 준비" : "첫 번째 잔류체 준비", action: advance)
                    .disabled(!read)
            }.frame(maxWidth: .infinity)
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
            .overlay(Rectangle().stroke(DAColor.gold.opacity(0.4)))
            .frame(maxWidth: .infinity)
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
            .overlay(Rectangle().stroke(DAColor.gold.opacity(0.55)))
        }.padding(32)
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.title3.weight(.semibold)).foregroundStyle(DAColor.gold)
                .padding(.horizontal, 28).padding(.vertical, 14).frame(maxWidth: .infinity)
                .background {
                    Image("Floor9EntryButtonPlate").resizable().scaledToFill()
                }.clipped()
        }.buttonStyle(.plain)
    }

    private func advance() { gameSession.send(.advanceExpansion) }
}

private struct LowerFloorDescentView: View {
    @EnvironmentObject private var gameSession: GameSessionStore
    @EnvironmentObject private var appSettings: AppSettings
    let current: ExpansionProgress
    @State private var approvedThisVisit = false

    var body: some View {
        let definitions = DescentDoorGlyphCatalog.lowerFloorApprovals(floor: current.floorNumber)
        VStack(spacing: 12) {
            HStack(spacing: 20) {
                ForEach(Array(definitions.enumerated()), id: \.element.id) { index, definition in
                    Label("\(index + 1). \(definition.name)",
                        systemImage: index < current.descentStage ? "checkmark.seal.fill" : "lock.circle")
                        .foregroundStyle(index < current.descentStage ? DAColor.gold : DAColor.secondary)
                }
            }.font(.headline).padding(.top, 16)
            if current.descentStage == definitions.count {
                Spacer()
                Image("ScrollLearningCompletionSeal").resizable().scaledToFit().frame(height: 120)
                Text("세 문양의 승인 기록이 저장되었습니다.").font(.title2).foregroundStyle(DAColor.gold)
                Text(current.floorNumber == 1 ? "출구가 열렸습니다." : "다음 층으로 내려갈 수 있습니다.")
                    .foregroundStyle(DAColor.body)
                Button(current.floorNumber == 1 ? "출구로 나아가기" : "제\(current.floorNumber - 1)층으로 하강") {
                    gameSession.send(.advanceExpansion)
                }.buttonStyle(.borderedProminent).tint(DAColor.magic).controlSize(.large)
                Spacer()
            } else {
                let definition = definitions[current.descentStage]
                Text("\(definition.name) · \(definition.requiredStrokes)획 · 승인 \(current.descentStage)/3")
                    .font(.title2.weight(.semibold)).foregroundStyle(DAColor.gold)
                Text("시범을 확인한 뒤 따라 그리십시오. 실패해도 앞선 승인은 유지됩니다.")
                    .foregroundStyle(DAColor.secondary)
                GeometryReader { geometry in
                    GlyphCastingPanel(spell: inputSpell(definition), inputPreference: appSettings.inputPreference,
                        availableMana: 150, availableStrokes: definition.requiredStrokes, erasureZones: [],
                        showsResourceHeader: false, inputFeedbackMode: .practice,
                        gateSealPresentation: .init(stageTitles: ["문양 확인", "승인 대조", "기록 저장"], castTitle: "승인 문양 제출")) { submission in
                            guard submission.evaluation.succeeded, !approvedThisVisit else { return }
                            approvedThisVisit = true
                            gameSession.send(.approveExpansionStage(current.descentStage + 1))
                        }
                        .frame(width: min(geometry.size.width - 40, max(430, geometry.size.height * 1.15)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .id(definition.id)
                }
            }
        }
        .background(.black.opacity(0.84))
        .onChange(of: current.descentStage) { _, _ in approvedThisVisit = false }
    }

    /// A presentation adapter only. Door input never grants or casts a combat spell.
    private func inputSpell(_ definition: DescentDoorGlyphDefinition) -> SpellDefinition {
        .init(id: .sealRelease, name: definition.name, category: .dispel, tier: .sealed,
              recommendedMana: definition.recommendedMana, effect: .dispelAbsoluteBarrier(minimumCharges: 1, maximumCharges: 1),
              glyph: definition.glyph)
    }
}
