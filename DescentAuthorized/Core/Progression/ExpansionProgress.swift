import Foundation

/// Explicit progression for the playable extension, independent of legacy 10–8F scenes.
enum ExpansionStage: String, Codable, CaseIterable, Sendable {
    case entrance
    case preparation
    case residualEncounter
    case residualBattle
    case residualDefeated
    case residualInvestigation
    case recordReward
    case sealedDoor
    case bossPreparation
    case bossEncounter
    case bossBattle
    case bossDefeated
    case reward
    case finalRecord
    case descent
    case complete
    case learnDebuff

    var isEncounter: Bool { self == .residualEncounter || self == .bossEncounter }

    var isBattle: Bool { self == .residualBattle || self == .bossBattle }
}

struct ExpansionProgress: Codable, Equatable, Sendable {
    var floorNumber: Int
    var stage: ExpansionStage
    /// Completed independent approvals: 0...2 on 7–5F, 0...3 on 4–1F.
    var descentStage: Int
    /// Zero-based residual encounter. A and B resume independently.
    var residualIndex: Int

    init(floorNumber: Int = 7, stage: ExpansionStage = .entrance, descentStage: Int = 0, residualIndex: Int = 0) {
        self.floorNumber = floorNumber
        self.stage = stage
        self.descentStage = descentStage
        self.residualIndex = residualIndex
    }

