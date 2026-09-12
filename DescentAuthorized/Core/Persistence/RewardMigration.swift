import Foundation

extension GameProgress {
    /// Maps #96's placeholder scrolls once, retaining the reward the player chose.
    mutating func migrateLegacyRewards(fromVersion version: Int) {
        guard version < 5 else { return }
        selectedRewardIDs = selectedRewardIDs.map { RewardCatalog.legacyRewardIDs[$0] ?? $0 }
        for floor in [9, 8] {
            guard let reward = RewardCatalog.candidates(forFloorNumber: floor).first(where: {
                selectedRewardIDs.contains($0.id)
            }) else { continue }
            let passedLesson = currentFloor.rawValue < floor
                || (floor == 9 && currentScene == .floor9DescentDoor)
                || (floor == 8 && currentScene == .floor8DescentDoor)
            if passedLesson {
                let spell = RewardCatalog.learningSpell(for: reward)
                learnedSpells.insert(spell)
                completedTrainingSpells.insert(spell)
            }
        }
        synchronizeLoadout()
    }
}
