import SwiftUI

struct PauseMenuView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var gameFeedback: GameFeedbackManager
    @EnvironmentObject private var gameSession: GameSessionStore

    let onTravelToCheckpoint: (CheckpointID) -> Void
    let onExitToTitle: () -> Void

    @State private var mode = Mode.overview
    @State private var selectedCheckpoint: CheckpointID?
    @State private var isConfirmingRestart = false
    @State private var isConfirmingExit = false

    var body: some View {
        GeometryReader { proxy in
            let width = min(760, max(560, proxy.size.width - 96))
            let height = min(670, max(540, proxy.size.height - 72))

            ZStack {
                DASettingsBackdrop(imageName: "PauseMenuBackground")
                Color.black.opacity(0.48).ignoresSafeArea()

                pausePanel(width: width, height: height)
                    .frame(width: width, height: height)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            selectedCheckpoint = gameSession.progress.checkpoint
        }
        .confirmationDialog(
            "현재 전투를 다시 시작할까요?",
            isPresented: $isConfirmingRestart,
            titleVisibility: .visible
        ) {
            Button("전투 다시 시작", role: .destructive) {
                gameFeedback.playInterface(.confirm, settings: appSettings.settings)
                restartEncounter()
            }
            Button("취소", role: .cancel) {
                gameFeedback.playInterface(.back, settings: appSettings.settings)
            }
        } message: {
            Text(restartMessage)
        }
        .confirmationDialog(
            "타이틀로 돌아갈까요?",
            isPresented: $isConfirmingExit,
            titleVisibility: .visible
        ) {
            Button("타이틀로 돌아가기") {
                gameFeedback.playInterface(.confirm, settings: appSettings.settings)
                dismiss()
                onExitToTitle()
            }
            Button("취소", role: .cancel) {
                gameFeedback.playInterface(.back, settings: appSettings.settings)
            }
        } message: {
            Text("완료된 절차와 해금된 체크포인트는 저장되어 있습니다.")
        }
    }

    private func pausePanel(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(red: 0.035, green: 0.038, blue: 0.045).opacity(0.97))

            Image("GateSealMechanism")
                .resizable()
                .scaledToFit()
                .frame(width: min(width * 0.7, height * 0.78))
                .opacity(0.055)
                .blendMode(.screen)
                .allowsHitTesting(false)

            RoundedRectangle(cornerRadius: 4)
                .stroke(PausePalette.gold.opacity(0.72), lineWidth: 1)
                .padding(1)

            RoundedRectangle(cornerRadius: 2)
                .stroke(PausePalette.gold.opacity(0.28), lineWidth: 1)
                .padding(8)

            Group {
                if mode == .overview {
                    overviewContent
                        .transition(.opacity.combined(with: .scale(scale: 0.985)))
                } else {
                    checkpointContent
                        .transition(.opacity.combined(with: .scale(scale: 0.985)))
                }
            }
            .padding(.horizontal, 42)
            .padding(.vertical, 34)

            closeButton
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(color: .black.opacity(0.82), radius: 34, y: 18)
        .animation(.easeInOut(duration: appSettings.reducedMotion ? 0 : 0.2), value: mode)
    }

    private var overviewContent: some View {
        VStack(spacing: 15) {
            pauseHeader(
                title: "절차 일시정지",
                subtitle: "제\(gameSession.progress.currentFloor.rawValue)층 · \(checkpointTitle)"
            )

            ornamentDivider

            VStack(spacing: 11) {
                if gameSession.battleState != nil {
                    actionRow(
                        title: "현재 전투 다시 시작",
                        detail: "전투 진입 상태로 복원",
                        systemImage: "arrow.counterclockwise",
                        tint: PausePalette.warning
                    ) {
                        isConfirmingRestart = true
                    }
                }

                actionRow(
                    title: "체크포인트 이동",
                    detail: "해금한 절차 지점 선택",
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                    tint: PausePalette.magic
                ) {
                    gameFeedback.playInterface(.select, settings: appSettings.settings)
                    selectedCheckpoint = gameSession.progress.checkpoint
                    mode = .checkpoints
                }

                actionRow(
                    title: "타이틀로 돌아가기",
                    detail: "현재 진행 상황 저장",
                    systemImage: "house.fill",
                    tint: PausePalette.body
                ) {
                    isConfirmingExit = true
                }
            }

            Spacer(minLength: 4)

            Button {
                gameFeedback.playInterface(.back, settings: appSettings.settings)
                dismiss()
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "play.fill")
                    Text("계속하기")
                        .font(.system(size: 27, weight: .medium, design: .serif))
                }
                .foregroundStyle(PausePalette.title)
                .frame(maxWidth: .infinity, minHeight: 78)
                .background(PausePalette.magic.opacity(0.09))
                .overlay {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(PausePalette.magic.opacity(0.88), lineWidth: 1.5)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("일시정지 창을 닫고 현재 장면으로 돌아갑니다")
        }
    }

    private var checkpointContent: some View {
        VStack(spacing: 15) {
            pauseHeader(
                title: "체크포인트 이동",
                subtitle: "완료한 범위 안에서 절차 장면을 복원합니다"
            )

            ornamentDivider

            ScrollView(showsIndicators: false) {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 10
                ) {
                    ForEach(unlockedCheckpoints, id: \.self) { checkpoint in
                        checkpointButton(checkpoint)
                    }
                }
                .padding(.vertical, 2)
            }
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white, location: 0.025),
                        .init(color: .white, location: 0.975),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

            HStack(spacing: 12) {
                Button {
                    gameFeedback.playInterface(.back, settings: appSettings.settings)
                    mode = .overview
                } label: {
                    Label("돌아가기", systemImage: "chevron.left")
                        .frame(maxWidth: .infinity, minHeight: 58)
                }
                .buttonStyle(PauseSecondaryButtonStyle())

                Button(action: travelToSelectedCheckpoint) {
                    Label("이동하기", systemImage: "arrow.right.circle.fill")
                        .font(.system(size: 19, weight: .semibold, design: .serif))
                        .frame(maxWidth: .infinity, minHeight: 58)
                }
                .buttonStyle(PausePrimaryButtonStyle())
                .disabled(selectedCheckpoint == nil)
            }
        }
    }

    private func pauseHeader(title: String, subtitle: String) -> some View {
        VStack(spacing: 7) {
            Text(title)
                .font(.system(size: 40, weight: .medium, design: .serif))
                .foregroundStyle(PausePalette.title)
            Text(subtitle)
                .font(.system(size: 17, weight: .medium, design: .serif))
                .foregroundStyle(PausePalette.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 54)
    }

    private var ornamentDivider: some View {
        HStack(spacing: 12) {
            Rectangle().fill(PausePalette.gold.opacity(0.45)).frame(height: 1)
            Image(systemName: "diamond.fill")
                .font(.system(size: 8))
                .foregroundStyle(PausePalette.gold)
            Rectangle().fill(PausePalette.gold.opacity(0.45)).frame(height: 1)
        }
    }

    private func actionRow(
        title: String,
        detail: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 18) {
                Image(systemName: systemImage)
                    .font(.system(size: 27, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 20, weight: .medium, design: .serif))
                        .foregroundStyle(PausePalette.body)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(PausePalette.secondary)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(PausePalette.gold.opacity(0.7))
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(Color.white.opacity(0.025))
            .overlay {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(PausePalette.gold.opacity(0.3), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func checkpointButton(_ checkpoint: CheckpointID) -> some View {
        let isSelected = selectedCheckpoint == checkpoint
        let isCurrent = gameSession.progress.checkpoint == checkpoint

        return Button {
            gameFeedback.playInterface(.select, settings: appSettings.settings)
            selectedCheckpoint = checkpoint
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(isSelected ? PausePalette.magic : PausePalette.gold.opacity(0.45))
                        .frame(width: 34, height: 34)
                    Image(systemName: isSelected ? "checkmark" : checkpoint.iconName)
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(isSelected ? PausePalette.magic : PausePalette.secondary)

                VStack(alignment: .leading, spacing: 3) {
                    Text(checkpoint.pauseTitle)
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .lineLimit(1)
                    Text(isCurrent ? "현재 위치" : checkpoint.pauseSubtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isCurrent ? PausePalette.magic : PausePalette.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? PausePalette.title : PausePalette.body)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(isSelected ? PausePalette.magic.opacity(0.1) : Color.white.opacity(0.02))
            .overlay {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(
                        isSelected ? PausePalette.magic.opacity(0.9) : PausePalette.gold.opacity(0.22),
                        lineWidth: isSelected ? 1.3 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(checkpoint.pauseTitle), \(isCurrent ? "현재 위치" : checkpoint.pauseSubtitle)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var closeButton: some View {
        Button {
            gameFeedback.playInterface(.back, settings: appSettings.settings)
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(PausePalette.gold)
                .frame(width: 48, height: 48)
                .background(Color.black.opacity(0.42))
                .overlay {
                    Rectangle().stroke(PausePalette.gold.opacity(0.5), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("계속하기")
    }

    private var unlockedCheckpoints: [CheckpointID] {
        CheckpointID.allCases.filter {
            $0.progressionIndex <= gameSession.progress.furthestCheckpoint.progressionIndex
        }
    }

    private var checkpointTitle: String {
        gameSession.progress.checkpoint.pauseTitle
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

    private func travelToSelectedCheckpoint() {
        guard let selectedCheckpoint else { return }
        gameFeedback.playInterface(.confirm, settings: appSettings.settings)
        onTravelToCheckpoint(selectedCheckpoint)
        dismiss()
    }
}

private extension PauseMenuView {
    enum Mode {
        case overview
        case checkpoints
    }
}

private extension CheckpointID {
    var pauseTitle: String {
        switch self {
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

    var pauseSubtitle: String {
        switch self {
        case .floor10Start: "업무 개시"
        case .floor10Complete: "제9층 입구"
        case .recordsBattle: "전투 직전"
        case .recordsDefeated: "보상 선택 전"
        case .floor8Start: "제8층 입구"
        case .residualBattle: "잔류체 전투 직전"
        case .residualDefeated: "봉인 해제 전"
        case .observationBattle: "관리자 전투 직전"
        case .observationDefeated: "보상 선택 전"
        case .demoComplete: "데모 완료"
        }
    }

    var iconName: String {
        switch self {
        case .recordsBattle, .residualBattle, .observationBattle: "shield.lefthalf.filled"
        case .recordsDefeated, .residualDefeated, .observationDefeated: "seal.fill"
        case .demoComplete: "flag.checkered"
        default: "diamond.fill"
        }
    }
}

private enum PausePalette {
    static let gold = Color(red: 0.68, green: 0.54, blue: 0.34)
    static let title = Color(red: 0.9, green: 0.86, blue: 0.78)
    static let body = Color(red: 0.82, green: 0.8, blue: 0.76)
    static let secondary = Color(red: 0.58, green: 0.55, blue: 0.52)
    static let magic = Color(red: 0.63, green: 0.43, blue: 0.96)
    static let warning = Color(red: 0.9, green: 0.57, blue: 0.25)
}

private struct PauseSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(PausePalette.body)
            .background(Color.black.opacity(configuration.isPressed ? 0.68 : 0.42))
            .overlay {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(PausePalette.gold.opacity(0.48), lineWidth: 1)
            }
    }
}

private struct PausePrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? PausePalette.title : PausePalette.secondary)
            .background(
                PausePalette.magic.opacity(
                    isEnabled ? (configuration.isPressed ? 0.22 : 0.12) : 0.03
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(
                        isEnabled ? PausePalette.magic.opacity(0.85) : PausePalette.gold.opacity(0.2),
                        lineWidth: 1.2
                    )
            }
    }
}
