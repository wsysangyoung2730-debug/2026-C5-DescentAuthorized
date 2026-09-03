import Foundation
import XCTest
@testable import DescentAuthorizedCore

final class ProgressionTests: XCTestCase {
    func testScrollLearningCompletesFloor10SpellsWithoutLegacyTrainingScene() throws {
        var controller = GameProgressionController()

        _ = try controller.leaveMeetingRoom()
        let afterglowEvents = try controller.completeScrollLearning(
            spell: .afterglowErasure,
            grade: .precise
        )

        XCTAssertEqual(controller.progress.currentScene, .floor10GlyphArchive)
        XCTAssertTrue(controller.progress.learnedSpells.contains(.afterglowErasure))
        XCTAssertTrue(controller.progress.completedTrainingSpells.contains(.afterglowErasure))
        XCTAssertTrue(afterglowEvents.contains(.spellLearned(.afterglowErasure)))

        _ = try controller.completeScrollLearning(
            spell: .riftSeverance,
            grade: .approved
        )

        XCTAssertEqual(controller.progress.currentScene, .floor10DescentDoor)
        XCTAssertTrue(controller.progress.learnedSpells.contains(.riftSeverance))
        XCTAssertTrue(controller.progress.completedTrainingSpells.contains(.riftSeverance))
    }

    func testBarrierScrollLearningHappensBeforeFloor8Entry() throws {
        var controller = try makeFloor8AntechamberController()

        _ = try controller.completeScrollLearning(
            spell: .basicBarrier,
            grade: .approved
        )

        XCTAssertEqual(controller.progress.currentScene, .floor8Antechamber)
        XCTAssertTrue(controller.progress.learnedSpells.contains(.basicBarrier))
        XCTAssertTrue(controller.progress.completedTrainingSpells.contains(.basicBarrier))

        _ = try controller.enterProtectionRoom()

        XCTAssertEqual(controller.progress.currentScene, .floor8ResidualEncounter)
        XCTAssertEqual(controller.progress.checkpoint, .residualBattle)
    }

    func testSealReleaseIsLearnedFromScrollAfterResidualDefeat() throws {
        var controller = try makeFloor8AntechamberController()
        _ = try controller.completeScrollLearning(spell: .basicBarrier, grade: .approved)
        _ = try controller.enterProtectionRoom()
        _ = try controller.beginResidualBattle()
        let victoryEvents = try controller.completeEncounter(
            enemy: .observationResidual,
            remainingPlayerHP: 55
        )

        XCTAssertFalse(controller.progress.learnedSpells.contains(.sealRelease))
        XCTAssertFalse(victoryEvents.contains(.spellLearned(.sealRelease)))

        _ = try controller.continueAfterResidualDefeat()
        _ = try controller.completeScrollLearning(spell: .sealRelease, grade: .perfect)

        XCTAssertEqual(controller.progress.currentScene, .floor8SealedDoor)
        XCTAssertTrue(controller.progress.learnedSpells.contains(.sealRelease))
        XCTAssertTrue(controller.progress.completedTrainingSpells.contains(.sealRelease))
    }

