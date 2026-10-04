import XCTest
@testable import DescentAuthorizedCore

final class CombatPresentationTimelineTests: XCTestCase {
    func testAuthoredAttackReleaseImpactAndRecoveryMatchEveryRuntimeActor() throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let actors = repository.appendingPathComponent("DescentAuthorized/Resources/Reality/Actors")
        let manifests = try FileManager.default.contentsOfDirectory(at: actors, includingPropertiesForKeys: nil)
            .map { $0.appendingPathComponent("motion.json") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        XCTAssertEqual(manifests.count, EnemyID.allCases.count)
        for url in manifests {
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            let clips = try XCTUnwrap(json["clips"] as? [String: [String: Any]])
            for (name, timing) in [("attack", EnemyAttackTiming.normal), ("heavyAttack", .heavy)] {
                let clip = try XCTUnwrap(clips[name], "\(url.path): \(name)")
                let release = try XCTUnwrap(clip["release"] as? Double)
                let impact = try XCTUnwrap(clip["impact"] as? Double)
                let settled = try XCTUnwrap(clip["settledAt"] as? Double)
                let duration = try XCTUnwrap(clip["duration"] as? Double)
                let start = try XCTUnwrap(clip["start"] as? Double)
                let end = try XCTUnwrap(clip["end"] as? Double)
                let label = "\(url.deletingLastPathComponent().lastPathComponent) \(name)"
                XCTAssertEqual(release, timing.release, accuracy: 0.001, label)
                XCTAssertEqual(impact, timing.impact, accuracy: 0.001, label)
                XCTAssertEqual(settled, timing.settled, accuracy: 0.001, label)
                XCTAssertEqual(duration, timing.duration, accuracy: 0.001, label)
                XCTAssertEqual(end - start, duration, accuracy: 0.001, label)
                XCTAssertGreaterThan(release, 0, label)
                XCTAssertLessThan(release, impact, label)
                XCTAssertLessThan(impact, settled, label)
                XCTAssertLessThan(settled, duration, label)
            }
        }
    }

    func testDeathDroopsThenFallsBeforeDissolvingWithoutUnboundedAngles() {
        let start = GroundedDeathPose.sample(elapsed: 0, reducedMotion: false)
        XCTAssertEqual(start.forwardTilt, 0)
        let droop = GroundedDeathPose.sample(elapsed: 0.65, reducedMotion: false)
        XCTAssertEqual(droop.forwardTilt, 0.18, accuracy: 0.001)
        XCTAssertEqual(droop.sideTilt, 0)
        var previous: Float = 0
        for step in 0...245 {
            let pose = GroundedDeathPose.sample(elapsed: Double(step) / 100, reducedMotion: false)
            XCTAssertTrue(pose.forwardTilt.isFinite && pose.sideTilt.isFinite)
            XCTAssertGreaterThanOrEqual(pose.forwardTilt, previous)
            XCTAssertLessThanOrEqual(pose.forwardTilt, 1.401)
            XCTAssertTrue((0...1).contains(pose.opacity))
            if step <= 65 { XCTAssertEqual(pose.opacity, 1) }
            previous = pose.forwardTilt
        }
        XCTAssertEqual(GroundedDeathPose.sample(elapsed: 1.05, reducedMotion: false).opacity, 0, accuracy: 0.001)
        let reduced = GroundedDeathPose.sample(elapsed: 0.2, reducedMotion: true)
        XCTAssertEqual(reduced.forwardTilt, 0)
        XCTAssertEqual(reduced.sideTilt, 0)
        XCTAssertEqual(reduced.opacity, 0)
        XCTAssertEqual(GroundedDeathPose.sample(elapsed: .nan, reducedMotion: false).forwardTilt, 0)
    }

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
        XCTAssertEqual(steps[2].delay, 1.40, accuracy: 0.001)
        XCTAssertGreaterThan(steps[2].delay, CombatPresentationTimeline.deathDuration)
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
        XCTAssertEqual(waitSteps[2].delay, 0.54, accuracy: 0.001)
        XCTAssertEqual(waitSteps[0].enemyAction?.attackStrength, false)

