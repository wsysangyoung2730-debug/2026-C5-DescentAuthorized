import SwiftUI

struct RuneDrawingState: Equatable {
    let completedStrokes: [DrawnStroke]
    let activeStroke: DrawnStroke?
    let inputMethod: DrawingInputMethod?

    var previewStrokes: [DrawnStroke] {
        guard let activeStroke else { return completedStrokes }
        return completedStrokes + [activeStroke]
    }

    static let empty = RuneDrawingState(
        completedStrokes: [],
        activeStroke: nil,
        inputMethod: nil
    )
}

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
    let erasureZones: [ErasureZone]
    let strokeColor: UIColor
    let controller: RuneDrawingCanvasController
    let onDrawingChanged: ((RuneDrawingState) -> Void)?
    let onInputRejected: ((StrokeCaptureError) -> Void)?

    @Binding var strokes: [DrawnStroke]
    @Binding var lastInputMethod: DrawingInputMethod?

    init(
        inputPreference: DrawingInputPreference,
        maximumStrokeCount: Int,
        guidePaths: [[NormalizedPoint]] = [],
        guideNodes: [NormalizedPoint] = [],
        erasureZones: [ErasureZone] = [],
        strokeColor: UIColor = UIColor(red: 0.66, green: 0.38, blue: 1, alpha: 1),
        controller: RuneDrawingCanvasController,
        strokes: Binding<[DrawnStroke]>,
        lastInputMethod: Binding<DrawingInputMethod?>,
        onDrawingChanged: ((RuneDrawingState) -> Void)? = nil,
        onInputRejected: ((StrokeCaptureError) -> Void)? = nil
    ) {
        self.inputPreference = inputPreference
        self.maximumStrokeCount = maximumStrokeCount
        self.guidePaths = guidePaths
        self.guideNodes = guideNodes
        self.erasureZones = erasureZones
        self.strokeColor = strokeColor
        self.controller = controller
        self.onDrawingChanged = onDrawingChanged
        self.onInputRejected = onInputRejected
        _strokes = strokes
        _lastInputMethod = lastInputMethod
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            strokes: $strokes,
            lastInputMethod: $lastInputMethod,
            onDrawingChanged: onDrawingChanged,
            onInputRejected: onInputRejected
        )
    }

    func makeUIView(context: Context) -> RuneDrawingCanvasView {
        let view = RuneDrawingCanvasView()
        controller.canvasView = view
        view.onDrawingChanged = { [weak coordinator = context.coordinator] state in
            coordinator?.strokes.wrappedValue = state.completedStrokes
            coordinator?.lastInputMethod.wrappedValue = state.inputMethod
            coordinator?.onDrawingChanged?(state)
        }
        view.onInputRejected = { [weak coordinator = context.coordinator] error in
            coordinator?.onInputRejected?(error)
        }
        return view
    }

    func updateUIView(_ view: RuneDrawingCanvasView, context: Context) {
        context.coordinator.strokes = $strokes
        context.coordinator.lastInputMethod = $lastInputMethod
        context.coordinator.onDrawingChanged = onDrawingChanged
        context.coordinator.onInputRejected = onInputRejected
        controller.canvasView = view
        view.guidePaths = guidePaths
        view.guideNodes = guideNodes
        view.erasureZones = erasureZones
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
        view.onDrawingChanged = nil
        view.onInputRejected = nil
    }

    final class Coordinator {
        var strokes: Binding<[DrawnStroke]>
        var lastInputMethod: Binding<DrawingInputMethod?>
        var onDrawingChanged: ((RuneDrawingState) -> Void)?
        var onInputRejected: ((StrokeCaptureError) -> Void)?

        init(
            strokes: Binding<[DrawnStroke]>,
            lastInputMethod: Binding<DrawingInputMethod?>,
            onDrawingChanged: ((RuneDrawingState) -> Void)?,
            onInputRejected: ((StrokeCaptureError) -> Void)?
        ) {
            self.strokes = strokes
            self.lastInputMethod = lastInputMethod
            self.onDrawingChanged = onDrawingChanged
            self.onInputRejected = onInputRejected
        }
    }
}
