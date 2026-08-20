import Foundation
import GameKit
import UIKit

@MainActor
protocol GameAchievementReporting: AnyObject {
    func submit(_ updates: [GameAchievementUpdate])
}

enum GameCenterAuthenticationState: Equatable {
    case notStarted
    case authenticating
    case authenticated(displayName: String)
    case unavailable
}

struct GameCenterAuthenticationRequest: Identifiable {
    let id = UUID()
    let viewController: UIViewController
}

@MainActor
final class GameCenterManager: ObservableObject, GameAchievementReporting {
    @Published private(set) var authenticationState: GameCenterAuthenticationState = .notStarted
    @Published private(set) var lastSyncError: String?
    @Published var authenticationRequest: GameCenterAuthenticationRequest?

    private let defaults: UserDefaults
    private let queueKey: String
    private var queue: GameAchievementQueue
    private var isReporting = false
    private var didInstallAuthenticationHandler = false

    init(
        defaults: UserDefaults = .standard,
        queueKey: String = "game-center.pending-achievements.v1"
    ) {
        self.defaults = defaults
        self.queueKey = queueKey
        if let data = defaults.data(forKey: queueKey),
           let restoredQueue = try? JSONDecoder().decode(
               GameAchievementQueue.self,
               from: data
           ) {
            queue = restoredQueue
        } else {
            queue = GameAchievementQueue()
        }
    }

    var isAuthenticated: Bool {
        if case .authenticated = authenticationState { return true }
        return false
    }

    var statusTitle: String {
        switch authenticationState {
        case .notStarted:
            "연결 대기"
        case .authenticating:
            "로그인 확인 중"
        case let .authenticated(displayName):
            displayName
        case .unavailable:
            "사용할 수 없음"
        }
    }

    func authenticate(force: Bool = false) {
        if didInstallAuthenticationHandler && !force {
            flushPendingAchievements()
            return
        }

        didInstallAuthenticationHandler = true
        authenticationState = .authenticating
        lastSyncError = nil

        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            Task { @MainActor in
                self?.handleAuthentication(
                    viewController: viewController,
                    error: error
                )
            }
        }
    }

    func submit(_ updates: [GameAchievementUpdate]) {
        queue.merge(updates)
        persistQueue()
        flushPendingAchievements()
    }

    func finishAuthenticationPresentation() {
        authenticationRequest = nil
        if GKLocalPlayer.local.isAuthenticated {
            markAuthenticated()
        }
    }

    private func handleAuthentication(
        viewController: UIViewController?,
        error: Error?
    ) {
        if let viewController {
            authenticationState = .authenticating
            authenticationRequest = GameCenterAuthenticationRequest(
                viewController: viewController
            )
            return
        }

        authenticationRequest = nil
        if GKLocalPlayer.local.isAuthenticated {
            markAuthenticated()
        } else {
            authenticationState = .unavailable
            lastSyncError = error?.localizedDescription
        }
    }

    private func markAuthenticated() {
        authenticationState = .authenticated(
            displayName: GKLocalPlayer.local.displayName
        )
        lastSyncError = nil
        flushPendingAchievements()
    }

    private func flushPendingAchievements() {
        guard GKLocalPlayer.local.isAuthenticated,
              !isReporting,
              !queue.isEmpty else {
            return
        }

        let updates = queue.pendingUpdates
        let achievements = updates.map { update in
            let achievement = GKAchievement(identifier: update.id.rawValue)
            achievement.percentComplete = Double(update.percentComplete)
            achievement.showsCompletionBanner = update.percentComplete == 100
            return achievement
        }

        isReporting = true
        GKAchievement.report(achievements) { [weak self] error in
            Task { @MainActor in
                self?.finishReporting(updates: updates, error: error)
            }
        }
    }

    private func finishReporting(
        updates: [GameAchievementUpdate],
        error: Error?
    ) {
        isReporting = false
        if let error {
            lastSyncError = error.localizedDescription
            return
        }

        queue.acknowledge(updates)
        persistQueue()
        lastSyncError = nil
        flushPendingAchievements()
    }

    private func persistQueue() {
        guard let data = try? JSONEncoder().encode(queue) else { return }
        defaults.set(data, forKey: queueKey)
    }
}
