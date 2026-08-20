import Foundation

struct GameSettingsManager {
    private(set) var settings: GameSettings
    private let store: any GameSettingsStore

    init(store: any GameSettingsStore = UserDefaultsGameSettingsStore()) {
        self.store = store
        settings = store.load()
    }

    mutating func setInputPreference(
        _ preference: DrawingInputPreference
    ) throws {
        guard preference != settings.inputPreference else { return }
        var updated = settings
        updated.inputPreference = preference
        try store.save(updated)
        settings = updated
    }

    mutating func reset() {
        store.reset()
        settings = .defaults
    }
}
