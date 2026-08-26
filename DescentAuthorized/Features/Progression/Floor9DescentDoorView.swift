import SwiftUI

struct Floor9DescentDoorView: View {
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var gameSession: GameSessionStore

    let sceneController: RealitySceneController
    @State private var descentState: RealityDescentPresentationState = .ready
    @State private var transitionTask: Task<Void, Never>?

    var body: some View {
        Floor9DescentSealView(
            onStateChanged: updateDescentState,
            onApproved: completeDescent
        )
        .onAppear {
            sceneController.resetProgressionPresentation(reducedMotion: appSettings.reducedMotion)
            setDescentState(.ready)
        }
        .onChange(of: appSettings.reducedMotion) { _, reducedMotion in
            sceneController.setDescentPresentation(descentState, reducedMotion: reducedMotion)
        }
        .onDisappear { transitionTask?.cancel() }
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

private struct Floor9DescentSealView: View {
    let onStateChanged: (DoorGlyphPresentationState) -> Void
    let onApproved: () -> Void

    @State private var completedStages = 0
    @State private var selectedNodes: [Int] = []
    @State private var dragLocation: CGPoint?
    @State private var phase: Floor9SealPhase = .ready
    @State private var remainingAttempts = 2

    var body: some View {
        GeometryReader { proxy in
            let sideWidth = min(max(proxy.size.width * 0.235, 250), 350)
            let centerWidth = min(max(proxy.size.width * 0.38, 430), 590)

            VStack(spacing: 14) {
                header

                HStack(alignment: .center, spacing: max(18, proxy.size.width * 0.02)) {
                    recordPanel.frame(width: sideWidth)
                    inputPanel.frame(width: centerWidth)
                    informationPanel.frame(width: sideWidth)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, max(20, proxy.size.width * 0.035))
            .padding(.vertical, 14)
        }
        .background(Color.black.opacity(0.18))
        .onAppear { onStateChanged(.ready) }
    }

    private var header: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.black.opacity(0.78))
                .overlay {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Floor10SealPalette.gold.opacity(0.74), lineWidth: 1)
                }

            HStack {
                Label("제9층 · 기록 관리 구역", systemImage: "seal")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("층 이동 봉인문")
                    .font(.system(size: 28, weight: .semibold, design: .serif))
                    .foregroundStyle(Floor10SealPalette.title)
                    .frame(maxWidth: .infinity)
                Text("하강 절차 03 / 04 · 이중 문양 검수")
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
                VStack(spacing: 5) {
                    Text("해제 기록")
                        .font(.system(size: 23, weight: .semibold, design: .serif))
                    Text("제9층 이중 봉인 검수 기록")
                        .font(.caption.weight(.medium))

                    recordPattern(stage: 0, title: "제1기록 · 관리 서명")
                    recordPattern(stage: 1, title: "제2기록 · 관측 좌표")

                    Text("두 기록을 표시된 순서대로 각각 연결하십시오.")
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(Floor10SealPalette.ink)
                .padding(.top, proxy.size.height * 0.105)
                .padding(.bottom, proxy.size.height * 0.11)
                .padding(.horizontal, proxy.size.width * 0.14)
            }
        }
        .aspectRatio(CGFloat(1086) / 1448, contentMode: .fit)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("제9층 이중 봉인 해제 정답 기록")
    }

