import SwiftUI

/// The canonical investigation experience used by every floor.
/// Floor-specific behavior is supplied entirely through `InvestigationConfiguration`.
struct InvestigationView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var gameFeedback: GameFeedbackManager
    @EnvironmentObject private var gameSession: GameSessionStore

    @ObservedObject var sceneController: RealitySceneController
    let configuration: InvestigationConfiguration
    let onCompletion: (() -> Void)?

    @State private var detailClueID: String?
    @State private var cameraLookOrigin: CGSize?
    @State private var coachStep: TutorialCoachStep?
    @State private var isAnchorPulseActive = false
    @State private var completesWhenRecordCloses = false

    private let sceneProjectionTopInset: CGFloat = 96
    private let anchorMinProjectionScale: CGFloat = 0.9
    private let anchorMarkerImageSize = CGSize(width: 112, height: 162)
    private let anchorMarkerHitboxSize = CGSize(width: 132, height: 186)
    private let anchorPanelBaseWidth: CGFloat = 430
    private let anchorPanelFloorRiseConnectionRatio: CGFloat = 0.22

    init(
        sceneController: RealitySceneController,
        configuration: InvestigationConfiguration,
        onCompletion: (() -> Void)? = nil
    ) {
        self.sceneController = sceneController
        self.configuration = configuration
        self.onCompletion = onCompletion
    }

    private var clues: [InvestigationClue] {
        configuration.clues
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                limitedLookSurface(viewportSize: proxy.size)

                ForEach(clues) { clue in
                    if let projection = projection(for: clue, in: proxy.size) {
                        let effectiveScale = max(anchorMinProjectionScale, projection.scale)

                        investigationMarker(
                            clue,
                            projection: projection,
                            visualScale: effectiveScale
                        )
                            .position(projection.point)
                            .zIndex(Double(projection.scale))

                        spatialCluePanel(clue, scale: effectiveScale)
                            .position(panelPosition(for: clue, projection: projection, scale: effectiveScale))
                            .transition(panelTransition(for: clue))
                            .zIndex(4 + Double(projection.scale))
                    }
                }

                areaHeader
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, 32)
                    .padding(.top, 24)
                    .zIndex(8)

                if inspectedClueIDs.count == clues.count,
                   detailClueID == nil,
                   let completionAction = configuration.completionAction {
                    completionButton(completionAction)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 34)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(8)
                }

                if let clue = detailClue {
                    clueRecordOverlay(clue)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                        .zIndex(20)
                }
            }
            .clipped()
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: detailClueID)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.28), value: inspectedClueIDs.count)
        }
        .tutorialCoach(
            step: coachStep,
            onNext: advanceCoach,
            onSkip: skipCoach
        )
        .onAppear {
            sceneController.setLimitedCameraInteractionEnabled(true)
            startAnchorPulse()
            resumeCoach()
        }
        .onDisappear {
            sceneController.setLimitedCameraInteractionEnabled(false)
        }
        .onChange(of: gameSession.progress.tutorialProgress.requestedReplay) { _, replay in
            if replay == configuration.tutorial?.sequence {
                resumeCoach()
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var areaHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(configuration.areaTitle)
                .font(.system(size: 18, weight: .semibold, design: .serif))
                .foregroundStyle(configuration.headerAccent)
            Text(configuration.instruction)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
            Text("조사 \(inspectedClueIDs.count) / \(clues.count)")
                .font(.caption.monospaced().weight(.bold))
                .foregroundStyle(configuration.statusAccent.opacity(0.92))
        }
        .frame(width: 394, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(configuration.headerAccent.opacity(0.34), lineWidth: 1)
        }
    }

    private func investigationMarker(
        _ clue: InvestigationClue,
        projection: InvestigationProjection,
        visualScale: CGFloat
    ) -> some View {
        let isCompleted = inspectedClueIDs.contains(clue.recordID)
        let glowColor = isCompleted
            ? Color.cyan.opacity(0.3)
            : clue.accent.opacity(isAnchorPulseActive ? 0.2 : 0.12)
        let markerSize = CGSize(
            width: anchorMarkerImageSize.width * visualScale,
            height: anchorMarkerImageSize.height * visualScale
        )
        let hitboxSize = CGSize(
            width: anchorMarkerHitboxSize.width * visualScale,
            height: anchorMarkerHitboxSize.height * visualScale
        )

        return Button {
            reveal(clue)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(glowColor)
                    .frame(width: hitboxSize.width, height: hitboxSize.height)
                    .blur(radius: 18)

                Image(
                    isCompleted
                        ? "InvestigationAnchorCompleted"
                        : "InvestigationAnchorAvailable"
                )
                .resizable()
                .scaledToFit()
                .frame(width: markerSize.width, height: markerSize.height)
                .opacity(isCompleted ? 0.98 : (isAnchorPulseActive ? 1 : 0.82))
                .scaleEffect(
                    isCompleted || reduceMotion
                        ? 1
                        : (isAnchorPulseActive ? 1.022 : 0.992)
                )
                .shadow(
                    color: isCompleted
                        ? Color.cyan.opacity(0.28)
                        : clue.accent.opacity(isAnchorPulseActive ? 0.56 : 0.34),
                    radius: isCompleted ? 9 : 12
                )
            }
            .frame(width: hitboxSize.width, height: hitboxSize.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(InvestigationAnchorButtonStyle())
        .opacity(projection.opacity)
        .accessibilityLabel("조사 지점, \(clue.markerTitle)")
        .accessibilityValue(isCompleted ? "조사 완료, 다시 열어볼 수 있음" : "미조사")
        .accessibilityHint("두 번 탭하여 조사 정보 패널 열기")
    }

    private func spatialCluePanel(_ clue: InvestigationClue, scale: CGFloat) -> some View {
        let isCompleted = inspectedClueIDs.contains(clue.recordID)
        let width = anchorPanelBaseWidth * scale
        let height = width / 2.196

        return ZStack {
            Image("InvestigationPanelFrame")
                .resizable()
                .scaledToFit()
                .frame(width: width, height: height)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: isCompleted ? "checkmark.seal.fill" : clue.icon)
                        .foregroundStyle(isCompleted ? Color.cyan.opacity(0.9) : clue.accent)

                    Text(clue.markerTitle)
                        .font(.system(size: 19, weight: .semibold, design: .serif))
                        .foregroundStyle(DAColor.gold)
                        .lineLimit(1)
                }

                Text(clue.detectionText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)

                HStack(spacing: 10) {
                    Label(
                        isCompleted ? "조사 완료" : "미조사 · 반응 확인 필요",
                        systemImage: isCompleted ? "checkmark.circle.fill" : "waveform.path.ecg"
                    )
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isCompleted ? Color.cyan.opacity(0.88) : clue.accent.opacity(0.94))

                    Spacer(minLength: 8)

                    investigationPlateButton(
                        title: isCompleted ? "다시 보기" : "조사하기"
                    ) {
                        reveal(clue)
                    }
                }
            }
            .padding(.leading, width * 0.09)
            .padding(.trailing, width * 0.075)
            .padding(.top, height * 0.10)
            .padding(.bottom, height * 0.12)
        }
        .frame(width: width, height: height)
        .shadow(color: .black.opacity(0.72), radius: 22, y: 10)
        .shadow(color: clue.accent.opacity(0.22), radius: 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(clue.markerTitle) 조사 패널")
        .tutorialTarget(TutorialTargetID(clue.recordID))
    }

    private func investigationPlateButton(
        title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Image("InvestigationButtonPlate")
                    .resizable()
                    .scaledToFit()

                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.bottom, 2)
            }
            .frame(width: 138, height: 59)
            .contentShape(Rectangle())
        }
        .buttonStyle(InvestigationPlateButtonStyle())
        .accessibilityHint(
            title == "다시 보기"
                ? "완료한 조사 기록을 다시 엽니다"
                : "선택한 지점의 조사 내용을 엽니다"
        )
    }

    private func clueRecordOverlay(_ clue: InvestigationClue) -> some View {
        GeometryReader { proxy in
            let recordHeight = min(proxy.size.height * 0.82, 700)
            let recordWidth = recordHeight * (1086 / 1448)
            let parchmentSideInsetRatio: CGFloat = 0.17

            ZStack {
                Color.black.opacity(0.84)
                    .ignoresSafeArea()
                    .onTapGesture { closeClueRecord() }

                ZStack {
                    Image("RecordParchment")
                        .resizable()
                        .scaledToFit()
                        .frame(width: recordWidth, height: recordHeight)
                        .allowsHitTesting(false)

                    VStack(spacing: 16) {
                        Text(configuration.recordTitle)
                            .font(.system(size: 15, weight: .bold, design: .serif))
                            .tracking(1.1)
                            .foregroundStyle(InvestigationRecordPalette.ink.opacity(0.72))
                            .lineLimit(1)

                        Text(clue.title)
                            .font(.system(size: 29, weight: .semibold, design: .serif))
                            .foregroundStyle(InvestigationRecordPalette.ink)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.86)

                        HStack(spacing: 8) {
                            Rectangle()
                                .fill(InvestigationRecordPalette.ink.opacity(0.38))
                                .frame(height: 1)
                            Image(systemName: clue.icon)
                                .font(.caption.weight(.bold))
                            Rectangle()
                                .fill(InvestigationRecordPalette.ink.opacity(0.38))
                                .frame(height: 1)
                        }
                        .foregroundStyle(InvestigationRecordPalette.ink.opacity(0.62))

                        Text(clue.body)
                            .font(.system(size: 19, weight: .medium, design: .serif))
                            .foregroundStyle(InvestigationRecordPalette.ink.opacity(0.92))
                            .lineSpacing(8)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        if let recordTag = clue.recordTag,
                           let recordTagIcon = clue.recordTagIcon {
                            Label(recordTag, systemImage: recordTagIcon)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(InvestigationRecordPalette.magicInk)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(
                                    InvestigationRecordPalette.magicInk.opacity(0.09),
                                    in: Capsule()
                                )
                        }

                        Spacer(minLength: 4)

                        Label("조사 완료 · 기록 보존됨", systemImage: "checkmark.seal.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(InvestigationRecordPalette.sealInk)

                        Button("기록 닫기") {
                            closeClueRecord()
                        }
                        .font(.system(size: 17, weight: .semibold, design: .serif))
                        .foregroundStyle(Color(red: 0.88, green: 0.79, blue: 0.59))
                        .padding(.horizontal, 26)
                        .frame(height: 48)
                        .background(
                            InvestigationRecordPalette.ink.opacity(0.9),
                            in: RoundedRectangle(cornerRadius: 5)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(InvestigationRecordPalette.sealInk.opacity(0.7), lineWidth: 1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("조사 기록을 닫고 공간 탐색으로 돌아갑니다")
                    }
                    // The parchment's vertical ornaments sit near 17% from each edge.
                    .padding(.horizontal, recordWidth * parchmentSideInsetRatio)
                    .padding(.top, recordHeight * 0.205)
                    .padding(.bottom, recordHeight * 0.12)
                    .frame(height: recordHeight)
                }
                .frame(width: recordWidth, height: recordHeight)
                .shadow(color: .black.opacity(0.76), radius: 28, y: 12)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private func completionButton(_ action: InvestigationCompletionAction) -> some View {
        ArcaneNavigationButton(
            title: action.title,
            symbol: action.symbol,
            width: action.width,
            showsWaypoint: action.showsWaypoint
        ) {
            onCompletion?()
        }
        .accessibilityHint(action.accessibilityHint)
    }

    private func limitedLookSurface(viewportSize: CGSize) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        if cameraLookOrigin == nil {
                            cameraLookOrigin = value.translation
                            sceneController.beginBattleCameraLook()
                        }

                        let origin = cameraLookOrigin ?? .zero
                        let translation = CGSize(
                            width: value.translation.width - origin.width,
                            height: value.translation.height - origin.height
                        )

                        sceneController.updateBattleCameraLook(
                            translation: translation,
                            viewportSize: viewportSize,
                            configuration: configuration.cameraInteraction
                        )
                    }
                    .onEnded { _ in
                        cameraLookOrigin = nil
                    }
            )
            .accessibilityHidden(true)
    }

    private var detailClue: InvestigationClue? {
        guard let detailClueID else { return nil }
        return clues.first { $0.id == detailClueID }
    }

    private var inspectedClueIDs: Set<String> {
        Set(clues.map(\.recordID)).intersection(gameSession.progress.readRecordIDs)
    }

    private func reveal(_ clue: InvestigationClue) {
        let isNewClue = !inspectedClueIDs.contains(clue.recordID)
        let willCompleteInvestigation = configuration.completionAction == nil
            && isNewClue
            && inspectedClueIDs.count == clues.count - 1

        if isNewClue {
            gameSession.send(.readRecord(clue.recordID))
        } else {
            gameFeedback.trigger(
                .recordOpened,
                settings: appSettings.settings,
                includesHaptic: false
            )
        }

        completesWhenRecordCloses = willCompleteInvestigation

        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.86)) {
            detailClueID = clue.id
        }
    }

    private func closeClueRecord() {
        gameFeedback.playInterface(.back, settings: appSettings.settings)
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
            detailClueID = nil
        }

        guard completesWhenRecordCloses else { return }
        completesWhenRecordCloses = false

        let completionDelay = reduceMotion ? 0 : 0.2
        DispatchQueue.main.asyncAfter(deadline: .now() + completionDelay) {
            onCompletion?()
        }
    }

    private func projection(
        for clue: InvestigationClue,
        in viewportSize: CGSize
    ) -> InvestigationProjection? {
        guard let worldProjection = sceneController
            .projectedInvestigationAnchors[clue.recordID] else { return nil }

        let x = worldProjection.point.x
        let y = worldProjection.point.y - sceneProjectionTopInset
        let point = CGPoint(x: x, y: y)
        let centerDistance = min(1, abs(x - viewportSize.width * 0.5) / (viewportSize.width * 0.5))
        let centerEmphasis = 1 - (centerDistance * 0.08)
        let scale = clue.distanceScale * centerEmphasis
        let edgeFade = max(0.56, 1 - centerDistance * 0.28)
        let extendedViewport = CGRect(origin: .zero, size: viewportSize)
            .insetBy(dx: -460, dy: -300)
        guard extendedViewport.contains(point) else { return nil }

        return InvestigationProjection(
            point: point,
            scale: scale,
            opacity: edgeFade
        )
    }

    private func panelPosition(
        for clue: InvestigationClue,
        projection: InvestigationProjection,
        scale: CGFloat
    ) -> CGPoint {
        let panelWidth = anchorPanelBaseWidth * scale
        let markerHeight = anchorMarkerHitboxSize.height * scale
        switch clue.presentation {
        case .floorRise:
            return CGPoint(
                x: projection.point.x,
                y: projection.point.y
                    - markerHeight * anchorPanelFloorRiseConnectionRatio
                    + clue.panelVerticalOffset * scale
            )
        case .surfaceReveal:
            return CGPoint(
                x: projection.point.x + clue.panelHorizontalDirection * (panelWidth * 0.57),
                y: projection.point.y + clue.panelVerticalOffset * scale
            )
        case .sideUnfold:
            return CGPoint(
                x: projection.point.x + clue.panelHorizontalDirection * (panelWidth * 0.59),
                y: projection.point.y + clue.panelVerticalOffset * scale
            )
        }
    }

    private func panelTransition(for clue: InvestigationClue) -> AnyTransition {
        switch clue.presentation {
        case .floorRise:
            .opacity.combined(with: .offset(y: 42))
        case .surfaceReveal:
            .opacity.combined(with: .scale(scale: 0.82, anchor: .center))
        case .sideUnfold:
            .opacity.combined(
                with: .offset(x: clue.panelHorizontalDirection > 0 ? -34 : 34)
            )
        }
    }

    private func startAnchorPulse() {
        guard !reduceMotion else {
            isAnchorPulseActive = true
            return
        }

        withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
            isAnchorPulseActive = true
        }
    }

    private func resumeCoach() {
        guard let tutorial = configuration.tutorial else {
            coachStep = nil
            return
        }
        let progress = gameSession.progress.tutorialProgress
        guard progress.shouldPresent(tutorial.sequence) else { return }
        let step = progress.activeSequence == tutorial.sequence
            ? (progress.activeStep ?? tutorial.explorationStep)
            : tutorial.explorationStep
        if progress.activeSequence != tutorial.sequence {
            gameSession.send(.beginTutorial(sequence: tutorial.sequence, step: step))
        }
        coachStep = coach(for: step)
    }

    private func coach(for step: TutorialStepID) -> TutorialCoachStep? {
        guard let tutorial = configuration.tutorial else { return nil }

        if step == tutorial.explorationStep {
            return TutorialCoachStep(
                id: step,
                title: tutorial.explorationTitle,
                message: tutorial.explorationMessage,
                targetIDs: [],
                placement: .center
            )
        }

        if step == tutorial.markerStep {
            return TutorialCoachStep(
                id: step,
                title: tutorial.markerTitle,
                message: tutorial.markerMessage,
                targetIDs: [TutorialTargetID(tutorial.targetRecordID)],
                placement: .bottom
            )
        }

        return nil
    }

    private func advanceCoach() {
        guard let coachStep,
              let tutorial = configuration.tutorial else { return }
        if coachStep.id == tutorial.explorationStep {
            gameSession.send(.completeTutorialStep(
                step: tutorial.explorationStep,
                next: tutorial.markerStep
            ))
            self.coachStep = coach(for: tutorial.markerStep)
        } else {
            gameSession.send(.completeTutorialStep(step: tutorial.markerStep, next: nil))
            gameSession.send(.completeTutorial(tutorial.sequence))
            self.coachStep = nil
        }
    }

    private func skipCoach() {
        guard let tutorial = configuration.tutorial else { return }
        gameSession.send(.skipTutorial(tutorial.sequence))
        coachStep = nil
    }
}

