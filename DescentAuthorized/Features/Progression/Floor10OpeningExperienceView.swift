import SwiftUI

struct Floor10OpeningExperienceView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var gameSession: GameSessionStore

    let sceneController: RealitySceneController
    let isSceneReady: Bool

    @State private var presentation: Presentation = .terminal
    @State private var terminalLineCount = 0
    @State private var terminalCharacterCount = 0
    @State private var terminalPower: CGFloat = 0
    @State private var terminalIsOnline = false
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
        GeometryReader { proxy in
            let monitorWidth = min(proxy.size.width, proxy.size.height * 4 / 3)
            let monitorHeight = monitorWidth * 3 / 4
            let screenWidth = monitorWidth * 0.77
            let screenHeight = monitorHeight * 0.73

            ZStack {
                Color(red: 2 / 255, green: 3 / 255, blue: 4 / 255)

                ZStack {
                    Color(red: 2 / 255, green: 10 / 255, blue: 12 / 255)

                    terminalContent
                        .padding(.horizontal, max(24, screenWidth * 0.035))
                        .padding(.vertical, max(20, screenHeight * 0.045))

                    CRTBootNoiseOverlay(isOnline: terminalIsOnline, reducedMotion: reducesMotion)
                    CRTScanlineOverlay(reducedMotion: reducesMotion)

                    Image("Floor10CRTGlassDamage")
                        .resizable()
                        .scaledToFill()
                        .frame(width: screenWidth, height: screenHeight)
                        .blendMode(.screen)
                        .opacity(0.52)
                        .allowsHitTesting(false)
                }
                .frame(width: screenWidth, height: screenHeight)
                .clipShape(RoundedRectangle(cornerRadius: monitorHeight * 0.075, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: monitorHeight * 0.075, style: .continuous)
                        .stroke(Color.cyan.opacity(terminalIsOnline ? 0.2 : 0.06), lineWidth: 1)
                }
                .scaleEffect(y: max(0.004, terminalPower), anchor: .center)
                .opacity(terminalPower > 0.01 ? 1 : 0)
                .shadow(color: .cyan.opacity(0.15 * Double(terminalPower)), radius: 28)

                if terminalPower < 0.16 {
                    Rectangle()
                        .fill(.white)
                        .frame(width: screenWidth * max(0.06, terminalPower * 5.8), height: 2.2)
                        .shadow(color: .cyan, radius: 10)
                        .opacity(terminalPower > 0 ? 0.95 : 0)
                }

                Image("Floor10CRTBezel")
                    .resizable()
                    .scaledToFit()
                    .frame(width: monitorWidth, height: monitorHeight)
                    .allowsHitTesting(false)

                skipButton
                    .padding(30)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("시스템 복구 터미널. 관리자 00을 실행합니다. 생체 반응을 확인했습니다.")
    }

    private var terminalContent: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                TerminalStatusChip(label: "DESCENT AUTH", value: "RECOVERY / 10F", tint: .cyan)
                TerminalStatusChip(label: "POWER", value: terminalIsOnline ? "AUX 43%" : "BOOT", tint: .green)
                TerminalStatusChip(label: "RIFT", value: "CRITICAL", tint: .red)
            }

            Rectangle()
                .fill(Color.cyan.opacity(0.3))
                .frame(height: 1)

            HStack(spacing: 24) {
                terminalLog
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                TerminalDiagnosticPanel(
                    progress: terminalProgress,
                    isOnline: terminalIsOnline,
                    reducedMotion: reducesMotion
                )
                .frame(width: 250)
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(terminalStatusTitle)
                        Spacer()
                        Text("\(Int(terminalProgress * 100))%")
                    }
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.cyan.opacity(0.82))

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color.cyan.opacity(0.09))
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [.cyan.opacity(0.68), .green.opacity(0.82)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geometry.size.width * terminalProgress)
                        }
                    }
                    .frame(height: 5)
                }

                TerminalSignalView(progress: terminalProgress)
                    .frame(width: 180, height: 28)
            }
        }
        .foregroundStyle(.green.opacity(0.88))
        .opacity(terminalIsOnline ? 1 : min(1, terminalPower * 3.2))
    }

    private var terminalLog: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SYSTEM LOG / LIVE")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.cyan.opacity(0.72))
                .padding(.bottom, 10)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(terminalLines.prefix(terminalLineCount).enumerated()), id: \.offset) { index, line in
                    terminalLine(line, index: index)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                if terminalLineCount < terminalLines.count {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        terminalLine(terminalCurrentLine, index: terminalLineCount)
                        Text("▋")
                            .foregroundStyle(.green.opacity(0.95))
                            .modifier(TerminalCursorBlink(reducedMotion: reducesMotion))
                    }
                }
            }
            .animation(reducesMotion ? nil : .easeOut(duration: 0.22), value: terminalLineCount)
        }
    }

    private func terminalLine(_ line: String, index: Int) -> some View {
        Text(line)
            .font(.system(size: 14, weight: .regular, design: .monospaced))
            .foregroundStyle(
                line.hasPrefix("!")
                    ? Color.red.opacity(0.94)
                    : (index.isMultiple(of: 3) ? Color.cyan.opacity(0.82) : Color.green.opacity(0.88))
            )
            .lineLimit(1)
            .minimumScaleFactor(0.78)
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
            "> auth.recovery --sector 10F --subject UNKNOWN",
            "[BOOT] 비상 전력 계통 우회 연결",
            "[SYNC] 관제 채널 00 / 응답 지연 1842ms",
            "[SCAN] 구조 손상 37% / 시야 계통 대기",
            "! 경고: 균열 억제망 임계치 초과",
            "[BIO] 생체 반응 감지 / 신원 대조 실패",
            "! 기억 식별값 손상 / 승인자 서명 조회 실패",
            "[LINK] 제10층 감시 장치 부분 복구",
            "[LOAD] 시각 정보 복원 72%",
            "[RUN] 시스템 관리자 00"
        ]
    }

    private var terminalCurrentLine: String {
        guard terminalLineCount < terminalLines.count else { return "" }
        return String(terminalLines[terminalLineCount].prefix(terminalCharacterCount))
    }

    private var terminalProgress: CGFloat {
        guard !terminalLines.isEmpty else { return 1 }
        let completed = CGFloat(terminalLineCount)
        guard terminalLineCount < terminalLines.count else { return 1 }
        let lineLength = max(terminalLines[terminalLineCount].count, 1)
        let partial = CGFloat(terminalCharacterCount) / CGFloat(lineLength)
        return min(1, (completed + partial) / CGFloat(terminalLines.count))
    }

    private var terminalStatusTitle: String {
        switch terminalProgress {
        case ..<0.22: "AUXILIARY POWER LINK"
        case ..<0.55: "FACILITY DAMAGE SCAN"
        case ..<0.82: "SUBJECT RECOVERY"
        default: "VISUAL UPLINK"
        }
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
            terminalCharacterCount = 0
            terminalPower = reducesMotion ? 1 : 0
            terminalIsOnline = reducesMotion

            if reducesMotion {
                terminalLineCount = terminalLines.count
                try? await Task.sleep(for: .milliseconds(420))
            } else {
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
                withAnimation(.easeIn(duration: 0.16)) {
                    terminalPower = 0.018
                }

                try? await Task.sleep(for: .milliseconds(240))
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                    terminalPower = 0.13
                }

                try? await Task.sleep(for: .milliseconds(260))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.62)) {
                    terminalPower = 1
                }

                try? await Task.sleep(for: .milliseconds(520))
                guard !Task.isCancelled else { return }
                terminalIsOnline = true

                for index in terminalLines.indices {
                    let line = terminalLines[index]
                    terminalCharacterCount = 0

                    for characterCount in 1...line.count {
                        guard !Task.isCancelled else { return }
                        terminalCharacterCount = characterCount
                        let delay = line.hasPrefix("!") ? 39 : 31
                        try? await Task.sleep(for: .milliseconds(delay))
                    }

                    try? await Task.sleep(
                        for: .milliseconds(line.hasPrefix("!") ? 620 : 330)
                    )
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        terminalLineCount = index + 1
                        terminalCharacterCount = 0
                    }
                }
            }

            try? await Task.sleep(for: .milliseconds(reducesMotion ? 120 : 1_150))
            guard !Task.isCancelled else { return }
            gameSession.send(.completeTutorialStep(step: .terminalBoot, next: .awaken))
            resetAwakeningVisuals()
            withAnimation(.easeInOut(duration: reducesMotion ? 0 : 0.68)) {
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
                    eyelidOpening = 0.1
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

private struct TerminalStatusChip: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(tint)
                .frame(width: 5, height: 5)
                .shadow(color: tint, radius: 4)

            Text(label)
                .foregroundStyle(.white.opacity(0.5))

            Text(value)
                .foregroundStyle(tint.opacity(0.9))
                .lineLimit(1)
        }
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
        .background(Color.black.opacity(0.38))
        .overlay {
            RoundedRectangle(cornerRadius: 2)
                .stroke(tint.opacity(0.22), lineWidth: 1)
        }
    }
}

