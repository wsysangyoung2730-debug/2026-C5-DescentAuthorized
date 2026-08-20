import SwiftUI

@MainActor
final class RuneDrawingCanvasController {
    fileprivate weak var canvasView: RuneDrawingCanvasView?

    func undoLastStroke() {
        canvasView?.undoLastStroke()
    }

    func clear() {
        canvasView?.clearStrokes()
    }
}

struct RuneDrawingCanvas: UIViewRepresentable {
    let inputPreference: DrawingInputPreference
    let maximumStrokeCount: Int
    let guidePaths: [[NormalizedPoint]]
    let guideNodes: [NormalizedPoint]
    let strokeColor: UIColor
    let controller: RuneDrawingCanvasController

    @Binding var strokes: [DrawnStroke]
    @Binding var lastInputMethod: DrawingInputMethod?

    init(
        inputPreference: DrawingInputPreference,
        maximumStrokeCount: Int,
        guidePaths: [[NormalizedPoint]] = [],
        guideNodes: [NormalizedPoint] = [],
        strokeColor: UIColor = UIColor(red: 0.66, green: 0.38, blue: 1, alpha: 1),
        controller: RuneDrawingCanvasController,
        strokes: Binding<[DrawnStroke]>,
        lastInputMethod: Binding<DrawingInputMethod?>
    ) {
        self.inputPreference = inputPreference
        self.maximumStrokeCount = maximumStrokeCount
        self.guidePaths = guidePaths
        self.guideNodes = guideNodes
        self.strokeColor = strokeColor
        self.controller = controller
        _strokes = strokes
        _lastInputMethod = lastInputMethod
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            strokes: $strokes,
            lastInputMethod: $lastInputMethod
        )
    }

    func makeUIView(context: Context) -> RuneDrawingCanvasView {
        let view = RuneDrawingCanvasView()
        controller.canvasView = view
        view.onStrokesChanged = { [weak coordinator = context.coordinator] strokes, method in
            coordinator?.strokes.wrappedValue = strokes
            coordinator?.lastInputMethod.wrappedValue = method
        }
        return view
    }

    func updateUIView(_ view: RuneDrawingCanvasView, context: Context) {
        context.coordinator.strokes = $strokes
        context.coordinator.lastInputMethod = $lastInputMethod
        controller.canvasView = view
        view.guidePaths = guidePaths
        view.guideNodes = guideNodes
        view.strokeColor = strokeColor
        view.configure(
            inputPreference: inputPreference,
            maximumStrokeCount: maximumStrokeCount
        )
    }

    static func dismantleUIView(
        _ view: RuneDrawingCanvasView,
        coordinator: Coordinator
    ) {
        view.onStrokesChanged = nil
    }

    final class Coordinator {
        var strokes: Binding<[DrawnStroke]>
        var lastInputMethod: Binding<DrawingInputMethod?>

        init(
            strokes: Binding<[DrawnStroke]>,
            lastInputMethod: Binding<DrawingInputMethod?>
        ) {
            self.strokes = strokes
            self.lastInputMethod = lastInputMethod
        }
    }
}
