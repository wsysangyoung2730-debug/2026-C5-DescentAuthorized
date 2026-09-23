#if DEBUG
import Foundation

/// Isolated simulator preview; never reads or writes the player's persistent save.
enum ExpansionPreviewSupport {
    static var floor: Int? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--preview-floor"), args.indices.contains(index + 1),
              let floor = Int(args[index + 1]), (1...7).contains(floor) else { return nil }
        return floor
    }
    static var loadoutFloor: Int? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--preview-loadout-floor"), args.indices.contains(index + 1),
              let floor = Int(args[index + 1]), (8...9).contains(floor) else { return nil }
        return floor
    }

    static var isBattle: Bool { ProcessInfo.processInfo.arguments.contains("--preview-battle") }
    static var isBoss: Bool { ProcessInfo.processInfo.arguments.contains("--preview-boss") }
    static func makeStore() -> (any GameSaveStore)? {
        if let loadoutFloor {
            var seed = GameProgress.newGame
            seed.furthestCheckpoint = .observationBattle
            var controller = GameProgressionController(progress: seed)
            do {
                _ = try controller.travel(to: loadoutFloor == 9 ? .recordsBattle : (isBoss ? .observationBattle : .residualBattle))
                return InMemoryGameSaveStore(progress: controller.progress)
            } catch { return nil }
        }
        guard let floor else { return nil }
        if floor <= 4 { return makeLowerFloorStore(floor: floor) }
        var seed = GameProgress.newGame
        seed.furthestCheckpoint = .demoComplete
        var controller = GameProgressionController(progress: seed)
        do {
            _ = try controller.travel(to: .demoComplete)
            if floor <= 6 {
                _ = try controller.learnExpansionSpell(.axisSeverance)
                _ = try controller.learnExpansionSpell(.outputReduction)
            }
            if floor <= 5 { _ = try controller.learnExpansionSpell(.executionDelay) }
            let args = ProcessInfo.processInfo.arguments
            var stage: ExpansionStage = isBoss ? .bossPreparation : .preparation
            if let index = args.firstIndex(of: "--preview-stage"), args.indices.contains(index + 1),
               let requested = ExpansionStage(rawValue: args[index + 1]),
               !requested.isBattle, requested != .complete { stage = requested }
            var approvals = 0
            if stage == .descent, let index = args.firstIndex(of: "--preview-approvals"), args.indices.contains(index + 1) {
                approvals = min(2, max(0, Int(args[index + 1]) ?? 0))
            }
            try controller.updateExpansion(.init(floorNumber: floor, stage: stage, descentStage: approvals))
            return InMemoryGameSaveStore(progress: controller.progress)
        } catch { return nil }
    }

    private static func makeLowerFloorStore(floor: Int) -> (any GameSaveStore)? {
        let args = ProcessInfo.processInfo.arguments
        func value(_ flag: String) -> String? {
            guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
            return args[index + 1]
        }
        let requested = value("--preview-stage").flatMap(ExpansionStage.init(rawValue:))
        let stage = requested ?? (isBoss ? .bossPreparation : .preparation)
        let residualIndex = min(1, max(0, Int(value("--preview-residual") ?? "0") ?? 0))
        let approvals = min(3, max(0, Int(value("--preview-approvals") ?? "0") ?? 0))
        let current = ExpansionProgress(floorNumber: floor, stage: stage,
            descentStage: stage == .complete ? 3 : approvals,
            residualIndex: [.recordReward, .sealedDoor].contains(stage) ? 1 : residualIndex)
        guard current.isValid else { return nil }
        var seed = GameProgress.newGame
        seed.furthestCheckpoint = .towerHandoffComplete
        var controller = GameProgressionController(progress: seed)
        do {
            _ = try controller.travel(to: current.lowerFloorCheckpoint)
            try controller.updateExpansion(current)
            var progress = controller.progress
            if args.contains("--preview-all-spells") {
                progress.learnedSpells = Set(SpellID.allCases)
                progress.completedTrainingSpells = Set(SpellID.allCases)
            }
            return InMemoryGameSaveStore(progress: progress)
        } catch { return nil }
    }
}
#endif
