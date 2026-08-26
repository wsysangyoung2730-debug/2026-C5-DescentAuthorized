import UIKit

@MainActor
final class RuneDrawingCanvasView: UIView {
    var onDrawingChanged: ((RuneDrawingState) -> Void)?
    var onInputRejected: ((StrokeCaptureError) -> Void)?

    private(set) var inputPreference: DrawingInputPreference
    private(set) var maximumStrokeCount: Int

    var guidePaths: [[NormalizedPoint]] = [] {
        didSet { setNeedsDisplay() }
    }

    var guideNodes: [NormalizedPoint] = [] {
        didSet { setNeedsDisplay() }
    }

    var erasureZones: [ErasureZone] = [] {
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
                notifyStateChanged()
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

        drawErasureZones(in: context)
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
        let activeStroke = activeDisplayPoints.isEmpty
            ? nil
            : DrawnStroke(points: activeDisplayPoints.map(normalizedPoint(for:)))
        onDrawingChanged?(
            RuneDrawingState(
                completedStrokes: captureSession.completedStrokes,
                activeStroke: activeStroke,
                inputMethod: captureSession.activeMethod ?? captureSession.lastCompletedMethod
            )
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

    private func normalizedPoint(for point: CGPoint) -> NormalizedPoint {
        guard bounds.width > 0, bounds.height > 0 else {
            return NormalizedPoint(x: 0, y: 0)
        }
        return NormalizedPoint(
            x: min(max(point.x / bounds.width * 100, 0), 100),
            y: min(max(point.y / bounds.height * 100, 0), 100)
        )
    }

    private func drawErasureZones(in context: CGContext) {
        for zone in erasureZones {
            let topLeft = canvasPoint(for: NormalizedPoint(
                x: zone.bounds.minX,
                y: zone.bounds.minY
            ))
            let bottomRight = canvasPoint(for: NormalizedPoint(
                x: zone.bounds.maxX,
                y: zone.bounds.maxY
            ))
            let zoneRect = CGRect(
                x: topLeft.x,
                y: topLeft.y,
                width: bottomRight.x - topLeft.x,
                height: bottomRight.y - topLeft.y
            )

            context.saveGState()
            context.setFillColor(UIColor.systemRed.withAlphaComponent(0.1).cgColor)
            context.fill(zoneRect)
            context.setStrokeColor(UIColor.systemRed.withAlphaComponent(0.45).cgColor)
            context.setLineWidth(1)
            context.setLineDash(phase: 0, lengths: [4, 5])
            context.stroke(zoneRect.insetBy(dx: 0.5, dy: 0.5))
            context.restoreGState()
        }
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

        let endpoints = Set(guidePaths.flatMap { path in
            [path.first, path.last].compactMap { $0 }
        })
        context.setFillColor(guideColor.withAlphaComponent(0.8).cgColor)
        for node in guideNodes where !endpoints.contains(node) {
            let point = canvasPoint(for: node)
            context.fillEllipse(in: CGRect(
                x: point.x - 4,
                y: point.y - 4,
                width: 8,
                height: 8
            ))
        }

        for guidePath in guidePaths where guidePath.count > 1 {
            let points = guidePath.map(canvasPoint(for:))
            guard let start = points.first, let end = points.last else { continue }
            drawStartMarker(at: start, in: context)
            drawEndMarker(at: end, in: context)
            drawDirectionArrow(from: start, along: points, in: context)
        }
    }

    private func drawStartMarker(at point: CGPoint, in context: CGContext) {
        context.saveGState()
        context.setFillColor(strokeColor.withAlphaComponent(0.32).cgColor)
        context.fillEllipse(in: CGRect(
            x: point.x - 7,
            y: point.y - 7,
            width: 14,
            height: 14
        ))
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.92).cgColor)
        context.setLineWidth(2)
        context.strokeEllipse(in: CGRect(
            x: point.x - 6,
            y: point.y - 6,
            width: 12,
            height: 12
        ))
        context.setFillColor(UIColor.white.withAlphaComponent(0.95).cgColor)
        context.fillEllipse(in: CGRect(
            x: point.x - 2.5,
            y: point.y - 2.5,
            width: 5,
            height: 5
        ))
        context.restoreGState()
    }

    private func drawEndMarker(at point: CGPoint, in context: CGContext) {
        let radius: CGFloat = 7
        let diamond = CGMutablePath()
        diamond.move(to: CGPoint(x: point.x, y: point.y - radius))
        diamond.addLine(to: CGPoint(x: point.x + radius, y: point.y))
        diamond.addLine(to: CGPoint(x: point.x, y: point.y + radius))
        diamond.addLine(to: CGPoint(x: point.x - radius, y: point.y))
        diamond.closeSubpath()

        context.saveGState()
        context.setFillColor(guideColor.withAlphaComponent(0.28).cgColor)
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.9).cgColor)
        context.setLineWidth(2)
        context.addPath(diamond)
        context.drawPath(using: .fillStroke)
        context.restoreGState()
    }

    private func drawDirectionArrow(
        from start: CGPoint,
        along points: [CGPoint],
        in context: CGContext
    ) {
        guard let next = points.dropFirst().first(where: {
            hypot($0.x - start.x, $0.y - start.y) > 3
        }) else { return }

        let deltaX = next.x - start.x
        let deltaY = next.y - start.y
        let segmentLength = hypot(deltaX, deltaY)
        guard segmentLength > 0 else { return }

        let unitX = deltaX / segmentLength
        let unitY = deltaY / segmentLength
        let tipDistance = min(20, segmentLength * 0.72)
        guard tipDistance >= 5 else { return }
        let tailDistance = min(8, tipDistance * 0.35)
        let tail = CGPoint(
            x: start.x + (unitX * tailDistance),
            y: start.y + (unitY * tailDistance)
        )
        let tip = CGPoint(
            x: start.x + (unitX * tipDistance),
            y: start.y + (unitY * tipDistance)
        )
        let headLength = min(6, tipDistance * 0.3)
        let headWidth = headLength * 0.67
        let headBase = CGPoint(
            x: tip.x - (unitX * headLength),
            y: tip.y - (unitY * headLength)
        )
        let perpendicularX = -unitY
        let perpendicularY = unitX

        let arrow = CGMutablePath()
        arrow.move(to: tail)
        arrow.addLine(to: tip)
        arrow.move(to: tip)
        arrow.addLine(to: CGPoint(
            x: headBase.x + (perpendicularX * headWidth),
            y: headBase.y + (perpendicularY * headWidth)
        ))
        arrow.move(to: tip)
        arrow.addLine(to: CGPoint(
            x: headBase.x - (perpendicularX * headWidth),
            y: headBase.y - (perpendicularY * headWidth)
        ))

        context.saveGState()
        context.setStrokeColor(strokeColor.withAlphaComponent(0.95).cgColor)
        context.setLineWidth(2)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setShadow(
            offset: .zero,
            blur: 4,
            color: strokeColor.withAlphaComponent(0.6).cgColor
        )
        context.addPath(arrow)
        context.strokePath()
        context.restoreGState()
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
