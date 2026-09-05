import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var gameFeedback: GameFeedbackManager
    @EnvironmentObject private var gameCenter: GameCenterManager
    @EnvironmentObject private var gameSession: GameSessionStore

    @State private var selectedCategory = SettingsCategory.input
    @State private var testStrokes: [DrawnStroke] = []
    @State private var lastInputMethod: DrawingInputMethod?
    @State private var canvasController = RuneDrawingCanvasController()
    @State private var isShowingAchievements = false
    @State private var isConfirmingTutorialReset = false

    var body: some View {
        GeometryReader { proxy in
            let horizontalInset = min(36, max(16, proxy.size.width * 0.045))
            let verticalInset = min(30, max(14, proxy.size.height * 0.04))
            let panelWidth = max(1, proxy.size.width - (horizontalInset * 2))
            let panelHeight = max(1, proxy.size.height - (verticalInset * 2))
            let sidebarWidth = min(270, max(184, panelWidth * 0.235))

            ZStack {
                DASettingsBackdrop(imageName: "SettingsMenuBackground")
                Color.black.opacity(0.48).ignoresSafeArea()

                settingsPanel(sidebarWidth: sidebarWidth)
                    .frame(width: panelWidth, height: panelHeight)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
        }
        .preferredColorScheme(.dark)
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
        .fullScreenCover(isPresented: $isShowingAchievements) {
            GameCenterDashboardView()
                .ignoresSafeArea()
        }
    }

    private func settingsPanel(sidebarWidth: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(SettingsPalette.panel.opacity(0.975))

            Image("GateSealMechanism")
                .resizable()
                .scaledToFit()
                .opacity(0.025)
                .blendMode(.screen)
                .padding(80)
                .allowsHitTesting(false)

            RoundedRectangle(cornerRadius: 5)
                .stroke(SettingsPalette.gold.opacity(0.76), lineWidth: 1)
                .padding(1)

            RoundedRectangle(cornerRadius: 3)
                .stroke(SettingsPalette.gold.opacity(0.24), lineWidth: 1)
                .padding(9)

            VStack(spacing: 0) {
                panelHeader
                    .frame(height: 88)

                Rectangle()
                    .fill(SettingsPalette.gold.opacity(0.4))
                    .frame(height: 1)
                    .padding(.horizontal, 26)

                HStack(spacing: 0) {
                    categorySidebar
                        .frame(width: sidebarWidth)

                    Rectangle()
                        .fill(SettingsPalette.gold.opacity(0.28))
                        .frame(width: 1)
                        .padding(.vertical, 18)

                    categoryDetail
                }
            }
            .padding(10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .shadow(color: .black.opacity(0.82), radius: 34, y: 16)
    }

    private var panelHeader: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("설정")
                    .font(.system(size: 32, weight: .medium, design: .serif))
                    .foregroundStyle(SettingsPalette.title)

                Text("절차 환경과 입력 방식을 조정합니다")
                    .font(.subheadline)
                    .foregroundStyle(SettingsPalette.secondary)
            }

            Spacer()

            Button {
                gameFeedback.playInterface(.back, settings: appSettings.settings)
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 21, weight: .light))
                    .foregroundStyle(SettingsPalette.title)
                    .frame(width: 52, height: 52)
                    .background(SettingsPalette.surface.opacity(0.72))
                    .overlay {
                        Rectangle()
                            .stroke(SettingsPalette.gold.opacity(0.58), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .help("설정 닫기")
            .accessibilityLabel("설정 닫기")
        }
        .padding(.leading, 34)
        .padding(.trailing, 22)
    }

    private var categorySidebar: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(SettingsCategory.allCases) { category in
                    Button {
                        gameFeedback.playInterface(.select, settings: appSettings.settings)
                        withAnimation(.easeInOut(duration: appSettings.reducedMotion ? 0 : 0.16)) {
                            selectedCategory = category
                        }
                    } label: {
                        HStack(spacing: 15) {
                            Image(systemName: category.icon)
                                .font(.system(size: 23, weight: .light))
                                .frame(width: 30)

                            Text(category.title)
                                .font(.system(size: 18, weight: .medium))

                            Spacer(minLength: 4)
                        }
                        .foregroundStyle(
                            selectedCategory == category
                                ? SettingsPalette.magicBright
                                : SettingsPalette.body
                        )
                        .padding(.horizontal, 22)
                        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                        .background {
                            if selectedCategory == category {
                                LinearGradient(
                                    colors: [
                                        SettingsPalette.magic.opacity(0.18),
                                        SettingsPalette.magic.opacity(0.025)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            }
                        }
                        .overlay(alignment: .leading) {
                            if selectedCategory == category {
                                Rectangle()
                                    .fill(SettingsPalette.magicBright)
                                    .frame(width: 3)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedCategory == category ? .isSelected : [])

                    if category != SettingsCategory.allCases.last {
                        Rectangle()
                            .fill(SettingsPalette.gold.opacity(0.13))
                            .frame(height: 1)
                            .padding(.horizontal, 18)
                    }
                }
            }
            .padding(.vertical, 18)
        }
    }

    private var categoryDetail: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text(selectedCategory.title)
                    .font(.system(size: 25, weight: .semibold, design: .serif))
                    .foregroundStyle(SettingsPalette.title)

                Text(selectedCategory.detail)
                    .font(.subheadline)
                    .foregroundStyle(SettingsPalette.secondary)
            }
            .padding(.horizontal, 32)
            .padding(.top, 23)
            .padding(.bottom, 18)

            ScrollView(showsIndicators: false) {
                categoryContent
                    .padding(.horizontal, 32)
                    .padding(.bottom, 28)
            }
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white, location: 0.018),
                        .init(color: .white, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .id(selectedCategory)
        .transition(.opacity)
    }

    @ViewBuilder
    private var categoryContent: some View {
        switch selectedCategory {
        case .input:
            inputSettings
        case .sound:
            soundSettings
        case .display:
            displaySettings
        case .tutorial:
            tutorialSettings
        case .gameCenter:
            gameCenterSettings
        }
    }

    private var inputSettings: some View {
        VStack(spacing: 16) {
            settingsSection(title: "입력 방식", subtitle: "필기 도구와 전투 입력 패드 위치") {
                VStack(spacing: 0) {
                    settingRow(title: "입력 도구", detail: "자동은 먼저 감지된 입력을 사용합니다") {
                        Picker("입력 도구", selection: inputPreferenceBinding) {
                            Text("자동").tag(DrawingInputPreference.automatic)
                            Text("Apple Pencil").tag(DrawingInputPreference.pencilOnly)
                            Text("손가락").tag(DrawingInputPreference.fingerOnly)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .accessibilityLabel("마법진 입력 방식")
                    }

                    rowDivider

                    settingRow(title: "전투 입력 패드", detail: "주로 사용하는 손에 맞춰 배치합니다") {
                        Picker("전투 입력 패드 위치", selection: drawingPadPositionBinding) {
                            Text("왼쪽").tag(DrawingPadPosition.left)
                            Text("오른쪽").tag(DrawingPadPosition.right)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .accessibilityLabel("전투 입력 패드 위치")
                    }
                }
            }

            settingsSection(title: "입력 확인", subtitle: "최대 2획까지 직접 그려 입력 상태를 확인합니다") {
                VStack(spacing: 12) {
                    drawingSurface
                    inputConfirmationControls
                }
                .padding(16)
            }
        }
    }

    private var soundSettings: some View {
        settingsSection(title: "소리와 반응", subtitle: "전투 중 재생되는 감각 피드백") {
            VStack(spacing: 0) {
                toggleRow(
                    title: "효과음",
                    detail: "주문과 인터페이스 효과음",
                    systemImage: "speaker.wave.2.fill",
                    isOn: settingBinding(
                        get: { $0.soundEffectsEnabled },
                        set: appSettings.setSoundEffectsEnabled
                    )
                )
                rowDivider
                toggleRow(
                    title: "배경음",
                    detail: "장면과 전투 배경 음악",
                    systemImage: "music.note",
                    isOn: settingBinding(
                        get: { $0.musicEnabled },
                        set: appSettings.setMusicEnabled
                    )
                )
                rowDivider
                toggleRow(
                    title: "햅틱",
                    detail: "입력과 판정 시 진동 피드백",
                    systemImage: "hand.tap.fill",
                    isOn: settingBinding(
                        get: { $0.hapticsEnabled },
                        set: appSettings.setHapticsEnabled
                    )
                )
            }
        }
    }

    private var displaySettings: some View {
        settingsSection(title: "화면 효과", subtitle: "시각 연출과 움직임의 강도를 조정합니다") {
            VStack(spacing: 0) {
                toggleRow(
                    title: "번쩍임 줄이기",
                    detail: "강한 섬광 효과의 밝기와 빈도를 낮춥니다",
                    systemImage: "light.max",
                    isOn: settingBinding(
                        get: { $0.reducedFlashes },
                        set: appSettings.setReducedFlashes
                    )
                )
                rowDivider
                toggleRow(
                    title: "동작 줄이기",
                    detail: "회전과 전환 애니메이션을 간소화합니다",
                    systemImage: "figure.walk.motion",
                    isOn: settingBinding(
                        get: { $0.reducedMotion },
                        set: appSettings.setReducedMotion
                    )
                )
            }
        }
    }

    private var tutorialSettings: some View {
        VStack(spacing: 16) {
            settingsSection(title: "튜토리얼 다시 보기", subtitle: "선택한 안내는 다음 해당 장면에서 재생됩니다") {
                VStack(spacing: 0) {
                    ForEach(Array(TutorialSequenceID.allCases.enumerated()), id: \.element) { index, sequence in
                        tutorialReplayButton(sequence)
                        if index < TutorialSequenceID.allCases.count - 1 {
                            rowDivider
                        }
                    }
                }
            }

            Button(role: .destructive) {
                isConfirmingTutorialReset = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.counterclockwise")
                    Text("모든 튜토리얼 기록 초기화")
                    Spacer()
                    Text("게임 진행 유지")
                        .font(.caption)
                        .foregroundStyle(SettingsPalette.secondary)
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(Color.red.opacity(0.055))
                .overlay {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.red.opacity(0.32), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.red.opacity(0.86))
        }
    }

    private var gameCenterSettings: some View {
        settingsSection(title: "Game Center", subtitle: "업적과 계정 연결 상태") {
            VStack(spacing: 0) {
                settingRow(
                    title: gameCenter.statusTitle,
                    detail: gameCenter.isAuthenticated ? "업적 동기화 준비됨" : "계정 연결이 필요합니다",
                    systemImage: gameCenterStatusIcon
                ) {
                    Circle()
                        .fill(gameCenter.isAuthenticated ? Color.green : SettingsPalette.secondary)
                        .frame(width: 9, height: 9)
                        .accessibilityHidden(true)
                }

                rowDivider

                Button {
                    gameFeedback.playInterface(.select, settings: appSettings.settings)
                    if gameCenter.isAuthenticated {
                        isShowingAchievements = true
                    } else {
                        gameCenter.authenticate(force: true)
                    }
                } label: {
                    HStack(spacing: 13) {
                        Image(systemName: gameCenter.isAuthenticated ? "trophy.fill" : "arrow.clockwise")
                            .frame(width: 24)
                        Text(gameCenter.isAuthenticated ? "업적 보기" : "다시 연결")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(SettingsPalette.secondary)
                    }
                    .foregroundStyle(SettingsPalette.body)
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity, minHeight: 62)
                }
                .buttonStyle(.plain)

                if let syncError = gameCenter.lastSyncError {
                    rowDivider
                    Text(syncError)
                        .font(.caption)
                        .foregroundStyle(Color.red.opacity(0.82))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                }
            }
        }
    }

    private func settingsSection<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(SettingsPalette.title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(SettingsPalette.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 15)

            Rectangle()
                .fill(SettingsPalette.gold.opacity(0.2))
                .frame(height: 1)

            content()
        }
        .background(SettingsPalette.surface.opacity(0.66))
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .stroke(SettingsPalette.gold.opacity(0.28), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func settingRow<Control: View>(
        title: String,
        detail: String,
        systemImage: String? = nil,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 18) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 19, weight: .light))
                    .foregroundStyle(SettingsPalette.magicBright)
                    .frame(width: 26)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(SettingsPalette.body)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(SettingsPalette.secondary)
            }

            Spacer(minLength: 20)

            control()
                .frame(maxWidth: 470)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, minHeight: 76)
    }

    private func toggleRow(
        title: String,
        detail: String,
        systemImage: String,
        isOn: Binding<Bool>
    ) -> some View {
        settingRow(title: title, detail: detail, systemImage: systemImage) {
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .tint(SettingsPalette.magic)
        }
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(SettingsPalette.gold.opacity(0.12))
            .frame(height: 1)
            .padding(.horizontal, 20)
    }

    private var drawingSurface: some View {
        ZStack {
            Color(red: 0.018, green: 0.021, blue: 0.03)
            grid

            Image("GateSealMechanism")
                .resizable()
                .scaledToFit()
                .opacity(0.045)
                .padding(18)
                .allowsHitTesting(false)

            RuneDrawingCanvas(
                inputPreference: appSettings.inputPreference,
                maximumStrokeCount: 2,
                controller: canvasController,
                strokes: $testStrokes,
                lastInputMethod: $lastInputMethod
            )
        }
        .frame(minHeight: 235, idealHeight: 275, maxHeight: 310)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .stroke(SettingsPalette.gold.opacity(0.38), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var inputConfirmationControls: some View {
        HStack(spacing: 16) {
            Label(inputMethodTitle, systemImage: inputMethodIcon)
                .foregroundStyle(SettingsPalette.secondary)

            Spacer(minLength: 16)

            Text("\(testStrokes.count) / 2획")
                .monospacedDigit()
                .foregroundStyle(SettingsPalette.magicBright)

            Button {
                gameFeedback.playInterface(.back, settings: appSettings.settings)
                canvasController.undoLastStroke()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .frame(width: 42, height: 36)
                    .background(SettingsPalette.panel.opacity(0.7))
                    .overlay {
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(SettingsPalette.gold.opacity(0.34), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
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
            "입력 대기"
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
        gameCenter.isAuthenticated
            ? "person.crop.circle.badge.checkmark"
            : "person.crop.circle.badge.xmark"
    }

    private func tutorialReplayButton(_ sequence: TutorialSequenceID) -> some View {
        let title = sequence.settingsTitle
        return Button {
            gameFeedback.playInterface(.select, settings: appSettings.settings)
            gameSession.send(.requestTutorialReplay(sequence))
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "book.closed")
                    .foregroundStyle(SettingsPalette.magicBright)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .foregroundStyle(SettingsPalette.body)
                    Text("다음 해당 장면에서 다시 안내")
                        .font(.caption)
                        .foregroundStyle(SettingsPalette.secondary)
                }

                Spacer()
                replayStatusIcon(sequence)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SettingsPalette.secondary)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 66)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) 다시 보기")
        .accessibilityHint("다음에 해당 장면에 들어가면 안내를 다시 표시합니다")
    }

    @ViewBuilder
    private func replayStatusIcon(_ sequence: TutorialSequenceID) -> some View {
        let progress = gameSession.progress.tutorialProgress
        if progress.requestedReplay == sequence {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(SettingsPalette.magicBright)
                .accessibilityLabel("다시 보기 예약됨")
        } else if progress.completedSequences.contains(sequence) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green.opacity(0.8))
                .accessibilityLabel("완료")
        } else if progress.skippedSequences.contains(sequence) {
            Image(systemName: "forward.end.circle")
                .foregroundStyle(SettingsPalette.secondary)
                .accessibilityLabel("건너뜀")
        }
    }
}

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case input
    case sound
    case display
    case tutorial
    case gameCenter

    var id: Self { self }

    var title: String {
        switch self {
        case .input: "입력 및 조작"
        case .sound: "소리와 반응"
        case .display: "화면 효과"
        case .tutorial: "튜토리얼"
        case .gameCenter: "Game Center"
        }
    }

    var detail: String {
        switch self {
        case .input: "마법진 입력 방식과 전투 패드 배치를 확인합니다"
        case .sound: "음향과 진동 피드백을 선택합니다"
        case .display: "움직임과 섬광 연출의 강도를 조정합니다"
        case .tutorial: "완료한 안내를 원하는 시점에 다시 예약합니다"
        case .gameCenter: "계정 연결 상태와 달성한 업적을 확인합니다"
        }
    }

    var icon: String {
        switch self {
        case .input: "pencil.and.scribble"
        case .sound: "speaker.wave.2"
        case .display: "sparkles"
        case .tutorial: "book.closed"
        case .gameCenter: "circle.hexagongrid"
        }
    }
}

private enum SettingsPalette {
    static let panel = Color(red: 0.032, green: 0.035, blue: 0.041)
    static let surface = Color(red: 0.052, green: 0.056, blue: 0.065)
    static let gold = Color(red: 0.62, green: 0.49, blue: 0.29)
    static let magic = Color(red: 0.46, green: 0.28, blue: 0.76)
    static let magicBright = Color(red: 0.72, green: 0.58, blue: 1.0)
    static let title = Color(red: 0.88, green: 0.84, blue: 0.75)
    static let body = Color.white.opacity(0.83)
    static let secondary = Color.white.opacity(0.52)
}

private extension TutorialSequenceID {
    var settingsTitle: String {
        switch self {
        case .floor10Intro: "10층 시작·기상 연출"
        case .floor10Investigation: "10층 탐색과 조사"
        case .afterglowDiscovery: "떨어진 두루마리 주문 학습"
        case .riftDiscovery: "이전 균열 절단 발견 안내"
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
