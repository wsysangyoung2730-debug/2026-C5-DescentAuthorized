import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var gameFeedback: GameFeedbackManager
    @EnvironmentObject private var gameCenter: GameCenterManager
    @EnvironmentObject private var gameSession: GameSessionStore

    @State private var testStrokes: [DrawnStroke] = []
    @State private var lastInputMethod: DrawingInputMethod?
    @State private var canvasController = RuneDrawingCanvasController()
    @State private var isShowingAchievements = false
    @State private var isConfirmingTutorialReset = false

    var body: some View {
        NavigationStack {
            ZStack {
                DASettingsBackdrop(imageName: "SettingsMenuBackground")

                List {
                Section("입력 방식") {
                    Picker("입력 방식", selection: inputPreferenceBinding) {
                        Text("자동").tag(DrawingInputPreference.automatic)
                        Text("Pencil").tag(DrawingInputPreference.pencilOnly)
                        Text("손가락").tag(DrawingInputPreference.fingerOnly)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("마법진 입력 방식")

                    Picker("전투 입력 패드 위치", selection: drawingPadPositionBinding) {
                        Text("왼쪽").tag(DrawingPadPosition.left)
                        Text("오른쪽").tag(DrawingPadPosition.right)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("전투 입력 패드 위치")
                }

                inputConfirmationSection

                Section("소리와 반응") {
                    Toggle(
                        "효과음",
                        isOn: settingBinding(
                            get: { $0.soundEffectsEnabled },
                            set: appSettings.setSoundEffectsEnabled
                        )
                    )
                    Toggle(
                        "배경음",
                        isOn: settingBinding(
                            get: { $0.musicEnabled },
                            set: appSettings.setMusicEnabled
                        )
                    )
                    Toggle(
                        "햅틱",
                        isOn: settingBinding(
                            get: { $0.hapticsEnabled },
                            set: appSettings.setHapticsEnabled
                        )
                    )
                }

                Section("화면 효과") {
                    Toggle(
                        "번쩍임 줄이기",
                        isOn: settingBinding(
                            get: { $0.reducedFlashes },
                            set: appSettings.setReducedFlashes
                        )
                    )
                    Toggle(
                        "동작 줄이기",
                        isOn: settingBinding(
                            get: { $0.reducedMotion },
                            set: appSettings.setReducedMotion
                        )
                    )
                }

                Section {
                    ForEach(TutorialSequenceID.allCases, id: \.self) { sequence in
                        tutorialReplayButton(sequence)
                    }

                    Button(role: .destructive) {
                        isConfirmingTutorialReset = true
                    } label: {
                        Label("모든 튜토리얼 기록 초기화", systemImage: "arrow.counterclockwise")
                            .frame(minHeight: 44)
                    }
                } header: {
                    Text("튜토리얼")
                } footer: {
                    Text("다시 보기는 게임 진행을 되돌리지 않습니다. 모든 기록 초기화 후에는 아직 지나지 않은 안내와 현재 장면의 안내가 다시 표시됩니다.")
                }

                Section("Game Center") {
                    Label(gameCenter.statusTitle, systemImage: gameCenterStatusIcon)
                        .foregroundStyle(gameCenter.isAuthenticated ? .primary : .secondary)

                    if gameCenter.isAuthenticated {
                        Button {
                            isShowingAchievements = true
                        } label: {
                            Label("업적 보기", systemImage: "trophy")
                        }
                    } else {
                        Button {
                            gameCenter.authenticate(force: true)
                        } label: {
                            Label("다시 연결", systemImage: "arrow.clockwise")
                        }
                    }

                    if let syncError = gameCenter.lastSyncError {
                        Text(syncError)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                }
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        gameFeedback.playInterface(.back, settings: appSettings.settings)
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .help("설정 닫기")
                    .accessibilityLabel("설정 닫기")
                }
            }
            .alert("설정을 저장하지 못했습니다", isPresented: $appSettings.showsPersistenceError) {
                Button("확인", role: .cancel) {}
            }
            .confirmationDialog(
                "튜토리얼 기록을 초기화할까요?",
                isPresented: $isConfirmingTutorialReset,
                titleVisibility: .visible
            ) {
                Button("모든 튜토리얼 기록 초기화", role: .destructive) {
                    gameFeedback.playInterface(.confirm, settings: appSettings.settings)
                    gameSession.send(.resetTutorials)
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("게임 진행과 저장된 전투 상태는 유지됩니다.")
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $isShowingAchievements) {
            GameCenterDashboardView()
                .ignoresSafeArea()
        }
    }

    private var drawingSurface: some View {
        ZStack {
            Color(red: 0.035, green: 0.04, blue: 0.055)

            grid

            RuneDrawingCanvas(
                inputPreference: appSettings.inputPreference,
                maximumStrokeCount: 2,
                controller: canvasController,
                strokes: $testStrokes,
                lastInputMethod: $lastInputMethod
            )
        }
        .frame(minHeight: 240, idealHeight: 280, maxHeight: 320)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
        .accessibilityElement(children: .contain)
    }

    private var inputConfirmationSection: some View {
        Section("입력 확인") {
            drawingSurface
            inputConfirmationControls
        }
    }

    private var inputConfirmationControls: some View {
        HStack(spacing: 16) {
            Label(inputMethodTitle, systemImage: inputMethodIcon)
                .foregroundStyle(.secondary)

            Spacer(minLength: 16)

            Text("\(testStrokes.count) / 2획")
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Button {
                gameFeedback.playInterface(.back, settings: appSettings.settings)
                canvasController.undoLastStroke()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.borderless)
            .disabled(testStrokes.isEmpty)
            .help("마지막 획 되돌리기")
            .accessibilityLabel("마지막 획 되돌리기")
        }
        .frame(minHeight: 44)
    }

    private var grid: some View {
        Canvas { context, size in
            var path = Path()
            let columns = 8
            let rows = 5
            for column in 1..<columns {
                let x = size.width * CGFloat(column) / CGFloat(columns)
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            for row in 1..<rows {
                let y = size.height * CGFloat(row) / CGFloat(rows)
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(.white.opacity(0.055)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }

    private var inputPreferenceBinding: Binding<DrawingInputPreference> {
        Binding(
            get: { appSettings.inputPreference },
            set: {
                gameFeedback.playInterface(.select, settings: appSettings.settings)
                appSettings.setInputPreference($0)
            }
        )
    }

    private var drawingPadPositionBinding: Binding<DrawingPadPosition> {
        Binding(
            get: { appSettings.drawingPadPosition },
            set: {
                gameFeedback.playInterface(.select, settings: appSettings.settings)
                appSettings.setDrawingPadPosition($0)
            }
        )
    }

    private func settingBinding(
        get: @escaping (GameSettings) -> Bool,
        set: @escaping (Bool) -> Void
    ) -> Binding<Bool> {
        Binding(
            get: { get(appSettings.settings) },
            set: { value in
                gameFeedback.playInterface(.select, settings: appSettings.settings)
                set(value)
            }
        )
    }

    private var inputMethodTitle: String {
        switch lastInputMethod {
        case .pencil:
            "Apple Pencil"
        case .finger:
            "손가락"
        case nil:
            "대기"
        }
    }

    private var inputMethodIcon: String {
        switch lastInputMethod {
        case .pencil:
            "pencil.tip"
        case .finger:
            "hand.draw"
        case nil:
            "circle.dotted"
        }
    }

    private var gameCenterStatusIcon: String {
        gameCenter.isAuthenticated ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.xmark"
    }

    private func tutorialReplayButton(_ sequence: TutorialSequenceID) -> some View {
        let title = sequence.settingsTitle
        return Button {
            gameFeedback.playInterface(.select, settings: appSettings.settings)
            gameSession.send(.requestTutorialReplay(sequence))
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                    Text("다음 해당 장면에서 다시 안내")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                replayStatusIcon(sequence)
            }
            .frame(minHeight: 44)
        }
        .accessibilityLabel("\(title) 다시 보기")
        .accessibilityHint("다음에 해당 장면에 들어가면 안내를 다시 표시합니다")
    }

    @ViewBuilder
    private func replayStatusIcon(_ sequence: TutorialSequenceID) -> some View {
        let progress = gameSession.progress.tutorialProgress
        if progress.requestedReplay == sequence {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(DAColor.magicGlow)
                .accessibilityLabel("다시 보기 예약됨")
        } else if progress.completedSequences.contains(sequence) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green.opacity(0.8))
                .accessibilityLabel("완료")
        } else if progress.skippedSequences.contains(sequence) {
            Image(systemName: "forward.end.circle")
                .foregroundStyle(.secondary)
                .accessibilityLabel("건너뜀")
        }
    }
}

private extension TutorialSequenceID {
    var settingsTitle: String {
        switch self {
        case .floor10Intro: "10층 시작·기상 연출"
        case .floor10Investigation: "10층 탐색과 조사"
        case .afterglowDiscovery: "잔광 말소 발견·훈련"
        case .riftDiscovery: "균열 절단 발견·훈련"
        case .floor10DescentSeal: "10층 하강 봉인문"
        case .recordsBattleBasics: "9층 첫 전투"
        }
    }
}

struct DASettingsBackdrop: View {
    let imageName: String

    var body: some View {
        GeometryReader { proxy in
            Image(imageName)
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
