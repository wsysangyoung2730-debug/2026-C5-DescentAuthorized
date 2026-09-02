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
            let screenWidth = monitorWidth * 0.955
            let screenHeight = monitorHeight * 0.92
            let screenCornerRadius = monitorHeight * 0.058

            ZStack {
                Color(red: 2 / 255, green: 3 / 255, blue: 4 / 255)

                ZStack {
                    Color(red: 2 / 255, green: 10 / 255, blue: 12 / 255)

                    terminalContent
                        .padding(.horizontal, max(22, screenWidth * 0.028))
                        .padding(.vertical, max(20, screenHeight * 0.027))

                    CRTBootNoiseOverlay(isOnline: terminalIsOnline, reducedMotion: reducesMotion)
                    CRTScanlineOverlay(reducedMotion: reducesMotion)
                    CRTInterferenceSweepOverlay(reducedMotion: reducesMotion)

                    Image("Floor10CRTGlassDamage")
                        .resizable()
                        .scaledToFill()
                        .frame(width: screenWidth, height: screenHeight)
                        .blendMode(.screen)
                        .opacity(0.52)
                        .allowsHitTesting(false)

                    CRTCurvatureOverlay()

                    CRTPowerRevealOverlay(reveal: terminalPower)
                }
                .frame(width: screenWidth, height: screenHeight)
                .clipShape(RoundedRectangle(cornerRadius: screenCornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: screenCornerRadius, style: .continuous)
                        .stroke(Color.cyan.opacity(terminalIsOnline ? 0.2 : 0.06), lineWidth: 1.2)
                }
                .shadow(color: .cyan.opacity(0.15 * Double(terminalPower)), radius: 28)

                if terminalPower < 0.16 {
                    Rectangle()
                        .fill(.white)
                        .frame(width: screenWidth * max(0.06, terminalPower * 5.8), height: 2.2)
                        .shadow(color: .cyan, radius: 10)
                        .opacity(terminalPower > 0 ? 0.95 : 0)
                }

                RoundedRectangle(cornerRadius: screenCornerRadius + 10, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(red: 0.2, green: 0.16, blue: 0.11),
                                .black,
                                Color(red: 0.13, green: 0.1, blue: 0.07)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 13
                    )
                    .frame(width: screenWidth + 15, height: screenHeight + 15)
                    .shadow(color: .black.opacity(0.9), radius: 20)
                    .allowsHitTesting(false)

            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("시스템 복구 터미널. 관리자 00을 실행합니다. 생체 반응을 확인했습니다.")
    }

    private var terminalContent: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                TerminalHeaderBar(isOnline: terminalIsOnline)
                skipButton
                    .frame(width: 108)
            }
            .frame(height: 38)

            HStack(spacing: 12) {
                TerminalPanel(title: ">_ SYSTEM LOG") {
                    terminalLog
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                TerminalRecoveryDashboard(
                    progress: terminalProgress,
                    isOnline: terminalIsOnline,
                    reducedMotion: reducesMotion
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            TerminalRecoveryFooter(progress: terminalProgress, status: terminalStatusTitle)
                .frame(height: 82)
        }
        .foregroundStyle(.green.opacity(0.88))
        .opacity(terminalIsOnline ? 1 : min(1, terminalPower * 3.2))
    }

    private var terminalLog: some View {
        GeometryReader { proxy in
            let rowHeight = max(20, proxy.size.height / CGFloat(terminalLines.count + 1))

            VStack(alignment: .leading, spacing: 0) {
                ForEach(terminalLines.indices, id: \.self) { index in
                    Group {
                        if index < terminalLineCount {
                            terminalLine(terminalLines[index], index: index)
                        } else if index == terminalLineCount {
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                terminalLine(terminalCurrentLine, index: index)
                                Text("▋")
                                    .foregroundStyle(.green.opacity(0.95))
                                    .modifier(TerminalCursorBlink(reducedMotion: reducesMotion))
                            }
                        } else {
                            Color.clear
                        }
                    }
                    .frame(height: rowHeight, alignment: .leading)
                }

                Spacer(minLength: 0)
            }
        }
    }

    private func terminalLine(_ line: String, index: Int) -> some View {
        Text(line)
            .font(.system(size: 12.5, weight: .regular, design: .monospaced))
            .foregroundStyle(
                line.contains("[CRIT]")
                    ? Color.red.opacity(0.94)
                    : (line.contains("[WARN]") || line.contains("[RUN]"))
                        ? Color.orange.opacity(0.92)
                        : (index.isMultiple(of: 4) ? Color.cyan.opacity(0.84) : Color.green.opacity(0.88))
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
            "[23:46:41] 관리자 00을 실행합니다 ................ [OK]",
            "[23:46:41] [OK] 비상 전원 연결",
            "[23:46:42] [OK] 생체 반응 확인",
            "[23:46:43] [WARN] 기억 식별값 손상",
            "[23:46:44] 코어 격리 프로토콜 초기화 ............ [OK]",
            "[23:46:45] 심층 기억 영역 스캔 시작 ............. [10%]",
            "[23:46:46] 손상 패턴 분석 중 .................... [23%]",
            "[23:46:47] 외부 관제 채널 연결 .................. [10%]",
            "[23:46:48] 승인자 서명 조회 실패 ................ [WARN]",
            "[23:46:49] 봉인 해제 검증 루틴 .................. [OK]",
            "[23:46:51] 데이터 재구성 버퍼 할당 .............. [OK]",
            "[23:46:52] 시각 정보 복구 개시 .................. [RUN]",
            "    └ 기억 단편 정렬 중 ...................... [31%]",
            "    └ 지각 벡터 매핑 중 ...................... [17%]",
            "    └ 이미지 데이터 복원 대기열 생성 ......... [08%]",
            "[23:46:55] 오류 복구 시도 : 2 / 7 .............. [WARN]",
            "[23:46:56] 이계 간섭 감지 ...................... [WARN]",
            "[23:46:57] 보호막 출력 저하 : 12% .............. [CRIT]",
            "[23:46:59] 복구 우선순위 재조정 ................ [OK]"
        ]
    }

    private var initiallyVisibleTerminalLineCount: Int {
        max(terminalLines.count - 3, 0)
    }

    private var terminalCurrentLine: String {
        guard terminalLineCount < terminalLines.count else { return "" }
        return String(terminalLines[terminalLineCount].prefix(terminalCharacterCount))
    }

    private var terminalProgress: CGFloat {
        guard !terminalLines.isEmpty else { return 1 }
        guard terminalLineCount < terminalLines.count else { return 1 }

        let dynamicLineCount = max(terminalLines.count - initiallyVisibleTerminalLineCount, 1)
        let completed = CGFloat(max(terminalLineCount - initiallyVisibleTerminalLineCount, 0))
        let lineLength = max(terminalLines[terminalLineCount].count, 1)
        let partial = CGFloat(terminalCharacterCount) / CGFloat(lineLength)
        let dynamicProgress = min(1, (completed + partial) / CGFloat(dynamicLineCount))
        return 0.31 + (dynamicProgress * 0.69)
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
            terminalLineCount = reducesMotion
                ? terminalLines.count
                : initiallyVisibleTerminalLineCount
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
                withAnimation(.easeOut(duration: 0.18)) {
                    terminalPower = 0.13
                }

                try? await Task.sleep(for: .milliseconds(260))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.52)) {
                    terminalPower = 1
                }

                try? await Task.sleep(for: .milliseconds(520))
                guard !Task.isCancelled else { return }
                terminalIsOnline = true

                for index in terminalLines.indices.dropFirst(initiallyVisibleTerminalLineCount) {
                    let line = terminalLines[index]
                    terminalCharacterCount = 0

                    for characterCount in 1...line.count {
                        guard !Task.isCancelled else { return }
                        terminalCharacterCount = characterCount
                        let delay = line.contains("[WARN]") || line.contains("[CRIT]") ? 36 : 28
                        try? await Task.sleep(for: .milliseconds(delay))
                    }

                    try? await Task.sleep(
                        for: .milliseconds(
                            line.contains("[WARN]") || line.contains("[CRIT]") ? 600 : 360
                        )
                    )
                    guard !Task.isCancelled else { return }
                    terminalLineCount = index + 1
                    terminalCharacterCount = 0
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

private struct TerminalHeaderBar: View {
    let isOnline: Bool

    var body: some View {
        HStack(spacing: 18) {
            Text("DESCENT AUTHORIZATION TERMINAL")
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("RECOVERY CONSOLE / 10F")
                .frame(maxWidth: .infinity)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 12) {
                    Text("SYS 10F-ARK")
                    Text(context.date, format: .dateTime.hour().minute().second())
                    HStack(spacing: 2) {
                        Text("SIGNAL")
                        ForEach(0..<7, id: \.self) { index in
                            Rectangle()
                                .fill(index < (isOnline ? 5 : 1) ? Color.cyan.opacity(0.8) : Color.cyan.opacity(0.12))
                                .frame(width: 4, height: 9)
                                .rotationEffect(.degrees(12))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .foregroundStyle(.cyan.opacity(0.78))
        .padding(.horizontal, 14)
        .background(Color.black.opacity(0.3))
        .overlay {
            Rectangle().stroke(Color.cyan.opacity(0.26), lineWidth: 1)
        }
    }
}

private struct TerminalPanel<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Text(title)
                Spacer()
                Text("⊞")
                    .opacity(0.7)
            }
            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(.cyan.opacity(0.78))

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(10)
        .background(Color.black.opacity(0.24))
        .overlay {
            Rectangle().stroke(Color.cyan.opacity(0.28), lineWidth: 1)
        }
    }
}

private struct TerminalRecoveryDashboard: View {
    let progress: CGFloat
    let isOnline: Bool
    let reducedMotion: Bool

    var body: some View {
        VStack(spacing: 9) {
            TerminalPanel(title: "CORE RECOVERY DIAGNOSTIC") {
                HStack(spacing: 18) {
                    TimelineView(.animation(minimumInterval: reducedMotion ? 1 : 1 / 20)) { context in
                        let time = context.date.timeIntervalSinceReferenceDate
                        let rotation = reducedMotion ? 0 : time.truncatingRemainder(dividingBy: 36) * 10
                        let pulse = reducedMotion ? 1 : 0.985 + (sin(time * 2.4) * 0.015)

                        ZStack {
                            Image("Floor10CRTDiagnosticRing")
                                .resizable()
                                .scaledToFit()
                                .rotationEffect(.degrees(rotation))
                                .scaleEffect(pulse)
                                .opacity(isOnline ? 0.72 : 0.18)

                            VStack(spacing: 0) {
                                Text("RECOVERY RATE")
                                    .font(.system(size: 7, weight: .medium, design: .monospaced))
                                HStack(alignment: .firstTextBaseline, spacing: 1) {
                                    Text("\(Int(progress * 100))")
                                        .font(.system(size: 27, weight: .light, design: .monospaced))
                                    Text("%")
                                        .font(.system(size: 11, design: .monospaced))
                                }
                            }
                            .foregroundStyle(.cyan.opacity(0.9))
                        }
                    }
                    .frame(width: 165)

                    VStack(spacing: 9) {
                        TerminalMetricBar(label: "SIGNAL STRENGTH", value: min(1, progress * 1.45))
                        TerminalMetricBar(label: "CORE STABILITY", value: min(1, progress * 1.12))
                        TerminalMetricBar(label: "MEMORY INTEGRITY", value: progress * 0.62, tint: .orange)
                        TerminalMetricBar(label: "OCCULT COHERENCE", value: min(1, progress * 1.3))
                        TerminalMetricBar(label: "VISUAL RECOVERY", value: progress)
                    }
                }
            }
            .frame(height: 205)

            HStack(spacing: 9) {
                TerminalPanel(title: "BIOMETRIC RESPONSE") {
                    VStack(spacing: 5) {
                        TerminalSignalView(progress: progress)
                        HStack {
                            Text("HR \(72 + Int(progress * 15))")
                            Spacer()
                            Text("BR \(12 + Int(progress * 7))")
                            Spacer()
                            Text(isOnline ? "LIVE" : "WAIT")
                                .foregroundStyle(isOnline ? .green.opacity(0.9) : .orange.opacity(0.9))
                        }
                        .font(.system(size: 9, design: .monospaced))
                    }
                }

                TerminalPanel(title: "FLOOR-10 SCHEMATIC") {
                    TerminalFloorSchematic(progress: progress)
                }
            }
            .frame(height: 137)

            HStack(spacing: 9) {
                TerminalPanel(title: "MEMORY INTEGRITY") {
                    TerminalMemoryGrid(progress: progress)
                }

                TerminalPanel(title: "RECOVERY STACK") {
                    TerminalRecoveryStack(progress: progress)
                }
            }
        }
    }
}

private struct TerminalMetricBar: View {
    let label: String
    let value: CGFloat
    var tint: Color = .cyan

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .stroke(tint.opacity(0.65), lineWidth: 1)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.cyan.opacity(0.72))
                .frame(width: 92, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.cyan.opacity(0.07))
                    Rectangle()
                        .fill(tint.opacity(0.75))
                        .frame(width: proxy.size.width * min(max(value, 0), 1))
                }
            }
            .frame(height: 5)
        }
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
    }
}

