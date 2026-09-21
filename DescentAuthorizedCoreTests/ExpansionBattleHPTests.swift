import Foundation
import XCTest
@testable import DescentAuthorizedCore

final class ExpansionBattleHPTests: XCTestCase {
    func testEveryNewExpansionFloorRestoresFullHPOnlyOnEntry() throws {
        var seed = GameProgress.newGame
        seed.currentScene = .demoComplete
        seed.isDemoComplete = true
        seed.playerHP = 9
        var controller = GameProgressionController(progress: seed)
        try controller.beginExpansion()
        XCTAssertEqual(controller.progress.playerHP, 100)
        controller.setExpansionPlayerHP(31)
        try controller.beginExpansion()
        XCTAssertEqual(controller.progress.playerHP, 31, "Revisiting an existing floor must not heal it")
        for floor in stride(from: 7, through: 5, by: -1) {
            try controller.updateExpansion(.init(floorNumber: floor, stage: .descent, descentStage: 2))
            controller.setExpansionPlayerHP(9)
            _ = try controller.advanceExpansion()
            XCTAssertEqual(controller.progress.expansion?.floorNumber, floor - 1)
            XCTAssertEqual(controller.progress.playerHP, 100)
        }
    }

    func testSixthFloorLearnsDiscoveredScrollBeforeEncounter() throws {
        var seed = GameProgress.newGame
        seed.currentScene = .demoComplete
        seed.isDemoComplete = true
        seed.expansion = .init(floorNumber: 6, stage: .entrance)
        seed.learnedSpells = [.afterglowErasure, .basicBarrier, .sealRelease]
        var controller = GameProgressionController(progress: seed)
        _ = try controller.advanceExpansion()
        XCTAssertEqual(controller.progress.expansion?.stage, .learnDebuff)
        _ = try controller.learnExpansionDebuff(grade: .approved)
        XCTAssertEqual(controller.progress.expansion?.stage, .preparation)
        XCTAssertTrue(controller.progress.learnedSpells.contains(.outputReduction))
        _ = try controller.advanceExpansion()
        XCTAssertEqual(controller.progress.expansion?.stage, .residualEncounter)
    }

    func testAllSixEncountersKeepEntryHPAndRestartAtFullHP() throws {
        for floor in 5...7 {
            for boss in [false, true] {
                var seed = GameProgress.newGame
                seed.currentScene = .demoComplete
                seed.isDemoComplete = true
                seed.expansion = .init(floorNumber: floor, stage: boss ? .bossPreparation : .preparation)
                seed.playerHP = 37
                seed.learnedSpells = [.afterglowErasure, .basicBarrier, .sealRelease, .outputReduction]
                var session = DemoGameSession(progress: seed)
                _ = try session.handle(.advanceExpansion)
                XCTAssertEqual(session.progress.expansion?.stage, boss ? .bossEncounter : .residualEncounter)
                XCTAssertThrowsError(try session.handle(.startEncounter))
                XCTAssertNil(session.battleState)
                _ = try session.handle(.advanceExpansion)
                _ = try session.handle(.startEncounter)
                XCTAssertEqual(session.battleState?.player.hp, 37, "\(floor), boss=\(boss)")
                XCTAssertEqual(session.battleState?.enemy.hp, ExpansionEnemyCatalog.enemy(floor: floor, isBoss: boss)?.maxHP)

                // Relaunch in an unfinished fight returns to preparation with full HP.
                let saved = try JSONDecoder().decode(GameProgress.self, from: JSONEncoder().encode(session.progress))
                let resumed = DemoGameSession(progress: saved)
                XCTAssertEqual(resumed.progress.playerHP, 100)
                XCTAssertEqual(resumed.progress.expansion?.stage, boss ? .bossPreparation : .preparation)
                XCTAssertNil(resumed.battleState)

                for _ in 0..<40 {
                    if session.battleState?.phase == .defeat { break }
                    _ = try session.handle(.finishTurn)
                }
                XCTAssertEqual(session.battleState?.phase, .defeat)
                _ = try session.handle(.restartEncounter)
                XCTAssertNil(session.battleState)
                XCTAssertEqual(session.progress.playerHP, 100)
                _ = try session.handle(.advanceExpansion)
                XCTAssertEqual(session.progress.expansion?.stage, boss ? .bossEncounter : .residualEncounter)
                XCTAssertThrowsError(try session.handle(.startEncounter))
                XCTAssertNil(session.battleState)
                _ = try session.handle(.advanceExpansion)
                _ = try session.handle(.startEncounter)
                XCTAssertEqual(session.battleState?.player.hp, 100)
                XCTAssertEqual(session.battleState?.turnNumber, 1)
                XCTAssertTrue(session.battleState?.expansion.scheduledDamage.isEmpty == true)
            }
        }
    }
}
