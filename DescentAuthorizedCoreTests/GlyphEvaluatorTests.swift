import XCTest
@testable import DescentAuthorizedCore

final class GlyphEvaluatorTests: XCTestCase {
    private let evaluator = GlyphEvaluator()

    func testReferencePathsProducePerfectCastForEverySpell() {
        for spell in SpellCatalog.all.values {
            let result = evaluator.evaluate(
                spell: spell,
                strokes: referenceStrokes(for: spell),
                inputMethod: .pencil
            )

            XCTAssertEqual(result.grade, .perfect, "Expected perfect cast for \(spell.name), got \(result)")
            XCTAssertNil(result.failure)
            XCTAssertEqual(result.manaUsed, spell.recommendedMana, accuracy: 0.001)
        }
    }

    func testFingerReferencePathsCanAlsoProducePerfectCast() {
        for spell in SpellCatalog.all.values {
            let result = evaluator.evaluate(
                spell: spell,
                strokes: referenceStrokes(for: spell),
                inputMethod: .finger
            )

            XCTAssertEqual(result.grade, .perfect, "Expected finger perfect cast for \(spell.name)")
            XCTAssertNil(result.failure)
        }
    }

    func testFingerReceivesSmallStartPointTolerance() {
        let spell = SpellCatalog.afterglowErasure
        var points = spell.glyph.strokes[0].referencePath
        points[0] = NormalizedPoint(x: points[0].x + 6.5, y: points[0].y)

        let pencil = evaluator.evaluate(
            spell: spell,
            strokes: [DrawnStroke(points: points)],
            inputMethod: .pencil
        )
        let finger = evaluator.evaluate(
            spell: spell,
            strokes: [DrawnStroke(points: points)],
            inputMethod: .finger
        )

        XCTAssertEqual(pencil.failure, .invalidStart)
        XCTAssertNotEqual(finger.failure, .invalidStart)
    }

    func testFingerStillRejectsMissingRequiredNodes() {
        let spell = SpellCatalog.riftSeverance
        let result = evaluator.evaluate(
            spell: spell,
            strokes: [
                DrawnStroke(points: [
                    spell.glyph.strokes[0].start,
                    NormalizedPoint(x: 20, y: 50),
                    spell.glyph.strokes[0].end
                ])
            ],
            inputMethod: .finger
        )

        XCTAssertEqual(result.grade, .rejected)
        XCTAssertEqual(result.failure, .missingRequiredNode)
    }

    func testWrongStrokeCountIsRejected() {
        let spell = SpellCatalog.barrierPiercing
        let result = evaluator.evaluate(
            spell: spell,
            strokes: [referenceStrokes(for: spell)[0]],
            inputMethod: .pencil
        )

        XCTAssertEqual(result.grade, .rejected)
        XCTAssertEqual(result.failure, .wrongStrokeCount)
    }

    func testMissingRequiredNodeIsRejected() {
        let spell = SpellCatalog.riftSeverance
        let result = evaluator.evaluate(
            spell: spell,
            strokes: [
                DrawnStroke(points: [
                    spell.glyph.strokes[0].start,
                    NormalizedPoint(x: 20, y: 50),
                    spell.glyph.strokes[0].end
                ])
            ],
            inputMethod: .pencil
        )

        XCTAssertEqual(result.grade, .rejected)
        XCTAssertEqual(result.failure, .missingRequiredNode)
    }

    func testDetourConsumesMoreManaThanReferencePath() {
        let spell = SpellCatalog.afterglowErasure
        let reference = evaluator.evaluate(
            spell: spell,
            strokes: referenceStrokes(for: spell),
            inputMethod: .pencil
        )
        var points = spell.glyph.strokes[0].referencePath
        points.insert(NormalizedPoint(x: 5, y: 95), at: 1)
        let detour = evaluator.evaluate(
            spell: spell,
            strokes: [DrawnStroke(points: points)],
            inputMethod: .pencil
        )

        XCTAssertGreaterThan(detour.manaUsed, reference.manaUsed)
    }

    func testErasureZoneIncreasesManaConsumption() {
        let spell = SpellCatalog.afterglowErasure
        let strokes = referenceStrokes(for: spell)
        let normal = evaluator.evaluate(spell: spell, strokes: strokes, inputMethod: .pencil)
        let erased = evaluator.evaluate(
            spell: spell,
            strokes: strokes,
            inputMethod: .pencil,
            erasureZones: [
                ErasureZone(
                    id: "full-board",
                    bounds: NormalizedRect(minX: 0, minY: 0, maxX: 100, maxY: 100)
                )
            ]
        )

        XCTAssertGreaterThan(erased.manaUsed, normal.manaUsed)
        XCTAssertGreaterThan(erased.manaUsedInErasureZones, 0)
    }

    func testMissingOptionalHookCapsAfterglowAtIncomplete() {
        let spell = SpellCatalog.afterglowErasure
        let path = spell.glyph.strokes[0].referencePath
        let withoutHook = [path[0], path[1], path[2], path[4]]
        let result = evaluator.evaluate(
            spell: spell,
            strokes: [DrawnStroke(points: withoutHook)],
            inputMethod: .pencil
        )

        XCTAssertLessThanOrEqual(result.grade, .incomplete)
    }

    private func referenceStrokes(for spell: SpellDefinition) -> [DrawnStroke] {
        spell.glyph.strokes.map { DrawnStroke(points: $0.referencePath) }
    }
}
