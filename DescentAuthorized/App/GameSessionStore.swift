import Foundation
import SwiftUI

@MainActor
final class GameSessionStore: ObservableObject {
    @Published private(set) var session: DemoGameSession
    @Published private(set) var latestEvents: [DemoSessionEvent] = []
    /// Full command context for guides, independent of one-shot audiovisual stages.
    @Published private(set) var latestCommandEvents: [DemoSessionEvent] = []
    @Published private(set) var eventSequence: UInt64 = 0
    @Published private(set) var isCombatPresentationActive = false
    @Published var presentedError: PresentedGameError?

    private struct CombatSnapshot {
        let progress: GameProgress
        var battle: BattleState
    }

    @Published private var combatSnapshot: CombatSnapshot?
    private var combatPresentationTask: Task<Void, Never>?
    private var combatPresentationGeneration: UInt64 = 0
    private var combatPresentationSuspended = false
    private var pendingCombatSteps: [CombatPresentationTimeline.Step] = []
    private var finalCombatState: BattleState?
    private var nextCombatStepDelay: TimeInterval = 0
    private var combatStepStartedAt: ContinuousClock.Instant?

    private var coordinator: GameSessionCoordinator
    private let persistentSaveStore: any GameSaveStore
    /// A failed restore must never allow fallback autosaves to replace the original file.
    private var isRecoverySession = false
    private weak var achievementReporter: (any GameAchievementReporting)?
    private let achievementTracker = GameAchievementTracker()

    init(
        saveStore: (any GameSaveStore)? = nil,
        achievementReporter: (any GameAchievementReporting)? = nil
    ) {
        self.achievementReporter = achievementReporter
        let store = saveStore ?? FileGameSaveStore(fileURL: Self.defaultSaveURL)
        persistentSaveStore = store
        do {
            let coordinator = try GameSessionCoordinator(saveStore: store)
            self.coordinator = coordinator
            session = coordinator.session
        } catch {
            let fallback = try! GameSessionCoordinator(
                saveStore: InMemoryGameSaveStore(),
                restoreFromStore: false
            )
            coordinator = fallback
            session = fallback.session
            isRecoverySession = true
            presentedError = PresentedGameError(
                title: "저장 데이터를 불러오지 못했습니다",
                message: "기존 저장 데이터는 그대로 보관했습니다. 현재 임시 진행은 저장되지 않습니다. 새 게임을 시작하면 기존 진행이 초기화됩니다."
            )
        }
        reportAchievementSnapshot()
    }

    var progress: GameProgress { combatSnapshot?.progress ?? session.progress }
    var battleState: BattleState? { combatSnapshot?.battle ?? session.battleState }
    var hasSavedProgress: Bool { coordinator.hasSavedProgress }
    var presentation: DemoScenePresentation {
        .presentation(for: progress.currentScene, expansion: progress.expansion)
    }

    @discardableResult
    func send(_ command: DemoCommand) -> [DemoSessionEvent] {
        if isCombatPresentationActive {
            switch command {
            case .castSpell, .finishTurn: return []
            default: cancelCombatPresentation()
            }
        }
        let previousProgress = progress
        let previousBattle = battleState
        do {
            let events = try coordinator.execute(command)
            latestCommandEvents = events
            session = coordinator.session
            presentedError = nil
            reportAchievementSnapshot(events: events)
            let steps = CombatPresentationTimeline.steps(for: events)
            if let previousBattle,
               let finalBattle = session.battleState ?? session.lastCompletedBattleState,
               !steps.isEmpty {
                beginCombatPresentation(steps, progress: previousProgress,
                                        previousBattle: previousBattle, finalBattle: finalBattle)
            } else {
                publish(events)
            }
            return events
        } catch {
            presentedError = PresentedGameError(
                title: "절차를 진행할 수 없습니다",
                message: Self.message(for: error)
            )
            return []
        }
    }

    /// Commands returning no events (for example, saving a loadout) can still succeed.
    /// Observe the existing dispatch result without running the command a second time.
    @discardableResult
    func sendChecked(_ command: DemoCommand) -> Bool {
        let previousSequence = eventSequence
        send(command)
        return eventSequence != previousSequence
    }

