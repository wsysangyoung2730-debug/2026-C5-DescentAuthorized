import Foundation

enum DrawingInputPreference: String, Codable, CaseIterable, Sendable {
    case automatic
    case pencilOnly
    case fingerOnly
}

enum DrawingPadPosition: String, Codable, CaseIterable, Sendable {
    case left
    case right
}

struct GameSettings: Codable, Equatable, Sendable {
    static let currentVersion = 3
    static let defaults = GameSettings(
        saveVersion: currentVersion,
        inputPreference: .automatic,
        drawingPadPosition: .left,
        soundEffectsEnabled: true,
        musicEnabled: true,
        hapticsEnabled: true,
        reducedFlashes: false,
        reducedMotion: false
    )

    var saveVersion: Int
    var inputPreference: DrawingInputPreference
    var drawingPadPosition: DrawingPadPosition
    var soundEffectsEnabled: Bool
    var musicEnabled: Bool
    var hapticsEnabled: Bool
    var reducedFlashes: Bool
    var reducedMotion: Bool

    init(
        saveVersion: Int = currentVersion,
        inputPreference: DrawingInputPreference = .automatic,
        drawingPadPosition: DrawingPadPosition = .left,
        soundEffectsEnabled: Bool = true,
        musicEnabled: Bool = true,
        hapticsEnabled: Bool = true,
        reducedFlashes: Bool = false,
        reducedMotion: Bool = false
    ) {
        self.saveVersion = saveVersion
        self.inputPreference = inputPreference
        self.drawingPadPosition = drawingPadPosition
        self.soundEffectsEnabled = soundEffectsEnabled
        self.musicEnabled = musicEnabled
        self.hapticsEnabled = hapticsEnabled
        self.reducedFlashes = reducedFlashes
        self.reducedMotion = reducedMotion
    }

    func migratedToCurrentVersion() -> GameSettings {
        var migrated = self
        migrated.saveVersion = Self.currentVersion
        return migrated
    }

    private enum CodingKeys: String, CodingKey {
        case saveVersion
        case inputPreference
        case drawingPadPosition
        case soundEffectsEnabled
        case musicEnabled
        case hapticsEnabled
        case reducedFlashes
        case reducedMotion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        saveVersion = try container.decodeIfPresent(Int.self, forKey: .saveVersion) ?? 1
        inputPreference = try container.decodeIfPresent(
            DrawingInputPreference.self,
            forKey: .inputPreference
        ) ?? .automatic
        drawingPadPosition = try container.decodeIfPresent(
            DrawingPadPosition.self,
            forKey: .drawingPadPosition
        ) ?? .left
        soundEffectsEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .soundEffectsEnabled
        ) ?? true
        musicEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .musicEnabled
        ) ?? true
        hapticsEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .hapticsEnabled
        ) ?? true
        reducedFlashes = try container.decodeIfPresent(
            Bool.self,
            forKey: .reducedFlashes
        ) ?? false
        reducedMotion = try container.decodeIfPresent(
            Bool.self,
            forKey: .reducedMotion
        ) ?? false
    }
}

struct DrawingEvaluationProfile: Equatable, Sendable {
    let nodeRadiusMultiplier: Double
    let pathRadiusMultiplier: Double
    let crossingRadiusMultiplier: Double

    static let pencil = DrawingEvaluationProfile(
        nodeRadiusMultiplier: 1,
        pathRadiusMultiplier: 1,
        crossingRadiusMultiplier: 1
    )

    static let finger = DrawingEvaluationProfile(
        nodeRadiusMultiplier: 1.2,
        pathRadiusMultiplier: 1.15,
        crossingRadiusMultiplier: 1.15
    )
}
