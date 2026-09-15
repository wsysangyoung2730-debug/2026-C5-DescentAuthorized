import Foundation
import XCTest
@testable import DescentAuthorizedCore

final class ExpansionIntegrationTests: XCTestCase {
    func testCatalogPathsAndLegacyRewardMigration() throws {
        XCTAssertEqual(SpellID.allCases.count, 20)
        XCTAssertEqual(EnemyCatalog.all.count, 9)
        for spell in SpellCatalog.all.values {
            let result = GlyphEvaluator(maximumMana: 100).evaluate(spell: spell,
                strokes: strokes(spell), inputMethod: .pencil, erasureZones: [])
            XCTAssertTrue(result.succeeded, spell.name)
        }
        var seed = GameProgress.newGame
        seed.furthestCheckpoint = .demoComplete
        var controller = GameProgressionController(progress: seed)
        _ = try controller.travel(to: .demoComplete)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(controller.progress)) as? [String: Any])
        json["saveVersion"] = 3
        json["selectedRewardIDs"] = ["floor9-worn-b", "floor8-engraved"]
        for key in ["equippedSpells", "protectedAttack", "protectedDefense", "loadoutTutorials", "expansion"] { json.removeValue(forKey: key) }
        let migrated = try JSONDecoder().decode(GameProgress.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(migrated.selectedRewardIDs, ["floor9-barrier", "floor8-lingering"])
        XCTAssertTrue(migrated.learnedSpells.contains(.lingeringBarrier))
        XCTAssertLessThanOrEqual(migrated.equippedSpells.count, 6)
        try GameProgressValidator().validate(migrated)
        XCTAssertEqual(DemoGameSession(progress: migrated).progress.expansion?.stage, .entrance)
    }

    func testReservationSnapshotDelayAndSingleReducedHit() throws {
        var engine = CombatEngine(enemy: ExpansionEnemyCatalog.causalityVerificationAdministrator)
        _ = try engine.beginPlayerTurn(intent: .expansion(name: "증폭", action: .amplify(multiplier: 1.5)))
        try resolve(&engine)
        _ = try engine.beginPlayerTurn(intent: .expansion(name: "등록", action: .schedule([.init(name: "결과", damage: 32, turnsFromNow: 2)])))
        try resolve(&engine)
        let reservation = try XCTUnwrap(engine.state.expansion.scheduledDamage.first)
        XCTAssertEqual(reservation.damage, 48)
        XCTAssertNil(engine.state.expansion.enemyAmplification)
        _ = try engine.beginPlayerTurn(intent: idle)
        _ = try cast(.executionDelay, engine: &engine, target: .scheduledDamage(reservation.id))
        XCTAssertThrowsError(try cast(.executionDelay, engine: &engine, target: .scheduledDamage(reservation.id)))
        try resolve(&engine)
        _ = try engine.beginPlayerTurn(intent: idle)
        try resolve(&engine)
        XCTAssertEqual(engine.state.player.hp, 100)
        _ = try engine.beginPlayerTurn(intent: idle)
        _ = try cast(.outputReduction, engine: &engine)
        _ = try cast(.causalCushion, engine: &engine)
        try resolve(&engine)
        XCTAssertEqual(engine.state.player.hp, 99) // round(48 × .75 × .70) - 24 barrier
        XCTAssertTrue(engine.state.expansion.scheduledDamage.isEmpty)
        _ = try engine.beginPlayerTurn(intent: idle)
        try resolve(&engine)
        XCTAssertEqual(engine.state.player.hp, 99)
    }

    func testCopyTriggersOnceAndLocksKeepProtectedCoreUsable() throws {
        let loadout: [SpellID] = [.sealRelease, .riftSeverance, .basicBarrier, .chainInscription, .purificationGlyph, .executionDelay]
        let protected: Set<SpellID> = [.sealRelease, .riftSeverance, .basicBarrier]
        var engine = CombatEngine(enemy: ExpansionEnemyCatalog.memoryOriginalAdministrator,
            equippedSpells: loadout, protectedSpells: protected)
        _ = try engine.beginPlayerTurn(intent: .expansion(name: "기록", action: .recordLastSpell))
        _ = try cast(.riftSeverance, engine: &engine)
        try resolve(&engine)
        _ = try engine.beginPlayerTurn(intent: .expansion(name: "모사", action: .copyReaction(baseDamage: 10, categoryEffects: false, extraDamage: 12)))
        _ = try cast(.riftSeverance, engine: &engine)
        _ = try cast(.riftSeverance, engine: &engine)
        try resolve(&engine)
        XCTAssertEqual(engine.state.player.hp, 78)
        XCTAssertNil(engine.state.expansion.copyRecord)
        _ = try engine.beginPlayerTurn(intent: .expansion(name: "봉인", action: .lockAndSchedule(count: 2, damage: 40)))
        _ = try cast(.chainInscription, engine: &engine)
        try resolve(&engine)
        XCTAssertEqual(Set(engine.state.expansion.lockedSpells.keys), [.chainInscription, .purificationGlyph])
        XCTAssertTrue(protected.allSatisfy { engine.state.spellUnavailabilityReason(for: SpellCatalog.spell($0)) == nil })
        _ = try engine.beginPlayerTurn(intent: idle)
        let reservation = try XCTUnwrap(engine.state.expansion.scheduledDamage.first)
        _ = try cast(.executionDelay, engine: &engine, target: .scheduledDamage(reservation.id))
        try resolve(&engine)
        XCTAssertTrue(engine.state.expansion.lockedSpells.isEmpty)
        XCTAssertEqual(engine.state.expansion.scheduledDamage.count, 1)
    }

    func testAllFloorsRewardsAndResumableApprovalReachFourthFloor() throws {
        var seed = GameProgress.newGame
        seed.furthestCheckpoint = .demoComplete
        var progress = GameProgressionController(progress: seed)
        _ = try progress.travel(to: .demoComplete)
        XCTAssertEqual(progress.progress.learnedSpells.count, 6)
        for floor in stride(from: 7, through: 5, by: -1) {
            XCTAssertEqual(progress.progress.expansion?.floorNumber, floor)
            _ = try progress.advanceExpansion()
            if floor == 6 {
                XCTAssertEqual(progress.progress.expansion?.stage, .learnDebuff)
                _ = try progress.learnExpansionDebuff(grade: .approved)
            }
            _ = try progress.advanceExpansion()
            XCTAssertEqual(progress.progress.expansion?.stage, .residualBattle)
            _ = try progress.recordExpansionVictory(enemy: XCTUnwrap(ExpansionEnemyCatalog.enemy(floor: floor, isBoss: false)).id, remainingPlayerHP: 12)
            XCTAssertEqual(progress.progress.playerHP, 60)
            _ = try progress.advanceExpansion()
            _ = try progress.releaseExpansionSeal(grade: .approved)
            _ = try progress.advanceExpansion()
            _ = try progress.recordExpansionVictory(enemy: XCTUnwrap(ExpansionEnemyCatalog.enemy(floor: floor, isBoss: true)).id, remainingPlayerHP: 35)
            _ = try progress.advanceExpansion()
            let reward = try XCTUnwrap(RewardCatalog.candidates(forFloorNumber: floor).first)
            _ = try progress.selectReward(candidateID: reward.id)
            _ = try progress.completeRewardLearning(candidateID: reward.id, grade: .approved)
            try progress.approveExpansionStage(1)
            progress = GameProgressionController(progress: try JSONDecoder().decode(GameProgress.self, from: JSONEncoder().encode(progress.progress)))
            XCTAssertEqual(progress.progress.expansion?.descentStage, 1)
            XCTAssertThrowsError(try progress.advanceExpansion())
            try progress.approveExpansionStage(2)
            _ = try progress.advanceExpansion()
            try GameProgressValidator().validate(progress.progress)
        }
        XCTAssertTrue(progress.progress.expansion?.isComplete == true)
        XCTAssertEqual(progress.progress.learnedSpells.count, 10)
        XCTAssertEqual(progress.progress.equippedSpells.count, 6)
    }

    private var idle: EnemyAction { .expansion(name: "빈틈", action: .wait) }
    private func strokes(_ spell: SpellDefinition) -> [DrawnStroke] { spell.glyph.strokes.map { .init(points: $0.referencePath) } }
    @discardableResult private func cast(_ id: SpellID, engine: inout CombatEngine, target: ExpansionEffectTarget? = nil) throws -> [BattleEvent] {
        let spell = SpellCatalog.spell(id)
        return try engine.submitSpell(spell, strokes: strokes(spell), inputMethod: .pencil, selectedTarget: target)
    }
    private func resolve(_ engine: inout CombatEngine) throws {
        if engine.state.phase == .playerTurn { _ = try engine.endPlayerTurn() }
        if engine.state.phase == .resolvingEnemyAction { _ = try engine.resolveEnemyIntent() }
    }
}
