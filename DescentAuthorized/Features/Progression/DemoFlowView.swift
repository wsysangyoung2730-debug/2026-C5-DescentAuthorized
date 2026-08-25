import SwiftUI

struct DemoFlowView: View {
    @EnvironmentObject private var gameSession: GameSessionStore

    let onExit: () -> Void

    @State private var isShowingPauseMenu = false
    @State private var isShowingSettings = false
    @StateObject private var sceneController = RealitySceneController()

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

            sceneView
                .id(gameSession.presentation.progressSceneID)

            HStack {
                Button {
                    isShowingPauseMenu = true
                } label: {
                    Image(systemName: "pause.fill")
                }
                .help("일시정지")
                .accessibilityLabel("일시정지")

                Spacer()

                Text("제\(gameSession.progress.currentFloor.rawValue)층")
                    .font(.caption.monospaced().weight(.bold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("설정")
                .accessibilityLabel("설정")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .foregroundStyle(DAColor.body)
            .background(DAColor.panel.opacity(0.78))
            .overlay(alignment: .bottom) {
                Rectangle().fill(DAColor.divider.opacity(0.8)).frame(height: 1)
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
