import Foundation

enum CombatCommandError: Error, Equatable {
    case invalidPhase(expected: BattlePhase, actual: BattlePhase)
    case spellNotLearned(SpellID)
    case insufficientStrokes(required: Int, remaining: Int)
    case invalidStrokeSubmission(required: Int, submitted: Int)
    case missingEnemyIntent
    case battleAlreadyFinished
}

struct BattleState: Equatable, Sendable {
    var phase: BattlePhase
    var turnNumber: Int
    var player: CombatantState
    var enemy: CombatantState
    var resources: TurnResources
    var learnedSpells: Set<SpellID>
    var currentEnemyIntent: EnemyAction?
    var activeErasureZones: [ErasureZone]
    var triggeredThresholdRuleIDs: Set<String>
    var castsThisTurn: [SpellID]
}

struct CombatEngine: Sendable {
    let enemyDefinition: EnemyDefinition
    private(set) var state: BattleState

    init(
        enemy: EnemyDefinition,
        playerHP: Int = 100,
        playerNormalBarrier: Int = 0,
        learnedSpells: Set<SpellID> = Set(SpellID.allCases)
    ) {
        enemyDefinition = enemy
        state = BattleState(
            phase: .preparing,
            turnNumber: 0,
            player: CombatantState(
                id: .player,
                name: "익명 봉인관",
                maxHP: 100,
                hp: playerHP,
                normalBarrier: playerNormalBarrier
            ),
            enemy: CombatantState(
                id: .enemy(enemy.id),
                name: enemy.name,
                maxHP: enemy.maxHP,
                absoluteBarrierCharges: enemy.startingAbsoluteBarrierCharges
            ),
            resources: .demoDefault,
            learnedSpells: learnedSpells,
            currentEnemyIntent: nil,
            activeErasureZones: [],
            triggeredThresholdRuleIDs: [],
            castsThisTurn: []
        )
    }

    mutating func startBattle() -> [BattleEvent] {
        guard state.phase == .preparing, state.turnNumber == 0 else { return [] }

        var events: [BattleEvent] = [.battleStarted(enemy: enemyDefinition.id)]
        if state.player.normalBarrier > 0 {
            events.append(
                .normalBarrierChanged(
                    target: state.player.id,
                    amount: state.player.normalBarrier
                )
            )
        }
        if state.enemy.absoluteBarrierCharges > 0 {
            events.append(
                .absoluteBarrierChanged(
                    target: state.enemy.id,
                    charges: state.enemy.absoluteBarrierCharges
                )
            )
        }
        return events
    }

    mutating func beginPlayerTurn(intent: EnemyAction) throws -> [BattleEvent] {
        try ensureBattleCanContinue()
        guard state.phase == .preparing else {
            throw CombatCommandError.invalidPhase(expected: .preparing, actual: state.phase)
        }

        state.turnNumber += 1
        state.phase = .playerTurn
        state.resources.reset()
        state.castsThisTurn = []
        state.currentEnemyIntent = intent

        return [
            .turnStarted(number: state.turnNumber, intent: intent),
            .resourcesChanged(
                mana: state.resources.remainingMana,
                strokes: state.resources.remainingStrokes
            )
        ]
    }

    mutating func submitSpell(
        _ spell: SpellDefinition,
        strokes: [DrawnStroke],
        inputMethod: DrawingInputMethod
    ) throws -> [BattleEvent] {
        try ensureBattleCanContinue()
        guard state.phase == .playerTurn else {
            throw CombatCommandError.invalidPhase(expected: .playerTurn, actual: state.phase)
        }
        guard state.learnedSpells.contains(spell.id) else {
            throw CombatCommandError.spellNotLearned(spell.id)
        }
        guard strokes.count == spell.requiredStrokes else {
            throw CombatCommandError.invalidStrokeSubmission(
                required: spell.requiredStrokes,
                submitted: strokes.count
            )
        }
        guard state.resources.remainingStrokes >= spell.requiredStrokes else {
            throw CombatCommandError.insufficientStrokes(
                required: spell.requiredStrokes,
                remaining: state.resources.remainingStrokes
            )
        }

        let evaluator = GlyphEvaluator(maximumMana: state.resources.remainingMana)
        let evaluation = evaluator.evaluate(
            spell: spell,
            strokes: strokes,
            inputMethod: inputMethod,
            erasureZones: state.activeErasureZones
        )

        state.resources.remainingStrokes -= spell.requiredStrokes
        state.resources.remainingMana = max(
            0,
            state.resources.remainingMana - evaluation.manaUsed
        )
        state.castsThisTurn.append(spell.id)

        var events: [BattleEvent]
        if evaluation.succeeded {
            events = [.spellResolved(spell: spell.id, grade: evaluation.grade)]
            events.append(contentsOf: apply(spell.effect, grade: evaluation.grade))
        } else {
            events = [
                .spellRejected(
                    spell: spell.id,
                    reason: evaluation.failure ?? .incompleteGlyph
                )
            ]
        }

        events.append(
            .resourcesChanged(
                mana: state.resources.remainingMana,
                strokes: state.resources.remainingStrokes
            )
        )

        if state.enemy.isDefeated {
            state.phase = .victory
            events.append(.enemyActionCancelled)
            events.append(.victory(enemyDefinition.id))
        } else if state.resources.remainingStrokes == 0 || state.resources.remainingMana == 0 {
            state.phase = .resolvingEnemyAction
        }

        return events
    }

