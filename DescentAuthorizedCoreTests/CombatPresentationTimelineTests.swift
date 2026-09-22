import XCTest
@testable import DescentAuthorizedCore

final class CombatPresentationTimelineTests: XCTestCase {
    func testCombinedTurnLaunchesProjectileThenStagesEnemyImpactAndRecovery() {
        let attack = EnemyAction.attack(name: "공격", damage: 12, isStrong: false)
        let damage = DemoSessionEvent.combat(.damageApplied(
            target: .enemy(.recordsAdministrator), amount: 18, remainingHP: 42
        ))
        let events: [DemoSessionEvent] = [
            .combat(.spellResolved(spell: .afterglowErasure, grade: .perfect)), damage,
            .combat(.resourcesChanged(mana: 40, strokes: 0)),
            .combat(.enemyActionStarted(attack)),
            .combat(.damageApplied(target: .player, amount: 12, remainingHP: 88)),
            .combat(.turnStarted(number: 2, intent: attack)),
            .combat(.resourcesChanged(mana: 100, strokes: 2))
        ]
        let steps = CombatPresentationTimeline.steps(for: events)
        XCTAssertEqual(steps.map(\.kind), [.playerCast, .playerImpact, .enemyWindup, .enemyImpact, .recovery])
        XCTAssertEqual(steps.flatMap(\.events), events)
        XCTAssertTrue(steps[0].events.contains(damage), "Damage must launch the existing spell projectile.")
        XCTAssertFalse(steps[0].stateEvents.contains(damage), "HP waits until that projectile lands.")
        XCTAssertTrue(steps[1].stateEvents.contains(damage))
        XCTAssertEqual(steps[1].delay + steps[2].delay, 0.38, accuracy: 0.001)
        XCTAssertEqual(steps[3].delay, 0.46, accuracy: 0.001)
        XCTAssertEqual(steps[4].delay, 0.54, accuracy: 0.001)

        var initial = CombatEngine(enemy: EnemyCatalog.recordsAdministrator).state
        initial.enemy.hp = 60
        var final = initial
        final.enemy.hp = 42
        final.player.hp = 88
        final.phase = .playerTurn
        final.turnNumber = 2
        var state = CombatPresentationTimeline.applying(steps[0], to: initial, finalState: final)
        XCTAssertEqual(state.enemy.hp, 60)
        XCTAssertEqual(state.resources.remainingStrokes, 0)
        state = CombatPresentationTimeline.applying(steps[1], to: state, finalState: final)
        XCTAssertEqual(state.enemy.hp, 42)
        state = CombatPresentationTimeline.applying(steps[2], to: state, finalState: final)
        XCTAssertEqual(state.player.hp, 100)
        XCTAssertEqual(state.phase, .resolvingEnemyAction)
        state = CombatPresentationTimeline.applying(steps[3], to: state, finalState: final)
        XCTAssertEqual(state.player.hp, 88)
        XCTAssertEqual(state.turnNumber, initial.turnNumber)
        XCTAssertEqual(CombatPresentationTimeline.applying(steps[4], to: state, finalState: final), final)
    }

    func testVictoryStartsAtProjectileImpactAndHoldsProgressionForCollapse() {
        let events: [DemoSessionEvent] = [
            .combat(.spellResolved(spell: .afterglowErasure, grade: .perfect)),
            .combat(.damageApplied(target: .enemy(.recordsAdministrator), amount: 20, remainingHP: 0)),
            .combat(.resourcesChanged(mana: 70, strokes: 1)),
            .combat(.enemyActionCancelled),
            .combat(.victory(.recordsAdministrator)),
            .encounterWon(.recordsAdministrator),
            .progression(.sceneChanged(.floor9RecordsDefeated))
        ]
        let steps = CombatPresentationTimeline.steps(for: events)
        XCTAssertEqual(steps.map(\.kind), [.playerCast, .playerImpact, .victoryRelease])
        XCTAssertEqual(steps.flatMap(\.events), events)
        XCTAssertEqual(steps[1].events, [.combat(.victory(.recordsAdministrator))])
        XCTAssertEqual(steps[1].delay, 0.20, accuracy: 0.001)
        XCTAssertEqual(steps[2].delay, 1.80, accuracy: 0.001)
        XCTAssertEqual(steps[2].events, [.encounterWon(.recordsAdministrator),
                                        .progression(.sceneChanged(.floor9RecordsDefeated))])

        let initial = CombatEngine(enemy: EnemyCatalog.recordsAdministrator).state
        var final = initial
        final.phase = .victory
        final.enemy.hp = 0
        let state = CombatPresentationTimeline.applying(steps[1], to: initial, finalState: final)
        XCTAssertEqual(state, final)
    }

