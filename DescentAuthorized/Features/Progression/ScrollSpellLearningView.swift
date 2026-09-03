import SwiftUI

enum ScrollSpellLearningPresentation {
    case floor10
    case standard

    var maximumContentWidth: CGFloat {
        switch self {
        case .floor10: 1240
        case .standard: 1120
        }
    }

    var maximumBoardWidth: CGFloat {
        switch self {
        case .floor10: 820
        case .standard: 740
        }
    }
}

struct ScrollSpellLearningView: View {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var gameFeedback: GameFeedbackManager
    @EnvironmentObject private var gameSession: GameSessionStore

    let spell: SpellDefinition
    let sourceCode: String
    let discoveryText: String
    let presentation: ScrollSpellLearningPresentation
    let tutorialSequence: TutorialSequenceID?
    let failureMechanic: TutorialMechanicID?
    let onCompleted: (CastingGrade) -> Void

    @State private var stage = Stage.fallen
    @State private var pulse = false
    @State private var revealRotation = -4.0
    @State private var completionGrade: CastingGrade?
    @State private var failureCount = 0
    @State private var hasFinished = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                backdrop

                switch stage {
                case .fallen:
                    fallenScrollStage(in: proxy.size)
                        .transition(.opacity)
                case .revealed:
                    revealedScrollStage(in: proxy.size)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                case .practice:
                    practiceStage(in: proxy.size)
                        .transition(.opacity)
                case .acquired:
                    acquiredStage(in: proxy.size)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .tutorialCoach(
            step: scrollDiscoveryCoachStep,
            nextTitle: "두루마리 확인",
            onNext: beginReveal,
            onSkip: {}
        )
        .onAppear {
            startPulse()
            synchronizeTutorial()
        }
        .onChange(of: gameSession.progress.tutorialProgress.requestedReplay) { _, replay in
            guard replay == tutorialSequence else { return }
            stage = .fallen
            synchronizeTutorial()
        }
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
    }