private struct InvestigationProjection {
    let point: CGPoint
    let scale: CGFloat
    let opacity: CGFloat
}

enum InvestigationPresentation: Equatable {
    case floorRise
    case surfaceReveal
    case sideUnfold
}

struct InvestigationClue: Identifiable {
    let id: String
    let recordID: String
    let markerTitle: String
    let title: String
    let detectionText: String
    let body: String
    let icon: String
    let accent: Color
    let distanceScale: CGFloat
    let panelHorizontalDirection: CGFloat
    let panelVerticalOffset: CGFloat
    let presentation: InvestigationPresentation
    let recordTag: String?
    let recordTagIcon: String?
}

struct InvestigationCompletionAction {
    let title: String
    let symbol: ArcaneNavigationSymbol
    let width: CGFloat
    let showsWaypoint: Bool
    let accessibilityHint: String
}

struct InvestigationTutorialConfiguration {
    let sequence: TutorialSequenceID
    let explorationStep: TutorialStepID
    let markerStep: TutorialStepID
    let targetRecordID: String
    let explorationTitle: String
    let explorationMessage: String
    let markerTitle: String
    let markerMessage: String
}

struct InvestigationConfiguration {
    let areaTitle: String
    let instruction: String
    let recordTitle: String
    let headerAccent: Color
    let statusAccent: Color
    let enemyPreviewCameraYaw: Float
    let cameraInteraction: BattleCameraInteractionConfiguration
    let clues: [InvestigationClue]
    let completionAction: InvestigationCompletionAction?
    let tutorial: InvestigationTutorialConfiguration?

