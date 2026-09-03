import XCTest
@testable import DescentAuthorizedCore

final class TutorialRuntimeTests: XCTestCase {
    func testTutorialSequenceCanResumeCompleteAndSkip() throws {
        var session = DemoGameSession()

        _ = try session.handle(.beginTutorial(sequence: .floor10Intro, step: .terminalBoot))
        XCTAssertEqual(session.progress.tutorialProgress.activeSequence, .floor10Intro)
        XCTAssertEqual(session.progress.tutorialProgress.activeStep, .terminalBoot)

        _ = try session.handle(.completeTutorialStep(step: .terminalBoot, next: .awaken))
        XCTAssertTrue(session.progress.tutorialProgress.completedSteps.contains(.terminalBoot))
        XCTAssertEqual(session.progress.tutorialProgress.activeStep, .awaken)

        _ = try session.handle(.completeTutorial(.floor10Intro))
        XCTAssertTrue(session.progress.tutorialProgress.completedSequences.contains(.floor10Intro))
        XCTAssertNil(session.progress.tutorialProgress.activeSequence)

        _ = try session.handle(.beginTutorial(sequence: .floor10Investigation, step: .explorationControls))
        _ = try session.handle(.skipTutorial(.floor10Investigation))
        XCTAssertTrue(session.progress.tutorialProgress.skippedSequences.contains(.floor10Investigation))
        XCTAssertFalse(session.progress.tutorialProgress.shouldPresent(.floor10Investigation))
    }

    func testTutorialFailureCountsPersistThroughRoundTrip() throws {
        var session = DemoGameSession()
        _ = try session.handle(.recordTutorialFailure(.descentSeal))
        _ = try session.handle(.recordTutorialFailure(.descentSeal))

        let data = try JSONEncoder().encode(session.progress)
        let restored = try JSONDecoder().decode(GameProgress.self, from: data)

        XCTAssertEqual(restored.tutorialProgress.failureCount(for: .descentSeal), 2)
        XCTAssertEqual(restored.saveVersion, GameProgress.currentSaveVersion)
    }

    func testLegacySaveMigratesWithoutForcingCompletedFloorTutorials() throws {
        let legacy: [String: Any] = [
            "saveVersion": 1,
            "currentFloor": 9,
            "currentScene": "floor9Entrance",
            "checkpoint": "floor10Complete",
            "playerHP": 100,
            "learnedSpells": ["afterglowErasure", "riftSeverance"],
            "defeatedEnemies": [],
            "readRecordIDs": [],
            "tutorials": ["cardSelection", "drawing"],
            "spellMastery": [],
            "completedTrainingSpells": ["afterglowErasure", "riftSeverance"],
            "selectedRewardIDs": [],
            "isDemoComplete": false
        ]
        let data = try JSONSerialization.data(withJSONObject: legacy)
        let progress = try JSONDecoder().decode(GameProgress.self, from: data)

        XCTAssertEqual(progress.saveVersion, GameProgress.currentSaveVersion)
        XCTAssertEqual(progress.furthestCheckpoint, .floor10Complete)
        XCTAssertTrue(progress.tutorialProgress.completedSequences.contains(.floor10Intro))
        XCTAssertTrue(progress.tutorialProgress.completedSequences.contains(.floor10Investigation))
        XCTAssertTrue(progress.tutorialProgress.completedSequences.contains(.floor10DescentSeal))
        XCTAssertFalse(progress.tutorialProgress.shouldPresent(.floor10Intro))
    }

    func testInvalidActiveTutorialStateIsRejected() {
        var progress = GameProgress.newGame
        progress.tutorialProgress.activeSequence = .floor10Intro

        XCTAssertThrowsError(try GameProgressValidator().validate(progress))
    }

    func testReplayRequestOverridesCompletedAndSkippedSequence() throws {
        var session = DemoGameSession()
        _ = try session.handle(.skipTutorial(.recordsBattleBasics))
        XCTAssertFalse(session.progress.tutorialProgress.shouldPresent(.recordsBattleBasics))

        _ = try session.handle(.requestTutorialReplay(.recordsBattleBasics))
        XCTAssertTrue(session.progress.tutorialProgress.shouldPresent(.recordsBattleBasics))
        XCTAssertEqual(session.progress.tutorialProgress.requestedReplay, .recordsBattleBasics)

        _ = try session.handle(.beginTutorial(
            sequence: .recordsBattleBasics,
            step: .battlePlayerHP
        ))
        _ = try session.handle(.completeTutorial(.recordsBattleBasics))
        XCTAssertNil(session.progress.tutorialProgress.requestedReplay)
        XCTAssertTrue(session.progress.tutorialProgress.completedSequences.contains(.recordsBattleBasics))
        XCTAssertFalse(session.progress.tutorialProgress.skippedSequences.contains(.recordsBattleBasics))
    }

    func testResetTutorialsKeepsGameplayProgress() throws {
        var progress = GameProgress.newGame
        progress.playerHP = 73
        progress.learnedSpells.insert(.afterglowErasure)
        progress.readRecordIDs.insert("floor10.clue.training-target")
        progress.tutorialProgress.completedSequences.insert(.floor10Intro)
        progress.tutorialProgress.failureCounts[.afterglowDrawing] = 2
        var session = DemoGameSession(progress: progress)

        _ = try session.handle(.resetTutorials)

        XCTAssertEqual(session.progress.playerHP, 73)
        XCTAssertTrue(session.progress.learnedSpells.contains(.afterglowErasure))
        XCTAssertTrue(session.progress.readRecordIDs.contains("floor10.clue.training-target"))
        XCTAssertEqual(session.progress.tutorialProgress, .empty)
    }

    func testActiveStepPersistsAcrossSaveRestore() throws {
        let store = InMemoryGameSaveStore()
        var session = DemoGameSession()
        _ = try session.handle(.beginTutorial(
            sequence: .floor10DescentSeal,
            step: .descentInformation
        ))
        try session.save(to: store)

        let restored = try DemoGameSession.restore(from: store)
        XCTAssertEqual(restored.progress.tutorialProgress.activeSequence, .floor10DescentSeal)
        XCTAssertEqual(restored.progress.tutorialProgress.activeStep, .descentInformation)
    }
}
