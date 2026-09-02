import SwiftUI

struct DescentSealStageConfiguration {
    let recordTitle: String
    let inputTitle: String
    let sequence: [Int]
}

struct DescentSealProcedureConfiguration {
    let recordSubtitle: String
    let destination: String
    let loadingContext: LoadingScreenContext
    let stages: [DescentSealStageConfiguration]
    let accessibilityLabel: String
    let maximumAttempts: Int
    let layout: DescentSealPatternLayout

    static let floor10 = DescentSealProcedureConfiguration(
        recordSubtitle: "제10층 봉인 해제 기록",
        destination: "제9층 기록 관리 구역",
        loadingContext: .floor10,
        stages: [
            DescentSealStageConfiguration(
                recordTitle: "단일 승인 문양",
                inputTitle: "승인 기록 대조",
                sequence: [0, 3, 1, 4, 7, 6, 9, 8, 5, 2]
            )
        ],
        accessibilityLabel: "제10층 봉인 해제 정답 기록",
        maximumAttempts: 2,
        layout: .standard
    )

    static let floor9 = DescentSealProcedureConfiguration(
        recordSubtitle: "제9층 이중 봉인 검수 기록",
        destination: "제8층 관측실",
        loadingContext: .floor9,
        stages: [
            DescentSealStageConfiguration(
                recordTitle: "1단계 · 관리 서명",
                inputTitle: "1차 기록 대조",
                sequence: [0, 3, 1, 4, 7, 6, 9]
            ),
            DescentSealStageConfiguration(
                recordTitle: "2단계 · 관측 좌표",
                inputTitle: "2차 관측 좌표 검증",
                sequence: [2, 5, 8, 6, 4, 1, 3]
            )
        ],
        accessibilityLabel: "제9층 이중 봉인 해제 정답 기록",
        maximumAttempts: 2,
        layout: .standard
    )

    static let floor8 = DescentSealProcedureConfiguration(
        recordSubtitle: "제8층 이중 봉인 검수 기록",
        destination: "제7층 미확인 구역",
        loadingContext: .floor8,
        stages: [
            DescentSealStageConfiguration(
                recordTitle: "1단계 · 중심 좌표",
                inputTitle: "1차 중심 좌표 대조",
                sequence: [3, 0, 4, 6, 5, 8, 9]
            ),
            DescentSealStageConfiguration(
                recordTitle: "2단계 · 하강 경로",
                inputTitle: "2차 하강 경로 검증",
                sequence: [0, 4, 3, 1, 6, 5, 2]
            )
        ],
        accessibilityLabel: "제8층 이중 봉인 해제 정답 기록",
        maximumAttempts: 2,
        layout: .standard
    )
}

struct DescentDoorSceneView: View {
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var gameFeedback: GameFeedbackManager
    @EnvironmentObject private var gameSession: GameSessionStore

    let configuration: DescentSealProcedureConfiguration
    let sceneController: RealitySceneController
    @Binding var retryLoadingPresentation: SceneRetryLoadingPresentation?

    @State private var descentState: RealityDescentPresentationState = .ready
    @State private var transitionTask: Task<Void, Never>?
    @State private var isSealInterfaceVisible = true
    @State private var isCompletingDescent = false

    var body: some View {
        ZStack {
            Color.clear

            if isSealInterfaceVisible {
                DescentSealProcedureView(
                    configuration: configuration,
                    onStateChanged: updateDescentState,
                    onValidationFeedback: playValidationFeedback,
                    onRejected: presentSealRejection,
                    onCollapse: presentSealCollapse,
                    onRetry: retrySeal,
                    onApproved: completeDescent
                )
                .transition(.opacity)
            }
        }
        .animation(
            .easeOut(duration: RealityDescentTransitionTiming.interfaceFadeDuration),
            value: isSealInterfaceVisible
        )
        .onAppear {
            transitionTask?.cancel()
            transitionTask = nil
            isSealInterfaceVisible = true
            isCompletingDescent = false
            retryLoadingPresentation = nil
            sceneController.resetProgressionPresentation(reducedMotion: appSettings.reducedMotion)
            sceneController.resetDescentCamera()
            setDescentState(.ready)
        }
        .onChange(of: appSettings.reducedMotion) { _, reducedMotion in
            sceneController.setDescentPresentation(descentState, reducedMotion: reducedMotion)
        }
        .onDisappear {
            transitionTask?.cancel()
            transitionTask = nil
            retryLoadingPresentation = nil
            sceneController.resetDescentCamera()
        }
    }

