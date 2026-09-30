import Foundation

/// A resolved action keeps its gesture even after the staged state removes due reservations.
struct EnemyActionPresentation: Equatable, Sendable {
    let attackStrength: Bool?
    let includesScheduledDamage: Bool

    init(action: EnemyAction, resolvedEvents: [DemoSessionEvent]? = nil, state: BattleState? = nil) {
        let direct: Bool?
        switch action {
        case let .attack(_, _, strong): direct = strong
        case let .expansion(_, action): direct = Self.expansionStrength(action)
        default: direct = nil
        }
        let scheduled: [Int]
        if let resolvedEvents {
            scheduled = resolvedEvents.compactMap {
                if case let .combat(.scheduledDamageExecuted(_, damage)) = $0 { return damage }
                return nil
            }
        } else if let state {
            scheduled = state.expansion.scheduledDamage
                .filter { $0.dueEnemyTurn <= state.turnNumber }.map(\.damage)
        } else {
            scheduled = []
        }
        includesScheduledDamage = !scheduled.isEmpty
        let actualDamage = resolvedEvents?.compactMap { event -> Int? in
            if case let .combat(.damageApplied(.player, amount, _)) = event, amount > 0 { return amount }
            return nil
        } ?? []
        if direct != nil || !scheduled.isEmpty || !actualDamage.isEmpty {
            attackStrength = direct == true || scheduled.contains { $0 >= 30 } || actualDamage.contains { $0 >= 30 }
        } else {
            attackStrength = nil
        }
    }

    private static func expansionStrength(_ action: ExpansionEnemyAction) -> Bool? {
        switch action {
        case .correctionStrike, .barrierStrike: return true
        case .copyReaction, .counterExecute: return false
        case let .directHits(hits): return hits.contains { $0 >= 30 }
        case let .sequence(actions):
            let strengths = actions.compactMap(expansionStrength)
            return strengths.isEmpty ? nil : strengths.contains(true)
        default: return nil
        }
    }
}

/// Shared by authored poses, the released projectile, and damage presentation.
struct EnemyAttackTiming: Equatable, Sendable {
    let release: TimeInterval
    let impact: TimeInterval
    let settled: TimeInterval
    let duration: TimeInterval

    static let normal = Self(release: 0.40, impact: 0.46, settled: 0.96, duration: 1.0)
    static let heavy = Self(release: 0.54, impact: 0.62, settled: 1.28, duration: 1.3)

    static func forAttack(strong: Bool) -> Self { strong ? .heavy : .normal }
    var flightDuration: TimeInterval { impact - release }
    var recoveryDuration: TimeInterval { duration - impact }
}

/// Timing belongs to presentation; combat and saving still resolve synchronously.
struct CombatPresentationTimeline {
    static let playerImpactDelay: TimeInterval = 0.20
    static let playerToEnemyDelay: TimeInterval = 0.38
    static let deathPoseDuration: TimeInterval = 0.65
    static let dissolveDuration: TimeInterval = 0.40
    static let deathDuration: TimeInterval = deathPoseDuration + dissolveDuration

    static func enemyImpactDelay(strong: Bool) -> TimeInterval { EnemyAttackTiming.forAttack(strong: strong).impact }
    static func enemyRecovery(strong: Bool) -> TimeInterval { EnemyAttackTiming.forAttack(strong: strong).recoveryDuration }

    static func enemyActionDuration(_ action: EnemyAction, presentation: EnemyActionPresentation? = nil) -> TimeInterval {
        if let strong = (presentation ?? EnemyActionPresentation(action: action)).attackStrength {
            return EnemyAttackTiming.forAttack(strong: strong).duration
        }
        if case .telegraph = action { return 1.20 }
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
        let enemyAction: EnemyActionPresentation?

        init(_ kind: Kind, after delay: TimeInterval, events: [DemoSessionEvent],
             stateEvents: [DemoSessionEvent]? = nil, enemyAction: EnemyActionPresentation? = nil) {
            self.kind = kind
            self.delay = delay
            self.events = events
            self.stateEvents = stateEvents ?? events
            self.enemyAction = enemyAction
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
            guard case let .combat(.enemyActionStarted(action)) = enemyEvents[0] else { return result }
            let presentation = EnemyActionPresentation(action: action, resolvedEvents: actionEvents)
            let strong = presentation.attackStrength ?? false
            let impactDelay = enemyImpactDelay(strong: strong)
            let actionDuration = enemyActionDuration(action, presentation: presentation)
            let windupEvents = (hasPlayerCast ? [] : playerEvents) + [enemyEvents[0]]
            result.append(Step(.enemyWindup,
                               after: hasPlayerCast ? playerToEnemyDelay - playerImpactDelay : 0,
                               events: windupEvents, enemyAction: presentation))
            result.append(Step(.enemyImpact, after: impactDelay,
                               events: Array(actionEvents.dropFirst()), enemyAction: presentation))
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

/// Deterministic whole-model fall. No joint indices or accumulated transforms are used.
struct GroundedDeathPose {
    let forwardTilt: Float
    let sideTilt: Float
    let opacity: Float

    static func sample(elapsed: TimeInterval, reducedMotion: Bool) -> Self {
        let time = elapsed.isFinite ? max(0, elapsed) : 0
        func smooth(_ value: Double) -> Float {
            let t = min(1, max(0, value))
            return Float(t * t * (3 - 2 * t))
        }
        let droop = smooth(time / 0.65)
        let fall = smooth((time - 0.65) / 0.95)
        let fadeStart = reducedMotion ? 0 : CombatPresentationTimeline.deathPoseDuration
        let fadeDuration = reducedMotion ? 0.15 : CombatPresentationTimeline.dissolveDuration
        return Self(forwardTilt: reducedMotion ? 0 : 0.18 * droop + 1.22 * fall,
                    sideTilt: reducedMotion ? 0 : 0.12 * fall,
                    opacity: 1 - smooth((time - fadeStart) / fadeDuration))
    }
}
