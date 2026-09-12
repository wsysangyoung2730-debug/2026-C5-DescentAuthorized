import XCTest
@testable import DescentAuthorizedCore

final class GlyphCheckpointTrackerTests: XCTestCase {
    func testEveryCatalogReferencePathEmitsAllCheckpointsInOrder() {
        for method in [DrawingInputMethod.pencil, .finger] {
            for spell in SpellCatalog.all.values {
                var tracker = GlyphCheckpointTracker()
                for (strokeIndex, stroke) in spell.glyph.strokes.enumerated() {
                    let expected = GlyphCheckpointTracker.orderedPoints(for: stroke)
                    var hits = tracker.begin(stroke: stroke, strokeIndex: strokeIndex, at: stroke.start, inputMethod: method)
                    hits += tracker.append(Array(stroke.referencePath.dropFirst()))

                    XCTAssertEqual(hits.map(\.position), expected, "\(spell.name), stroke \(strokeIndex), \(method)")
                    XCTAssertEqual(hits.map(\.checkpointIndex), Array(expected.indices))
                    XCTAssertTrue(hits.allSatisfy { $0.strokeIndex == strokeIndex })
                    XCTAssertEqual(hits.filter(\.isStrokeEnd).count, 1)
                    XCTAssertEqual(hits.last?.position, stroke.end)
                }
            }
        }
    }

    func testOptionalAndRequiredNodesAreMergedInReferenceOrder() {
        let stroke = spec(
            path: [(0, 0), (20, 0), (40, 0), (60, 0), (80, 0)],
            required: [(60, 0), (20, 0)],
            optional: [(40, 0), (20, 0)]
        )
        XCTAssertEqual(GlyphCheckpointTracker.orderedPoints(for: stroke), stroke.referencePath)
    }

    func testRepeatedCoordinatesKeepSeparateVisitsInTheirPathOrder() {
        let stroke = spec(
            path: [(0, 0), (20, 0), (20, 20), (20, 0), (40, 0)],
            required: [(20, 0), (20, 0)],
            optional: [(20, 20)]
        )
        XCTAssertEqual(GlyphCheckpointTracker.orderedPoints(for: stroke), stroke.referencePath)
        var tracker = GlyphCheckpointTracker()
        var hits = tracker.begin(stroke: stroke, strokeIndex: 0, at: stroke.start, inputMethod: .pencil)
        hits += tracker.append(Array(stroke.referencePath.dropFirst()))
        XCTAssertEqual(hits.map(\.position), stroke.referencePath)
    }

    func testBarrierPiercingCrossingProducesSeparateAscendingAndDescendingHits() {
        let stroke = SpellCatalog.barrierPiercing.glyph.strokes[0]
        let crossing = point(37, 54)
        for method in [DrawingInputMethod.pencil, .finger] {
            var tracker = GlyphCheckpointTracker()
            var firstPass = tracker.begin(stroke: stroke, strokeIndex: 0, at: stroke.start, inputMethod: method)
            firstPass += tracker.append([point(30, 63), crossing])
            XCTAssertEqual(firstPass.filter { $0.position == crossing }.map(\.checkpointIndex), [1])

            let loop = tracker.append([
                point(44, 45), point(50, 34), point(55, 23),
                point(59, 14), point(57, 8), point(51, 6),
                point(44, 10), point(40, 18), point(37, 30),
                point(36, 43), crossing
            ])
            XCTAssertEqual(loop.filter { $0.position == crossing }.map(\.checkpointIndex), [5])
            let bothVisits = (firstPass + loop).filter { $0.position == crossing }
            XCTAssertEqual(bothVisits.count, 2)
            XCTAssertTrue(bothVisits.allSatisfy { !$0.isStrokeEnd })
            XCTAssertTrue(tracker.append([crossing, crossing]).isEmpty)
        }
    }

    func testRepeatedCheckpointRequiresLeavingAndReturning() {
        let stroke = spec(
            path: [(0, 0), (20, 0), (20, 20), (20, 0), (40, 0)],
            required: [(20, 0), (20, 0)]
        )
        var tracker = GlyphCheckpointTracker()
        _ = tracker.begin(stroke: stroke, strokeIndex: 0, at: stroke.start, inputMethod: .pencil)
        XCTAssertEqual(tracker.append([point(20, 0)]).map(\.checkpointIndex), [1])
        XCTAssertTrue(tracker.append([point(20, 0), point(21, 0)]).isEmpty)
        XCTAssertTrue(tracker.append([point(20, 20)]).isEmpty)
        XCTAssertEqual(tracker.append([point(20, 0)]).map(\.checkpointIndex), [2])
        XCTAssertEqual(tracker.append([stroke.end]).map(\.checkpointIndex), [3])
    }

    func testFastSegmentDetectsCheckpointsWithoutSamplesInsideTheirRadius() {
        let stroke = spec(
            path: [(0, 0), (25, 0), (50, 0), (75, 0), (100, 0)],
            required: [(25, 0), (75, 0)],
            optional: [(50, 0)]
        )
        var tracker = GlyphCheckpointTracker()
        let start = tracker.begin(stroke: stroke, strokeIndex: 0, at: stroke.start, inputMethod: .pencil)
        let rest = tracker.append([stroke.end])
        XCTAssertEqual((start + rest).map(\.position), stroke.referencePath)
    }

    func testWrongStartCannotRecoverByEnteringTheGuideLater() {
        let stroke = SpellCatalog.afterglowErasure.glyph.strokes[0]
        var tracker = GlyphCheckpointTracker()
        XCTAssertTrue(tracker.begin(stroke: stroke, strokeIndex: 0, at: stroke.end, inputMethod: .pencil).isEmpty)
        XCTAssertTrue(tracker.append(stroke.referencePath).isEmpty)
    }

