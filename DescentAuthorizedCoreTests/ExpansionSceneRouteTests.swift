import XCTest
@testable import DescentAuthorizedCore

final class ExpansionSceneRouteTests: XCTestCase {
    func testEveryPlayableStageRoutesToExpectedRoomAndCamera() {
        for floor in 5...7 {
            for stage in ExpansionStage.allCases where stage != .complete {
                let progress = ExpansionProgress(floorNumber: floor, stage: stage)
                guard progress.isValid else { continue }
                let route = ExpansionSceneRoute(progress)
                XCTAssertEqual(route?.floorNumber, floor)
                XCTAssertEqual(route?.isBoss, [.bossPreparation, .bossEncounter, .bossBattle, .bossDefeated, .reward, .descent].contains(stage))
                switch stage {
                case .sealedDoor, .descent: XCTAssertEqual(route?.camera, .descentInput)
                case .reward: XCTAssertEqual(route?.camera, .rewardSelection)
                default: XCTAssertEqual(route?.camera, .battle)
                }
            }
        }
    }

    func testTerminalAndUnsupportedFloorsHaveNoRoom() {
        XCTAssertNil(ExpansionSceneRoute(.init(floorNumber: 4, stage: .complete)))
        XCTAssertNil(ExpansionSceneRoute(.init(floorNumber: 8, stage: .entrance)))
        XCTAssertNil(ExpansionSceneRoute(.init(floorNumber: 5, stage: .complete)))
    }

    func testLowerFloorRoomIdentitySurvivesSaveAndBattleResume() throws {
        for floor in 1...4 {
            for index in 0...1 {
                let progress = ExpansionProgress(floorNumber: floor, stage: .residualBattle, residualIndex: index)
                var restored = try JSONDecoder().decode(ExpansionProgress.self, from: JSONEncoder().encode(progress))
                restored.stage = restored.resumableStage
                XCTAssertEqual(ExpansionSceneRoute(restored), ExpansionSceneRoute(progress))
                XCTAssertEqual(ExpansionSceneRoute(restored)?.room, index == 0 ? .residualA : .residualB)
                let boss = ExpansionProgress(floorNumber: floor, stage: .descent, descentStage: 2, residualIndex: index)
                XCTAssertEqual(ExpansionSceneRoute(boss)?.room, .administrator)
                XCTAssertEqual(ExpansionSceneRoute(boss)?.camera, .descentInput)
            }
        }
    }

    func testRecordRewardStaysInResidualRoomAndFinalRecordUsesAdministrator() {
        XCTAssertEqual(ExpansionSceneRoute(.init(floorNumber: 3, stage: .recordReward))?.room, .residualA)
        XCTAssertEqual(ExpansionSceneRoute(.init(floorNumber: 1, stage: .finalRecord, residualIndex: 1))?.room, .administrator)
        XCTAssertEqual(ExpansionSceneRoute(.init(floorNumber: 1, stage: .finalRecord))?.camera, .rewardSelection)
    }

    func testRestoredBattlesKeepTheirRoomAndPartialDescentKeepsInputCamera() {
        for floor in 5...7 {
            for stage in [ExpansionStage.residualEncounter, .bossEncounter, .residualBattle, .bossBattle] {
                let progress = ExpansionProgress(floorNumber: floor, stage: stage)
                let resumed = ExpansionProgress(floorNumber: floor, stage: progress.resumableStage)
                XCTAssertEqual(ExpansionSceneRoute(progress), ExpansionSceneRoute(resumed))
            }
            let partial = ExpansionProgress(floorNumber: floor, stage: .descent, descentStage: 1)
            XCTAssertEqual(ExpansionSceneRoute(partial)?.camera, .descentInput)
            XCTAssertEqual(ExpansionSceneRoute(partial)?.isBoss, true)
        }
    }
}