    static let floor10 = InvestigationConfiguration(
        areaTitle: "제10층 · 승인 관리 구역",
        instruction: "시야를 드래그해 주변을 살피고 표시된 지점을 조사하십시오.",
        recordTitle: "제10층 조사 기록",
        headerAccent: DAColor.gold,
        statusAccent: .purple,
        enemyPreviewCameraYaw: 0,
        cameraInteraction: .floor10Investigation,
        clues: [
            .init(
                id: "target",
                recordID: "floor10.clue.training-target",
                markerTitle: "파손된 훈련 표적",
                title: "멈춘 훈련 표적",
                detectionText: "잔류 마력 반응 감지",
                body: "표적의 외피가 안쪽에서부터 갈라져 있다.\n누군가 이곳에서 반복해서 같은 문양을\n시험한 듯하다.",
                icon: "scope",
                accent: .red,
                distanceScale: 0.86,
                panelHorizontalDirection: -1,
                panelVerticalOffset: -24,
                presentation: .surfaceReveal,
                recordTag: "주문 기록과 연결되는 마력 반응",
                recordTagIcon: "sparkles"
            ),
            .init(
                id: "impact",
                recordID: "floor10.clue.impact-scar",
                markerTitle: "충격 흔적",
                title: "벽면의 균열",
                detectionText: "구조 손상 반응 감지",
                body: "금속 벽면이 바깥이 아니라\n방 안쪽으로 움푹 패였다.\n이 층에서 무언가가 깨어난 뒤\n빠져나간 것 같다.",
                icon: "burst",
                accent: .orange,
                distanceScale: 0.76,
                panelHorizontalDirection: -1,
                panelVerticalOffset: -24,
                presentation: .surfaceReveal,
                recordTag: nil,
                recordTagIcon: nil
            ),
            .init(
                id: "archive",
                recordID: "floor10.clue.glyph-archive",
                markerTitle: "중앙 기록실 단말",
                title: "해독 가능한 기록",
                detectionText: "봉인 기록 반응 감지",
                body: "잉크가 번진 기록 사이에서\n두 개의 문양만 선명하게 반응한다.\n기억에는 없지만 손끝은\n획의 시작점을 알아본다.",
                icon: "doc.text.magnifyingglass",
                accent: .purple,
                distanceScale: 0.72,
                panelHorizontalDirection: 1,
                panelVerticalOffset: 18,
                presentation: .sideUnfold,
                recordTag: "주문 기록과 연결되는 마력 반응",
                recordTagIcon: "sparkles"
            )
        ],
        completionAction: .init(
            title: "훈련 표적 앞으로 이동",
            symbol: .forward,
            width: 390,
            showsWaypoint: true,
            accessibilityHint: "발견한 주문 기록을 확인하는 단계로 이동합니다"
        ),
        tutorial: .init(
            sequence: .floor10Investigation,
            explorationStep: .explorationControls,
            markerStep: .investigationMarkers,
            targetRecordID: "floor10.clue.training-target",
            explorationTitle: "주변 둘러보기",
            explorationMessage: "화면을 좌우 또는 위아래로 드래그하면 제한된 범위 안에서 시선을 움직일 수 있습니다. 일부 지점은 고개를 돌려야 발견할 수 있습니다.",
            markerTitle: "조사 가능한 지점",
            markerMessage: "파손된 훈련 표적의 조사하기를 누르십시오. 완료한 뒤에도 기록을 다시 확인할 수 있습니다."
        )
    )

