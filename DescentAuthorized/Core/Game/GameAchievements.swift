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
    /// Version 1 used demo-ending and single-run collection rules.
    private static let currentRulesVersion = 2
    private var rulesVersion = currentRulesVersion
    private(set) var desiredPercentages: [GameAchievementID: Int] = [:]
    private(set) var reportedPercentages: [String: [GameAchievementID: Int]] = [:]
    private(set) var lifetimeLearnedSpells: Set<SpellID> = []

    init() {}

    private enum CodingKeys: String, CodingKey {
        case rulesVersion, desiredPercentages, reportedPercentages, lifetimeLearnedSpells
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let previousVersion = try values.decodeIfPresent(Int.self, forKey: .rulesVersion) ?? 1
        desiredPercentages = try values.decodeIfPresent(
            [GameAchievementID: Int].self, forKey: .desiredPercentages
        ) ?? [:]
        reportedPercentages = try values.decodeIfPresent(
            [String: [GameAchievementID: Int]].self, forKey: .reportedPercentages
        ) ?? [:]
        lifetimeLearnedSpells = try values.decodeIfPresent(
            Set<SpellID>.self, forKey: .lifetimeLearnedSpells
        ) ?? []
        if previousVersion < Self.currentRulesVersion {
            // Rebuild these from the saved game, not stale demo percentages queued offline.
            // Successful server reports stay recorded: Game Center cannot reduce them.
            for id in [GameAchievementID.spellArchive, .descentProcedure, .demoCompleted] {
                desiredPercentages.removeValue(forKey: id)
            }
        }
        rulesVersion = Self.currentRulesVersion
    }

    mutating func merge(
        _ updates: [GameAchievementUpdate],
        learnedSpells: Set<SpellID> = []
    ) {
        lifetimeLearnedSpells.formUnion(learnedSpells)
        // The archive is a collection across runs; a percentage cannot identify duplicates.
        for update in updates where update.percentComplete > 0 && update.id != .spellArchive {
            desiredPercentages[update.id] = max(
                desiredPercentages[update.id] ?? 0,
                update.percentComplete
            )
        }
        if !lifetimeLearnedSpells.isEmpty {
            desiredPercentages[.spellArchive] = lifetimeLearnedSpells.count * 100 / SpellID.allCases.count
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
    func updates(
        for progress: GameProgress,
        events: [DemoSessionEvent] = []
    ) -> [GameAchievementUpdate] {
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
            binary(
                .absoluteBarrierDispelled,
                earned: containsSuccessfulAbsoluteBarrierDispel(in: events)
            ),
            binary(
                .observationCleared,
                earned: progress.defeatedEnemies.contains(.observationAdministrator)
            ),
            GameAchievementUpdate(
                id: .descentProcedure,
                percentComplete: descentProgress(for: progress)
            ),
            // The old stored isDemoComplete flag marks the handoff from 8F to 7F.
            binary(.demoCompleted, earned: progress.expansion?.isComplete == true)
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
        let floor = min(10, max(1, progress.displayedFloorNumber))
        return (10 - floor) * 100 / 9
    }

    private func containsSuccessfulAbsoluteBarrierDispel(
        in events: [DemoSessionEvent]
    ) -> Bool {
        var resolvedSealRelease = false
        for event in events {
            guard case let .combat(battleEvent) = event else { continue }
            switch battleEvent {
            case .spellResolved(spell: .sealRelease, grade: _):
                resolvedSealRelease = true
            case .absoluteBarrierChanged(target: .enemy(_), charges: _):
                if resolvedSealRelease { return true }
            default:
                break
            }
        }
        return false
    }
}
