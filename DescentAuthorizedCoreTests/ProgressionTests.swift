import Foundation
import XCTest
@testable import DescentAuthorizedCore

final class ProgressionTests: XCTestCase {
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
        _ = try controller.releaseObservationDoor()
        _ = try controller.beginAdministratorBattle()
        _ = try controller.completeEncounter(
            enemy: .observationAdministrator,
            remainingPlayerHP: 18
        )
        _ = try controller.selectReward(candidateID: "floor8-forbidden")
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

    func testEveryFloor9CandidateResolvesToBarrierPiercing() throws {
        for candidate in RewardCatalog.candidates(for: .floor9) {
            var controller = try makeFloor9RewardController()

            _ = try controller.selectReward(candidateID: candidate.id)

            XCTAssertTrue(controller.progress.learnedSpells.contains(.barrierPiercing))
            XCTAssertEqual(controller.progress.selectedRewardIDs, [candidate.id])
            XCTAssertEqual(controller.progress.currentScene, .floor9DescentDoor)
        }
    }

    func testRewardCanOnlyBeSelectedOnce() throws {
        var controller = try makeFloor9RewardController()
        _ = try controller.selectReward(candidateID: "floor9-worn-b")

        XCTAssertThrowsError(try controller.selectReward(candidateID: "floor9-sealed"))
    }

    func testRecoveryRulesAreAppliedAtFloorBoundaries() throws {
        var controller = try makeFloor9RewardController(remainingHP: 35)
        _ = try controller.selectReward(candidateID: "floor9-worn-a")
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
}
