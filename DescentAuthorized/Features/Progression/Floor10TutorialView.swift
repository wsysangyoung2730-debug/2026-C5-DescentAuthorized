import SwiftUI

struct Floor10TutorialView: View {
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var gameSession: GameSessionStore

    @State private var descentState: RealityDescentPresentationState = .inactive
    @State private var transitionTask: Task<Void, Never>?
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
        .onDisappear { transitionTask?.cancel() }
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
        Floor10DescentSealView(
            onStateChanged: updateDescentState,
            onApproved: completeDescent
        )
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

    private func updateDescentState(_ state: DoorGlyphPresentationState) {
        switch state {
        case .ready: setDescentState(.ready)
        case .drawing: setDescentState(.drawing)
        case .failed: setDescentState(.failed)
        case .approved: setDescentState(.approved)
        }
    }

    private func completeDescent() {
        setDescentState(.approved)
        transitionTask?.cancel()
        transitionTask = Task { @MainActor in
            try? await Task.sleep(
                for: RealityDescentTransitionTiming.approvalAnimationDelay(
                    reducedMotion: appSettings.reducedMotion
                )
            )
            guard !Task.isCancelled else { return }
            setDescentState(.open)
            try? await Task.sleep(for: RealityDescentTransitionTiming.openStateHold)
            guard !Task.isCancelled else { return }
            gameSession.send(.approveDescentDoor)
        }
    }

    private func setDescentState(_ state: RealityDescentPresentationState) {
        descentState = state
        sceneController.setDescentPresentation(state, reducedMotion: appSettings.reducedMotion)
    }
}

private struct Floor10DescentSealView: View {
    let onStateChanged: (DoorGlyphPresentationState) -> Void
    let onApproved: () -> Void

    @State private var selectedNodes: [Int] = []
    @State private var dragLocation: CGPoint?
    @State private var phase: Floor10SealInputPhase = .ready
    @State private var remainingAttempts = 2

