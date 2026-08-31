import SwiftUI

struct Floor10OpeningExperienceView: View {
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var gameSession: GameSessionStore

    let sceneController: RealitySceneController
    let isSceneReady: Bool

    @State private var presentation: Presentation = .terminal
    @State private var terminalLineCount = 0
    @State private var openingTask: Task<Void, Never>?
    @State private var focus: Floor10OpeningCameraFocus = .rising
    @State private var showsRiseButton = false

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

                if showsRiseButton {
                    Button(action: beginSurvey) {
                        Label("몸 일으키기", systemImage: "figure.stand")
                            .font(.system(size: 19, weight: .semibold, design: .serif))
                            .padding(.horizontal, 28)
                            .frame(height: 58)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple.opacity(0.82))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 62)
                    .accessibilityHint("선택하면 몸을 일으킨 뒤 방 안을 자동으로 둘러봅니다")
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
            presentation = .terminal
            runTerminal()
        } else {
            presentation = .awakening
            showsRiseButton = step == .rise
            prepareAwakeningIfNeeded()
        }
    }

    private func runTerminal() {
        openingTask?.cancel()
        openingTask = Task { @MainActor in
            terminalLineCount = 0
            for index in terminalLines.indices {
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: appSettings.reducedMotion ? 0 : 0.16)) {
                    terminalLineCount = index + 1
                }
                try? await Task.sleep(for: .milliseconds(appSettings.reducedMotion ? 30 : 430))
            }
            try? await Task.sleep(for: .milliseconds(appSettings.reducedMotion ? 50 : 850))
            guard !Task.isCancelled else { return }
            gameSession.send(.completeTutorialStep(step: .terminalBoot, next: .awaken))
            withAnimation(.easeInOut(duration: appSettings.reducedMotion ? 0 : 0.48)) {
                presentation = .awakening
            }
            prepareAwakeningIfNeeded()
        }
    }

    private func prepareAwakeningIfNeeded() {
        guard isSceneReady else { return }
        if let step = gameSession.progress.tutorialProgress.activeStep,
           [.surveyTarget, .surveyDesk, .surveyDamage, .surveyDoor].contains(step) {
            startSurveyCamera()
            return
        }
        sceneController.prepareFloor10FallenCamera(reducedMotion: appSettings.reducedMotion)
        guard gameSession.progress.tutorialProgress.activeStep == .awaken else { return }

        openingTask?.cancel()
        openingTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(appSettings.reducedMotion ? 80 : 900))
            guard !Task.isCancelled else { return }
            gameSession.send(.completeTutorialStep(step: .awaken, next: .rise))
            withAnimation(.easeOut(duration: appSettings.reducedMotion ? 0 : 0.25)) {
                showsRiseButton = true
            }
        }
    }

    private func beginSurvey() {
        showsRiseButton = false
        gameSession.send(.completeTutorialStep(step: .rise, next: .surveyTarget))
        startSurveyCamera()
    }

    private func startSurveyCamera() {
        openingTask?.cancel()
        openingTask = Task { @MainActor in
            await sceneController.playFloor10OpeningCamera(
                reducedMotion: appSettings.reducedMotion
            ) { newFocus in
                withAnimation(.easeOut(duration: appSettings.reducedMotion ? 0 : 0.18)) {
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

    private enum Presentation {
        case terminal
        case awakening
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
