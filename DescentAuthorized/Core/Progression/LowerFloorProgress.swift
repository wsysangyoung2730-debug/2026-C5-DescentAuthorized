import Foundation

extension ExpansionProgress {
    var isValid: Bool {
        guard (1...7).contains(floorNumber), (0...requiredDescentStages).contains(descentStage),
              (0..<requiredResidualCount).contains(residualIndex),
              stage != .learnDebuff || floorNumber == 6,
              stage != .complete || (floorNumber == 1 && descentStage == 3),
              stage != .finalRecord || floorNumber == 1,
              stage != .recordReward || ([3,4].contains(floorNumber) && residualIndex == 1),
              stage != .residualInvestigation || (isLowerFloor && residualIndex == 0) else { return false }
        return true
    }

    var lowerFloorCheckpoint: CheckpointID {
        if isComplete { return .towerHandoffComplete }
        let suffix: String = switch stage {
        case .entrance: "Investigation"
        case .preparation, .residualEncounter, .residualBattle: residualIndex == 0 ? "Encounter" : "SecondEncounter"
        case .residualInvestigation: "SecondEncounter"
        case .residualDefeated: residualIndex == 0 ? "SecondEncounter" : ([3,4].contains(floorNumber) ? "RecordReward" : "SealedDoor")
        case .sealedDoor: "SealedDoor"
        case .recordReward: "RecordReward"
        case .bossPreparation, .bossEncounter, .bossBattle: "BossEncounter"
        case .bossDefeated, .reward, .finalRecord: floorNumber == 1 ? "FinalRecord" : "Reward"
        case .descent, .complete: "Descent"
        case .learnDebuff: "Encounter"
        }
        if floorNumber == 4 && suffix == "Investigation" { return .floor5Complete }
        return CheckpointID(rawValue: "floor\(floorNumber)\(suffix)")!
    }
}

extension CheckpointID {
    var lowerFloorDestination: ExpansionProgress? {
        if self == .towerHandoffComplete { return .init(floorNumber: 1, stage: .complete, descentStage: 3, residualIndex: 1) }
        guard rawValue.hasPrefix("floor"), let floor = Int(rawValue.dropFirst(5).prefix(1)), (1...4).contains(floor) else { return nil }
        let suffix = String(rawValue.dropFirst(6))
        let stage: ExpansionStage
        switch suffix {
        case "Investigation": stage = .entrance
        case "Encounter", "SecondEncounter": stage = .preparation
        case "RecordReward": stage = .recordReward
        case "SealedDoor": stage = .sealedDoor
        case "BossEncounter": stage = .bossPreparation
        case "Reward": stage = .reward
        case "FinalRecord": stage = .finalRecord
        case "Descent": stage = .descent
        default: return nil
        }
        return .init(floorNumber: floor, stage: stage, residualIndex: ["Investigation", "Encounter"].contains(suffix) ? 0 : 1)
    }
}

extension GameProgress {
    var currentRewardCandidates: [RewardCandidate] {
        if let site = expansion?.rewardSite { return lowerRewardOffers[site.rawValue] ?? [] }
        return RewardCatalog.candidates(forFloorNumber: displayedFloorNumber)
    }

    mutating func ensureLowerRewardOffer() {
        guard let site = expansion?.rewardSite, lowerRewardOffers[site.rawValue] == nil else { return }
        lowerRewardOffers[site.rawValue] = RewardCatalog.candidates(for: site, learned: learnedSpells)
    }

    /// Rebuild the durable milestones of a replay checkpoint, never an in-progress battle.
    mutating func restoreLowerMilestones(to destination: ExpansionProgress) {
        completedLowerRewardSites = []
        for floor in stride(from: 4, through: destination.floorNumber, by: -1) {
            let completed = floor > destination.floorNumber || destination.isComplete
            let same = floor == destination.floorNumber
            let bossReached = completed || (same && destination.showsBoss)
            for index in 0...1 {
                let residualComplete = completed || (same && (destination.residualIndex > index || bossReached ||
                    (destination.residualIndex == index && [.recordReward, .sealedDoor].contains(destination.stage))))
                if residualComplete, let enemy = ExpansionEnemyCatalog.enemy(floor: floor, isBoss: false, residualIndex: index) { defeatedEnemies.insert(enemy.id) }
            }
            if completed || (same && [.reward,.finalRecord,.descent].contains(destination.stage)),
               let boss = ExpansionEnemyCatalog.enemy(floor: floor, isBoss: true) { defeatedEnemies.insert(boss.id) }
            for site in ExpansionRewardSite.allCases where site.floorNumber == floor {
                let earned = completed || (same && (site.isRecord
                    ? bossReached || destination.stage == .sealedDoor
                    : destination.stage == .descent))
                guard earned else { continue }
                let offers = lowerRewardOffers[site.rawValue] ?? RewardCatalog.candidates(for: site, learned: learnedSpells)
                lowerRewardOffers[site.rawValue] = offers
                let choice = offers.first { $0.id == lowerRewardChoices[site.rawValue] } ?? offers.first
                if let choice, let spell = choice.resolvedSpell {
                    lowerRewardChoices[site.rawValue] = choice.id
                    selectedRewardIDs.append(choice.id)
                    learnedSpells.insert(spell)
                    completedTrainingSpells.insert(spell)
                }
                completedLowerRewardSites.insert(site.rawValue)
            }
        }
        ensureLowerRewardOffer()
    }
}
