import SwiftUI

struct GlyphCastSubmission {
    let strokes: [DrawnStroke]
    let inputMethod: DrawingInputMethod
    let evaluation: CastingEvaluation
}

struct GlyphCastingPanel: View {
    let spell: SpellDefinition
    let inputPreference: DrawingInputPreference
    let availableMana: Double
    let availableStrokes: Int
    let erasureZones: [ErasureZone]
    let onCast: (GlyphCastSubmission) -> Void

    @State private var drawingState = RuneDrawingState.empty
    @State private var completedStrokes: [DrawnStroke] = []
    @State private var lastInputMethod: DrawingInputMethod?
    @State private var feedback: CastingEvaluation?
    @State private var rejectionMessage: String?
    @State private var canvasController = RuneDrawingCanvasController()

    private let manaEstimator = GlyphManaEstimator()

    var body: some View {
        VStack(spacing: 12) {
            resourceHeader
            drawingSurface
            actionBar
        }
        .onChange(of: spell.id) { _, _ in resetDrawing() }
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
            grid

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
        .aspectRatio(1.62, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(categoryColor.opacity(0.35), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(spell.name)
                    .font(.headline)
                Text("\(categoryTitle) · \(spell.requiredStrokes)획")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                canvasController.undoLastStroke()
                feedback = nil
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.bordered)
            .help("마지막 획 취소")
            .accessibilityLabel("마지막 획 취소")
            .disabled(completedStrokes.isEmpty)

            Button {
                resetDrawing()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
            .help("마법진 지우기")
            .accessibilityLabel("마법진 지우기")
            .disabled(drawingState.previewStrokes.isEmpty)

            Button("시전") {
                cast()
            }
            .buttonStyle(.borderedProminent)
            .tint(categoryColor)
            .disabled(!canCast)
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

    private func updateDrawing(_ state: RuneDrawingState) {
        drawingState = state
        feedback = nil
        rejectionMessage = nil
    }

    private func handleInputRejection(_ error: StrokeCaptureError) {
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
    }

    private func resetDrawing() {
        canvasController.clear()
        drawingState = .empty
        completedStrokes = []
        lastInputMethod = nil
        feedback = nil
        rejectionMessage = nil
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
