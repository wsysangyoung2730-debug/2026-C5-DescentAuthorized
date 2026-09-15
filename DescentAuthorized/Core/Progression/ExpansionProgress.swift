import Foundation

/// Explicit progression for the playable extension, independent of legacy 10–8F scenes.
enum ExpansionStage: String, Codable, CaseIterable, Sendable {
    case entrance
    case preparation
    case residualBattle
    case residualDefeated
    case sealedDoor
    case bossPreparation
    case bossBattle
    case bossDefeated
    case reward
    case descent
    case complete
    case learnDebuff

    var isBattle: Bool { self == .residualBattle || self == .bossBattle }
}

struct ExpansionProgress: Codable, Equatable, Sendable {
    var floorNumber: Int
    var stage: ExpansionStage
    /// Completed approvals at this floor's descent door: 0, 1, or 2.
    var descentStage: Int

    init(floorNumber: Int = 7, stage: ExpansionStage = .entrance, descentStage: Int = 0) {
        self.floorNumber = floorNumber
        self.stage = stage
        self.descentStage = descentStage
    }

    var isComplete: Bool { floorNumber == 4 && stage == .complete }

    /// Battles resume at preparation; completed approval stage one survives relaunch.
    var resumableStage: ExpansionStage {
        switch stage {
        case .residualBattle: .preparation
        case .bossBattle: .bossPreparation
        default: stage
        }
    }
}

enum LoadoutTutorialFlag: String, Codable, Hashable, Sendable {
    case firstSixLoadout
    case firstOverflowLoadout
    case statusEffects
    case scheduledDamage
    case reservationCounter
    case reservationResult
    case memoryRecord
    case cardSeal
}

enum LoadoutValidationIssue: Equatable, Sendable {
    case tooManySpells
    case duplicateSpell
    case unlearnedSpell(SpellID)
    case missingSealRelease
    case missingAttack
    case missingDefense

    var message: String {
        switch self {
        case .tooManySpells: "주문은 최대 6개까지 준비할 수 있습니다."
        case .duplicateSpell: "같은 주문을 두 번 준비할 수 없습니다."
        case .unlearnedSpell: "아직 배우지 않은 주문입니다."
        case .missingSealRelease: "봉인 해제를 준비해 주세요."
        case .missingAttack: "공격 주문을 하나 이상 준비해 주세요."
        case .missingDefense: "방어 주문을 하나 이상 준비해 주세요."
        }
    }
}

enum LoadoutRules {
    static let maximumEquipped = 6

    static func defaultSpells(from learned: Set<SpellID>) -> [SpellID] {
        normalized(SpellID.allCases.filter(learned.contains), learned: learned)
    }

    /// Before the 8F lesson, only categories already learned are required.
    static func issues(for equipped: [SpellID], learned: Set<SpellID>) -> [LoadoutValidationIssue] {
        var issues: [LoadoutValidationIssue] = []
        if equipped.count > maximumEquipped { issues.append(.tooManySpells) }
        if Set(equipped).count != equipped.count { issues.append(.duplicateSpell) }
        for id in equipped where !learned.contains(id) { issues.append(.unlearnedSpell(id)) }
        if learned.contains(.sealRelease), !equipped.contains(.sealRelease) {
            issues.append(.missingSealRelease)
        }
        if learned.contains(where: { category(of: $0) == .attack }),
           !equipped.contains(where: { category(of: $0) == .attack }) {
            issues.append(.missingAttack)
        }
        if learned.contains(where: { category(of: $0) == .defense }),
           !equipped.contains(where: { category(of: $0) == .defense }) {
            issues.append(.missingDefense)
        }
        return issues
    }

    /// Repairs migrated or stale loadouts without replacing the player's valid choices.
    static func normalized(_ equipped: [SpellID], learned: Set<SpellID>) -> [SpellID] {
        var seen = Set<SpellID>()
        var result = equipped.filter { learned.contains($0) && seen.insert($0).inserted }
        let learnedOrder = SpellID.allCases.filter(learned.contains)
        var required: [SpellID] = []
        if learned.contains(.sealRelease) { required.append(.sealRelease) }
        for category in [SpellCategory.attack, .defense] {
            if let selected = result.first(where: { Self.category(of: $0) == category })
                ?? learnedOrder.first(where: { Self.category(of: $0) == category }) {
                required.append(selected)
            }
        }
        // Remove only optional entries when a newly learned requirement needs a slot.
        for id in required where !result.contains(id) { result.append(id) }
        while result.count > maximumEquipped {
            guard let index = result.lastIndex(where: { !required.contains($0) }) else { break }
            result.remove(at: index)
        }
        return result
    }

    static func protectedSpell(
        preferred: SpellID?, category: SpellCategory, equipped: [SpellID]
    ) -> SpellID? {
        if let preferred, equipped.contains(preferred), Self.category(of: preferred) == category {
            return preferred
        }
        return equipped.first { Self.category(of: $0) == category }
    }

    private static func category(of id: SpellID) -> SpellCategory? {
        SpellCatalog.all[id]?.category
    }
}

extension GameProgress {
    var protectedSpells: Set<SpellID> {
        var result = Set([protectedAttack, protectedDefense].compactMap { $0 })
        if equippedSpells.contains(.sealRelease) { result.insert(.sealRelease) }
        return result.intersection(equippedSpells)
    }

    var loadoutIssues: [LoadoutValidationIssue] {
        LoadoutRules.issues(for: equippedSpells, learned: learnedSpells)
    }

    /// Call after learning or replaying a checkpoint. Player-chosen ordering is retained.
    mutating func synchronizeLoadout(automaticallyEquipNewSpells: Bool = false) {
        var ordered = equippedSpells
        if automaticallyEquipNewSpells {
            for id in SpellID.allCases where learnedSpells.contains(id) && !ordered.contains(id) {
                if ordered.count < LoadoutRules.maximumEquipped { ordered.append(id) }
            }
        }
        equippedSpells = LoadoutRules.normalized(ordered, learned: learnedSpells)
        protectedAttack = LoadoutRules.protectedSpell(
            preferred: protectedAttack, category: .attack, equipped: equippedSpells
        )
        protectedDefense = LoadoutRules.protectedSpell(
            preferred: protectedDefense, category: .defense, equipped: equippedSpells
        )
    }

    /// Returns false without changing the saved loadout when a required role is missing.
    @discardableResult
    mutating func setLoadout(
        _ spells: [SpellID], protectedAttack: SpellID? = nil, protectedDefense: SpellID? = nil
    ) -> Bool {
        guard LoadoutRules.issues(for: spells, learned: learnedSpells).isEmpty else { return false }
        equippedSpells = spells
        self.protectedAttack = LoadoutRules.protectedSpell(
            preferred: protectedAttack ?? self.protectedAttack, category: .attack, equipped: spells
        )
        self.protectedDefense = LoadoutRules.protectedSpell(
            preferred: protectedDefense ?? self.protectedDefense, category: .defense, equipped: spells
        )
        return true
    }
}

extension ExpansionProgress {
    var areaName: String {
        switch floorNumber {
        case 7: "좌표 교정 구역"
        case 6: "인과 검증 구역"
        case 5: "기억 원본 보관 구역"
        default: "다음 하강 구역"
        }
    }
    var showsBoss: Bool {
        [.bossPreparation, .bossBattle, .bossDefeated, .reward, .descent].contains(stage)
    }
}

extension GameProgress {
    var displayedFloorNumber: Int { expansion?.floorNumber ?? currentFloor.rawValue }
}
