import Foundation

protocol GameSettingsStore {
    func load() -> GameSettings
    func save(_ settings: GameSettings) throws
    func reset()
}

final class InMemoryGameSettingsStore: GameSettingsStore {
    private var settings: GameSettings

    init(settings: GameSettings = .defaults) {
        self.settings = settings
    }

    func load() -> GameSettings {
        settings
    }

    func save(_ settings: GameSettings) throws {
        self.settings = settings
    }

    func reset() {
        settings = .defaults
    }
}

struct UserDefaultsGameSettingsStore: GameSettingsStore {
    static let defaultKey = "descentAuthorized.gameSettings"

    let defaults: UserDefaults
    let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = defaultKey
    ) {
        self.defaults = defaults
        self.key = key
    }

    func load() -> GameSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(GameSettings.self, from: data),
              settings.saveVersion <= GameSettings.currentVersion else {
            return .defaults
        }
        return settings
    }

    func save(_ settings: GameSettings) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        defaults.set(try encoder.encode(settings), forKey: key)
    }

    func reset() {
        defaults.removeObject(forKey: key)
    }
}
