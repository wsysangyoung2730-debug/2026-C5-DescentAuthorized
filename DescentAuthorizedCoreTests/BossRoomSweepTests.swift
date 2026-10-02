import XCTest
import simd
@testable import DescentAuthorizedCore

final class BossRoomSweepTests: XCTestCase {
    func testBundledTrackExistsForEveryBossAndOnlyBossFloors() throws {
        for floor in 1...9 {
            let track = try XCTUnwrap(BossRoomSweepCatalog.track(for: floor))
            XCTAssertEqual(track.floor, floor)
            XCTAssertEqual(track.duration, 12)
            XCTAssertEqual(track.framesPerSecond, 30)
            XCTAssertEqual(track.samples.count, 361)
            // Translation must reveal real room depth, rather than rotating in place.
            XCTAssertGreaterThan(simd_distance(track.pose(at: 0).position, track.pose(at: 3.4).position), 1)
            XCTAssertGreaterThan(simd_distance(track.pose(at: 3.4).position, track.pose(at: 7.2).position), 1)
            for index in 0...720 {
                let pose = track.pose(at: Double(index) / 60)
                XCTAssertTrue(pose.position.x.isFinite && pose.position.y.isFinite && pose.position.z.isFinite)
                XCTAssertEqual(simd_length(pose.orientation.vector), 1, accuracy: 0.000_001)
                XCTAssertGreaterThan(pose.lensMillimeters, 0)
            }
            assertEqual(track.pose(at: 11.2), track.pose(at: 12))
        }
        for floor in [-1, 0, 10, 11] {
            XCTAssertNil(BossRoomSweepCatalog.track(for: floor))
        }
    }

    func testRefinedObservatoryRightPoseAndInteriorLowerFloorReturnsArePreserved() throws {
        let observatory = try XCTUnwrap(BossRoomSweepCatalog.track(for: 8))
        XCTAssertLessThan(simd_distance(observatory.pose(at: 7.2).position, SIMD3(4.3, 2.6, 3.4)), 0.000_01)
        let expectedReturns: [Int: SIMD3<Float>] = [
            1: SIMD3(0, -15, 4.8), 2: SIMD3(0, -8.4, 4.8), 3: SIMD3(0, -7.5, 4.2)
        ]
        for (floor, expected) in expectedReturns {
            let track = try XCTUnwrap(BossRoomSweepCatalog.track(for: floor))
            XCTAssertLessThan(simd_distance(track.pose(at: 12).position, expected), 0.000_01)
        }
    }

    func testInterpolationUsesPhysicalPositionLensAndNormalizedQuaternion() throws {
        let track = try fixtureTrack()
        let pose = track.pose(at: 0.25)
        XCTAssertEqual(pose.position, SIMD3(1, 2, 3))
        XCTAssertEqual(pose.lensMillimeters, 30)
        XCTAssertEqual(pose.shift, SIMD2(0.1, -0.1))
        let forward = pose.orientation.act(SIMD3<Float>(1, 0, 0))
        XCTAssertLessThan(simd_distance(forward, SIMD3(0, 1, 0)), 0.000_001)
        XCTAssertEqual(simd_length(pose.orientation.vector), 1, accuracy: 0.000_001)
    }

    func testQuaternionSignChangeDoesNotCauseFullSpin() throws {
        let row: [Double] = [0, 0, 0, 1, 0, 0, 0, 24, 0, 0]
        var opposite = row
        opposite[3] = -1
        let track = try fixtureTrack(rows: [row, opposite, row])
        for time in stride(from: 0.0, through: 1.0, by: 0.05) {
            let pose = track.pose(at: time)
            XCTAssertLessThan(simd_distance(pose.orientation.act(SIMD3<Float>(1, 0, 0)), SIMD3(1, 0, 0)), 0.000_001)
        }
    }

    func testSamplingClampsBeforeAndAfterTrackAndRejectsNaNTime() throws {
        let track = try fixtureTrack()
        for time in [-Double.infinity, -1, .nan] {
            assertEqual(track.pose(at: time), track.pose(at: 0))
        }
        for time in [2, 200, Double.infinity] {
            assertEqual(track.pose(at: time), track.pose(at: 1))
        }
    }

    func testLandscapeLensConversionPreservesHorizontalSensorFit() throws {
        let track = try fixtureTrack()
        let onTablet = track.verticalFieldOfView(lensMillimeters: 24, aspectRatio: 4 / 3)
        let onWideScreen = track.verticalFieldOfView(lensMillimeters: 24, aspectRatio: 16 / 9)
        XCTAssertEqual(onTablet, 58.715507, accuracy: 0.000_1)
        XCTAssertLessThan(onWideScreen, onTablet)
        XCTAssertEqual(
            track.verticalFieldOfView(lensMillimeters: 24, aspectRatio: .nan),
            track.verticalFieldOfView(lensMillimeters: 24, aspectRatio: track.authoredAspectRatio)
        )
    }

