import XCTest
@testable import DescentAuthorizedCore

final class EnemyPatternTests: XCTestCase {
    func testRecordsAdministratorAlternatesAttackAndBarrier() throws {
        var encounter = EncounterController(enemy: EnemyCatalog.recordsAdministrator)
        _ = try encounter.start()
        XCTAssertEqual(encounter.state.currentEnemyIntent, EnemyCatalog.recordsAdministrator.pattern[0])

        _ = try encounter.finishTurnAndAdvance()
        XCTAssertEqual(encounter.state.currentEnemyIntent, EnemyCatalog.recordsAdministrator.pattern[1])

        _ = try encounter.finishTurnAndAdvance()
        XCTAssertEqual(encounter.state.currentEnemyIntent, EnemyCatalog.recordsAdministrator.pattern[0])
    }

    func testObservationResidualTelegraphsBeforeStrongAttack() throws {
        var encounter = EncounterController(enemy: EnemyCatalog.observationResidual)
        _ = try encounter.start()

        XCTAssertEqual(encounter.state.currentEnemyIntent, EnemyCatalog.observationResidual.pattern[0])
        _ = try encounter.finishTurnAndAdvance()
        XCTAssertEqual(encounter.state.currentEnemyIntent, EnemyCatalog.observationResidual.pattern[1])
        _ = try encounter.finishTurnAndAdvance()
        XCTAssertEqual(encounter.state.currentEnemyIntent, EnemyCatalog.observationResidual.pattern[2])
    }

    func testRecordsAdministratorAddsOneErasureZoneAtHalfHP() throws {
        var encounter = EncounterController(enemy: EnemyCatalog.recordsAdministrator)
        _ = try encounter.start()

        let spell = SpellCatalog.riftSeverance
        _ = try encounter.submitSpell(.riftSeverance, strokes: referenceStrokes(for: spell))
        let events = try encounter.submitSpell(.riftSeverance, strokes: referenceStrokes(for: spell))

        XCTAssertEqual(encounter.state.enemy.hp, 42)
        XCTAssertEqual(encounter.state.activeErasureZones.count, 1)
        XCTAssertTrue(events.contains { event in
            if case .erasureZoneAdded = event { return true }
            return false
        })

        _ = try encounter.finishTurnAndAdvance()
        _ = try encounter.submitSpell(.riftSeverance, strokes: referenceStrokes(for: spell))
        XCTAssertEqual(encounter.state.activeErasureZones.count, 1)
    }

    func testObservationAdministratorRegeneratesBarrierOnceAtHalfHP() throws {
        var encounter = EncounterController(enemy: EnemyCatalog.observationAdministrator)
        _ = try encounter.start()

        try cast(.sealRelease, in: &encounter)
        try cast(.riftSeverance, in: &encounter)
        _ = try encounter.finishTurnAndAdvance()

        try cast(.riftSeverance, in: &encounter)
        let thresholdEvents = try cast(.afterglowErasure, in: &encounter)

        XCTAssertLessThanOrEqual(encounter.state.enemy.hpFraction, 0.5)
        XCTAssertEqual(encounter.state.enemy.absoluteBarrierCharges, 1)
        XCTAssertTrue(thresholdEvents.contains(.absoluteBarrierChanged(target: encounter.state.enemy.id, charges: 1)))
        XCTAssertEqual(encounter.state.triggeredThresholdRuleIDs.count, 1)
    }

    func testScriptedObservationBattleReachesVictory() throws {
        var encounter = EncounterController(enemy: EnemyCatalog.observationAdministrator)
        _ = try encounter.start()

        var safetyCounter = 0
        while encounter.state.phase != .victory && encounter.state.phase != .defeat {
            safetyCounter += 1
            XCTAssertLessThan(safetyCounter, 20)

            if encounter.state.phase == .playerTurn {
                if encounter.state.enemy.absoluteBarrierCharges > 0,
                   encounter.state.resources.remainingStrokes > 0 {
                    try cast(.sealRelease, in: &encounter)
                }

                if encounter.state.phase == .playerTurn,
                   encounter.state.resources.remainingStrokes > 0 {
                    if isStrongAttack(encounter.state.currentEnemyIntent) {
                        try cast(.basicBarrier, in: &encounter)
                    } else if encounter.state.resources.remainingMana >= SpellCatalog.riftSeverance.recommendedMana {
                        try cast(.riftSeverance, in: &encounter)
                    } else {
                        try cast(.afterglowErasure, in: &encounter)
                    }
                }

                if encounter.state.phase == .playerTurn,
                   encounter.state.resources.remainingStrokes > 0,
                   !isStrongAttack(encounter.state.currentEnemyIntent) {
                    try cast(.afterglowErasure, in: &encounter)
                }
            }

            _ = try encounter.finishTurnAndAdvance()
        }

        XCTAssertEqual(encounter.state.phase, .victory)
        XCTAssertGreaterThan(encounter.state.player.hp, 0)
    }

    @discardableResult
    private func cast(
        _ id: SpellID,
        in encounter: inout EncounterController
    ) throws -> [BattleEvent] {
        let spell = SpellCatalog.spell(id)
        return try encounter.submitSpell(id, strokes: referenceStrokes(for: spell))
    }

    private func referenceStrokes(for spell: SpellDefinition) -> [DrawnStroke] {
        spell.glyph.strokes.map { DrawnStroke(points: $0.referencePath) }
    }

    private func isStrongAttack(_ action: EnemyAction?) -> Bool {
        guard case let .attack(_, _, isStrong) = action else { return false }
        return isStrong
    }
}