    private var backdrop: some View {
        ZStack {
            Color.black
                .opacity(stage == .fallen ? 0.28 : 0.8)
                .ignoresSafeArea()

            RadialGradient(
                colors: [categoryColor.opacity(stage == .fallen ? 0.08 : 0.18), .clear],
                center: stage == .fallen ? .bottomLeading : .center,
                startRadius: 40,
                endRadius: 760
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    private func fallenScrollStage(in size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            stageHeader(
                eyebrow: sourceCode,
                title: "바닥에 떨어진 두루마리",
                detail: discoveryText
            )

            Spacer(minLength: 12)

            HStack(alignment: .bottom, spacing: 32) {
                Button(action: beginReveal) {
                    ZStack {
                        Ellipse()
                            .fill(categoryColor.opacity(pulse ? 0.22 : 0.1))
                            .frame(width: 390, height: 132)
                            .blur(radius: 28)

                        Image("ScrollLearningFallenScroll")
                            .resizable()
                            .scaledToFit()
                            .frame(width: min(size.width * 0.4, 460))
                            .scaleEffect(reduceMotion ? 1 : (pulse ? 1.025 : 0.985))
                            .shadow(color: categoryColor.opacity(0.5), radius: pulse ? 24 : 12)
                    }
                    .frame(minWidth: 360, minHeight: 230)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .tutorialTarget("scroll-learning.fallen-scroll")
                .accessibilityLabel("떨어진 두루마리")
                .accessibilityHint("눌러서 안쪽의 주문 흔적을 확인합니다")

                VStack(alignment: .leading, spacing: 10) {
                    Label("새로운 마력 반응", systemImage: "sparkles")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(categoryColor)

                    Text("두루마리 안쪽에서 기억에 없는 획의 순서가 감지됩니다.")
                        .font(.system(size: 18, design: .serif))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineSpacing(4)

                    Button("두루마리 펼치기", action: beginReveal)
                        .buttonStyle(.borderedProminent)
                        .tint(categoryColor.opacity(0.82))
                        .frame(minHeight: 44)
                }
                .padding(20)
                .frame(maxWidth: 390, alignment: .leading)
                .background(DAColor.card.opacity(0.94), in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(DAColor.gold.opacity(0.42), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.72), radius: 18, y: 8)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 42)
        .padding(.vertical, 28)
        .frame(maxWidth: presentation.maximumContentWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func revealedScrollStage(in size: CGSize) -> some View {
        VStack(spacing: 12) {
            stageHeader(
                eyebrow: "주문 흔적 복원",
                title: spell.name,
                detail: "두루마리에 남은 문양을 확인하고 실제 입력판에서 같은 순서로 재현하십시오."
            )
            .frame(maxWidth: 760)

            Spacer(minLength: 4)

            ZStack {
                Image("ScrollLearningProjection")
                    .resizable()
                    .scaledToFit()
                    .frame(height: min(size.height * 0.64, 590))
                    .opacity(0.5)
                    .rotationEffect(.degrees(revealRotation))
                    .blendMode(.screen)
                    .allowsHitTesting(false)

                openScrollReference(width: min(size.width * 0.72, 820))
                    .shadow(color: categoryColor.opacity(0.25), radius: 30)
            }

            Spacer(minLength: 2)

            Button {
                showPracticeBoard()
            } label: {
                Label("확대 입력판에서 문양 익히기", systemImage: "hand.draw.fill")
                    .frame(minWidth: 310, minHeight: 46)
            }
            .buttonStyle(.borderedProminent)
            .tint(categoryColor.opacity(0.84))
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 24)
        .frame(maxWidth: presentation.maximumContentWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 4.8).repeatForever(autoreverses: true)) {
                revealRotation = 4
            }
        }
    }

    private func practiceStage(in size: CGSize) -> some View {
        let boardWidth = min(presentation.maximumBoardWidth, size.width * 0.62)
        let referenceWidth = min(390, max(270, size.width - boardWidth - 96))

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("두루마리 문양 해독")
                        .font(.caption.monospaced().weight(.bold))
                        .foregroundStyle(categoryColor)
                    Text("\(spell.name) 입력 연습")
                        .font(.system(size: 27, weight: .semibold, design: .serif))
                    Text(practiceGuidance)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }

                Spacer()

                Label("\(spell.requiredStrokes)획", systemImage: "pencil.and.outline")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(categoryColor)
            }

            HStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("두루마리 원본")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DAColor.gold.opacity(0.9))

                    ZStack {
                        Image("ScrollLearningProjection")
                            .resizable()
                            .scaledToFit()
                            .opacity(0.34)
                            .blendMode(.screen)

                        openScrollReference(width: referenceWidth)
                    }
                    .frame(width: referenceWidth)
                    .frame(maxHeight: boardWidth * 0.7)

                    if failureCount > 0 {
                        Label(
                            failureCount == 1 ? "시작점을 다시 확인하십시오" : "핵심점을 순서대로 통과하십시오",
                            systemImage: "lightbulb.max.fill"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DAColor.gold)
                        .transition(.opacity)
                    }
                }
                .frame(width: referenceWidth)

                GlyphCastingPanel(
                    spell: spell,
                    inputPreference: appSettings.inputPreference,
                    availableMana: 100,
                    availableStrokes: max(2, spell.requiredStrokes),
                    erasureZones: [],
                    showsResourceHeader: false,
                    usesBattleArtwork: true,
                    onCast: handleSubmission
                )
                .frame(width: boardWidth)
                .tutorialTarget("scroll-learning.input-board")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 22)
        .frame(maxWidth: presentation.maximumContentWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func acquiredStage(in size: CGSize) -> some View {
        VStack(spacing: 18) {
            Spacer(minLength: 8)

            ZStack {
                Image("ScrollLearningAcquisitionEffect")
                    .resizable()
                    .scaledToFit()
                    .frame(width: min(size.width * 0.82, 1040))
                    .opacity(0.82)
                    .blendMode(.screen)
                    .allowsHitTesting(false)

                Circle()
                    .fill(categoryColor.opacity(0.13))
                    .frame(width: 330, height: 330)
                    .blur(radius: 28)

                ScrollLearningGlyphReference(
                    spell: spell,
                    color: categoryColor,
                    showsNodes: false,
                    lineWidth: 7
                )
                .frame(width: 300, height: 220)
                .shadow(color: categoryColor, radius: 16)
            }
            .frame(maxHeight: min(size.height * 0.54, 500))

            VStack(spacing: 8) {
                Text("주문 습득 완료")
                    .font(.caption.monospaced().weight(.bold))
                    .tracking(2)
                    .foregroundStyle(categoryColor)

                Text(spell.name)
                    .font(.system(size: 38, weight: .semibold, design: .serif))
                    .foregroundStyle(DAColor.gold)

                if let completionGrade {
                    Text("문양 동기화 \(gradeTitle(completionGrade))")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                }
            }

            Button("계속") {
                finishLearning()
            }
            .buttonStyle(.borderedProminent)
            .tint(categoryColor.opacity(0.84))
            .frame(minWidth: 180, minHeight: 46)

            Spacer(minLength: 12)
        }
        .padding(30)
        .frame(maxWidth: presentation.maximumContentWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openScrollReference(width: CGFloat) -> some View {
        ZStack {
            Image("ScrollLearningOpenScroll")
                .resizable()
                .scaledToFit()

            ScrollLearningGlyphReference(
                spell: spell,
                color: categoryColor,
                showsNodes: true,
                lineWidth: 4
            )
            .frame(width: width * 0.5, height: width * 0.3)
            .offset(y: -width * 0.015)
        }
        .frame(width: width)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(spell.name) 문양이 펼쳐진 두루마리")
    }

    private func stageHeader(eyebrow: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow)
                .font(.caption.monospaced().weight(.bold))
                .foregroundStyle(categoryColor)

            Text(title)
                .font(.system(size: 30, weight: .semibold, design: .serif))
                .foregroundStyle(DAColor.gold)

            Text(detail)
                .font(.system(size: 17, design: .serif))
                .foregroundStyle(.white.opacity(0.8))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scrollDiscoveryCoachStep: TutorialCoachStep? {
        guard let tutorialSequence,
              stage == .fallen,
              gameSession.progress.tutorialProgress.activeSequence == tutorialSequence,
              gameSession.progress.tutorialProgress.activeStep == .afterglowInspect else {
            return nil
        }

        return TutorialCoachStep(
            id: .afterglowInspect,
            title: "떨어진 두루마리",
            message: "탐색 중 발견한 두루마리에는 새로운 주문 문양이 남아 있을 수 있습니다. 두루마리를 펼치고 실제 입력판에서 흔적을 따라 그리면 주문을 익힐 수 있습니다.",
            targetIDs: ["scroll-learning.fallen-scroll"],
            placement: .top,
            showsSkip: false
        )
    }

    private var practiceGuidance: String {
        if failureCount == 0 {
            return "왼쪽 두루마리의 시작점과 핵심점을 확인한 뒤 확대된 전투 입력판에 그대로 그리십시오."
        }
        return "입력은 초기화되었습니다. 밝은 시작점부터 천천히 다시 이어 보십시오."
    }

    private var categoryColor: Color {
        switch spell.category {
        case .attack: Color(red: 0.84, green: 0.24, blue: 0.68)
        case .defense: Color(red: 0.24, green: 0.76, blue: 0.94)
        case .dispel: Color(red: 0.94, green: 0.68, blue: 0.2)
        }
    }

    private var reduceMotion: Bool {
        systemReduceMotion || appSettings.reducedMotion
    }

    private func startPulse() {
        guard !reduceMotion else {
            pulse = true
            return
        }
        withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
            pulse = true
        }
    }

    private func synchronizeTutorial() {
        guard let tutorialSequence else { return }
        let progress = gameSession.progress.tutorialProgress

        if progress.activeSequence == tutorialSequence {
            if progress.activeStep == .afterglowTraining {
                stage = .practice
            }
            return
        }

        guard progress.shouldPresent(tutorialSequence) else { return }
        gameSession.send(.beginTutorial(sequence: tutorialSequence, step: .afterglowInspect))
    }

    private func beginReveal() {
        gameFeedback.playInterface(.confirm, settings: appSettings.settings)
        if let tutorialSequence,
           gameSession.progress.tutorialProgress.activeSequence == tutorialSequence,
           gameSession.progress.tutorialProgress.activeStep == .afterglowInspect {
            gameSession.send(.completeTutorialStep(
                step: .afterglowInspect,
                next: .afterglowTraining
            ))
        }

        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.42)) {
            stage = .revealed
        }
    }

