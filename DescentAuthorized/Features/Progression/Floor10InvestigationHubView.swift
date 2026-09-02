import SwiftUI

struct Floor10InvestigationHubView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var gameSession: GameSessionStore

    let sceneController: RealitySceneController

    @State private var selectedClueID: String?
    @State private var detailClueID: String?
    @State private var cameraLookOrigin: CGSize?
    @State private var cameraLookStartOffset = CGSize.zero
    @State private var cameraLookOffset = CGSize.zero
    @State private var coachStep: TutorialCoachStep?
    @State private var isAnchorPulseActive = false

    private let clues = Floor10InvestigationClue.allCases

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                limitedLookSurface(viewportSize: proxy.size)

                ForEach(clues) { clue in
                    let projection = projection(for: clue, in: proxy.size)

                    if projection.isVisible {
                        investigationMarker(clue, projection: projection)
                            .position(projection.point)
                            .zIndex(clue.id == selectedClueID ? 4 : projection.scale)
                    }
                }

                if let clue = selectedClue,
                   projection(for: clue, in: proxy.size).isVisible {
                    let projection = projection(for: clue, in: proxy.size)

                    spatialCluePanel(
                        clue,
                        isShowingDetail: detailClueID == clue.id
                    )
                    .scaleEffect(max(0.86, projection.scale))
                    .position(panelPosition(for: clue, projection: projection, in: proxy.size))
                    .transition(panelTransition(for: clue))
                    .zIndex(6)
                }

                areaHeader
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, 32)
                    .padding(.top, 24)
                    .zIndex(8)

                if inspectedClueIDs.count == clues.count,
                   selectedClueID == nil {
                    continueButton
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 34)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(8)
                }
            }
            .clipped()
            .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: selectedClueID)
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
            if replay == .floor10Investigation {
                resumeCoach()
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var areaHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("제10층 · 승인 관리 구역")
                .font(.system(size: 18, weight: .semibold, design: .serif))
                .foregroundStyle(DAColor.gold)
            Text("시야를 드래그해 주변을 살피고 표시된 지점을 조사하십시오.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
            Text("조사 \(inspectedClueIDs.count) / \(clues.count)")
                .font(.caption.monospaced().weight(.bold))
                .foregroundStyle(.purple.opacity(0.92))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(DAColor.gold.opacity(0.34), lineWidth: 1)
        }
    }

    private func investigationMarker(
        _ clue: Floor10InvestigationClue,
        projection: Floor10InvestigationProjection
    ) -> some View {
        let isCompleted = inspectedClueIDs.contains(clue.recordID)
        let isSelected = selectedClueID == clue.id

        return Button {
            select(clue)
        } label: {
            ZStack {
                Image(
                    isCompleted
                        ? "Floor10InvestigationAnchorCompleted"
                        : "Floor10InvestigationAnchorAvailable"
                )
                .resizable()
                .scaledToFit()
                .frame(width: 82, height: 119)
                .opacity(isCompleted ? 0.98 : (isAnchorPulseActive ? 1 : 0.78))
                .scaleEffect(
                    isCompleted || reduceMotion
                        ? 1
                        : (isAnchorPulseActive ? 1.035 : 0.98)
                )
                .shadow(
                    color: isCompleted
                        ? Color.cyan.opacity(0.25)
                        : Color.purple.opacity(isAnchorPulseActive ? 0.66 : 0.3),
                    radius: isCompleted ? 7 : 12
                )

                if isSelected {
                    Circle()
                        .stroke(DAColor.gold.opacity(0.9), lineWidth: 1.5)
                        .frame(width: 52, height: 28)
                        .offset(y: 42)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 94, height: 130)
            .contentShape(Rectangle())
        }
        .buttonStyle(InvestigationAnchorButtonStyle())
        .scaleEffect(projection.scale)
        .opacity(projection.opacity)
        .tutorialTarget(TutorialTargetID(clue.recordID))
        .accessibilityLabel("조사 지점, \(clue.markerTitle)")
        .accessibilityValue(isCompleted ? "조사 완료, 다시 열어볼 수 있음" : "미조사")
        .accessibilityHint("두 번 탭하여 조사 정보 패널 열기")
    }

    private func spatialCluePanel(
        _ clue: Floor10InvestigationClue,
        isShowingDetail: Bool
    ) -> some View {
        let isCompleted = inspectedClueIDs.contains(clue.recordID)
        let width: CGFloat = isShowingDetail ? 500 : 430
        let height = width / 2.196

        return ZStack {
            Image("Floor10InvestigationPanelFrame")
                .resizable()
                .scaledToFit()
                .frame(width: width, height: height)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: isShowingDetail ? 12 : 9) {
                HStack(spacing: 10) {
                    Image(systemName: isCompleted ? "checkmark.seal.fill" : clue.icon)
                        .foregroundStyle(isCompleted ? Color.cyan.opacity(0.9) : clue.accent)

                    Text(isShowingDetail ? clue.title : clue.markerTitle)
                        .font(.system(size: isShowingDetail ? 19 : 21, weight: .semibold, design: .serif))
                        .foregroundStyle(DAColor.gold)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Button {
                        closeCluePanel()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.72))
                    .accessibilityLabel("조사 창 닫기")
                }

                if isShowingDetail {
                    Text(clue.body)
                        .font(.system(size: 16, design: .serif))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 9) {
                        Label("조사 완료", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.cyan.opacity(0.9))

                        if clue.kind == .spellTrace {
                            Label("주문 기록과 연결", systemImage: "sparkles")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.purple.opacity(0.92))
                        }

                        Spacer()

                        investigationPlateButton(title: "닫기") {
                            closeCluePanel()
                        }
                    }
                } else {
                    Text(clue.detectionText)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)

                    HStack(spacing: 12) {
                        Label(
                            isCompleted ? "조사 완료 · 기록 보존됨" : "미조사 · 반응 확인 필요",
                            systemImage: isCompleted ? "checkmark.circle.fill" : "waveform.path.ecg"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isCompleted ? Color.cyan.opacity(0.88) : Color.purple.opacity(0.94))

                        Spacer()

                        investigationPlateButton(
                            title: isCompleted ? "다시 보기" : "조사하기"
                        ) {
                            reveal(clue)
                        }
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
        .shadow(color: Color.purple.opacity(0.22), radius: 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(clue.markerTitle) 조사 패널")
    }

    private func investigationPlateButton(
        title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Image("Floor10InvestigationButtonPlate")
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

    private var continueButton: some View {
        Button {
            gameSession.send(.leaveMeetingRoom)
        } label: {
            Label("훈련 표적 앞으로 이동", systemImage: "arrow.forward")
                .font(.headline)
                .padding(.horizontal, 24)
                .frame(height: 54)
        }
        .buttonStyle(.borderedProminent)
        .tint(.purple.opacity(0.82))
        .accessibilityHint("발견한 주문 기록을 확인하는 단계로 이동합니다")
    }

    private func limitedLookSurface(viewportSize: CGSize) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        if cameraLookOrigin == nil {
                            cameraLookOrigin = value.translation
                            cameraLookStartOffset = cameraLookOffset
                            sceneController.beginBattleCameraLook()
                        }

                        let origin = cameraLookOrigin ?? .zero
                        let translation = CGSize(
                            width: value.translation.width - origin.width,
                            height: value.translation.height - origin.height
                        )

                        cameraLookOffset = clampedCameraOffset(
                            CGSize(
                                width: cameraLookStartOffset.width + translation.width,
                                height: cameraLookStartOffset.height + translation.height
                            ),
                            viewportSize: viewportSize
                        )

                        sceneController.updateBattleCameraLook(
                            translation: translation,
                            viewportSize: viewportSize,
                            configuration: .floorExploration
                        )
                    }
                    .onEnded { _ in
                        cameraLookOrigin = nil
                    }
            )
            .accessibilityHidden(true)
    }

    private var selectedClue: Floor10InvestigationClue? {
        guard let selectedClueID else { return nil }
        return clues.first { $0.id == selectedClueID }
    }

    private var inspectedClueIDs: Set<String> {
        Set(clues.map(\.recordID)).intersection(gameSession.progress.readRecordIDs)
    }

    private func select(_ clue: Floor10InvestigationClue) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.82)) {
            if selectedClueID == clue.id {
                closeCluePanel()
            } else {
                selectedClueID = clue.id
                detailClueID = nil
            }
        }
    }

    private func reveal(_ clue: Floor10InvestigationClue) {
        if !inspectedClueIDs.contains(clue.recordID) {
            gameSession.send(.readRecord(clue.recordID))
        }

        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.86)) {
            detailClueID = clue.id
        }
    }

    private func closeCluePanel() {
        detailClueID = nil
        selectedClueID = nil
    }

    private func projection(
        for clue: Floor10InvestigationClue,
        in viewportSize: CGSize
    ) -> Floor10InvestigationProjection {
        let x = (viewportSize.width * clue.panoramaPosition.x)
            + (cameraLookOffset.width * clue.horizontalParallax)
        let y = (viewportSize.height * clue.panoramaPosition.y)
            + (cameraLookOffset.height * clue.verticalParallax)
        let point = CGPoint(x: x, y: y)
        let centerDistance = min(1, abs(x - viewportSize.width * 0.5) / (viewportSize.width * 0.5))
        let centerEmphasis = 1 - (centerDistance * 0.08)
        let scale = clue.distanceScale * centerEmphasis
        let margin = 72 * scale
        let isVisible = x > -margin
            && x < viewportSize.width + margin
            && y > -margin
            && y < viewportSize.height + margin
        let edgeFade = max(0.56, 1 - centerDistance * 0.28)

        return Floor10InvestigationProjection(
            point: point,
            scale: scale,
            opacity: edgeFade,
            isVisible: isVisible
        )
    }

    private func panelPosition(
        for clue: Floor10InvestigationClue,
        projection: Floor10InvestigationProjection,
        in viewportSize: CGSize
    ) -> CGPoint {
        let isDetail = detailClueID == clue.id
        let panelWidth: CGFloat = (isDetail ? 500 : 430) * max(0.86, projection.scale)
        let panelHeight = panelWidth / 2.196
        let horizontalInset = panelWidth * 0.5 + 22
        let verticalInset = panelHeight * 0.5 + 22

        let proposedPoint: CGPoint
        switch clue.presentation {
        case .floorRise:
            proposedPoint = CGPoint(
                x: projection.point.x,
                y: projection.point.y - (96 * projection.scale) - panelHeight * 0.5
            )
        case .surfaceReveal:
            let direction: CGFloat = projection.point.x > viewportSize.width * 0.55 ? -1 : 1
            proposedPoint = CGPoint(
                x: projection.point.x + direction * (panelWidth * 0.57),
                y: projection.point.y - (24 * projection.scale)
            )
        case .sideUnfold:
            let direction: CGFloat = projection.point.x > viewportSize.width * 0.5 ? -1 : 1
            proposedPoint = CGPoint(
                x: projection.point.x + direction * (panelWidth * 0.59),
                y: projection.point.y - (18 * projection.scale)
            )
        }

        return CGPoint(
            x: min(max(proposedPoint.x, horizontalInset), viewportSize.width - horizontalInset),
            y: min(max(proposedPoint.y, verticalInset + 10), viewportSize.height - verticalInset - 12)
        )
    }

    private func panelTransition(for clue: Floor10InvestigationClue) -> AnyTransition {
        switch clue.presentation {
        case .floorRise:
            .opacity.combined(with: .offset(y: 42))
        case .surfaceReveal:
            .opacity.combined(with: .scale(scale: 0.82, anchor: .center))
        case .sideUnfold:
            .opacity.combined(
                with: .offset(x: clue.panoramaPosition.x > 0.5 ? 34 : -34)
            )
        }
    }

    private func clampedCameraOffset(
        _ offset: CGSize,
        viewportSize: CGSize
    ) -> CGSize {
        CGSize(
            width: min(max(offset.width, -viewportSize.width * 0.5), viewportSize.width * 0.5),
            height: min(max(offset.height, -viewportSize.height * 0.46), viewportSize.height * 0.54)
        )
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
        let progress = gameSession.progress.tutorialProgress
        guard progress.shouldPresent(.floor10Investigation) else { return }
        let step = progress.activeSequence == .floor10Investigation
            ? (progress.activeStep ?? .explorationControls)
            : .explorationControls
        if progress.activeSequence != .floor10Investigation {
            gameSession.send(.beginTutorial(sequence: .floor10Investigation, step: step))
        }
        coachStep = coach(for: step)
    }

    private func coach(for step: TutorialStepID) -> TutorialCoachStep? {
        switch step {
        case .explorationControls:
            TutorialCoachStep(
                id: step,
                title: "주변 둘러보기",
                message: "화면을 좌우 또는 위아래로 드래그하면 제한된 범위 안에서 시선을 움직일 수 있습니다. 일부 지점은 고개를 돌려야 발견할 수 있습니다.",
                targetIDs: [],
                placement: .center
            )
        case .investigationMarkers:
            TutorialCoachStep(
                id: step,
                title: "조사 가능한 지점",
                message: "공간에 떠오른 표식을 눌러 조사 패널을 여십시오. 완료된 지점도 다시 확인할 수 있습니다.",
                targetIDs: clues.map { TutorialTargetID($0.recordID) },
                placement: .bottom
            )
        default:
            nil
        }
    }

    private func advanceCoach() {
        guard let coachStep else { return }
        if coachStep.id == .explorationControls {
            gameSession.send(.completeTutorialStep(step: .explorationControls, next: .investigationMarkers))
            self.coachStep = coach(for: .investigationMarkers)
        } else {
            gameSession.send(.completeTutorialStep(step: .investigationMarkers, next: nil))
            gameSession.send(.completeTutorial(.floor10Investigation))
            self.coachStep = nil
        }
    }

    private func skipCoach() {
        gameSession.send(.skipTutorial(.floor10Investigation))
        coachStep = nil
    }
}

