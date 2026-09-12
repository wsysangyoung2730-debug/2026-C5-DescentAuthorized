import XCTest
@testable import DescentAuthorizedCore

final class GlyphPracticeDemonstrationTests: XCTestCase {
    func testFirstStrokeHoldsAtItsStartBeforeDrawing() {
        let glyph = SpellCatalog.barrierPiercing.glyph
        let demonstration = GlyphPracticeDemonstration(glyph: glyph)
        for elapsed in [0.0, 0.2, 0.44] {
            let frame = demonstration.frame(at: elapsed)
            XCTAssertEqual(frame.strokeIndex, 0)
            XCTAssertEqual(frame.visibleStrokes.count, 1)
            XCTAssertTrue(frame.visibleStrokes[0].allSatisfy { $0 == glyph.strokes[0].start })
            XCTAssertEqual(frame.cursor, glyph.strokes[0].start)
            XCTAssertFalse(frame.isLifting)
            XCTAssertFalse(frame.isComplete)
        }
    }

    func testDrawingAdvancesByDistanceRatherThanVertexCount() {
        let stroke = GlyphStrokeSpec(
            start: point(0, 0),
            end: point(100, 0),
            requiredNodes: [point(10, 0)],
            referencePath: [point(0, 0), point(10, 0), point(100, 0)],
            nodeRadius: 9,
            pathRadius: 9
        )
        let demonstration = GlyphPracticeDemonstration(glyph: glyph(with: [stroke]))
        let drawingDuration = demonstration.duration - 0.45 - 0.55
        let frame = demonstration.frame(at: 0.45 + drawingDuration / 2)

        XCTAssertEqual(frame.visibleStrokes.count, 1)
        XCTAssertEqual(frame.visibleStrokes[0].count, 3)
        XCTAssertEqual(frame.visibleStrokes[0][1], point(10, 0))
        XCTAssertEqual(frame.cursor?.x ?? -1, 50, accuracy: 0.000_001)
        XCTAssertEqual(frame.cursor?.y ?? -1, 0, accuracy: 0.000_001)
        XCTAssertFalse(frame.isLifting)
        XCTAssertFalse(frame.isComplete)
    }

    func testTwoStrokeDemonstrationLiftsThenShowsSeparateSecondStart() {
        let glyph = SpellCatalog.barrierPiercing.glyph
        let demonstration = GlyphPracticeDemonstration(glyph: glyph)
        let firstDuration = GlyphPracticeDemonstration(glyph: self.glyph(with: [glyph.strokes[0]])).duration

        let lift = demonstration.frame(at: firstDuration - 0.25)
        XCTAssertEqual(lift.strokeIndex, 0)
        XCTAssertEqual(lift.visibleStrokes, [glyph.strokes[0].referencePath])
        XCTAssertTrue(lift.isLifting)
        XCTAssertNil(lift.cursor)
        XCTAssertFalse(lift.isComplete)

        let secondStart = demonstration.frame(at: firstDuration + 0.2)
        XCTAssertEqual(secondStart.strokeIndex, 1)
        XCTAssertEqual(secondStart.visibleStrokes.count, 2)
        XCTAssertEqual(secondStart.visibleStrokes[0], glyph.strokes[0].referencePath)
        XCTAssertTrue(secondStart.visibleStrokes[1].allSatisfy { $0 == glyph.strokes[1].start })
        XCTAssertEqual(secondStart.cursor, glyph.strokes[1].start)
        XCTAssertFalse(secondStart.isLifting)
        XCTAssertFalse(secondStart.isComplete)
    }

    func testSecondStrokeDrawsInItsOwnPathAndLiftsBeforeCompletion() {
        let glyph = SpellCatalog.barrierPiercing.glyph
        let demonstration = GlyphPracticeDemonstration(glyph: glyph)
        let firstDuration = GlyphPracticeDemonstration(glyph: self.glyph(with: [glyph.strokes[0]])).duration
        let secondDuration = demonstration.duration - firstDuration
        let drawing = demonstration.frame(at: firstDuration + 0.45 + (secondDuration - 1) / 2)

        XCTAssertEqual(drawing.strokeIndex, 1)
        XCTAssertEqual(drawing.visibleStrokes.count, 2)
        XCTAssertEqual(drawing.visibleStrokes[0], glyph.strokes[0].referencePath)
        XCTAssertEqual(drawing.visibleStrokes[1].first, glyph.strokes[1].start)
        XCTAssertNotEqual(drawing.cursor, glyph.strokes[1].start)
        XCTAssertNotEqual(drawing.cursor, glyph.strokes[1].end)
        XCTAssertFalse(drawing.visibleStrokes[1].contains(glyph.strokes[0].end))
        XCTAssertFalse(drawing.isLifting)

        let lift = demonstration.frame(at: demonstration.duration - 0.1)
        XCTAssertEqual(lift.visibleStrokes, glyph.strokes.map(\.referencePath))
        XCTAssertTrue(lift.isLifting)
        XCTAssertNil(lift.cursor)
        XCTAssertFalse(lift.isComplete)
    }

