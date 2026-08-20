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
        try update(\.inputPreference, to: preference)
    }

    mutating func setSoundEffectsEnabled(_ isEnabled: Bool) throws {
        try update(\.soundEffectsEnabled, to: isEnabled)
    }

    mutating func setMusicEnabled(_ isEnabled: Bool) throws {
        try update(\.musicEnabled, to: isEnabled)
    }

    mutating func setHapticsEnabled(_ isEnabled: Bool) throws {
        try update(\.hapticsEnabled, to: isEnabled)
    }

    mutating func setReducedFlashes(_ isEnabled: Bool) throws {
        try update(\.reducedFlashes, to: isEnabled)
    }

    mutating func setReducedMotion(_ isEnabled: Bool) throws {
        try update(\.reducedMotion, to: isEnabled)
    }

    mutating func reset() {
        store.reset()
        settings = .defaults
    }

    private mutating func update<Value: Equatable>(
        _ keyPath: WritableKeyPath<GameSettings, Value>,
        to value: Value
    ) throws {
        guard settings[keyPath: keyPath] != value else { return }
        var updated = settings
        updated[keyPath: keyPath] = value
        try store.save(updated)
        settings = updated
    }
}