    static let floor9 = InvestigationConfiguration(
        areaTitle: "제9층 · 중앙 기록실 입구",
        instruction: "공간의 표식을 눌러 입구 기록을 확인하십시오.",
        recordTitle: "제9층 입구 조사 기록",
        headerAccent: Color(red: 0.76, green: 0.56, blue: 0.3),
        statusAccent: Color(red: 0.76, green: 0.56, blue: 0.3),
        enemyPreviewCameraYaw: -.pi * 14 / 180,
        cameraInteraction: .floor9Investigation,
        clues: [
            .init(
                id: "broken-cable-coil",
                recordID: "9-entrance-01",
                markerTitle: "끊어진 케이블 코일",
                title: "의도적으로 끊긴 연결",
                detectionText: "비정상 신호 잔류 감지",
                body: "케이블 피복은 충격으로 찢긴 것이 아니라\n일정한 간격으로 잘려 있다.\n중앙 기록실로 향하던 신호를 누군가\n의도적으로 차단한 흔적으로 보인다.",
                icon: "cable.connector.horizontal",
                accent: Color(red: 0.77, green: 0.56, blue: 0.3),
                distanceScale: 0.9,
                panelHorizontalDirection: 1,
                panelVerticalOffset: -28,
                presentation: .sideUnfold,
                recordTag: "통신 차단 흔적",
                recordTagIcon: "bolt.slash.fill"
            ),
            .init(
                id: "erased-monitor",
                recordID: "floor9.entrance.erased-monitor",
                markerTitle: "손상된 벽면 모니터",
                title: "반려 기록의 반복",
                detectionText: "관리자 집행 로그 감지",
                body: "깨진 화면에는 동일한 승인 요청이\n열두 번 반려된 기록이 남아 있다.\n마지막 반려 시각은 현재보다\n몇 분 뒤로 표시되어 있다.",
                icon: "display.trianglebadge.exclamationmark",
                accent: Color(red: 0.62, green: 0.32, blue: 0.88),
                distanceScale: 0.82,
                panelHorizontalDirection: -1,
                panelVerticalOffset: 22,
                presentation: .sideUnfold,
                recordTag: "전투 위험 예고",
                recordTagIcon: "exclamationmark.shield"
            )
        ],
        completionAction: nil,
        tutorial: nil
    )

