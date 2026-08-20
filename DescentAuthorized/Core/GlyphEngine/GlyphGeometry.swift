import Foundation

enum GlyphGeometry {
    static func length(of points: [NormalizedPoint]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { partial, pair in
            partial + pair.0.distance(to: pair.1)
        }
    }

    static func distance(
        from point: NormalizedPoint,
        toSegmentStart start: NormalizedPoint,
        end: NormalizedPoint
    ) -> Double {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let squaredLength = dx * dx + dy * dy

        guard squaredLength > .ulpOfOne else {
            return point.distance(to: start)
        }

        let projection = ((point.x - start.x) * dx + (point.y - start.y) * dy) / squaredLength
        let t = min(max(projection, 0), 1)
        let closest = NormalizedPoint(x: start.x + t * dx, y: start.y + t * dy)
        return point.distance(to: closest)
    }

    static func distance(from point: NormalizedPoint, toPolyline polyline: [NormalizedPoint]) -> Double {
        guard polyline.count > 1 else {
            return polyline.first.map { point.distance(to: $0) } ?? .infinity
        }

        return zip(polyline, polyline.dropFirst())
            .map { distance(from: point, toSegmentStart: $0.0, end: $0.1) }
            .min() ?? .infinity
    }

    static func resample(_ points: [NormalizedPoint], spacing: Double = 1) -> [NormalizedPoint] {
        guard points.count > 1, spacing > 0 else { return points }

        var result = [points[0]]
        for (start, end) in zip(points, points.dropFirst()) {
            let segmentLength = start.distance(to: end)
            guard segmentLength > .ulpOfOne else { continue }

            let sampleCount = max(Int(segmentLength / spacing), 1)
            for index in 1...sampleCount {
                let t = min(Double(index) * spacing / segmentLength, 1)
                result.append(
                    NormalizedPoint(
                        x: start.x + (end.x - start.x) * t,
                        y: start.y + (end.y - start.y) * t
                    )
                )
            }
            if result.last != end {
                result.append(end)
            }
        }
        return result
    }

    static func weightedLength(
        of points: [NormalizedPoint],
        erasureZones: [ErasureZone]
    ) -> (total: Double, inErasureZones: Double) {
        var total = 0.0
        var inZones = 0.0

        for (start, end) in zip(points, points.dropFirst()) {
            let length = start.distance(to: end)
            let midpoint = NormalizedPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
            let multiplier = erasureZones
                .filter { $0.bounds.contains(midpoint) }
                .map(\.manaMultiplier)
                .max() ?? 1

            total += length * multiplier
            if multiplier > 1 {
                inZones += length * multiplier
            }
        }

        return (total, inZones)
    }
}

