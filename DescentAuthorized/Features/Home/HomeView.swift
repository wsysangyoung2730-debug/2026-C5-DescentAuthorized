import SwiftUI
import UIKit

struct HomeView: View {
    @EnvironmentObject private var gameSession: GameSessionStore

    @State private var isShowingSettings = false
    @State private var isPlaying = false
    @State private var isPreparingStartup = false
    @State private var isStartupReady = false
    @State private var startupProgress = 0.0
    @State private var startupTip = LoadingTipCatalog.randomTip(for: .startup)

    var body: some View {
        ZStack {
            if isStartupReady {
                NavigationStack {
                    if isPlaying {
                        DemoFlowView(onExit: { isPlaying = false })
                    } else {
                        homeContent
                    }
                }
                .transition(.opacity)
            } else {
                LoadingScreenView(
                    context: .startup,
                    progress: startupProgress,
                    tip: startupTip
                )
                .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await prepareStartupAssets()
        }
    }

    @MainActor
    private func prepareStartupAssets() async {
        guard !isPreparingStartup else { return }
        isPreparingStartup = true

        let imageNames = [
            "LoadingMain",
            "LoadingFloor10",
            "LoadingFloor09",
            "LoadingFloor08"
        ]
        for (index, imageName) in imageNames.enumerated() {
            autoreleasepool {
                let image = UIImage(named: imageName)
                _ = image?.cgImage?.dataProvider?.data
            }
            let completed = Double(index + 1) / Double(imageNames.count)
            withAnimation(.linear(duration: 0.16)) {
                startupProgress = completed * 0.92
            }
            try? await Task.sleep(for: .milliseconds(90))
        }

        withAnimation(.linear(duration: 0.16)) {
            startupProgress = 1
        }
        try? await Task.sleep(for: .milliseconds(160))
        withAnimation(.easeOut(duration: 0.2)) {
            isStartupReady = true
        }
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
