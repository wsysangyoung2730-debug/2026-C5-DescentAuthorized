import SwiftUI

struct GlyphCastSubmission {
    let strokes: [DrawnStroke]
    let inputMethod: DrawingInputMethod
    let evaluation: CastingEvaluation
}

struct GateSealGlyphPresentation {
    let stageTitles: [String]
    let resetTitle: String
    let castTitle: String

    init(
        stageTitles: [String] = ["문양 인식", "봉인 공명", "잠금 해제"],
        resetTitle: String = "초기화",
        castTitle: String = "봉인 해제 시전"
    ) {
        self.stageTitles = stageTitles
        self.resetTitle = resetTitle
        self.castTitle = castTitle
    }
}

struct GateSealInteractionView: View {
    let title: String
    let instruction: String
    let spell: SpellDefinition
    let inputPreference: DrawingInputPreference
    let availableMana: Double
    let availableStrokes: Int
    let presentation: GateSealGlyphPresentation
    let onCast: (GlyphCastSubmission) -> Void

    var body: some View {
        GeometryReader { proxy in
            let preferredWidth = max(proxy.size.width * 0.68, 520)
            let maximumWidthForHeight = max(
                420,
                (proxy.size.height - 274) * 1.25 + 126
            )
            let contentWidth = min(
                min(preferredWidth, 960),
                maximumWidthForHeight
            )

            ZStack {
                Color.black.opacity(0.34)
                    .ignoresSafeArea()

                RadialGradient(
                    colors: [Color.purple.opacity(0.09), .clear],
                    center: .center,
                    startRadius: 80,
                    endRadius: 680
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                VStack(spacing: 16) {
                    VStack(spacing: 7) {
                        Text(title)
                            .font(.system(size: 32, weight: .semibold, design: .serif))
                            .foregroundStyle(DAColor.gold)
                            .shadow(color: .black.opacity(0.85), radius: 3, y: 2)

                        Text(instruction)
                            .font(.system(size: 17, weight: .medium, design: .serif))
                            .foregroundStyle(DAColor.body.opacity(0.86))
                            .multilineTextAlignment(.center)
                    }

                    GlyphCastingPanel(
                        spell: spell,
                        inputPreference: inputPreference,
                        availableMana: availableMana,
                        availableStrokes: availableStrokes,
                        erasureZones: [],
                        showsResourceHeader: false,
                        gateSealPresentation: presentation,
                        onCast: onCast
                    )
                    .frame(width: contentWidth)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

struct GlyphCastingPanel: View {
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var gameFeedback: GameFeedbackManager

    let spell: SpellDefinition
    let inputPreference: DrawingInputPreference
    let availableMana: Double
    let availableStrokes: Int
    let erasureZones: [ErasureZone]
    let showsResourceHeader: Bool
    let surfaceOpacity: Double
    let usesBattleArtwork: Bool
    let gateSealPresentation: GateSealGlyphPresentation?
    let onResourcePreviewChanged: ((Double, Int) -> Void)?
    let onCast: (GlyphCastSubmission) -> Void

    @State private var drawingState = RuneDrawingState.empty
    @State private var completedStrokes: [DrawnStroke] = []
    @State private var lastInputMethod: DrawingInputMethod?
    @State private var feedback: CastingEvaluation?
    @State private var rejectionMessage: String?
    @State private var canvasController = RuneDrawingCanvasController()
    @State private var resetAfterCastTask: Task<Void, Never>?

    private let manaEstimator = GlyphManaEstimator()

    init(
        spell: SpellDefinition,
        inputPreference: DrawingInputPreference,
        availableMana: Double,
        availableStrokes: Int,
        erasureZones: [ErasureZone],
        showsResourceHeader: Bool = true,
        surfaceOpacity: Double = 1,
        usesBattleArtwork: Bool = false,
        gateSealPresentation: GateSealGlyphPresentation? = nil,
        onResourcePreviewChanged: ((Double, Int) -> Void)? = nil,
        onCast: @escaping (GlyphCastSubmission) -> Void
    ) {
        self.spell = spell
        self.inputPreference = inputPreference
        self.availableMana = availableMana
        self.availableStrokes = availableStrokes
        self.erasureZones = erasureZones
        self.showsResourceHeader = showsResourceHeader
        self.surfaceOpacity = surfaceOpacity
        self.usesBattleArtwork = usesBattleArtwork
        self.gateSealPresentation = gateSealPresentation
        self.onResourcePreviewChanged = onResourcePreviewChanged
        self.onCast = onCast
    }

    var body: some View {
        Group {
            if let gateSealPresentation {
                gateSealArtworkPanel(gateSealPresentation)
            } else if usesBattleArtwork {
                battleArtworkPanel
            } else {
                VStack(spacing: 12) {
                    if showsResourceHeader {
                        resourceHeader
                    }
                    drawingSurface
                    actionBar
                }
            }
        }
        .onAppear { publishResourcePreview(for: drawingState) }
        .onDisappear {
            resetAfterCastTask?.cancel()
            onResourcePreviewChanged?(availableMana, availableStrokes)
        }
        .onChange(of: spell.id) { _, _ in resetDrawing() }
        .onChange(of: availableMana) { _, _ in resetDrawing() }
        .onChange(of: availableStrokes) { _, _ in resetDrawing() }
    }

    private var resourceHeader: some View {
        HStack(spacing: 16) {
            Label {
                Text("마나 \(Int(remainingMana.rounded()))")
                    .monospacedDigit()
            } icon: {
                Image(systemName: "scribble.variable")
            }
            .foregroundStyle(remainingMana > 0 ? categoryColor : Color.red)

            ProgressView(value: remainingMana, total: max(availableMana, 1))
                .tint(categoryColor)
                .frame(maxWidth: 220)

            Spacer(minLength: 8)

            Label(
                "남은 획 \(remainingStrokeCount)",
                systemImage: "pencil.and.outline"
            )
            .monospacedDigit()
            .foregroundStyle(remainingStrokeCount >= 0 ? .white : .red)
        }
        .font(.subheadline.weight(.semibold))
        .accessibilityElement(children: .combine)
    }

    private var drawingSurface: some View {
        ZStack {
            Color(red: 0.025, green: 0.03, blue: 0.045)
                .opacity(surfaceOpacity)
            grid
            canvasContent
        }
        .aspectRatio(1.62, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(categoryColor.opacity(0.35), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var battleArtworkPanel: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack {
                Image("BattleGlyphInputFrame")
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)
                    .allowsHitTesting(false)

                canvasContent
                    .frame(width: size.width * 0.89, height: size.height * 0.63)
                    .position(x: size.width * 0.5, y: size.height * 0.36)

                battleArtworkActionBar
                    .frame(width: size.width * 0.86, height: size.height * 0.18)
                    .position(x: size.width * 0.5, y: size.height * 0.868)
            }
        }
        .aspectRatio(1331 / 994, contentMode: .fit)
        .accessibilityElement(children: .contain)
    }

    private func gateSealArtworkPanel(
        _ presentation: GateSealGlyphPresentation
    ) -> some View {
        VStack(spacing: 14) {
            gateSealResourceHeader

            HStack(spacing: 18) {
                gateSealDrawingSurface

                gateSealStageRail(presentation.stageTitles)
                    .frame(width: 108)
            }

            gateSealActionBar(presentation)
                .offset(y: -28)
        }
        .accessibilityElement(children: .contain)
    }

    private var gateSealResourceHeader: some View {
        HStack(spacing: 14) {
            Label {
                Text("마나 \(Int(remainingMana.rounded()))")
                    .monospacedDigit()
            } icon: {
                Image(systemName: "scribble.variable")
            }
            .foregroundStyle(remainingMana > 0 ? categoryColor : Color.red)

            ProgressView(value: remainingMana, total: max(availableMana, 1))
                .tint(categoryColor)
                .frame(maxWidth: 250)

            Spacer(minLength: 12)

            Label(
                "남은 획 \(remainingStrokeCount)",
                systemImage: "pencil.and.outline"
            )
            .monospacedDigit()
            .foregroundStyle(remainingStrokeCount >= 0 ? .white : .red)
        }
        .font(.system(size: 17, weight: .semibold, design: .serif))
        .padding(.horizontal, 18)
        .accessibilityElement(children: .combine)
    }

    private var gateSealDrawingSurface: some View {
        ZStack {
            ZStack {
                Color(red: 0.018, green: 0.02, blue: 0.026)
                    .opacity(0.72)

                gateSealMechanism
                    .padding(8)
                    .opacity(0.24)

                grid

                canvasContent
                    .padding(8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 42)
            .padding(.vertical, 38)

            extractedArtwork("GateSealInputFrame")
                .allowsHitTesting(false)
        }
        .aspectRatio(CGFloat(1402) / 1122, contentMode: .fit)
        .shadow(color: .black.opacity(0.82), radius: 18, y: 9)
        .accessibilityLabel("관문 봉인 해제 문양 입력판")
    }

    private var gateSealMechanism: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            let rotation = appSettings.reducedMotion
                ? 0
                : timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 42) / 42 * 360

            extractedArtwork("GateSealMechanism")
                .rotationEffect(.degrees(rotation))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func gateSealStageRail(_ stageTitles: [String]) -> some View {
        let titles = Array(stageTitles.prefix(3))

        return VStack(spacing: 0) {
            ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                gateSealStage(title: title, index: index)

                if index < titles.count - 1 {
                    Rectangle()
                        .fill(gateSealStageColor(index + 1).opacity(0.42))
                        .frame(width: 1, height: 30)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
        .accessibilityElement(children: .combine)
    }

    private func gateSealStage(title: String, index: Int) -> some View {
        let color = gateSealStageColor(index)
        let isCompleted = index < gateSealStageIndex
        let isActive = index == gateSealStageIndex

        return VStack(spacing: 7) {
            ZStack {
                Circle()
                    .stroke(color.opacity(isActive ? 0.9 : 0.45), lineWidth: 1)
                    .frame(width: 42, height: 42)

                Image(systemName: isCompleted ? "checkmark" : gateSealStageIcon(index))
                    .font(.system(size: 17, weight: .semibold))
            }
            .shadow(color: isActive ? color.opacity(0.6) : .clear, radius: 9)

            Text(title)
                .font(.system(size: 13, weight: isActive ? .semibold : .medium, design: .serif))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .foregroundStyle(color)
        .opacity(index <= gateSealStageIndex ? 1 : 0.5)
    }

    private func gateSealActionBar(
        _ presentation: GateSealGlyphPresentation
    ) -> some View {
        GeometryReader { proxy in
            let drawingBoardWidth = max(proxy.size.width - 126, 0)
            let availableWidth = max(drawingBoardWidth - 22, 0)
            let resetWidth = min(154, max(112, availableWidth * 0.24))
            let castWidth = min(430, max(220, availableWidth - resetWidth))

            HStack(spacing: 22) {
                Button {
                    gameFeedback.playInterface(.back, settings: appSettings.settings)
                    resetDrawing()
                } label: {
                    Label(presentation.resetTitle, systemImage: "arrow.counterclockwise")
                        .font(.system(size: 17, weight: .semibold, design: .serif))
                        .foregroundStyle(DAColor.body)
                        .frame(width: resetWidth, height: 58)
                        .background(Color.black.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(DAColor.gold.opacity(0.62), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .disabled(completedStrokes.isEmpty && drawingState.previewStrokes.isEmpty)
                .opacity(completedStrokes.isEmpty && drawingState.previewStrokes.isEmpty ? 0.46 : 1)
                .offset(y: -4)

                Button(action: cast) {
                    ZStack {
                        Image("ScrollLearningContinueButtonPlate")
                            .resizable()
                            .scaledToFill()
                            .frame(width: castWidth, height: 92)
                            .clipped()

                        Text(presentation.castTitle)
                            .font(.system(size: 23, weight: .semibold, design: .serif))
                            .foregroundStyle(DAColor.gold)
                            .shadow(color: .black.opacity(0.9), radius: 3, y: 2)
                            .offset(y: -5)
                    }
                    .frame(width: castWidth, height: 92)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canCast || feedback != nil)
                .opacity(!canCast || feedback != nil ? 0.42 : 1)
                .accessibilityLabel(presentation.castTitle)
            }
            .frame(width: drawingBoardWidth, alignment: .center)
        }
        .frame(height: 92)
    }

    private var gateSealStageIndex: Int {
        if feedback?.succeeded == true || canCast {
            return 2
        }
        if !drawingState.previewStrokes.isEmpty || !completedStrokes.isEmpty {
            return 1
        }
        return 0
    }

    private func gateSealStageColor(_ index: Int) -> Color {
        index <= gateSealStageIndex ? categoryColor : DAColor.body.opacity(0.55)
    }

    private func gateSealStageIcon(_ index: Int) -> String {
        switch index {
        case 0: "scope"
        case 1: "waveform.path"
        default: "lock.open"
        }
    }

    private func extractedArtwork(_ name: String) -> some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .mask {
                Image(name)
                    .resizable()
                    .scaledToFit()
                    .colorInvert()
                    .contrast(4)
                    .brightness(-0.12)
                    .luminanceToAlpha()
            }
    }

    private var canvasContent: some View {
        ZStack {
            RuneDrawingCanvas(
                inputPreference: inputPreference,
                maximumStrokeCount: spell.requiredStrokes,
                guidePaths: spell.glyph.strokes.map(\.referencePath),
                guideNodes: guideNodes,
                erasureZones: erasureZones,
                strokeColor: UIColor(categoryColor),
                controller: canvasController,
                strokes: $completedStrokes,
                lastInputMethod: $lastInputMethod,
                onDrawingChanged: updateDrawing,
                onInputRejected: handleInputRejection
            )
            .allowsHitTesting(feedback == nil)

            if let result = feedback {
                resultOverlay(result)
                    .allowsHitTesting(false)
            } else if let rejectionMessage {
                Text(rejectionMessage)
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.75))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .allowsHitTesting(false)
            }
        }
    }

    private var battleArtworkActionBar: some View {
        GeometryReader { proxy in
            let size = proxy.size

            Button {
                gameFeedback.playInterface(.back, settings: appSettings.settings)
                canvasController.undoLastStroke()
                feedback = nil
            } label: {
                Image("BattleGlyphUndoButton")
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width * 0.25, height: size.height)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(completedStrokes.isEmpty || feedback != nil ? 0.42 : 1)
            .help("마지막 획 취소")
            .accessibilityLabel("마지막 획 취소")
            .disabled(completedStrokes.isEmpty || feedback != nil)
            .position(x: size.width * 0.22, y: size.height * 0.5)

            Rectangle()
                .fill(DAColor.gold.opacity(0.58))
                .frame(width: 1, height: size.height * 0.62)
                .position(x: size.width * 0.42, y: size.height * 0.5)
                .allowsHitTesting(false)

            Button {
                cast()
            } label: {
                ZStack {
                    Image("BattleGlyphCastButton")
                        .resizable()
                        .scaledToFit()
                    Text("시전")
                        .font(.system(size: 20, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.white.opacity(0.94))
                        .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
                }
                .frame(width: size.width * 0.44, height: size.height)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(!canCast || feedback != nil ? 0.42 : 1)
            .accessibilityLabel("시전")
            .disabled(!canCast || feedback != nil)
            .position(x: size.width * 0.7, y: size.height * 0.5)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(spell.name)
                    .font(.headline)
                Text("\(effectRangeTitle) · \(spell.requiredStrokes)획")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                gameFeedback.playInterface(.back, settings: appSettings.settings)
                canvasController.undoLastStroke()
                feedback = nil
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.bordered)
            .help("마지막 획 취소")
            .accessibilityLabel("마지막 획 취소")
            .disabled(completedStrokes.isEmpty || feedback != nil)

            Button("시전") {
                cast()
            }
            .buttonStyle(.borderedProminent)
            .tint(categoryColor)
            .disabled(!canCast || feedback != nil)
        }
    }

    private var grid: some View {
        Canvas { context, size in
            var path = Path()
            for column in 1..<10 {
                let x = size.width * CGFloat(column) / 10
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            for row in 1..<6 {
                let y = size.height * CGFloat(row) / 6
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(.white.opacity(0.05)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }

    private func resultOverlay(_ result: CastingEvaluation) -> some View {
        VStack(spacing: 4) {
            Image(systemName: result.succeeded ? "checkmark.seal.fill" : "xmark.octagon.fill")
                .font(.title)
            Text(result.succeeded ? gradeTitle(result.grade) : failureTitle(result.failure))
                .font(.headline)
            if result.succeeded {
                Text("정확도 \(Int(result.score.rounded()))%")
                    .font(.caption.monospacedDigit())
            }
        }
        .foregroundStyle(result.succeeded ? categoryColor : .red)
        .padding(14)
        .background(.black.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var currentEstimate: GlyphManaEstimate {
        manaEstimator.estimate(
            spell: spell,
            strokes: drawingState.previewStrokes,
            erasureZones: erasureZones
        )
    }

    private var remainingMana: Double {
        max(0, availableMana - currentEstimate.total)
    }

    private var remainingStrokeCount: Int {
        availableStrokes - drawingState.previewStrokes.count
    }

    private var canCast: Bool {
        completedStrokes.count == spell.requiredStrokes
            && completedStrokes.count <= availableStrokes
            && lastInputMethod != nil
    }

    private var guideNodes: [NormalizedPoint] {
        spell.glyph.strokes.flatMap {
            [$0.start] + $0.requiredNodes + $0.optionalNodes + [$0.end]
        }
    }

    private var categoryColor: Color {
        switch spell.category {
        case .attack: Color(red: 0.86, green: 0.2, blue: 0.38)
        case .defense: Color(red: 0.2, green: 0.72, blue: 0.92)
        case .dispel: Color(red: 0.94, green: 0.68, blue: 0.18)
        }
    }

    private var categoryTitle: String {
        switch spell.category {
        case .attack: "공격"
        case .defense: "방어"
        case .dispel: "해제"
        }
    }

    private var effectRangeTitle: String {
        let range = spell.effect.range
        return "\(categoryTitle) \(range.lowerBound)~\(range.upperBound)"
    }

    private func updateDrawing(_ state: RuneDrawingState) {
        drawingState = state
        feedback = nil
        rejectionMessage = nil
        publishResourcePreview(for: state)
    }

    private func handleInputRejection(_ error: StrokeCaptureError) {
        gameFeedback.playInterface(.error, settings: appSettings.settings)
        switch error {
        case .inputRejected:
            rejectionMessage = "설정에서 허용한 입력 도구를 사용해 주세요"
        case .strokeLimitReached:
            rejectionMessage = "이 주문에 필요한 획을 모두 그렸습니다"
        case .strokeAlreadyActive:
            rejectionMessage = "한 번에 하나의 선만 그릴 수 있습니다"
        case .noActiveStroke, .contactMismatch:
            rejectionMessage = "입력이 끊겼습니다. 획을 다시 그려 주세요"
        }
    }

    private func cast() {
        guard let method = lastInputMethod else { return }
        gameFeedback.playInterface(.confirm, settings: appSettings.settings)
        let evaluation = GlyphEvaluator(maximumMana: availableMana).evaluate(
            spell: spell,
            strokes: completedStrokes,
            inputMethod: method,
            erasureZones: erasureZones
        )
        feedback = evaluation
        onCast(GlyphCastSubmission(
            strokes: completedStrokes,
            inputMethod: method,
            evaluation: evaluation
        ))
        scheduleResetAfterCast()
    }

    private func scheduleResetAfterCast() {
        resetAfterCastTask?.cancel()
        resetAfterCastTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            resetAfterCastTask = nil
            clearDrawingState()
        }
    }

    private func resetDrawing() {
        resetAfterCastTask?.cancel()
        resetAfterCastTask = nil
        clearDrawingState()
    }

    private func clearDrawingState() {
        canvasController.clear()
        drawingState = .empty
        completedStrokes = []
        lastInputMethod = nil
        feedback = nil
        rejectionMessage = nil
        onResourcePreviewChanged?(availableMana, availableStrokes)
    }

    private func publishResourcePreview(for state: RuneDrawingState) {
        let estimate = manaEstimator.estimate(
            spell: spell,
            strokes: state.previewStrokes,
            erasureZones: erasureZones
        )
        onResourcePreviewChanged?(
            max(0, availableMana - estimate.total),
            availableStrokes - state.previewStrokes.count
        )
    }

    private func gradeTitle(_ grade: CastingGrade) -> String {
        switch grade {
        case .perfect: "완전 시전"
        case .precise: "정밀 시전"
        case .approved: "승인 시전"
        case .incomplete: "불완전 시전"
        case .rejected: "시전 거부"
        }
    }

    private func failureTitle(_ failure: CastingFailure?) -> String {
        switch failure {
        case .noInput: "문양 없음"
        case .wrongStrokeCount: "획 불일치"
        case .invalidStart: "시작점 오류"
        case .missingRequiredNode: "필수 지점 누락"
        case .invalidEnd: "종료점 오류"
        case .missingCrossing: "교차점 누락"
        case .manaDepleted: "마나 고갈"
        case .incompleteGlyph, nil: "문양 불완전"
        }
    }
}
