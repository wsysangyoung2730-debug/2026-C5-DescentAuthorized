import SwiftUI

struct Floor8ExplorationView: View {
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var gameSession: GameSessionStore
    @StateObject private var sceneController = RealitySceneController()

    var body: some View {
        ZStack {
            RealityStageView(
                sceneID: gameSession.presentation.floorSceneID ?? .floor08ResidueIsolation,
                cameraPreset: gameSession.presentation.cameraPreset,
                reducedMotion: appSettings.reducedMotion,
                controller: sceneController
            )

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

    @ViewBuilder
    private var sceneContent: some View {
        switch gameSession.progress.currentScene {
        case .floor8Antechamber:
            antechamber
        case .floor8ProtectionRoom:
            protectionRoom
        case .floor8SealedDoor:
            sealedDoor
        default:
            EmptyView()
        }
    }

    private var antechamber: some View {
        VStack(alignment: .leading, spacing: 18) {
            sceneCode("8-A / 균열 관측실 전초")
            Text("제0균열 관측 구역")
                .font(.system(size: 30, weight: .semibold))
            Text("깨진 모니터마다 기억침식 수치가 다른 값으로 반복된다. 관측 본실은 금색 봉인문 뒤에 있고, 보호 절차실의 비상등만 켜져 있다.")
                .foregroundStyle(.secondary)
                .lineSpacing(4)

            VStack(alignment: .leading, spacing: 9) {
                Label("본실 봉인: 유지", systemImage: "lock.fill")
                    .foregroundStyle(.yellow)
                Label("관측 장비: 83% 손실", systemImage: "waveform.path.ecg.rectangle")
                    .foregroundStyle(.red)
                Label("보호 절차: 사용 가능", systemImage: "shield.fill")
                    .foregroundStyle(.cyan)
            }
            .font(.subheadline.monospaced())

            Spacer()

            Button {
                gameSession.send(.enterProtectionRoom)
            } label: {
                Label("보호 절차실 진입", systemImage: "shield.lefthalf.filled")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)
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
        return VStack(alignment: .leading, spacing: 14) {
            sceneCode("8-D / 관측 본실 봉인문")
            Label("잔류체 핵에서 주문 해독 완료", systemImage: "lock.open.fill")
                .font(.headline)
                .foregroundStyle(.yellow)
            Text(spell.name)
                .font(.title2.weight(.semibold))
            Text("공격으로는 열리지 않는 봉인이다. 금색 핵심점을 따라 해제 문양을 완성해 본실 잠금을 제거한다.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            GlyphCastingPanel(
                spell: spell,
                inputPreference: appSettings.inputPreference,
                availableMana: 100,
                availableStrokes: 2,
                erasureZones: [],
                onCast: { submission in
                    guard submission.evaluation.succeeded else { return }
                    gameSession.send(.releaseObservationDoor)
                }
            )
            .frame(maxWidth: 760)
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

    private var contentWidth: CGFloat {
        switch gameSession.progress.currentScene {
        case .floor8ProtectionRoom, .floor8SealedDoor: 720
        default: 500
        }
    }

    private func sceneCode(_ text: String) -> some View {
        Text(text)
            .font(.caption.monospaced().weight(.bold))
            .foregroundStyle(.cyan)
    }
}
