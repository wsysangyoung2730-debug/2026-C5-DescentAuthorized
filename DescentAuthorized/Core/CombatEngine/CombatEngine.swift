import Foundation

enum CombatCommandError: Error, Equatable {
    case invalidPhase(expected: BattlePhase, actual: BattlePhase)
    case spellNotLearned(SpellID)
    case insufficientStrokes(required: Int, remaining: Int)
    case invalidStrokeSubmission(required: Int, submitted: Int)
    case missingEnemyIntent
    case battleAlreadyFinished
    case spellUnavailable(String)
    case invalidEffectTarget
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
    var expansion: ExpansionBattleState = ExpansionBattleState()
}

struct CombatEngine: Sendable {
    let enemyDefinition: EnemyDefinition
    private(set) var state: BattleState

    init(
        enemy: EnemyDefinition,
        playerHP: Int = 100,
        playerNormalBarrier: Int = 0,
        learnedSpells: Set<SpellID> = Set(SpellID.allCases),
        equippedSpells: [SpellID]? = nil,
        protectedSpells: Set<SpellID> = []
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
            castsThisTurn: [],
            expansion: ExpansionBattleState(equippedSpells: equippedSpells, protectedSpells: protectedSpells)
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
        state.expansion.lastSuccessfulSpellThisTurn = nil
        let preparedIntent = preparedIntent(intent)
        state.currentEnemyIntent = preparedIntent
        var events: [BattleEvent] = []
        if state.expansion.nextTurnBarrier > 0 {
            events.append(contentsOf: grantPlayerBarrier(state.expansion.nextTurnBarrier))
            state.expansion.nextTurnBarrier = 0
        }

        events.append(contentsOf: [
            .turnStarted(number: state.turnNumber, intent: preparedIntent),
            .resourcesChanged(
                mana: state.resources.remainingMana,
                strokes: state.resources.remainingStrokes
            )
        ])
        return events
    }

