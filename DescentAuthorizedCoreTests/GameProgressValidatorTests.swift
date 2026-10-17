import Foundation
import XCTest
@testable import DescentAuthorizedCore

final class GameProgressValidatorTests: XCTestCase {
    private let validator = GameProgressValidator()

    func testNewGameProgressIsValid() throws {
        XCTAssertNoThrow(try validator.validate(.newGame))
    }

    func testEveryProducedProgressStateIsValid() throws {
        var controller = GameProgressionController()

        try assertValid(controller.progress)
        _ = try controller.leaveMeetingRoom()
        try assertValid(controller.progress)
        _ = try controller.learnAfterglowErasure()
        try assertValid(controller.progress)
        _ = try controller.completeTraining(spell: .afterglowErasure, grade: .approved)
        try assertValid(controller.progress)
        _ = try controller.learnRiftSeverance()
        try assertValid(controller.progress)
        _ = try controller.completeTraining(spell: .riftSeverance, grade: .precise)
        try assertValid(controller.progress)
        _ = try controller.approveDescentDoor()
        try assertValid(controller.progress)
        _ = try controller.enterRecordsBattle()
        try assertValid(controller.progress)
        _ = try controller.enterRecordsEncounter()
        _ = try controller.beginRecordsBattle()
        try assertValid(controller.progress)
        _ = try controller.completeEncounter(enemy: .recordsAdministrator, remainingPlayerHP: 55)
        try assertValid(controller.progress)
        _ = try controller.continueAfterRecordsDefeat()
        try assertValid(controller.progress)
        _ = try controller.selectReward(candidateID: "floor9-barrier")
        try assertValid(controller.progress)
        _ = try controller.completeRewardLearning(
            candidateID: "floor9-barrier",
            grade: .approved
        )
        try assertValid(controller.progress)
        _ = try controller.approveDescentDoor()
        try assertValid(controller.progress)
        _ = try controller.enterProtectionRoom()
        try assertValid(controller.progress)
        _ = try controller.learnBasicBarrier()
        try assertValid(controller.progress)
        _ = try controller.completeProtectionTraining(grade: .approved)
        try assertValid(controller.progress)
        _ = try controller.enterResidualEncounter()
        _ = try controller.beginResidualBattle()
        try assertValid(controller.progress)
        _ = try controller.completeEncounter(enemy: .observationResidual, remainingPlayerHP: 45)
        try assertValid(controller.progress)
        _ = try controller.continueAfterResidualDefeat()
        try assertValid(controller.progress)
        _ = try controller.completeScrollLearning(spell: .sealRelease, grade: .approved)
        try assertValid(controller.progress)
        _ = try controller.releaseObservationDoor()
        try assertValid(controller.progress)
        _ = try controller.enterAdministratorEncounter()
        try assertValid(controller.progress)
        _ = try controller.beginAdministratorBattle()
        try assertValid(controller.progress)
        _ = try controller.completeEncounter(enemy: .observationAdministrator, remainingPlayerHP: 35)
        try assertValid(controller.progress)
        _ = try controller.continueAfterAdministratorDefeat()
        try assertValid(controller.progress)
        _ = try controller.selectReward(candidateID: "floor8-rupture")
        try assertValid(controller.progress)
        _ = try controller.completeRewardLearning(
            candidateID: "floor8-rupture",
            grade: .approved
        )
        try assertValid(controller.progress)
        _ = try controller.approveDescentDoor()
        try assertValid(controller.progress)
    }

    func testInvalidHPAndMasteryAreRejected() throws {
        var progress = GameProgress.newGame
        progress.playerHP = 0
        XCTAssertThrowsError(try validator.validate(progress)) { error in
            XCTAssertEqual(error as? GameProgressValidationError, .invalidPlayerHP(0))
        }

        progress = .newGame
        progress.spellMastery[.afterglowErasure] = SpellMastery(
            bestGrade: .approved,
            successfulCasts: 1
        )
        XCTAssertThrowsError(try validator.validate(progress)) { error in
            XCTAssertEqual(
                error as? GameProgressValidationError,
                .invalidMastery(.afterglowErasure)
            )
        }
    }

