import XCTest
@testable import DescentAuthorizedCore

final class GameAchievementTests: XCTestCase {
    private let tracker = GameAchievementTracker()

    func testNewGameHasNoReportableAchievementProgress() {
        XCTAssertTrue(tracker.updates(for: .newGame).isEmpty)
    }

    func testTrackerDerivesProgressFromPersistentGameState() {
        var progress = GameProgress.newGame
        progress.currentFloor = .floor8
        progress.learnedSpells = Set(SpellID.allCases)
        progress.completedTrainingSpells = [.afterglowErasure]
        progress.defeatedEnemies = [.recordsAdministrator]
        progress.spellMastery[.afterglowErasure] = SpellMastery(
            bestGrade: .perfect,
            successfulCasts: 1
        )
        progress.spellMastery[.sealRelease] = SpellMastery(
            bestGrade: .approved,
            successfulCasts: 1
        )

        let updates = Dictionary(
            uniqueKeysWithValues: tracker.updates(for: progress).map {
                ($0.id, $0.percentComplete)
            }
        )

        XCTAssertEqual(updates[.firstGlyph], 100)
        XCTAssertEqual(updates[.perfectCast], 100)
        XCTAssertEqual(updates[.recordsCleared], 100)
        XCTAssertEqual(updates[.spellArchive], 100)
        XCTAssertEqual(updates[.absoluteBarrierDispelled], 100)
        XCTAssertEqual(updates[.descentProcedure], 67)
        XCTAssertNil(updates[.observationCleared])
        XCTAssertNil(updates[.demoCompleted])
    }

    func testQueueKeepsHighestProgressAndAcknowledgesOnlyReportedValue() {
        var queue = GameAchievementQueue()
        queue.merge([
            GameAchievementUpdate(id: .spellArchive, percentComplete: 20),
            GameAchievementUpdate(id: .spellArchive, percentComplete: 40)
        ])

        let oldBatch = queue.pendingUpdates
        queue.merge([
            GameAchievementUpdate(id: .spellArchive, percentComplete: 60)
        ])
        queue.acknowledge(oldBatch)

        XCTAssertEqual(
            queue.pendingUpdates,
            [GameAchievementUpdate(id: .spellArchive, percentComplete: 60)]
        )
        queue.acknowledge(queue.pendingUpdates)
        XCTAssertTrue(queue.isEmpty)
    }

    func testAchievementPercentagesAreClampedToGameCenterRange() {
        XCTAssertEqual(
            GameAchievementUpdate(id: .spellArchive, percentComplete: -10).percentComplete,
            0
        )
        XCTAssertEqual(
            GameAchievementUpdate(id: .spellArchive, percentComplete: 120).percentComplete,
            100
        )
    }
}