    var body: some View {
        GeometryReader { proxy in
            let sideWidth = min(max(proxy.size.width * 0.235, 250), 350)
            let centerWidth = min(max(proxy.size.width * 0.38, 430), 590)

            VStack(spacing: 14) {
                header

                HStack(alignment: .center, spacing: max(18, proxy.size.width * 0.02)) {
                    recordPanel
                        .frame(width: sideWidth)

                    inputPanel
                        .frame(width: centerWidth)

                    informationPanel
                        .frame(width: sideWidth)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, max(20, proxy.size.width * 0.035))
            .padding(.vertical, 14)
        }
        .background(Color.black.opacity(0.16))
        .onAppear { onStateChanged(.ready) }
    }

    private var header: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.black.opacity(0.76))
                .overlay {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Floor10SealPalette.gold.opacity(0.74), lineWidth: 1)
                }

            HStack {
                Label("제10층 · 절차 관리 구역", systemImage: "seal")
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("층 이동 봉인문")
                    .font(.system(size: 28, weight: .semibold, design: .serif))
                    .foregroundStyle(Floor10SealPalette.title)
                    .frame(maxWidth: .infinity)

                Text("하강 절차 02 / 03 · 문양 입력")
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Floor10SealPalette.secondary)
            .padding(.horizontal, 24)
        }
        .frame(height: 62)
    }

    private var recordPanel: some View {
        ZStack {
            Image("Floor10DescentRecordParchment")
                .resizable()
                .scaledToFit()

            GeometryReader { proxy in
                VStack(spacing: 8) {
                    Text("해제 기록")
                        .font(.system(size: 24, weight: .semibold, design: .serif))

                    Text("제10층 봉인 해제 기록")
                        .font(.caption.weight(.medium))

                    SealPatternDiagram(
                        selectedNodes: Floor10SealLayout.targetSequence,
                        lineColor: Floor10SealPalette.ink,
                        nodeColor: Floor10SealPalette.ink,
                        showsActiveEndpoint: false
                    )
                    .padding(.horizontal, proxy.size.width * 0.08)

                    Text("기록된 순서를 따라 핵심점을 연결하십시오.")
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(Floor10SealPalette.ink)
                .padding(.top, proxy.size.height * 0.12)
                .padding(.bottom, proxy.size.height * 0.13)
                .padding(.horizontal, proxy.size.width * 0.14)
            }
        }
        .aspectRatio(CGFloat(1086) / 1448, contentMode: .fit)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("제10층 봉인 해제 정답 기록")
    }

    private var inputPanel: some View {
        VStack(spacing: 10) {
            VStack(spacing: 3) {
                Text("봉인 문양 입력")
                    .font(.system(size: 28, weight: .semibold, design: .serif))
                    .foregroundStyle(Floor10SealPalette.title)

                Text("해제 기록에 표시된 순서대로 핵심점을 연결하십시오.")
                    .font(.subheadline)
                    .foregroundStyle(Floor10SealPalette.secondary)
            }

            GeometryReader { padProxy in
                SealPatternDiagram(
                    selectedNodes: selectedNodes,
                    dragLocation: dragLocation,
                    lineColor: phase.lineColor,
                    nodeColor: phase.nodeColor,
                    showsActiveEndpoint: true
                )
                .contentShape(Rectangle())
                .gesture(inputGesture(in: padProxy.size))
                .background(Color.black.opacity(0.46), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Floor10SealPalette.gold.opacity(0.46), lineWidth: 1)
                }
            }
            .aspectRatio(0.78, contentMode: .fit)
            .accessibilityLabel("하강문 봉인 문양 입력판")

            Button(action: resetInput) {
                Label("입력 초기화", systemImage: "arrow.counterclockwise")
                    .font(.headline)
                    .foregroundStyle(Floor10SealPalette.secondary)
                    .frame(maxWidth: 270)
                    .frame(height: 52)
            }
            .buttonStyle(Floor10SealResetButtonStyle())
            .disabled(selectedNodes.isEmpty || phase == .approved)
            .opacity(selectedNodes.isEmpty ? 0.58 : 1)
        }
    }

    private var informationPanel: some View {
        ZStack {
            Image("Floor10DescentInfoPanel")
                .resizable()
                .scaledToFit()

            GeometryReader { proxy in
                VStack(spacing: 0) {
                    Text("하강 정보")
                        .font(.system(size: 23, weight: .semibold, design: .serif))
                        .foregroundStyle(Floor10SealPalette.cyan)
                        .padding(.bottom, 18)

                    informationRow(icon: "location.north.line", title: "목적지", value: "제9층 기록 관리 구역")
                    divider
                    informationRow(icon: "scope", title: "입력 상태", value: "\(selectedNodes.count) / \(Floor10SealLayout.targetSequence.count)")
                    divider
                    informationRow(icon: "clock.arrow.circlepath", title: "남은 시도", value: "\(remainingAttempts)")

                    Spacer(minLength: 18)

                    VStack(spacing: 9) {
                        Image(systemName: phase.statusIcon)
                            .font(.system(size: 42, weight: .light))
                        Text(phase.statusTitle)
                            .font(.system(size: 22, weight: .medium, design: .serif))
                        HStack(spacing: 7) {
                            ForEach(0..<3, id: \.self) { index in
                                Circle()
                                    .fill(index == phase.indicatorIndex ? phase.statusColor : Color.white.opacity(0.24))
                                    .frame(width: 7, height: 7)
                            }
                        }
                    }
                    .foregroundStyle(phase.statusColor)
                }
                .padding(.top, proxy.size.height * 0.13)
                .padding(.bottom, proxy.size.height * 0.12)
                .padding(.horizontal, proxy.size.width * 0.14)
            }
        }
        .aspectRatio(CGFloat(1122) / 1402, contentMode: .fit)
    }

    private var divider: some View {
        Rectangle()
            .fill(Floor10SealPalette.cyan.opacity(0.18))
            .frame(height: 1)
            .padding(.vertical, 13)
    }

    private func informationRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .frame(width: 22)
                .foregroundStyle(Floor10SealPalette.cyan.opacity(0.75))
            Text(title)
                .foregroundStyle(Floor10SealPalette.secondary)
            Spacer(minLength: 8)
            Text(value)
                .foregroundStyle(.white.opacity(0.88))
                .multilineTextAlignment(.trailing)
        }
        .font(.caption.weight(.medium))
    }

    private func inputGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard phase != .approved else { return }
                if phase == .failed {
                    selectedNodes.removeAll()
                    phase = .ready
                    onStateChanged(.ready)
                }

                dragLocation = value.location
                if let node = Floor10SealLayout.nearestNode(to: value.location, in: size),
                   !selectedNodes.contains(node) {
                    selectedNodes.append(node)
                    phase = .drawing
                    onStateChanged(.drawing)
                }
            }
            .onEnded { _ in
                dragLocation = nil
                guard !selectedNodes.isEmpty, phase != .approved else { return }
                evaluateInput()
            }
    }

    private func evaluateInput() {
        if selectedNodes == Floor10SealLayout.targetSequence {
            phase = .approved
            onStateChanged(.approved)
            onApproved()
        } else {
            phase = .failed
            remainingAttempts = max(0, remainingAttempts - 1)
            onStateChanged(.failed)
        }
    }

    private func resetInput() {
        selectedNodes.removeAll()
        dragLocation = nil
        phase = .ready
        if remainingAttempts == 0 {
            remainingAttempts = 2
        }
        onStateChanged(.ready)
    }
}