    func testFullDemoProgressionReachesFloor7WithAllDemoSpells() throws {
        var controller = GameProgressionController()

        _ = try controller.leaveMeetingRoom()
        _ = try controller.learnAfterglowErasure()
        _ = try controller.completeTraining(spell: .afterglowErasure, grade: .approved)
        _ = try controller.learnRiftSeverance()
        _ = try controller.completeTraining(spell: .riftSeverance, grade: .precise)
        _ = try controller.approveDescentDoor()

        _ = try controller.enterRecordsBattle()
        _ = try controller.beginRecordsBattle()
        _ = try controller.completeEncounter(
            enemy: .recordsAdministrator,
            remainingPlayerHP: 40
        )
        _ = try controller.continueAfterRecordsDefeat()
        _ = try controller.selectReward(candidateID: "floor9-worn-a")
        _ = try controller.completeRewardLearning(
            candidateID: "floor9-worn-a",
            grade: .approved
        )
        _ = try controller.approveDescentDoor()

        _ = try controller.enterProtectionRoom()
        _ = try controller.learnBasicBarrier()
        _ = try controller.completeProtectionTraining(grade: .approved)
        _ = try controller.beginResidualBattle()
        _ = try controller.completeEncounter(
            enemy: .observationResidual,
            remainingPlayerHP: 25
        )
        _ = try controller.continueAfterResidualDefeat()
        _ = try controller.completeScrollLearning(spell: .sealRelease, grade: .approved)
        _ = try controller.releaseObservationDoor()
        _ = try controller.beginAdministratorBattle()
        _ = try controller.completeEncounter(
            enemy: .observationAdministrator,
            remainingPlayerHP: 18
        )
        _ = try controller.continueAfterAdministratorDefeat()
        _ = try controller.selectReward(candidateID: "floor8-forbidden")
        _ = try controller.completeRewardLearning(
            candidateID: "floor8-forbidden",
            grade: .approved
        )
        let completionEvents = try controller.approveDescentDoor()

        XCTAssertEqual(controller.progress.currentFloor, .floor7)
        XCTAssertEqual(controller.progress.currentScene, .demoComplete)
        XCTAssertEqual(controller.progress.checkpoint, .demoComplete)
        XCTAssertEqual(controller.progress.learnedSpells, Set(SpellID.allCases))
        XCTAssertEqual(controller.progress.defeatedEnemies, Set(EnemyID.allCases))
        XCTAssertTrue(controller.progress.isDemoComplete)
        XCTAssertTrue(completionEvents.contains(.demoCompleted))
    }

    func testProgressionRejectsActionsFromWrongScene() throws {
        var controller = GameProgressionController()

        XCTAssertThrowsError(try controller.enterRecordsBattle()) { error in
            XCTAssertEqual(
                error as? ProgressionError,
                .invalidScene(expected: [.floor9Entrance], actual: .floor10MeetingRoom)
            )
        }

        _ = try controller.leaveMeetingRoom()
        XCTAssertThrowsError(
            try controller.completeTraining(spell: .afterglowErasure, grade: .approved)
        )
    }

    func testEveryFloor9CandidateRequiresPracticeBeforeDescent() throws {
        for candidate in RewardCatalog.candidates(for: .floor9) {
            var controller = try makeFloor9RewardController()

            _ = try controller.selectReward(candidateID: candidate.id)

            XCTAssertFalse(controller.progress.learnedSpells.contains(.barrierPiercing))
            XCTAssertEqual(controller.progress.selectedRewardIDs, [candidate.id])
            XCTAssertEqual(controller.progress.currentScene, .floor9RewardVault)

            _ = try controller.completeRewardLearning(
                candidateID: candidate.id,
                grade: .precise
            )

            XCTAssertTrue(controller.progress.learnedSpells.contains(.barrierPiercing))
            XCTAssertTrue(controller.progress.completedTrainingSpells.contains(.barrierPiercing))
            XCTAssertEqual(controller.progress.currentScene, .floor9DescentDoor)
        }
    }

    func testRewardLearningRejectsFailedOrUnselectedTracing() throws {
        var controller = try makeFloor9RewardController()

        XCTAssertThrowsError(
            try controller.completeRewardLearning(
                candidateID: "floor9-worn-a",
                grade: .approved
            )
        )

        _ = try controller.selectReward(candidateID: "floor9-worn-a")
        XCTAssertThrowsError(
            try controller.completeRewardLearning(
                candidateID: "floor9-worn-a",
                grade: .rejected
            )
        )
        XCTAssertEqual(controller.progress.currentScene, .floor9RewardVault)
    }

    func testRewardCanOnlyBeSelectedOnce() throws {
        var controller = try makeFloor9RewardController()
        _ = try controller.selectReward(candidateID: "floor9-worn-b")

        XCTAssertThrowsError(try controller.selectReward(candidateID: "floor9-sealed"))
    }