    func testOutOfOrderNodesDoNotReceiveCreditFromEarlierSegmentPositions() {
        let stroke = spec(
            path: [(0, 0), (30, 30), (30, 0), (60, 0)],
            required: [(30, 30), (30, 0)]
        )
        var tracker = GlyphCheckpointTracker()
        _ = tracker.begin(stroke: stroke, strokeIndex: 0, at: stroke.start, inputMethod: .pencil)
        XCTAssertTrue(tracker.append([point(30, 0)]).isEmpty)
        XCTAssertEqual(tracker.append([point(30, 30)]).map(\.checkpointIndex), [1])
        XCTAssertTrue(tracker.append([stroke.end]).isEmpty)
    }

    func testSkippedOptionalNodeDoesNotRewardLaterGuideNodes() {
        let stroke = spec(
            path: [(0, 0), (30, 30), (60, 0), (90, 0)],
            required: [(60, 0)],
            optional: [(30, 30)]
        )
        var tracker = GlyphCheckpointTracker()
        _ = tracker.begin(stroke: stroke, strokeIndex: 0, at: stroke.start, inputMethod: .pencil)
        XCTAssertTrue(tracker.append([point(60, 0), stroke.end]).isEmpty)
    }

    func testFinishedStrokeDoesNotReplaySoundsForDuplicateOrReversedSamples() {
        let stroke = SpellCatalog.riftSeverance.glyph.strokes[0]
        var tracker = GlyphCheckpointTracker()
        _ = tracker.begin(stroke: stroke, strokeIndex: 0, at: stroke.start, inputMethod: .pencil)
        _ = tracker.append(stroke.referencePath)
        XCTAssertTrue(tracker.append(Array(stroke.referencePath.reversed())).isEmpty)
        XCTAssertTrue(tracker.append(stroke.referencePath).isEmpty)
    }

    func testTwoStrokeSpellStartsEachStrokeIndependently() {
        let first = SpellCatalog.barrierPiercing.glyph.strokes[0]
        let second = SpellCatalog.barrierPiercing.glyph.strokes[1]
        var tracker = GlyphCheckpointTracker()
        _ = tracker.begin(stroke: first, strokeIndex: 0, at: first.start, inputMethod: .pencil)
        _ = tracker.append(first.referencePath)

        XCTAssertTrue(tracker.begin(stroke: second, strokeIndex: 1, at: first.end, inputMethod: .pencil).isEmpty)
        XCTAssertTrue(tracker.append(second.referencePath).isEmpty)
        var hits = tracker.begin(stroke: second, strokeIndex: 1, at: second.start, inputMethod: .pencil)
        hits += tracker.append(second.referencePath)
        XCTAssertEqual(hits.first?.checkpointIndex, 0)
        XCTAssertEqual(hits.last?.isStrokeEnd, true)
        XCTAssertTrue(hits.allSatisfy { $0.strokeIndex == 1 })
    }

    func testResetClearsPendingProgressAndAllowsFreshAttempt() {
        let stroke = SpellCatalog.afterglowErasure.glyph.strokes[0]
        var tracker = GlyphCheckpointTracker()
        _ = tracker.begin(stroke: stroke, strokeIndex: 0, at: stroke.start, inputMethod: .pencil)
        _ = tracker.append([stroke.requiredNodes[0]])
        tracker.reset()
        XCTAssertTrue(tracker.append(stroke.referencePath).isEmpty)

        let start = tracker.begin(stroke: stroke, strokeIndex: 0, at: stroke.start, inputMethod: .pencil)
        XCTAssertEqual(start.map(\.checkpointIndex), [0])
        XCTAssertEqual(tracker.append([stroke.requiredNodes[0]]).map(\.checkpointIndex), [1])
    }

    func testFingerUsesItsEvaluationToleranceButFeedbackRemainsPrecise() {
        let stroke = spec(path: [(0, 0), (30, 0), (60, 0)], required: [(30, 0)])
        var pencil = GlyphCheckpointTracker()
        var finger = GlyphCheckpointTracker()
        XCTAssertTrue(pencil.begin(stroke: stroke, strokeIndex: 0, at: point(0, 10), inputMethod: .pencil).isEmpty)
        XCTAssertEqual(finger.begin(stroke: stroke, strokeIndex: 0, at: point(0, 10), inputMethod: .finger).count, 1)

        _ = pencil.begin(stroke: stroke, strokeIndex: 0, at: point(0, 6), inputMethod: .pencil)
        _ = finger.begin(stroke: stroke, strokeIndex: 0, at: point(0, 6), inputMethod: .finger)
        XCTAssertTrue(pencil.append([point(60, 6)]).isEmpty)
        XCTAssertEqual(finger.append([point(60, 6)]).map(\.checkpointIndex), [1, 2])
    }

    private func spec(
        path: [(Double, Double)],
        required: [(Double, Double)],
        optional: [(Double, Double)] = []
    ) -> GlyphStrokeSpec {
        let points = path.map(point)
        return GlyphStrokeSpec(
            start: points[0],
            end: points[points.count - 1],
            requiredNodes: required.map(point),
            optionalNodes: optional.map(point),
            referencePath: points,
            nodeRadius: 9,
            pathRadius: 9
        )
    }

    private func point(_ x: Double, _ y: Double) -> NormalizedPoint {
        NormalizedPoint(x: x, y: y)
    }
}