    private func recordPattern(stage: Int, title: String) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: completedStages > stage ? "checkmark.seal.fill" : "seal")
                Text(title)
            }
            .font(.caption2.weight(.semibold))

            SealPatternDiagram(
                selectedNodes: Floor9SealPattern.targetSequences[stage],
                lineColor: Floor10SealPalette.ink,
                nodeColor: Floor10SealPalette.ink,
                showsActiveEndpoint: false
            )
            .frame(height: 112)
        }
    }

    private var inputPanel: some View {
        VStack(spacing: 10) {
            VStack(spacing: 3) {
                Text("봉인 문양 입력")
                    .font(.system(size: 28, weight: .semibold, design: .serif))
                    .foregroundStyle(Floor10SealPalette.title)
                Text("\(stageTitle) · 핵심점을 순서대로 연결하십시오.")
                    .font(.subheadline)
                    .foregroundStyle(Floor10SealPalette.secondary)
            }

            GeometryReader { padProxy in
                SealPatternDiagram(
                    selectedNodes: selectedNodes,
                    dragLocation: dragLocation,
                    lineColor: phase.lineColor,
                    nodeColor: phase.statusColor,
                    showsActiveEndpoint: true
                )
                .contentShape(Rectangle())
                .gesture(inputGesture(in: padProxy.size))
                .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Floor10SealPalette.gold.opacity(0.5), lineWidth: 1)
                }
            }
            .aspectRatio(0.78, contentMode: .fit)
            .accessibilityLabel("제9층 이중 봉인 문양 입력판")

            HStack(spacing: 8) {
                ForEach(Floor9SealPattern.targetSequences.indices, id: \.self) { index in
                    Capsule()
                        .fill(stageColor(index))
                        .frame(width: 58, height: 4)
                }
            }

            Button(action: resetInput) {
                Label("전체 입력 초기화", systemImage: "arrow.counterclockwise")
                    .font(.headline)
                    .foregroundStyle(Floor10SealPalette.secondary)
                    .frame(maxWidth: 270)
                    .frame(height: 52)
            }
            .buttonStyle(Floor10SealResetButtonStyle())
            .disabled((selectedNodes.isEmpty && completedStages == 0) || phase == .approved)
            .opacity(selectedNodes.isEmpty && completedStages == 0 ? 0.58 : 1)
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
                        .padding(.bottom, 16)

                    informationRow(icon: "location.north.line", title: "목적지", value: "제8층 관측실")
                    divider
                    informationRow(icon: "doc.text.magnifyingglass", title: "검수 단계", value: "\(displayStage) / 2")
                    divider
                    informationRow(icon: "scope", title: "핵심점", value: "\(selectedNodes.count) / \(currentSequence.count)")
                    divider
                    informationRow(icon: "clock.arrow.circlepath", title: "남은 시도", value: "\(remainingAttempts)")

                    Spacer(minLength: 12)

                    VStack(spacing: 8) {
                        Image(systemName: phase.statusIcon)
                            .font(.system(size: 38, weight: .light))
                        Text(statusTitle)
                            .font(.system(size: 20, weight: .medium, design: .serif))
                    }
                    .foregroundStyle(phase.statusColor)
                }
                .padding(.top, proxy.size.height * 0.12)
                .padding(.bottom, proxy.size.height * 0.11)
                .padding(.horizontal, proxy.size.width * 0.13)
            }
        }
        .aspectRatio(CGFloat(1122) / 1402, contentMode: .fit)
    }

    private var divider: some View {
        Rectangle()
            .fill(Floor10SealPalette.cyan.opacity(0.18))
            .frame(height: 1)
            .padding(.vertical, 10)
    }

    private var currentSequence: [Int] {
        Floor9SealPattern.targetSequences[min(completedStages, 1)]
    }

    private var displayStage: Int { min(completedStages + 1, 2) }
    private var stageTitle: String { completedStages == 0 ? "1차 기록 대조" : "2차 관측 좌표 검증" }

    private var statusTitle: String {
        if phase == .ready, completedStages == 1 { return "1차 검수 완료" }
        return phase.statusTitle
    }

    private func stageColor(_ index: Int) -> Color {
        if phase == .approved || index < completedStages { return Floor10SealPalette.magic }
        if index == completedStages { return phase.statusColor }
        return Color.white.opacity(0.24)
    }

    private func informationRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .frame(width: 22)
                .foregroundStyle(Floor10SealPalette.cyan.opacity(0.75))
            Text(title).foregroundStyle(Floor10SealPalette.secondary)
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
        guard selectedNodes == currentSequence else {
            phase = .failed
            remainingAttempts = max(0, remainingAttempts - 1)
            onStateChanged(.failed)
            return
        }

        selectedNodes.removeAll()
        completedStages += 1
        if completedStages == Floor9SealPattern.targetSequences.count {
            phase = .approved
            onStateChanged(.approved)
            onApproved()
        } else {
            phase = .ready
            onStateChanged(.ready)
        }
    }

    private func resetInput() {
        completedStages = 0
        selectedNodes.removeAll()
        dragLocation = nil
        phase = .ready
        if remainingAttempts == 0 { remainingAttempts = 2 }
        onStateChanged(.ready)
    }
}

private enum Floor9SealPattern {
    static let targetSequences = [
        [0, 3, 1, 4, 7, 6, 9],
        [2, 5, 8, 6, 4, 1, 3]
    ]
}

private enum Floor9SealPhase {
    case ready
    case drawing
    case failed
    case approved

    var statusTitle: String {
        switch self {
        case .ready: "입력 대기"
        case .drawing: "기록 대조 중"
        case .failed: "문양 불일치"
        case .approved: "하강 승인"
        }
    }

    var statusIcon: String {
        switch self {
        case .ready: "circle.dotted"
        case .drawing: "doc.text.magnifyingglass"
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

    var lineColor: Color { self == .failed ? .red : Floor10SealPalette.magic }
}
