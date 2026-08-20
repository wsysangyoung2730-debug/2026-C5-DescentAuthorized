import Foundation

enum DrawingInputPreference: String, Codable, CaseIterable, Sendable {
    case automatic
    case pencilOnly
    case fingerOnly
}

struct GameSettings: Codable, Equatable, Sendable {
    static let currentVersion = 1
    static let defaults = GameSettings(
        saveVersion: currentVersion,
        inputPreference: .automatic
    )

    var saveVersion: Int
    var inputPreference: DrawingInputPreference

    init(
        saveVersion: Int = currentVersion,
        inputPreference: DrawingInputPreference = .automatic
    ) {
        self.saveVersion = saveVersion
        self.inputPreference = inputPreference
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
