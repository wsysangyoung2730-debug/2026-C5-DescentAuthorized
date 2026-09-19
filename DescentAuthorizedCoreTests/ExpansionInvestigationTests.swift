import Foundation
import XCTest
@testable import DescentAuthorizedCore

final class ExpansionInvestigationTests: XCTestCase {
    func testPartialInvestigationSurvivesSaveWithoutRevealingEnemyEarly() throws {
        for floor in 5...7 {
            var seed = GameProgress.newGame
            seed.currentScene = .demoComplete
            seed.isDemoComplete = true
            seed.expansion = .init(floorNumber: floor)
            var session = DemoGameSession(progress: seed)
            let records = ExpansionInvestigationCatalog.records(for: floor)
            XCTAssertEqual(records.count, 2)
            _ = try session.handle(.readRecord(records[0].id))
            let restored = try JSONDecoder().decode(GameProgress.self, from: JSONEncoder().encode(session.progress))
            session = DemoGameSession(progress: restored)
            XCTAssertEqual(session.progress.expansion?.stage, .entrance)
            XCTAssertFalse(ExpansionInvestigationCatalog.isComplete(floor: floor, readRecordIDs: session.progress.readRecordIDs))
            _ = try session.handle(.readRecord(records[0].id))
            XCTAssertEqual(session.progress.readRecordIDs.count, 1)
            _ = try session.handle(.readRecord(records[1].id))
            let complete = try JSONDecoder().decode(GameProgress.self, from: JSONEncoder().encode(session.progress))
            XCTAssertTrue(ExpansionInvestigationCatalog.isComplete(floor: floor, readRecordIDs: complete.readRecordIDs))
            for other in (5...7) where other != floor {
                XCTAssertFalse(ExpansionInvestigationCatalog.isComplete(floor: other, readRecordIDs: complete.readRecordIDs))
            }
        }
    }
}
