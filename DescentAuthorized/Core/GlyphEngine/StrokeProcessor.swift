import Foundation

struct DrawingCanvasSize: Equatable, Sendable {
    let width: Double
    let height: Double

    var isValid: Bool {
        width.isFinite && height.isFinite && width > 0 && height > 0
    }
}

struct RawDrawingSample: Equatable, Sendable {
    let x: Double
    let y: Double
    let timestamp: TimeInterval

    init(x: Double, y: Double, timestamp: TimeInterval = 0) {
        self.x = x
        self.y = y
        self.timestamp = timestamp
    }

    var isFinite: Bool {
        x.isFinite && y.isFinite && timestamp.isFinite
    }
}

struct StrokeProcessingProfile: Equatable, Sendable {
    let minimumPointDistance: Double
    let neighborSmoothingWeight: Double

    static func profile(for method: DrawingInputMethod) -> StrokeProcessingProfile {
        switch method {
        case .pencil:
            StrokeProcessingProfile(
                minimumPointDistance: 0.08,
                neighborSmoothingWeight: 0.08
            )
        case .finger:
            StrokeProcessingProfile(
                minimumPointDistance: 0.25,
                neighborSmoothingWeight: 0.2
            )
        }
    }
}

enum StrokeProcessingError: Error, Equatable {
    case invalidCanvasSize
    case noValidSamples
}

struct StrokeProcessor: Sendable {
    func process(
        samples: [RawDrawingSample],
        canvasSize: DrawingCanvasSize,
        method: DrawingInputMethod
    ) throws -> DrawnStroke {
        guard canvasSize.isValid else {
            throw StrokeProcessingError.invalidCanvasSize
        }

        let normalized = normalize(samples, canvasSize: canvasSize)
        guard !normalized.isEmpty else {
            throw StrokeProcessingError.noValidSamples
        }

        let profile = StrokeProcessingProfile.profile(for: method)
        let reduced = removeNearDuplicates(
            normalized,
            minimumDistance: profile.minimumPointDistance
        )
        return DrawnStroke(points: smooth(
            reduced,
            neighborWeight: profile.neighborSmoothingWeight
        ))
    }

    private func normalize(
        _ samples: [RawDrawingSample],
        canvasSize: DrawingCanvasSize
    ) -> [NormalizedPoint] {
        var lastTimestamp = -Double.infinity
        return samples.compactMap { sample in
            guard sample.isFinite, sample.timestamp >= lastTimestamp else {
                return nil
            }
            lastTimestamp = sample.timestamp
            let x = min(max(sample.x, 0), canvasSize.width) / canvasSize.width * 100
            let y = min(max(sample.y, 0), canvasSize.height) / canvasSize.height * 100
            return NormalizedPoint(x: x, y: y)
        }
    }

    private func removeNearDuplicates(
        _ points: [NormalizedPoint],
        minimumDistance: Double
    ) -> [NormalizedPoint] {
        guard let first = points.first, points.count > 1 else { return points }

        var result = [first]
        for point in points.dropFirst().dropLast() {
            if result.last?.distance(to: point) ?? .infinity >= minimumDistance {
                result.append(point)
            }
        }

        guard let last = points.last else { return result }
        if result.count == 1 {
            if result[0] != last {
                result.append(last)
            }
        } else if result.last?.distance(to: last) ?? .infinity < minimumDistance {
            result[result.count - 1] = last
        } else {
            result.append(last)
        }
        return result
    }

    private func smooth(
        _ points: [NormalizedPoint],
        neighborWeight: Double
    ) -> [NormalizedPoint] {
        guard points.count >= 3, neighborWeight > 0 else { return points }
        precondition(neighborWeight < 0.5)

        var result = points
        let centerWeight = 1 - neighborWeight * 2
        for index in 1..<(points.count - 1) {
            result[index] = NormalizedPoint(
                x: points[index - 1].x * neighborWeight
                    + points[index].x * centerWeight
                    + points[index + 1].x * neighborWeight,
                y: points[index - 1].y * neighborWeight
                    + points[index].y * centerWeight
                    + points[index + 1].y * neighborWeight
            )
        }
        return result
    }
}

enum StrokeCaptureStartResult: Equatable, Sendable {
    case started
    case replacedFingerWithPencil
}

enum StrokeCaptureError: Error, Equatable {
    case inputRejected(DrawingInputMethod)
    case strokeLimitReached(Int)
    case strokeAlreadyActive
    case noActiveStroke
    case contactMismatch
}

