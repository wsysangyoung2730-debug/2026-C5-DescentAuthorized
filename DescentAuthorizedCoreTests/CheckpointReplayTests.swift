import Foundation
import XCTest
@testable import DescentAuthorizedCore

final class CheckpointReplayTests: XCTestCase {
    private func unlockedController() -> GameProgressionController {
        var seed = GameProgress.newGame
        seed.furthestCheckpoint = .towerHandoffComplete
        return GameProgressionController(progress: seed)
    }

    func testEveryCheckpointRestoresAValidSaveAndSurvivesRelaunch() throws {
        var controller = unlockedController()
        for checkpoint in CheckpointID.allCases {
            _ = try controller.travel(to: checkpoint)
            XCTAssertEqual(controller.progress.checkpoint, checkpoint)
            XCTAssertEqual(controller.progress.playerHP, 100)
            try GameProgressValidator().validate(controller.progress)
            let saved = try JSONEncoder().encode(controller.progress)
            let resumed = DemoGameSession(progress: try JSONDecoder().decode(GameProgress.self, from: saved))
            XCTAssertEqual(resumed.progress.checkpoint, checkpoint)
            XCTAssertEqual(resumed.progress.expansion, checkpoint.expansionDestination)
            try GameProgressValidator().validate(resumed.progress)
        }
    }

    func testChangedRewardReplacesOldSpellInLowerFloorsAfterSaveAndRepeatedTravel() throws {
        var controller = unlockedController()
        let rewards: [(Int, CheckpointID)] = [(7, .floor7Reward), (6, .floor6Reward), (5, .floor5Reward)]
        for (floor, checkpoint) in rewards {
            let candidates = RewardCatalog.candidates(forFloorNumber: floor)
            for chosen in candidates {
                _ = try controller.travel(to: checkpoint)
                for candidate in candidates {
                    XCTAssertFalse(controller.progress.learnedSpells.contains(RewardCatalog.learningSpell(for: candidate)))
                    XCTAssertFalse(controller.progress.selectedRewardIDs.contains(candidate.id))
                }
                _ = try controller.selectReward(candidateID: chosen.id)
                _ = try controller.completeRewardLearning(candidateID: chosen.id, grade: .approved)
                controller = GameProgressionController(progress: try JSONDecoder().decode(
                    GameProgress.self, from: JSONEncoder().encode(controller.progress)))
                _ = try controller.travel(to: .floor5Complete)
                XCTAssertTrue(controller.progress.learnedSpells.contains(RewardCatalog.learningSpell(for: chosen)))
                XCTAssertTrue(controller.progress.selectedRewardIDs.contains(chosen.id))
                for other in candidates where other.id != chosen.id {
                    let spell = RewardCatalog.learningSpell(for: other)
                    XCTAssertFalse(controller.progress.learnedSpells.contains(spell))
                    XCTAssertFalse(controller.progress.equippedSpells.contains(spell))
                    XCTAssertFalse(controller.progress.completedTrainingSpells.contains(spell))
                    XCTAssertNil(controller.progress.spellMastery[spell])
                }
                try GameProgressValidator().validate(controller.progress)
            }
        }
        // Revisit the user's specific destination with the revised 7F choice.
        _ = try controller.travel(to: .floor6BossEncounter)
        XCTAssertTrue(controller.progress.learnedSpells.contains(.consequenceErasure))
        XCTAssertFalse(controller.progress.learnedSpells.contains(.axisSeverance))
        XCTAssertFalse(controller.progress.learnedSpells.contains(.anchorGuard))
        XCTAssertFalse(controller.progress.learnedSpells.contains(.executionDelay))
    }

    func testInvestigationCanRepeatAndEncounterSkipsOnlyItsOwnCompletedInvestigation() throws {
        var controller = unlockedController()
        let checkpoints: [(Int, CheckpointID, CheckpointID)] = [
            (7, .demoComplete, .floor7Encounter),
            (6, .floor6Investigation, .floor6Encounter),
            (5, .floor5Investigation, .floor5Encounter)
        ]
        for (floor, investigation, encounter) in checkpoints {
            _ = try controller.travel(to: encounter)
            XCTAssertTrue(ExpansionInvestigationCatalog.isComplete(floor: floor, readRecordIDs: controller.progress.readRecordIDs))
            for _ in 0..<2 {
                _ = try controller.travel(to: investigation)
                XCTAssertFalse(ExpansionInvestigationCatalog.isComplete(floor: floor, readRecordIDs: controller.progress.readRecordIDs))
                for later in 5...floor {
                    XCTAssertTrue(Set(ExpansionInvestigationCatalog.records(for: later).map(\.id))
                        .isDisjoint(with: controller.progress.readRecordIDs))
                }
                for record in ExpansionInvestigationCatalog.records(for: floor) {
                    XCTAssertNotNil(controller.readRecord(id: record.id))
                }
                XCTAssertEqual(controller.progress.checkpoint, floor == 6 ? .floor6Learning : encounter)
            }
        }
        _ = try controller.travel(to: .floor10Complete)
        XCTAssertFalse(controller.progress.readRecordIDs.contains("9-entrance-01"))
        _ = try controller.travel(to: .floor8Start)
        XCTAssertFalse(controller.progress.readRecordIDs.contains("floor8.entrance.warning-tags"))
        _ = try controller.travel(to: .floor10Start)
        XCTAssertTrue(controller.progress.readRecordIDs.isEmpty)
    }

