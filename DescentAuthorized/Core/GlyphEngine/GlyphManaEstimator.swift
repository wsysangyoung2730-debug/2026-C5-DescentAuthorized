import Foundation

struct GlyphManaEstimate: Equatable, Sendable {
    let total: Double
    let inErasureZones: Double
}

struct GlyphManaEstimator: Sendable {
    func estimate(
        spell: SpellDefinition,
        strokes: [DrawnStroke],
        erasureZones: [ErasureZone] = []
    ) -> GlyphManaEstimate {
        let referenceLength = spell.glyph.strokes.reduce(0) {
            $0 + GlyphGeometry.length(of: $1.referencePath)
        }
        guard referenceLength > 0 else {
            return GlyphManaEstimate(total: spell.recommendedMana, inErasureZones: 0)
        }

        let weighted = strokes.reduce(into: (total: 0.0, inZones: 0.0)) { result, stroke in
            let length = GlyphGeometry.weightedLength(
                of: stroke.points,
                erasureZones: erasureZones
            )
            result.total += length.total
            result.inZones += length.inErasureZones
        }
        let scale = spell.recommendedMana / referenceLength
        return GlyphManaEstimate(
            total: weighted.total * scale,
            inErasureZones: weighted.inZones * scale
        )
    }
}
