import Foundation

struct GameSessionCoordinator {
    private(set) var session: DemoGameSession
    private(set) var hasSavedProgress: Bool

    private let saveStore: any GameSaveStore
    private let progressValidator: GameProgressValidator

    init(
        saveStore: any GameSaveStore,
        restoreFromStore: Bool = true,
        progressValidator: GameProgressValidator = GameProgressValidator()
    ) throws {
        self.saveStore = saveStore
        self.progressValidator = progressValidator
        if restoreFromStore, let progress = try saveStore.load() {
            try progressValidator.validate(progress)
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
        try progressValidator.validate(session.progress)
        try saveStore.save(session.progress)
        hasSavedProgress = session.progress != .newGame
    }
}