    func testMalformedSamplesCannotReachCameraPlayback() throws {
        let valid: [Double] = [0, 0, 0, 1, 0, 0, 0, 24, 0, 0]
        var zeroQuaternion = valid
        zeroQuaternion[3] = 0
        var zeroLens = valid
        zeroLens[7] = 0
        for rows in [[], [valid], [valid, zeroQuaternion, valid], [valid, zeroLens, valid], [valid, Array(valid.dropLast()), valid]] {
            XCTAssertThrowsError(try fixtureTrack(rows: rows))
        }
        var document = fixtureDocument()
        document["version"] = 2
        XCTAssertThrowsError(try BossRoomSweepCatalog.decode(JSONSerialization.data(withJSONObject: document)))
        document = fixtureDocument()
        document["duration"] = 1.1
        XCTAssertThrowsError(try BossRoomSweepCatalog.decode(JSONSerialization.data(withJSONObject: document)))
        document = fixtureDocument()
        document["rooms"] = (document["rooms"] as! [[String: Any]]) + (document["rooms"] as! [[String: Any]])
        XCTAssertThrowsError(try BossRoomSweepCatalog.decode(JSONSerialization.data(withJSONObject: document)))
    }

    func testPlaybackSuspendsAndDoesNotCatchUpAfterBackgrounding() {
        var playback = BossRoomSweepPlayback()
        XCTAssertFalse(playback.advance(elapsed: 0.05, isSuspended: false))
        for _ in 0..<10 {
            XCTAssertFalse(playback.advance(elapsed: 30, isSuspended: true))
        }
        XCTAssertEqual(playback.elapsedTime, 0.05)
        XCTAssertFalse(playback.advance(elapsed: 600, isSuspended: false))
        XCTAssertEqual(playback.elapsedTime, 0.15, accuracy: 0.000_001)
        for invalid in [Double.nan, .infinity, -.infinity, 0, -2] {
            XCTAssertFalse(playback.advance(elapsed: invalid, isSuspended: false))
        }
        XCTAssertEqual(playback.elapsedTime, 0.15, accuracy: 0.000_001)
    }

    func testPlaybackEndsExactlyOnceAfterTwelveActiveSeconds() {
        var playback = BossRoomSweepPlayback()
        var completions = 0
        for _ in 0..<720 {
            if playback.advance(elapsed: 1 / 60, isSuspended: false) { completions += 1 }
        }
        XCTAssertEqual(playback.elapsedTime, 12)
        XCTAssertTrue(playback.isFinished)
        XCTAssertEqual(completions, 1)
        XCTAssertFalse(playback.advance(elapsed: 0.1, isSuspended: false))
        XCTAssertFalse(playback.skip())
    }

    func testSkipAndReducedMotionCannotCompleteTheFlowTwice() {
        var playback = BossRoomSweepPlayback()
        playback.advance(elapsed: 0.1, isSuspended: false)
        XCTAssertTrue(playback.skip())
        XCTAssertTrue(playback.isFinished)
        XCTAssertEqual(playback.elapsedTime, 12)
        XCTAssertFalse(playback.skip())
        XCTAssertFalse(playback.advance(elapsed: 0.1, isSuspended: false))
    }

    private func assertEqual(_ first: BossRoomSweepPose, _ second: BossRoomSweepPose, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThan(simd_distance(first.position, second.position), 0.000_01, file: file, line: line)
        XCTAssertGreaterThan(abs(simd_dot(first.orientation.vector, second.orientation.vector)), 0.999_99, file: file, line: line)
        XCTAssertEqual(first.lensMillimeters, second.lensMillimeters, accuracy: 0.000_01, file: file, line: line)
        XCTAssertLessThan(simd_distance(first.shift, second.shift), 0.000_01, file: file, line: line)
    }

    private func fixtureTrack(rows: [[Double]]? = nil) throws -> BossRoomSweepTrack {
        let data = try JSONSerialization.data(withJSONObject: fixtureDocument(rows: rows))
        let tracks = try BossRoomSweepCatalog.decode(data)
        return try XCTUnwrap(tracks[9])
    }

    private func fixtureDocument(rows: [[Double]]? = nil) -> [String: Any] {
        [
            "version": 1, "fps": 2, "duration": 1,
            "rooms": [[
                "floor": 9, "sensorWidth": 36, "sensorHeight": 24,
                "sensorFit": "HORIZONTAL", "aspectRatio": 4.0 / 3.0,
                "nearClip": 0.08, "farClip": 200,
                "samples": rows ?? [
                    [0, 0, 0, 1, 0, 0, 0, 24, 0, 0],
                    [2, 4, 6, 0, 0, 0, 1, 36, 0.2, -0.2],
                    [2, 4, 6, 0, 0, 0, 1, 36, 0.2, -0.2]
                ]
            ]]
        ]
    }
}
