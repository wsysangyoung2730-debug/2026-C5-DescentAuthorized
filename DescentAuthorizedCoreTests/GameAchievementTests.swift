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
        // Collection progress belongs to the cumulative ledger, not a single save.
        XCTAssertNil(updates[.spellArchive])
        XCTAssertNil(updates[.absoluteBarrierDispelled])
        XCTAssertEqual(updates[.descentProcedure], 22)
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
            GameAchievementUpdate(id: .descentProcedure, percentComplete: 20),
            GameAchievementUpdate(id: .descentProcedure, percentComplete: 40)
        ])

        let firstBatch = ledger.updatesToReport(for: "player-a")
        ledger.acknowledge(firstBatch, for: "player-a")
        ledger.merge([
            GameAchievementUpdate(id: .descentProcedure, percentComplete: 60)
        ])

        XCTAssertEqual(
            ledger.updatesToReport(for: "player-a"),
            [GameAchievementUpdate(id: .descentProcedure, percentComplete: 60)]
        )
        XCTAssertEqual(
            ledger.updatesToReport(for: "player-b"),
            [GameAchievementUpdate(id: .descentProcedure, percentComplete: 60)]
        )
    }

    func testDescentAchievementCoversAllNineFloorTransitions() {
        let expected = [10: 0, 9: 11, 8: 22, 7: 33, 6: 44, 5: 55, 4: 66, 3: 77, 2: 88, 1: 100]
        for floor in stride(from: 10, through: 1, by: -1) {
            var progress = GameProgress.newGame
            if floor >= 8 {
                progress.currentFloor = FloorID(rawValue: floor)!
            } else {
                progress.currentFloor = .floor7
                progress.isDemoComplete = true
                progress.expansion = ExpansionProgress(floorNumber: floor)
            }
            let descent = tracker.updates(for: progress).first { $0.id == .descentProcedure }
            XCTAssertEqual(descent?.percentComplete ?? 0, expected[floor], "Floor \(floor)")
        }
    }

    func testLegacyDemoHandoffAndFinalBossDefeatDoNotAwardFullGameCompletion() {
        var progress = GameProgress.newGame
        progress.currentFloor = .floor7
        progress.isDemoComplete = true
        let incompleteStages: [ExpansionProgress?] = [
            nil,
            ExpansionProgress(floorNumber: 7),
            ExpansionProgress(floorNumber: 1, stage: .bossDefeated),
            ExpansionProgress(floorNumber: 1, stage: .finalRecord),
            ExpansionProgress(floorNumber: 1, stage: .descent, descentStage: 3)
        ]
        for expansion in incompleteStages {
            progress.expansion = expansion
            XCTAssertFalse(tracker.updates(for: progress).contains { $0.id == .demoCompleted })
        }
        progress.expansion = ExpansionProgress(floorNumber: 1, stage: .complete, descentStage: 3)
        XCTAssertTrue(tracker.updates(for: progress).contains(
            GameAchievementUpdate(id: .demoCompleted, percentComplete: 100)
        ))
    }

    func testSpellArchiveAccumulatesDistinctSpellsAcrossRunsAndRelaunch() throws {
        XCTAssertEqual(SpellID.allCases.count, 28)
        let firstRun = Set(SpellID.allCases.prefix(15))
        let secondRun = Set(SpellID.allCases.suffix(15))
        var ledger = GameAchievementLedger()
        ledger.merge([], learnedSpells: firstRun)
        XCTAssertEqual(ledger.desiredPercentages[.spellArchive], 53)

        // Starting again and revisiting the same spells must neither erase nor double-count.
        ledger.merge([], learnedSpells: [])
        ledger.merge([], learnedSpells: firstRun)
        XCTAssertEqual(ledger.lifetimeLearnedSpells.count, 15)
        XCTAssertEqual(ledger.desiredPercentages[.spellArchive], 53)
        ledger = try JSONDecoder().decode(
            GameAchievementLedger.self, from: JSONEncoder().encode(ledger)
        )
        ledger.merge([], learnedSpells: secondRun)
        XCTAssertEqual(ledger.lifetimeLearnedSpells, Set(SpellID.allCases))
        XCTAssertEqual(ledger.desiredPercentages[.spellArchive], 100)
    }

    func testSpellArchiveCannotBeAwardedFromAnUnverifiedPercentage() {
        var ledger = GameAchievementLedger()
        ledger.merge([GameAchievementUpdate(id: .spellArchive, percentComplete: 100)])
        XCTAssertNil(ledger.desiredPercentages[.spellArchive])
        XCTAssertTrue(ledger.updatesToReport(for: "player").isEmpty)
    }

    func testLegacyLedgerRebuildsChangedRulesBeforeReportingToAnyPlayer() throws {
        let legacy = LegacyLedger(
            desiredPercentages: [.firstGlyph: 100, .spellArchive: 100, .descentProcedure: 100, .demoCompleted: 100],
            reportedPercentages: ["old-player": [.firstGlyph: 100, .spellArchive: 100, .descentProcedure: 100, .demoCompleted: 100]]
        )
        var ledger = try JSONDecoder().decode(
            GameAchievementLedger.self, from: JSONEncoder().encode(legacy)
        )
        XCTAssertEqual(ledger.desiredPercentages, [.firstGlyph: 100])
        XCTAssertEqual(ledger.reportedPercentages, legacy.reportedPercentages)
        XCTAssertTrue(ledger.lifetimeLearnedSpells.isEmpty)

        var savedGame = GameProgress.newGame
        savedGame.currentFloor = .floor7
        savedGame.isDemoComplete = true
        savedGame.expansion = ExpansionProgress(floorNumber: 7)
        savedGame.learnedSpells = Set(SpellID.allCases.prefix(2))
        ledger.merge(tracker.updates(for: savedGame), learnedSpells: savedGame.learnedSpells)
        let reports = Dictionary(uniqueKeysWithValues: ledger.updatesToReport(for: "new-player").map {
            ($0.id, $0.percentComplete)
        })
        XCTAssertEqual(reports[.firstGlyph], 100)
        XCTAssertEqual(reports[.descentProcedure], 33)
        XCTAssertEqual(reports[.spellArchive], 7)
        XCTAssertNil(reports[.demoCompleted])
        // Already awarded server progress cannot be undone or reported downward.
        XCTAssertTrue(ledger.updatesToReport(for: "old-player").isEmpty)
    }

    func testCurrentRulesSurviveRelaunchAndKeepFinalCompletionAcrossNewGames() throws {
        var complete = GameProgress.newGame
        complete.currentFloor = .floor7
        complete.expansion = ExpansionProgress(floorNumber: 1, stage: .complete, descentStage: 3)
        var ledger = GameAchievementLedger()
        ledger.merge(tracker.updates(for: complete), learnedSpells: Set(SpellID.allCases))
        ledger.acknowledge(ledger.updatesToReport(for: "player-a"), for: "player-a")
        let decoded = try JSONDecoder().decode(
            GameAchievementLedger.self, from: JSONEncoder().encode(ledger)
        )
        XCTAssertEqual(decoded, ledger)
        ledger = decoded
        ledger.merge(tracker.updates(for: .newGame), learnedSpells: [])
        XCTAssertEqual(ledger.desiredPercentages[.demoCompleted], 100)
        XCTAssertEqual(ledger.desiredPercentages[.descentProcedure], 100)
        XCTAssertEqual(ledger.desiredPercentages[.spellArchive], 100)
        XCTAssertTrue(ledger.updatesToReport(for: "player-a").isEmpty)
        XCTAssertEqual(ledger.updatesToReport(for: "player-b").count, 3)
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

    private struct LegacyLedger: Encodable {
        let desiredPercentages: [GameAchievementID: Int]
        let reportedPercentages: [String: [GameAchievementID: Int]]
    }
}