    @discardableResult
    func startNewGame() -> Bool {
        cancelCombatPresentation()
        do {
            if isRecoverySession {
                var replacement = try GameSessionCoordinator(
                    saveStore: persistentSaveStore,
                    restoreFromStore: false
                )
                try replacement.replaceWithNewGame()
                coordinator = replacement
                isRecoverySession = false
            } else {
                try coordinator.replaceWithNewGame()
            }
            session = coordinator.session
            latestEvents = []
            latestCommandEvents = []
            eventSequence &+= 1
            presentedError = nil
            reportAchievementSnapshot()
            return true
        } catch {
            presentedError = PresentedGameError(
                title: "새 게임을 시작하지 못했습니다",
                message: "저장 공간을 확인한 뒤 다시 시도해 주세요."
            )
            return false
        }
    }

    func clearEvents() {
        cancelCombatPresentation()
        latestEvents = []
        latestCommandEvents = []
        eventSequence &+= 1
    }

    /// Pause the presentation clock along with actor motion, including app backgrounding.
    func setCombatPresentationSuspended(_ suspended: Bool) {
        guard combatPresentationSuspended != suspended else { return }
        combatPresentationSuspended = suspended
        if suspended {
            combatPresentationGeneration &+= 1
            if let started = combatStepStartedAt {
                let elapsed = started.duration(to: ContinuousClock.now).components
                let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
                nextCombatStepDelay = max(0, nextCombatStepDelay - seconds)
            }
            combatPresentationTask?.cancel()
            combatPresentationTask = nil
            combatStepStartedAt = nil
        } else {
            scheduleCombatStep()
        }
    }

    /// Navigation and retry discard stale visual work; the coordinator is already current.
    func cancelCombatPresentation() {
        combatPresentationGeneration &+= 1
        combatPresentationTask?.cancel()
        combatPresentationTask = nil
        combatStepStartedAt = nil
        pendingCombatSteps = []
        finalCombatState = nil
        combatSnapshot = nil
        nextCombatStepDelay = 0
        isCombatPresentationActive = false
    }

    private func beginCombatPresentation(
        _ steps: [CombatPresentationTimeline.Step],
        progress: GameProgress,
        previousBattle: BattleState,
        finalBattle: BattleState
    ) {
        cancelCombatPresentation()
        combatSnapshot = CombatSnapshot(progress: progress, battle: previousBattle)
        finalCombatState = finalBattle
        pendingCombatSteps = steps
        isCombatPresentationActive = true
        // The launch/windup event must reach observers in the command's own update.
        presentCombatStep(pendingCombatSteps.removeFirst())
        nextCombatStepDelay = pendingCombatSteps.first?.delay ?? 0
        scheduleCombatStep()
    }

