import SwiftUI

struct Floor10TutorialView: View {
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var gameSession: GameSessionStore

    @State private var descentState: RealityDescentPresentationState = .inactive
    let sceneController: RealitySceneController

    var body: some View {
        Group {
            if gameSession.progress.currentScene == .floor10MeetingRoom {
                FloorEntrancePanel(
                    configuration: .floor10,
                    action: { gameSession.send(.leaveMeetingRoom) }
                )
            } else if gameSession.progress.currentScene == .floor10DescentDoor {
                descentDoorScene
            } else {
                ZStack {
                    LinearGradient(
                        colors: [.clear, DAColor.background.opacity(0.2), DAColor.background.opacity(0.82)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                    sceneContent
                        .frame(width: contentWidth)
                        .frame(maxHeight: .infinity)
                        .padding(22)
                        .background(DAColor.panel.opacity(0.9))
                        .overlay(alignment: .leading) {
                            Rectangle().fill(DAColor.magic.opacity(0.65)).frame(width: 1)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                }
            }
        }
        .onAppear { synchronizeDescentState() }
        .onChange(of: gameSession.progress.currentScene) { _, _ in synchronizeDescentState() }
        .onChange(of: appSettings.reducedMotion) { _, reducedMotion in
            sceneController.setDescentPresentation(descentState, reducedMotion: reducedMotion)
        }
    }

    @ViewBuilder
    private var sceneContent: some View {
        switch gameSession.progress.currentScene {
        case .floor10MeetingRoom:
            EmptyView()

        case .floor10Office:
            spellDiscovery(
                spell: SpellCatalog.afterglowErasure,
                code: "10-B / 폐쇄 사무실",
                body: "찢어진 비상 시전 양식의 문자가 뜻으로 읽힌다. 기억에는 없지만 손은 획의 순서를 알고 있다."
            )

        case .floor10GlyphArchive:
            spellDiscovery(
                spell: SpellCatalog.riftSeverance,
                code: "10-C / 문양 자료 구역",
                body: "훼손되지 않은 두 번째 공격 문양이 서류함 안쪽에 남아 있다. 아래층에 대비하려면 더 까다로운 서명을 익혀야 한다."
            )

        case .floor10TrainingWall:
            trainingScene

        case .floor10DescentDoor:
            EmptyView()

        default:
            EmptyView()
        }
    }

    private func spellDiscovery(
        spell: SpellDefinition,
        code: String,
        body: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sceneCode(code)
            Label("해독 가능한 주문 기록", systemImage: "doc.text.magnifyingglass")
                .font(.headline)
                .foregroundStyle(.purple)
            Text(spell.name)
                .font(.system(size: 32, weight: .semibold))
            Text(body)
                .foregroundStyle(.secondary)
                .lineSpacing(4)

            glyphPreview(spell)
                .frame(maxHeight: 260)

            Spacer()

            Button {
                gameSession.send(.learnSpell(spell.id))
            } label: {
                Label("\(spell.name) 익히기", systemImage: "scroll.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
        }
    }

    private var trainingScene: some View {
        let spell = trainingSpell
        return VStack(alignment: .leading, spacing: 14) {
            sceneCode("10-D / 시전 시험 벽면")
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("훈련 표적에 \(spell.name) 시전")
                        .font(.title2.weight(.semibold))
                    Text("가이드의 점을 순서대로 지나 문양을 완성한다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "scope")
                    .font(.title)
                    .foregroundStyle(.red)
            }

            GlyphCastingPanel(
                spell: spell,
                inputPreference: appSettings.inputPreference,
                availableMana: 100,
                availableStrokes: 2,
                erasureZones: [],
                onCast: { submission in
                    guard submission.evaluation.succeeded else { return }
                    gameSession.send(.completeTraining(
                        spell: spell.id,
                        grade: submission.evaluation.grade
                    ))
                }
            )
            .frame(maxWidth: 760)
        }
    }

    private var descentDoorScene: some View {
        VStack {
            Spacer()

            Button {
                gameSession.send(.approveDescentDoor)
            } label: {
                Label("다음 층으로 이동", systemImage: "arrow.down.circle.fill")
                    .font(.headline)
                    .frame(minWidth: 240)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(DAColor.magic)
            .padding(12)
            .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            .padding(.bottom, 44)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var trainingSpell: SpellDefinition {
        if gameSession.progress.learnedSpells.contains(.riftSeverance),
           !gameSession.progress.completedTrainingSpells.contains(.riftSeverance) {
            return SpellCatalog.riftSeverance
        }
        return SpellCatalog.afterglowErasure
    }

    private func glyphPreview(_ spell: SpellDefinition) -> some View {
        Canvas { context, size in
            for stroke in spell.glyph.strokes {
                var path = Path()
                guard let first = stroke.referencePath.first else { continue }
                path.move(to: canvasPoint(first, size: size))
                for point in stroke.referencePath.dropFirst() {
                    path.addLine(to: canvasPoint(point, size: size))
                }
                context.stroke(
                    path,
                    with: .color(.purple.opacity(0.9)),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .background(Color.black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.purple.opacity(0.25), lineWidth: 1)
        }
    }

    private func canvasPoint(_ point: NormalizedPoint, size: CGSize) -> CGPoint {
        CGPoint(
            x: size.width * point.x / 100,
            y: size.height * point.y / 100
        )
    }

    private func sceneCode(_ text: String) -> some View {
        Text(text)
            .font(.caption.monospaced().weight(.bold))
            .foregroundStyle(.purple)
    }

    private var contentWidth: CGFloat {
        switch gameSession.progress.currentScene {
        case .floor10TrainingWall: 760
        default: 500
        }
    }

    private func synchronizeDescentState() {
        sceneController.setRewardPresentation(.inactive, reducedMotion: appSettings.reducedMotion)
        setDescentState(gameSession.progress.currentScene == .floor10DescentDoor ? .ready : .inactive)
    }

    private func setDescentState(_ state: RealityDescentPresentationState) {
        descentState = state
        sceneController.setDescentPresentation(state, reducedMotion: appSettings.reducedMotion)
    }
}

struct FloorEntrancePanel: View {
    let configuration: FloorEntranceConfiguration
    let action: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let panelWidth = min(max(proxy.size.width * 0.42, 540), 680)

            ZStack(alignment: .trailing) {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: DAColor.background.opacity(0.1), location: 0.42),
                        .init(color: DAColor.background.opacity(0.78), location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .padding(.trailing, panelWidth)
                .allowsHitTesting(false)

                panel(width: panelWidth)
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func panel(width: CGFloat) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(configuration.code)
                        .font(.caption.monospaced().weight(.bold))
                        .foregroundStyle(configuration.accent)

                    Text(configuration.title)
                        .font(.system(size: 34, weight: .semibold, design: .serif))
                        .foregroundStyle(FloorEntrancePalette.title)

                    Text(configuration.summary)
                        .font(.subheadline)
                        .foregroundStyle(DAColor.secondary)
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                }

                divider.padding(.vertical, 22)

                Text("구역 상태")
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .foregroundStyle(FloorEntrancePalette.brass)

                VStack(spacing: 0) {
                    ForEach(Array(configuration.statuses.enumerated()), id: \.offset) { index, status in
                        statusRow(status)
                        if index < configuration.statuses.count - 1 {
                            Rectangle()
                                .fill(DAColor.divider.opacity(0.6))
                                .frame(height: 1)
                                .padding(.leading, 56)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .background(DAColor.card.opacity(0.48), in: RoundedRectangle(cornerRadius: 7))
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(FloorEntrancePalette.brass.opacity(0.28), lineWidth: 1)
                }
                .padding(.top, 12)

                divider.padding(.vertical, 22)

                confirmedSignal

                Spacer(minLength: 34)

                actionButton
            }
            .padding(.horizontal, 32)
            .padding(.top, 34)
            .padding(.bottom, 30)
            .frame(minHeight: 760, alignment: .top)
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .background {
            ZStack {
                Image("Floor9PanelTexture")
                    .resizable()
                    .scaledToFill()
                    .opacity(0.22)
                LinearGradient(
                    colors: [FloorEntrancePalette.panelTop.opacity(0.96), DAColor.background.opacity(0.99)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [configuration.accent.opacity(0.35), configuration.accent, FloorEntrancePalette.brass.opacity(0.4)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 2)
                .shadow(color: configuration.accent.opacity(0.7), radius: 7)
        }
        .overlay {
            Rectangle()
                .stroke(FloorEntrancePalette.brass.opacity(0.5), lineWidth: 1)
                .padding(8)
                .allowsHitTesting(false)
        }
        .clipped()
    }

    private func statusRow(_ status: FloorEntranceStatus) -> some View {
        HStack(spacing: 14) {
            Image(systemName: status.icon)
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(status.color)
                .frame(width: 34, height: 34)
                .background(status.color.opacity(0.08), in: Circle())
                .overlay { Circle().stroke(status.color.opacity(0.45), lineWidth: 1) }

            Text(status.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(status.color)

            Spacer()

            Text(status.value)
                .font(.subheadline.monospaced())
                .foregroundStyle(status.valueColor)
        }
        .padding(.vertical, 12)
    }

    private var confirmedSignal: some View {
        ZStack(alignment: .trailing) {
            Image("Floor9DocumentStamp")
                .resizable()
                .scaledToFit()
                .frame(width: 90, height: 90)
                .opacity(0.15)

            VStack(alignment: .leading, spacing: 9) {
                Text(configuration.signalTitle)
                    .font(.system(size: 17, weight: .semibold, design: .serif))
                    .foregroundStyle(FloorEntrancePalette.brass)
                Text(configuration.signalBody)
                    .font(.subheadline)
                    .foregroundStyle(DAColor.secondary)
                    .lineSpacing(4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 62)
        }
        .padding(16)
        .background(DAColor.card.opacity(0.58), in: RoundedRectangle(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(FloorEntrancePalette.brass.opacity(0.42), lineWidth: 1)
        }
    }

    private var actionButton: some View {
        Button(action: action) {
            ZStack {
                Image(configuration.buttonAsset)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 88)
                    .clipped()

                HStack(spacing: 16) {
                    Image(systemName: configuration.actionIcon)
                        .font(.system(size: 27, weight: .light))
                    Text(configuration.actionTitle)
                        .font(.system(size: 22, weight: .medium, design: .serif))
                }
                .foregroundStyle(FloorEntrancePalette.buttonText)
                .shadow(color: configuration.accent.opacity(0.5), radius: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 88, maxHeight: 88)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(configuration.actionTitle)
    }

    private var divider: some View {
        Image("Floor9SectionDivider")
            .resizable()
            .scaledToFill()
            .frame(height: 16)
            .clipped()
            .opacity(0.72)
            .accessibilityHidden(true)
    }
}

struct FloorEntranceConfiguration {
    let code: String
    let title: String
    let summary: String
    let accent: Color
    let statuses: [FloorEntranceStatus]
    let signalTitle: String
    let signalBody: String
    let buttonAsset: String
    let actionTitle: String
    let actionIcon: String

    static let floor10 = FloorEntranceConfiguration(
        code: "10-A / 폐쇄 회의실",
        title: "기억보다 먼저 깨어난 문양",
        summary: "비상등과 손등의 흔적이 서로 다른 박자로 빛난다.\n출입문은 잠겼지만 관리 단말에는 하강 봉인 절차가 남아 있다.",
        accent: Color(red: 0.88, green: 0.34, blue: 0.78),
        statuses: [
            .init(icon: "lock.fill", title: "회의실 출입문", value: "잠김", color: Color(red: 0.72, green: 0.37, blue: 0.92)),
            .init(icon: "scope", title: "하강 봉인 절차", value: "대기", color: DAColor.attack),
            .init(icon: "desktopcomputer", title: "관리 단말", value: "응답 중", color: DAColor.defense)
        ],
        signalTitle: "확인된 단서",
        signalBody: "손등의 문양이 관리 단말보다 먼저 반응했다.",
        buttonAsset: "Floor10ExitButtonPlate",
        actionTitle: "회의실을 나간다",
        actionIcon: "door.left.hand.open"
    )

    static let floor8 = FloorEntranceConfiguration(
        code: "8-A / 균열 관측실 전초",
        title: "제0균열 관측 구역",
        summary: "깨진 모니터마다 기억침식 수치가 다른 값으로 반복된다.\n관측 본실은 금색 봉인문 뒤에 있고, 보호 절차실의 비상등만 켜져 있다.",
        accent: Color(red: 0.22, green: 0.78, blue: 0.96),
        statuses: [
            .init(icon: "lock.fill", title: "본실 봉인", value: "유지", color: FloorEntrancePalette.brass),
            .init(icon: "waveform.path.ecg.rectangle", title: "관측 장비", value: "83% 손실", color: DAColor.attack),
            .init(icon: "shield.fill", title: "보호 절차", value: "사용 가능", color: DAColor.defense)
        ],
        signalTitle: "확인된 신호",
        signalBody: "보호 절차실의 비상동력이 작동 중이다.",
        buttonAsset: "Floor8ProtectionButtonPlate",
        actionTitle: "보호 절차실 진입",
        actionIcon: "shield.lefthalf.filled"
    )
}

struct FloorEntranceStatus {
    let icon: String
    let title: String
    let value: String
    let color: Color
    var valueColor: Color { color }
}

private enum FloorEntrancePalette {
    static let brass = Color(red: 184 / 255, green: 139 / 255, blue: 77 / 255)
    static let title = Color(red: 224 / 255, green: 199 / 255, blue: 158 / 255)
    static let buttonText = Color(red: 232 / 255, green: 203 / 255, blue: 146 / 255)
    static let panelTop = Color(red: 12 / 255, green: 14 / 255, blue: 17 / 255)
}
