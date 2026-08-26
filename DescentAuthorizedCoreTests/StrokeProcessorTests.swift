import XCTest
@testable import DescentAuthorizedCore

final class StrokeProcessorTests: XCTestCase {
    private let processor = StrokeProcessor()

    func testProcessorNormalizesCanvasCoordinatesToPercentages() throws {
        let stroke = try processor.process(
            samples: [
                RawDrawingSample(x: 0, y: 0, timestamp: 0),
                RawDrawingSample(x: 100, y: 50, timestamp: 1),
                RawDrawingSample(x: 200, y: 100, timestamp: 2)
            ],
            canvasSize: DrawingCanvasSize(width: 200, height: 100),
            method: .pencil
        )

        XCTAssertEqual(stroke.points.first, NormalizedPoint(x: 0, y: 0))
        XCTAssertEqual(stroke.points.last, NormalizedPoint(x: 100, y: 100))
        XCTAssertEqual(stroke.points[1].x, 50, accuracy: 0.001)
        XCTAssertEqual(stroke.points[1].y, 50, accuracy: 0.001)
    }

    func testProcessorClampsPointsToCanvasBounds() throws {
        let stroke = try processor.process(
            samples: [
                RawDrawingSample(x: -20, y: -10, timestamp: 0),
                RawDrawingSample(x: 120, y: 160, timestamp: 1)
            ],
            canvasSize: DrawingCanvasSize(width: 100, height: 100),
            method: .pencil
        )

        XCTAssertEqual(stroke.points, [
            NormalizedPoint(x: 0, y: 0),
            NormalizedPoint(x: 100, y: 100)
        ])
    }

    func testProcessorDropsNonFiniteAndOutOfOrderSamples() throws {
        let stroke = try processor.process(
            samples: [
                RawDrawingSample(x: .nan, y: 10, timestamp: 0),
                RawDrawingSample(x: 10, y: 10, timestamp: 1),
                RawDrawingSample(x: 20, y: 20, timestamp: 0.5),
                RawDrawingSample(x: 30, y: 30, timestamp: 2)
            ],
            canvasSize: DrawingCanvasSize(width: 100, height: 100),
            method: .pencil
        )

        XCTAssertEqual(stroke.points.first, NormalizedPoint(x: 10, y: 10))
        XCTAssertEqual(stroke.points.last, NormalizedPoint(x: 30, y: 30))
        XCTAssertEqual(stroke.points.count, 2)
    }

    func testProcessorRejectsInvalidCanvasAndEmptySamples() {
        XCTAssertThrowsError(try processor.process(
            samples: [RawDrawingSample(x: 1, y: 1)],
            canvasSize: DrawingCanvasSize(width: 0, height: 100),
            method: .finger
        )) { error in
            XCTAssertEqual(error as? StrokeProcessingError, .invalidCanvasSize)
        }

        XCTAssertThrowsError(try processor.process(
            samples: [RawDrawingSample(x: .infinity, y: 1)],
            canvasSize: DrawingCanvasSize(width: 100, height: 100),
            method: .finger
        )) { error in
            XCTAssertEqual(error as? StrokeProcessingError, .noValidSamples)
        }
    }

    func testFingerSmoothingReducesMiddlePointJitterAndPreservesEndpoints() throws {
        let samples = [
            RawDrawingSample(x: 10, y: 50, timestamp: 0),
            RawDrawingSample(x: 50, y: 55, timestamp: 1),
            RawDrawingSample(x: 90, y: 50, timestamp: 2)
        ]
        let finger = try processor.process(
            samples: samples,
            canvasSize: DrawingCanvasSize(width: 100, height: 100),
            method: .finger
        )

        XCTAssertEqual(finger.points.first, NormalizedPoint(x: 10, y: 50))
        XCTAssertEqual(finger.points.last, NormalizedPoint(x: 90, y: 50))
        XCTAssertLessThan(finger.points[1].y, 55)
        XCTAssertGreaterThan(finger.points[1].y, 50)
    }

    func testProcessorReducesDenseDuplicateSamples() throws {
        let stroke = try processor.process(
            samples: [
                RawDrawingSample(x: 10, y: 10, timestamp: 0),
                RawDrawingSample(x: 10.01, y: 10.01, timestamp: 1),
                RawDrawingSample(x: 10.02, y: 10.02, timestamp: 2),
                RawDrawingSample(x: 90, y: 90, timestamp: 3)
            ],
            canvasSize: DrawingCanvasSize(width: 100, height: 100),
            method: .finger
        )

        XCTAssertEqual(stroke.points.count, 2)
    }