    func testAllCatalogDemonstrationsFinishWithEverySeparateReferencePath() {
        for spell in SpellCatalog.all.values {
            for reducedMotion in [false, true] {
                let demonstration = GlyphPracticeDemonstration(glyph: spell.glyph, reducedMotion: reducedMotion)
                XCTAssertGreaterThan(demonstration.duration, 0)
                XCTAssertTrue(demonstration.duration.isFinite)
                for elapsed in [demonstration.duration, demonstration.duration + 100] {
                    let frame = demonstration.frame(at: elapsed)
                    XCTAssertTrue(frame.isComplete, "\(spell.name), reducedMotion=\(reducedMotion), elapsed=\(elapsed)")
                    XCTAssertFalse(frame.isLifting)
                    XCTAssertNil(frame.cursor)
                    XCTAssertEqual(frame.visibleStrokes, spell.glyph.strokes.map(\.referencePath))
                    XCTAssertEqual(frame.strokeIndex, spell.glyph.strokes.count - 1)
                }
            }
        }
    }

    func testReducedMotionRevealsOneWholeStrokeAtATimeWithoutMovingCursor() {
        let glyph = SpellCatalog.barrierPiercing.glyph
        let demonstration = GlyphPracticeDemonstration(glyph: glyph, reducedMotion: true)
        let firstDuration = GlyphPracticeDemonstration(
            glyph: self.glyph(with: [glyph.strokes[0]]),
            reducedMotion: true
        ).duration

        XCTAssertLessThan(demonstration.duration, GlyphPracticeDemonstration(glyph: glyph).duration)
        let initial = demonstration.frame(at: 0.2)
        XCTAssertTrue(initial.visibleStrokes[0].allSatisfy { $0 == glyph.strokes[0].start })
        XCTAssertNil(initial.cursor)
        let first = demonstration.frame(at: 0.5)
        XCTAssertEqual(first.visibleStrokes, [glyph.strokes[0].referencePath])
        XCTAssertNil(first.cursor)
        XCTAssertFalse(first.isLifting)

        let secondStart = demonstration.frame(at: firstDuration + 0.2)
        XCTAssertEqual(secondStart.visibleStrokes[0], glyph.strokes[0].referencePath)
        XCTAssertTrue(secondStart.visibleStrokes[1].allSatisfy { $0 == glyph.strokes[1].start })
        XCTAssertNil(secondStart.cursor)
        let second = demonstration.frame(at: firstDuration + 0.5)
        XCTAssertEqual(second.visibleStrokes, glyph.strokes.map(\.referencePath))
        XCTAssertNil(second.cursor)
        XCTAssertFalse(second.isComplete)
    }

    func testNegativeAndNonfiniteTimesReturnTheInitialFrame() {
        for reducedMotion in [false, true] {
            let demonstration = GlyphPracticeDemonstration(
                glyph: SpellCatalog.barrierPiercing.glyph,
                reducedMotion: reducedMotion
            )
            let initial = demonstration.frame(at: 0)
            for elapsed in [-10.0, -.infinity, .infinity, .nan] {
                XCTAssertEqual(demonstration.frame(at: elapsed), initial)
            }
        }
    }

    func testEmptyGlyphCompletesImmediatelyWithoutACursor() {
        let demonstration = GlyphPracticeDemonstration(glyph: glyph(with: []))
        XCTAssertEqual(demonstration.duration, 0)
        let frame = demonstration.frame(at: 0)
        XCTAssertTrue(frame.isComplete)
        XCTAssertTrue(frame.visibleStrokes.isEmpty)
        XCTAssertNil(frame.cursor)
        XCTAssertFalse(frame.isLifting)
    }

    private func glyph(with strokes: [GlyphStrokeSpec]) -> GlyphDefinition {
        GlyphDefinition(difficulty: .easy, strokes: strokes, crossings: [])
    }

    private func point(_ x: Double, _ y: Double) -> NormalizedPoint {
        NormalizedPoint(x: x, y: y)
    }
}
