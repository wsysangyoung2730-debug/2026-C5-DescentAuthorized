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
        GeometryReader { proxy in
            let menuButtonWidth = min(max(proxy.size.width * 0.25, 300), 350)

            ZStack {
                Image("HomeMainBackground")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.12), .black.opacity(0.42)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                VStack(spacing: 12) {
                    Spacer()

                    if gameSession.hasSavedProgress {
                        homeButton(
                            assetName: "HomeDescentContinueButton",
                            accessibilityLabel: "하강 절차 계속",
                            width: menuButtonWidth
                        ) {
                            isPlaying = true
                        }

                        homeButton(
                            assetName: "HomeRestartButton",
                            accessibilityLabel: "처음부터",
                            width: menuButtonWidth
                        ) {
                            gameSession.startNewGame()
                            isPlaying = true
                        }
                    } else {
                        homeButton(
                            assetName: "HomeDescentStartButton",
                            accessibilityLabel: "하강 절차 시작",
                            width: menuButtonWidth
                        ) {
                            gameSession.startNewGame()
                            isPlaying = true
                        }
                    }

                    Spacer()
                        .frame(height: max(proxy.size.height * 0.11, 58))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .ignoresSafeArea()
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

    private func homeButton(
        assetName: String,
        accessibilityLabel: String,
        width: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(HomeMenuAssetButtonStyle())
        .frame(width: width, height: width / 3)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct HomeMenuAssetButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .brightness(configuration.isPressed ? -0.08 : 0)
            .saturation(configuration.isPressed ? 1.12 : 1)
            .offset(y: configuration.isPressed ? 2 : 0)
            .shadow(
                color: Color.purple.opacity(configuration.isPressed ? 0.18 : 0.32),
                radius: configuration.isPressed ? 5 : 10
            )
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
