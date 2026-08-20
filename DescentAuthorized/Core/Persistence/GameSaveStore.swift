import Foundation

enum GameSaveError: Error, Equatable {
    case unsupportedVersion(Int)
}

protocol GameSaveStore {
    func load() throws -> GameProgress?
    func save(_ progress: GameProgress) throws
    func delete() throws
}

final class InMemoryGameSaveStore: GameSaveStore {
    private var storedProgress: GameProgress?

    init(progress: GameProgress? = nil) {
        storedProgress = progress
    }

    func load() throws -> GameProgress? {
        storedProgress
    }

    func save(_ progress: GameProgress) throws {
        storedProgress = progress
    }

    func delete() throws {
        storedProgress = nil
    }
}

struct FileGameSaveStore: GameSaveStore {
    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load() throws -> GameProgress? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(GameProgress.self, from: data)
    }

    func save(_ progress: GameProgress) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(progress).write(to: fileURL, options: .atomic)
    }

    func delete() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}

extension GameProgressionController {
    func save(to store: any GameSaveStore) throws {
        try store.save(progress)
    }

    static func restore(from store: any GameSaveStore) throws -> GameProgressionController {
        guard let progress = try store.load() else {
            return GameProgressionController()
        }
        guard progress.saveVersion <= GameProgress.newGame.saveVersion else {
            throw GameSaveError.unsupportedVersion(progress.saveVersion)
        }
        return GameProgressionController(progress: progress)
    }
}
