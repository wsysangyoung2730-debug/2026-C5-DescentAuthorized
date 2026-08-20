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

struct GameAchievementLedger: Codable, Equatable, Sendable {
    private(set) var desiredPercentages: [GameAchievementID: Int] = [:]
    private(set) var reportedPercentages: [String: [GameAchievementID: Int]] = [:]

    mutating func merge(_ updates: [GameAchievementUpdate]) {
        for update in updates where update.percentComplete > 0 {
            desiredPercentages[update.id] = max(
                desiredPercentages[update.id] ?? 0,
                update.percentComplete
            )
        }
    }

    func updatesToReport(for playerID: String) -> [GameAchievementUpdate] {
        let playerReports = reportedPercentages[playerID] ?? [:]
        return desiredPercentages
            .compactMap { id, desiredPercentage in
                guard desiredPercentage > (playerReports[id] ?? 0) else { return nil }
                return GameAchievementUpdate(
                    id: id,
                    percentComplete: desiredPercentage
                )
            }
            .sorted { $0.id.rawValue < $1.id.rawValue }
    }

    mutating func acknowledge(
        _ reportedUpdates: [GameAchievementUpdate],
        for playerID: String
    ) {
        var playerReports = reportedPercentages[playerID] ?? [:]
        for update in reportedUpdates {
            playerReports[update.id] = max(
                playerReports[update.id] ?? 0,
                update.percentComplete
            )
        }
        reportedPercentages[playerID] = playerReports
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
