import UIKit

@MainActor
final class RuneDrawingCanvasView: UIView {
    var onStrokesChanged: (([DrawnStroke], DrawingInputMethod?) -> Void)?
    var onInputRejected: ((StrokeCaptureError) -> Void)?

    private(set) var inputPreference: DrawingInputPreference
    private(set) var maximumStrokeCount: Int

    var guidePaths: [[NormalizedPoint]] = [] {
        didSet { setNeedsDisplay() }
    }

    var guideNodes: [NormalizedPoint] = [] {
        didSet { setNeedsDisplay() }
    }

    var strokeColor: UIColor = UIColor(red: 0.66, green: 0.38, blue: 1, alpha: 1) {
        didSet { setNeedsDisplay() }
    }

    var guideColor: UIColor = UIColor.white.withAlphaComponent(0.28) {
        didSet { setNeedsDisplay() }
    }

    private var captureSession: StrokeCaptureSession
    private var activeDisplayPoints: [CGPoint] = []
    private var activeDisplayMethod: DrawingInputMethod?

    override init(frame: CGRect) {
        inputPreference = .automatic
        maximumStrokeCount = 2
        captureSession = StrokeCaptureSession()
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        inputPreference = .automatic
        maximumStrokeCount = 2
        captureSession = StrokeCaptureSession()
        super.init(coder: coder)
        configureView()
    }

    func configure(
        inputPreference: DrawingInputPreference,
        maximumStrokeCount: Int
    ) {
        precondition(maximumStrokeCount > 0)

        if maximumStrokeCount != self.maximumStrokeCount {
            self.maximumStrokeCount = maximumStrokeCount
            captureSession = StrokeCaptureSession(
                inputPreference: inputPreference,
                maximumStrokeCount: maximumStrokeCount
            )
            activeDisplayPoints.removeAll(keepingCapacity: true)
            activeDisplayMethod = nil
            notifyStateChanged()
        } else if inputPreference != self.inputPreference {
            captureSession.updateInputPreference(inputPreference)
            activeDisplayPoints.removeAll(keepingCapacity: true)
            activeDisplayMethod = nil
            notifyStateChanged()
        }

        self.inputPreference = inputPreference
        updateAccessibilityValue()
        setNeedsDisplay()
    }

    func undoLastStroke() {
        guard captureSession.undoLastStroke() != nil else { return }
        notifyStateChanged()
        setNeedsDisplay()
    }

    func clearStrokes() {
        guard captureSession.hasActiveStroke
                || !captureSession.completedStrokes.isEmpty else {
            return
        }
        captureSession.clear()
        activeDisplayPoints.removeAll(keepingCapacity: true)
        activeDisplayMethod = nil
        notifyStateChanged()
        setNeedsDisplay()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)

