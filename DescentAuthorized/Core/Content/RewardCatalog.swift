import Foundation

enum RewardCatalog {
    static func candidates(for floor: FloorID) -> [RewardCandidate] {
        candidates(forFloorNumber: floor.rawValue)
    }

    static func candidates(forFloorNumber floor: Int) -> [RewardCandidate] {
        let entries: [(String, SpellID)]
        switch floor {
        case 9: entries = [("barrier", .barrierPiercing), ("chain", .chainInscription), ("condensed", .condensedBarrier)]
        case 8: entries = [("purification", .purificationGlyph), ("lingering", .lingeringBarrier), ("rupture", .focusedRupture)]
        case 7: entries = [("axis", .axisSeverance), ("anchor", .anchorGuard), ("erasure", .consequenceErasure)]
        case 6: entries = [("delay", .executionDelay), ("verdict", .advanceVerdict), ("cushion", .causalCushion)]
        case 5: entries = [("severance", .memorySeverance), ("suture", .memorySuture), ("prohibition", .mimicProhibition)]
        default: entries = []
        }
        return entries.map { key, id in
            let spell = SpellCatalog.spell(id)
            return RewardCandidate(id: "floor\(floor)-\(key)", obscuredName: spell.name,
                category: spell.category, tier: spell.tier, resolvedSpell: id)
        }
    }

    static var allCandidates: [RewardCandidate] { (5...9).flatMap { candidates(forFloorNumber: $0) } }

    static func learningSpell(for candidate: RewardCandidate) -> SpellID {
        precondition(candidate.resolvedSpell != nil, "Every selectable reward must teach a concrete spell")
        return candidate.resolvedSpell!
    }

    static let legacyRewardIDs: [String: String] = [
        "floor9-worn-a": "floor9-barrier", "floor9-worn-b": "floor9-barrier", "floor9-sealed": "floor9-barrier",
        "floor8-engraved": "floor8-lingering", "floor8-sealed": "floor8-purification", "floor8-forbidden": "floor8-rupture"
    ]
}