private struct TerminalFloorSchematic: View {
    let progress: CGFloat

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let shortest = min(size.width, size.height)

            for inset in [0.08, 0.2, 0.32] as [CGFloat] {
                let rect = CGRect(
                    x: size.width * inset,
                    y: size.height * inset,
                    width: size.width * (1 - inset * 2),
                    height: size.height * (1 - inset * 2)
                )
                context.stroke(Path(rect), with: .color(.cyan.opacity(0.22)), lineWidth: 1)
            }

            var crosshair = Path()
            crosshair.move(to: CGPoint(x: center.x, y: 0))
            crosshair.addLine(to: CGPoint(x: center.x, y: size.height))
            crosshair.move(to: CGPoint(x: 0, y: center.y))
            crosshair.addLine(to: CGPoint(x: size.width, y: center.y))
            context.stroke(crosshair, with: .color(.cyan.opacity(0.16)), lineWidth: 1)

            let radius = shortest * (0.12 + progress * 0.1)
            context.stroke(
                Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                with: .color(.purple.opacity(0.72)),
                lineWidth: 1.4
            )
        }
    }
}

private struct TerminalMemoryGrid: View {
    let progress: CGFloat
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 12)

    var body: some View {
        HStack(spacing: 10) {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(0..<72, id: \.self) { index in
                    let threshold = CGFloat((index * 37) % 100) / 100
                    Rectangle()
                        .fill(
                            threshold < progress
                                ? Color.cyan.opacity(index.isMultiple(of: 9) ? 0.35 : 0.68)
                                : Color.cyan.opacity(0.08)
                        )
                        .aspectRatio(1, contentMode: .fit)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("TOTAL 4096")
                Text("VERIFIED \(Int(progress * 4096))")
                Text("DAMAGED 0672")
                    .foregroundStyle(.orange.opacity(0.82))
                Text("UNKNOWN \(4096 - Int(progress * 4096))")
            }
            .font(.system(size: 8, design: .monospaced))
            .foregroundStyle(.cyan.opacity(0.68))
            .frame(width: 82, alignment: .leading)
        }
    }
}

