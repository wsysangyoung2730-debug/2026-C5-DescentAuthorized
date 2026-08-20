import SwiftUI

struct PauseMenuView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var gameSession: GameSessionStore

    let onExitToTitle: () -> Void

    @State private var isShowingSettings = false
    @State private var isConfirmingRestart = false
    @State private var isConfirmingExit = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        dismiss()
                    } label: {
                        Label("계속하기", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                Section("현재 절차") {
                    LabeledContent("위치", value: "제\(gameSession.progress.currentFloor.rawValue)층")
                    LabeledContent("체크포인트", value: checkpointTitle)

                    if gameSession.battleState != nil {
                        Button(role: .destructive) {
                            isConfirmingRestart = true
                        } label: {
                            Label("현재 전투 다시 시작", systemImage: "arrow.counterclockwise")
                        }
                    }
                }

                Section {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Label("설정", systemImage: "gearshape")
                    }

                    Button {
                        isConfirmingExit = true
                    } label: {
                        Label("타이틀로 돌아가기", systemImage: "house")
                    }
                }
            }
            .navigationTitle("절차 일시정지")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .help("계속하기")
                    .accessibilityLabel("계속하기")
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
        .confirmationDialog(
            "현재 전투를 다시 시작할까요?",
            isPresented: $isConfirmingRestart,
            titleVisibility: .visible
        ) {
            Button("전투 다시 시작", role: .destructive) {
                restartEncounter()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text(restartMessage)
        }
        .confirmationDialog(
            "타이틀로 돌아갈까요?",
            isPresented: $isConfirmingExit,
            titleVisibility: .visible
        ) {
            Button("타이틀로 돌아가기") {
                dismiss()
                onExitToTitle()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("완료된 절차와 현재 체크포인트는 저장되어 있습니다.")
        }
    }

    private var checkpointTitle: String {
        switch gameSession.progress.checkpoint {
        case .floor10Start: "10층 기동"
        case .floor10Complete: "10층 하강 승인"
        case .recordsBattle: "9층 기록 구역"
        case .recordsDefeated: "기록 관리자 처치"
        case .floor8Start: "8층 보호 절차실"
        case .residualBattle: "관측 잔류체"
        case .residualDefeated: "관측실 봉인문"
        case .observationBattle: "관측 관리자"
        case .observationDefeated: "8층 보상 기록"
        case .demoComplete: "제7층 도달"
        }
    }

    private var restartMessage: String {
        gameSession.battleState?.phase == .defeat
            ? "패배한 전투를 HP 100으로 재개합니다."
            : "이번 전투에서 발생한 피해와 방벽 상태를 초기화하고, 진입 당시 HP로 돌아갑니다."
    }

    private func restartEncounter() {
        let command: DemoCommand = gameSession.battleState?.phase == .defeat
            ? .restartEncounter
            : .restartEncounterFromCheckpoint
        gameSession.send(command)
        dismiss()
    }
}
