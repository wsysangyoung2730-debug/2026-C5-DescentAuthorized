import SwiftUI

struct Floor10InvestigationHubView: View {
    @EnvironmentObject private var gameSession: GameSessionStore

    let sceneController: RealitySceneController

    @State private var selectedClue: Floor10InvestigationClue?
    @State private var cameraLookOrigin: CGSize?
    @State private var coachStep: TutorialCoachStep?

    private let clues = Floor10InvestigationClue.allCases

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                limitedLookSurface(viewportSize: proxy.size)

                ForEach(clues) { clue in
                    investigationMarker(clue)
                        .position(
                            x: proxy.size.width * clue.screenPosition.x,
                            y: proxy.size.height * clue.screenPosition.y
                        )
                }

                areaHeader
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, 32)
                    .padding(.top, 24)

                if inspectedClueIDs.count == clues.count {
                    continueButton
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 34)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if let selectedClue {
                    clueCard(selectedClue)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        .zIndex(4)
                }
            }
            .animation(.easeOut(duration: 0.2), value: selectedClue?.id)
            .animation(.easeOut(duration: 0.25), value: inspectedClueIDs.count)
        }
        .tutorialCoach(
            step: coachStep,
            onNext: advanceCoach,
            onSkip: skipCoach
        )
        .onAppear {
            sceneController.setLimitedCameraInteractionEnabled(true)
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

    private func investigationMarker(_ clue: Floor10InvestigationClue) -> some View {
        Button {
            inspect(clue)
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(.black.opacity(0.74))
                        .frame(width: 48, height: 48)
                    Circle()
                        .stroke(clue.accent.opacity(0.9), lineWidth: 2)
                        .frame(width: 48, height: 48)
                    Image(systemName: inspectedClueIDs.contains(clue.recordID) ? "checkmark" : clue.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(clue.accent)
                }
                Text(clue.markerTitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 9)
                    .frame(height: 25)
                    .background(.black.opacity(0.72), in: Capsule())
            }
        }
        .buttonStyle(.plain)
        .tutorialTarget(TutorialTargetID(clue.recordID))
        .accessibilityLabel("조사 지점, \(clue.markerTitle)")
        .accessibilityValue(inspectedClueIDs.contains(clue.recordID) ? "조사 완료" : "미조사")
    }

    private func clueCard(_ clue: Floor10InvestigationClue) -> some View {
        ZStack {
            Color.black.opacity(0.58)
                .ignoresSafeArea()
                .onTapGesture { selectedClue = nil }

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: clue.icon)
                        .foregroundStyle(clue.accent)
                    Text(clue.title)
                        .font(.headline)
                        .foregroundStyle(DAColor.gold)
                    Spacer()
                    Button {
                        selectedClue = nil
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 38, height: 38)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("닫기")
                }

                Text(clue.body)
                    .font(.system(size: 18, design: .serif))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineSpacing(5)

                if clue.kind == .spellTrace {
                    Label("주문 기록과 연결되는 마력 반응", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.purple.opacity(0.92))
                }

                Button("확인") {
                    selectedClue = nil
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple.opacity(0.78))
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(24)
            .frame(maxWidth: 620)
            .background(DAColor.panel.opacity(0.98), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(DAColor.gold.opacity(0.62), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.7), radius: 24)
            .padding(30)
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
        Set(clues.map(\.recordID)).intersection(gameSession.progress.readRecordIDs)
    }

    private func inspect(_ clue: Floor10InvestigationClue) {
        gameSession.send(.readRecord(clue.recordID))
        selectedClue = clue
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
                message: "화면을 좌우 또는 위아래로 드래그하면 제한된 범위 안에서 시선을 움직일 수 있습니다.",
                targetIDs: [],
                placement: .center
            )
        case .investigationMarkers:
            TutorialCoachStep(
                id: step,
                title: "조사 가능한 지점",
                message: "빛나는 표식은 확인할 수 있는 물체입니다. 네 지점을 원하는 순서로 조사하십시오.",
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

private enum Floor10InvestigationKind: Equatable {
    case environment
    case spellTrace
}

private struct Floor10InvestigationClue: Identifiable, CaseIterable {
    static let target = Floor10InvestigationClue(
        id: "target",
        recordID: "floor10.clue.training-target",
        markerTitle: "파손된 훈련 표적",
        title: "멈춘 훈련 표적",
        body: "표적의 외피가 안쪽에서부터 갈라져 있다. 누군가 이곳에서 반복해서 같은 문양을 시험한 듯하다.",
        icon: "scope",
        accent: .red,
        screenPosition: CGPoint(x: 0.73, y: 0.39),
        kind: .spellTrace
    )
    static let desk = Floor10InvestigationClue(
        id: "desk",
        recordID: "floor10.clue.broken-desk",
        markerTitle: "뒤집힌 책상",
        title: "부서진 집기",
        body: "의자와 책상이 한 방향으로 쓰러져 있다. 단순한 사고라기보다 무언가가 방 전체를 밀어낸 흔적에 가깝다.",
        icon: "chair.lounge",
        accent: DAColor.gold,
        screenPosition: CGPoint(x: 0.28, y: 0.65),
        kind: .environment
    )
    static let impact = Floor10InvestigationClue(
        id: "impact",
        recordID: "floor10.clue.impact-scar",
        markerTitle: "충격 흔적",
        title: "벽면의 균열",
        body: "금속 벽면이 바깥이 아니라 방 안쪽으로 움푹 패였다. 이 층에서 무언가가 깨어난 뒤 빠져나간 것 같다.",
        icon: "burst",
        accent: .orange,
        screenPosition: CGPoint(x: 0.46, y: 0.31),
        kind: .environment
    )
    static let archive = Floor10InvestigationClue(
        id: "archive",
        recordID: "floor10.clue.glyph-archive",
        markerTitle: "문양 기록 더미",
        title: "해독 가능한 기록",
        body: "잉크가 번진 기록 사이에서 두 개의 문양만 선명하게 반응한다. 기억에는 없지만 손끝은 획의 시작점을 알아본다.",
        icon: "doc.text.magnifyingglass",
        accent: .purple,
        screenPosition: CGPoint(x: 0.18, y: 0.43),
        kind: .spellTrace
    )

    let id: String
    let recordID: String
    let markerTitle: String
    let title: String
    let body: String
    let icon: String
    let accent: Color
    let screenPosition: CGPoint
    let kind: Floor10InvestigationKind

    static let allCases: [Floor10InvestigationClue] = [.target, .desk, .impact, .archive]
}
