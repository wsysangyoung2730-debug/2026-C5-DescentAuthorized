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

    static var allCandidates: [RewardCandidate] {
        (5...9).flatMap { candidates(forFloorNumber: $0) }
        + ExpansionRewardSite.allCases.flatMap { site in SpellID.allCases.map { candidate($0, at: site) } }
    }

    /// Pure, deterministic generation. The controller persists this result on first entry.
    static func candidates(for site: ExpansionRewardSite, learned: Set<SpellID>) -> [RewardCandidate] {
        let originals = Array(SpellID.allCases.prefix(20))
        let sealed: [SpellID] = [.responsibilitySeverance, .isolationBarrier, .pressureRelease, .handoffBarrier]
        let preferred: (SpellID, SpellID, SpellCategory?) = switch site {
        case .floor4Record: (.bloodSealPiercing, .responsibilitySeverance, .defense)
        case .floor4Boss: (.limitBarrier, .isolationBarrier, .dispel)
        case .floor3Record: (.executionNullification, .pressureRelease, .defense)
        case .floor3Boss: (.directHitProhibition, .handoffBarrier, .attack)
        case .floor2Boss: (.mimicProhibition, .responsibilitySeverance, nil)
        }
        var selected: [SpellID] = []
        func available(_ id: SpellID) -> Bool { !learned.contains(id) && !selected.contains(id) }
        func oldNormal(_ priority: SpellCategory?) -> SpellID? {
            var roles: [SpellCategory] = []
            if let priority { roles.append(priority) }
            for role in [SpellCategory.dispel, .defense, .attack, .debuff] where !roles.contains(role) { roles.append(role) }
            return roles.lazy.compactMap { role in
                originals.first { available($0) && SpellCatalog.spell($0).tier != .forbidden && SpellCatalog.spell($0).category == role }
            }.first
        }
        let forbiddenPriority: [SpellID] = site == .floor2Boss
            ? [.mimicProhibition, .executionNullification, .limitBarrier, .directHitProhibition, .bloodSealPiercing]
            : [preferred.0]
        if let id = forbiddenPriority.first(where: available) ?? oldNormal(nil) { selected.append(id) }
        let sealedPriority = site == .floor2Boss ? sealed + originals.filter { SpellCatalog.spell($0).tier == .sealed } : [preferred.1]
        if let id = sealedPriority.first(where: available) ?? oldNormal(nil) { selected.append(id) }
        let learnedDispels = learned.filter { SpellCatalog.spell($0).category == .dispel && SpellCatalog.spell($0).tier != .forbidden }
        if let id = oldNormal(learnedDispels == [.sealRelease] ? .dispel : preferred.2) { selected.append(id) }
        for id in sealed + originals where selected.count < 3 && available(id) && SpellCatalog.spell(id).tier != .forbidden {
            selected.append(id)
        }
        return selected.map { candidate($0, at: site) }
    }

    static func candidate(_ id: SpellID, at site: ExpansionRewardSite) -> RewardCandidate {
        let spell = SpellCatalog.spell(id)
        return RewardCandidate(id: "\(site.rawValue)-\(id.rawValue)", obscuredName: spell.name,
                               category: spell.category, tier: spell.tier, resolvedSpell: id)
    }

    static func learningSpell(for candidate: RewardCandidate) -> SpellID {
        precondition(candidate.resolvedSpell != nil, "Every selectable reward must teach a concrete spell")
        return candidate.resolvedSpell!
    }

    static let legacyRewardIDs: [String: String] = [
        "floor9-worn-a": "floor9-barrier", "floor9-worn-b": "floor9-barrier", "floor9-sealed": "floor9-barrier",
        "floor8-engraved": "floor8-lingering", "floor8-sealed": "floor8-purification", "floor8-forbidden": "floor8-rupture"
    ]
}