    func testAutomaticCaptureLetsPencilReplaceActiveFinger() throws {
        var session = StrokeCaptureSession(inputPreference: .automatic)
        _ = try session.beginStroke(
            contactID: 1,
            method: .finger,
            sample: RawDrawingSample(x: 10, y: 10)
        )

        let result = try session.beginStroke(
            contactID: 2,
            method: .pencil,
            sample: RawDrawingSample(x: 20, y: 20)
        )

        XCTAssertEqual(result, .replacedFingerWithPencil)
        XCTAssertEqual(session.activeContactID, 2)
        XCTAssertEqual(session.activeMethod, .pencil)
    }

    func testCaptureRejectsInputOutsideConfiguredMode() {
        var session = StrokeCaptureSession(inputPreference: .pencilOnly)

        XCTAssertThrowsError(try session.beginStroke(
            contactID: 1,
            method: .finger,
            sample: RawDrawingSample(x: 10, y: 10)
        )) { error in
            XCTAssertEqual(
                error as? StrokeCaptureError,
                .inputRejected(.finger)
            )
        }
    }

    func testCaptureCompletesCancelsAndLimitsStrokes() throws {
        var session = StrokeCaptureSession(maximumStrokeCount: 1)
        _ = try session.beginStroke(
            contactID: 1,
            method: .finger,
            sample: RawDrawingSample(x: 0, y: 0, timestamp: 0)
        )
        XCTAssertTrue(session.cancelStroke(contactID: 1))
        XCTAssertTrue(session.completedStrokes.isEmpty)

        _ = try session.beginStroke(
            contactID: 2,
            method: .finger,
            sample: RawDrawingSample(x: 0, y: 0, timestamp: 0)
        )
        _ = try session.endStroke(
            contactID: 2,
            finalSamples: [RawDrawingSample(x: 100, y: 100, timestamp: 1)],
            canvasSize: DrawingCanvasSize(width: 100, height: 100)
        )

        XCTAssertEqual(session.completedStrokes.count, 1)
        XCTAssertEqual(session.completedStrokes[0].duration ?? -1, 1, accuracy: 0.001)
        XCTAssertEqual(session.remainingStrokeCount, 0)
        XCTAssertThrowsError(try session.beginStroke(
            contactID: 3,
            method: .finger,
            sample: RawDrawingSample(x: 10, y: 10)
        )) { error in
            XCTAssertEqual(
                error as? StrokeCaptureError,
                .strokeLimitReached(1)
            )
        }
    }

    func testPreferenceChangeCancelsDisallowedActiveStroke() throws {
        var session = StrokeCaptureSession(inputPreference: .automatic)
        _ = try session.beginStroke(
            contactID: 1,
            method: .finger,
            sample: RawDrawingSample(x: 10, y: 10)
        )

        session.updateInputPreference(.pencilOnly)

        XCTAssertFalse(session.hasActiveStroke)
        XCTAssertEqual(session.inputPreference, .pencilOnly)
    }

    func testPreferenceChangeCancelsEvenStillAllowedActiveStroke() throws {
        var session = StrokeCaptureSession(inputPreference: .automatic)
        _ = try session.beginStroke(
            contactID: 1,
            method: .pencil,
            sample: RawDrawingSample(x: 10, y: 10)
        )

        session.updateInputPreference(.pencilOnly)

        XCTAssertFalse(session.hasActiveStroke)
    }

    func testUndoAndClearManageCompletedStrokes() throws {
        var session = StrokeCaptureSession(maximumStrokeCount: 2)
        for (contactID, method) in [(1, DrawingInputMethod.finger), (2, .pencil)] {
            _ = try session.beginStroke(
                contactID: contactID,
                method: method,
                sample: RawDrawingSample(x: 0, y: 0, timestamp: 0)
            )
            _ = try session.endStroke(
                contactID: contactID,
                finalSamples: [RawDrawingSample(x: 100, y: 100, timestamp: 1)],
                canvasSize: DrawingCanvasSize(width: 100, height: 100)
            )
        }

        XCTAssertEqual(session.lastCompletedMethod, .pencil)
        XCTAssertNotNil(session.undoLastStroke())
        XCTAssertEqual(session.completedStrokes.count, 1)
        XCTAssertEqual(session.lastCompletedMethod, .finger)
        session.clear()
        XCTAssertTrue(session.completedStrokes.isEmpty)
        XCTAssertNil(session.lastCompletedMethod)
    }
}
