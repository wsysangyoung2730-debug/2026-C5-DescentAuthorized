import SwiftUI

struct FloorEntranceInvestigationLayer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var gameFeedback: GameFeedbackManager
    @EnvironmentObject private var gameSession: GameSessionStore

    @ObservedObject var sceneController: RealitySceneController

    let configuration: FloorEntranceInvestigationConfiguration
    let trailingReservedWidth: CGFloat
    let onCompletion: (() -> Void)?

    @State private var detailClueID: String?
    @State private var cameraLookOrigin: CGSize?
    @State private var isAnchorPulseActive = false
    @State private var completesWhenRecordCloses = false

    private let sceneProjectionTopInset: CGFloat = 96
    private let markerSize = CGSize(width: 76, height: 110)
    private let markerHitboxSize = CGSize(width: 96, height: 126)
    private let panelBaseWidth: CGFloat = 312

    var body: some View {
        GeometryReader { proxy in
            let explorationWidth = max(320, proxy.size.width - trailingReservedWidth)

            ZStack {
                limitedLookSurface(viewportSize: proxy.size)
                    .frame(width: explorationWidth)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                ForEach(configuration.clues) { clue in
                    if let projection = projection(for: clue, in: proxy.size) {
                        let visualScale = max(0.84, projection.scale)

                        connector(
                            for: clue,
                            projection: projection,
                            scale: visualScale
                        )
                        .zIndex(1)

                        investigationMarker(
                            clue,
                            projection: projection,
                            visualScale: visualScale
                        )
                        .position(projection.point)
                        .zIndex(2)

                        cluePanel(clue, scale: visualScale)
                            .position(panelPosition(for: clue, projection: projection, scale: visualScale))
                            .zIndex(3)
                    }
                }

                investigationHeader
                    .frame(width: explorationWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, 28)
                    .padding(.top, 24)
                    .allowsHitTesting(false)
                    .zIndex(5)

                if let clue = detailClue {
                    recordOverlay(clue)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                        .zIndex(20)
                }
            }
            .clipped()
        }
        .onAppear {
            sceneController.setLimitedCameraInteractionEnabled(true)
            startAnchorPulse()
        }
        .onDisappear {
            sceneController.setLimitedCameraInteractionEnabled(false)
        }
        .accessibilityElement(children: .contain)
    }

    private var investigationHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(configuration.areaTitle)
                .font(.system(size: 17, weight: .semibold, design: .serif))
                .foregroundStyle(configuration.accent)

            Text("공간의 표식을 눌러 입구 기록을 확인하십시오.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))

            Text("조사 \(inspectedClueIDs.count) / \(configuration.clues.count)")
                .font(.caption.monospaced().weight(.bold))
                .foregroundStyle(configuration.accent.opacity(0.94))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(configuration.accent.opacity(0.38), lineWidth: 1)
        }
        .fixedSize()
    }

    private func investigationMarker(
        _ clue: FloorEntranceInvestigationClue,
        projection: FloorEntranceInvestigationProjection,
        visualScale: CGFloat
    ) -> some View {
        let isCompleted = inspectedClueIDs.contains(clue.recordID)
        let size = CGSize(
            width: markerSize.width * visualScale,
            height: markerSize.height * visualScale
        )
        let hitbox = CGSize(
            width: markerHitboxSize.width * visualScale,
            height: markerHitboxSize.height * visualScale
        )

        return Button {
            reveal(clue)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        (isCompleted ? Color.cyan : clue.accent)
                            .opacity(isAnchorPulseActive ? 0.22 : 0.12)
                    )
                    .frame(width: hitbox.width, height: hitbox.height)
                    .blur(radius: 16)

                Image(
                    isCompleted
                        ? "Floor10InvestigationAnchorCompleted"
                        : "Floor10InvestigationAnchorAvailable"
                )
                .resizable()
                .scaledToFit()
                .frame(width: size.width, height: size.height)
                .opacity(isCompleted ? 0.98 : (isAnchorPulseActive ? 1 : 0.82))
                .scaleEffect(
                    isCompleted || reduceMotion
                        ? 1
                        : (isAnchorPulseActive ? 1.025 : 0.99)
                )
                .shadow(color: clue.accent.opacity(0.55), radius: 11)
            }
            .frame(width: hitbox.width, height: hitbox.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(FloorEntranceAnchorButtonStyle())
        .opacity(projection.opacity)
        .accessibilityLabel("조사 지점, \(clue.markerTitle)")
        .accessibilityValue(isCompleted ? "조사 완료, 다시 열어볼 수 있음" : "미조사")
    }

    private func cluePanel(
        _ clue: FloorEntranceInvestigationClue,
        scale: CGFloat
    ) -> some View {
        let isCompleted = inspectedClueIDs.contains(clue.recordID)
        let width = panelBaseWidth * scale
        let height = width / 2.196

        return ZStack {
            Image("Floor10InvestigationPanelFrame")
                .resizable()
                .scaledToFit()
                .frame(width: width, height: height)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: isCompleted ? "checkmark.seal.fill" : clue.icon)
                        .foregroundStyle(isCompleted ? Color.cyan.opacity(0.92) : clue.accent)

                    Text(clue.markerTitle)
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .foregroundStyle(DAColor.gold)
                        .lineLimit(1)
                }

                Text(clue.detectionText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Label(
                        isCompleted ? "조사 완료" : "미조사",
                        systemImage: isCompleted ? "checkmark.circle.fill" : "waveform.path.ecg"
                    )
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isCompleted ? Color.cyan.opacity(0.88) : clue.accent)

                    Spacer(minLength: 4)

                    Button(isCompleted ? "다시 보기" : "조사하기") {
                        reveal(clue)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(clue.accent.opacity(0.28), in: RoundedRectangle(cornerRadius: 5))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(clue.accent.opacity(0.62), lineWidth: 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, width * 0.09)
            .padding(.trailing, width * 0.075)
            .padding(.vertical, height * 0.1)
        }
        .frame(width: width, height: height)
        .shadow(color: .black.opacity(0.74), radius: 20, y: 9)
        .shadow(color: clue.accent.opacity(0.18), radius: 10)
        .accessibilityElement(children: .contain)
    }

    private func connector(
        for clue: FloorEntranceInvestigationClue,
        projection: FloorEntranceInvestigationProjection,
        scale: CGFloat
    ) -> some View {
        let panelWidth = panelBaseWidth * scale
        let markerWidth = markerHitboxSize.width * scale
        let centerOffset = clue.panelHorizontalDirection * (panelWidth * 0.62)
        let connectorWidth = max(18, abs(centerOffset) - panelWidth * 0.48 - markerWidth * 0.34)

        return Capsule()
            .fill(
                LinearGradient(
                    colors: [clue.accent.opacity(0.16), clue.accent.opacity(0.72)],
                    startPoint: clue.panelHorizontalDirection > 0 ? .leading : .trailing,
                    endPoint: clue.panelHorizontalDirection > 0 ? .trailing : .leading
                )
            )
            .frame(width: connectorWidth, height: 2)
            .position(
                x: projection.point.x + centerOffset * 0.5,
                y: projection.point.y
            )
            .opacity(projection.opacity)
            .allowsHitTesting(false)
    }

    private func recordOverlay(_ clue: FloorEntranceInvestigationClue) -> some View {
        GeometryReader { proxy in
            let recordHeight = min(proxy.size.height * 0.82, 700)
            let recordWidth = recordHeight * (1086 / 1448)

            ZStack {
                Color.black.opacity(0.86)
                    .ignoresSafeArea()
                    .onTapGesture { closeRecord() }

                ZStack {
                    Image("Floor10DescentRecordParchment")
                        .resizable()
                        .scaledToFit()
                        .frame(width: recordWidth, height: recordHeight)
                        .allowsHitTesting(false)

                    VStack(spacing: 15) {
                        Text(configuration.recordTitle)
                            .font(.system(size: 15, weight: .bold, design: .serif))
                            .tracking(1.1)
                            .foregroundStyle(FloorEntranceRecordPalette.ink.opacity(0.72))

                        Text(clue.title)
                            .font(.system(size: 28, weight: .semibold, design: .serif))
                            .foregroundStyle(FloorEntranceRecordPalette.ink)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.84)

                        HStack(spacing: 8) {
                            Rectangle()
                                .fill(FloorEntranceRecordPalette.ink.opacity(0.38))
                                .frame(height: 1)
                            Image(systemName: clue.icon)
                                .font(.caption.weight(.bold))
                            Rectangle()
                                .fill(FloorEntranceRecordPalette.ink.opacity(0.38))
                                .frame(height: 1)
                        }
                        .foregroundStyle(FloorEntranceRecordPalette.ink.opacity(0.62))

                        Text(clue.body)
                            .font(.system(size: 18, weight: .medium, design: .serif))
                            .foregroundStyle(FloorEntranceRecordPalette.ink.opacity(0.92))
                            .lineSpacing(7)
                            .fixedSize(horizontal: false, vertical: true)

                        Label(clue.recordTag, systemImage: clue.tagIcon)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(FloorEntranceRecordPalette.magicInk)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .background(
                                FloorEntranceRecordPalette.magicInk.opacity(0.09),
                                in: Capsule()
                            )

                        Spacer(minLength: 4)

                        Label("조사 완료 · 기록 보존됨", systemImage: "checkmark.seal.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(FloorEntranceRecordPalette.sealInk)

                        Button("기록 닫기") {
                            closeRecord()
                        }
                        .font(.system(size: 17, weight: .semibold, design: .serif))
                        .foregroundStyle(Color(red: 0.88, green: 0.79, blue: 0.59))
                        .padding(.horizontal, 26)
                        .frame(height: 48)
                        .background(
                            FloorEntranceRecordPalette.ink.opacity(0.9),
                            in: RoundedRectangle(cornerRadius: 5)
                        )
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, recordWidth * 0.14)
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
                        sceneController.updateBattleCameraLook(
                            translation: CGSize(
                                width: value.translation.width - origin.width,
                                height: value.translation.height - origin.height
                            ),
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

    private var inspectedClueIDs: Set<String> {
        Set(configuration.clues.map(\.recordID))
            .intersection(gameSession.progress.readRecordIDs)
    }

    private var detailClue: FloorEntranceInvestigationClue? {
        guard let detailClueID else { return nil }
        return configuration.clues.first { $0.id == detailClueID }
    }

    private func reveal(_ clue: FloorEntranceInvestigationClue) {
        let isNewClue = !inspectedClueIDs.contains(clue.recordID)
        let willCompleteInvestigation = isNewClue
            && inspectedClueIDs.count == configuration.clues.count - 1

        if inspectedClueIDs.contains(clue.recordID) {
            gameFeedback.trigger(
                .recordOpened,
                settings: appSettings.settings,
                includesHaptic: false
            )
        } else {
            gameSession.send(.readRecord(clue.recordID))
        }

        completesWhenRecordCloses = willCompleteInvestigation

        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.86)) {
            detailClueID = clue.id
        }
    }

    private func closeRecord() {
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
        for clue: FloorEntranceInvestigationClue,
        in viewportSize: CGSize
    ) -> FloorEntranceInvestigationProjection? {
        guard let worldProjection = sceneController
            .projectedInvestigationAnchors[clue.recordID] else { return nil }

        let point = CGPoint(
            x: worldProjection.point.x,
            y: worldProjection.point.y - sceneProjectionTopInset
        )
        let centerDistance = min(
            1,
            abs(point.x - viewportSize.width * 0.5) / (viewportSize.width * 0.5)
        )
        let extendedViewport = CGRect(origin: .zero, size: viewportSize)
            .insetBy(dx: -420, dy: -280)
        guard extendedViewport.contains(point) else { return nil }

        return FloorEntranceInvestigationProjection(
            point: point,
            scale: clue.distanceScale * (1 - centerDistance * 0.08),
            opacity: max(0.52, 1 - centerDistance * 0.3)
        )
    }

    private func panelPosition(
        for clue: FloorEntranceInvestigationClue,
        projection: FloorEntranceInvestigationProjection,
        scale: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: projection.point.x
                + clue.panelHorizontalDirection * (panelBaseWidth * scale * 0.62),
            y: projection.point.y + clue.panelVerticalOffset * scale
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
}

struct FloorEntranceInvestigationConfiguration {
    let areaTitle: String
    let recordTitle: String
    let accent: Color
    let clues: [FloorEntranceInvestigationClue]

    static let floor9 = FloorEntranceInvestigationConfiguration(
        areaTitle: "제9층 · 중앙 기록실 입구",
        recordTitle: "제9층 입구 조사 기록",
        accent: Color(red: 0.76, green: 0.56, blue: 0.3),
        clues: [
            .init(
                id: "approval-document",
                recordID: "9-entrance-01",
                markerTitle: "검은 제본 승인서",
                title: "이름이 지워진 승인서",
                detectionText: "기억침식 흔적 감지",
                body: "승인자 서명이 자신의 필체와 닮아 있다. 이름 칸만 반복해서 긁어낸 듯 비어 있고, 종이 가장자리에는 방금 마른 잉크 냄새가 남아 있다.",
                icon: "doc.text.magnifyingglass",
                accent: Color(red: 0.77, green: 0.56, blue: 0.3),
                distanceScale: 0.92,
                panelHorizontalDirection: 1,
                panelVerticalOffset: -18,
                recordTag: "기록 소실 반응",
                tagIcon: "text.badge.xmark"
            ),
            .init(
                id: "erased-monitor",
                recordID: "floor9.entrance.erased-monitor",
                markerTitle: "손상된 벽면 모니터",
                title: "반려 기록의 반복",
                detectionText: "관리자 집행 로그 감지",
                body: "깨진 화면에는 동일한 승인 요청이 열두 번 반려된 기록이 남아 있다. 마지막 반려 시각은 현재보다 몇 분 뒤로 표시되어 있다.",
                icon: "display.trianglebadge.exclamationmark",
                accent: Color(red: 0.62, green: 0.32, blue: 0.88),
                distanceScale: 0.82,
                panelHorizontalDirection: -1,
                panelVerticalOffset: 22,
                recordTag: "전투 위험 예고",
                tagIcon: "exclamationmark.shield"
            )
        ]
    )

    static let floor8 = FloorEntranceInvestigationConfiguration(
        areaTitle: "제8층 · 균열 관측실 전초",
        recordTitle: "제8층 입구 조사 기록",
        accent: Color(red: 0.22, green: 0.78, blue: 0.96),
        clues: [
            .init(
                id: "warning-tags",
                recordID: "floor8.entrance.warning-tags",
                markerTitle: "격리 경고표 묶음",
                title: "중단된 격리 절차",
                detectionText: "비상 격리 이력 감지",
                body: "경고표마다 서로 다른 폐쇄 시각이 적혀 있지만 서명은 모두 같은 손으로 쓰였다. 마지막 표에는 ‘보호 절차 없이 진입 금지’라는 문장만 남아 있다.",
                icon: "exclamationmark.triangle.fill",
                accent: Color(red: 0.94, green: 0.58, blue: 0.2),
                distanceScale: 0.9,
                panelHorizontalDirection: 1,
                panelVerticalOffset: -20,
                recordTag: "보호 절차 필요",
                tagIcon: "shield.lefthalf.filled"
            ),
            .init(
                id: "isolation-monitor",
                recordID: "floor8.entrance.isolation-monitor",
                markerTitle: "관측 수치 모니터",
                title: "증가하는 잔류 반응",
                detectionText: "비정상 마나 파형 감지",
                body: "멈춘 화면처럼 보이지만 파형의 끝이 아주 느리게 자라고 있다. 관측 대상은 사라진 것이 아니라 격리실 안에서 밀도를 높이고 있다.",
                icon: "waveform.path.ecg.rectangle",
                accent: Color(red: 0.26, green: 0.84, blue: 0.94),
                distanceScale: 0.84,
                panelHorizontalDirection: -1,
                panelVerticalOffset: 24,
                recordTag: "잔류체 위험 예고",
                tagIcon: "waveform.path.ecg"
            )
        ]
    )
}

struct FloorEntranceInvestigationClue: Identifiable {
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
    let recordTag: String
    let tagIcon: String
}

private struct FloorEntranceInvestigationProjection {
    let point: CGPoint
    let scale: CGFloat
    let opacity: CGFloat
}

private enum FloorEntranceRecordPalette {
    static let ink = Color(red: 0.19, green: 0.13, blue: 0.08)
    static let magicInk = Color(red: 0.33, green: 0.16, blue: 0.42)
    static let sealInk = Color(red: 0.48, green: 0.15, blue: 0.12)
}

private struct FloorEntranceAnchorButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .brightness(configuration.isPressed ? 0.08 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
