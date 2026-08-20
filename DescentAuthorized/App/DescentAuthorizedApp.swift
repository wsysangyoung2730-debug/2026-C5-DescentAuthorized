import SwiftUI

@main
struct DescentAuthorizedApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appSettings = AppSettings()
    @StateObject private var gameCenter: GameCenterManager
    @StateObject private var gameSession: GameSessionStore

    init() {
        let gameCenter = GameCenterManager()
        _gameCenter = StateObject(wrappedValue: gameCenter)
        _gameSession = StateObject(
            wrappedValue: GameSessionStore(achievementReporter: gameCenter)
        )
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(appSettings)
                .environmentObject(gameCenter)
                .environmentObject(gameSession)
                .alert(item: $gameSession.presentedError) { error in
                    Alert(
                        title: Text(error.title),
                        message: Text(error.message),
                        dismissButton: .default(Text("확인"))
                    )
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .inactive || phase == .background else { return }
                    gameSession.saveForLifecycleTransition()
                }
                .task {
                    gameCenter.authenticate()
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
