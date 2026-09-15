import Foundation

enum GameFeedbackCue: Equatable, Sendable {
    case spellAccepted(perfect: Bool)
    case spellRejected
    case enemyAttack(strong: Bool)
    case enemyDamaged
    case playerDamaged(strong: Bool)
    case playerHealed
    case barrierDamaged(strong: Bool)
    case barrierBroken(strong: Bool)
    case barrierApplied(isAbsolute: Bool)
    case absoluteBarrierNegated
    case barrierDispelled
    case victory
    case defeat
    case recordOpened
    case rewardSelected
    case floorTransition
    case descentSealRejected(exhausted: Bool)
    case descentSealStageCompleted(final: Bool)
}

struct GameFeedbackMapper: Sendable {
    func cues(for events: [DemoSessionEvent]) -> [GameFeedbackCue] {
        var cues: [GameFeedbackCue] = []
        var currentEnemyAttackIsStrong = false
        var isResolvingEnemyAttack = false
        var isResolvingPlayerSpell = false

        for event in events {
            switch event {
            case let .combat(battleEvent):
                switch battleEvent {
                case let .spellResolved(_, grade):
                    isResolvingPlayerSpell = true
                    isResolvingEnemyAttack = false
                    currentEnemyAttackIsStrong = false
                    cues.append(.spellAccepted(perfect: grade == .perfect))
                case .spellRejected:
                    isResolvingPlayerSpell = false
                    cues.append(.spellRejected)
                case let .damageApplied(target, amount, _):
                    guard amount > 0 else { continue }
                    switch target {
                    case .player:
                        cues.append(.playerDamaged(strong: currentEnemyAttackIsStrong))
                    case .enemy:
                        cues.append(.enemyDamaged)
                    }
                case let .normalBarrierChanged(target, amount):
                    if target == .player, isResolvingEnemyAttack {
                        if amount == 0 {
                            cues.append(.barrierBroken(strong: currentEnemyAttackIsStrong))
                        } else {
                            cues.append(.barrierDamaged(strong: currentEnemyAttackIsStrong))
                        }
                    } else if isResolvingPlayerSpell, target != .player {
                        if amount == 0 {
                            cues.append(.barrierBroken(strong: false))
                        } else {
                            cues.append(.barrierDamaged(strong: false))
                        }
                    } else if amount > 0 {
                        cues.append(.barrierApplied(isAbsolute: false))
                    }
                case let .absoluteBarrierChanged(_, charges):
                    if isResolvingPlayerSpell {
                        if charges > 0 {
                            cues.append(.barrierDamaged(strong: false))
                        } else {
                            cues.append(.barrierDispelled)
                        }
                    } else if charges > 0 {
                        cues.append(.barrierApplied(isAbsolute: true))
                    }
                case .attackNegatedByAbsoluteBarrier:
                    cues.append(.absoluteBarrierNegated)
                case let .healingApplied(amount, _):
                    if amount > 0 { cues.append(.playerHealed) }
                case .expansionChanged:
                    // A state refresh may accompany several effects; avoid duplicate feedback.
                    break
                case let .enemyActionStarted(action):
                    isResolvingPlayerSpell = false
                    isResolvingEnemyAttack = false
                    currentEnemyAttackIsStrong = false
                    if case let .attack(_, _, isStrong) = action {
                        currentEnemyAttackIsStrong = isStrong
                        isResolvingEnemyAttack = true
                        cues.append(.enemyAttack(strong: isStrong))
                    } else if case let .expansion(_, expansionAction) = action {
                        // A delayed hit can arrive during any expansion action, including a wait.
                        isResolvingEnemyAttack = true
                        if let strong = expansionAttackStrength(expansionAction) {
                            currentEnemyAttackIsStrong = strong
                            cues.append(.enemyAttack(strong: strong))
                        }
                    }
                case .victory:
                    cues.append(.victory)
                case .defeat:
                    cues.append(.defeat)
                default:
                    break
                }

            case let .progression(progressionEvent):
                switch progressionEvent {
                case .recordRead, .rewardCandidates:
                    cues.append(.recordOpened)
                case .rewardSelected:
                    cues.append(.rewardSelected)
                case let .sceneChanged(scene):
                    if scene == .floor9Entrance
                        || scene == .floor8Antechamber
                        || scene == .demoComplete {
                        cues.append(.floorTransition)
                    }
                default:
                    break
                }

            case .encounterStarted, .encounterWon, .encounterLost:
                break
            }
        }
        return cues
    }

    private func expansionAttackStrength(_ action: ExpansionEnemyAction) -> Bool? {
        switch action {
        case .correctionStrike: true
        case .copyReaction: false
        case let .sequence(actions): actions.compactMap(expansionAttackStrength).first
        case .correctionBarrier, .amplify, .schedule, .recordLastSpell,
             .lockAndSchedule, .preparedLockAndSchedule, .wait:
            nil
        }
    }
}