    private func showPracticeBoard() {
        gameFeedback.playInterface(.select, settings: appSettings.settings)
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.36)) {
            stage = .practice
        }
    }

    private func handleSubmission(_ submission: GlyphCastSubmission) {
        guard submission.evaluation.succeeded else {
            failureCount += 1
            if let failureMechanic {
                gameSession.send(.recordTutorialFailure(failureMechanic))
            }
            return
        }

        completionGrade = submission.evaluation.grade
        if let tutorialSequence,
           gameSession.progress.tutorialProgress.activeSequence == tutorialSequence {
            gameSession.send(.completeTutorialStep(step: .afterglowTraining, next: nil))
            gameSession.send(.completeTutorial(tutorialSequence))
        }

        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.48)) {
            stage = .acquired
        }
    }

    private func finishLearning() {
        guard !hasFinished, let completionGrade else { return }
        hasFinished = true
        gameFeedback.playInterface(.confirm, settings: appSettings.settings)
        onCompleted(completionGrade)
    }

    private func gradeTitle(_ grade: CastingGrade) -> String {
        switch grade {
        case .perfect: "완전"
        case .precise: "정밀"
        case .approved: "승인"
        case .incomplete: "불완전"
        case .rejected: "거부"
        }
    }
}

private extension ScrollSpellLearningView {
    enum Stage {
        case fallen
        case revealed
        case practice
        case acquired
    }
}

