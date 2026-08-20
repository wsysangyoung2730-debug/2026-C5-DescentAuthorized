import SwiftUI

struct HomeView: View {
    @State private var isShowingSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 12) {
                    Text("하강 승인")
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(.white)

                    Text("제0균열")
                        .font(.title2)
                        .foregroundStyle(.purple)

                    Text("DESCENT AUTHORIZED: Rift Zero")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .help("설정")
                    .accessibilityLabel("설정")
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
        }
        .preferredColorScheme(.dark)
    }
}
