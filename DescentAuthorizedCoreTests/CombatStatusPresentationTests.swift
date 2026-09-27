import XCTest
@testable import DescentAuthorizedCore

final class CombatStatusPresentationTests: XCTestCase {
    func testEffectsFollowAffectedCombatantAndThreatsStayWithEnemy() {
        var battle = CombatEngine(enemy: ExpansionEnemyCatalog.causalityVerificationAdministrator).state
        battle.phase = .playerTurn
        battle.expansion.playerAttackWeakening = .init(multiplier: 0.7, expiresAfterTurn: 2)
        battle.expansion.outputReduction = .init(multiplier: 0.75, expiresAfterTurn: 2)
        battle.expansion.enemyAmplification = 1.5
        battle.expansion.enemyPreservation = .init(multiplier: 0.7, expiresAfterTurn: 2)
        battle.expansion.directHitProhibitionThroughTurn = 2
        battle.expansion.chainAttackBonus = 12
        battle.expansion.lockedSpells[.basicBarrier] = 2
        battle.expansion.mimicProhibitionThroughEnemyTurn = 2
        let player = Set(battle.statusItems(for: .player).map(\.id))
        let enemy = Set(battle.statusItems(for: .enemy).map(\.id))
        XCTAssertEqual(player, ["weakening", "direct", "chain", "lock-basicBarrier"])
        XCTAssertEqual(enemy, ["output", "amplification", "preservation", "mimic"])
        XCTAssertTrue(player.isDisjoint(with: enemy))
        XCTAssertTrue(battle.showsCombatStatus)
    }

    func testFinishedBattleRemovesEffectsAndTheirHitArea() {
        var battle = CombatEngine(enemy: ExpansionEnemyCatalog.causalityVerificationAdministrator).state
        battle.expansion.counterDamage = 14
        battle.expansion.nextHitFlatReduction = 6
        for phase in [BattlePhase.victory, .defeat, .preparing] {
            battle.phase = phase
            XCTAssertTrue(battle.statusItems(for: .player).isEmpty)
            XCTAssertTrue(battle.statusItems(for: .enemy).isEmpty)
            XCTAssertFalse(battle.showsCombatStatus)
        }
    }
}