private struct TerminalRecoveryStack: View {
    let progress: CGFloat

    private let stages = [
        "CORE ISOLATION",
        "MEMORY ACQUISITION",
        "PATTERN ANALYSIS",
        "VISUAL RECONSTRUCTION",
        "CONSOLIDATION"
    ]

    var body: some View {
        VStack(spacing: 5) {
            ForEach(Array(stages.enumerated()), id: \.offset) { index, title in
                let lowerBound = CGFloat(index) / CGFloat(stages.count)
                let stageProgress = min(max((progress - lowerBound) * CGFloat(stages.count), 0), 1)
                HStack(spacing: 6) {
                    Text("0\(index + 1).")
                    Text(title)
                        .frame(width: 104, alignment: .leading)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color.cyan.opacity(0.07))
                            Rectangle()
                                .fill(Color.cyan.opacity(0.64))
                                .frame(width: proxy.size.width * stageProgress)
                        }
                    }
                    .frame(height: 5)
                    Text("[\(Int(stageProgress * 100))%]")
                        .frame(width: 35, alignment: .trailing)
                }
                .font(.system(size: 7.5, design: .monospaced))
                .foregroundStyle(.cyan.opacity(stageProgress > 0 ? 0.74 : 0.24))
            }
        }
    }
}

private struct TerminalRecoveryFooter: View {
    let progress: CGFloat
    let status: String

