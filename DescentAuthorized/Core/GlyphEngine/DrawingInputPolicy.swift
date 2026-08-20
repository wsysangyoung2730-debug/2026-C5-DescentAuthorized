import Foundation

struct DrawingInputPolicy: Equatable, Sendable {
    let preference: DrawingInputPreference

    init(preference: DrawingInputPreference) {
        self.preference = preference
    }

    func accepts(_ method: DrawingInputMethod) -> Bool {
        switch (preference, method) {
        case (.automatic, _), (.pencilOnly, .pencil), (.fingerOnly, .finger):
            true
        case (.pencilOnly, .finger), (.fingerOnly, .pencil):
            false
        }
    }

    static func evaluationProfile(
        for method: DrawingInputMethod
    ) -> DrawingEvaluationProfile {
        switch method {
        case .pencil:
            .pencil
        case .finger:
            .finger
        }
    }
}
