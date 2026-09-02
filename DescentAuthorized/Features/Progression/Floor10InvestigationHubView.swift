import SwiftUI

struct Floor10InvestigationHubView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var gameSession: GameSessionStore

    @ObservedObject var sceneController: RealitySceneController

    @State private var detailClueID: String?
    @State private var cameraLookOrigin: CGSize?
    @State private var coachStep: TutorialCoachStep?
    @State private var isAnchorPulseActive = false

    private let clues = Floor10InvestigationClue.allCases
    private let sceneProjectionTopInset: CGFloat = 96
    private let anchorMinProjectionScale: CGFloat = 0.9
    private let anchorMarkerImageSize = CGSize(width: 112, height: 162)
    private let anchorMarkerHitboxSize = CGSize(width: 132, height: 186)
    private let anchorPanelBaseWidth: CGFloat = 430
    private let anchorPanelFloorRiseConnectionRatio: CGFloat = 0.22
    private let floorRiseClueYOffset: CGFloat = -34
    private let archiveClueYOffset: CGFloat = 34

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
                   detailClueID == nil {
                    continueButton
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
        projection: Floor10InvestigationProjection,
        visualScale: CGFloat
    ) -> some View {
        let isCompleted = inspectedClueIDs.contains(clue.recordID)
        let glowColor = isCompleted
            ? Color.cyan.opacity(0.3)
            : DAColor.gold.opacity(isAnchorPulseActive ? 0.2 : 0.12)
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
                        ? "Floor10InvestigationAnchorCompleted"
                        : "Floor10InvestigationAnchorAvailable"
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
                        : Color.purple.opacity(isAnchorPulseActive ? 0.56 : 0.34),
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

    private func spatialCluePanel(_ clue: Floor10InvestigationClue, scale: CGFloat) -> some View {
        let isCompleted = inspectedClueIDs.contains(clue.recordID)
        let width = anchorPanelBaseWidth * scale
        let height = width / 2.196

        return ZStack {
            Image("Floor10InvestigationPanelFrame")
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
                    .foregroundStyle(isCompleted ? Color.cyan.opacity(0.88) : Color.purple.opacity(0.94))

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
        .shadow(color: Color.purple.opacity(0.22), radius: 12)
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

    private func clueRecordOverlay(_ clue: Floor10InvestigationClue) -> some View {
        GeometryReader { proxy in
            let recordHeight = min(proxy.size.height * 0.82, 700)
            let recordWidth = recordHeight * (1086 / 1448)

            ZStack {
                Color.black.opacity(0.84)
                    .ignoresSafeArea()
                    .onTapGesture { closeClueRecord() }

                ZStack {
                    Image("Floor10DescentRecordParchment")
                        .resizable()
                        .scaledToFit()
                        .frame(width: recordWidth, height: recordHeight)
                        .allowsHitTesting(false)

                    VStack(spacing: 16) {
                        Text("제10층 조사 기록")
                            .font(.system(size: 15, weight: .bold, design: .serif))
                            .tracking(1.1)
                            .foregroundStyle(Floor10InvestigationPalette.ink.opacity(0.72))
                            .lineLimit(1)

                        Text(clue.title)
                            .font(.system(size: 29, weight: .semibold, design: .serif))
                            .foregroundStyle(Floor10InvestigationPalette.ink)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.86)

                        HStack(spacing: 8) {
                            Rectangle()
                                .fill(Floor10InvestigationPalette.ink.opacity(0.38))
                                .frame(height: 1)
                            Image(systemName: clue.icon)
                                .font(.caption.weight(.bold))
                            Rectangle()
                                .fill(Floor10InvestigationPalette.ink.opacity(0.38))
                                .frame(height: 1)
                        }
                        .foregroundStyle(Floor10InvestigationPalette.ink.opacity(0.62))

                        Text(clue.body)
                            .font(.system(size: 19, weight: .medium, design: .serif))
                            .foregroundStyle(Floor10InvestigationPalette.ink.opacity(0.92))
                            .lineSpacing(8)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        if clue.kind == .spellTrace {
                            Label("주문 기록과 연결되는 마력 반응", systemImage: "sparkles")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Floor10InvestigationPalette.magicInk)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(
                                    Floor10InvestigationPalette.magicInk.opacity(0.09),
                                    in: Capsule()
                                )
                        }

                        Spacer(minLength: 4)

                        Label("조사 완료 · 기록 보존됨", systemImage: "checkmark.seal.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Floor10InvestigationPalette.sealInk)

                        Button("기록 닫기") {
                            closeClueRecord()
                        }
                        .font(.system(size: 17, weight: .semibold, design: .serif))
                        .foregroundStyle(Color(red: 0.88, green: 0.79, blue: 0.59))
                        .padding(.horizontal, 26)
                        .frame(height: 48)
                        .background(
                            Floor10InvestigationPalette.ink.opacity(0.9),
                            in: RoundedRectangle(cornerRadius: 5)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Floor10InvestigationPalette.sealInk.opacity(0.7), lineWidth: 1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("조사 기록을 닫고 공간 탐색으로 돌아갑니다")
                    }
                    .padding(.horizontal, recordWidth * 0.14)
                    // The parchment's top rule and diamond sit around 14% high.
                    // Keep the copy below them so glyphs never break the ornament.
                    .padding(.top, recordHeight * 0.205)
                    .padding(.bottom, recordHeight * 0.12)
                    .frame(width: recordWidth, height: recordHeight)
                }
                .frame(width: recordWidth, height: recordHeight)
                .shadow(color: .black.opacity(0.76), radius: 28, y: 12)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
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
                            configuration: .floorExploration
                        )
                    }
                    .onEnded { _ in
                        cameraLookOrigin = nil
                    }
            )
            .accessibilityHidden(true)
    }

    private var detailClue: Floor10InvestigationClue? {
        guard let detailClueID else { return nil }
        return clues.first { $0.id == detailClueID }
    }

    private var inspectedClueIDs: Set<String> {
        Set(clues.map(\.recordID)).intersection(gameSession.progress.readRecordIDs)
    }

    private func reveal(_ clue: Floor10InvestigationClue) {
        if !inspectedClueIDs.contains(clue.recordID) {
            gameSession.send(.readRecord(clue.recordID))
        }

        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.86)) {
            detailClueID = clue.id
        }
    }

    private func closeClueRecord() {
        detailClueID = nil
    }

    private func projection(
        for clue: Floor10InvestigationClue,
        in viewportSize: CGSize
    ) -> Floor10InvestigationProjection? {
        guard let worldProjection = sceneController
            .projectedFloor10InvestigationAnchors[clue.recordID] else { return nil }

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

        return Floor10InvestigationProjection(
            point: point,
            scale: scale,
            opacity: edgeFade
        )
    }

    private func panelPosition(
        for clue: Floor10InvestigationClue,
        projection: Floor10InvestigationProjection,
        scale: CGFloat
    ) -> CGPoint {
        let panelWidth = anchorPanelBaseWidth * scale
        let panelHeight = panelWidth / 2.196
        let markerHeight = anchorMarkerHitboxSize.height * scale
        let specialYOffset: CGFloat = {
            switch clue.recordID {
            case "floor10.clue.broken-desk": floorRiseClueYOffset
            case "floor10.clue.glyph-archive": archiveClueYOffset
            default: 0
            }
        }()

        switch clue.presentation {
        case .floorRise:
            return CGPoint(
                x: projection.point.x,
                y: projection.point.y - markerHeight * anchorPanelFloorRiseConnectionRatio + specialYOffset
            )
        case .surfaceReveal:
            return CGPoint(
                x: projection.point.x + clue.panelHorizontalDirection * (panelWidth * 0.57),
                y: projection.point.y - (24 * projection.scale) + specialYOffset
            )
        case .sideUnfold:
            return CGPoint(
                x: projection.point.x + clue.panelHorizontalDirection * (panelWidth * 0.59),
                y: projection.point.y - (18 * projection.scale) + specialYOffset
            )
        }
    }

    private func panelTransition(for clue: Floor10InvestigationClue) -> AnyTransition {
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
                message: "공간에 열린 패널의 조사하기를 누르십시오. 완료된 지점도 다시 확인할 수 있습니다.",
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
        distanceScale: 0.86,
        panelHorizontalDirection: -1,
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
        distanceScale: 1,
        panelHorizontalDirection: 0,
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
        distanceScale: 0.76,
        panelHorizontalDirection: -1,
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
        distanceScale: 0.72,
        panelHorizontalDirection: 1,
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
    let distanceScale: CGFloat
    let panelHorizontalDirection: CGFloat
    let presentation: Floor10InvestigationPresentation
    let kind: Floor10InvestigationKind

    static let allCases: [Floor10InvestigationClue] = [.target, .desk, .impact, .archive]
}

private enum Floor10InvestigationPalette {
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