    mutating func submitSpell(
        _ spell: SpellDefinition,
        strokes: [DrawnStroke],
        inputMethod: DrawingInputMethod,
        selectedTarget: ExpansionEffectTarget? = nil
    ) throws -> [BattleEvent] {
        try ensureBattleCanContinue()
        guard state.phase == .playerTurn else {
            throw CombatCommandError.invalidPhase(expected: .playerTurn, actual: state.phase)
        }
        guard state.learnedSpells.contains(spell.id) else {
            throw CombatCommandError.spellNotLearned(spell.id)
        }
        if let reason = state.spellUnavailabilityReason(for: spell) {
            throw CombatCommandError.spellUnavailable(reason)
        }
        let targets = state.availableEffectTargets(for: spell)
        if let selectedTarget, !targets.contains(where: { $0.id == selectedTarget }) {
            throw CombatCommandError.invalidEffectTarget
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

        let previousStatus = state.expansion.statusSummary
        var events: [BattleEvent]
        if evaluation.succeeded {
            events = [.spellResolved(spell: spell.id, grade: evaluation.grade)]
            events.append(contentsOf: apply(
                spell.effect,
                effectStrength: evaluation.effectStrength,
                spellID: spell.id,
                target: selectedTarget ?? targets.first?.id
            ))
            recordSuccessfulSpell(spell)
            if previousStatus != state.expansion.statusSummary {
                events.append(.expansionChanged(message: state.expansion.statusSummary))
            }
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
            state.expansion.clearTransientEffects()
            events.append(.enemyActionCancelled)
            events.append(.victory(enemyDefinition.id))
        } else if state.resources.remainingStrokes == 0 || state.resources.remainingMana == 0 {
            events.append(contentsOf: finishPlayerWindow())
            state.phase = .resolvingEnemyAction
        }

        return events
    }

    mutating func endPlayerTurn() throws -> [BattleEvent] {
        try ensureBattleCanContinue()
        guard state.phase == .playerTurn else {
            throw CombatCommandError.invalidPhase(expected: .playerTurn, actual: state.phase)
        }

        let events = finishPlayerWindow()
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

        let previousStatus = state.expansion.statusSummary
        var events: [BattleEvent] = [.enemyActionStarted(intent)]
        switch intent {
        case let .attack(_, damage, _):
            events.append(contentsOf: damagePlayer(damage, scheduled: false))

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

        case let .expansion(_, action):
            events.append(contentsOf: resolveExpansionAction(action))

        case .telegraph:
            break
        }

        events.append(contentsOf: resolveDueReservations())
        expireEnemyWindowEffects()
        if previousStatus != state.expansion.statusSummary {
            events.append(.expansionChanged(message: state.expansion.statusSummary))
        }
        state.currentEnemyIntent = nil
        if state.player.isDefeated {
            state.phase = .defeat
            state.expansion.clearTransientEffects()
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

    private mutating func apply(
        _ effect: SpellEffect,
        effectStrength: Double,
        spellID: SpellID,
        target: ExpansionEffectTarget?
    ) -> [BattleEvent] {
        switch effect {
        case let .damage(minimum, maximum, piercesNormalBarrier):
            guard state.enemy.absoluteBarrierCharges == 0 else {
                return [.attackNegatedByAbsoluteBarrier(target: state.enemy.id)]
            }

            let damage = scaledEffect(
                minimum: minimum,
                maximum: maximum,
                strength: effectStrength
            )
            return damageEnemy(damage, piercesNormalBarrier: piercesNormalBarrier)

        case let .fixedBarrier(minimum, maximum, maxStack):
            let amount = scaledEffect(
                minimum: minimum,
                maximum: maximum,
                strength: effectStrength
            )
            state.player.normalBarrier = min(state.player.normalBarrier + amount, maxStack)
            return [
                .normalBarrierChanged(
                    target: state.player.id,
                    amount: state.player.normalBarrier
                )
            ]

        case let .dispelAbsoluteBarrier(minimumCharges, maximumCharges):
            guard state.enemy.absoluteBarrierCharges > 0 else { return [] }
            let charges = scaledEffect(
                minimum: minimumCharges,
                maximum: maximumCharges,
                strength: effectStrength
            )
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
        case let .expansion(effect):
            return applyExpansionSpell(effect, strength: effectStrength, spellID: spellID, target: target)
        }
    }

    private func scaledEffect(
        minimum: Int,
        maximum: Int,
        strength: Double
    ) -> Int {
        let clampedStrength = min(max(strength, 0), 1)
        return minimum + Int(
            (Double(maximum - minimum) * clampedStrength).rounded()
        )
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

extension CombatEngine {
    mutating func setEncounterPhase(_ phase: Int) {
        state.expansion.encounterPhase = max(1, phase)
    }

    private mutating func recordSuccessfulSpell(_ spell: SpellDefinition) {
        if state.expansion.copyRecord?.spell == spell.id {
            state.expansion.copyRecord?.reused = true
        }
        state.expansion.lastSuccessfulSpell = spell.id
        state.expansion.lastSuccessfulSpellThisTurn = spell.id
        state.expansion.successfulSpellHistory.removeAll { $0 == spell.id }
        state.expansion.successfulSpellHistory.append(spell.id)
    }

    private mutating func finishPlayerWindow() -> [BattleEvent] {
        state.expansion.chainAttackBonus = 0
        if let value = state.expansion.playerAttackWeakening, value.expiresAfterTurn <= state.turnNumber {
            state.expansion.playerAttackWeakening = nil
        }
        if let value = state.expansion.enemyPreservation, value.expiresAfterTurn <= state.turnNumber {
            state.expansion.enemyPreservation = nil
        }
        // Correction barriers must survive until the telegraphed strike reads them.
        if state.enemy.normalBarrier > 0, !state.expansion.retainsCorrectionBarrier {
            state.enemy.normalBarrier = 0
            return [.normalBarrierChanged(target: state.enemy.id, amount: 0)]
        }
        return []
    }

    private mutating func expireEnemyWindowEffects() {
        state.expansion.nextHitFlatReduction = 0
        state.expansion.scheduledHitReduction = nil
        if let modifier = state.expansion.outputReduction, modifier.expiresAfterTurn <= state.turnNumber {
            state.expansion.outputReduction = nil
        }
        if let turn = state.expansion.mimicProhibitionThroughEnemyTurn, turn <= state.turnNumber {
            state.expansion.mimicProhibitionThroughEnemyTurn = nil
        }
        state.expansion.lockedSpells = state.expansion.lockedSpells.filter { $0.value > state.turnNumber }
    }

    private mutating func grantPlayerBarrier(_ amount: Int) -> [BattleEvent] {
        state.player.normalBarrier = min(40, state.player.normalBarrier + max(0, amount))
        return [.normalBarrierChanged(target: state.player.id, amount: state.player.normalBarrier)]
    }

    private mutating func damageEnemy(_ base: Int, piercesNormalBarrier: Bool = false) -> [BattleEvent] {
        guard state.enemy.absoluteBarrierCharges == 0 else {
            return [.attackNegatedByAbsoluteBarrier(target: state.enemy.id)]
        }
        var damage = Double(base + state.expansion.chainAttackBonus)
        state.expansion.chainAttackBonus = 0
        if let preservation = state.expansion.enemyPreservation {
            damage *= preservation.multiplier
            state.expansion.enemyPreservation = nil
        }
        if let weakening = state.expansion.playerAttackWeakening {
            damage *= weakening.multiplier
            state.expansion.playerAttackWeakening = nil
        }
        return applyDamage(max(0, Int(damage.rounded())), to: &state.enemy, piercesNormalBarrier: piercesNormalBarrier)
    }

    private mutating func damagePlayer(_ amount: Int, scheduled: Bool) -> [BattleEvent] {
        guard amount > 0, !state.player.isDefeated else { return [] }
        var damage = Double(amount)
        if let reduction = state.expansion.outputReduction {
            damage *= reduction.multiplier
            state.expansion.outputReduction = nil
        }
        if scheduled, let reduction = state.expansion.scheduledHitReduction {
            damage *= reduction
            state.expansion.scheduledHitReduction = nil
        }
        damage -= Double(state.expansion.nextHitFlatReduction)
        state.expansion.nextHitFlatReduction = 0
        return applyDamage(max(0, Int(damage.rounded())), to: &state.player, piercesNormalBarrier: false)
    }

    private mutating func applyExpansionSpell(
        _ effect: ExpansionSpellEffect,
        strength: Double,
        spellID: SpellID,
        target: ExpansionEffectTarget?
    ) -> [BattleEvent] {
        let amount = scaledEffect(minimum: effect.range.lowerBound, maximum: effect.range.upperBound, strength: strength)
        switch effect {
        case .chainInscription:
            guard state.enemy.absoluteBarrierCharges == 0 else { return [.attackNegatedByAbsoluteBarrier(target: state.enemy.id)] }
            let events = damageEnemy(amount)
            state.expansion.chainAttackBonus = 12
            return events
        case .purificationGlyph:
            guard let target else { return [] }
            switch target {
            case .playerAttackWeakening: state.expansion.playerAttackWeakening = nil
            case let .cardSeal(id): state.expansion.lockedSpells[id] = nil
            case .enemyAmplification: state.expansion.enemyAmplification = nil
            case .enemyPreservation: state.expansion.enemyPreservation = nil
            case .enemyCopyRecord: state.expansion.copyRecord = nil
            default: break
            }
            return []
        case .lingeringBarrier:
            state.expansion.nextTurnBarrier = 10
            return grantPlayerBarrier(amount)
        case .axisSeverance:
            let bonus = state.enemy.normalBarrier > 0 || state.expansion.hasRemovableEnemyBuff ? 12 : 0
            return damageEnemy(amount + bonus)
        case .anchorGuard:
            state.expansion.nextHitFlatReduction = 6
            return grantPlayerBarrier(amount)
        case .consequenceErasure:
            switch target {
            case let .scheduledDamage(id): state.expansion.scheduledDamage.removeAll { $0.id == id }
            case .enemyNormalBarrier:
                state.enemy.normalBarrier = 0
                return [.normalBarrierChanged(target: state.enemy.id, amount: 0)]
            default: break
            }
            return []
        case .outputReduction:
            state.expansion.outputReduction = .init(multiplier: 0.75, expiresAfterTurn: state.turnNumber + 1)
            return []
        case .executionDelay:
            if case let .scheduledDamage(id) = target,
               let index = state.expansion.scheduledDamage.firstIndex(where: { $0.id == id && !$0.wasDelayed }) {
                state.expansion.scheduledDamage[index].dueEnemyTurn += 1
                state.expansion.scheduledDamage[index].wasDelayed = true
            }
            return []
        case .advanceVerdict:
            let bonus = state.expansion.scheduledDamage.contains { $0.dueEnemyTurn == state.turnNumber } ? 12 : 0
            return damageEnemy(amount + bonus)
        case .causalCushion:
            state.expansion.scheduledHitReduction = 0.70
            return grantPlayerBarrier(amount)
        case .memorySeverance:
            let previous = state.expansion.lastSuccessfulSpell
            let bonus = previous != nil && previous != spellID ? 10 : 0
            return damageEnemy(amount + bonus)
        case .memorySuture:
            state.expansion.memorySutureUses += 1
            let oldHP = state.player.hp
            state.player.hp = min(state.player.maxHP, state.player.hp + 8)
            return [.healingApplied(amount: state.player.hp - oldHP, remainingHP: state.player.hp)] + grantPlayerBarrier(amount)
        case .mimicProhibition:
            state.player.hp -= 6
            state.expansion.copyRecord = nil
            state.expansion.mimicProhibitionThroughEnemyTurn = state.turnNumber + 1
            return [.damageApplied(target: .player, amount: 6, remainingHP: state.player.hp)]
        }
    }

    private func preparedIntent(_ intent: EnemyAction) -> EnemyAction {
        guard case let .expansion(name, action) = intent else { return intent }
        return .expansion(name: name, action: preparedAction(action))
    }

    private func preparedAction(_ action: ExpansionEnemyAction) -> ExpansionEnemyAction {
        switch action {
        case let .lockAndSchedule(count, damage):
            let equipped = state.expansion.equippedSpells ?? SpellID.allCases.filter { state.learnedSpells.contains($0) }
            let protected = state.expansion.protectedSpells.union([.sealRelease])
            let candidates = equipped.filter { !protected.contains($0) }
            let recent = state.expansion.successfulSpellHistory.reversed().filter { candidates.contains($0) }
            let ordered = Array(recent) + candidates.filter { !recent.contains($0) }
            return .preparedLockAndSchedule(spells: Array(ordered.prefix(max(0, count))), damage: damage)
        case let .sequence(actions): return .sequence(actions.map(preparedAction))
        default: return action
        }
    }

    private mutating func resolveExpansionAction(_ action: ExpansionEnemyAction) -> [BattleEvent] {
        switch action {
        case let .correctionBarrier(amount):
            state.enemy.normalBarrier = max(state.enemy.normalBarrier, amount)
            state.expansion.retainsCorrectionBarrier = true
            return [.normalBarrierChanged(target: state.enemy.id, amount: state.enemy.normalBarrier)]
        case let .correctionStrike(normal, strong):
            let damage = state.enemy.normalBarrier > 0 ? strong : normal
            state.enemy.normalBarrier = 0
            state.expansion.retainsCorrectionBarrier = false
            return [.normalBarrierChanged(target: state.enemy.id, amount: 0)] + damagePlayer(damage, scheduled: false)
        case let .amplify(multiplier):
            state.expansion.enemyAmplification = max(1, multiplier)
            return []
        case let .schedule(specs):
            let amplification = state.expansion.enemyAmplification ?? 1
            for spec in specs {
                state.expansion.nextReservationID += 1
                state.expansion.scheduledDamage.append(.init(
                    id: "\(enemyDefinition.id.rawValue)-\(state.expansion.nextReservationID)",
                    name: spec.name,
                    damage: max(0, Int((Double(spec.damage) * amplification).rounded())),
                    dueEnemyTurn: state.turnNumber + max(0, spec.turnsFromNow)
                ))
            }
            if !specs.isEmpty { state.expansion.enemyAmplification = nil }
            return []
        case .recordLastSpell:
            guard !reactionIsProhibited, let spell = state.expansion.lastSuccessfulSpellThisTurn else {
                state.expansion.copyRecord = nil
                return []
            }
            state.expansion.copyRecord = .init(spell: spell, category: SpellCatalog.spell(spell).category)
            return []
        case let .copyReaction(baseDamage, categoryEffects, extraDamage):
            var events = damagePlayer(baseDamage, scheduled: false)
            let record = state.expansion.copyRecord
            state.expansion.copyRecord = nil
            guard !state.player.isDefeated, !reactionIsProhibited, let record, record.reused else { return events }
            if !categoryEffects || record.category == .attack {
                events.append(contentsOf: damagePlayer(extraDamage, scheduled: false))
            } else if record.category == .defense {
                state.expansion.enemyPreservation = .init(multiplier: 0.70, expiresAfterTurn: state.turnNumber + 1)
            } else if record.category == .dispel {
                state.player.normalBarrier = max(0, state.player.normalBarrier - 12)
                events.append(.normalBarrierChanged(target: .player, amount: state.player.normalBarrier))
            } else {
                state.expansion.playerAttackWeakening = .init(multiplier: 0.70, expiresAfterTurn: state.turnNumber + 1)
            }
            return events
        case .lockAndSchedule:
            return resolveExpansionAction(preparedAction(action))
        case let .preparedLockAndSchedule(spells, damage):
            for spell in spells where !state.expansion.protectedSpells.contains(spell) && spell != .sealRelease {
                state.expansion.lockedSpells[spell] = state.turnNumber + 1
            }
            return resolveExpansionAction(.schedule([.init(name: "기억 압착", damage: damage, turnsFromNow: 1)]))
        case let .sequence(actions):
            var events: [BattleEvent] = []
            for action in actions where !state.player.isDefeated {
                events.append(contentsOf: resolveExpansionAction(action))
            }
            return events
        case .wait: return []
        }
    }

    private var reactionIsProhibited: Bool {
        guard let through = state.expansion.mimicProhibitionThroughEnemyTurn else { return false }
        return through >= state.turnNumber
    }

    private mutating func resolveDueReservations() -> [BattleEvent] {
        let due = state.expansion.scheduledDamage.filter { $0.dueEnemyTurn <= state.turnNumber }
        state.expansion.scheduledDamage.removeAll { $0.dueEnemyTurn <= state.turnNumber }
        var events: [BattleEvent] = []
        for reservation in due where !state.player.isDefeated {
            events.append(.expansionChanged(message: "\(reservation.name) · 예약 피해 \(reservation.damage) 집행"))
            events.append(contentsOf: damagePlayer(reservation.damage, scheduled: true))
        }
        return events
    }
}