struct SealPatternDiagram: View {
    let selectedNodes: [Int]
    var dragLocation: CGPoint? = nil
    let lineColor: Color
    let nodeColor: Color
    let showsActiveEndpoint: Bool

    var body: some View {
        Canvas { context, size in
            Floor10SealLayout.drawGuides(context: &context, size: size)
            Floor10SealLayout.drawDiamond(context: &context, size: size)

            if !selectedNodes.isEmpty {
                var selectedPath = Path()
                selectedPath.move(to: Floor10SealLayout.point(selectedNodes[0], in: size))
                for node in selectedNodes.dropFirst() {
                    selectedPath.addLine(to: Floor10SealLayout.point(node, in: size))
                }
                if let dragLocation, showsActiveEndpoint {
                    selectedPath.addLine(to: dragLocation)
                }
                context.stroke(
                    selectedPath,
                    with: .color(lineColor),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                )
            }

            for index in Floor10SealLayout.nodes.indices {
                let center = Floor10SealLayout.point(index, in: size)
                let isSelected = selectedNodes.contains(index)
                let radius = isSelected ? 10.0 : 8.0
                let outer = Path(ellipseIn: CGRect(
                    x: center.x - radius - 5,
                    y: center.y - radius - 5,
                    width: (radius + 5) * 2,
                    height: (radius + 5) * 2
                ))
                context.stroke(outer, with: .color(nodeColor.opacity(isSelected ? 0.8 : 0.32)), lineWidth: 1.5)

                let node = Path(ellipseIn: CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                ))
                context.fill(node, with: .color(isSelected ? nodeColor : Color.black.opacity(0.62)))
                context.stroke(node, with: .color(nodeColor.opacity(0.9)), lineWidth: 2)
            }
        }
    }
}

enum Floor10SealLayout {
    static let nodes: [CGPoint] = [
        CGPoint(x: 0.50, y: 0.08),
        CGPoint(x: 0.22, y: 0.25),
        CGPoint(x: 0.78, y: 0.25),
        CGPoint(x: 0.50, y: 0.33),
        CGPoint(x: 0.27, y: 0.50),
        CGPoint(x: 0.73, y: 0.50),
        CGPoint(x: 0.50, y: 0.68),
        CGPoint(x: 0.30, y: 0.82),
        CGPoint(x: 0.70, y: 0.82),
        CGPoint(x: 0.50, y: 0.94)
    ]