struct StrokeCaptureSession: Sendable {
    private struct ActiveStroke: Sendable {
        let contactID: Int
        let method: DrawingInputMethod
        var samples: [RawDrawingSample]
    }

    private(set) var completedStrokes: [DrawnStroke]
    private(set) var completedInputMethods: [DrawingInputMethod]
    private(set) var inputPreference: DrawingInputPreference
    let maximumStrokeCount: Int

    private var activeStroke: ActiveStroke?
    private let processor: StrokeProcessor

    init(
        inputPreference: DrawingInputPreference = .automatic,
        maximumStrokeCount: Int = 2,
        completedStrokes: [DrawnStroke] = [],
        completedInputMethods: [DrawingInputMethod] = [],
        processor: StrokeProcessor = StrokeProcessor()
    ) {
        precondition(maximumStrokeCount > 0)
        precondition(completedStrokes.count <= maximumStrokeCount)
        precondition(completedStrokes.count == completedInputMethods.count)
        self.inputPreference = inputPreference
        self.maximumStrokeCount = maximumStrokeCount
        self.completedStrokes = completedStrokes
        self.completedInputMethods = completedInputMethods
        self.processor = processor
    }

    var activeMethod: DrawingInputMethod? { activeStroke?.method }
    var activeContactID: Int? { activeStroke?.contactID }
    var hasActiveStroke: Bool { activeStroke != nil }
    var remainingStrokeCount: Int { maximumStrokeCount - completedStrokes.count }
    var lastCompletedMethod: DrawingInputMethod? { completedInputMethods.last }

    mutating func updateInputPreference(_ preference: DrawingInputPreference) {
        guard preference != inputPreference else { return }
        inputPreference = preference
        activeStroke = nil
    }

    mutating func beginStroke(
        contactID: Int,
        method: DrawingInputMethod,
        sample: RawDrawingSample
    ) throws -> StrokeCaptureStartResult {
        let policy = DrawingInputPolicy(preference: inputPreference)
        guard policy.accepts(method) else {
            throw StrokeCaptureError.inputRejected(method)
        }
        guard completedStrokes.count < maximumStrokeCount else {
            throw StrokeCaptureError.strokeLimitReached(maximumStrokeCount)
        }

        if let activeStroke {
            let pencilTakesPriority = inputPreference == .automatic
                && activeStroke.method == .finger
                && method == .pencil
            guard pencilTakesPriority else {
                throw StrokeCaptureError.strokeAlreadyActive
            }
            self.activeStroke = ActiveStroke(
                contactID: contactID,
                method: method,
                samples: [sample]
            )
            return .replacedFingerWithPencil
        }

        activeStroke = ActiveStroke(
            contactID: contactID,
            method: method,
            samples: [sample]
        )
        return .started
    }

    mutating func appendSamples(
        contactID: Int,
        samples: [RawDrawingSample]
    ) throws {
        guard var activeStroke else {
            throw StrokeCaptureError.noActiveStroke
        }
        guard activeStroke.contactID == contactID else {
            throw StrokeCaptureError.contactMismatch
        }
        activeStroke.samples.append(contentsOf: samples)
        self.activeStroke = activeStroke
    }

    @discardableResult
    mutating func endStroke(
        contactID: Int,
        finalSamples: [RawDrawingSample],
        canvasSize: DrawingCanvasSize
    ) throws -> DrawnStroke {
        guard var activeStroke else {
            throw StrokeCaptureError.noActiveStroke
        }
        guard activeStroke.contactID == contactID else {
            throw StrokeCaptureError.contactMismatch
        }

        activeStroke.samples.append(contentsOf: finalSamples)
        self.activeStroke = nil
        let stroke = try processor.process(
            samples: activeStroke.samples,
            canvasSize: canvasSize,
            method: activeStroke.method
        )
        completedStrokes.append(stroke)
        completedInputMethods.append(activeStroke.method)
        return stroke
    }

    @discardableResult
    mutating func cancelStroke(contactID: Int) -> Bool {
        guard activeStroke?.contactID == contactID else { return false }
        activeStroke = nil
        return true
    }

    @discardableResult
    mutating func undoLastStroke() -> DrawnStroke? {
        guard !completedStrokes.isEmpty else { return nil }
        completedInputMethods.removeLast()
        return completedStrokes.removeLast()
    }

    mutating func clear() {
        activeStroke = nil
        completedStrokes.removeAll(keepingCapacity: true)
        completedInputMethods.removeAll(keepingCapacity: true)
    }
}
