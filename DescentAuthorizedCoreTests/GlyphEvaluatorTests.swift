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

    func testRelaxedStartPointToleranceAcceptsPencilAndFinger() {
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

        XCTAssertNotEqual(pencil.failure, .invalidStart)
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

    func testBarrierPiercingAcceptsSmallDrawingDeviation() {
        let spell = SpellCatalog.barrierPiercing
        let strokes = referenceStrokes(for: spell).map { stroke in
            DrawnStroke(points: stroke.points.map {
                NormalizedPoint(x: $0.x + 2.5, y: $0.y + 2)
            })
        }
        let result = evaluator.evaluate(
            spell: spell,
            strokes: strokes,
            inputMethod: .pencil
        )

        XCTAssertTrue(result.succeeded)
        XCTAssertNil(result.failure)
    }

    func testBarrierPiercingRisesRightThenLoopsLeftAndCrossesItsFirstPass() {
        let spell = SpellCatalog.barrierPiercing
        let firstStroke = DrawnStroke(points: [
            (24.0, 72.0), (30, 63), (37, 54),
            (44, 45), (50, 34), (55, 23),
            (59, 14), (57, 8), (51, 6),
            (44, 10), (40, 18), (37, 30),
            (36, 43), (37, 54), (40, 63),
            (43, 69), (49, 74), (56, 78),
            (62, 79), (69, 77), (76, 72)
        ].map { NormalizedPoint(x: $0.0, y: $0.1) })
        let secondStroke = DrawnStroke(points: spell.glyph.strokes[1].referencePath)

        for method in [DrawingInputMethod.pencil, .finger] {
            let result = evaluator.evaluate(
                spell: spell,
                strokes: [firstStroke, secondStroke],
                inputMethod: method
            )
            XCTAssertTrue(result.succeeded, "Expected right-first loop to succeed with \(method)")
            XCTAssertEqual(result.grade, .perfect)
            XCTAssertNil(result.failure)
        }
    }

    func testBarrierPiercingRejectsThePreviousLeftFirstLoopDirection() {
        let spell = SpellCatalog.barrierPiercing
        let oldFirstStroke = DrawnStroke(points: [
            (24.0, 72.0), (30, 63), (37, 54),
            (36, 43), (37, 30), (40, 18),
            (44, 10), (51, 6), (57, 8),
            (59, 14), (57, 25), (54, 37),
            (50, 47), (44, 56), (32, 58),
            (43, 69), (49, 74), (56, 78),
            (62, 79), (69, 77), (76, 72)
        ].map { NormalizedPoint(x: $0.0, y: $0.1) })
        let secondStroke = DrawnStroke(points: spell.glyph.strokes[1].referencePath)

        for method in [DrawingInputMethod.pencil, .finger] {
            let result = evaluator.evaluate(
                spell: spell,
                strokes: [oldFirstStroke, secondStroke],
                inputMethod: method
            )
            XCTAssertEqual(result.grade, .rejected, "The old loop must not pass with \(method)")
            XCTAssertEqual(result.failure, .missingRequiredNode)
        }
    }

    func testFasterCastProducesStrongerEffectAtSameAccuracy() {
        let spell = SpellCatalog.barrierPiercing
        let fast = evaluator.evaluate(
            spell: spell,
            strokes: referenceStrokes(for: spell, duration: 0.7),
            inputMethod: .pencil
        )
        let slow = evaluator.evaluate(
            spell: spell,
            strokes: referenceStrokes(for: spell, duration: 4),
            inputMethod: .pencil
        )

        XCTAssertTrue(fast.succeeded)
        XCTAssertTrue(slow.succeeded)
        XCTAssertGreaterThan(fast.breakdown.speed, slow.breakdown.speed)
        XCTAssertGreaterThan(fast.effectStrength, slow.effectStrength)
    }

    func testRelaxedToleranceAcceptsImperfectGlyphWithReducedEffect() {
        let spell = SpellCatalog.afterglowErasure
        let imperfect = DrawnStroke(points: spell.glyph.strokes[0].referencePath.map {
            NormalizedPoint(x: $0.x + 6, y: $0.y + 4)
        }, duration: 1)
        let result = evaluator.evaluate(
            spell: spell,
            strokes: [imperfect],
            inputMethod: .pencil
        )

        XCTAssertTrue(result.succeeded)
        XCTAssertLessThan(result.effectStrength, 1)
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

    private func referenceStrokes(
        for spell: SpellDefinition,
        duration: TimeInterval? = nil
    ) -> [DrawnStroke] {
        spell.glyph.strokes.map {
            DrawnStroke(points: $0.referencePath, duration: duration)
        }
    }
}
