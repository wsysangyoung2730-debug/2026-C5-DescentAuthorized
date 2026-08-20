import SwiftUI

struct Floor8ExplorationView: View {
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var gameSession: GameSessionStore

    var body: some View {
        ZStack {
            Color(red: 0.014, green: 0.024, blue: 0.03)
                .ignoresSafeArea()

            HStack(spacing: 0) {
                observationStage
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                sceneContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(30)
            }
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

    private var observationStage: some View {
        ZStack {
            Canvas { context, size in
                var lines = Path()
                for column in 1..<8 {
                    let x = size.width * CGFloat(column) / 8
                    lines.move(to: CGPoint(x: x, y: size.height * 0.08))
                    lines.addLine(to: CGPoint(x: x, y: size.height * 0.92))
                }
                context.stroke(lines, with: .color(.cyan.opacity(0.05)), lineWidth: 1)

                let window = CGRect(
                    x: size.width * 0.12,
                    y: size.height * 0.16,
                    width: size.width * 0.76,
                    height: size.height * 0.46
                )
                context.fill(Path(window), with: .color(.black.opacity(0.56)))
                context.stroke(Path(window), with: .color(.cyan.opacity(0.2)), lineWidth: 2)
            }

            VStack(spacing: 16) {
                Image(systemName: stageSymbol)
                    .font(.system(size: 112, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.7))
                    .shadow(color: stageColor.opacity(0.55), radius: 18)
                Text(stageTitle)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            VStack {
                Spacer()
                Text("관측창 너머의 도시는 일부 방향으로만 중력을 따른다")
                    .font(.caption)
                    .foregroundStyle(.cyan.opacity(0.58))
                    .padding(.bottom, 34)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(stageTitle)
    }

    private var stageSymbol: String {
        switch gameSession.progress.currentScene {
        case .floor8ProtectionRoom: "shield.fill"
        case .floor8SealedDoor: "lock.square.fill"
        default: "eye.circle"
        }
    }

    private var stageColor: Color {
        gameSession.progress.currentScene == .floor8SealedDoor ? .yellow : .cyan
    }

    private var stageTitle: String {
        switch gameSession.progress.currentScene {
        case .floor8ProtectionRoom: "비상 보호 절차실"
        case .floor8SealedDoor: "금색 관측 본실 봉인"
        default: "파손된 제0균열 관측창"
        }
    }

    private func sceneCode(_ text: String) -> some View {
        Text(text)
            .font(.caption.monospaced().weight(.bold))
            .foregroundStyle(.cyan)
    }
}