    static let targetSequence = [0, 3, 1, 4, 7, 6, 9, 8, 5, 2]

    private static let guideEdges: [(Int, Int)] = [
        (0, 3), (1, 3), (3, 2), (1, 4), (2, 5),
        (4, 5), (4, 7), (5, 8), (7, 6), (6, 8), (6, 9)
    ]

    static func point(_ index: Int, in size: CGSize) -> CGPoint {
        let normalized = nodes[index]
        return CGPoint(x: normalized.x * size.width, y: normalized.y * size.height)
    }

    static func nearestNode(to location: CGPoint, in size: CGSize) -> Int? {
        let threshold = max(32, min(size.width, size.height) * 0.09)
        return nodes.indices
            .map { ($0, distance(from: location, to: point($0, in: size))) }
            .filter { $0.1 <= threshold }
            .min { $0.1 < $1.1 }?
            .0
    }

    static func drawGuides(context: inout GraphicsContext, size: CGSize) {
        var guides = Path()
        for edge in guideEdges {
            guides.move(to: point(edge.0, in: size))
            guides.addLine(to: point(edge.1, in: size))
        }
        context.stroke(guides, with: .color(.white.opacity(0.13)), lineWidth: 1)
    }

    static func drawDiamond(context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.51)
        let halfWidth = size.width * 0.075
        let halfHeight = size.height * 0.065
        var diamond = Path()
        diamond.move(to: CGPoint(x: center.x, y: center.y - halfHeight))
        diamond.addLine(to: CGPoint(x: center.x + halfWidth, y: center.y))
        diamond.addLine(to: CGPoint(x: center.x, y: center.y + halfHeight))
        diamond.addLine(to: CGPoint(x: center.x - halfWidth, y: center.y))
        diamond.closeSubpath()
        context.stroke(diamond, with: .color(.white.opacity(0.28)), lineWidth: 1.5)
    }

    private static func distance(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }
}

private enum Floor10SealInputPhase {
    case ready
    case drawing
    case failed
    case approved

    var statusTitle: String {
        switch self {
        case .ready: "입력 대기"
        case .drawing: "문양 확인 중"
        case .failed: "문양 불일치"
        case .approved: "하강 승인"
        }
    }

    var statusIcon: String {
        switch self {
        case .ready: "circle.dotted"
        case .drawing: "scope"
        case .failed: "xmark.seal"
        case .approved: "checkmark.seal.fill"
        }
    }

    var statusColor: Color {
        switch self {
        case .ready: Floor10SealPalette.secondary
        case .drawing: Floor10SealPalette.cyan
        case .failed: .red
        case .approved: Floor10SealPalette.magic
        }
    }

    var lineColor: Color {
        switch self {
        case .failed: .red
        case .approved: Floor10SealPalette.magic
        default: Floor10SealPalette.magic
        }
    }

    var nodeColor: Color { statusColor }

    var indicatorIndex: Int {
        switch self {
        case .ready: 0
        case .drawing: 1
        case .failed, .approved: 2
        }
    }
}

struct Floor10SealResetButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            Image(configuration.isPressed ? "Floor10DescentResetButtonPressed" : "Floor10DescentResetButton")
                .resizable()
                .scaledToFit()
            configuration.label
        }
        .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

enum Floor10SealPalette {
    static let gold = Color(red: 184 / 255, green: 139 / 255, blue: 77 / 255)
    static let title = Color(red: 225 / 255, green: 202 / 255, blue: 164 / 255)
    static let secondary = Color(red: 210 / 255, green: 207 / 255, blue: 200 / 255)
    static let cyan = Color(red: 89 / 255, green: 204 / 255, blue: 224 / 255)
    static let magic = Color(red: 154 / 255, green: 104 / 255, blue: 246 / 255)
    static let ink = Color(red: 45 / 255, green: 34 / 255, blue: 25 / 255)
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
