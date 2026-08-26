import SwiftUI

struct DemoFlowView: View {
    @EnvironmentObject private var gameSession: GameSessionStore

    let onExit: () -> Void

    @State private var isShowingPauseMenu = false
    @State private var isShowingSettings = false
    @StateObject private var sceneController = RealitySceneController()

    private let topBarHeight: CGFloat = 58

    var body: some View {
        ZStack(alignment: .top) {
            if let floorSceneID = gameSession.presentation.floorSceneID {
                RealityStageView(
                    sceneID: floorSceneID,
                    cameraPreset: gameSession.presentation.cameraPreset,
                    erasureZones: gameSession.battleState?.activeErasureZones ?? [],
                    controller: sceneController
                )
            } else {
                Color.black.ignoresSafeArea()
            }

            if isPresentationReady {
                VStack(spacing: 0) {
                    topBar
                        .frame(height: topBarHeight)
                        .clipped()

                    sceneView
                        .id(gameSession.presentation.progressSceneID)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            Color.black
                .opacity(sceneController.cameraFadeOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.18), value: sceneController.cameraFadeOpacity)
        }
        .sheet(isPresented: $isShowingPauseMenu) {
            PauseMenuView(onExitToTitle: onExit)
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
        .onChange(of: gameSession.presentation.floorSceneID) { _, floorSceneID in
            if floorSceneID == nil {
                sceneController.unload()
            }
        }
    }

    private var isPresentationReady: Bool {
        guard let floorSceneID = gameSession.presentation.floorSceneID else { return true }
        return sceneController.isReady(
            sceneID: floorSceneID,
            cameraPreset: gameSession.presentation.cameraPreset
        )
    }

    private var topBar: some View {
        ZStack {
            DAColor.background.opacity(0.96)

            GeometryReader { proxy in
                Image("SharedTopHUDRail")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .opacity(0.9)
                    .allowsHitTesting(false)
            }

            HStack(spacing: 18) {
                topBarButton(systemImage: "pause.fill") {
                    isShowingPauseMenu = true
                }
                .help("일시정지")
                .accessibilityLabel("일시정지")

                Spacer(minLength: 20)

                HStack(spacing: 11) {
                    floorOrnament

                    Text("제\(gameSession.progress.currentFloor.rawValue)층")
                        .font(.system(size: 19, weight: .medium, design: .serif))
                        .foregroundStyle(SharedHUDPalette.title)
                        .shadow(color: SharedHUDPalette.brass.opacity(0.34), radius: 4)

                    floorOrnament
                        .scaleEffect(x: -1, y: 1)
                }

                Spacer(minLength: 20)

                topBarButton(systemImage: "gearshape") {
                    isShowingSettings = true
                }
                .help("설정")
                .accessibilityLabel("설정")
            }
            .padding(.horizontal, 16)
        }
        .frame(height: topBarHeight)
        .clipped()
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SharedHUDPalette.brass.opacity(0.45))
                .frame(height: 1)
        }
    }

    private var floorOrnament: some View {
        Image("SharedFloorOrnament")
            .resizable()
            .scaledToFill()
            .frame(width: 76, height: 20)
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func topBarButton(
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Image("SharedHUDIconPlate")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 44)
                    .clipped()

                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(SharedHUDPalette.icon)
            }
            .frame(width: 48, height: 44)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var sceneView: some View {
        switch gameSession.presentation.experience {
        case .floor10Tutorial:
            Floor10TutorialView(sceneController: sceneController)
        case .floor9Entrance:
            Floor9EntranceView(sceneController: sceneController)
        case .battle:
            BattleView(realityController: sceneController)
        case let .reward(floor):
            RewardSelectionView(floor: floor, sceneController: sceneController)
        case .floor8Exploration:
            Floor8ExplorationView(sceneController: sceneController)
        case let .descent(floor):
            if floor == .floor9 {
                Floor9DescentDoorView(sceneController: sceneController)
            } else {
                Floor8DescentDoorView(sceneController: sceneController)
            }
        case .completion:
            DemoCompleteView(onReturnToTitle: onExit)
        }
    }
}

private enum SharedHUDPalette {
    static let brass = Color(red: 184 / 255, green: 139 / 255, blue: 77 / 255)
    static let title = Color(red: 225 / 255, green: 202 / 255, blue: 164 / 255)
    static let icon = Color(red: 222 / 255, green: 216 / 255, blue: 202 / 255)
}
