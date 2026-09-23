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

    func testLowerFloorsNeverRequestAnUpperFloorRealityRoom() {
        for floor in 1...4 {
            for stage in ExpansionStage.allCases {
                XCTAssertNil(ExpansionSceneRoute(.init(floorNumber: floor, stage: stage)))
            }
        }
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