private struct Floor10InvestigationProjection {
    let point: CGPoint
    let scale: CGFloat
    let opacity: CGFloat
    let isVisible: Bool
}

private enum Floor10InvestigationKind: Equatable {
    case environment
    case spellTrace
}

private enum Floor10InvestigationPresentation: Equatable {
    case floorRise
    case surfaceReveal
    case sideUnfold
}

private struct Floor10InvestigationClue: Identifiable, CaseIterable {
    static let target = Floor10InvestigationClue(
        id: "target",
        recordID: "floor10.clue.training-target",
        markerTitle: "파손된 훈련 표적",
        title: "멈춘 훈련 표적",
        detectionText: "잔류 마력 반응 감지",
        body: "표적의 외피가 안쪽에서부터 갈라져 있다. 누군가 이곳에서 반복해서 같은 문양을 시험한 듯하다.",
        icon: "scope",
        accent: .red,
        panoramaPosition: CGPoint(x: 0.73, y: 0.45),
        distanceScale: 0.86,
        horizontalParallax: 0.92,
        verticalParallax: 0.55,
        presentation: .surfaceReveal,
        kind: .spellTrace
    )
    static let desk = Floor10InvestigationClue(
        id: "desk",
        recordID: "floor10.clue.broken-desk",
        markerTitle: "뒤집힌 책상",
        title: "부서진 집기",
        detectionText: "충격 패턴 감지",
        body: "의자와 책상이 한 방향으로 쓰러져 있다. 단순한 사고라기보다 무언가가 방 전체를 밀어낸 흔적에 가깝다.",
        icon: "chair.lounge",
        accent: DAColor.gold,
        panoramaPosition: CGPoint(x: 0.28, y: 0.72),
        distanceScale: 1,
        horizontalParallax: 1.08,
        verticalParallax: 0.72,
        presentation: .floorRise,
        kind: .environment
    )
    static let impact = Floor10InvestigationClue(
        id: "impact",
        recordID: "floor10.clue.impact-scar",
        markerTitle: "충격 흔적",
        title: "벽면의 균열",
        detectionText: "구조 손상 반응 감지",
        body: "금속 벽면이 바깥이 아니라 방 안쪽으로 움푹 패였다. 이 층에서 무언가가 깨어난 뒤 빠져나간 것 같다.",
        icon: "burst",
        accent: .orange,
        panoramaPosition: CGPoint(x: 0.46, y: 0.31),
        distanceScale: 0.76,
        horizontalParallax: 0.78,
        verticalParallax: 0.46,
        presentation: .surfaceReveal,
        kind: .environment
    )
    static let archive = Floor10InvestigationClue(
        id: "archive",
        recordID: "floor10.clue.glyph-archive",
        markerTitle: "중앙 기록실 단말",
        title: "해독 가능한 기록",
        detectionText: "봉인 기록 반응 감지",
        body: "잉크가 번진 기록 사이에서 두 개의 문양만 선명하게 반응한다. 기억에는 없지만 손끝은 획의 시작점을 알아본다.",
        icon: "doc.text.magnifyingglass",
        accent: .purple,
        panoramaPosition: CGPoint(x: 1.14, y: 0.48),
        distanceScale: 0.72,
        horizontalParallax: 1,
        verticalParallax: 0.5,
        presentation: .sideUnfold,
        kind: .spellTrace
    )

    let id: String
    let recordID: String
    let markerTitle: String
    let title: String
    let detectionText: String
    let body: String
    let icon: String
    let accent: Color
    let panoramaPosition: CGPoint
    let distanceScale: CGFloat
    let horizontalParallax: CGFloat
    let verticalParallax: CGFloat
    let presentation: Floor10InvestigationPresentation
    let kind: Floor10InvestigationKind

    static let allCases: [Floor10InvestigationClue] = [.target, .desk, .impact, .archive]
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
