import Foundation

struct GlyphCheckpointHit: Equatable, Sendable {
    let strokeIndex: Int
    let checkpointIndex: Int
    let position: NormalizedPoint
    let isStrokeEnd: Bool
}

/// Tracks feedback for one pen-down gesture. Casting validity remains the evaluator's job.
struct GlyphCheckpointTracker {
    private var checkpoints: [NormalizedPoint] = []
    private var strokeIndex = 0
    private var nextCheckpointIndex = 0
    private var previousPoint: NormalizedPoint?
    private var feedbackRadius = 0.0
    private var requiresExitBeforeReentry = false

    /// Required and optional nodes are displayed in the order they occur on the guide.
    /// Repeated coordinates use successive occurrences on the reference path; a node
    /// present in both lists is still only one checkpoint at each occurrence.
    static func orderedPoints(for spec: GlyphStrokeSpec) -> [NormalizedPoint] {
        let requiredCounts = spec.requiredNodes.reduce(into: [NormalizedPoint: Int]()) {
            $0[$1, default: 0] += 1
        }
        let optionalCounts = spec.optionalNodes.reduce(into: [NormalizedPoint: Int]()) {
            $0[$1, default: 0] += 1
        }
        var uniqueNodes: [NormalizedPoint] = []
        for node in spec.requiredNodes + spec.optionalNodes where !uniqueNodes.contains(node) {
            uniqueNodes.append(node)
        }

        let length = GlyphGeometry.length(of: spec.referencePath)
        var ordered: [(point: NormalizedPoint, progress: Double, sourceIndex: Int)] = []
        for (sourceIndex, node) in uniqueNodes.enumerated() {
            let occurrences = max(requiredCounts[node, default: 0], optionalCounts[node, default: 0])
            let positions = referencePositions(of: node, on: spec.referencePath)
                .filter { $0 > 0.000_001 && $0 < length - 0.000_001 }
            for position in positions.prefix(occurrences) {
                ordered.append((node, position, sourceIndex))
            }
        }
        ordered.sort {
            if abs($0.progress - $1.progress) > 0.000_001 { return $0.progress < $1.progress }
            return $0.sourceIndex < $1.sourceIndex
        }
        return [spec.start] + ordered.map(\.point) + [spec.end]
    }

    mutating func begin(
        stroke: GlyphStrokeSpec,
        strokeIndex: Int,
        at point: NormalizedPoint,
        inputMethod: DrawingInputMethod
    ) -> [GlyphCheckpointHit] {
        reset()
        let profile = DrawingInputPolicy.evaluationProfile(for: inputMethod)
        guard point.distance(to: stroke.start) <= stroke.nodeRadius * profile.nodeRadiusMultiplier else {
            // Entering the start later must not reward a gesture begun in the wrong place.
            return []
        }

        checkpoints = Self.orderedPoints(for: stroke)
        self.strokeIndex = strokeIndex
        previousPoint = point
        nextCheckpointIndex = 1
        // Keep feedback more precise than cast acceptance, while preserving finger tolerance.
        feedbackRadius = min(stroke.nodeRadius * profile.nodeRadiusMultiplier * 0.6, 6.5)
        requiresExitBeforeReentry = checkpoints[0] == checkpoints[1]
        return [hit(at: 0)]
    }

    /// Supply incremental touch samples, not the complete accumulated stroke each time.
    mutating func append(_ points: [NormalizedPoint]) -> [GlyphCheckpointHit] {
        guard var start = previousPoint else { return [] }
        var hits: [GlyphCheckpointHit] = []

        for end in points {
            defer { start = end }
            guard start.distance(to: end) > 0.000_001 else { continue }
            var minimumParameter = 0.0

            while nextCheckpointIndex < checkpoints.count {
                let target = checkpoints[nextCheckpointIndex]
                if requiresExitBeforeReentry {
                    let remainingStart = Self.interpolate(start, end, at: minimumParameter)
                    if remainingStart.distance(to: target) > feedbackRadius + 0.000_001 {
                        requiresExitBeforeReentry = false
                    } else {
                        if end.distance(to: target) > feedbackRadius + 0.000_001 {
                            requiresExitBeforeReentry = false
                        }
                        break
                    }
                }
                guard let entry = Self.entryParameter(
                    into: target,
                    radius: feedbackRadius,
                    from: start,
                    to: end,
                    after: minimumParameter
                ) else { break }

                hits.append(hit(at: nextCheckpointIndex))
                nextCheckpointIndex += 1
                minimumParameter = entry
                if nextCheckpointIndex < checkpoints.count {
                    requiresExitBeforeReentry = target == checkpoints[nextCheckpointIndex]
                }
            }
        }
        previousPoint = start
        return hits
    }

    mutating func reset() {
        checkpoints = []
        previousPoint = nil
        nextCheckpointIndex = 0
        requiresExitBeforeReentry = false
    }

    private func hit(at index: Int) -> GlyphCheckpointHit {
        GlyphCheckpointHit(
            strokeIndex: strokeIndex,
            checkpointIndex: index,
            position: checkpoints[index],
            isStrokeEnd: index == checkpoints.count - 1
        )
    }

    private static func referencePositions(
        of point: NormalizedPoint,
        on path: [NormalizedPoint]
    ) -> [Double] {
        var candidates: [(distance: Double, progress: Double)] = []
        var cumulativeLength = 0.0
        for (start, end) in zip(path, path.dropFirst()) {
            let dx = end.x - start.x
            let dy = end.y - start.y
            let length = start.distance(to: end)
            guard length > 0.000_001 else { continue }
            let projection = ((point.x - start.x) * dx + (point.y - start.y) * dy) / (length * length)
            let parameter = min(max(projection, 0), 1)
            candidates.append((
                point.distance(to: interpolate(start, end, at: parameter)),
                cumulativeLength + parameter * length
            ))
            cumulativeLength += length
        }
        guard let nearestDistance = candidates.map(\.distance).min() else { return [] }
        var result: [Double] = []
        for candidate in candidates where candidate.distance <= nearestDistance + 0.000_001 {
            if result.last.map({ abs($0 - candidate.progress) > 0.000_001 }) ?? true {
                result.append(candidate.progress)
            }
        }
        return result
    }

    private static func entryParameter(
        into center: NormalizedPoint,
        radius: Double,
        from start: NormalizedPoint,
        to end: NormalizedPoint,
        after minimum: Double
    ) -> Double? {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let a = dx * dx + dy * dy
        guard a > .ulpOfOne else { return nil }
        let offsetX = start.x - center.x
        let offsetY = start.y - center.y
        let b = 2 * (offsetX * dx + offsetY * dy)
        let c = offsetX * offsetX + offsetY * offsetY - radius * radius
        let discriminant = b * b - 4 * a * c
        guard discriminant >= 0 else { return nil }
        let root = sqrt(discriminant)
        let entry = max(minimum, max(0, (-b - root) / (2 * a)))
        let exit = min(1, (-b + root) / (2 * a))
        return entry <= exit ? entry : nil
    }

    private static func interpolate(
        _ start: NormalizedPoint,
        _ end: NormalizedPoint,
        at parameter: Double
    ) -> NormalizedPoint {
        NormalizedPoint(
            x: start.x + (end.x - start.x) * parameter,
            y: start.y + (end.y - start.y) * parameter
        )
    }
}
