import XCTest
@testable import DescentAuthorizedCore

final class CatalogTests: XCTestCase {
    func testSpellCatalogContainsEveryDemoSpell() {
        XCTAssertEqual(SpellCatalog.all.count, SpellID.allCases.count)

        for id in SpellID.allCases {
            let spell = SpellCatalog.spell(id)
            XCTAssertEqual(spell.id, id)
            XCTAssertEqual(spell.requiredStrokes, spell.glyph.strokes.count)
            XCTAssertGreaterThan(spell.recommendedMana, 0)
        }
    }

    func testSpellStrokeCountsMatchPRD() {
        XCTAssertEqual(SpellCatalog.afterglowErasure.requiredStrokes, 1)
        XCTAssertEqual(SpellCatalog.riftSeverance.requiredStrokes, 1)
        XCTAssertEqual(SpellCatalog.barrierPiercing.requiredStrokes, 2)
        XCTAssertEqual(SpellCatalog.basicBarrier.requiredStrokes, 1)
        XCTAssertEqual(SpellCatalog.sealRelease.requiredStrokes, 1)
    }

    func testEnemyCatalogContainsEveryDemoEnemy() {
        XCTAssertEqual(EnemyCatalog.all.count, EnemyID.allCases.count)

        for id in EnemyID.allCases {
            let enemy = EnemyCatalog.enemy(id)
            XCTAssertEqual(enemy.id, id)
            XCTAssertGreaterThan(enemy.maxHP, 0)
            XCTAssertFalse(enemy.pattern.isEmpty)
        }
    }

    func testObservationAdministratorStartsWithAbsoluteBarrier() {
        let enemy = EnemyCatalog.observationAdministrator

        XCTAssertEqual(enemy.startingAbsoluteBarrierCharges, 1)
        XCTAssertEqual(enemy.thresholdRules.count, 1)
    }

    func testNewGameProgressRoundTripsThroughJSON() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(GameProgress.newGame)
        let restored = try JSONDecoder().decode(GameProgress.self, from: data)

        XCTAssertEqual(restored, .newGame)
    }
}
