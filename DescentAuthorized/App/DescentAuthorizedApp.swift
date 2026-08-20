import SwiftUI

@main
struct DescentAuthorizedApp: App {
    @StateObject private var appSettings = AppSettings()
    @StateObject private var gameSession = GameSessionStore()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(appSettings)
                .environmentObject(gameSession)
                .alert(item: $gameSession.presentedError) { error in
                    Alert(
                        title: Text(error.title),
                        message: Text(error.message),
                        dismissButton: .default(Text("확인"))
                    )
                }
        }
    }
}
