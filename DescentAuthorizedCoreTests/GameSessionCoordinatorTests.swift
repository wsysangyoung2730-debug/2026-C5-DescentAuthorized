import XCTest
@testable import DescentAuthorizedCore

final class GameSessionCoordinatorTests: XCTestCase {
    func testProgressChangingCommandIsSaved() throws {
        let store = InMemoryGameSaveStore()
        var coordinator = try GameSessionCoordinator(saveStore: store)

        _ = try coordinator.execute(.leaveMeetingRoom)

        XCTAssertEqual(try store.load(), coordinator.session.progress)
        XCTAssertTrue(coordinator.hasSavedProgress)
    }

    func testFailedSaveDoesNotPublishUpdatedSession() throws {
        var coordinator = try GameSessionCoordinator(
            saveStore: FailingGameSaveStore()
        )

        XCTAssertThrowsError(try coordinator.execute(.leaveMeetingRoom))
        XCTAssertEqual(coordinator.session.progress, .newGame)
    }

    func testCoordinatorRestoresSavedProgress() throws {
        var progress = GameProgress.newGame
        progress.currentScene = .floor10Office
        let store = InMemoryGameSaveStore(progress: progress)

        let coordinator = try GameSessionCoordinator(saveStore: store)

        XCTAssertEqual(coordinator.session.progress, progress)
        XCTAssertTrue(coordinator.hasSavedProgress)
    }

    func testNewGameDeletesStoredProgress() throws {
        var progress = GameProgress.newGame
        progress.currentScene = .floor10Office
        let store = InMemoryGameSaveStore(progress: progress)
        var coordinator = try GameSessionCoordinator(saveStore: store)

        try coordinator.replaceWithNewGame()

        XCTAssertNil(try store.load())
        XCTAssertEqual(coordinator.session.progress, .newGame)
        XCTAssertFalse(coordinator.hasSavedProgress)
    }

    func testCoordinatorRejectsFloorAndSceneMismatch() throws {
        var progress = GameProgress.newGame
        progress.currentFloor = .floor9
        let store = InMemoryGameSaveStore(progress: progress)

        XCTAssertThrowsError(try GameSessionCoordinator(saveStore: store)) { error in
            XCTAssertEqual(
                error as? GameProgressValidationError,
                .floorSceneMismatch(floor: .floor9, scene: .floor10MeetingRoom)
            )
        }
    }

    func testCoordinatorRejectsImpossibleSpellProgress() throws {
        var progress = GameProgress.newGame
        progress.currentScene = .floor10DescentDoor
        let store = InMemoryGameSaveStore(progress: progress)

        XCTAssertThrowsError(try GameSessionCoordinator(saveStore: store)) { error in
            XCTAssertEqual(
                error as? GameProgressValidationError,
                .missingRequirement("잔광 말소 습득")
            )
        }
    }

    func testCoordinatorRejectsFutureSaveVersion() throws {
        var progress = GameProgress.newGame
        progress.saveVersion += 1
        let store = InMemoryGameSaveStore(progress: progress)

        XCTAssertThrowsError(try GameSessionCoordinator(saveStore: store)) { error in
            XCTAssertEqual(
                error as? GameProgressValidationError,
                .unsupportedVersion(GameProgress.currentSaveVersion + 1)
            )
        }
    }
}

private struct FailingGameSaveStore: GameSaveStore {
    struct SaveFailure: Error {}

    func load() throws -> GameProgress? { nil }
    func save(_ progress: GameProgress) throws { throw SaveFailure() }
    func delete() throws {}
}
