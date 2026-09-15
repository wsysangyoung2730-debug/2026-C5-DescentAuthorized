import Foundation

struct EncounterController: Sendable {
    private(set) var combat: CombatEngine
    private var nextPatternIndex: Int
    private var firstPhaseTwoCycle = false

    init(
        enemy: EnemyDefinition,
        playerHP: Int = 100,
        playerNormalBarrier: Int = 0,
        learnedSpells: Set<SpellID> = Set(SpellID.allCases),
        equippedSpells: [SpellID]? = nil,
        protectedSpells: Set<SpellID> = []
    ) {
        combat = CombatEngine(
            enemy: enemy,
            playerHP: playerHP,
            playerNormalBarrier: playerNormalBarrier,
            learnedSpells: learnedSpells,
            equippedSpells: equippedSpells,
            protectedSpells: protectedSpells
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
        inputMethod: DrawingInputMethod = .pencil,
        selectedTarget: ExpansionEffectTarget? = nil
    ) throws -> [BattleEvent] {
        let spell = SpellCatalog.spell(spellID)
        var events = try combat.submitSpell(
            spell,
            strokes: strokes,
            inputMethod: inputMethod,
            selectedTarget: selectedTarget
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
        var events: [BattleEvent] = []
        // Lock the phase at cycle boundaries so a displayed intent never changes mid-turn.
        if nextPatternIndex == 0,
           state.expansion.encounterPhase == 1,
           state.enemy.hpFraction <= 0.5,
           ExpansionEnemyCatalog.phaseTwoPattern(for: enemyDefinition.id, firstCycle: true) != nil {
            combat.setEncounterPhase(2)
            firstPhaseTwoCycle = true
            events.append(.expansionChanged(message: "2단계 시작 · 이번 주기부터 강화된 절차 적용"))
        }
        let pattern = state.expansion.encounterPhase == 2
            ? ExpansionEnemyCatalog.phaseTwoPattern(for: enemyDefinition.id, firstCycle: firstPhaseTwoCycle) ?? enemyDefinition.pattern
            : enemyDefinition.pattern
        precondition(!pattern.isEmpty, "Enemy pattern must not be empty")

        let intent = pattern[nextPatternIndex]
        nextPatternIndex = (nextPatternIndex + 1) % pattern.count
        if nextPatternIndex == 0, state.expansion.encounterPhase == 2 {
            firstPhaseTwoCycle = false
        }
        events.append(contentsOf: try combat.beginPlayerTurn(intent: intent))
        return events
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