    func testSixthFloorLearningAndDescentApprovalAreReplayable() throws {
        var controller = unlockedController()
        _ = try controller.travel(to: .floor6Learning)
        XCTAssertTrue(ExpansionInvestigationCatalog.isComplete(floor: 6, readRecordIDs: controller.progress.readRecordIDs))
        XCTAssertFalse(controller.progress.learnedSpells.contains(.outputReduction))
        _ = try controller.learnExpansionDebuff(grade: .approved)
        XCTAssertEqual(controller.progress.checkpoint, .floor6Encounter)
        _ = try controller.travel(to: .floor6Descent)
        try controller.approveExpansionStage(1)
        _ = try controller.travel(to: .floor6Descent)
        XCTAssertEqual(controller.progress.expansion?.descentStage, 0)
        XCTAssertTrue(controller.progress.learnedSpells.contains(.outputReduction))
    }

    func testActualProgressUnlocksCheckpointsWithoutUnlockingUnreachedFloor() throws {
        var seed = GameProgress.newGame
        seed.furthestCheckpoint = .demoComplete
        var controller = GameProgressionController(progress: seed)
        _ = try controller.travel(to: .demoComplete)
        XCTAssertThrowsError(try controller.travel(to: .floor7Reward))
        for record in ExpansionInvestigationCatalog.records(for: 7) { _ = controller.readRecord(id: record.id) }
        XCTAssertEqual(controller.progress.furthestCheckpoint, .floor7Encounter)
        _ = try controller.advanceExpansion()
        _ = try controller.advanceExpansion()
        _ = try controller.advanceExpansion()
        _ = try controller.recordExpansionVictory(enemy: .coordinateDriftResidual, remainingPlayerHP: 80)
        XCTAssertEqual(controller.progress.furthestCheckpoint, .floor7SealedDoor)
        _ = try controller.advanceExpansion()
        _ = try controller.releaseExpansionSeal(grade: .approved)
        XCTAssertEqual(controller.progress.furthestCheckpoint, .floor7BossEncounter)
        _ = try controller.advanceExpansion()
        _ = try controller.advanceExpansion()
        _ = try controller.recordExpansionVictory(enemy: .coordinateCorrectionAdministrator, remainingPlayerHP: 70)
        XCTAssertEqual(controller.progress.furthestCheckpoint, .floor7Reward)
        _ = try controller.advanceExpansion()
        _ = try controller.selectReward(candidateID: "floor7-anchor")
        _ = try controller.completeRewardLearning(candidateID: "floor7-anchor", grade: .approved)
        XCTAssertEqual(controller.progress.furthestCheckpoint, .floor7Descent)
        try controller.approveExpansionStage(1)
        try controller.approveExpansionStage(2)
        _ = try controller.advanceExpansion()
        XCTAssertEqual(controller.progress.furthestCheckpoint, .floor6Investigation)
        XCTAssertThrowsError(try controller.travel(to: .floor6BossEncounter))
    }

    func testVersionFiveSaveMigratesItsActualExpansionLocationAndRewardChoices() throws {
        var controller = unlockedController()
        _ = try controller.travel(to: .floor7Reward)
        _ = try controller.selectReward(candidateID: "floor7-anchor")
        _ = try controller.completeRewardLearning(candidateID: "floor7-anchor", grade: .approved)
        _ = try controller.travel(to: .floor6BossEncounter)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(controller.progress)) as? [String: Any])
        json["saveVersion"] = 5
        json["checkpoint"] = "demoComplete"
        json["furthestCheckpoint"] = "demoComplete"
        json.removeValue(forKey: "checkpointRewardChoices")
        let migrated = try JSONDecoder().decode(GameProgress.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(migrated.checkpoint, .floor6BossEncounter)
        XCTAssertEqual(migrated.furthestCheckpoint, .floor6BossEncounter)
        XCTAssertEqual(migrated.checkpointRewardChoices[7], "floor7-anchor")
        try GameProgressValidator().validate(migrated)
    }
}
