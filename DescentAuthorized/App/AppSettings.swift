import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    @Published private(set) var settings: GameSettings
    @Published var showsPersistenceError = false

    private var manager: GameSettingsManager

    init(store: any GameSettingsStore = UserDefaultsGameSettingsStore()) {
        manager = GameSettingsManager(store: store)
        settings = manager.settings
    }

    var inputPreference: DrawingInputPreference {
        settings.inputPreference
    }

    func setInputPreference(_ preference: DrawingInputPreference) {
        do {
            try manager.setInputPreference(preference)
            settings = manager.settings
        } catch {
            showsPersistenceError = true
        }
    }

    func reset() {
        manager.reset()
        settings = manager.settings
    }
}
