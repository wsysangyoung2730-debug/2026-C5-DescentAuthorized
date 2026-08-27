import Foundation

enum GameFeedbackCue: Equatable, Sendable {
    case spellAccepted(perfect: Bool)
    case spellRejected
    case enemyDamaged
    case playerDamaged(strong: Bool)
    case playerGuarded(strong: Bool)
    case barrierApplied
    case absoluteBarrierNegated
    case barrierDispelled
    case victory
    case defeat
    case rewardSelected
    case descentApproved
}

struct GameFeedbackMapper: Sendable {
    func cues(for events: [DemoSessionEvent]) -> [GameFeedbackCue] {
        var cues: [GameFeedbackCue] = []
        var currentEnemyAttackIsStrong = false
        var isResolvingEnemyAttack = false

        for event in events {
            switch event {
            case let .combat(battleEvent):
                switch battleEvent {
                case let .spellResolved(spell, grade):
                    cues.append(.spellAccepted(perfect: grade == .perfect))
                    if spell == .sealRelease {
                        cues.append(.barrierDispelled)
                    }
                case .spellRejected:
                    cues.append(.spellRejected)
                case let .damageApplied(target, amount, _):
                    guard amount > 0 else { continue }
                    switch target {
                    case .player:
                        if let guardedCueIndex = cues.lastIndex(where: { cue in
                            if case .playerGuarded = cue { return true }
                            return false
                        }) {
                            cues.remove(at: guardedCueIndex)
                        }
                        cues.append(.playerDamaged(strong: currentEnemyAttackIsStrong))
                    case .enemy:
                        cues.append(.enemyDamaged)
                    }
                case let .normalBarrierChanged(target, amount):
                    if target == .player, isResolvingEnemyAttack {
                        cues.append(.playerGuarded(strong: currentEnemyAttackIsStrong))
                    } else if amount > 0 {
                        cues.append(.barrierApplied)
                    }
                case .attackNegatedByAbsoluteBarrier:
                    cues.append(.absoluteBarrierNegated)
                case let .enemyActionStarted(action):
                    isResolvingEnemyAttack = false
                    if case let .attack(_, _, isStrong) = action {
                        currentEnemyAttackIsStrong = isStrong
                        isResolvingEnemyAttack = true
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
                case .rewardSelected:
                    cues.append(.rewardSelected)
                case let .sceneChanged(scene):
                    if scene == .floor9Entrance
                        || scene == .floor8Antechamber
                        || scene == .demoComplete {
                        cues.append(.descentApproved)
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