private struct TerminalDiagnosticPanel: View {
    let progress: CGFloat
    let isOnline: Bool
    let reducedMotion: Bool

    var body: some View {
        VStack(spacing: 8) {
            TimelineView(.animation(minimumInterval: reducedMotion ? 1 : 1 / 20)) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                let rotation = reducedMotion ? 0 : time.truncatingRemainder(dividingBy: 36) * 10
                let pulse = reducedMotion ? 1 : 0.98 + (sin(time * 2.4) * 0.02)

                ZStack {
                    Image("Floor10CRTDiagnosticRing")
                        .resizable()
                        .scaledToFit()
                        .rotationEffect(.degrees(rotation))
                        .scaleEffect(pulse)
                        .opacity(isOnline ? 0.76 : 0.2)

                    Circle()
                        .stroke(Color.cyan.opacity(0.28), lineWidth: 1)
                        .frame(width: 72, height: 72)

                    VStack(spacing: 1) {
                        Text("RECOVERY")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        Text("\(Int(progress * 100))")
                            .font(.system(size: 25, weight: .light, design: .monospaced))
                    }
                    .foregroundStyle(.cyan.opacity(0.88))
                }
            }
            .frame(height: 205)

            VStack(spacing: 5) {
                DiagnosticMetric(label: "BIO SIGNAL", value: progress > 0.46 ? "DETECTED" : "SCANNING", tint: .green)
                DiagnosticMetric(label: "IDENTITY", value: progress > 0.66 ? "DAMAGED" : "PENDING", tint: progress > 0.66 ? .red : .cyan)
                DiagnosticMetric(label: "VISUAL LINK", value: progress > 0.82 ? "PARTIAL" : "OFFLINE", tint: progress > 0.82 ? .orange : .red)
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.34))
        .overlay {
            RoundedRectangle(cornerRadius: 3)
                .stroke(Color.cyan.opacity(0.16), lineWidth: 1)
        }
    }
}

