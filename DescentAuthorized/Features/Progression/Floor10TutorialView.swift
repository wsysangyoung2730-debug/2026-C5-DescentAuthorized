import SwiftUI

struct Floor10TutorialView: View {
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var gameSession: GameSessionStore

    @State private var descentState: RealityDescentPresentationState = .inactive
    @State private var transitionTask: Task<Void, Never>?
    @StateObject private var sceneController = RealitySceneController()

    var body: some View {
        ZStack {
            RealityStageView(
                sceneID: .floor10ClosedOffice,
                cameraPreset: cameraPreset,
                descentState: descentState,
                reducedMotion: appSettings.reducedMotion,
                controller: sceneController
            )

            LinearGradient(
                colors: [.clear, DAColor.background.opacity(0.2), DAColor.background.opacity(0.82)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            sceneContent
                .frame(width: contentWidth)
                .frame(maxHeight: .infinity)
                .padding(22)
                .background(DAColor.panel.opacity(0.9))
                .overlay(alignment: .leading) {
                    Rectangle().fill(DAColor.magic.opacity(0.65)).frame(width: 1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
        .onAppear { synchronizeDescentState() }
        .onChange(of: gameSession.progress.currentScene) { _, _ in synchronizeDescentState() }
        .onDisappear { transitionTask?.cancel() }
    }

    @ViewBuilder
    private var sceneContent: some View {
        switch gameSession.progress.currentScene {
        case .floor10MeetingRoom:
            narrativeScene(
                code: "10-A / 폐쇄 회의실",
                title: "기억보다 먼저 깨어난 문양",
                body: "비상등과 손등의 흔적이 서로 다른 박자로 빛난다. 출입문은 잠겼지만 관리 단말에는 하강 봉인 절차가 남아 있다.",
                actionTitle: "회의실을 나간다",
                actionIcon: "door.left.hand.open",
                command: .leaveMeetingRoom
            )

        case .floor10Office:
            spellDiscovery(
                spell: SpellCatalog.afterglowErasure,
                code: "10-B / 폐쇄 사무실",
                body: "찢어진 비상 시전 양식의 문자가 뜻으로 읽힌다. 기억에는 없지만 손은 획의 순서를 알고 있다."
            )

        case .floor10GlyphArchive:
            spellDiscovery(
                spell: SpellCatalog.riftSeverance,
                code: "10-C / 문양 자료 구역",
                body: "훼손되지 않은 두 번째 공격 문양이 서류함 안쪽에 남아 있다. 아래층에 대비하려면 더 까다로운 서명을 익혀야 한다."
            )

        case .floor10TrainingWall:
            trainingScene

        case .floor10DescentDoor:
            descentDoorScene

        default:
            EmptyView()
        }
    }

    private func narrativeScene(
        code: String,
        title: String,
        body: String,
        actionTitle: String,
        actionIcon: String,
        command: DemoCommand
    ) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            sceneCode(code)
            Text(title)
                .font(.system(size: 30, weight: .semibold))
            Text(body)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineSpacing(5)
                .frame(maxWidth: 520, alignment: .leading)
            Spacer()
            Button {
                gameSession.send(command)
            } label: {
                Label(actionTitle, systemImage: actionIcon)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
        }
    }

    private func spellDiscovery(
        spell: SpellDefinition,
        code: String,
        body: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sceneCode(code)
            Label("해독 가능한 주문 기록", systemImage: "doc.text.magnifyingglass")
                .font(.headline)
                .foregroundStyle(.purple)
            Text(spell.name)
                .font(.system(size: 32, weight: .semibold))
            Text(body)
                .foregroundStyle(.secondary)
                .lineSpacing(4)

            glyphPreview(spell)
                .frame(maxHeight: 260)

            Spacer()

            Button {
                gameSession.send(.learnSpell(spell.id))
            } label: {
                Label("\(spell.name) 익히기", systemImage: "scroll.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
        }
    }

    private var trainingScene: some View {
        let spell = trainingSpell
        return VStack(alignment: .leading, spacing: 14) {
            sceneCode("10-D / 시전 시험 벽면")
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("훈련 표적에 \(spell.name) 시전")
                        .font(.title2.weight(.semibold))
                    Text("가이드의 점을 순서대로 지나 문양을 완성한다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "scope")
                    .font(.title)
                    .foregroundStyle(.red)
            }

            GlyphCastingPanel(
                spell: spell,
                inputPreference: appSettings.inputPreference,
                availableMana: 100,
                availableStrokes: 2,
                erasureZones: [],
                onCast: { submission in
                    guard submission.evaluation.succeeded else { return }
                    gameSession.send(.completeTraining(
                        spell: spell.id,
                        grade: submission.evaluation.grade
                    ))
                }
            )
            .frame(maxWidth: 760)
        }
    }

    private var descentDoorScene: some View {
        VStack(alignment: .leading, spacing: 14) {
            sceneCode("10-E / 제9층 하강문")
            Text("하강 권한을 증명하십시오")
                .font(.title2.weight(.semibold))
            Text("문 위의 관리국 표식을 따라 승인 문양을 정확히 그려야 잠금이 해제된다. 문 아래에서는 금속을 긁는 듯한 소리가 들린다.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(3)

            DoorGlyphPanel(
                definition: DescentDoorGlyphCatalog.floor10,
                inputPreference: appSettings.inputPreference,
                onStateChanged: updateDescentState,
                onApproved: { _ in
                    completeDescent()
                }
            )
            .frame(maxWidth: 720)
        }
    }

    private var trainingSpell: SpellDefinition {
        if gameSession.progress.learnedSpells.contains(.riftSeverance),
           !gameSession.progress.completedTrainingSpells.contains(.riftSeverance) {
            return SpellCatalog.riftSeverance
        }
        return SpellCatalog.afterglowErasure
    }

    private func glyphPreview(_ spell: SpellDefinition) -> some View {
        Canvas { context, size in
            for stroke in spell.glyph.strokes {
                var path = Path()
                guard let first = stroke.referencePath.first else { continue }
                path.move(to: canvasPoint(first, size: size))
                for point in stroke.referencePath.dropFirst() {
                    path.addLine(to: canvasPoint(point, size: size))
                }
                context.stroke(
                    path,
                    with: .color(.purple.opacity(0.9)),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .background(Color.black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.purple.opacity(0.25), lineWidth: 1)
        }
    }

    private func canvasPoint(_ point: NormalizedPoint, size: CGSize) -> CGPoint {
        CGPoint(
            x: size.width * point.x / 100,
            y: size.height * point.y / 100
        )
    }

    private func sceneCode(_ text: String) -> some View {
        Text(text)
            .font(.caption.monospaced().weight(.bold))
            .foregroundStyle(.purple)
    }

    private var cameraPreset: RealityCameraPreset {
        switch gameSession.progress.currentScene {
        case .floor10TrainingWall: .battle
        case .floor10DescentDoor: .descentInput
        default: .tutorial
        }
    }

    private var contentWidth: CGFloat {
        switch gameSession.progress.currentScene {
        case .floor10TrainingWall, .floor10DescentDoor: 760
        default: 500
        }
    }

    private func synchronizeDescentState() {
        descentState = gameSession.progress.currentScene == .floor10DescentDoor ? .ready : .inactive
    }

    private func updateDescentState(_ state: DoorGlyphPresentationState) {
        switch state {
        case .ready: descentState = .ready
        case .drawing: descentState = .drawing
        case .failed: descentState = .failed
        case .approved: descentState = .approved
        }
    }

    private func completeDescent() {
        descentState = .approved
        transitionTask?.cancel()
        transitionTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(appSettings.reducedMotion ? 20 : 560))
            guard !Task.isCancelled else { return }
            descentState = .open
            try? await Task.sleep(for: .milliseconds(appSettings.reducedMotion ? 20 : 420))
            guard !Task.isCancelled else { return }
            gameSession.send(.approveDescentDoor)
        }
    }
}
