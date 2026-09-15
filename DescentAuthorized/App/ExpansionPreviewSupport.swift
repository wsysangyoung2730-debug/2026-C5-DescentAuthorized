#if DEBUG
import Foundation

/// Isolated simulator preview; never reads or writes the player's persistent save.
enum ExpansionPreviewSupport {
    static var floor: Int? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--preview-floor"), args.indices.contains(index + 1),
              let floor = Int(args[index + 1]), (5...7).contains(floor) else { return nil }
        return floor
    }
    static var isBattle: Bool { ProcessInfo.processInfo.arguments.contains("--preview-battle") }
    static var isBoss: Bool { ProcessInfo.processInfo.arguments.contains("--preview-boss") }
    static func makeStore() -> (any GameSaveStore)? {
        guard let floor else { return nil }
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
            try controller.updateExpansion(.init(floorNumber: floor, stage: isBoss ? .bossPreparation : .preparation))
            return InMemoryGameSaveStore(progress: controller.progress)
        } catch { return nil }
    }
}
#endif
