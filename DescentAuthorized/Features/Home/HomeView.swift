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

                VStack(spacing: 18) {
                    Spacer()

                    if gameSession.hasSavedProgress {
                        homeButton("하강 절차 계속", prominence: .primary) {
                            isPlaying = true
                        }

                        homeButton("처음부터", prominence: .secondary) {
                            gameSession.startNewGame()
                            isPlaying = true
                        }
                    } else {
                        homeButton("하강 절차 시작", prominence: .primary) {
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
        _ title: String,
        prominence: DescentMenuButtonStyle.Prominence,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 19, weight: .semibold, design: .serif))
                .tracking(0.8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(DescentMenuButtonStyle(prominence: prominence))
        .frame(width: 300, height: 64)
    }
}

private struct DescentMenuButtonStyle: ButtonStyle {
    enum Prominence: Equatable {
        case primary
        case secondary
    }

    let prominence: Prominence

    private var surfaceColors: [Color] {
        switch prominence {
        case .primary:
            [Color(red: 0.04, green: 0.04, blue: 0.045), Color(red: 0.10, green: 0.085, blue: 0.075)]
        case .secondary:
            [Color(red: 0.20, green: 0.19, blue: 0.18), Color(red: 0.13, green: 0.125, blue: 0.12)]
        }
    }

    private var foregroundColor: Color {
        prominence == .primary
            ? Color(red: 0.93, green: 0.81, blue: 0.58)
            : Color(red: 0.84, green: 0.76, blue: 0.62)
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foregroundColor)
            .background {
                DescentButtonShape(cut: 12)
                    .fill(
                        LinearGradient(
                            colors: surfaceColors,
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay {
                        DescentButtonShape(cut: 12)
                            .stroke(
                                Color(red: 0.78, green: 0.61, blue: 0.34),
                                lineWidth: 2
                            )
                    }
                    .overlay {
                        DescentButtonShape(cut: 9)
                            .stroke(
                                Color(red: 0.93, green: 0.78, blue: 0.50).opacity(0.74),
                                lineWidth: 0.8
                            )
                            .padding(5)
                    }
                    .overlay(alignment: .top) {
                        DescentButtonDiamond()
                            .offset(y: -5)
                    }
                    .overlay(alignment: .bottom) {
                        DescentButtonDiamond()
                            .offset(y: 5)
                    }
                    .shadow(
                        color: Color.purple.opacity(prominence == .primary ? 0.25 : 0.12),
                        radius: 8
                    )
            }
            .contentShape(DescentButtonShape(cut: 12))
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .brightness(configuration.isPressed ? 0.08 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct DescentButtonShape: Shape {
    let cut: CGFloat

    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX + cut, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cut))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cut))
            path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + cut, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - cut))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cut))
            path.closeSubpath()
        }
    }
}

private struct DescentButtonDiamond: View {
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color.purple, Color(red: 0.34, green: 0.12, blue: 0.58)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 10, height: 10)
            .rotationEffect(.degrees(45))
            .overlay {
                Rectangle()
                    .stroke(Color(red: 0.91, green: 0.73, blue: 0.42), lineWidth: 1)
                    .rotationEffect(.degrees(45))
            }
            .shadow(color: .purple.opacity(0.7), radius: 5)
    }
}
