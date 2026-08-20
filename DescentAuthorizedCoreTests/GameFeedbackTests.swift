import XCTest
@testable import DescentAuthorizedCore

final class GameFeedbackTests: XCTestCase {
    private let mapper = GameFeedbackMapper()

    func testPerfectDispelProducesCastAndDispelFeedback() {
        let cues = mapper.cues(for: [
            .combat(.spellResolved(spell: .sealRelease, grade: .perfect))
        ])

        XCTAssertEqual(cues, [
            .spellAccepted(perfect: true),
            .barrierDispelled
        ])
    }

    func testStrongEnemyActionMarksFollowingPlayerDamageAsStrong() {
        let action = EnemyAction.attack(name: "강공격", damage: 30, isStrong: true)
        let cues = mapper.cues(for: [
            .combat(.enemyActionStarted(action)),
            .combat(.damageApplied(target: .player, amount: 30, remainingHP: 70))
        ])

        XCTAssertEqual(cues, [.playerDamaged(strong: true)])
    }

    func testProgressionEventsProduceRewardAndDescentFeedback() {
        let cues = mapper.cues(for: [
            .progression(.rewardSelected(candidateID: "reward", spell: nil)),
            .progression(.sceneChanged(.floor8Antechamber))
        ])

        XCTAssertEqual(cues, [.rewardSelected, .descentApproved])
    }
}
