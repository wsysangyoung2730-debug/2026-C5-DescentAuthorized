import SwiftUI

struct DemoFlowView: View {
    @EnvironmentObject private var gameSession: GameSessionStore

    let onExit: () -> Void

    @State private var isShowingPauseMenu = false
    @State private var isShowingSettings = false

    var body: some View {
        ZStack(alignment: .top) {
            sceneView

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
        switch gameSession.progress.currentScene {
        case .floor10MeetingRoom,
             .floor10Office,
             .floor10GlyphArchive,
             .floor10TrainingWall,
             .floor10DescentDoor:
            Floor10TutorialView()

        case .floor9RecordsBattle,
             .floor8ResidualBattle,
             .floor8AdministratorBattle:
            BattleView()

        case .floor9Entrance:
            Floor9EntranceView()

        case .floor9RewardVault:
            RewardSelectionView(floor: .floor9)

        case .floor9DescentDoor:
            Floor9DescentDoorView()

        case .floor8Antechamber,
             .floor8ProtectionRoom,
             .floor8SealedDoor:
            Floor8ExplorationView()

        case .floor8Reward:
            RewardSelectionView(floor: .floor8)

        case .floor8DescentDoor:
            Floor8DescentDoorView()

        case .demoComplete:
            DemoCompleteView(onReturnToTitle: onExit)
        }
    }
}
