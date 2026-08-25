import SwiftUI

struct DemoFlowView: View {
    @EnvironmentObject private var gameSession: GameSessionStore

    let onExit: () -> Void

    @State private var isShowingPauseMenu = false
    @State private var isShowingSettings = false

    var body: some View {
        ZStack(alignment: .top) {
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
        }
        .sheet(isPresented: $isShowingPauseMenu) {
            PauseMenuView(onExitToTitle: onExit)
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
    }

    @ViewBuilder
    private var sceneView: some View {
        switch gameSession.presentation.experience {
        case .floor10Tutorial:
            Floor10TutorialView()
        case .floor9Entrance:
            Floor9EntranceView()
        case .battle:
            BattleView()
        case let .reward(floor):
            RewardSelectionView(floor: floor)
        case .floor8Exploration:
            Floor8ExplorationView()
        case let .descent(floor):
            if floor == .floor9 {
                Floor9DescentDoorView()
            } else {
                Floor8DescentDoorView()
            }
        case .completion:
            DemoCompleteView(onReturnToTitle: onExit)
        }
    }
}