    private func updateDescentState(_ state: DoorGlyphPresentationState) {
        switch state {
        case .ready: setDescentState(.ready)
        case .drawing: setDescentState(.drawing)
        case .failed: setDescentState(.failed)
        case .approved: setDescentState(.approved)
        }
    }

    private func playValidationFeedback(_ feedback: DescentSealValidationFeedback) {
        let cue: GameFeedbackCue
        switch feedback {
        case let .rejected(exhausted):
            cue = .descentSealRejected(exhausted: exhausted)
        case let .stageCompleted(final):
            cue = .descentSealStageCompleted(final: final)
        }
        gameFeedback.trigger(cue, settings: appSettings.settings)
    }

    private func presentSealRejection() async {
        await sceneController.playDescentSealRejectionCamera(
            reducedMotion: appSettings.reducedMotion
        )
    }

    private func presentSealCollapse() async {
        await sceneController.playDescentSealFailureCamera(
            reducedMotion: appSettings.reducedMotion
        )
    }

    private func retrySeal() async {
        gameFeedback.playInterface(.confirm, settings: appSettings.settings)
        let tip = LoadingTipCatalog.randomTip(for: configuration.loadingContext)

        withAnimation(.easeInOut(duration: appSettings.reducedMotion ? 0 : 0.18)) {
            retryLoadingPresentation = SceneRetryLoadingPresentation(
                context: configuration.loadingContext,
                progress: 0.08,
                tip: tip
            )
        }

        guard await waitForRetryStep(milliseconds: 180) else { return }
        retryLoadingPresentation?.progress = 0.34
        sceneController.resetDescentCamera()
        setDescentState(.ready)

        guard await waitForRetryStep(milliseconds: 420) else { return }
        retryLoadingPresentation?.progress = 0.82

        guard await waitForRetryStep(milliseconds: 220) else { return }
        retryLoadingPresentation?.progress = 1

        guard await waitForRetryStep(milliseconds: 180) else { return }
        withAnimation(.easeOut(duration: appSettings.reducedMotion ? 0 : 0.2)) {
            retryLoadingPresentation = nil
        }
    }

    private func waitForRetryStep(milliseconds: Int) async -> Bool {
        let duration = appSettings.reducedMotion ? min(milliseconds, 80) : milliseconds
        do {
            try await Task.sleep(for: .milliseconds(duration))
            return !Task.isCancelled
        } catch {
            return false
        }
    }