        let nonattacks: [(EnemyAction, TimeInterval)] = [
            (.telegraph(name: "준비", upcomingActionName: "공격"), 1.20),
            (.grantNormalBarrier(name: "방벽", amount: 12), 2.00),
            (.expansion(name: "증폭", action: .amplify(multiplier: 1.5)), 2.00),
            (wait, 2.00)
        ]
        for (action, expectedDuration) in nonattacks {
            let steps = CombatPresentationTimeline.steps(for: [
                .combat(.enemyActionStarted(action))
            ])
            XCTAssertEqual(steps[0].events, [.combat(.enemyActionStarted(action))])
            XCTAssertEqual(steps[1].delay, 0.46, accuracy: 0.001)
            XCTAssertEqual(steps[1].delay + steps[2].delay, expectedDuration,
                           accuracy: 0.001, action.name)
            XCTAssertNil(steps[0].enemyAction?.attackStrength)
        }
    }

    func testRealExitReviewReservationGetsHeavyGestureEvenWhenFullyGuarded() throws {
        let enemy = try XCTUnwrap(LowerFloorEnemyCatalog.all[.exitReviewResidual])
        var engine = CombatEngine(enemy: enemy, playerNormalBarrier: 100)
        for action in enemy.pattern.prefix(2) {
            _ = try engine.beginPlayerTurn(intent: action)
            _ = try engine.endPlayerTurn()
            _ = try engine.resolveEnemyIntent()
        }
        let wait = enemy.pattern[2]
        _ = try engine.beginPlayerTurn(intent: wait)
        let priorState = engine.state
        XCTAssertEqual(EnemyActionPresentation(action: wait, state: priorState).attackStrength, true)
        _ = try engine.endPlayerTurn()
        let events = try engine.resolveEnemyIntent().map(DemoSessionEvent.combat)
        XCTAssertTrue(events.contains(.combat(.scheduledDamageExecuted(name: "퇴거 집행", damage: 32))))
        XCTAssertFalse(events.contains { if case .combat(.damageApplied(.player, _, _)) = $0 { true } else { false } })
        XCTAssertTrue(engine.state.expansion.scheduledDamage.isEmpty)
        let steps = CombatPresentationTimeline.steps(for: events)
        XCTAssertEqual(steps[0].enemyAction?.attackStrength, true)
        XCTAssertEqual(steps[0].enemyAction?.includesScheduledDamage, true)
        XCTAssertEqual(steps[1].enemyAction, steps[0].enemyAction)
        XCTAssertEqual(steps[1].delay, EnemyAttackTiming.heavy.impact)
        XCTAssertEqual(steps[2].delay, EnemyAttackTiming.heavy.recoveryDuration)
        XCTAssertTrue(GameFeedbackMapper().cues(for: steps[0].events,
            enemyActionPresentation: steps[0].enemyAction).contains(.enemyAttack(strong: true)))
        XCTAssertTrue(GameFeedbackMapper().cues(for: events).contains(.barrierDamaged(strong: true)))
        XCTAssertEqual(steps.flatMap(\.events), events)
    }

    func testDueNormalReservationUsesAttackAndCancelledOrDelayedWaitStaysSpecial() throws {
        for spellID: SpellID? in [nil, .consequenceErasure, .executionDelay] {
            var engine = CombatEngine(enemy: EnemyCatalog.recordsAdministrator)
            _ = try engine.beginPlayerTurn(intent: .expansion(name: "예약", action: .schedule([
                .init(name: "집행", damage: 18, turnsFromNow: 1)
            ])))
            _ = try engine.endPlayerTurn()
            _ = try engine.resolveEnemyIntent()
            let wait = EnemyAction.expansion(name: "대기", action: .wait)
            _ = try engine.beginPlayerTurn(intent: wait)
            let id = try XCTUnwrap(engine.state.expansion.scheduledDamage.first?.id)
            if let spellID {
                let spell = SpellCatalog.spell(spellID)
                _ = try engine.submitSpell(spell,
                    strokes: spell.glyph.strokes.map { .init(points: $0.referencePath) },
                    inputMethod: .pencil, selectedTarget: .scheduledDamage(id))
            }
            if engine.state.phase == .playerTurn { _ = try engine.endPlayerTurn() }
            let events = try engine.resolveEnemyIntent().map(DemoSessionEvent.combat)
            let steps = CombatPresentationTimeline.steps(for: events)
            XCTAssertEqual(steps[0].enemyAction?.attackStrength, spellID == nil ? false : nil)
            XCTAssertEqual(steps[0].enemyAction?.includesScheduledDamage, spellID == nil)
            XCTAssertEqual(steps[1].delay + steps[2].delay, spellID == nil ? 1 : 2, accuracy: 0.001)
        }
    }
}