    private func scheduleCombatStep() {
        guard isCombatPresentationActive, !combatPresentationSuspended,
              combatPresentationTask == nil, !pendingCombatSteps.isEmpty else { return }
        let generation = combatPresentationGeneration
        let delay = nextCombatStepDelay
        combatStepStartedAt = ContinuousClock.now
        combatPresentationTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) }
            catch { return }
            guard let self, self.combatPresentationGeneration == generation,
                  !self.combatPresentationSuspended else { return }
            self.combatPresentationTask = nil
            self.combatStepStartedAt = nil
            guard !self.pendingCombatSteps.isEmpty else { return }
            self.presentCombatStep(self.pendingCombatSteps.removeFirst())
            self.nextCombatStepDelay = self.pendingCombatSteps.first?.delay ?? 0
            self.scheduleCombatStep()
        }
    }

    private func presentCombatStep(_ step: CombatPresentationTimeline.Step) {
        guard var snapshot = combatSnapshot, let finalCombatState else { return }
        snapshot.battle = CombatPresentationTimeline.applying(
            step, to: snapshot.battle, finalState: finalCombatState
        )
        if step.kind == .recovery || step.kind == .victoryRelease {
            combatSnapshot = nil
            self.finalCombatState = nil
            isCombatPresentationActive = false
        } else {
            combatSnapshot = snapshot
        }
        publish(step.events)
    }

    private func publish(_ events: [DemoSessionEvent]) {
        latestEvents = events
        eventSequence &+= 1
    }

    private func reportAchievementSnapshot(events: [DemoSessionEvent] = []) {
        achievementReporter?.submit(
            achievementTracker.updates(for: session.progress, events: events)
        )
    }

    func saveForLifecycleTransition() {
        guard !isRecoverySession, hasSavedProgress else { return }
        do {
            try coordinator.saveCurrentProgress()
        } catch {
            presentedError = PresentedGameError(
                title: "진행 상황을 저장하지 못했습니다",
                message: "앱으로 돌아온 뒤 저장 공간을 확인해 주세요."
            )
        }
    }

    private static var defaultSaveURL: URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("DescentAuthorized", isDirectory: true)
            .appendingPathComponent("progress.json")
    }

    private static func message(for error: Error) -> String {
        switch error {
        case let progression as ProgressionError:
            switch progression {
            case .invalidScene:
                "현재 안내된 절차를 먼저 완료해 주세요."
            case let .unexpectedSpell(spell):
                "지금은 \(SpellCatalog.spell(spell).name)을 사용할 수 없습니다. 안내된 주문을 선택해 주세요."
            case .unexpectedEnemy:
                "현재 전투 대상과 맞지 않습니다. 전투 준비 화면에서 다시 진입해 주세요."
            case .unknownReward:
                "현재 층에서 선택할 수 없는 두루마리입니다. 보상 목록을 다시 확인해 주세요."
            case .rewardAlreadySelected:
                "이 층의 보상은 이미 선택했습니다. 선택한 두루마리의 학습을 진행해 주세요."
            case let .requirementMissing(requirement):
                requirement.unicodeScalars.contains(where: { (0xAC00...0xD7A3).contains($0.value) })
                    ? requirement
                    : "먼저 현재 안내된 학습·전투·보상 절차를 완료해 주세요."
            }
        case let combat as CombatCommandError:
            switch combat {
            case let .spellUnavailable(reason):
                reason
            case .invalidEffectTarget:
                "선택한 효과 대상이 바뀌었거나 사라졌습니다. 현재 목록에서 대상을 다시 선택해 주세요."
            case let .spellNotLearned(spell):
                "아직 \(SpellCatalog.spell(spell).name)을 배우지 않았습니다. 가방에서 배운 주문을 선택해 주세요."
            case let .insufficientStrokes(required, remaining):
                "이 주문에는 \(required)획이 필요합니다. 이번 턴에 남은 획은 \(remaining)획입니다."
            case let .invalidStrokeSubmission(required, _):
                "문양의 획수를 확인해 주세요. 이 주문은 \(required)획을 순서대로 그려야 합니다."
            case .invalidPhase:
                "지금은 주문을 사용할 수 없습니다. 내 차례가 시작되면 다시 시도해 주세요."
            case .missingEnemyIntent:
                "적의 다음 행동을 준비하고 있습니다. 잠시 후 다시 시도해 주세요."
            case .battleAlreadyFinished:
                "이미 끝난 전투입니다. 결과 화면에서 다음 절차를 진행해 주세요."
            }
        case let session as DemoSessionError:
            switch session {
            case .encounterAlreadyActive:
                "이미 전투가 진행 중입니다. 현재 전투를 계속해 주세요."
            case .noActiveEncounter:
                "아직 시작한 전투가 없습니다. 출전 준비를 마친 뒤 전투에 진입해 주세요."
            case .encounterNotDefeated:
                "패배 후에 사용할 수 있는 재도전 절차입니다. 현재 전투를 계속해 주세요."
            case .noEncounterForScene:
                "현재 위치에서는 전투를 시작할 수 없습니다. 화면의 진행 버튼을 확인해 주세요."
            }
        default:
            "저장 상태를 확인한 뒤 다시 시도해 주세요."
        }
    }
}

struct PresentedGameError: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String

    static func == (lhs: PresentedGameError, rhs: PresentedGameError) -> Bool {
        lhs.title == rhs.title && lhs.message == rhs.message
    }
}
