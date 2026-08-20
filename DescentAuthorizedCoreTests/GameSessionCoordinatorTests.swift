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
}

private struct FailingGameSaveStore: GameSaveStore {
    struct SaveFailure: Error {}

    func load() throws -> GameProgress? { nil }
    func save(_ progress: GameProgress) throws { throw SaveFailure() }
    func delete() throws {}
}