    private func completeDescent() {
        guard !isCompletingDescent else { return }
        isCompletingDescent = true
        isSealInterfaceVisible = false
        if descentState != .approved {
            setDescentState(.approved)
        }
        transitionTask?.cancel()
        transitionTask = Task { @MainActor in
            try? await Task.sleep(
                for: RealityDescentTransitionTiming.doorOpeningDelay(
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

private enum DescentSealValidationFeedback {
    case rejected(exhausted: Bool)
    case stageCompleted(final: Bool)
}

private struct DescentSealProcedureView: View {
    @EnvironmentObject private var gameSession: GameSessionStore

    let configuration: DescentSealProcedureConfiguration
    let onStateChanged: (DoorGlyphPresentationState) -> Void
    let onValidationFeedback: (DescentSealValidationFeedback) -> Void
    let onRejected: () async -> Void
    let onCollapse: () async -> Void
    let onRetry: () async -> Void
    let onApproved: () -> Void

    @State private var completedStageCount = 0
    @State private var selectedNodes: [Int] = []
    @State private var dragLocation: CGPoint?
    @State private var phase: DescentSealInputPhase = .ready
    @State private var remainingAttempts: Int
    @State private var isGameOver = false
    @State private var isSealInterfaceSuppressed = false
    @State private var isRetrying = false
    @State private var validationTask: Task<Void, Never>?
    @State private var coachStep: TutorialCoachStep?

    init(
        configuration: DescentSealProcedureConfiguration,
        onStateChanged: @escaping (DoorGlyphPresentationState) -> Void,
        onValidationFeedback: @escaping (DescentSealValidationFeedback) -> Void,
        onRejected: @escaping () async -> Void,
        onCollapse: @escaping () async -> Void,
        onRetry: @escaping () async -> Void,
        onApproved: @escaping () -> Void
    ) {
        precondition(!configuration.stages.isEmpty, "A descent seal requires at least one stage")
        self.configuration = configuration
        self.onStateChanged = onStateChanged
        self.onValidationFeedback = onValidationFeedback
        self.onRejected = onRejected
        self.onCollapse = onCollapse
        self.onRetry = onRetry
        self.onApproved = onApproved
        _remainingAttempts = State(initialValue: configuration.maximumAttempts)
    }

    var body: some View {
        ZStack {
            if !isSealInterfaceSuppressed {
                GeometryReader { proxy in
                    let sideWidth = min(max(proxy.size.width * 0.235, 250), 350)
                    let centerWidth = min(max(proxy.size.width * 0.38, 430), 590)

                    VStack(spacing: 14) {
                        Color.clear
                            .frame(height: 62)
                            .accessibilityHidden(true)

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
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isSealInterfaceSuppressed ? Color.clear : Color.black.opacity(0.18))
        .overlay {
            if isGameOver {
                sealGameOverOverlay
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.24), value: isGameOver)
        .animation(.easeOut(duration: 0.28), value: isSealInterfaceSuppressed)
        .tutorialCoach(
            step: coachStep,
            onNext: advanceCoach,
            onSkip: skipCoach
        )
        .onAppear {
            onStateChanged(.ready)
            resumeCoachIfNeeded()
        }
        .onDisappear {
            validationTask?.cancel()
            validationTask = nil
        }
        .onChange(of: gameSession.progress.tutorialProgress.requestedReplay) { _, replay in
            if replay == .floor10DescentSeal {
                resumeCoachIfNeeded()
            }
        }
    }

    private var sealGameOverOverlay: some View {
        GeometryReader { proxy in
            let panelWidth = min(720, proxy.size.width * 0.58)
            let panelHeight = panelWidth * 0.75
            let retryButtonWidth = panelWidth * 0.72
            let retryButtonHeight = panelHeight * 0.19

            ZStack {
                Color.black.opacity(0.76)
                    .ignoresSafeArea()

                ZStack {
                    Image("DescentSealFailurePanel")
                        .resizable()
                        .scaledToFit()
                        .frame(width: panelWidth, height: panelHeight)

                    Image("DescentSealFailureSeal")
                        .resizable()
                        .scaledToFit()
                        .frame(width: panelWidth * 0.37, height: panelWidth * 0.37)
                        .position(
                            x: panelWidth * 0.5,
                            y: panelHeight * 0.09
                        )
                        .shadow(color: .black.opacity(0.7), radius: 12, y: 6)

                    Image("DescentSealFailureTitle")
                        .resizable()
                        .scaledToFill()
                        .frame(width: panelWidth * 0.65, height: panelHeight * 0.13)
                        .clipped()
                        .position(
                            x: panelWidth * 0.5,
                            y: panelHeight * 0.37
                        )

                    Image("DescentSealFailureDecoration")
                        .resizable()
                        .scaledToFill()
                        .frame(width: panelWidth * 0.72, height: panelHeight * 0.07)
                        .clipped()
                        .position(
                            x: panelWidth * 0.5,
                            y: panelHeight * 0.465
                        )

                    Text("하강 절차가 일시 중단되었습니다.")
                        .font(.system(size: 18, weight: .semibold, design: .serif))
                        .foregroundStyle(DAColor.attack)
                        .position(
                            x: panelWidth * 0.5,
                            y: panelHeight * 0.515
                        )

                    Text("입력 기록을 초기화하고 현재 단계부터 다시 검수합니다.")
                        .font(.system(size: 15, weight: .medium, design: .serif))
                        .foregroundStyle(DAColor.body.opacity(0.86))
                        .position(
                            x: panelWidth * 0.5,
                            y: panelHeight * 0.59
                        )

                    Button(action: retrySeal) {
                        ZStack {
                            Image("DescentSealFailureRetryButton")
                                .resizable()
                                .scaledToFill()
                                .frame(
                                    width: retryButtonWidth,
                                    height: retryButtonHeight
                                )
                                .clipped()

                            HStack(spacing: 26) {
                                Image("DescentSealFailureRetryIcon")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 54, height: 54)
                                    .offset(x: -20)

                                Text("봉인 검수 재시도")
                                    .font(.system(size: 23, weight: .semibold, design: .serif))
                                    .foregroundStyle(DAColor.body)
                                    .offset(x: -20)
                            }
                            .frame(
                                width: retryButtonWidth,
                                height: retryButtonHeight,
                                alignment: .center
                            )
                        }
                        .frame(width: retryButtonWidth, height: retryButtonHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isRetrying)
                    .accessibilityLabel("봉인 검수 재시도")
                    .accessibilityHint("현재 봉인 검수 단계부터 다시 시작합니다")
                    .position(
                        x: panelWidth * 0.5,
                        y: panelHeight * 0.76
                    )
                }
                .frame(width: panelWidth, height: panelHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var recordPanel: some View {
        ZStack {
            Image("Floor10DescentRecordParchment")
                .resizable()
                .scaledToFit()

            GeometryReader { proxy in
                ZStack(alignment: .bottomLeading) {
                    VStack(spacing: 7) {
                        Text("해제 기록")
                            .font(.system(size: 23, weight: .semibold, design: .serif))
                        Text(configuration.recordSubtitle)
                            .font(.caption.weight(.medium))

                        if completedStageCount > 0, configuration.stages.count > 1 {
                            Label(
                                "\(completedStageCount)단계 · 대조 완료",
                                systemImage: "checkmark.circle.fill"
                            )
                            .font(.caption2.weight(.semibold))
                        }

                        recordPattern(stage: currentStageIndex)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .id(completedStageCount)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .padding(.top, proxy.size.height * 0.17)
                    .padding(.bottom, proxy.size.height * 0.15)
                    .padding(.horizontal, proxy.size.width * 0.14)

                    if let nextStageNumber {
                        Label("\(nextStageNumber)단계 · 미확인", systemImage: "circle")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(DescentSealPalette.ink.opacity(0.48))
                            .padding(.leading, proxy.size.width * 0.14)
                            .padding(.bottom, proxy.size.height * 0.12)
                            .transition(.opacity)
                    }
                }
                .foregroundStyle(DescentSealPalette.ink)
            }
        }
        .aspectRatio(CGFloat(1086) / 1448, contentMode: .fit)
        .animation(.easeInOut(duration: 0.28), value: completedStageCount)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(configuration.accessibilityLabel)
        .tutorialTarget("descent.record")
    }

    private func recordPattern(stage: Int) -> some View {
        let stageConfiguration = configuration.stages[stage]
        return VStack(spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: completedStageCount > stage ? "checkmark.seal.fill" : "seal")
                Text(stageConfiguration.recordTitle)
            }
            .font(.caption2.weight(.semibold))

            SealPatternDiagram(
                layout: configuration.layout,
                selectedNodes: stageConfiguration.sequence,
                lineColor: DescentSealPalette.ink,
                nodeColor: DescentSealPalette.ink,
                showsActiveEndpoint: false,
                highlightsStartNode: true,
                contentInsets: EdgeInsets(top: 22, leading: 4, bottom: 18, trailing: 4)
            )
            .frame(height: configuration.stages.count == 1 ? 250 : 190)
        }
    }

    private var inputPanel: some View {
        VStack(spacing: 10) {
            VStack(spacing: 3) {
                Text("봉인 문양 입력")
                    .font(.system(size: 28, weight: .semibold, design: .serif))
                    .foregroundStyle(DescentSealPalette.title)
                Text("\(currentStage.inputTitle) · 핵심점을 순서대로 연결하십시오.")
                    .font(.subheadline)
                    .foregroundStyle(DescentSealPalette.secondary)
            }

            GeometryReader { padProxy in
                SealPatternDiagram(
                    layout: configuration.layout,
                    selectedNodes: selectedNodes,
                    dragLocation: dragLocation,
                    lineColor: phase.lineColor,
                    nodeColor: phase.statusColor,
                    showsActiveEndpoint: true,
                    highlightsStartNode: false
                )
                .contentShape(Rectangle())
                .gesture(inputGesture(in: padProxy.size))
                .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(DescentSealPalette.gold.opacity(0.5), lineWidth: 1)
                }
            }
            .aspectRatio(0.78, contentMode: .fit)
            .accessibilityLabel("하강문 봉인 문양 입력판")
            .tutorialTarget("descent.input")

            if configuration.stages.count > 1 {
                HStack(spacing: 8) {
                    ForEach(configuration.stages.indices, id: \.self) { index in
                        Capsule()
                            .fill(stageColor(index))
                            .frame(width: 58, height: 4)
                    }
                }
            }

            Button(action: resetInput) {
                Label(
                    configuration.stages.count == 1 ? "입력 초기화" : "전체 입력 초기화",
                    systemImage: "arrow.counterclockwise"
                )
                .font(.headline)
                .foregroundStyle(DescentSealPalette.secondary)
                .frame(maxWidth: 270)
                .frame(height: 52)
            }
            .buttonStyle(DescentSealResetButtonStyle())
            .disabled((selectedNodes.isEmpty && completedStageCount == 0) || phase == .approved)
            .opacity(selectedNodes.isEmpty && completedStageCount == 0 ? 0.58 : 1)
            .tutorialTarget("descent.reset")
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
                        .foregroundStyle(DescentSealPalette.cyan)
                        .padding(.bottom, 18)

                    informationRow(icon: "location.north.line", title: "목적지", value: configuration.destination)
                    divider
                    if configuration.stages.count > 1 {
                        informationRow(
                            icon: "doc.text.magnifyingglass",
                            title: "검수 단계",
                            value: "\(currentStageIndex + 1) / \(configuration.stages.count)"
                        )
                        divider
                    }
                    informationRow(
                        icon: "scope",
                        title: "핵심점",
                        value: "\(selectedNodes.count) / \(currentStage.sequence.count)"
                    )
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
                .padding(.top, proxy.size.height * 0.19)
                .padding(.bottom, proxy.size.height * 0.11)
                .padding(.horizontal, proxy.size.width * 0.13)
            }
        }
        .aspectRatio(CGFloat(1122) / 1402, contentMode: .fit)
        .tutorialTarget("descent.information")
    }

    private var divider: some View {
        Rectangle()
            .fill(DescentSealPalette.cyan.opacity(0.18))
            .frame(height: 1)
            .padding(.vertical, 10)
    }

    private var currentStageIndex: Int {
        min(completedStageCount, configuration.stages.count - 1)
    }

    private var currentStage: DescentSealStageConfiguration {
        configuration.stages[currentStageIndex]
    }

    private var nextStageNumber: Int? {
        let nextIndex = completedStageCount + 1
        guard nextIndex < configuration.stages.count else { return nil }
        return nextIndex + 1
    }

    private var statusTitle: String {
        if phase == .ready, completedStageCount > 0 {
            return "\(completedStageCount)차 검수 완료"
        }
        return phase.statusTitle
    }

    private func stageColor(_ index: Int) -> Color {
        if phase == .approved || index < completedStageCount { return DescentSealPalette.magic }
        if index == completedStageCount { return phase.statusColor }
        return Color.white.opacity(0.24)
    }

    private func informationRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .frame(width: 22)
                .foregroundStyle(DescentSealPalette.cyan.opacity(0.75))
            Text(title).foregroundStyle(DescentSealPalette.secondary)
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
                guard phase != .approved,
                      phase != .failed,
                      !isGameOver,
                      !isRetrying,
                      coachStep == nil else { return }

                dragLocation = value.location
                if let node = configuration.layout.nearestNode(to: value.location, in: size),
                   !selectedNodes.contains(node) {
                    selectedNodes.append(node)
                    phase = .drawing
                    onStateChanged(.drawing)
                }
            }
            .onEnded { _ in
                dragLocation = nil
                guard !selectedNodes.isEmpty, phase != .approved, !isGameOver else { return }
                evaluateInput()
            }
    }

    private func evaluateInput() {
        guard selectedNodes == currentStage.sequence else {
            if configuration.loadingContext == .floor10 {
                gameSession.send(.recordTutorialFailure(.descentSeal))
            }
            let attemptsLeft = max(0, remainingAttempts - 1)
            phase = .failed
            remainingAttempts = attemptsLeft
            onStateChanged(.failed)
            onValidationFeedback(.rejected(exhausted: attemptsLeft == 0))
            presentRejectedInput(exhausted: attemptsLeft == 0)
            return
        }

        selectedNodes.removeAll()
        completedStageCount += 1
        let isFinalStage = completedStageCount == configuration.stages.count
        onValidationFeedback(.stageCompleted(final: isFinalStage))
        if isFinalStage {
            phase = .approved
            onStateChanged(.approved)
            onApproved()
        } else {
            phase = .ready
            onStateChanged(.ready)
        }
    }

    private func resetInput() {
        completedStageCount = 0
        selectedNodes.removeAll()
        dragLocation = nil
        phase = .ready
        onStateChanged(.ready)
    }

    private func retrySeal() {
        guard !isRetrying else { return }
        validationTask?.cancel()
        isRetrying = true
        withAnimation(.easeOut(duration: 0.16)) {
            isGameOver = false
        }
        validationTask = Task { @MainActor in
            selectedNodes.removeAll()
            dragLocation = nil
            remainingAttempts = configuration.maximumAttempts
            phase = .ready
            isSealInterfaceSuppressed = false
            onStateChanged(.ready)

            await onRetry()
            guard !Task.isCancelled else { return }
            isRetrying = false
            validationTask = nil
        }
    }

    private func presentRejectedInput(exhausted: Bool) {
        validationTask?.cancel()
        validationTask = Task { @MainActor in
            await onRejected()
            guard !Task.isCancelled else { return }
            if exhausted {
                withAnimation(.easeOut(duration: 0.28)) {
                    isSealInterfaceSuppressed = true
                }
                guard await waitForFailureStep(milliseconds: 300) else { return }
                await onCollapse()
                guard !Task.isCancelled else { return }
                withAnimation(.easeIn(duration: 0.2)) {
                    isGameOver = true
                }
            } else {
                selectedNodes.removeAll()
                dragLocation = nil
                phase = .ready
                onStateChanged(.ready)
            }
            validationTask = nil
        }
    }

    private func waitForFailureStep(milliseconds: Int) async -> Bool {
        do {
            try await Task.sleep(for: .milliseconds(milliseconds))
            return !Task.isCancelled
        } catch {
            return false
        }
    }

    private func resumeCoachIfNeeded() {
        guard configuration.loadingContext == .floor10 else { return }
        let progress = gameSession.progress.tutorialProgress
        guard progress.shouldPresent(.floor10DescentSeal) else { return }
        let step = progress.activeSequence == .floor10DescentSeal
            ? (progress.activeStep ?? .descentRecord)
            : .descentRecord
        if progress.activeSequence != .floor10DescentSeal {
            gameSession.send(.beginTutorial(sequence: .floor10DescentSeal, step: step))
        }
        coachStep = descentCoach(for: step)
    }

    private func descentCoach(for step: TutorialStepID) -> TutorialCoachStep? {
        switch step {
        case .descentRecord:
            TutorialCoachStep(
                id: step,
                title: "해제 기록",
                message: "왼쪽 기록은 봉인문이 요구하는 정답 문양입니다. 밝은 시작점에서 출발해 표시된 핵심점을 순서대로 기억하십시오.",
                targetIDs: ["descent.record"],
                placement: .bottom
            )
        case .descentInput:
            TutorialCoachStep(
                id: step,
                title: "한 붓 입력",
                message: "가운데 입력판에서 손을 떼지 않고 한 번에 경로를 연결합니다. 시작 위치와 핵심점의 순서가 모두 일치해야 승인됩니다.",
                targetIDs: ["descent.input"],
                placement: .bottom
            )
        case .descentInformation:
            TutorialCoachStep(
                id: step,
                title: "하강 정보",
                message: "목적지, 현재 연결한 핵심점 수, 남은 검수 시도를 확인할 수 있습니다. 시도가 모두 소진되면 현재 단계부터 다시 검수합니다.",
                targetIDs: ["descent.information"],
                placement: .bottom
            )
        case .descentReset:
            TutorialCoachStep(
                id: step,
                title: "입력 초기화",
                message: "경로를 잘못 시작했다면 입력 초기화로 현재 선을 지우고 다시 시작할 수 있습니다. 초기화는 실패 횟수를 차감하지 않습니다.",
                targetIDs: ["descent.reset"],
                placement: .top
            )
        default:
            nil
        }
    }

    private func advanceCoach() {
        guard let step = coachStep?.id else { return }
        let next: TutorialStepID?
        switch step {
        case .descentRecord: next = .descentInput
        case .descentInput: next = .descentInformation
        case .descentInformation: next = .descentReset
        case .descentReset: next = nil
        default: next = nil
        }
        gameSession.send(.completeTutorialStep(step: step, next: next))
        if let next {
            coachStep = descentCoach(for: next)
        } else {
            gameSession.send(.completeTutorial(.floor10DescentSeal))
            coachStep = nil
        }
    }

    private func skipCoach() {
        gameSession.send(.skipTutorial(.floor10DescentSeal))
        coachStep = nil
    }
}

struct SealPatternDiagram: View {
    let layout: DescentSealPatternLayout
    let selectedNodes: [Int]
    var dragLocation: CGPoint? = nil
    let lineColor: Color
    let nodeColor: Color
    let showsActiveEndpoint: Bool
    let highlightsStartNode: Bool
    var contentInsets: EdgeInsets = EdgeInsets()

    var body: some View {
        Canvas { context, size in
            let diagramSize = CGSize(
                width: max(1, size.width - contentInsets.leading - contentInsets.trailing),
                height: max(1, size.height - contentInsets.top - contentInsets.bottom)
            )
            context.translateBy(x: contentInsets.leading, y: contentInsets.top)

            layout.drawGuides(context: &context, size: diagramSize)
            layout.drawCenterMark(context: &context, size: diagramSize)

            if !selectedNodes.isEmpty {
                var selectedPath = Path()
                selectedPath.move(to: layout.point(selectedNodes[0], in: diagramSize))
                for node in selectedNodes.dropFirst() {
                    selectedPath.addLine(to: layout.point(node, in: diagramSize))
                }
                if let dragLocation, showsActiveEndpoint {
                    selectedPath.addLine(to: CGPoint(
                        x: dragLocation.x - contentInsets.leading,
                        y: dragLocation.y - contentInsets.top
                    ))
                }
                context.stroke(
                    selectedPath,
                    with: .color(lineColor),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                )
            }

            for index in layout.nodes.indices {
                let center = layout.point(index, in: diagramSize)
                let isSelected = selectedNodes.contains(index)
                let isStartNode = highlightsStartNode && selectedNodes.first == index
                let radius = isSelected ? 10.0 : 8.0

                if isStartNode {
                    let markerRadius = radius + 8
                    var marker = Path()
                    marker.move(to: CGPoint(x: center.x, y: center.y - markerRadius))
                    marker.addLine(to: CGPoint(x: center.x + markerRadius, y: center.y))
                    marker.addLine(to: CGPoint(x: center.x, y: center.y + markerRadius))
                    marker.addLine(to: CGPoint(x: center.x - markerRadius, y: center.y))
                    marker.closeSubpath()
                    context.fill(marker, with: .color(nodeColor.opacity(0.18)))
                    context.stroke(marker, with: .color(nodeColor.opacity(0.95)), lineWidth: 2)
                    continue
                }

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

struct DescentSealPatternLayout {
    let nodes: [CGPoint]
    let guideEdges: [(Int, Int)]
    let centerMark: CGPoint

    static let standard = DescentSealPatternLayout(
        nodes: [
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
        ],
        guideEdges: [
            (0, 3), (1, 3), (3, 2), (1, 4), (2, 5),
            (4, 5), (4, 7), (5, 8), (7, 6), (6, 8), (6, 9)
        ],
        centerMark: CGPoint(x: 0.5, y: 0.51)
    )

    func point(_ index: Int, in size: CGSize) -> CGPoint {
        let normalized = nodes[index]
        return CGPoint(x: normalized.x * size.width, y: normalized.y * size.height)
    }

    func nearestNode(to location: CGPoint, in size: CGSize) -> Int? {
        let threshold = max(32, min(size.width, size.height) * 0.09)
        return nodes.indices
            .map { ($0, distance(from: location, to: point($0, in: size))) }
            .filter { $0.1 <= threshold }
            .min { $0.1 < $1.1 }?
            .0
    }

    func drawGuides(context: inout GraphicsContext, size: CGSize) {
        var guides = Path()
        for edge in guideEdges {
            guides.move(to: point(edge.0, in: size))
            guides.addLine(to: point(edge.1, in: size))
        }
        context.stroke(guides, with: .color(.white.opacity(0.13)), lineWidth: 1)
    }

    func drawCenterMark(context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width * centerMark.x, y: size.height * centerMark.y)
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

    private func distance(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }
}

private enum DescentSealInputPhase {
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
        case .ready: DescentSealPalette.secondary
        case .drawing: DescentSealPalette.cyan
        case .failed: .red
        case .approved: DescentSealPalette.magic
        }
    }

    var lineColor: Color { self == .failed ? .red : DescentSealPalette.magic }
}

struct DescentSealResetButtonStyle: ButtonStyle {
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

enum DescentSealPalette {
    static let gold = Color(red: 184 / 255, green: 139 / 255, blue: 77 / 255)
    static let title = Color(red: 225 / 255, green: 202 / 255, blue: 164 / 255)
    static let secondary = Color(red: 210 / 255, green: 207 / 255, blue: 200 / 255)
    static let cyan = Color(red: 89 / 255, green: 204 / 255, blue: 224 / 255)
    static let magic = Color(red: 154 / 255, green: 104 / 255, blue: 246 / 255)
    static let ink = Color(red: 45 / 255, green: 34 / 255, blue: 25 / 255)
}
