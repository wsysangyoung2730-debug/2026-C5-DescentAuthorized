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

    var drawingPadPosition: DrawingPadPosition {
        settings.drawingPadPosition
    }

    var reducedFlashes: Bool { settings.reducedFlashes }
    var reducedMotion: Bool { settings.reducedMotion }

    func setInputPreference(_ preference: DrawingInputPreference) {
        update { try $0.setInputPreference(preference) }
    }

    func setDrawingPadPosition(_ position: DrawingPadPosition) {
        update { try $0.setDrawingPadPosition(position) }
    }

    func setSoundEffectsEnabled(_ isEnabled: Bool) {
        update { try $0.setSoundEffectsEnabled(isEnabled) }
    }

    func setMusicEnabled(_ isEnabled: Bool) {
        update { try $0.setMusicEnabled(isEnabled) }
    }

    func setHapticsEnabled(_ isEnabled: Bool) {
        update { try $0.setHapticsEnabled(isEnabled) }
    }

    func setReducedFlashes(_ isEnabled: Bool) {
        update { try $0.setReducedFlashes(isEnabled) }
    }

    func setReducedMotion(_ isEnabled: Bool) {
        update { try $0.setReducedMotion(isEnabled) }
    }

    private func update(
        _ operation: (inout GameSettingsManager) throws -> Void
    ) {
        do {
            try operation(&manager)
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
