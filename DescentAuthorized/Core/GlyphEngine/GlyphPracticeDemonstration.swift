import Foundation

struct GlyphDemonstrationFrame: Equatable, Sendable {
    let strokeIndex: Int
    let visibleStrokes: [[NormalizedPoint]]
    let cursor: NormalizedPoint?
    let isLifting: Bool
    let isComplete: Bool
}

/// A display-only reference playback. Its paths never enter the player's capture session.
struct GlyphPracticeDemonstration: Sendable {
    let glyph: GlyphDefinition
    var reducedMotion = false

    private let startHold: TimeInterval = 0.45
    private let liftHold: TimeInterval = 0.55

    var duration: TimeInterval {
        glyph.strokes.reduce(0) { $0 + startHold + drawingDuration(for: $1) + liftHold }
    }

    func frame(at elapsed: TimeInterval) -> GlyphDemonstrationFrame {
        var remaining = max(0, elapsed.isFinite ? elapsed : 0)
        if remaining >= duration {
            return GlyphDemonstrationFrame(
                strokeIndex: max(0, glyph.strokes.count - 1),
                visibleStrokes: glyph.strokes.map(\.referencePath),
                cursor: nil, isLifting: false, isComplete: true
            )
        }
        var visible: [[NormalizedPoint]] = []

        for (index, stroke) in glyph.strokes.enumerated() {
            let drawingDuration = drawingDuration(for: stroke)
            let strokeDuration = startHold + drawingDuration + liftHold
            if remaining < strokeDuration {
                let progress = min(max((remaining - startHold) / drawingDuration, 0), 1)
                let isLifting = remaining >= startHold + drawingDuration
                let points: [NormalizedPoint]
                if reducedMotion {
                    points = remaining < startHold ? [stroke.start] : stroke.referencePath
                } else {
                    points = prefix(of: stroke.referencePath, progress: progress)
                }
                visible.append(points)
                return GlyphDemonstrationFrame(
                    strokeIndex: index,
                    visibleStrokes: visible,
                    cursor: reducedMotion || isLifting ? nil : points.last,
                    isLifting: isLifting,
                    isComplete: false
                )
            }
            visible.append(stroke.referencePath)
            remaining -= strokeDuration
        }

        return GlyphDemonstrationFrame(
            strokeIndex: max(0, glyph.strokes.count - 1),
            visibleStrokes: visible,
            cursor: nil,
            isLifting: false,
            isComplete: true
        )
    }

    private func drawingDuration(for stroke: GlyphStrokeSpec) -> TimeInterval {
        reducedMotion ? 0.8 : min(max(GlyphGeometry.length(of: stroke.referencePath) / 70, 1.35), 3)
    }

    private func prefix(of points: [NormalizedPoint], progress: Double) -> [NormalizedPoint] {
        guard let first = points.first else { return [] }
        guard progress < 1 else { return points }
        var remaining = GlyphGeometry.length(of: points) * progress
        var result = [first]
        for (start, end) in zip(points, points.dropFirst()) {
            let distance = start.distance(to: end)
            guard distance > .ulpOfOne else { continue }
            if remaining >= distance {
                result.append(end)
                remaining -= distance
            } else {
                let fraction = remaining / distance
                result.append(NormalizedPoint(
                    x: start.x + (end.x - start.x) * fraction,
                    y: start.y + (end.y - start.y) * fraction
                ))
                break
            }
        }
        return result
    }
}
