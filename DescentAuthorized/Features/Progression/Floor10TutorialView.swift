import SwiftUI

struct Floor10TutorialView: View {
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var gameSession: GameSessionStore

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                floorBackground

                HStack(spacing: 0) {
                    environmentStage
                        .frame(width: proxy.size.width * 0.46)

                    Divider()

                    sceneContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(28)
                }
            }
        }
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
                onApproved: { _ in
                    gameSession.send(.approveDescentDoor)
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

    private var environmentStage: some View {
        ZStack {
            Color(red: 0.035, green: 0.04, blue: 0.05)

            VStack(spacing: 22) {
                Spacer()
                Image(systemName: environmentSymbol)
                    .font(.system(size: 118, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.72))
                    .shadow(color: .purple.opacity(0.5), radius: 18)
                Text(environmentTitle)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            officeLines
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(environmentTitle)
    }

    private var officeLines: some View {
        Canvas { context, size in
            var path = Path()
            for row in 1..<7 {
                let y = size.height * CGFloat(row) / 7
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(.white.opacity(0.035)), lineWidth: 1)

            let window = CGRect(
                x: size.width * 0.16,
                y: size.height * 0.12,
                width: size.width * 0.68,
                height: size.height * 0.25
            )
            context.stroke(Path(window), with: .color(.red.opacity(0.16)), lineWidth: 2)
        }
        .allowsHitTesting(false)
    }

    private var environmentSymbol: String {
        switch gameSession.progress.currentScene {
        case .floor10MeetingRoom: "rectangle.and.pencil.and.ellipsis"
        case .floor10Office: "doc.text.magnifyingglass"
        case .floor10GlyphArchive: "archivebox.fill"
        case .floor10TrainingWall: "scope"
        case .floor10DescentDoor: "door.left.hand.closed"
        default: "building.2"
        }
    }

    private var environmentTitle: String {
        switch gameSession.progress.currentScene {
        case .floor10MeetingRoom: "불이 꺼진 회의실"
        case .floor10Office: "기억침식 비상 사무실"
        case .floor10GlyphArchive: "훼손된 문양 자료실"
        case .floor10TrainingWall: "봉인 시험 벽면"
        case .floor10DescentDoor: "제9층 하강문"
        default: "제10층"
        }
    }

    private var floorBackground: some View {
        Color(red: 0.018, green: 0.021, blue: 0.028)
            .ignoresSafeArea()
    }
}
