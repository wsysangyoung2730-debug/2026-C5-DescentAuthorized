import XCTest
@testable import DescentAuthorizedCore

final class EndingCreditsPlaybackTests: XCTestCase {
    func testWaitsForScrollableLayoutBeforeStarting() {
        var playback = EndingCreditsPlayback()
        XCTAssertNil(playback.advance(elapsed: 0.1, isSuspended: false))
        XCTAssertFalse(playback.isAtEnd)

        playback.updateLayout(offset: 0, maximumOffset: -100)
        XCTAssertEqual(playback.maximumOffset, 0)
        XCTAssertNil(playback.advance(elapsed: 0.1, isSuspended: false))

        playback.updateLayout(offset: 0, maximumOffset: 900)
        XCTAssertEqual(playback.advance(elapsed: 0.1, isSuspended: false), 1)
    }

    func testDifferentContentHeightsTakeApproximatelyNinetySeconds() throws {
        for maximumOffset in [450.0, 2_400.0, 12_000.0] {
            var playback = EndingCreditsPlayback()
            playback.updateLayout(offset: 0, maximumOffset: maximumOffset)
            for _ in 0..<450 {
                let target = try XCTUnwrap(playback.advance(elapsed: 0.1, isSuspended: false))
                // The next frame reports the actual position reached by the scroll view.
                playback.updateLayout(offset: target, maximumOffset: maximumOffset)
            }
            XCTAssertEqual(playback.offset, maximumOffset / 2, accuracy: 0.000_001)
            for _ in 0..<451 {
                if let target = playback.advance(elapsed: 0.1, isSuspended: false) {
                    playback.updateLayout(offset: target, maximumOffset: maximumOffset)
                }
            }
            XCTAssertEqual(playback.offset, maximumOffset)
            XCTAssertTrue(playback.isAtEnd)
        }
    }

    func testSuspensionHoldsPositionAndLongResumeFrameDoesNotCatchUp() {
        var playback = EndingCreditsPlayback()
        playback.updateLayout(offset: 300, maximumOffset: 900)
        for _ in 0..<20 {
            XCTAssertNil(playback.advance(elapsed: 30, isSuspended: true))
        }
        XCTAssertEqual(playback.offset, 300)
        XCTAssertEqual(playback.advance(elapsed: 600, isSuspended: false), 301)
        XCTAssertEqual(playback.advance(elapsed: 0.05, isSuspended: false), 301.5)
    }

    func testLastTargetClampsToEndAndHoldsUntilReaderScrollsBack() {
        var playback = EndingCreditsPlayback()
        playback.updateLayout(offset: 899.8, maximumOffset: 900)
        XCTAssertEqual(playback.advance(elapsed: 0.1, isSuspended: false), 900)
        XCTAssertTrue(playback.isAtEnd)
        for _ in 0..<10 {
            XCTAssertNil(playback.advance(elapsed: 0.1, isSuspended: false))
        }
        playback.updateLayout(offset: 950, maximumOffset: 900)
        XCTAssertEqual(playback.offset, 900)
        XCTAssertTrue(playback.isAtEnd)

        playback.updateLayout(offset: 450, maximumOffset: 900)
        XCTAssertFalse(playback.isAtEnd)
        XCTAssertEqual(playback.advance(elapsed: 0.1, isSuspended: false), 451)
    }

    func testActualScrollPositionReplacesPriorTargetAfterManualInteraction() {
        var playback = EndingCreditsPlayback()
        playback.updateLayout(offset: 300, maximumOffset: 900)
        XCTAssertEqual(playback.advance(elapsed: 0.1, isSuspended: false), 301)
        playback.updateLayout(offset: 100, maximumOffset: 900)
        XCTAssertNil(playback.advance(elapsed: 1, isSuspended: true))
        XCTAssertEqual(playback.advance(elapsed: 0.1, isSuspended: false), 101)

        playback.updateLayout(offset: -40, maximumOffset: 900)
        XCTAssertEqual(playback.offset, 0)
        XCTAssertEqual(playback.advance(elapsed: 0.1, isSuspended: false), 1)
    }

    func testNewLayoutClampsPositionAndRecomputesTheRemainingScroll() {
        var playback = EndingCreditsPlayback()
        playback.updateLayout(offset: 600, maximumOffset: 900)
        playback.updateLayout(offset: 600, maximumOffset: 400)
        XCTAssertEqual(playback.offset, 400)
        XCTAssertTrue(playback.isAtEnd)
        XCTAssertNil(playback.advance(elapsed: 0.1, isSuspended: false))

        playback.updateLayout(offset: 400, maximumOffset: 1_800)
        XCTAssertFalse(playback.isAtEnd)
        XCTAssertEqual(playback.advance(elapsed: 0.1, isSuspended: false), 402)
        playback.updateLayout(offset: 402, maximumOffset: 0)
        XCTAssertEqual(playback.offset, 0)
        XCTAssertFalse(playback.isAtEnd)
        XCTAssertNil(playback.advance(elapsed: 0.1, isSuspended: false))
    }

    func testInvalidGeometryAndElapsedTimeDoNotCorruptValidPosition() {
        var playback = EndingCreditsPlayback()
        playback.updateLayout(offset: 300, maximumOffset: 900)
        let valid = playback
        for invalid in [Double.nan, .infinity, -.infinity] {
            playback.updateLayout(offset: invalid, maximumOffset: 900)
            XCTAssertEqual(playback, valid)
            playback.updateLayout(offset: 20, maximumOffset: invalid)
            XCTAssertEqual(playback, valid)
        }
        for invalid in [Double.nan, .infinity, -.infinity, -10, 0] {
            XCTAssertNil(playback.advance(elapsed: invalid, isSuspended: false))
            XCTAssertEqual(playback, valid)
        }
        XCTAssertEqual(playback.advance(elapsed: 0.1, isSuspended: false), 301)
    }
}
