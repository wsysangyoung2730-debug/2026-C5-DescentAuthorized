import Foundation

enum RewardCatalog {
    static func candidates(for floor: FloorID) -> [RewardCandidate] {
        switch floor {
        case .floor9:
            floor9Candidates
        case .floor8:
            floor8Candidates
        case .floor10, .floor7:
            []
        }
    }

    static func learningSpell(for candidate: RewardCandidate) -> SpellID {
        if let resolvedSpell = candidate.resolvedSpell {
            return resolvedSpell
        }

        switch candidate.category {
        case .attack:
            return .riftSeverance
        case .defense:
            return .basicBarrier
        case .dispel:
            return .sealRelease
        }
    }

    private static let floor9Candidates = [
        RewardCandidate(
            id: "floor9-worn-a",
            obscuredName: "방벽...",
            category: .attack,
            tier: .worn,
            resolvedSpell: .barrierPiercing
        ),
        RewardCandidate(
            id: "floor9-worn-b",
            obscuredName: "...관통",
            category: .attack,
            tier: .worn,
            resolvedSpell: .barrierPiercing
        ),
        RewardCandidate(
            id: "floor9-sealed",
            obscuredName: "승인 불가",
            category: .attack,
            tier: .sealed,
            resolvedSpell: .barrierPiercing
        )
    ]

    private static let floor8Candidates = [
        RewardCandidate(
            id: "floor8-engraved",
            obscuredName: "관측...",
            category: .defense,
            tier: .engraved,
            resolvedSpell: nil
        ),
        RewardCandidate(
            id: "floor8-sealed",
            obscuredName: "...격리",
            category: .dispel,
            tier: .sealed,
            resolvedSpell: nil
        ),
        RewardCandidate(
            id: "floor8-forbidden",
            obscuredName: "열람 금지",
            category: .attack,
            tier: .forbidden,
            resolvedSpell: nil
        )
    ]
}