    var body: some View {
        HStack(spacing: 22) {
            VStack(alignment: .leading, spacing: 2) {
                Text("시각 정보 복구 중")
                    .font(.system(size: 23, weight: .medium, design: .monospaced))
                Text("VISUAL RECOVERY PROGRESS")
                    .font(.system(size: 9, design: .monospaced))
            }
            .foregroundStyle(.cyan.opacity(0.78))

            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(0..<32, id: \.self) { index in
                        Rectangle()
                            .fill(
                                CGFloat(index) / 32 < progress
                                    ? Color.cyan.opacity(0.75)
                                    : Color.cyan.opacity(0.08)
                            )
                    }
                }
                .padding(5)
                .overlay {
                    Rectangle().stroke(Color.cyan.opacity(0.24), lineWidth: 1)
                }
            }
            .frame(height: 38)

            Text("\(Int(progress * 100))%")
                .font(.system(size: 25, weight: .light, design: .monospaced))
                .foregroundStyle(.cyan.opacity(0.84))

            VStack(alignment: .leading, spacing: 3) {
                Text("CURRENT OPERATION")
                Text(status)
            }
            .font(.system(size: 8.5, design: .monospaced))
            .foregroundStyle(.cyan.opacity(0.66))
            .frame(width: 180, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .background(Color.black.opacity(0.28))
        .overlay {
            Rectangle().stroke(Color.cyan.opacity(0.28), lineWidth: 1)
        }
    }
}