        let prioritized = touches.sorted { first, second in
            touchPriority(first) > touchPriority(second)
        }
        for touch in prioritized {
            guard let method = inputMethod(for: touch) else { continue }
            let sample = rawSample(for: touch)
            do {
                _ = try captureSession.beginStroke(
                    contactID: contactID(for: touch),
                    method: method,
                    sample: sample
                )
                activeDisplayPoints = [location(for: touch)]
                activeDisplayMethod = method
                notifyStateChanged()
                setNeedsDisplay()
                break
            } catch let error as StrokeCaptureError {
                onInputRejected?(error)
            } catch {
                assertionFailure("Unexpected stroke begin error: \(error)")
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)

        for touch in touches where contactID(for: touch) == captureSession.activeContactID {
            let coalesced = event?.coalescedTouches(for: touch) ?? [touch]
            do {
                try captureSession.appendSamples(
                    contactID: contactID(for: touch),
                    samples: coalesced.map(rawSample(for:))
                )
                activeDisplayPoints.append(contentsOf: coalesced.map(location(for:)))
                setNeedsDisplay()
            } catch let error as StrokeCaptureError {
                onInputRejected?(error)
            } catch {
                assertionFailure("Unexpected stroke move error: \(error)")
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)

        for touch in touches where contactID(for: touch) == captureSession.activeContactID {
            let finalTouches = event?.coalescedTouches(for: touch) ?? [touch]
            do {
                _ = try captureSession.endStroke(
                    contactID: contactID(for: touch),
                    finalSamples: finalTouches.map(rawSample(for:)),
                    canvasSize: DrawingCanvasSize(
                        width: bounds.width,
                        height: bounds.height
                    )
                )
            } catch let error as StrokeCaptureError {
                onInputRejected?(error)
            } catch let error as StrokeProcessingError {
                assertionFailure("Stroke processing failed: \(error)")
            } catch {
                assertionFailure("Unexpected stroke end error: \(error)")
            }

            activeDisplayPoints.removeAll(keepingCapacity: true)
            activeDisplayMethod = nil
            notifyStateChanged()
            setNeedsDisplay()
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)

        for touch in touches {
            if captureSession.cancelStroke(contactID: contactID(for: touch)) {
                activeDisplayPoints.removeAll(keepingCapacity: true)
                activeDisplayMethod = nil
                notifyStateChanged()
                setNeedsDisplay()
                break
            }
        }
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        drawGuides(in: context)
        for stroke in captureSession.completedStrokes {
            drawStroke(
                points: stroke.points.map(canvasPoint(for:)),
                lineWidth: 5,
                in: context
            )
        }

        if !activeDisplayPoints.isEmpty {
            let width: CGFloat = activeDisplayMethod == .finger ? 7 : 4
            drawStroke(points: activeDisplayPoints, lineWidth: width, in: context)
            if activeDisplayMethod == .finger,
               let point = activeDisplayPoints.last {
                context.setFillColor(strokeColor.withAlphaComponent(0.28).cgColor)
                context.fillEllipse(in: CGRect(
                    x: point.x - 9,
                    y: point.y - 9,
                    width: 18,
                    height: 18
                ))
            }
        }
    }

    private func configureView() {
        backgroundColor = .clear
        isOpaque = false
        isMultipleTouchEnabled = true
        contentMode = .redraw
        accessibilityLabel = "마법진 입력판"
        accessibilityTraits = [.allowsDirectInteraction]
        updateAccessibilityValue()
    }

    private func notifyStateChanged() {
        updateAccessibilityValue()
        onStrokesChanged?(
            captureSession.completedStrokes,
            captureSession.activeMethod ?? captureSession.lastCompletedMethod
        )
    }

    private func updateAccessibilityValue() {
        accessibilityValue = "\(captureSession.completedStrokes.count) / \(maximumStrokeCount)획"
    }

    private func touchPriority(_ touch: UITouch) -> Int {
        touch.type == .pencil ? 1 : 0
    }

    private func inputMethod(for touch: UITouch) -> DrawingInputMethod? {
        switch touch.type {
        case .pencil:
            .pencil
        case .direct:
            .finger
        case .indirect, .indirectPointer:
            nil
        @unknown default:
            nil
        }
    }

    private func contactID(for touch: UITouch) -> Int {
        ObjectIdentifier(touch).hashValue
    }

    private func rawSample(for touch: UITouch) -> RawDrawingSample {
        let point = location(for: touch)
        return RawDrawingSample(
            x: point.x,
            y: point.y,
            timestamp: touch.timestamp
        )
    }

    private func location(for touch: UITouch) -> CGPoint {
        touch.preciseLocation(in: self)
    }

    private func canvasPoint(for point: NormalizedPoint) -> CGPoint {
        CGPoint(
            x: bounds.width * point.x / 100,
            y: bounds.height * point.y / 100
        )
    }

    private func drawGuides(in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(guideColor.cgColor)
        context.setLineWidth(1.5)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineDash(phase: 0, lengths: [5, 5])

        for guidePath in guidePaths where guidePath.count > 1 {
            let path = bezierPath(points: guidePath.map(canvasPoint(for:)))
            context.addPath(path.cgPath)
            context.strokePath()
        }
        context.restoreGState()

        context.setFillColor(guideColor.withAlphaComponent(0.8).cgColor)
        for node in guideNodes {
            let point = canvasPoint(for: node)
            context.fillEllipse(in: CGRect(
                x: point.x - 4,
                y: point.y - 4,
                width: 8,
                height: 8
            ))
        }
    }

    private func drawStroke(
        points: [CGPoint],
        lineWidth: CGFloat,
        in context: CGContext
    ) {
        guard !points.isEmpty else { return }
        let path = bezierPath(points: points)

        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(strokeColor.withAlphaComponent(0.65).cgColor)
        context.setLineWidth(lineWidth + 4)
        context.setShadow(
            offset: .zero,
            blur: 10,
            color: strokeColor.withAlphaComponent(0.85).cgColor
        )
        context.addPath(path.cgPath)
        context.strokePath()
        context.restoreGState()

        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.9).cgColor)
        context.setLineWidth(max(1.5, lineWidth * 0.35))
        context.addPath(path.cgPath)
        context.strokePath()
        context.restoreGState()
    }

    private func bezierPath(points: [CGPoint]) -> UIBezierPath {
        let path = UIBezierPath()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }
}