    func testRecoveryRulesAreAppliedAtFloorBoundaries() throws {
        var controller = try makeFloor9RewardController(remainingHP: 35)
        _ = try controller.selectReward(candidateID: "floor9-worn-a")
        _ = try controller.completeRewardLearning(
            candidateID: "floor9-worn-a",
            grade: .approved
        )
        _ = try controller.approveDescentDoor()
        XCTAssertEqual(controller.progress.playerHP, 65)

        _ = try controller.enterProtectionRoom()
        _ = try controller.learnBasicBarrier()
        _ = try controller.completeProtectionTraining(grade: .approved)
        _ = try controller.beginResidualBattle()
        _ = try controller.completeEncounter(
            enemy: .observationResidual,
            remainingPlayerHP: 10
        )
        XCTAssertEqual(controller.progress.playerHP, 60)
    }

    func testMasteryTracksBestGradeAndSuccessfulCastCount() throws {
        var controller = GameProgressionController()
        _ = try controller.leaveMeetingRoom()
        _ = try controller.learnAfterglowErasure()
        _ = try controller.completeTraining(spell: .afterglowErasure, grade: .approved)

        _ = try controller.recordCasting(
            spell: .afterglowErasure,
            grade: .perfect,
            succeeded: true
        )
        _ = try controller.recordCasting(
            spell: .afterglowErasure,
            grade: .incomplete,
            succeeded: true
        )
        let rejected = try controller.recordCasting(
            spell: .afterglowErasure,
            grade: .rejected,
            succeeded: false
        )

        XCTAssertEqual(
            controller.progress.spellMastery[.afterglowErasure],
            SpellMastery(bestGrade: .perfect, successfulCasts: 3)
        )
        XCTAssertNil(rejected)
    }

    func testInMemoryStoreRoundTripsProgress() throws {
        var controller = GameProgressionController()
        _ = try controller.leaveMeetingRoom()
        _ = controller.readRecord(id: "10-01")
        let store = InMemoryGameSaveStore()

        try controller.save(to: store)
        let restored = try GameProgressionController.restore(from: store)

        XCTAssertEqual(restored.progress, controller.progress)
    }

    func testFileStoreRoundTripsAndDeletesProgress() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("save.json")
        let store = FileGameSaveStore(fileURL: fileURL)
        defer { try? FileManager.default.removeItem(at: directory) }

        var controller = GameProgressionController()
        _ = try controller.leaveMeetingRoom()
        _ = try controller.learnAfterglowErasure()
        try controller.save(to: store)

        XCTAssertEqual(try store.load(), controller.progress)
        try store.delete()
        XCTAssertNil(try store.load())
    }

    func testEmptyStoreRestoresNewGame() throws {
        let restored = try GameProgressionController.restore(
            from: InMemoryGameSaveStore()
        )

        XCTAssertEqual(restored.progress, .newGame)
    }

    private func makeFloor9RewardController(
        remainingHP: Int = 60
    ) throws -> GameProgressionController {
        var controller = GameProgressionController()
        _ = try controller.leaveMeetingRoom()
        _ = try controller.learnAfterglowErasure()
        _ = try controller.completeTraining(spell: .afterglowErasure, grade: .approved)
        _ = try controller.learnRiftSeverance()
        _ = try controller.completeTraining(spell: .riftSeverance, grade: .approved)
        _ = try controller.approveDescentDoor()
        _ = try controller.enterRecordsBattle()
        _ = try controller.beginRecordsBattle()
        _ = try controller.completeEncounter(
            enemy: .recordsAdministrator,
            remainingPlayerHP: remainingHP
        )
        _ = try controller.continueAfterRecordsDefeat()
        return controller
    }

    private func makeFloor8AntechamberController() throws -> GameProgressionController {
        var controller = try makeFloor9RewardController()
        _ = try controller.selectReward(candidateID: "floor9-worn-a")
        _ = try controller.completeRewardLearning(
            candidateID: "floor9-worn-a",
            grade: .approved
        )
        _ = try controller.approveDescentDoor()
        return controller
    }
}