private struct ScrollLearningGlyphReference: View {
    let spell: SpellDefinition
    let color: Color
    let showsNodes: Bool
    let lineWidth: CGFloat

    var body: some View {
        Canvas { context, size in
            for stroke in spell.glyph.strokes {
                guard let first = stroke.referencePath.first else { continue }
                var path = Path()
                path.move(to: canvasPoint(first, size: size))
                for point in stroke.referencePath.dropFirst() {
                    path.addLine(to: canvasPoint(point, size: size))
                }
                context.stroke(
                    path,
                    with: .color(color.opacity(0.92)),
                    style: StrokeStyle(
                        lineWidth: lineWidth,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )

                guard showsNodes else { continue }
                let nodes = [stroke.start] + stroke.requiredNodes + [stroke.end]
                for (index, node) in nodes.enumerated() {
                    let center = canvasPoint(node, size: size)
                    let diameter: CGFloat = index == 0 ? 13 : 9
                    let nodePath = Path(ellipseIn: CGRect(
                        x: center.x - diameter / 2,
                        y: center.y - diameter / 2,
                        width: diameter,
                        height: diameter
                    ))
                    context.fill(
                        nodePath,
                        with: .color(index == 0 ? DAColor.gold : Color.white.opacity(0.9))
                    )
                }
            }
        }
        .aspectRatio(1.62, contentMode: .fit)
        .allowsHitTesting(false)
    }

    private func canvasPoint(_ point: NormalizedPoint, size: CGSize) -> CGPoint {
        CGPoint(
            x: size.width * point.x / 100,
            y: size.height * point.y / 100
        )
    }
}
