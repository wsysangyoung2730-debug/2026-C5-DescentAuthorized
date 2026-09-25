/// Keeps passive drawing feedback separate from the scroll-only teaching sequence.
enum GlyphInputFeedbackMode: Equatable, Sendable {
    case disabled
    case practice
    case battle

    var showsPracticeGuidance: Bool {
        self == .practice
    }

    var showsCheckpointFeedback: Bool {
        self != .disabled
    }

    var checkpointVolume: Float {
        switch self {
        case .disabled: 0
        case .practice: 0.58
        case .battle: 0.40
        }
    }
}
