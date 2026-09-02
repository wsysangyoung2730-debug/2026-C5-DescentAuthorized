import SwiftUI

struct Floor10OpeningExperienceView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var gameSession: GameSessionStore

    let sceneController: RealitySceneController
    let isSceneReady: Bool

    @State private var presentation: Presentation = .terminal
    @State private var terminalLineCount = 0
    @State private var openingTask: Task<Void, Never>?
    @State private var focus: Floor10OpeningCameraFocus = .rising
    @State private var showsRiseButton = false
    @State private var eyelidOpening: CGFloat = 0.015
    @State private var focusRecovery: CGFloat = 0
    @State private var showsAwakeningEffects = true
    @State private var isAwakeningSequenceRunning = false
    @State private var isRiseButtonPulsing = false
    @State private var isBeginningSurvey = false

    private var reducesMotion: Bool {
        appSettings.reducedMotion || accessibilityReduceMotion
    }

    var body: some View {
        ZStack {
            switch presentation {
            case .terminal:
                terminalView
                    .transition(.opacity)
            case .awakening:
                awakeningView
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .onAppear(perform: resume)
        .onChange(of: isSceneReady) { _, ready in
            guard ready, presentation == .awakening else { return }
            prepareAwakeningIfNeeded()
        }
        .onDisappear {
            openingTask?.cancel()
        }
    }

    private var terminalView: some View {
        ZStack {
            Color(red: 4 / 255, green: 7 / 255, blue: 8 / 255)

            LinearGradient(
                colors: [.clear, Color.cyan.opacity(0.035), .clear],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Text("DESCENT AUTHORIZATION TERMINAL")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Spacer()
                    Text("RECOVERY CONSOLE / 10F")
                        .font(.caption.monospaced())
                }
                .foregroundStyle(.cyan.opacity(0.68))

                Rectangle()
                    .fill(Color.cyan.opacity(0.24))
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 9) {
                    ForEach(Array(terminalLines.prefix(terminalLineCount).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .foregroundStyle(line.hasPrefix("!") ? Color.red.opacity(0.9) : Color.green.opacity(0.86))
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    if terminalLineCount < terminalLines.count {
                        Text("_")
                            .foregroundStyle(.green)
                            .opacity(0.8)
                    }
                }
                .font(.system(size: 17, weight: .regular, design: .monospaced))
                .lineSpacing(5)

                Spacer()

                HStack {
                    Text("관리자 00을 실행합니다")
                        .font(.system(size: 23, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer()
                    ProgressView()
                        .tint(.green)
                }
            }
            .padding(.horizontal, 72)
            .padding(.vertical, 56)

            skipButton
                .padding(30)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("시스템 복구 터미널. 관리자 00을 실행합니다. 생체 반응을 확인했습니다.")
    }

    private var awakeningView: some View {
        ZStack {
            if !isSceneReady {
                Color.black
                ProgressView("제10층 시야를 복구하는 중")
                    .tint(.purple)
                    .foregroundStyle(.white.opacity(0.8))
            } else {
                LinearGradient(
                    colors: [Color.black.opacity(0.74), .clear, Color.black.opacity(0.44)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                if showsAwakeningEffects {
                    AwakeningFocusRecoveryOverlay(recovery: focusRecovery)
                        .transition(.opacity)

                    AwakeningEyelidOverlay(opening: eyelidOpening)
                        .transition(.opacity)
                }

                if showsRiseButton {
                    riseButton
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                } else if focus != .rising {
                    focusCaption
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 58)
                        .transition(.opacity)
                }

                skipButton
                    .padding(30)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
    }

    private var riseButton: some View {
        Button(action: beginSurvey) {
            ZStack {
                Image("Floor10RiseButtonPlate")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 420, height: 92)
                    .clipped()
                    .accessibilityHidden(true)

                Text("몸 일으키기")
                    .font(.system(size: 22, weight: .medium, design: .serif))
                    .tracking(0.8)
                    .foregroundStyle(Color(red: 0.94, green: 0.91, blue: 0.86))
                    .shadow(color: .black.opacity(0.9), radius: 2, y: 1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 420, height: 92)
            .contentShape(Rectangle())
        }
        .buttonStyle(Floor10RiseButtonStyle(reducedMotion: reducesMotion))
        .scaleEffect(isRiseButtonPulsing ? 1.012 : 1)
        .shadow(
            color: Color.purple.opacity(isRiseButtonPulsing ? 0.6 : 0.28),
            radius: isRiseButtonPulsing ? 18 : 9
        )
        .disabled(isBeginningSurvey)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 54)
        .onAppear(perform: startRiseButtonPulse)
        .onDisappear {
            isRiseButtonPulsing = false
        }
        .accessibilityLabel("몸 일으키기")
        .accessibilityHint("선택하면 몸을 일으킨 뒤 방 안을 자동으로 둘러봅니다")
    }

    private var focusCaption: some View {
        Text(focus.caption)
            .font(.system(size: 17, weight: .medium, design: .serif))
            .foregroundStyle(.white.opacity(0.88))
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(.black.opacity(0.68), in: Capsule())
            .id(focus.caption)
    }

    private var skipButton: some View {
        Button("인트로 건너뛰기", action: skip)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.72))
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(.black.opacity(0.58), in: Capsule())
            .overlay {
                Capsule().stroke(.white.opacity(0.16), lineWidth: 1)
            }
    }

    private var terminalLines: [String] {
        [
            "> descent.recovery --floor 10 --subject unknown",
            "[OK] 비상 전원 연결",
            "[OK] 생체 반응 확인",
            "! 기억 식별값 손상 / 승인자 서명 조회 실패",
            "[WAIT] 시각 정보 복구",
            "[RUN] 시스템 관리자 00"
        ]
    }

    private func resume() {
        let progress = gameSession.progress.tutorialProgress
        guard progress.shouldPresent(.floor10Intro) else { return }

        let step = progress.activeSequence == .floor10Intro
            ? (progress.activeStep ?? .terminalBoot)
            : .terminalBoot
        if progress.activeSequence != .floor10Intro {
            gameSession.send(.beginTutorial(sequence: .floor10Intro, step: step))
        }

        if step == .terminalBoot {
            resetAwakeningVisuals()
            presentation = .terminal
            runTerminal()
        } else {
            presentation = .awakening
            showsRiseButton = step == .rise
            if step == .awaken {
                resetAwakeningVisuals()
            } else if step == .rise {
                presentFullyAwake()
            } else {
                showsAwakeningEffects = false
            }
            prepareAwakeningIfNeeded()
        }
    }

    private func runTerminal() {
        openingTask?.cancel()
        openingTask = Task { @MainActor in
            terminalLineCount = 0
            for index in terminalLines.indices {
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: reducesMotion ? 0 : 0.16)) {
                    terminalLineCount = index + 1
                }
                try? await Task.sleep(for: .milliseconds(reducesMotion ? 30 : 430))
            }
            try? await Task.sleep(for: .milliseconds(reducesMotion ? 50 : 850))
            guard !Task.isCancelled else { return }
            gameSession.send(.completeTutorialStep(step: .terminalBoot, next: .awaken))
            resetAwakeningVisuals()
            withAnimation(.easeInOut(duration: reducesMotion ? 0 : 0.48)) {
                presentation = .awakening
            }
            prepareAwakeningIfNeeded()
        }
    }

    private func prepareAwakeningIfNeeded() {
        guard isSceneReady else { return }
        if let step = gameSession.progress.tutorialProgress.activeStep,
           [.surveyTarget, .surveyDesk, .surveyDamage, .surveyDoor].contains(step) {
            showsAwakeningEffects = false
            showsRiseButton = false
            startSurveyCamera()
            return
        }
        sceneController.prepareFloor10FallenCamera(reducedMotion: reducesMotion)

        if gameSession.progress.tutorialProgress.activeStep == .rise {
            presentFullyAwake()
            return
        }

        guard gameSession.progress.tutorialProgress.activeStep == .awaken,
              !isAwakeningSequenceRunning else { return }

        openingTask?.cancel()
        isAwakeningSequenceRunning = true
        openingTask = Task { @MainActor in
            if reducesMotion {
                presentFullyAwake()
                try? await Task.sleep(for: .milliseconds(80))
            } else {
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.45)) {
                    eyelidOpening = 0.1
                    focusRecovery = 0.06
                }

                try? await Task.sleep(for: .milliseconds(650))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.78)) {
                    eyelidOpening = 0.62
                    focusRecovery = 0.46
                }

                try? await Task.sleep(for: .milliseconds(960))
                guard !Task.isCancelled else { return }
                withAnimation(.easeIn(duration: 0.14)) {
                    eyelidOpening = 0.44
                    focusRecovery = 0.34
                }

                try? await Task.sleep(for: .milliseconds(160))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.68)) {
                    eyelidOpening = 0.94
                    focusRecovery = 1
                }

                try? await Task.sleep(for: .milliseconds(760))
            }

            guard !Task.isCancelled else { return }
            guard gameSession.progress.tutorialProgress.activeStep == .awaken else { return }
            gameSession.send(.completeTutorialStep(step: .awaken, next: .rise))
            withAnimation(
                reducesMotion
                    ? .linear(duration: 0)
                    : .spring(response: 0.42, dampingFraction: 0.84)
            ) {
                showsRiseButton = true
            }
            isAwakeningSequenceRunning = false
        }
    }

    private func beginSurvey() {
        guard !isBeginningSurvey else { return }
        isBeginningSurvey = true
        openingTask?.cancel()
        isAwakeningSequenceRunning = false
        withAnimation(.easeOut(duration: reducesMotion ? 0 : 0.28)) {
            showsRiseButton = false
            showsAwakeningEffects = false
            eyelidOpening = 1
            focusRecovery = 1
        }
        gameSession.send(.completeTutorialStep(step: .rise, next: .surveyTarget))
        startSurveyCamera()
    }

    private func startSurveyCamera() {
        openingTask?.cancel()
        openingTask = Task { @MainActor in
            await sceneController.playFloor10OpeningCamera(
                reducedMotion: reducesMotion
            ) { newFocus in
                withAnimation(.easeOut(duration: reducesMotion ? 0 : 0.18)) {
                    focus = newFocus
                }
                persist(newFocus)
            }
        }
    }

    private func persist(_ newFocus: Floor10OpeningCameraFocus) {
        switch newFocus {
        case .trainingTarget:
            completeIfNeeded(.surveyTarget, next: .surveyDesk)
        case .surroundingDesk(2):
            completeIfNeeded(.surveyDesk, next: .surveyDamage)
        case .damagedRoom:
            completeIfNeeded(.surveyDamage, next: .surveyDoor)
        case .lockedDoor:
            completeIfNeeded(.surveyDoor, next: nil)
        case .settled:
            gameSession.send(.completeTutorial(.floor10Intro))
        default:
            break
        }
    }

    private func completeIfNeeded(_ step: TutorialStepID, next: TutorialStepID?) {
        guard !gameSession.progress.tutorialProgress.completedSteps.contains(step) else { return }
        gameSession.send(.completeTutorialStep(step: step, next: next))
    }

    private func skip() {
        openingTask?.cancel()
        sceneController.restoreFloor10OpeningCamera()
        gameSession.send(.skipTutorial(.floor10Intro))
    }

    private func resetAwakeningVisuals() {
        eyelidOpening = 0.015
        focusRecovery = 0
        showsAwakeningEffects = true
        showsRiseButton = false
        isAwakeningSequenceRunning = false
        isRiseButtonPulsing = false
        isBeginningSurvey = false
    }

    private func presentFullyAwake() {
        eyelidOpening = 0.94
        focusRecovery = 1
        showsAwakeningEffects = true
    }

    private func startRiseButtonPulse() {
        guard !reducesMotion else {
            isRiseButtonPulsing = false
            return
        }
        isRiseButtonPulsing = false
        withAnimation(.easeInOut(duration: 1.35).repeatForever(autoreverses: true)) {
            isRiseButtonPulsing = true
        }
    }

    private enum Presentation {
        case terminal
        case awakening
    }
}

