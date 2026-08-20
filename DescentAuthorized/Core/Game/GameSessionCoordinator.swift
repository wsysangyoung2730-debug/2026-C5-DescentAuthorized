import Foundation

struct GameSessionCoordinator {
    private(set) var session: DemoGameSession
    private(set) var hasSavedProgress: Bool

    private let saveStore: any GameSaveStore

    init(
        saveStore: any GameSaveStore,
        restoreFromStore: Bool = true
    ) throws {
        self.saveStore = saveStore
        if restoreFromStore, let progress = try saveStore.load() {
            guard progress.saveVersion <= GameProgress.newGame.saveVersion else {
                throw GameSaveError.unsupportedVersion(progress.saveVersion)
            }
            session = DemoGameSession(progress: progress)
            hasSavedProgress = progress != .newGame
        } else {
            session = DemoGameSession()
            hasSavedProgress = false
        }
    }

    @discardableResult
    mutating func execute(_ command: DemoCommand) throws -> [DemoSessionEvent] {
        var updatedSession = session
        let previousProgress = session.progress
        let events = try updatedSession.handle(command)

        if updatedSession.progress != previousProgress {
            try saveStore.save(updatedSession.progress)
            hasSavedProgress = updatedSession.progress != .newGame
        }
        session = updatedSession
        return events
    }

    mutating func replaceWithNewGame() throws {
        try saveStore.delete()
        session = DemoGameSession()
        hasSavedProgress = false
    }

    mutating func saveCurrentProgress() throws {
        try saveStore.save(session.progress)
        hasSavedProgress = session.progress != .newGame
    }
}
