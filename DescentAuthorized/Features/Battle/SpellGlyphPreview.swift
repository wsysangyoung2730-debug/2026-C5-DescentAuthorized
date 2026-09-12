import SwiftUI

/// Uses finished artwork where available and the actual casting path for new spells.
struct SpellGlyphPreview: View {
    enum Artwork: Equatable {
        case battle
        case scroll
        case path
    }

    let spell: SpellDefinition
    var artwork: Artwork = .battle
    var showsNodes = false
    var color: Color? = nil

    var body: some View {
        Group {
            if let assetName, !showsNodes {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .blendMode(artwork == .battle ? .screen : .normal)
            } else {
                pathPreview
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var pathPreview: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let lineWidth = max(1.5, min(side * 0.025, 5))
            let tint = color ?? categoryColor

            for (index, stroke) in spell.glyph.strokes.enumerated() {
                guard let first = stroke.referencePath.first else { continue }
                var path = Path()
                path.move(to: point(first, size: size))
                for node in stroke.referencePath.dropFirst() {
                    path.addLine(to: point(node, size: size))
                }
                let strokeColor = index == 0 ? tint : tint.opacity(0.72)
                context.stroke(path, with: .color(strokeColor.opacity(0.15)), lineWidth: lineWidth * 3)
                context.stroke(
                    path,
                    with: .color(strokeColor),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )

                guard showsNodes else { continue }
                for node in stroke.requiredNodes {
                    let center = point(node, size: size)
                    let diameter = lineWidth * 2.1
                    context.fill(
                        Path(ellipseIn: CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2,
                                               width: diameter, height: diameter)),
                        with: .color(DAColor.body)
                    )
                }
                let start = point(stroke.start, size: size)
                let diameter = lineWidth * 3
                context.fill(
                    Path(ellipseIn: CGRect(x: start.x - diameter / 2, y: start.y - diameter / 2,
                                           width: diameter, height: diameter)),
                    with: .color(DAColor.gold)
                )
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func point(_ node: NormalizedPoint, size: CGSize) -> CGPoint {
        let side = min(size.width, size.height) * 0.9
        return CGPoint(
            x: (size.width - side) / 2 + side * node.x / 100,
            y: (size.height - side) / 2 + side * node.y / 100
        )
    }

    private var assetName: String? {
        guard artwork != .path else { return nil }
        let suffix: String
        switch spell.id {
        case .afterglowErasure: suffix = "AfterglowErasure"
        case .riftSeverance: suffix = "RiftSeverance"
        case .barrierPiercing: suffix = "BarrierPiercing"
        case .basicBarrier: suffix = "BasicBarrier"
        case .sealRelease: suffix = "SealRelease"
        default: return nil
        }
        return artwork == .scroll ? "ScrollLearningGlyph\(suffix)" : "BattleGlyph\(suffix)"
    }

    private var categoryColor: Color {
        switch spell.category {
        case .attack: DAColor.attack
        case .defense: DAColor.defense
        case .dispel: DAColor.dispel
        case .debuff: DAColor.debuff
        }
    }
}

extension SpellDefinition {
    /// Small-card copy with meaningful units for effects that do not deal direct damage.
    var compactEffectDescription: String {
        let range = effect.range
        let amount = range.lowerBound == range.upperBound
            ? "\(range.lowerBound)"
            : "\(range.lowerBound)~\(range.upperBound)"
        switch effect {
        case .damage: return "공격 \(amount)"
        case .fixedBarrier: return "방벽 \(amount)"
        case .dispelAbsoluteBarrier: return "해제 \(amount)회"
        case let .expansion(expansion):
            switch expansion {
            case .chainInscription, .axisSeverance, .advanceVerdict, .memorySeverance:
                return "공격 \(amount)"
            case .purificationGlyph: return "상태 1개 해제"
            case .lingeringBarrier, .anchorGuard: return "방벽 \(amount)"
            case .consequenceErasure: return "예약·방벽 말소"
            case .outputReduction: return "피해 -25%"
            case .executionDelay: return "예약 +1턴"
            case .causalCushion: return "예약 피해 -30%"
            case .memorySuture: return "회복 8 · 방벽"
            case .mimicProhibition: return "모사 차단 2턴"
            }
        }
    }
}