    func testLethalEnemyDamageArrivesAtImpactWithoutRepeatingWindup() {
        let attack = EnemyAction.attack(name: "강공격", damage: 100, isStrong: true)
        let events: [DemoSessionEvent] = [
            .combat(.enemyActionStarted(attack)),
            .combat(.normalBarrierChanged(target: .player, amount: 0)),
            .combat(.damageApplied(target: .player, amount: 100, remainingHP: 0)),
            .combat(.defeat), .encounterLost(.recordsAdministrator)
        ]
        let steps = CombatPresentationTimeline.steps(for: events)
        XCTAssertEqual(steps.map(\.kind), [.enemyWindup, .enemyImpact, .recovery])
        XCTAssertEqual(steps[0].events, [.combat(.enemyActionStarted(attack))])
        XCTAssertTrue(steps[1].events.contains(.combat(.defeat)))
        XCTAssertFalse(steps[1].events.contains(.combat(.enemyActionStarted(attack))))
        XCTAssertEqual(steps[1].delay, 0.62, accuracy: 0.001)
        XCTAssertEqual(steps[2].delay, 0.68, accuracy: 0.001)
        XCTAssertEqual(steps.flatMap(\.events), events)
    }

    func testExpansionSequenceUsesStrongTimingAndWaitCanDeliverScheduledDamage() {
        let strong = EnemyAction.expansion(name: "교정", action: .sequence([
            .correctionBarrier(amount: 10), .correctionStrike(normalDamage: 18, strengthenedDamage: 30)
        ]))
        let strongSteps = CombatPresentationTimeline.steps(for: [.combat(.enemyActionStarted(strong))])
        XCTAssertEqual(strongSteps[1].delay, 0.62, accuracy: 0.001)
        XCTAssertEqual(strongSteps[2].delay, 0.68, accuracy: 0.001)

        let wait = EnemyAction.expansion(name: "대기", action: .wait)
        let delayedDamage = DemoSessionEvent.combat(.damageApplied(target: .player, amount: 9, remainingHP: 91))
        let waitSteps = CombatPresentationTimeline.steps(for: [.combat(.enemyActionStarted(wait)), delayedDamage])
        XCTAssertEqual(waitSteps[0].events, [.combat(.enemyActionStarted(wait))])
        XCTAssertEqual(waitSteps[1].events, [delayedDamage])
        XCTAssertEqual(waitSteps[1].delay, 0.46, accuracy: 0.001)

        let nonattacks: [(EnemyAction, TimeInterval)] = [
            (.telegraph(name: "준비", upcomingActionName: "공격"), 1.20),
            (.grantNormalBarrier(name: "방벽", amount: 12), 2.00),
            (.expansion(name: "증폭", action: .amplify(multiplier: 1.5)), 2.00),
            (wait, 2.00)
        ]
        for (action, expectedDuration) in nonattacks {
            let steps = CombatPresentationTimeline.steps(for: [
                .combat(.enemyActionStarted(action)), delayedDamage
            ])
            XCTAssertEqual(steps[0].events, [.combat(.enemyActionStarted(action))])
            XCTAssertEqual(steps[1].delay, 0.46, accuracy: 0.001)
            XCTAssertEqual(steps[1].delay + steps[2].delay, expectedDuration,
                           accuracy: 0.001, action.name)
        }
    }
}