    func testTrainingWallWithoutLearnedSpellIsRejected() {
        var progress = GameProgress.newGame
        progress.currentScene = .floor10TrainingWall

        XCTAssertThrowsError(try validator.validate(progress)) { error in
            XCTAssertEqual(
                error as? GameProgressValidationError,
                .missingRequirement("잔광 말소 습득")
            )
        }
    }

    func testGlyphArchiveRequiresCompletedFirstTraining() {
        var progress = GameProgress.newGame
        progress.currentScene = .floor10GlyphArchive
        progress.learnedSpells = [.afterglowErasure]

        XCTAssertThrowsError(try validator.validate(progress)) { error in
            XCTAssertEqual(
                error as? GameProgressValidationError,
                .missingRequirement("잔광 말소 훈련 완료")
            )
        }
    }

    func testMalformedExpansionIsRejectedBeforeCheckpointMigration() throws {
        let malformed: [[String: Any]] = [
            ["floorNumber": 1, "stage": "recordReward", "residualIndex": 1],
            ["floorNumber": 2, "stage": "recordReward", "residualIndex": 1],
            ["floorNumber": 0, "stage": "entrance"],
            ["floorNumber": 8, "stage": "bossBattle"],
            ["floorNumber": 2, "stage": "descent", "descentStage": 4],
            ["floorNumber": 2, "stage": "preparation", "residualIndex": -1],
            ["floorNumber": 7, "stage": "preparation", "residualIndex": 1]
        ]
        for expansion in malformed {
            let data = try savedData(expansion: expansion)
            XCTAssertThrowsError(try JSONDecoder().decode(GameProgress.self, from: data)) { error in
                guard case DecodingError.dataCorrupted = error else {
                    return XCTFail("Expected invalid expansion to throw safely: \(error)")
                }
            }
        }
    }

    func testInvalidExpansionRestorePreservesOriginalSaveFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("progress.json")
        let data = try savedData(expansion: ["floorNumber": 2, "stage": "recordReward", "residualIndex": 1])
        try data.write(to: url)

        XCTAssertThrowsError(try GameSessionCoordinator(saveStore: FileGameSaveStore(fileURL: url)))
        XCTAssertEqual(try Data(contentsOf: url), data)
    }

    func testSerializedUnsupportedSaveVersionIsRejectedBeforeMigration() throws {
        for version in [-1, 0, GameProgress.currentSaveVersion + 1] {
            var json = try XCTUnwrap(JSONSerialization.jsonObject(
                with: JSONEncoder().encode(GameProgress.newGame)
            ) as? [String: Any])
            json["saveVersion"] = version
            let data = try JSONSerialization.data(withJSONObject: json)
            XCTAssertThrowsError(try JSONDecoder().decode(GameProgress.self, from: data)) { error in
                XCTAssertEqual(error as? GameProgressValidationError, .unsupportedVersion(version))
            }
        }
    }

    func testInvalidInMemoryExpansionDoesNotCrashCheckpointMigration() {
        var progress = GameProgress.newGame
        progress.currentScene = .demoComplete
        progress.isDemoComplete = true
        progress.expansion = .init(floorNumber: 2, stage: .recordReward, residualIndex: 1)
        let checkpoint = progress.checkpoint
        progress.migrateExpansionCheckpoint()
        XCTAssertEqual(progress.checkpoint, checkpoint)
    }

    private func savedData(expansion: [String: Any]) throws -> Data {
        var seed = GameProgress.newGame
        seed.furthestCheckpoint = .towerHandoffComplete
        var controller = GameProgressionController(progress: seed)
        _ = try controller.travel(to: .floor2Encounter)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(controller.progress)
        ) as? [String: Any])
        json["expansion"] = expansion
        return try JSONSerialization.data(withJSONObject: json)
    }

    private func assertValid(
        _ progress: GameProgress,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertNoThrow(try validator.validate(progress), file: file, line: line)
    }
}
