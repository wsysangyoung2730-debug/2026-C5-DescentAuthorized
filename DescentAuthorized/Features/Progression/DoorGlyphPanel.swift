import SwiftUI

enum DoorGlyphPresentationState: Equatable {
    case ready
    case drawing
    case failed
    case approved
}

struct DoorGlyphPanel: View {
    let definition: DescentDoorGlyphDefinition
    let inputPreference: DrawingInputPreference
    var onStateChanged: ((DoorGlyphPresentationState) -> Void)? = nil
    let onApproved: (CastingEvaluation) -> Void

    @State private var drawingState = RuneDrawingState.empty
    @State private var completedStrokes: [DrawnStroke] = []
    @State private var lastInputMethod: DrawingInputMethod?
    @State private var evaluation: CastingEvaluation?
    @State private var isApproved = false
    @State private var canvasController = RuneDrawingCanvasController()

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Label(definition.name, systemImage: "lock.open.trianglebadge.exclamationmark")
                    .font(.headline)
                Spacer()
                Label(
                    "\(drawingState.previewStrokes.count) / \(definition.requiredStrokes)획",
                    systemImage: "pencil.and.outline"
                )
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
            }

            ZStack {
                Color(red: 0.025, green: 0.03, blue: 0.04)
                approvalGrid

                RuneDrawingCanvas(
                    inputPreference: inputPreference,
                    maximumStrokeCount: definition.requiredStrokes,
                    guidePaths: definition.glyph.strokes.map(\.referencePath),
                    guideNodes: guideNodes,
                    strokeColor: UIColor(red: 0.76, green: 0.33, blue: 0.95, alpha: 1),
                    controller: canvasController,
                    strokes: $completedStrokes,
                    lastInputMethod: $lastInputMethod,
                    onDrawingChanged: { state in
                        drawingState = state
                        evaluation = nil
                        onStateChanged?(state.previewStrokes.isEmpty ? .ready : .drawing)
                    }
                )

                if let evaluation {
                    VStack(spacing: 5) {
                        Image(systemName: evaluation.succeeded ? "checkmark.seal.fill" : "xmark.octagon.fill")
                            .font(.title)
                        Text(evaluation.succeeded ? "하강 승인" : failureTitle(evaluation.failure))
                            .font(.headline)
                    }
                    .foregroundStyle(evaluation.succeeded ? .purple : .red)
                    .padding(14)
                    .background(.black.opacity(0.82))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .allowsHitTesting(false)
                }
            }
            .aspectRatio(1.7, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.purple.opacity(0.4), lineWidth: 1)
            }

            HStack {
                Label(
                    "예상 마나 \(Int(manaEstimate.total.rounded()))",
                    systemImage: "scribble.variable"
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(.purple)

                Spacer()

                Button {
                    canvasController.clear()
                    drawingState = .empty
                    evaluation = nil
                    isApproved = false
                    onStateChanged?(.ready)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .help("승인 문양 지우기")
                .accessibilityLabel("승인 문양 지우기")
                .disabled(completedStrokes.isEmpty)

                Button("문양 확인") {
                    evaluateDoorGlyph()
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(
                    completedStrokes.count != definition.requiredStrokes
                        || lastInputMethod == nil
                        || isApproved
                )
            }
        }
        .onAppear { onStateChanged?(.ready) }
    }

    private var approvalGrid: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: size.width / 2, y: 0))
            path.addLine(to: CGPoint(x: size.width / 2, y: size.height))
            path.move(to: CGPoint(x: 0, y: size.height / 2))
            path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            context.stroke(path, with: .color(.white.opacity(0.06)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }

    private var guideNodes: [NormalizedPoint] {
        definition.glyph.strokes.flatMap {
            [$0.start] + $0.requiredNodes + [$0.end]
        }
    }

    private var manaEstimate: GlyphManaEstimate {
        GlyphManaEstimator().estimate(
            glyph: definition.glyph,
            recommendedMana: definition.recommendedMana,
            strokes: drawingState.previewStrokes
        )
    }

    private func evaluateDoorGlyph() {
        guard let lastInputMethod else { return }
        let result = GlyphEvaluator().evaluate(
            glyph: definition.glyph,
            recommendedMana: definition.recommendedMana,
            strokes: completedStrokes,
            inputMethod: lastInputMethod
        )
        evaluation = result
        guard result.succeeded else {
            onStateChanged?(.failed)
            return
        }
        isApproved = true
        onStateChanged?(.approved)
        onApproved(result)
    }

    private func failureTitle(_ failure: CastingFailure?) -> String {
        switch failure {
        case .invalidStart: "시작점이 다릅니다"
        case .missingRequiredNode: "필수 지점을 지나야 합니다"
        case .invalidEnd: "종료점이 다릅니다"
        case .missingCrossing: "교차점이 맞지 않습니다"
        case .wrongStrokeCount: "획 수가 다릅니다"
        case .manaDepleted: "문양이 너무 깁니다"
        case .noInput, .incompleteGlyph, nil: "문양을 다시 확인하세요"
        }
    }
}
