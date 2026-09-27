import XCTest
@testable import DescentAuthorizedCore

final class LowerFloorNarrativeTests: XCTestCase {
    func testAllTwentyFourScenesHaveDistinctAssetsAndApprovedDialogueCount() throws {
        var assets = Set<String>()
        var count = 0
        for floor in 1...4 {
            for actor in 0...2 {
                for defeated in [false, true] {
                    let stage: ExpansionStage = actor == 2
                        ? (defeated ? .bossDefeated : .bossEncounter)
                        : (defeated ? .residualDefeated : .residualEncounter)
                    let narrative = try XCTUnwrap(ExpansionNarrative(progress: .init(
                        floorNumber: floor, stage: stage, residualIndex: min(actor, 1))))
                    XCTAssertTrue(assets.insert(narrative.backgroundAsset).inserted)
                    XCTAssertFalse(narrative.dialogues.isEmpty)
                    XCTAssertTrue(narrative.dialogues.allSatisfy { !$0.speaker.isEmpty && !$0.text.isEmpty })
                    XCTAssertTrue(narrative.dialogues.contains { $0.speaker == "주인공" })
                    count += narrative.dialogues.count
                }
            }
        }
        XCTAssertEqual(assets.count, 24)
        XCTAssertEqual(count, 168)
        XCTAssertEqual(LowerFloorNarrativeCatalog.ending.count, 5)
    }

    func testThirdFloorResidualsFollowGameplayOrder() throws {
        for (index, name, asset) in [(0, "동의 보관 잔류체", "Floor3ResidualAEncounter"),
                                    (1, "격리 집행 잔류체", "Floor3ResidualBEncounter")] {
            let narrative = try XCTUnwrap(ExpansionNarrative(progress: .init(
                floorNumber: 3, stage: .residualEncounter, residualIndex: index)))
            XCTAssertEqual(narrative.backgroundAsset, asset)
            XCTAssertTrue(narrative.dialogues.contains { $0.speaker == name })
        }
    }

    func testNarrativeDoesNotReplacePreparationBattleOrRewards() {
        for stage: ExpansionStage in [.entrance, .preparation, .residualBattle, .residualGate,
                                      .recordReward, .bossPreparation, .bossBattle, .reward, .finalRecord, .descent] {
            XCTAssertNil(ExpansionNarrative(progress: .init(floorNumber: 4, stage: stage)))
        }
        XCTAssertNil(ExpansionNarrative(progress: .init(floorNumber: 0, stage: .bossEncounter)))
    }

    func testPreparedBattleWaitsForDialogueCompletion() throws {
        var seed = GameProgress.newGame
        seed.furthestCheckpoint = .towerHandoffComplete
        var controller = GameProgressionController(progress: seed)
        _ = try controller.travel(to: .floor5Complete)
        for record in ExpansionInvestigationCatalog.records(for: 4) {
            _ = controller.readRecord(id: record.id)
        }
        var session = DemoGameSession(progress: controller.progress)
        _ = try session.handle(.beginPreparedLowerBattle)
        XCTAssertEqual(session.progress.expansion?.stage, .residualEncounter)
        XCTAssertNil(session.encounter)
        XCTAssertThrowsError(try session.handle(.startEncounter))
        XCTAssertThrowsError(try session.handle(.beginPreparedLowerBattle))
        _ = try session.handle(.advanceExpansion)
        XCTAssertEqual(session.progress.expansion?.stage, .residualBattle)
        _ = try session.handle(.startEncounter)
        XCTAssertNotNil(session.encounter)
    }

    func testUpperFloorAssetsRemainUnchanged() throws {
        for floor in 5...7 {
            let narrative = try XCTUnwrap(ExpansionNarrative(progress: .init(floorNumber: floor, stage: .residualEncounter)))
            XCTAssertEqual(narrative.backgroundAsset, "Floor\(floor)ResidualEncounter")
            XCTAssertFalse(narrative.dialogues.isEmpty)
        }
    }
}
