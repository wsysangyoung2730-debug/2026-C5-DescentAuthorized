import SwiftUI

private struct GlyphInputSuspendedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isGlyphInputSuspended: Bool {
        get { self[GlyphInputSuspendedKey.self] }
        set { self[GlyphInputSuspendedKey.self] = newValue }
    }
}

/// Decorations only: the reference playback never becomes a captured player stroke.
struct GlyphInputFeedbackOverlay: View {
    let glyph: GlyphDefinition
    let frame: GlyphDemonstrationFrame?
    let nextStrokeIndex: Int
    let checkpoint: GlyphCheckpointHit?
    let color: Color
    let showsStartNumbers: Bool
    let reducesFlashes: Bool

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Canvas { context, canvasSize in
                    if let frame {
                        for (index, points) in frame.visibleStrokes.enumerated() {
                            guard let first = points.first else { continue }
                            var path = Path()
                            path.move(to: point(first, in: canvasSize))
                            for sample in points.dropFirst() {
                                path.addLine(to: point(sample, in: canvasSize))
                            }
                            let isCurrent = index == frame.strokeIndex
                            context.stroke(
                                path,
                                with: .color(color.opacity(isCurrent ? 0.2 : 0.08)),
                                style: StrokeStyle(lineWidth: 13, lineCap: .round, lineJoin: .round)
                            )
                            context.stroke(
                                path,
                                with: .color(color.opacity(isCurrent ? 0.95 : 0.45)),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                            )
                        }
                        if let cursor = frame.cursor {
                            let center = point(cursor, in: canvasSize)
                            context.fill(
                                Path(ellipseIn: CGRect(x: center.x - 10, y: center.y - 10, width: 20, height: 20)),
                                with: .color(color.opacity(0.35))
                            )
                            context.fill(
                                Path(ellipseIn: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)),
                                with: .color(.white)
                            )
                        }
                    }
                    if let checkpoint {
                        let center = point(checkpoint.position, in: canvasSize)
                        context.stroke(
                            Path(ellipseIn: CGRect(x: center.x - 10, y: center.y - 10, width: 20, height: 20)),
                            with: .color(color.opacity(reducesFlashes ? 0.65 : 1)),
                            lineWidth: reducesFlashes ? 1.5 : 2
                        )
                        if !reducesFlashes {
                            context.fill(
                                Path(ellipseIn: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)),
                                with: .color(.white)
                            )
                        }
                    }
                }

                if showsStartNumbers {
                    ForEach(glyph.strokes.indices, id: \.self) { index in
                        startBadge(index: index, in: size)
                    }
                }
            }
            .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func startBadge(index: Int, in size: CGSize) -> some View {
        let active = index == (frame?.strokeIndex ?? nextStrokeIndex)
        let start = point(glyph.strokes[index].start, in: size)
        let x: CGFloat = min(max(start.x - 18, 13), max(13, size.width - 13))
        let y: CGFloat = min(max(start.y - 18, 13), max(13, size.height - 13))
        let foreground: Color = active ? .black : .white.opacity(0.65)
        let background: Color = active ? color : .black.opacity(0.85)

        return Text("\(index + 1)")
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(foreground)
            .frame(width: 24, height: 24)
            .background(background, in: Circle())
            .overlay { Circle().stroke(color.opacity(active ? 1 : 0.4), lineWidth: 1) }
            .position(x: x, y: y)
    }

    private func point(_ point: NormalizedPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x / 100 * size.width, y: point.y / 100 * size.height)
    }
}