private struct DiagnosticMetric: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.white.opacity(0.42))
            Spacer()
            Text(value)
                .foregroundStyle(tint.opacity(0.86))
        }
        .font(.system(size: 9, weight: .medium, design: .monospaced))
    }
}

private struct TerminalSignalView: View {
    let progress: CGFloat

    var body: some View {
        Canvas { context, size in
            var baseline = Path()
            baseline.move(to: CGPoint(x: 0, y: size.height / 2))
            baseline.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            context.stroke(baseline, with: .color(.cyan.opacity(0.12)), lineWidth: 1)

            var signal = Path()
            let sampleCount = 30
            for index in 0...sampleCount {
                let x = size.width * CGFloat(index) / CGFloat(sampleCount)
                let activity = min(1, progress * 1.25)
                let wave = sin(CGFloat(index) * 1.4) * size.height * 0.14 * activity
                let spike = index.isMultiple(of: 7) ? size.height * 0.27 * activity : 0
                let y = (size.height / 2) - wave - spike
                if index == 0 {
                    signal.move(to: CGPoint(x: x, y: y))
                } else {
                    signal.addLine(to: CGPoint(x: x, y: y))
                }
            }
            context.stroke(signal, with: .color(.green.opacity(0.72)), lineWidth: 1.2)
        }
        .overlay(alignment: .topLeading) {
            Text("BIO / LIVE")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(.green.opacity(0.48))
        }
    }
}

private struct CRTScanlineOverlay: View {
    let reducedMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: reducedMotion ? 1 : 1 / 24)) { context in
            Canvas { canvas, size in
                var lines = Path()
                var y: CGFloat = 0
                while y < size.height {
                    lines.addRect(CGRect(x: 0, y: y, width: size.width, height: 1))
                    y += 4
                }
                canvas.fill(lines, with: .color(.black.opacity(0.2)))

                guard !reducedMotion else { return }
                let elapsed = context.date.timeIntervalSinceReferenceDate
                let sweep = CGFloat(elapsed.truncatingRemainder(dividingBy: 4.8) / 4.8)
                let sweepY = (size.height + 80) * sweep - 40
                let sweepRect = CGRect(x: 0, y: sweepY, width: size.width, height: 38)
                canvas.fill(
                    Path(sweepRect),
                    with: .linearGradient(
                        Gradient(colors: [.clear, .cyan.opacity(0.045), .clear]),
                        startPoint: CGPoint(x: 0, y: sweepRect.minY),
                        endPoint: CGPoint(x: 0, y: sweepRect.maxY)
                    )
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct CRTBootNoiseOverlay: View {
    let isOnline: Bool
    let reducedMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: reducedMotion ? 1 : 1 / 14)) { context in
            let tick = Int(context.date.timeIntervalSinceReferenceDate * 14)

            GeometryReader { proxy in
                ZStack {
                    ForEach(0..<3, id: \.self) { index in
                        let rawPosition = (tick * (index + 3) * 29 + index * 71) % 100
                        Rectangle()
                            .fill(index == 1 ? Color.white.opacity(0.06) : Color.cyan.opacity(0.055))
                            .frame(height: CGFloat(1 + ((tick + index) % 3)))
                            .offset(y: proxy.size.height * CGFloat(rawPosition) / 100)
                    }

                    if !isOnline && !reducedMotion {
                        Rectangle()
                            .fill(Color.white.opacity(0.16))
                            .frame(height: 3)
                            .shadow(color: .cyan.opacity(0.5), radius: 5)
                            .offset(y: CGFloat((tick * 47) % max(Int(proxy.size.height), 1)) - proxy.size.height / 2)
                    }
                }
                .opacity(reducedMotion ? 0.18 : 1)
            }
        }
        .blendMode(.screen)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct TerminalCursorBlink: ViewModifier {
    let reducedMotion: Bool

    func body(content: Content) -> some View {
        TimelineView(.periodic(from: .now, by: reducedMotion ? 1 : 0.48)) { context in
            let visible = reducedMotion || Int(context.date.timeIntervalSinceReferenceDate * 2).isMultiple(of: 2)
            content.opacity(visible ? 1 : 0.16)
        }
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
