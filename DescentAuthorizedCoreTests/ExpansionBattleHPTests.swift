import Foundation
import XCTest
@testable import DescentAuthorizedCore

final class ExpansionBattleHPTests: XCTestCase {
    func testAllSixEncountersKeepEntryHPAndRestartAtFullHP() throws {
        for floor in 5...7 {
            for boss in [false, true] {
                var seed = GameProgress.newGame
                seed.currentScene = .demoComplete
                seed.isDemoComplete = true
                seed.expansion = .init(floorNumber: floor, stage: boss ? .bossPreparation : .preparation)
                seed.playerHP = 37
                seed.learnedSpells = [.afterglowErasure, .basicBarrier, .sealRelease]
                var session = DemoGameSession(progress: seed)
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
                _ = try session.handle(.startEncounter)
                XCTAssertEqual(session.battleState?.player.hp, 100)
                XCTAssertEqual(session.battleState?.turnNumber, 1)
                XCTAssertTrue(session.battleState?.expansion.scheduledDamage.isEmpty == true)
            }
        }
    }
}
