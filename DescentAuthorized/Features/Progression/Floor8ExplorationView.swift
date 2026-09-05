import SwiftUI

struct Floor8ExplorationView: View {
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var gameSession: GameSessionStore

    let sceneController: RealitySceneController

    var body: some View {
        Group {
            if gameSession.progress.currentScene == .floor8Antechamber {
                InvestigationFlow(
                    sceneController: sceneController,
                    configuration: .floor8,
                    hasCompletedInvestigation: hasCompletedEntranceInvestigation,
                    hasCompletedPostInvestigation: hasCompletedBarrierScrollLearning,
                    postInvestigationContent: { completion in
                        ScrollSpellLearningView(
                            spell: SpellCatalog.basicBarrier,
                            sourceCode: "제8층 · 보호 절차실 입구",
                            discoveryText: "조사를 마치자 바닥의 격리 앵커 옆에서 청백색 문양이 새겨진 두루마리가 모습을 드러낸다.",
                            presentation: .standard,
                            tutorialSequence: nil,
                            failureMechanic: nil
                        ) { grade in
                            gameSession.send(.completeScrollLearning(
                                spell: .basicBarrier,
                                grade: grade
                            ))
                            completion()
                        }
                    },
                    entranceContent: {
                        FloorEntrancePanel(
                            configuration: .floor8,
                            action: { gameSession.send(.enterProtectionRoom) }
                        )
                    }
                )
            } else if gameSession.progress.currentScene == .floor8SealedDoor,
                      !gameSession.progress.learnedSpells.contains(.sealRelease) {
                ScrollSpellLearningView(
                    spell: SpellCatalog.sealRelease,
                    sourceCode: "8-D / 관측 본실 봉인문",
                    discoveryText: "소멸한 잔류체의 핵에서 떨어진 두루마리가 금빛 해제 문양을 드러낸다. 절대 방벽과 봉인을 무효화하는 획이다.",
                    presentation: .standard,
                    tutorialSequence: nil,
                    failureMechanic: nil
                ) { grade in
                    gameSession.send(.completeScrollLearning(
                        spell: .sealRelease,
                        grade: grade
                    ))
                }
            } else if gameSession.progress.currentScene == .floor8SealedDoor {
                sealedDoor
            } else {
                ZStack {
                    LinearGradient(
                        colors: [.clear, DAColor.background.opacity(0.18), DAColor.background.opacity(0.86)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                    sceneContent
                        .frame(width: contentWidth)
                        .frame(maxHeight: .infinity)
                        .padding(24)
                        .background(DAColor.panel.opacity(0.91))
                        .overlay(alignment: .leading) {
                            Rectangle().fill(stageColor.opacity(0.65)).frame(width: 1)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                }
            }
        }
        .onAppear {
            sceneController.resetProgressionPresentation(reducedMotion: appSettings.reducedMotion)
        }
    }

    @ViewBuilder
    private var sceneContent: some View {
        switch gameSession.progress.currentScene {
        case .floor8Antechamber:
            EmptyView()
        case .floor8ProtectionRoom:
            protectionRoom
        case .floor8SealedDoor:
            EmptyView()
        default:
            EmptyView()
        }
    }

    private var protectionRoom: some View {
        let spell = SpellCatalog.basicBarrier
        return VStack(alignment: .leading, spacing: 14) {
            sceneCode("8-B / 보호 절차실")
            Text("\(spell.name) 안전 시전")
                .font(.title2.weight(.semibold))
            Text("청백색 문양을 완성하면 고정 방벽 20이 생성된다. 방벽을 넘는 피해만 HP에 적용된다.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if gameSession.progress.learnedSpells.contains(.basicBarrier) {
                GlyphCastingPanel(
                    spell: spell,
                    inputPreference: appSettings.inputPreference,
                    availableMana: 100,
                    availableStrokes: 2,
                    erasureZones: [],
                    onCast: { submission in
                        guard submission.evaluation.succeeded else { return }
                        gameSession.send(.completeProtectionTraining(
                            grade: submission.evaluation.grade
                        ))
                    }
                )
            } else {
                spellRecord(spell)
                Spacer()
                Button {
                    gameSession.send(.learnSpell(.basicBarrier))
                } label: {
                    Label("초급 방벽 익히기", systemImage: "scroll.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
            }
        }
    }

    private var sealedDoor: some View {
        let spell = SpellCatalog.sealRelease
        return GateSealInteractionView(
            title: spell.name,
            instruction: "금색 핵심점을 따라 해제 문양을 완성하십시오.",
            spell: spell,
            inputPreference: appSettings.inputPreference,
            availableMana: 100,
            availableStrokes: 2,
            presentation: GateSealGlyphPresentation()
        ) { submission in
            guard submission.evaluation.succeeded else { return }
            gameSession.send(.releaseObservationDoor)
        }
    }

    private func spellRecord(_ spell: SpellDefinition) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "shield.fill")
                .font(.system(size: 64, weight: .thin))
                .foregroundStyle(.cyan)
                .shadow(color: .cyan.opacity(0.6), radius: 14)
            Text("보호 절차 문양 자료")
                .font(.headline)
            Text("낡은 주문서 · 방어 · 1획")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .background(Color.black.opacity(0.34))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.cyan.opacity(0.28), lineWidth: 1)
        }
    }

    private var stageColor: Color {
        gameSession.progress.currentScene == .floor8SealedDoor ? .yellow : .cyan
    }

    private var hasCompletedEntranceInvestigation: Bool {
        let recordIDs = Set(InvestigationConfiguration.floor8.clues.map(\.recordID))
        return recordIDs.isSubset(of: gameSession.progress.readRecordIDs)
    }

    private var hasCompletedBarrierScrollLearning: Bool {
        gameSession.progress.learnedSpells.contains(.basicBarrier)
            && gameSession.progress.completedTrainingSpells.contains(.basicBarrier)
    }

    private var contentWidth: CGFloat {
        switch gameSession.progress.currentScene {
        case .floor8ProtectionRoom: 720
        default: 500
        }
    }

    private func sceneCode(_ text: String) -> some View {
        Text(text)
            .font(.caption.monospaced().weight(.bold))
            .foregroundStyle(.cyan)
    }
}
