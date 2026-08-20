import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var gameSession: GameSessionStore

    @State private var isShowingSettings = false
    @State private var isPlaying = false

    var body: some View {
        NavigationStack {
            if isPlaying {
                DemoFlowView(onExit: { isPlaying = false })
            } else {
                homeContent
            }
        }
        .preferredColorScheme(.dark)
    }

    private var homeContent: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 12) {
                Spacer()
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

                Spacer()

                VStack(spacing: 10) {
                    if gameSession.hasSavedProgress {
                        Button("하강 절차 계속") {
                            isPlaying = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                        .frame(width: 260)
                    }

                    if gameSession.hasSavedProgress {
                        Button("처음부터") {
                            gameSession.startNewGame()
                            isPlaying = true
                        }
                        .buttonStyle(.bordered)
                        .tint(.purple)
                        .frame(width: 260)
                    } else {
                        Button("하강 절차 시작") {
                            gameSession.startNewGame()
                            isPlaying = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                        .frame(width: 260)
                    }
                }
                .controlSize(.large)

                Spacer()
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
}
