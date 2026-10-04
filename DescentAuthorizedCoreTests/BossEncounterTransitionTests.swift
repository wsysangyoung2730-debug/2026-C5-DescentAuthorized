import XCTest
@testable import DescentAuthorizedCore

/// Camera playback is transient UI state. These tests protect the real progression boundary
/// that must remain unchanged until the post-dialogue presentation explicitly completes.
final class BossEncounterTransitionTests: XCTestCase {
    func testEveryBossWaitsForPresentationCompletionBeforeStartingCombat() throws {
        for floor in 1...9 {
            var session = try preparedSession(floor: floor)
            _ = try session.handle(enterCommand(floor: floor))
            let pendingProgress = session.progress
            XCTAssertNil(session.encounter, "floor \(floor)")
            XCTAssertNil(session.battleState, "floor \(floor)")
            XCTAssertThrowsError(try session.handle(.startEncounter), "floor \(floor)")
            XCTAssertEqual(session.progress, pendingProgress, "floor \(floor)")
            XCTAssertNoThrow(try GameProgressValidator().validate(pendingProgress))
            if floor <= 7 {
                let narrative = try XCTUnwrap(ExpansionNarrative(progress: XCTUnwrap(pendingProgress.expansion)))
                XCTAssertTrue(narrative.isBoss)
                XCTAssertFalse(narrative.isDefeated)
            }

            _ = try session.handle(completionCommand(floor: floor))
            XCTAssertThrowsError(try session.handle(completionCommand(floor: floor)), "floor \(floor)")
            _ = try session.handle(.startEncounter)
            let expectedEnemy: EnemyID = floor == 9 ? .recordsAdministrator : floor == 8
                ? .observationAdministrator : try XCTUnwrap(ExpansionEnemyCatalog.enemy(floor: floor, isBoss: true)).id
            XCTAssertEqual(session.battleState?.enemy.id, .enemy(expectedEnemy), "floor \(floor)")
            XCTAssertThrowsError(try session.handle(.startEncounter), "floor \(floor)")
        }
    }

    func testSavingDuringBossPresentationRestoresPreparationWithoutStartingCombat() throws {
        for floor in 1...9 {
            var session = try preparedSession(floor: floor)
            _ = try session.handle(enterCommand(floor: floor))
            var pending = session.progress
            pending.playerHP = 73
            let store = InMemoryGameSaveStore(progress: pending)
            let restored = try DemoGameSession.restore(from: store)
            XCTAssertEqual(restored.progress.playerHP, 73, "floor \(floor)")
            XCTAssertNil(restored.encounter, "floor \(floor)")
            if floor <= 7 {
                XCTAssertEqual(restored.progress.expansion?.floorNumber, floor)
                XCTAssertEqual(restored.progress.expansion?.stage, .bossPreparation)
            } else {
                XCTAssertEqual(restored.progress.currentScene, floor == 9
                    ? .floor9RecordsPreparation : .floor8AdministratorPreparation)
            }
            XCTAssertNoThrow(try GameProgressValidator().validate(restored.progress))
        }
    }

    func testCheckpointTravelDuringPresentationLeavesNoActiveBossBattle() throws {
        for floor in 1...9 {
            var session = try preparedSession(floor: floor)
            _ = try session.handle(enterCommand(floor: floor))
            _ = try session.handle(.travelToCheckpoint(checkpoint(floor: floor)))
            XCTAssertNil(session.encounter, "floor \(floor)")
            XCTAssertThrowsError(try session.handle(.startEncounter), "floor \(floor)")
            if floor <= 7 {
                XCTAssertEqual(session.progress.expansion?.stage, .bossPreparation)
            } else {
                XCTAssertEqual(session.progress.currentScene, floor == 9
                    ? .floor9RecordsPreparation : .floor8AdministratorPreparation)
            }
        }
    }

    private func preparedSession(floor: Int) throws -> DemoGameSession {
        var seed = GameProgress.newGame
        seed.furthestCheckpoint = .towerHandoffComplete
        var session = DemoGameSession(progress: seed)
        _ = try session.handle(.travelToCheckpoint(checkpoint(floor: floor)))
        return session
    }

    private func checkpoint(floor: Int) -> CheckpointID {
        floor == 9 ? .recordsBattle : floor == 8 ? .observationBattle
            : CheckpointID(rawValue: "floor\(floor)BossEncounter")!
    }

    private func enterCommand(floor: Int) -> DemoCommand {
        floor == 9 ? .enterRecordsEncounter : floor == 8 ? .enterAdministratorEncounter
            : floor <= 4 ? .beginPreparedLowerBattle : .advanceExpansion
    }

    private func completionCommand(floor: Int) -> DemoCommand {
        floor == 9 ? .beginRecordsBattle : floor == 8 ? .beginAdministratorBattle : .advanceExpansion
    }
}
