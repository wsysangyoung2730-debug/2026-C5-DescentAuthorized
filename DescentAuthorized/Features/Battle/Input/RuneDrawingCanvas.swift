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

    func cancelActiveStroke() {
        canvasView?.cancelActiveStroke()
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
    let practiceStrokeSpecs: [GlyphStrokeSpec]
    let onCheckpointReached: ((GlyphCheckpointHit) -> Void)?

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
        onInputRejected: ((StrokeCaptureError) -> Void)? = nil,
        practiceStrokeSpecs: [GlyphStrokeSpec] = [],
        onCheckpointReached: ((GlyphCheckpointHit) -> Void)? = nil
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
        self.practiceStrokeSpecs = practiceStrokeSpecs
        self.onCheckpointReached = onCheckpointReached
        _strokes = strokes
        _lastInputMethod = lastInputMethod
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            strokes: $strokes,
            lastInputMethod: $lastInputMethod,
            onDrawingChanged: onDrawingChanged,
            onInputRejected: onInputRejected,
            onCheckpointReached: onCheckpointReached
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
        view.onCheckpointReached = { [weak coordinator = context.coordinator] hit in
            coordinator?.onCheckpointReached?(hit)
        }
        return view
    }

    func updateUIView(_ view: RuneDrawingCanvasView, context: Context) {
        context.coordinator.strokes = $strokes
        context.coordinator.lastInputMethod = $lastInputMethod
        context.coordinator.onDrawingChanged = onDrawingChanged
        context.coordinator.onInputRejected = onInputRejected
        context.coordinator.onCheckpointReached = onCheckpointReached
        controller.canvasView = view
        view.guidePaths = guidePaths
        view.guideNodes = guideNodes
        view.erasureZones = erasureZones
        view.strokeColor = strokeColor
        view.practiceStrokeSpecs = practiceStrokeSpecs
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
        view.onCheckpointReached = nil
        view.cancelActiveStroke()
    }

    final class Coordinator {
        var strokes: Binding<[DrawnStroke]>
        var lastInputMethod: Binding<DrawingInputMethod?>
        var onDrawingChanged: ((RuneDrawingState) -> Void)?
        var onInputRejected: ((StrokeCaptureError) -> Void)?
        var onCheckpointReached: ((GlyphCheckpointHit) -> Void)?

        init(
            strokes: Binding<[DrawnStroke]>,
            lastInputMethod: Binding<DrawingInputMethod?>,
            onDrawingChanged: ((RuneDrawingState) -> Void)?,
            onInputRejected: ((StrokeCaptureError) -> Void)?,
            onCheckpointReached: ((GlyphCheckpointHit) -> Void)?
        ) {
            self.strokes = strokes
            self.lastInputMethod = lastInputMethod
            self.onDrawingChanged = onDrawingChanged
            self.onInputRejected = onInputRejected
            self.onCheckpointReached = onCheckpointReached
        }
    }
}