    static let floor8 = InvestigationConfiguration(
        areaTitle: "제8층 · 균열 관측실 전초",
        instruction: "공간의 표식을 눌러 입구 기록을 확인하십시오.",
        recordTitle: "제8층 입구 조사 기록",
        headerAccent: Color(red: 0.22, green: 0.78, blue: 0.96),
        statusAccent: Color(red: 0.22, green: 0.78, blue: 0.96),
        enemyPreviewCameraYaw: 0,
        cameraInteraction: .floor8Investigation,
        clues: [
            .init(
                id: "warning-tags",
                recordID: "floor8.entrance.warning-tags",
                markerTitle: "격리 경고표 묶음",
                title: "중단된 격리 절차",
                detectionText: "비상 격리 이력 감지",
                body: "경고표마다 서로 다른 폐쇄 시각이 적혀 있지만\n서명은 모두 같은 손으로 쓰였다.\n마지막 표에는 ‘보호 절차 없이 진입 금지’라는\n문장만 남아 있다.",
                icon: "exclamationmark.triangle.fill",
                accent: Color(red: 0.94, green: 0.58, blue: 0.2),
                distanceScale: 0.9,
                panelHorizontalDirection: 1,
                panelVerticalOffset: -20,
                presentation: .sideUnfold,
                recordTag: "보호 절차 필요",
                recordTagIcon: "shield.lefthalf.filled"
            ),
            .init(
                id: "floor-anchor",
                recordID: "floor8.entrance.floor-anchor",
                markerTitle: "바닥 격리 앵커",
                title: "불안정한 격리 문양",
                detectionText: "잔류 마력 고정 반응 감지",
                body: "바닥의 격리 앵커가 일정한 박자를 잃고\n미세하게 떨린다.\n중심 문양에는 바깥에서 들어온 흔적이 아니라,\n안쪽의 무언가가 밀어낸 흔적이 겹쳐 있다.",
                icon: "scope",
                accent: Color(red: 0.26, green: 0.84, blue: 0.94),
                distanceScale: 0.9,
                panelHorizontalDirection: -1,
                panelVerticalOffset: 24,
                presentation: .sideUnfold,
                recordTag: "격리 장치 이상 반응",
                recordTagIcon: "exclamationmark.shield"
            )
        ],
        completionAction: nil,
        tutorial: nil
    )
}

private enum InvestigationRecordPalette {
    static let ink = Color(red: 0.19, green: 0.13, blue: 0.08)
    static let magicInk = Color(red: 0.33, green: 0.16, blue: 0.42)
    static let sealInk = Color(red: 0.48, green: 0.15, blue: 0.12)
}

private struct InvestigationAnchorButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .brightness(configuration.isPressed ? 0.08 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct InvestigationPlateButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .brightness(configuration.isPressed ? 0.12 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
