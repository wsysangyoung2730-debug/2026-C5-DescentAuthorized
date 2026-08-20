import SwiftUI

@main
struct DescentAuthorizedApp: App {
    @StateObject private var appSettings = AppSettings()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(appSettings)
        }
    }
}
