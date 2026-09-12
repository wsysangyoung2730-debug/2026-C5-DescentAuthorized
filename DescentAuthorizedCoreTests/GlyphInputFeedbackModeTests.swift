import XCTest
@testable import DescentAuthorizedCore

final class GlyphInputFeedbackModeTests: XCTestCase {
    func testDisabledModeDoesNotAddGuidanceOrCheckpointFeedback() {
        let mode = GlyphInputFeedbackMode.disabled

        XCTAssertFalse(mode.showsPracticeGuidance)
        XCTAssertFalse(mode.showsCheckpointFeedback)
        XCTAssertEqual(mode.checkpointVolume, 0)
    }

    func testPracticeKeepsDemonstrationAndCheckpointFeedbackTogether() {
        let mode = GlyphInputFeedbackMode.practice

        XCTAssertTrue(mode.showsPracticeGuidance)
        XCTAssertTrue(mode.showsCheckpointFeedback)
        XCTAssertEqual(mode.checkpointVolume, 0.58, accuracy: 0.0001)
    }

    func testBattleProvidesCheckpointFeedbackWithoutTeachingGuidance() {
        let mode = GlyphInputFeedbackMode.battle

        XCTAssertFalse(mode.showsPracticeGuidance)
        XCTAssertTrue(mode.showsCheckpointFeedback)
        XCTAssertEqual(mode.checkpointVolume, 0.40, accuracy: 0.0001)
        XCTAssertGreaterThan(mode.checkpointVolume, 0)
        XCTAssertLessThan(mode.checkpointVolume, GlyphInputFeedbackMode.practice.checkpointVolume)
    }

    func testEveryFeedbackModeHasFiniteVolumeWithinPlaybackRange() {
        for mode in [GlyphInputFeedbackMode.disabled, .practice, .battle] {
            XCTAssertTrue(mode.checkpointVolume.isFinite)
            XCTAssertGreaterThanOrEqual(mode.checkpointVolume, 0)
            XCTAssertLessThanOrEqual(mode.checkpointVolume, 1)
        }
    }
}
