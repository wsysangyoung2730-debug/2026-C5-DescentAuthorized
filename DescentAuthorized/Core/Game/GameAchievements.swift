import Foundation

enum GameAchievementID: String, Codable, CaseIterable, Sendable {
    case firstGlyph = "com.wsysangyoung.DescentAuthorized.achievement.firstGlyph"
    case perfectCast = "com.wsysangyoung.DescentAuthorized.achievement.perfectCast"
    case recordsCleared = "com.wsysangyoung.DescentAuthorized.achievement.recordsCleared"
    case spellArchive = "com.wsysangyoung.DescentAuthorized.achievement.spellArchive"
    case absoluteBarrierDispelled = "com.wsysangyoung.DescentAuthorized.achievement.absoluteBarrierDispelled"
    case observationCleared = "com.wsysangyoung.DescentAuthorized.achievement.observationCleared"
    case descentProcedure = "com.wsysangyoung.DescentAuthorized.achievement.descentProcedure"
    case demoCompleted = "com.wsysangyoung.DescentAuthorized.achievement.demoCompleted"
}

struct GameAchievementUpdate: Codable, Equatable, Sendable {
    let id: GameAchievementID
    let percentComplete: Int

    init(id: GameAchievementID, percentComplete: Int) {
        self.id = id
        self.percentComplete = min(max(percentComplete, 0), 100)
    }
}

struct GameAchievementQueue: Codable, Equatable, Sendable {
    private(set) var percentages: [GameAchievementID: Int] = [:]

    var isEmpty: Bool { percentages.isEmpty }

    var pendingUpdates: [GameAchievementUpdate] {
        percentages
            .map(GameAchievementUpdate.init)
            .sorted { $0.id.rawValue < $1.id.rawValue }
    }

    mutating func merge(_ updates: [GameAchievementUpdate]) {
        for update in updates where update.percentComplete > 0 {
            percentages[update.id] = max(
                percentages[update.id] ?? 0,
                update.percentComplete
            )
        }
    }

    mutating func acknowledge(_ reportedUpdates: [GameAchievementUpdate]) {
        for update in reportedUpdates where percentages[update.id] == update.percentComplete {
            percentages.removeValue(forKey: update.id)
        }
    }
}

struct GameAchievementTracker: Sendable {
    func updates(for progress: GameProgress) -> [GameAchievementUpdate] {
        let updates = [
            binary(
                .firstGlyph,
                earned: !progress.completedTrainingSpells.isEmpty
            ),
            binary(
                .perfectCast,
                earned: progress.spellMastery.values.contains { $0.bestGrade == .perfect }
            ),
            binary(
                .recordsCleared,
                earned: progress.defeatedEnemies.contains(.recordsAdministrator)
            ),
            GameAchievementUpdate(
                id: .spellArchive,
                percentComplete: progress.learnedSpells.count * 100 / SpellID.allCases.count
            ),
            binary(
                .absoluteBarrierDispelled,
                earned: (progress.spellMastery[.sealRelease]?.successfulCasts ?? 0) > 0
            ),
            binary(
                .observationCleared,
                earned: progress.defeatedEnemies.contains(.observationAdministrator)
            ),
            GameAchievementUpdate(
                id: .descentProcedure,
                percentComplete: descentProgress(for: progress)
            ),
            binary(.demoCompleted, earned: progress.isDemoComplete)
        ]
        return updates.filter { $0.percentComplete > 0 }
    }

    private func binary(
        _ id: GameAchievementID,
        earned: Bool
    ) -> GameAchievementUpdate {
        GameAchievementUpdate(id: id, percentComplete: earned ? 100 : 0)
    }

    private func descentProgress(for progress: GameProgress) -> Int {
        switch progress.currentFloor {
        case .floor10: 0
        case .floor9: 34
        case .floor8: 67
        case .floor7: 100
        }
    }
}
