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

        let updates = Dictionary(
            uniqueKeysWithValues: tracker.updates(for: progress).map {
                ($0.id, $0.percentComplete)
            }
        )

        XCTAssertEqual(updates[.firstGlyph], 100)
        XCTAssertEqual(updates[.perfectCast], 100)
        XCTAssertEqual(updates[.recordsCleared], 100)
        XCTAssertEqual(updates[.spellArchive], 100)
        XCTAssertNil(updates[.absoluteBarrierDispelled])
        XCTAssertEqual(updates[.descentProcedure], 67)
        XCTAssertNil(updates[.observationCleared])
        XCTAssertNil(updates[.demoCompleted])
    }

    func testAbsoluteBarrierAchievementRequiresActualBarrierChange() {
        let progress = GameProgress.newGame
        let noEffect = tracker.updates(
            for: progress,
            events: [.combat(.spellResolved(spell: .sealRelease, grade: .perfect))]
        )
        XCTAssertFalse(noEffect.contains { $0.id == .absoluteBarrierDispelled })

        let successfulDispel = tracker.updates(
            for: progress,
            events: [
                .combat(.spellResolved(spell: .sealRelease, grade: .perfect)),
                .combat(.absoluteBarrierChanged(
                    target: .enemy(.observationAdministrator),
                    charges: 0
                ))
            ]
        )
        XCTAssertTrue(successfulDispel.contains(
            GameAchievementUpdate(id: .absoluteBarrierDispelled, percentComplete: 100)
        ))
    }

    func testLedgerKeepsHighestProgressForEachPlayer() {
        var ledger = GameAchievementLedger()
        ledger.merge([
            GameAchievementUpdate(id: .spellArchive, percentComplete: 20),
            GameAchievementUpdate(id: .spellArchive, percentComplete: 40)
        ])

        let firstBatch = ledger.updatesToReport(for: "player-a")
        ledger.acknowledge(firstBatch, for: "player-a")
        ledger.merge([
            GameAchievementUpdate(id: .spellArchive, percentComplete: 60)
        ])

        XCTAssertEqual(
            ledger.updatesToReport(for: "player-a"),
            [GameAchievementUpdate(id: .spellArchive, percentComplete: 60)]
        )
        XCTAssertEqual(
            ledger.updatesToReport(for: "player-b"),
            [GameAchievementUpdate(id: .spellArchive, percentComplete: 60)]
        )
    }

    func testLedgerRoundTripsThroughJSON() throws {
        var ledger = GameAchievementLedger()
        ledger.merge([
            GameAchievementUpdate(id: .firstGlyph, percentComplete: 100)
        ])
        ledger.acknowledge(
            ledger.updatesToReport(for: "player"),
            for: "player"
        )

        let data = try JSONEncoder().encode(ledger)
        let decoded = try JSONDecoder().decode(GameAchievementLedger.self, from: data)

        XCTAssertEqual(decoded, ledger)
        XCTAssertTrue(decoded.updatesToReport(for: "player").isEmpty)
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
