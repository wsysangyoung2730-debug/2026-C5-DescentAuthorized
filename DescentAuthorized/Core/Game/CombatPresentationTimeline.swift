import Foundation

/// Timing belongs to presentation; combat and saving still resolve synchronously.
struct CombatPresentationTimeline {
    static let playerImpactDelay: TimeInterval = 0.20
    static let playerToEnemyDelay: TimeInterval = 0.38
    static let deathDuration: TimeInterval = 1.80

    static func enemyImpactDelay(strong: Bool) -> TimeInterval { strong ? 0.62 : 0.46 }
    static func enemyRecovery(strong: Bool) -> TimeInterval { strong ? 0.68 : 0.54 }

    static func enemyActionDuration(_ action: EnemyAction) -> TimeInterval {
        let cues = GameFeedbackMapper().cues(for: [.combat(.enemyActionStarted(action))])
        for cue in cues {
            if case let .enemyAttack(strong) = cue {
                return enemyImpactDelay(strong: strong) + enemyRecovery(strong: strong)
            }
        }
        if case .telegraph = action { return 1.20 }
        // Reservations can strike during a wait while its special gesture continues.
        return 2.00
    }

    enum Kind: Equatable, Sendable {
        case playerCast, playerImpact, enemyWindup, enemyImpact, recovery, victoryRelease
    }

    struct Step: Equatable, Sendable {
        let kind: Kind
        /// Delay since the preceding step, excluding time spent paused.
        let delay: TimeInterval
        let events: [DemoSessionEvent]
        /// Projectile events launch immediately, but their HP changes wait for impact.
        let stateEvents: [DemoSessionEvent]

        init(_ kind: Kind, after delay: TimeInterval, events: [DemoSessionEvent],
             stateEvents: [DemoSessionEvent]? = nil) {
            self.kind = kind
            self.delay = delay
            self.events = events
            self.stateEvents = stateEvents ?? events
        }
    }

    static func steps(for events: [DemoSessionEvent]) -> [Step] {
        let combat = events.filter { if case .combat = $0 { true } else { false } }
        let completion = events.filter { if case .combat = $0 { false } else { true } }
        let enemyIndex = combat.firstIndex {
            if case .combat(.enemyActionStarted) = $0 { true } else { false }
        }
        let hasPlayerCast = combat.contains {
            switch $0 {
            case .combat(.spellResolved), .combat(.spellRejected): true
            default: false
            }
        }
        let hasVictory = combat.contains {
            if case .combat(.victory) = $0 { true } else { false }
        }
        guard hasPlayerCast || enemyIndex != nil || hasVictory else { return [] }

        let playerEvents = Array(combat.prefix(enemyIndex ?? combat.count))
        let victoryEvents = playerEvents.filter {
            if case .combat(.victory) = $0 { true } else { false }
        }
        let castEvents = playerEvents.filter {
            if case .combat(.victory) = $0 { false } else { true }
        }
        var result: [Step] = []
        if hasPlayerCast || hasVictory {
            let immediateState = castEvents.filter {
                switch $0 {
                case .combat(.spellResolved), .combat(.spellRejected), .combat(.resourcesChanged): true
                default: false
                }
            }
            let impactState = playerEvents.filter { !immediateState.contains($0) }
            result.append(Step(.playerCast, after: 0, events: castEvents, stateEvents: immediateState))
            result.append(Step(.playerImpact, after: playerImpactDelay,
                               events: victoryEvents, stateEvents: impactState))
        }

        if hasVictory {
            result.append(Step(.victoryRelease, after: deathDuration, events: completion))
        } else if let enemyIndex {
            let enemyEvents = Array(combat.suffix(from: enemyIndex))
            let nextTurn = enemyEvents.firstIndex {
                if case .combat(.turnStarted) = $0 { true } else { false }
            } ?? enemyEvents.count
            let actionEvents = Array(enemyEvents.prefix(nextTurn))
            let strong = isStrongEnemyAction(in: actionEvents)
            let impactDelay = enemyImpactDelay(strong: strong)
            let actionDuration: TimeInterval
            if case let .combat(.enemyActionStarted(action)) = enemyEvents[0] {
                actionDuration = enemyActionDuration(action)
            } else {
                actionDuration = impactDelay + enemyRecovery(strong: strong)
            }
            let windupEvents = (hasPlayerCast ? [] : playerEvents) + [enemyEvents[0]]
            result.append(Step(.enemyWindup,
                               after: hasPlayerCast ? playerToEnemyDelay - playerImpactDelay : 0,
                               events: windupEvents))
            result.append(Step(.enemyImpact, after: impactDelay,
                               events: Array(actionEvents.dropFirst())))
            result.append(Step(.recovery, after: max(0, actionDuration - impactDelay),
                               events: Array(enemyEvents.suffix(from: nextTurn)) + completion))
        } else {
            result.append(Step(.recovery, after: playerToEnemyDelay - playerImpactDelay, events: completion))
        }
        return result
    }

    static func isStrongEnemyAction(in events: [DemoSessionEvent]) -> Bool {
        GameFeedbackMapper().cues(for: events).contains {
            switch $0 {
            case .enemyAttack(strong: true), .playerDamaged(strong: true),
                 .barrierDamaged(strong: true), .barrierBroken(strong: true): true
            default: false
            }
        }
    }

    static func applying(_ step: Step, to previous: BattleState, finalState: BattleState) -> BattleState {
        if step.kind == .recovery || step.kind == .victoryRelease { return finalState }
        var state = previous
        switch step.kind {
        case .playerCast, .playerImpact: state.phase = .resolvingPlayerSpell
        case .enemyWindup, .enemyImpact: state.phase = .resolvingEnemyAction
        case .recovery, .victoryRelease: break
        }
        for event in step.stateEvents {
            guard case let .combat(event) = event else { continue }
            switch event {
            case let .resourcesChanged(mana, strokes):
                state.resources.remainingMana = mana
                state.resources.remainingStrokes = strokes
            case let .spellResolved(spell, _):
                state.castsThisTurn.append(spell)
            case let .damageApplied(target, _, remainingHP):
                if target == .player { state.player.hp = remainingHP }
                else { state.enemy.hp = remainingHP }
            case let .normalBarrierChanged(target, amount):
                if target == .player { state.player.normalBarrier = amount }
                else { state.enemy.normalBarrier = amount }
            case let .absoluteBarrierChanged(target, charges):
                if target == .player { state.player.absoluteBarrierCharges = charges }
                else { state.enemy.absoluteBarrierCharges = charges }
            case let .healingApplied(_, remainingHP): state.player.hp = remainingHP
            case let .enemyActionStarted(action): state.currentEnemyIntent = action
            case .enemyActionCancelled: state.currentEnemyIntent = nil
            case let .erasureZoneAdded(zone):
                if !state.activeErasureZones.contains(where: { $0.id == zone.id }) {
                    state.activeErasureZones.append(zone)
                }
            case .expansionChanged: state.expansion = finalState.expansion
            case .victory, .defeat: state = finalState
            default: break
            }
        }
        if step.kind == .enemyImpact { state.currentEnemyIntent = nil }
        return state
    }
}
