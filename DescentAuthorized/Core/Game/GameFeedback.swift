import Foundation

enum GameFeedbackCue: Equatable, Sendable {
    case spellAccepted(perfect: Bool)
    case spellRejected
    case enemyAttack(strong: Bool)
    case enemyDamaged
    case playerDamaged(strong: Bool)
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
                case let .enemyActionStarted(action):
                    isResolvingPlayerSpell = false
                    isResolvingEnemyAttack = false
                    if case let .attack(_, _, isStrong) = action {
                        currentEnemyAttackIsStrong = isStrong
                        isResolvingEnemyAttack = true
                        cues.append(.enemyAttack(strong: isStrong))
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
}
