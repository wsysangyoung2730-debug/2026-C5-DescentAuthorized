import Foundation
import XCTest
@testable import DescentAuthorizedCore

final class ExpansionProgressTests: XCTestCase {
    func testLegacySaveMigratesLearnedCardsAndKeepsFurthestCheckpoint() throws {
        var original = GameProgress.newGame
        original.learnedSpells = [.afterglowErasure, .riftSeverance, .basicBarrier, .sealRelease]
        original.furthestCheckpoint = .observationDefeated
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any]
        )
        json["saveVersion"] = 3
        for key in ["equippedSpells", "protectedAttack", "protectedDefense", "loadoutTutorials", "expansion"] {
            json.removeValue(forKey: key)
        }
        let restored = try JSONDecoder().decode(
            GameProgress.self, from: JSONSerialization.data(withJSONObject: json)
        )
        XCTAssertEqual(restored.furthestCheckpoint, .observationDefeated)
        XCTAssertEqual(Set(restored.equippedSpells), original.learnedSpells)
        XCTAssertTrue(restored.loadoutIssues.isEmpty)
        XCTAssertTrue(restored.loadoutTutorials.isEmpty)
        XCTAssertNil(restored.expansion)
    }

    func testChosenAttackAndOrderSurviveRoundTripAndInvalidSelectionIsRejected() throws {
        var progress = GameProgress.newGame
        progress.learnedSpells = [.afterglowErasure, .riftSeverance, .basicBarrier, .sealRelease]
        let chosen: [SpellID] = [.sealRelease, .riftSeverance, .basicBarrier]
        XCTAssertTrue(progress.setLoadout(chosen, protectedAttack: .riftSeverance))
        XCTAssertFalse(progress.setLoadout([.riftSeverance, .basicBarrier]))
        progress.expansion = ExpansionProgress(floorNumber: 6, stage: .descent, descentStage: 1)
        progress.loadoutTutorials = [.firstSixLoadout, .firstOverflowLoadout]
        let restored = try JSONDecoder().decode(
            GameProgress.self, from: JSONEncoder().encode(progress)
        )
        XCTAssertEqual(restored, progress)
        XCTAssertEqual(restored.equippedSpells, chosen)
        XCTAssertEqual(restored.protectedSpells, Set(chosen))
        XCTAssertEqual(restored.expansion?.descentStage, 1)
    }

    func testLearningFillsAvailableSlotsAndDoesNotLosePlayerProtectionChoice() {
        var progress = GameProgress.newGame
        progress.learnedSpells = [.riftSeverance, .basicBarrier, .sealRelease]
        XCTAssertTrue(progress.setLoadout(
            [.riftSeverance, .basicBarrier, .sealRelease], protectedAttack: .riftSeverance
        ))
        progress.learnedSpells.insert(.afterglowErasure)
        XCTAssertEqual(progress.equippedSpells, [.riftSeverance, .basicBarrier, .sealRelease, .afterglowErasure])
        XCTAssertEqual(progress.protectedAttack, .riftSeverance)
        XCTAssertEqual(ExpansionProgress(stage: .bossBattle).resumableStage, .bossPreparation)
    }
}