private struct AwakeningFocusRecoveryOverlay: View {
    let recovery: CGFloat

    private var unresolved: Double {
        Double(1 - min(max(recovery, 0), 1))
    }

    var body: some View {
        GeometryReader { proxy in
            let shortestEdge = min(proxy.size.width, proxy.size.height)

            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(unresolved * 0.42)

                LinearGradient(
                    colors: [
                        Color.cyan.opacity(unresolved * 0.12),
                        .clear,
                        Color.purple.opacity(unresolved * 0.14)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .blendMode(.screen)

                RadialGradient(
                    colors: [
                        .clear,
                        Color.black.opacity(0.5 + (unresolved * 0.34))
                    ],
                    center: .center,
                    startRadius: shortestEdge * 0.2,
                    endRadius: max(proxy.size.width, proxy.size.height) * 0.67
                )

                RadialGradient(
                    colors: [
                        Color.purple.opacity(0.1 + (unresolved * 0.11)),
                        .clear
                    ],
                    center: UnitPoint(x: 0.78, y: 0.52),
                    startRadius: 0,
                    endRadius: shortestEdge * 0.55
                )
                .blendMode(.screen)
            }
        }
        .environment(\.colorScheme, .dark)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct AwakeningEyelidOverlay: View {
    let opening: CGFloat

    var body: some View {
        ZStack {
            AwakeningEyelidShape(opening: opening)
                .fill(Color.black.opacity(0.96))
                .blur(radius: 11)

            AwakeningEyelidShape(opening: opening)
                .fill(Color.black)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct AwakeningEyelidShape: Shape {
    var opening: CGFloat

    var animatableData: CGFloat {
        get { opening }
        set { opening = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let progress = min(max(opening, 0), 1)
        let centerY = rect.height * 0.515
        let centerHalfOpening = max(1.5, rect.height * 0.49 * progress)
        let sideHalfOpening = centerHalfOpening * (0.7 + (progress * 0.06))
        let upperCenter = centerY - centerHalfOpening
        let lowerCenter = centerY + centerHalfOpening
        let upperLeading = centerY - (sideHalfOpening * 0.94)
        let upperTrailing = centerY - sideHalfOpening
        let lowerLeading = centerY + sideHalfOpening
        let lowerTrailing = centerY + (sideHalfOpening * 0.93)

        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: upperTrailing))
        path.addCurve(
            to: CGPoint(x: rect.midX, y: upperCenter),
            control1: CGPoint(x: rect.width * 0.82, y: upperTrailing),
            control2: CGPoint(x: rect.width * 0.67, y: upperCenter - (rect.height * 0.008))
        )
        path.addCurve(
            to: CGPoint(x: rect.minX, y: upperLeading),
            control1: CGPoint(x: rect.width * 0.31, y: upperCenter + (rect.height * 0.006)),
            control2: CGPoint(x: rect.width * 0.14, y: upperLeading)
        )
        path.closeSubpath()

        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: lowerTrailing))
        path.addCurve(
            to: CGPoint(x: rect.midX, y: lowerCenter),
            control1: CGPoint(x: rect.width * 0.84, y: lowerTrailing),
            control2: CGPoint(x: rect.width * 0.68, y: lowerCenter + (rect.height * 0.008))
        )
        path.addCurve(
            to: CGPoint(x: rect.minX, y: lowerLeading),
            control1: CGPoint(x: rect.width * 0.32, y: lowerCenter - (rect.height * 0.004)),
            control2: CGPoint(x: rect.width * 0.15, y: lowerLeading)
        )
        path.closeSubpath()

        return path
    }
}

private struct Floor10RiseButtonStyle: ButtonStyle {
    let reducedMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reducedMotion ? 0.975 : 1)
            .brightness(configuration.isPressed ? -0.07 : 0)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(
                reducedMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}

private extension Floor10OpeningCameraFocus {
    var caption: String {
        switch self {
        case .rising:
            "몸을 일으킨다. 시야가 천천히 제자리로 돌아온다."
        case .trainingTarget:
            "금이 간 훈련 표적이 아직 작동하고 있다."
        case .surroundingDesk(1):
            "뒤집힌 책상과 흩어진 기록들."
        case .surroundingDesk:
            "주변 어디에도 사람의 기척은 없다."
        case .damagedRoom:
            "바닥과 벽에는 알 수 없는 충격의 흔적이 남아 있다."
        case .lockedDoor:
            "하강문은 봉인된 채 반응하지 않는다."
        case .settled:
            "제10층 · 승인 관리 구역"
        }
    }
}
