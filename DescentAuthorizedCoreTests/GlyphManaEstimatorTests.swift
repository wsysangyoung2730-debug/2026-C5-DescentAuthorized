import XCTest
@testable import DescentAuthorizedCore

final class GlyphManaEstimatorTests: XCTestCase {
    private let estimator = GlyphManaEstimator()

    func testReferencePathUsesRecommendedMana() {
        let spell = SpellCatalog.riftSeverance

        let estimate = estimator.estimate(
            spell: spell,
            strokes: spell.glyph.strokes.map { DrawnStroke(points: $0.referencePath) }
        )

        XCTAssertEqual(estimate.total, spell.recommendedMana, accuracy: 0.001)
        XCTAssertEqual(estimate.inErasureZones, 0)
    }

    func testLivePartialPathUsesLessManaThanCompletePath() {
        let spell = SpellCatalog.afterglowErasure
        let reference = spell.glyph.strokes[0].referencePath

        let partial = estimator.estimate(
            spell: spell,
            strokes: [DrawnStroke(points: Array(reference.prefix(3)))]
        )
        let complete = estimator.estimate(
            spell: spell,
            strokes: [DrawnStroke(points: reference)]
        )

        XCTAssertGreaterThan(partial.total, 0)
        XCTAssertLessThan(partial.total, complete.total)
    }

    func testErasureZoneCostIsReportedSeparately() {
        let spell = SpellCatalog.basicBarrier
        let estimate = estimator.estimate(
            spell: spell,
            strokes: [DrawnStroke(points: spell.glyph.strokes[0].referencePath)],
            erasureZones: [
                ErasureZone(
                    id: "entire-canvas",
                    bounds: NormalizedRect(minX: 0, minY: 0, maxX: 100, maxY: 100),
                    manaMultiplier: 2
                )
            ]
        )

        XCTAssertEqual(estimate.total, spell.recommendedMana * 2, accuracy: 0.001)
        XCTAssertEqual(estimate.inErasureZones, estimate.total, accuracy: 0.001)
    }
}
