import Foundation
import XCTest
@testable import DescentAuthorizedCore

final class InputSettingsTests: XCTestCase {
    func testDefaultSettingsUseAutomaticInput() {
        XCTAssertEqual(GameSettings.defaults.inputPreference, .automatic)
        XCTAssertEqual(GameSettings.defaults.saveVersion, GameSettings.currentVersion)
    }

    func testAutomaticPolicyAcceptsPencilAndFinger() {
        let policy = DrawingInputPolicy(preference: .automatic)

        XCTAssertTrue(policy.accepts(.pencil))
        XCTAssertTrue(policy.accepts(.finger))
    }

    func testExclusivePoliciesOnlyAcceptConfiguredMethod() {
        let pencil = DrawingInputPolicy(preference: .pencilOnly)
        let finger = DrawingInputPolicy(preference: .fingerOnly)

        XCTAssertTrue(pencil.accepts(.pencil))
        XCTAssertFalse(pencil.accepts(.finger))
        XCTAssertFalse(finger.accepts(.pencil))
        XCTAssertTrue(finger.accepts(.finger))
    }

    func testFingerEvaluationProfileIsForgivingWithoutLimitingGrade() {
        let pencil = DrawingInputPolicy.evaluationProfile(for: .pencil)
        let finger = DrawingInputPolicy.evaluationProfile(for: .finger)

        XCTAssertGreaterThan(finger.nodeRadiusMultiplier, pencil.nodeRadiusMultiplier)
        XCTAssertGreaterThan(finger.pathRadiusMultiplier, pencil.pathRadiusMultiplier)
        XCTAssertGreaterThan(finger.crossingRadiusMultiplier, pencil.crossingRadiusMultiplier)
    }

    func testInMemorySettingsStoreRoundTripsAndResets() throws {
        let store = InMemoryGameSettingsStore()
        let settings = GameSettings(inputPreference: .fingerOnly)

        try store.save(settings)
        XCTAssertEqual(store.load(), settings)

        store.reset()
        XCTAssertEqual(store.load(), .defaults)
    }

    func testUserDefaultsSettingsStoreRoundTrips() throws {
        let suiteName = "InputSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsGameSettingsStore(defaults: defaults)
        let settings = GameSettings(inputPreference: .pencilOnly)

        try store.save(settings)

        XCTAssertEqual(store.load(), settings)
    }

    func testCorruptedSettingsFallBackToDefaults() throws {
        let suiteName = "InputSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data("invalid-json".utf8), forKey: UserDefaultsGameSettingsStore.defaultKey)
        let store = UserDefaultsGameSettingsStore(defaults: defaults)

        XCTAssertEqual(store.load(), .defaults)
    }

    func testFutureSettingsVersionFallsBackToDefaults() throws {
        let suiteName = "InputSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsGameSettingsStore(defaults: defaults)
        try store.save(GameSettings(
            saveVersion: GameSettings.currentVersion + 1,
            inputPreference: .fingerOnly
        ))

        XCTAssertEqual(store.load(), .defaults)
    }

    func testSettingsManagerPersistsInputPreferenceBeforePublishingIt() throws {
        let store = InMemoryGameSettingsStore()
        var manager = GameSettingsManager(store: store)

        try manager.setInputPreference(.fingerOnly)

        XCTAssertEqual(manager.settings.inputPreference, .fingerOnly)
        XCTAssertEqual(store.load().inputPreference, .fingerOnly)
    }

    func testSettingsManagerKeepsPreviousValueWhenSaveFails() {
        let store = FailingGameSettingsStore()
        var manager = GameSettingsManager(store: store)

        XCTAssertThrowsError(try manager.setInputPreference(.pencilOnly))
        XCTAssertEqual(manager.settings, .defaults)
    }

    func testSettingsManagerResetRestoresAutomaticMode() throws {
        let store = InMemoryGameSettingsStore(
            settings: GameSettings(inputPreference: .fingerOnly)
        )
        var manager = GameSettingsManager(store: store)

        manager.reset()

        XCTAssertEqual(manager.settings, .defaults)
        XCTAssertEqual(store.load(), .defaults)
    }
}

private final class FailingGameSettingsStore: GameSettingsStore {
    struct SaveFailure: Error {}

    func load() -> GameSettings { .defaults }
    func save(_ settings: GameSettings) throws { throw SaveFailure() }
    func reset() {}
}
