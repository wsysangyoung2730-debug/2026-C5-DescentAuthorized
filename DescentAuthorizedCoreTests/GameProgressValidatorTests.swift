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
        _ = try controller.beginRecordsBattle()
        try assertValid(controller.progress)
        _ = try controller.completeEncounter(enemy: .recordsAdministrator, remainingPlayerHP: 55)
        try assertValid(controller.progress)
        _ = try controller.continueAfterRecordsDefeat()
        try assertValid(controller.progress)
        _ = try controller.selectReward(candidateID: "floor9-worn-a")
        try assertValid(controller.progress)
        _ = try controller.approveDescentDoor()
        try assertValid(controller.progress)
        _ = try controller.enterProtectionRoom()
        try assertValid(controller.progress)
        _ = try controller.learnBasicBarrier()
        try assertValid(controller.progress)
        _ = try controller.completeProtectionTraining(grade: .approved)
        try assertValid(controller.progress)
        _ = try controller.completeEncounter(enemy: .observationResidual, remainingPlayerHP: 45)
        try assertValid(controller.progress)
        _ = try controller.releaseObservationDoor()
        try assertValid(controller.progress)
        _ = try controller.completeEncounter(enemy: .observationAdministrator, remainingPlayerHP: 35)
        try assertValid(controller.progress)
        _ = try controller.selectReward(candidateID: "floor8-forbidden")
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

    private func assertValid(
        _ progress: GameProgress,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertNoThrow(try validator.validate(progress), file: file, line: line)
    }
}