private struct CRTPowerRevealOverlay: View {
    let reveal: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let clampedReveal = min(max(reveal, 0), 1)
            let coverHeight = proxy.size.height * (1 - clampedReveal) / 2

            VStack(spacing: 0) {
                Color.black
                    .frame(height: coverHeight)

                Color.clear

                Color.black
                    .frame(height: coverHeight)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct CRTCurvatureOverlay: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RadialGradient(
                    colors: [
                        .clear,
                        Color.black.opacity(0.08),
                        Color.black.opacity(0.58)
                    ],
                    center: .center,
                    startRadius: min(proxy.size.width, proxy.size.height) * 0.35,
                    endRadius: max(proxy.size.width, proxy.size.height) * 0.7
                )

                RoundedRectangle(cornerRadius: min(proxy.size.width, proxy.size.height) * 0.065)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.07),
                                .clear,
                                Color.cyan.opacity(0.035)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 8
                    )
                    .blur(radius: 5)

                LinearGradient(
                    colors: [
                        Color.cyan.opacity(0.018),
                        .clear,
                        Color.black.opacity(0.12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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

private struct CRTInterferenceSweepOverlay: View {
    let reducedMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: reducedMotion ? 1 : 1 / 30)) { context in
            GeometryReader { proxy in
                let elapsed = context.date.timeIntervalSinceReferenceDate
                let tick = Int(elapsed * 18)
                let sweepPhase: CGFloat = reducedMotion
                    ? 0.68
                    : CGFloat((sin(elapsed * Double.pi * 2 / 5.8) + 1) / 2)
                let sweepY = proxy.size.height * (0.08 + (sweepPhase * 0.84))

                ZStack {
                    interferenceLine(
                        width: proxy.size.width * 1.08,
                        height: max(72, proxy.size.height * 0.105),
                        opacity: reducedMotion ? 0.16 : 0.44
                    )
                    .position(x: proxy.size.width / 2, y: sweepY)

                    if !reducedMotion {
                        ForEach(0..<4, id: \.self) { index in
                            let verticalSeed = (tick * (index + 5) * 17 + index * 13) % 19
                            let horizontalSeed = (tick * (index + 3) * 11 + index * 23) % 31
                            let verticalJitter = CGFloat(verticalSeed - 9)
                            let horizontalJitter = CGFloat(horizontalSeed - 15)
                            let bandRatio = 0.58 + CGFloat(index) * 0.055
                            let lowerBandY = proxy.size.height * bandRatio
                            let lineWidth = proxy.size.width * (0.54 + CGFloat(index) * 0.11)
                            let lineOpacity = 0.2 + Double(index) * 0.035
                            let isVisible = (tick + index * 7) % 11 > 2

                            interferenceLine(
                                width: lineWidth,
                                height: max(30, proxy.size.height * 0.045),
                                opacity: isVisible ? lineOpacity : 0.035
                            )
                            .offset(x: horizontalJitter)
                            .position(
                                x: proxy.size.width / 2,
                                y: lowerBandY + verticalJitter
                            )
                        }
                    }
                }
            }
        }
        .blendMode(.screen)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func interferenceLine(
        width: CGFloat,
        height: CGFloat,
        opacity: Double
    ) -> some View {
        Image("Floor10CRTInterferenceLine")
            .resizable()
            .frame(width: width, height: height)
            .opacity(opacity)
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
