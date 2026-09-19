import XCTest
@testable import DescentAuthorizedCore

final class TutorialRuntimeTests: XCTestCase {
    func testLoadoutGuideResumesEveryPageWithoutStartingEncounter() throws {
        var seed = GameProgress.newGame
        seed.furthestCheckpoint = .recordsBattle
        var session = DemoGameSession(progress: seed)
        _ = try session.handle(.travelToCheckpoint(.recordsBattle))
        let spells = session.progress.equippedSpells
        let store = InMemoryGameSaveStore()
        _ = try session.handle(.beginTutorial(sequence: .floor9Loadout, step: .loadoutOverview))
        for step in Floor9LoadoutGuide.steps {
            XCTAssertEqual(Floor9LoadoutGuide.currentStep(in: session.progress), step)
            try session.save(to: store)
            session = try DemoGameSession.restore(from: store)
            XCTAssertEqual(Floor9LoadoutGuide.currentStep(in: session.progress), step)
            XCTAssertEqual(session.progress.currentScene, .floor9RecordsPreparation)
            XCTAssertEqual(session.progress.equippedSpells, spells)
            XCTAssertNil(session.encounter)
            _ = try session.handle(.completeTutorialStep(step: step, next: Floor9LoadoutGuide.next(after: step) ?? step))
        }
        _ = try session.handle(.completeTutorial(.floor9Loadout))
        try session.save(to: store)
        session = try DemoGameSession.restore(from: store)
        XCTAssertNil(Floor9LoadoutGuide.currentStep(in: session.progress))
        XCTAssertEqual(session.progress.currentScene, .floor9RecordsPreparation)
        _ = try session.handle(.requestTutorialReplay(.floor9Loadout))
        XCTAssertEqual(Floor9LoadoutGuide.currentStep(in: session.progress), .loadoutOverview)
    }

    func testLoadoutGuideIsRestrictedToFloor9Preparation() {
        var progress = GameProgress.newGame
        XCTAssertNil(Floor9LoadoutGuide.currentStep(in: progress))
        progress.currentFloor = .floor9
        progress.currentScene = .floor9RecordsPreparation
        XCTAssertEqual(Floor9LoadoutGuide.currentStep(in: progress), .loadoutOverview)
        progress.currentScene = .floor9RecordsEncounter
        XCTAssertNil(Floor9LoadoutGuide.currentStep(in: progress))
        progress.currentFloor = .floor8
        progress.currentScene = .floor8ResidualPreparation
        XCTAssertNil(Floor9LoadoutGuide.currentStep(in: progress))
    }

    func testExistingSaveWithoutLoadoutGuideFlagCanOpenNewGuide() throws {
        var progress = GameProgress.newGame
        progress.currentFloor = .floor9
        progress.currentScene = .floor9RecordsPreparation
        progress.tutorialProgress.completedSequences = [.afterglowDiscovery, .recordsBattleBasics]
        let restored = try JSONDecoder().decode(GameProgress.self, from: JSONEncoder().encode(progress))
        XCTAssertEqual(Floor9LoadoutGuide.currentStep(in: restored), .loadoutOverview)
    }

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
