import SwiftUI
import UIKit

struct HomeView: View {
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var gameFeedback: GameFeedbackManager
    @EnvironmentObject private var gameSession: GameSessionStore

    @State private var isShowingSettings = false
    @State private var isPlaying = false
    @State private var isConfirmingNewGame = false
    @State private var isShowingGameSystemOverlay = false
    @State private var isPreparingStartup = false
    @State private var isStartupReady = false
    @State private var startupProgress = 0.0
    @State private var lastPlayableSize = CGSize(width: 1024, height: 768)
    @State private var startupTip = LoadingTipCatalog.randomTip(for: .startup)

    var body: some View {
        GeometryReader { viewport in
            let playable = viewport.size.width >= 900 && viewport.size.height >= 600
                && viewport.size.width > viewport.size.height
            let gameSize = playable ? viewport.size : lastPlayableSize

            ZStack {
                if isStartupReady {
                    NavigationStack {
                        ZStack {
                            if isPlaying {
                                // Keep the same game subtree and layout while its window is
                                // unsuitable, so rotation never resets a battle or dialogue.
                                DemoFlowView(
                                    isViewportBlocked: !playable,
                                    onExit: returnToTitle,
                                    onSystemOverlayVisibilityChange: { isPresented in
                                        isShowingGameSystemOverlay = isPresented
                                    }
                                )
                                .frame(width: gameSize.width, height: gameSize.height)
                                .opacity(playable ? 1 : 0)
                                .allowsHitTesting(playable)
                                .accessibilityHidden(!playable)
                            } else {
                                homeContent
                            }

                            if isPlaying && !playable {
                                viewportGuidance(isPortrait: viewport.size.height >= viewport.size.width)
                            }
                        }
                        .frame(width: viewport.size.width, height: viewport.size.height)
                        .clipped()
                        .toolbar(isPlaying && !playable ? .hidden : .automatic, for: .navigationBar)
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
            .frame(width: viewport.size.width, height: viewport.size.height)
            .onChange(of: viewport.size, initial: true) { _, size in
                if playable { lastPlayableSize = size }
            }
            .preferredColorScheme(.dark)
            .gameStatusBarHidden(isPlaying && playable && !isShowingGameSystemOverlay)
        }
        .fullScreenCover(isPresented: $isShowingSettings) { SettingsView() }
        .task { await prepareStartupAssets() }
    }

    private func returnToTitle() {
        isShowingGameSystemOverlay = false
        isPlaying = false
    }

    private func viewportGuidance(isPortrait: Bool) -> some View {
        ZStack {
            Color(red: 0.025, green: 0.028, blue: 0.035)
                .ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: isPortrait ? "ipad.landscape" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 42, weight: .light))
                        .foregroundStyle(DAColor.gold)
                        .accessibilityHidden(true)
                    Text(isPortrait ? "가로 화면으로 전환해 주세요" : "게임 창을 조금 더 넓혀 주세요")
                        .font(.title2.weight(.medium))
                        .foregroundStyle(DAColor.gold)
                        .accessibilityAddTraits(.isHeader)
                    Text(isPortrait
                        ? "iPad를 가로로 돌리거나 창을 가로로 넓히면 이어서 진행합니다."
                        : "전체 화면 또는 넓은 가로 창에서 이어서 진행할 수 있습니다.")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.8))
                    Text("현재 진행은 잠시 멈춰 있습니다.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.6))
                    Button("타이틀로", action: returnToTitle)
                    .buttonStyle(.bordered)
                    .tint(DAColor.gold)
                    .padding(.top, 8)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
                .padding(28)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.center)
        }
        .accessibilityIdentifier("game.viewportGuidance")
    }

    @MainActor
    private func prepareStartupAssets() async {
        guard !isPreparingStartup else { return }
        isPreparingStartup = true

        let imageNames = [
            "LoadingMain",
            "LoadingFloor10",
            "LoadingFloor09",
            "LoadingFloor08",
            "LoadingFloor07",
            "LoadingFloor06",
            "LoadingFloor05",
            "LoadingFloor04",
            "LoadingFloor03",
            "LoadingFloor02",
            "LoadingFloor01"
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
        #if DEBUG
        if ExpansionPreviewSupport.floor != nil || ExpansionPreviewSupport.loadoutFloor != nil {
            isPlaying = true
            if let floor = ExpansionPreviewSupport.bossEncounterFloor {
                // The isolated preview follows the same prepared encounter commands as play.
                // Do not start combat here: the dialogue and camera sweep must finish first.
                switch floor {
                case 9: gameSession.send(.enterRecordsEncounter)
                case 8: gameSession.send(.enterAdministratorEncounter)
                case 1...4: gameSession.send(.beginPreparedLowerBattle)
                default: gameSession.send(.advanceExpansion)
                }
            } else if let floor = ExpansionPreviewSupport.floor, floor <= 4,
               ProcessInfo.processInfo.arguments.contains("--preview-direct-battle") {
                // In-memory preview only: use the real preparation/encounter transitions.
                gameSession.send(.beginPreparedLowerBattle)
                gameSession.send(.advanceExpansion)
                if ProcessInfo.processInfo.arguments.contains("--preview-sealed-card"),
                   let battle = gameSession.battleState, battle.expansion.needsSealChoice,
                   let candidate = battle.expansion.pendingSealChoices.first {
                    // Resolve an actual choice and enemy action in the isolated preview save.
                    gameSession.send(.chooseCardSeal(candidate))
                    gameSession.send(.finishTurn)
                }
            } else if ExpansionPreviewSupport.loadoutFloor == 8, ExpansionPreviewSupport.isBoss,
                      ProcessInfo.processInfo.arguments.contains("--barrier-guide-diagnostics") {
                gameSession.send(.enterAdministratorEncounter)
                gameSession.send(.beginAdministratorBattle)
            } else if ExpansionPreviewSupport.floor != nil && ExpansionPreviewSupport.isBattle {
                gameSession.send(.advanceExpansion)
            }
        }
        #endif
        withAnimation(.easeOut(duration: 0.2)) {
            isStartupReady = true
        }
    }

    private var homeContent: some View {
        GeometryReader { proxy in
            let menuButtonWidth = min(max(proxy.size.width * 0.23, 240), 325, max(1, proxy.size.width - 32))

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
                            gameFeedback.playInterface(.confirm, settings: appSettings.settings)
                            isPlaying = true
                        }

                        homeButton(
                            assetName: "HomeRestartButton",
                            accessibilityLabel: "처음부터",
                            width: menuButtonWidth
                        ) {
                            requestNewGame()
                        }
                    } else {
                        homeButton(
                            assetName: "HomeDescentStartButton",
                            accessibilityLabel: "하강 절차 시작",
                            width: menuButtonWidth
                        ) {
                            requestNewGame()
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
                    gameFeedback.playInterface(.select, settings: appSettings.settings)
                    isShowingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("설정")
                .accessibilityLabel("설정")
            }
        }
        .confirmationDialog("처음부터 시작할까요?", isPresented: $isConfirmingNewGame,
                            titleVisibility: .visible) {
            Button("기존 진행을 지우고 시작", role: .destructive) {
                beginNewGame(replacingSavedProgress: true)
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("기존 게임 진행과 습득 주문이 초기화되며 되돌릴 수 없습니다. 불러오지 못해 보관 중인 저장도 삭제됩니다. 설정과 Game Center 업적은 유지됩니다.")
        }
    }

    private func requestNewGame() {
        if gameSession.requiresNewGameConfirmation {
            isConfirmingNewGame = true
        } else {
            beginNewGame()
        }
    }

    private func beginNewGame(replacingSavedProgress: Bool = false) {
        if gameSession.startNewGame(replacingSavedProgress: replacingSavedProgress) {
            gameFeedback.playInterface(.confirm, settings: appSettings.settings)
            isPlaying = true
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

private extension View {
    func gameStatusBarHidden(_ hidden: Bool) -> some View {
        statusBarHidden(hidden)
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
