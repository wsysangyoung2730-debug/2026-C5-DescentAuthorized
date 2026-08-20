import Foundation
import SwiftUI

@MainActor
final class GameSessionStore: ObservableObject {
    @Published private(set) var session: DemoGameSession
    @Published private(set) var latestEvents: [DemoSessionEvent] = []
    @Published var presentedError: PresentedGameError?

    private var coordinator: GameSessionCoordinator
    private weak var achievementReporter: (any GameAchievementReporting)?
    private let achievementTracker = GameAchievementTracker()

    init(
        saveStore: (any GameSaveStore)? = nil,
        achievementReporter: (any GameAchievementReporting)? = nil
    ) {
        self.achievementReporter = achievementReporter
        let store = saveStore ?? FileGameSaveStore(fileURL: Self.defaultSaveURL)
        do {
            let coordinator = try GameSessionCoordinator(saveStore: store)
            self.coordinator = coordinator
            session = coordinator.session
        } catch {
            let fallback = try! GameSessionCoordinator(
                saveStore: store,
                restoreFromStore: false
            )
            coordinator = fallback
            session = fallback.session
            presentedError = PresentedGameError(
                title: "저장 데이터를 불러오지 못했습니다",
                message: "새 게임 상태로 시작합니다."
            )
        }
        reportAchievementSnapshot()
    }

    var progress: GameProgress { session.progress }
    var battleState: BattleState? { session.battleState }
    var hasSavedProgress: Bool { coordinator.hasSavedProgress }

    @discardableResult
    func send(_ command: DemoCommand) -> [DemoSessionEvent] {
        do {
            let events = try coordinator.execute(command)
            session = coordinator.session
            latestEvents = events
            reportAchievementSnapshot()
            return events
        } catch {
            presentedError = PresentedGameError(
                title: "절차를 진행할 수 없습니다",
                message: Self.message(for: error)
            )
            return []
        }
    }

    func startNewGame() {
        do {
            try coordinator.replaceWithNewGame()
            session = coordinator.session
            latestEvents = []
            reportAchievementSnapshot()
        } catch {
            presentedError = PresentedGameError(
                title: "새 게임을 시작하지 못했습니다",
                message: "저장 공간을 확인한 뒤 다시 시도해 주세요."
            )
        }
    }

    func clearEvents() {
        latestEvents = []
    }

    private func reportAchievementSnapshot() {
        achievementReporter?.submit(achievementTracker.updates(for: session.progress))
    }

    func saveForLifecycleTransition() {
        guard hasSavedProgress else { return }
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
            "현재 장면에서는 해당 절차를 실행할 수 없습니다. (\(progression))"
        case let combat as CombatCommandError:
            "현재 전투 단계에서는 해당 행동을 실행할 수 없습니다. (\(combat))"
        case let session as DemoSessionError:
            "전투 연결 상태를 확인해 주세요. (\(session))"
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
