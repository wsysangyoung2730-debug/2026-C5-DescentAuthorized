import SwiftUI
import UIKit

final class LandscapeAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        .landscape
    }
}

enum LandscapeOrientationController {
    @MainActor
    static func requestLandscape() {
        for case let windowScene as UIWindowScene in UIApplication.shared.connectedScenes {
            applyLandscape(to: windowScene)

            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                applyLandscape(to: windowScene)
            }
        }
    }

    @MainActor
    private static func applyLandscape(to windowScene: UIWindowScene) {
        windowScene.windows.first?.rootViewController?
            .setNeedsUpdateOfSupportedInterfaceOrientations()
        windowScene.requestGeometryUpdate(
            .iOS(interfaceOrientations: .landscapeRight)
        )
    }
}

@main
struct DescentAuthorizedApp: App {
    @UIApplicationDelegateAdaptor(LandscapeAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appSettings = AppSettings()
    @StateObject private var gameCenter: GameCenterManager
    @StateObject private var gameFeedback: GameFeedbackManager
    @StateObject private var gameSession: GameSessionStore

    init() {
        let gameCenter = GameCenterManager()
        let gameFeedback = GameFeedbackManager()
        _gameCenter = StateObject(wrappedValue: gameCenter)
        _gameFeedback = StateObject(wrappedValue: gameFeedback)
        _gameSession = StateObject(
            wrappedValue: GameSessionStore(achievementReporter: gameCenter)
        )
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(appSettings)
                .environmentObject(gameCenter)
                .environmentObject(gameFeedback)
                .environmentObject(gameSession)
                .alert(item: $gameSession.presentedError) { error in
                    Alert(
                        title: Text(error.title),
                        message: Text(error.message),
                        dismissButton: .default(Text("확인"))
                    )
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        LandscapeOrientationController.requestLandscape()
                    } else if phase == .inactive || phase == .background {
                        gameSession.saveForLifecycleTransition()
                    }
                }
                .task {
                    LandscapeOrientationController.requestLandscape()
                    gameCenter.authenticate()
                    gameFeedback.apply(settings: appSettings.settings)
                }
                .onChange(of: gameSession.eventSequence) { _, _ in
                    gameFeedback.consume(
                        gameSession.latestEvents,
                        settings: appSettings.settings
                    )
                }
                .onChange(of: appSettings.settings) { _, settings in
                    gameFeedback.apply(settings: settings)
                }
                .fullScreenCover(item: $gameCenter.authenticationRequest) { request in
                    GameCenterAuthenticationView(viewController: request.viewController)
                        .ignoresSafeArea()
                        .onDisappear {
                            gameCenter.finishAuthenticationPresentation()
                        }
                }
        }
    }
}
