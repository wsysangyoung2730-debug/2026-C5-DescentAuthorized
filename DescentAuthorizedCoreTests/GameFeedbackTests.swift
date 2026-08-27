import XCTest
@testable import DescentAuthorizedCore

final class GameFeedbackTests: XCTestCase {
    private let mapper = GameFeedbackMapper()

    func testPerfectDispelProducesCastThenBrokenBarrierFeedback() {
        let cues = mapper.cues(for: [
            .combat(.spellResolved(spell: .sealRelease, grade: .perfect)),
            .combat(.absoluteBarrierChanged(target: .enemy(.observationAdministrator), charges: 0))
        ])

        XCTAssertEqual(cues, [
            .spellAccepted(perfect: true),
            .barrierDispelled
        ])
    }

    func testPartialAbsoluteBarrierDispelDoesNotReplayActivationSound() {
        let cues = mapper.cues(for: [
            .combat(.spellResolved(spell: .sealRelease, grade: .approved)),
            .combat(.absoluteBarrierChanged(target: .enemy(.observationAdministrator), charges: 1))
        ])

        XCTAssertEqual(cues, [
            .spellAccepted(perfect: false),
            .barrierDamaged(strong: false)
        ])
    }

    func testAbsoluteBarrierCreationProducesActivationFeedback() {
        let cues = mapper.cues(for: [
            .combat(.absoluteBarrierChanged(target: .enemy(.observationAdministrator), charges: 2))
        ])

        XCTAssertEqual(cues, [.barrierApplied(isAbsolute: true)])
    }

    func testStrongEnemyAttackPlaysAttackBeforePlayerDamage() {
        let action = EnemyAction.attack(name: "강공격", damage: 30, isStrong: true)
        let cues = mapper.cues(for: [
            .combat(.enemyActionStarted(action)),
            .combat(.damageApplied(target: .player, amount: 30, remainingHP: 70))
        ])

        XCTAssertEqual(cues, [
            .enemyAttack(strong: true),
            .playerDamaged(strong: true)
        ])
    }

    func testStrongAttackAbsorbedByRemainingBarrierHasNoPlayerHit() {
        let action = EnemyAction.attack(name: "강공격", damage: 30, isStrong: true)
        let cues = mapper.cues(for: [
            .combat(.enemyActionStarted(action)),
            .combat(.normalBarrierChanged(target: .player, amount: 10))
        ])

        XCTAssertEqual(cues, [
            .enemyAttack(strong: true),
            .barrierDamaged(strong: true)
        ])
    }

    func testBarrierOverflowOrdersBreakBeforePlayerDamage() {
        let action = EnemyAction.attack(name: "강공격", damage: 30, isStrong: true)
        let cues = mapper.cues(for: [
            .combat(.enemyActionStarted(action)),
            .combat(.normalBarrierChanged(target: .player, amount: 0)),
            .combat(.damageApplied(target: .player, amount: 10, remainingHP: 90))
        ])

        XCTAssertEqual(cues, [
            .enemyAttack(strong: true),
            .barrierBroken(strong: true),
            .playerDamaged(strong: true)
        ])
    }

    func testPlayerBarrierCreationProducesNormalActivationFeedback() {
        let cues = mapper.cues(for: [
            .combat(.normalBarrierChanged(target: .player, amount: 20))
        ])

        XCTAssertEqual(cues, [.barrierApplied(isAbsolute: false)])
    }

    func testBarrierPiercingOrdersCastBreakHitAndVictory() {
        let cues = mapper.cues(for: [
            .combat(.spellResolved(spell: .barrierPiercing, grade: .approved)),
            .combat(.normalBarrierChanged(target: .enemy(.recordsAdministrator), amount: 0)),
            .combat(.damageApplied(
                target: .enemy(.recordsAdministrator),
                amount: 20,
                remainingHP: 0
            )),
            .combat(.victory(.recordsAdministrator))
        ])

        XCTAssertEqual(cues, [
            .spellAccepted(perfect: false),
            .barrierBroken(strong: false),
            .enemyDamaged,
            .victory
        ])
    }

    func testRejectedSpellProducesOnlyErrorFeedback() {
        let cues = mapper.cues(for: [
            .combat(.spellRejected(spell: .afterglowErasure, reason: .incompleteGlyph))
        ])

        XCTAssertEqual(cues, [.spellRejected])
    }

    func testRecordRewardAndFloorTransitionEventsAreDistinct() {
        let cues = mapper.cues(for: [
            .progression(.recordRead("record")),
            .progression(.rewardCandidates([])),
            .progression(.rewardSelected(candidateID: "reward", spell: nil)),
            .progression(.sceneChanged(.floor8Antechamber))
        ])

        XCTAssertEqual(cues, [
            .recordOpened,
            .recordOpened,
            .rewardSelected,
            .floorTransition
        ])
    }

    func testSameFloorSceneChangeDoesNotProduceFloorTransition() {
        let cues = mapper.cues(for: [
            .progression(.sceneChanged(.floor9RecordsBattle)),
            .progression(.sceneChanged(.floor9RewardVault)),
            .progression(.sceneChanged(.floor9DescentDoor))
        ])

        XCTAssertTrue(cues.isEmpty)
    }

    func testNonAttackEnemyActionDoesNotPlayManagerAttackSound() {
        let cues = mapper.cues(for: [
            .combat(.enemyActionStarted(.grantNormalBarrier(name: "기록 방벽", amount: 20)))
        ])

        XCTAssertTrue(cues.isEmpty)
    }

    func testZeroDamageEventDoesNotPlayHitSound() {
        let cues = mapper.cues(for: [
            .combat(.damageApplied(target: .player, amount: 0, remainingHP: 100))
        ])

        XCTAssertTrue(cues.isEmpty)
    }

    func testEncounterRestartDoesNotReplayCombatOrOutcomeSound() {
        let cues = mapper.cues(for: [
            .encounterStarted(.recordsAdministrator)
        ])

        XCTAssertTrue(cues.isEmpty)
    }

    func testAbsoluteBarrierNegationUsesBarrierImpactAfterCast() {
        let cues = mapper.cues(for: [
            .combat(.spellResolved(spell: .riftSeverance, grade: .approved)),
            .combat(.attackNegatedByAbsoluteBarrier(target: .enemy(.observationAdministrator)))
        ])

        XCTAssertEqual(cues, [
            .spellAccepted(perfect: false),
            .absoluteBarrierNegated
        ])
    }
}