    mutating func endPlayerTurn() throws -> [BattleEvent] {
        try ensureBattleCanContinue()
        guard state.phase == .playerTurn else {
            throw CombatCommandError.invalidPhase(expected: .playerTurn, actual: state.phase)
        }

        var events = [BattleEvent]()
        if state.enemy.normalBarrier > 0 {
            state.enemy.normalBarrier = 0
            events.append(.normalBarrierChanged(target: state.enemy.id, amount: 0))
        }
        state.phase = .resolvingEnemyAction
        return events
    }

    mutating func resolveEnemyIntent() throws -> [BattleEvent] {
        try ensureBattleCanContinue()
        guard state.phase == .resolvingEnemyAction else {
            throw CombatCommandError.invalidPhase(
                expected: .resolvingEnemyAction,
                actual: state.phase
            )
        }
        guard let intent = state.currentEnemyIntent else {
            throw CombatCommandError.missingEnemyIntent
        }

        var events: [BattleEvent] = [.enemyActionStarted(intent)]
        switch intent {
        case let .attack(_, damage, _):
            events.append(contentsOf: applyDamage(damage, to: &state.player, piercesNormalBarrier: false))

        case let .grantNormalBarrier(_, amount):
            state.enemy.normalBarrier = max(state.enemy.normalBarrier, amount)
            events.append(
                .normalBarrierChanged(
                    target: state.enemy.id,
                    amount: state.enemy.normalBarrier
                )
            )

        case let .grantAbsoluteBarrier(_, charges):
            state.enemy.absoluteBarrierCharges += charges
            events.append(
                .absoluteBarrierChanged(
                    target: state.enemy.id,
                    charges: state.enemy.absoluteBarrierCharges
                )
            )

        case .telegraph:
            break
        }

        state.currentEnemyIntent = nil
        if state.player.isDefeated {
            state.phase = .defeat
            events.append(.defeat)
        } else {
            state.phase = .preparing
        }
        return events
    }

    mutating func addErasureZone(_ zone: ErasureZone) -> [BattleEvent] {
        guard !state.activeErasureZones.contains(where: { $0.id == zone.id }) else {
            return []
        }
        state.activeErasureZones.append(zone)
        return [.erasureZoneAdded(zone)]
    }

    mutating func grantEnemyAbsoluteBarrier(charges: Int) -> [BattleEvent] {
        guard charges > 0 else { return [] }
        state.enemy.absoluteBarrierCharges += charges
        return [
            .absoluteBarrierChanged(
                target: state.enemy.id,
                charges: state.enemy.absoluteBarrierCharges
            )
        ]
    }

    mutating func markThresholdRuleTriggered(_ id: String) {
        state.triggeredThresholdRuleIDs.insert(id)
    }

    private mutating func apply(_ effect: SpellEffect, grade: CastingGrade) -> [BattleEvent] {
        switch effect {
        case let .damage(base, piercesNormalBarrier):
            guard state.enemy.absoluteBarrierCharges == 0 else {
                return [.attackNegatedByAbsoluteBarrier(target: state.enemy.id)]
            }

            let damage = Int((Double(base) * grade.damageMultiplier).rounded())
            return applyDamage(
                damage,
                to: &state.enemy,
                piercesNormalBarrier: piercesNormalBarrier
            )

        case let .fixedBarrier(amount, maxStack):
            state.player.normalBarrier = min(state.player.normalBarrier + amount, maxStack)
            return [
                .normalBarrierChanged(
                    target: state.player.id,
                    amount: state.player.normalBarrier
                )
            ]

        case let .dispelAbsoluteBarrier(charges):
            guard state.enemy.absoluteBarrierCharges > 0 else { return [] }
            state.enemy.absoluteBarrierCharges = max(
                0,
                state.enemy.absoluteBarrierCharges - charges
            )
            return [
                .absoluteBarrierChanged(
                    target: state.enemy.id,
                    charges: state.enemy.absoluteBarrierCharges
                )
            ]
        }
    }

    private func applyDamage(
        _ amount: Int,
        to target: inout CombatantState,
        piercesNormalBarrier: Bool
    ) -> [BattleEvent] {
        guard amount > 0 else { return [] }

        var events = [BattleEvent]()
        var hpDamage = amount

        if target.normalBarrier > 0 {
            if piercesNormalBarrier {
                target.normalBarrier = 0
                events.append(.normalBarrierChanged(target: target.id, amount: 0))
            } else {
                let absorbed = min(target.normalBarrier, amount)
                target.normalBarrier -= absorbed
                hpDamage -= absorbed
                events.append(
                    .normalBarrierChanged(
                        target: target.id,
                        amount: target.normalBarrier
                    )
                )
            }
        }

        if hpDamage > 0 {
            target.hp = max(0, target.hp - hpDamage)
            events.append(
                .damageApplied(
                    target: target.id,
                    amount: hpDamage,
                    remainingHP: target.hp
                )
            )
        }
        return events
    }

    private func ensureBattleCanContinue() throws {
        if state.phase == .victory || state.phase == .defeat {
            throw CombatCommandError.battleAlreadyFinished
        }
    }
}