    private enum CodingKeys: String, CodingKey { case floorNumber, stage, descentStage, residualIndex }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        floorNumber = try values.decode(Int.self, forKey: .floorNumber)
        stage = try values.decode(ExpansionStage.self, forKey: .stage)
        descentStage = try values.decodeIfPresent(Int.self, forKey: .descentStage) ?? 0
        residualIndex = try values.decodeIfPresent(Int.self, forKey: .residualIndex) ?? 0
        // Version 6 ended at the 4F entrance; this was not the game's ending.
        if floorNumber == 4 && stage == .complete {
            stage = .entrance
            descentStage = 0
        }
    }

    var isComplete: Bool { floorNumber == 1 && stage == .complete }

    /// Battles resume at preparation; completed approval stage one survives relaunch.
    var resumableStage: ExpansionStage {
        switch stage {
        case .residualEncounter, .residualBattle: .preparation
        case .bossEncounter, .bossBattle: .bossPreparation
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
    case tooManyForbiddenSpells
    case duplicateSpell
    case unlearnedSpell(SpellID)
    case missingSealRelease
    case missingAttack
    case missingDefense

    var message: String {
        switch self {
        case .tooManySpells: "주문은 최대 6개까지 준비할 수 있습니다."
        case .tooManyForbiddenSpells: "금서는 출전 6칸 중 최대 2종입니다. 기존 금서를 직접 교체하세요."
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
    static let maximumForbidden = 2

    static func forbiddenCount(_ spells: [SpellID]) -> Int {
        spells.filter { SpellCatalog.spell($0).tier == .forbidden }.count
    }

    static func canAutomaticallyEquip(_ id: SpellID, alongside spells: [SpellID]) -> Bool {
        spells.count < maximumEquipped && (SpellCatalog.spell(id).tier != .forbidden || forbiddenCount(spells) < maximumForbidden)
    }

    static func learnedProtectionCategories(in learned: Set<SpellID>) -> [SpellCategory] {
        [.attack, .defense].filter { role in
            learned.contains { category(of: $0) == role }
        }
    }

    static func protectionSummary(for learned: Set<SpellID>) -> String {
        var roles = learnedProtectionCategories(in: learned).map { $0 == .attack ? "공격 주문 하나" : "방어 주문 하나" }
        if learned.contains(.sealRelease) { roles.append("봉인 해제") }
        return roles.isEmpty ? "주문을 배우면 봉인 보호 상태를 확인할 수 있습니다."
            : roles.joined(separator: ", ") + "는 자동으로 봉인에서 보호됩니다."
    }

    static func defaultSpells(from learned: Set<SpellID>) -> [SpellID] {
        normalized(SpellID.allCases.filter(learned.contains), learned: learned)
    }

    /// Before the 8F lesson, only categories already learned are required.
    static func issues(for equipped: [SpellID], learned: Set<SpellID>) -> [LoadoutValidationIssue] {
        var issues: [LoadoutValidationIssue] = []
        if equipped.count > maximumEquipped { issues.append(.tooManySpells) }
        if forbiddenCount(equipped) > maximumForbidden { issues.append(.tooManyForbiddenSpells) }
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
        while forbiddenCount(result) > maximumForbidden {
            guard let index = result.lastIndex(where: { SpellCatalog.spell($0).tier == .forbidden && !required.contains($0) }) else { break }
            result.remove(at: index)
        }
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
                if LoadoutRules.canAutomaticallyEquip(id, alongside: ordered) { ordered.append(id) }
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
        case 4: "책임 심사실"
        case 3: "자발 격리구역"
        case 2: "봉인 유지기관"
        case 1: "최종 승인청"
        default: "다음 하강 구역"
        }
    }
    var showsBoss: Bool {
        [.bossPreparation, .bossEncounter, .bossBattle, .bossDefeated, .reward, .finalRecord, .descent, .complete].contains(stage)
    }
}

extension GameProgress {
    var displayedFloorNumber: Int { expansion?.floorNumber ?? currentFloor.rawValue }
}

/// A single route drives room and camera selection, including restored progress.
struct ExpansionSceneRoute: Equatable, Sendable {
    enum Camera: String, Sendable { case battle, rewardSelection, descentInput }
    let floorNumber: Int
    enum Room: String, Sendable { case residualA, residualB, administrator }
    let room: Room
    var isBoss: Bool { room == .administrator }
    let camera: Camera

    init?(_ progress: ExpansionProgress) {
        guard (1...7).contains(progress.floorNumber), progress.stage != .complete else { return nil }
        floorNumber = progress.floorNumber
        room = progress.showsBoss ? .administrator
            : (progress.isLowerFloor && progress.residualIndex == 1 ? .residualB : .residualA)
        switch progress.stage {
        case .sealedDoor, .descent: camera = .descentInput
        case .reward, .finalRecord: camera = .rewardSelection
        default: camera = .battle
        }
    }
}

// MARK: - Replayable checkpoints

extension CheckpointID {
    /// Legacy demoComplete is retained as the stable saved ID for the 7F investigation.
    var expansionDestination: ExpansionProgress? {
        switch self {
        case .demoComplete: .init(floorNumber: 7, stage: .entrance)
        case .floor7Encounter: .init(floorNumber: 7, stage: .preparation)
        case .floor7SealedDoor: .init(floorNumber: 7, stage: .sealedDoor)
        case .floor7BossEncounter: .init(floorNumber: 7, stage: .bossPreparation)
        case .floor7Reward: .init(floorNumber: 7, stage: .reward)
        case .floor7Descent: .init(floorNumber: 7, stage: .descent)
        case .floor6Investigation: .init(floorNumber: 6, stage: .entrance)
        case .floor6Learning: .init(floorNumber: 6, stage: .learnDebuff)
        case .floor6Encounter: .init(floorNumber: 6, stage: .preparation)
        case .floor6SealedDoor: .init(floorNumber: 6, stage: .sealedDoor)
        case .floor6BossEncounter: .init(floorNumber: 6, stage: .bossPreparation)
        case .floor6Reward: .init(floorNumber: 6, stage: .reward)
        case .floor6Descent: .init(floorNumber: 6, stage: .descent)
        case .floor5Investigation: .init(floorNumber: 5, stage: .entrance)
        case .floor5Encounter: .init(floorNumber: 5, stage: .preparation)
        case .floor5SealedDoor: .init(floorNumber: 5, stage: .sealedDoor)
        case .floor5BossEncounter: .init(floorNumber: 5, stage: .bossPreparation)
        case .floor5Reward: .init(floorNumber: 5, stage: .reward)
        case .floor5Descent: .init(floorNumber: 5, stage: .descent)
        case .floor5Complete: .init(floorNumber: 4, stage: .entrance)
        default: lowerFloorDestination
        }
    }
}

extension ExpansionProgress {
    var replayCheckpoint: CheckpointID {
        if isComplete { return .towerHandoffComplete }
        if isLowerFloor { return lowerFloorCheckpoint }
        let checkpoints: [CheckpointID] = switch floorNumber {
        case 7: [.demoComplete, .floor7Encounter, .floor7SealedDoor, .floor7BossEncounter, .floor7Reward, .floor7Descent]
        case 6: [.floor6Investigation, .floor6Encounter, .floor6SealedDoor, .floor6BossEncounter, .floor6Reward, .floor6Descent]
        default: [.floor5Investigation, .floor5Encounter, .floor5SealedDoor, .floor5BossEncounter, .floor5Reward, .floor5Descent]
        }
        switch stage {
        case .entrance: return checkpoints[0]
        case .learnDebuff: return .floor6Learning
        case .preparation, .residualEncounter, .residualBattle: return checkpoints[1]
        case .residualDefeated, .sealedDoor: return checkpoints[2]
        case .residualInvestigation: return checkpoints[1]
        case .bossPreparation, .bossEncounter, .bossBattle: return checkpoints[3]
        case .bossDefeated, .reward, .recordReward, .finalRecord: return checkpoints[4]
        case .descent, .complete: return checkpoints[5]
        }
    }
}

extension GameProgress {
    mutating func rememberCheckpointRewards() {
        for floor in 5...9 {
            if let choice = RewardCatalog.candidates(forFloorNumber: floor).first(where: {
                selectedRewardIDs.contains($0.id)
            }) { checkpointRewardChoices[floor] = choice.id }
        }
    }

    /// Older saves used the 8F completion ID throughout the extension.
    mutating func migrateExpansionCheckpoint() {
        guard currentScene == .demoComplete, isDemoComplete, let expansion else { return }
        var current = expansion.replayCheckpoint
        if expansion.stage == .entrance,
           ExpansionInvestigationCatalog.isComplete(floor: expansion.floorNumber, readRecordIDs: readRecordIDs) {
            current = ExpansionProgress(floorNumber: expansion.floorNumber,
                stage: expansion.floorNumber == 6 && !learnedSpells.contains(.outputReduction)
                    ? .learnDebuff : .preparation).replayCheckpoint
        }
        checkpoint = current
        if current.progressionIndex > furthestCheckpoint.progressionIndex { furthestCheckpoint = current }
    }
}
