import Foundation

struct EncounterController: Sendable {
    private(set) var combat: CombatEngine
    private var nextPatternIndex: Int

    init(
        enemy: EnemyDefinition,
        playerHP: Int = 100,
        learnedSpells: Set<SpellID> = Set(SpellID.allCases)
    ) {
        combat = CombatEngine(
            enemy: enemy,
            playerHP: playerHP,
            learnedSpells: learnedSpells
        )
        nextPatternIndex = 0
    }

    var state: BattleState { combat.state }
    var enemyDefinition: EnemyDefinition { combat.enemyDefinition }

    mutating func start() throws -> [BattleEvent] {
        var events = combat.startBattle()
        events.append(contentsOf: try beginNextTurn())
        return events
    }

    mutating func submitSpell(
        _ spellID: SpellID,
        strokes: [DrawnStroke],
        inputMethod: DrawingInputMethod = .pencil
    ) throws -> [BattleEvent] {
        let spell = SpellCatalog.spell(spellID)
        var events = try combat.submitSpell(
            spell,
            strokes: strokes,
            inputMethod: inputMethod
        )
        events.append(contentsOf: applyPendingThresholdRules())
        return events
    }

    mutating func finishTurnAndAdvance() throws -> [BattleEvent] {
        guard state.phase != .victory, state.phase != .defeat else { return [] }

        var events = [BattleEvent]()
        if state.phase == .playerTurn {
            events.append(contentsOf: try combat.endPlayerTurn())
        }
        if state.phase == .resolvingEnemyAction {
            events.append(contentsOf: try combat.resolveEnemyIntent())
        }
        if state.phase == .preparing {
            events.append(contentsOf: try beginNextTurn())
        }
        return events
    }

    private mutating func beginNextTurn() throws -> [BattleEvent] {
        let pattern = enemyDefinition.pattern
        precondition(!pattern.isEmpty, "Enemy pattern must not be empty")

        let intent = pattern[nextPatternIndex]
        nextPatternIndex = (nextPatternIndex + 1) % pattern.count
        return try combat.beginPlayerTurn(intent: intent)
    }

    private mutating func applyPendingThresholdRules() -> [BattleEvent] {
        guard !state.enemy.isDefeated else { return [] }

        var events = [BattleEvent]()
        for rule in enemyDefinition.thresholdRules {
            guard !state.triggeredThresholdRuleIDs.contains(rule.id),
                  state.enemy.hpFraction <= rule.hpFraction else {
                continue
            }

            combat.markThresholdRuleTriggered(rule.id)
            switch rule.effect {
            case let .addErasureZone(zone):
                events.append(contentsOf: combat.addErasureZone(zone))
            case let .grantAbsoluteBarrier(charges):
                events.append(contentsOf: combat.grantEnemyAbsoluteBarrier(charges: charges))
            }
        }
        return events
    }
}

