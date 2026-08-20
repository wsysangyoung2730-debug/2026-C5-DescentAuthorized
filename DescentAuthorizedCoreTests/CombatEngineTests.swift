import XCTest
@testable import DescentAuthorizedCore

final class CombatEngineTests: XCTestCase {
    func testPerfectAttackAppliesDamageMultiplier() throws {
        var engine = makeEngine()
        _ = engine.startBattle()
        _ = try engine.beginPlayerTurn(intent: weakAttack)

        let spell = SpellCatalog.afterglowErasure
        let events = try engine.submitSpell(
            spell,
            strokes: referenceStrokes(for: spell),
            inputMethod: .pencil
        )

        XCTAssertEqual(engine.state.enemy.hp, 95)
        XCTAssertTrue(events.contains(.damageApplied(target: engine.state.enemy.id, amount: 25, remainingHP: 95)))
    }

    func testAbsoluteBarrierNegatesAttackWithoutLosingCharge() throws {
        var engine = CombatEngine(enemy: EnemyCatalog.observationAdministrator)
        _ = try engine.beginPlayerTurn(intent: weakAttack)
        let spell = SpellCatalog.riftSeverance

        let events = try engine.submitSpell(
            spell,
            strokes: referenceStrokes(for: spell),
            inputMethod: .pencil
        )

        XCTAssertEqual(engine.state.enemy.hp, 165)
        XCTAssertEqual(engine.state.enemy.absoluteBarrierCharges, 1)
        XCTAssertTrue(events.contains(.attackNegatedByAbsoluteBarrier(target: engine.state.enemy.id)))
    }

    func testSealReleaseRemovesOneAbsoluteBarrierCharge() throws {
        var engine = CombatEngine(enemy: EnemyCatalog.observationAdministrator)
        _ = try engine.beginPlayerTurn(intent: weakAttack)
        let spell = SpellCatalog.sealRelease

        _ = try engine.submitSpell(
            spell,
            strokes: referenceStrokes(for: spell),
            inputMethod: .pencil
        )

        XCTAssertEqual(engine.state.enemy.absoluteBarrierCharges, 0)
        XCTAssertEqual(engine.state.enemy.hp, 165)
    }

    func testBarrierPiercingDamagesHPAndClearsNormalBarrier() throws {
        var engine = makeEngine()
        _ = try engine.beginPlayerTurn(
            intent: .grantNormalBarrier(name: "문서 방벽", amount: 22)
        )
        _ = try engine.endPlayerTurn()
        _ = try engine.resolveEnemyIntent()
        XCTAssertEqual(engine.state.enemy.normalBarrier, 22)

        _ = try engine.beginPlayerTurn(intent: weakAttack)
        let spell = SpellCatalog.barrierPiercing
        _ = try engine.submitSpell(
            spell,
            strokes: referenceStrokes(for: spell),
            inputMethod: .pencil
        )

        XCTAssertEqual(engine.state.enemy.normalBarrier, 0)
        XCTAssertEqual(engine.state.enemy.hp, 72)
    }

    func testBasicBarrierStacksToMaximumForty() throws {
        var engine = makeEngine()
        _ = try engine.beginPlayerTurn(intent: weakAttack)
        let spell = SpellCatalog.basicBarrier

        _ = try engine.submitSpell(
            spell,
            strokes: referenceStrokes(for: spell),
            inputMethod: .pencil
        )
        _ = try engine.submitSpell(
            spell,
            strokes: referenceStrokes(for: spell),
            inputMethod: .pencil
        )

        XCTAssertEqual(engine.state.player.normalBarrier, 40)
        XCTAssertEqual(engine.state.resources.remainingStrokes, 0)
        XCTAssertEqual(engine.state.phase, .resolvingEnemyAction)
    }

    func testEnemyDamageConsumesBarrierBeforeHP() throws {
        var engine = makeEngine()
        _ = try engine.beginPlayerTurn(
            intent: .attack(name: "강공격", damage: 42, isStrong: true)
        )
        let barrier = SpellCatalog.basicBarrier
        _ = try engine.submitSpell(
            barrier,
            strokes: referenceStrokes(for: barrier),
            inputMethod: .pencil
        )
        _ = try engine.endPlayerTurn()
        _ = try engine.resolveEnemyIntent()

        XCTAssertEqual(engine.state.player.normalBarrier, 0)
        XCTAssertEqual(engine.state.player.hp, 78)
    }

    func testTwoStrokeSpellConsumesWholeTurn() throws {
        var engine = makeEngine()
        _ = try engine.beginPlayerTurn(intent: weakAttack)
        let spell = SpellCatalog.barrierPiercing

        _ = try engine.submitSpell(
            spell,
            strokes: referenceStrokes(for: spell),
            inputMethod: .pencil
        )

        XCTAssertEqual(engine.state.resources.remainingStrokes, 0)
        XCTAssertEqual(engine.state.phase, .resolvingEnemyAction)
    }

    func testLethalSpellCancelsEnemyAction() throws {
        let fragileEnemy = EnemyDefinition(
            id: .recordsAdministrator,
            name: "시험 대상",
            maxHP: 10,
            startingAbsoluteBarrierCharges: 0,
            pattern: [weakAttack],
            thresholdRules: []
        )
        var engine = CombatEngine(enemy: fragileEnemy)
        _ = try engine.beginPlayerTurn(intent: weakAttack)
        let spell = SpellCatalog.afterglowErasure

        let events = try engine.submitSpell(
            spell,
            strokes: referenceStrokes(for: spell),
            inputMethod: .pencil
        )

        XCTAssertEqual(engine.state.phase, .victory)
        XCTAssertTrue(events.contains(.enemyActionCancelled))
        XCTAssertTrue(events.contains(.victory(.recordsAdministrator)))
    }

    func testUnlearnedSpellCannotBeCast() throws {
        var engine = CombatEngine(
            enemy: EnemyCatalog.recordsAdministrator,
            learnedSpells: [.afterglowErasure]
        )
        _ = try engine.beginPlayerTurn(intent: weakAttack)

        XCTAssertThrowsError(
            try engine.submitSpell(
                SpellCatalog.riftSeverance,
                strokes: referenceStrokes(for: SpellCatalog.riftSeverance),
                inputMethod: .pencil
            )
        ) { error in
            XCTAssertEqual(error as? CombatCommandError, .spellNotLearned(.riftSeverance))
        }
    }

    private var weakAttack: EnemyAction {
        .attack(name: "시험 공격", damage: 10, isStrong: false)
    }

    private func makeEngine() -> CombatEngine {
        CombatEngine(enemy: EnemyCatalog.recordsAdministrator)
    }

    private func referenceStrokes(for spell: SpellDefinition) -> [DrawnStroke] {
        spell.glyph.strokes.map { DrawnStroke(points: $0.referencePath) }
    }
}
