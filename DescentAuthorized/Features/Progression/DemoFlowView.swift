import SwiftUI

struct DemoFlowView: View {
    @EnvironmentObject private var gameSession: GameSessionStore

    let onExit: () -> Void

    @State private var isShowingPauseMenu = false
    @State private var isShowingSettings = false
    @StateObject private var sceneController = RealitySceneController()

    private let topBarHeight: CGFloat = 96

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
                if isNarrativePresentation {
                    sceneView
                        .id(gameSession.presentation.progressSceneID)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 0) {
                        topBar
                            .frame(height: topBarHeight)
                            .clipped()

                        sceneView
                            .id(gameSession.presentation.progressSceneID)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }

            Color.black
                .opacity(sceneController.cameraFadeOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.18), value: sceneController.cameraFadeOpacity)
        }
        .ignoresSafeArea(edges: .top)
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

    private var isNarrativePresentation: Bool {
        if case .narrative = gameSession.presentation.experience {
            return true
        }
        return false
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

            topBarControls
        }
        .frame(height: topBarHeight)
        .clipped()
        .background {
            DAColor.background
                .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SharedHUDPalette.brass.opacity(0.45))
                .frame(height: 1)
        }
    }

    private var topBarControls: some View {
        HStack(alignment: .center, spacing: 18) {
            topBarButton(systemImage: "pause.fill") {
                isShowingPauseMenu = true
            }
            .help("일시정지")
            .accessibilityLabel("일시정지")

            Spacer(minLength: 20)

            HStack(spacing: 11) {
                floorOrnament

                Text("제\(gameSession.progress.currentFloor.rawValue)층")
                    .font(.system(size: 24, weight: .medium, design: .serif))
                    .foregroundStyle(SharedHUDPalette.title)
                    .shadow(color: SharedHUDPalette.brass.opacity(0.34), radius: 4)

                floorOrnament
                    .scaleEffect(x: -1, y: 1)
            }
            .frame(height: 58)

            Spacer(minLength: 20)

            topBarButton(systemImage: "gearshape") {
                isShowingSettings = true
            }
            .help("설정")
            .accessibilityLabel("설정")
        }
        .padding(.horizontal, 54)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .offset(y: -3)
    }

    private var floorOrnament: some View {
        Image("SharedFloorOrnament")
            .resizable()
            .scaledToFill()
            .frame(width: 96, height: 26)
            .clipped()
            .blendMode(.screen)
            .compositingGroup()
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
                    .frame(width: 68, height: 58)
                    .clipped()
                    .blendMode(.screen)
                    .compositingGroup()

                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(SharedHUDPalette.icon)
            }
            .frame(width: 68, height: 58)
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
        case let .narrative(sequence):
            BossNarrativeView(sequence: sequence) {
                switch sequence {
                case .floor9Encounter:
                    gameSession.send(.beginRecordsBattle)
                case .floor9Defeated:
                    gameSession.send(.continueAfterRecordsDefeat)
                case .floor8ResidualEncounter:
                    gameSession.send(.beginResidualBattle)
                case .floor8ResidualDefeated:
                    gameSession.send(.continueAfterResidualDefeat)
                case .floor8AdministratorEncounter:
                    gameSession.send(.beginAdministratorBattle)
                case .floor8AdministratorDefeated:
                    gameSession.send(.continueAfterAdministratorDefeat)
                }
            }
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

private struct BossNarrativeView: View {
    @EnvironmentObject private var appSettings: AppSettings

    let sequence: BossNarrativeSequence
    let onFinished: () -> Void

    @State private var dialogueIndex = 0

    var body: some View {
        Button(action: advance) {
            ZStack {
                Image(sequence.backgroundAsset)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.12), .black.opacity(0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                VStack(spacing: 8) {
                    Spacer()
                    dialoguePanel
                    recordCounter
                }
                .padding(.horizontal, 68)
                .padding(.bottom, 22)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .accessibilityLabel("\(currentDialogue.speaker). \(currentDialogue.text)")
        .accessibilityHint(dialogueIndex == sequence.dialogues.count - 1 ? sequence.finalAccessibilityHint : "다음 대화")
    }

    private var dialoguePanel: some View {
        ZStack(alignment: .leading) {
            Image("BossDialoguePanel")
                .resizable()
                .scaledToFill()
                .frame(height: 148)
                .clipped()

            VStack(alignment: .leading, spacing: 14) {
                Text(currentDialogue.speaker)
                    .font(.system(size: 17, weight: .semibold, design: .serif))
                    .foregroundStyle(BossNarrativePalette.speaker)

                Text(currentDialogue.text)
                    .font(.system(size: 20, weight: .regular, design: .serif))
                    .foregroundStyle(BossNarrativePalette.dialogue)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .id(dialogueIndex)
            .transition(.opacity)
            .padding(.leading, 58)
            .padding(.trailing, 190)

            HStack(spacing: 10) {
                Text("탭하여 계속")
                    .font(.caption)
                    .foregroundStyle(BossNarrativePalette.prompt)

                Image(systemName: "diamond.fill")
                    .font(.caption)
                    .foregroundStyle(BossNarrativePalette.speaker)
                    .shadow(color: BossNarrativePalette.speaker, radius: 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 34)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, minHeight: 148, maxHeight: 148)
    }

    private var recordCounter: some View {
        HStack(spacing: 9) {
            Image(systemName: "sparkle")
                .font(.caption2)
            Text("\(sequence.recordTitle)  \(dialogueIndex + 1) / \(sequence.dialogues.count)")
                .font(.caption.monospaced())
            Image(systemName: "sparkle")
                .font(.caption2)
        }
        .foregroundStyle(BossNarrativePalette.counter)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 4)
    }

    private var currentDialogue: BossNarrativeDialogue {
        sequence.dialogues[dialogueIndex]
    }

    private func advance() {
        guard dialogueIndex < sequence.dialogues.count - 1 else {
            onFinished()
            return
        }

        withAnimation(.easeInOut(duration: appSettings.reducedMotion ? 0 : 0.2)) {
            dialogueIndex += 1
        }
    }
}

private struct BossNarrativeDialogue {
    let speaker: String
    let text: String
}

private extension BossNarrativeSequence {
    var backgroundAsset: String {
        switch self {
        case .floor9Encounter: "Floor9AdministratorEncounter"
        case .floor9Defeated: "Floor9AdministratorDefeated"
        case .floor8ResidualEncounter: "Floor8ResidualEncounter"
        case .floor8ResidualDefeated: "Floor8ResidualDefeated"
        case .floor8AdministratorEncounter: "Floor8AdministratorEncounter"
        case .floor8AdministratorDefeated: "Floor8AdministratorDefeated"
        }
    }

    var recordTitle: String {
        switch self {
        case .floor9Encounter, .floor8ResidualEncounter, .floor8AdministratorEncounter: "조우 기록"
        case .floor9Defeated, .floor8ResidualDefeated, .floor8AdministratorDefeated: "처치 기록"
        }
    }

    var finalAccessibilityHint: String {
        switch self {
        case .floor9Encounter, .floor8ResidualEncounter, .floor8AdministratorEncounter: "전투 시작"
        case .floor9Defeated: "두루마리 선택으로 이동"
        case .floor8ResidualDefeated: "관측 본실 봉인문으로 이동"
        case .floor8AdministratorDefeated: "두루마리 선택으로 이동"
        }
    }

    var dialogues: [BossNarrativeDialogue] {
        switch self {
        case .floor9Encounter:
            [
                .init(speaker: "기록 관리자", text: "“하강 승인서에 서명이 없군. 절차를 다시 밟도록.”"),
                .init(speaker: "기록 관리자", text: "“성명 조회 실패. 기억침식 대상 가능성 있음.”"),
                .init(speaker: "기록 관리자", text: "“대상을 신규 기록으로 분류합니다. 분류 완료 후—말소합니다.”")
            ]
        case .floor9Defeated:
            [
                .init(speaker: "기록 관리자", text: "“기록 복원 불가. 말소 절차를… 종료합니다.”"),
                .init(speaker: "기록 관리자", text: "“당신의 필체가 남아 있습니다. 최초 승인자와… 일치…”"),
                .init(speaker: "주인공", text: "“최초 승인자… 내가 이 절차를 승인했다는 뜻인가.”")
            ]
        case .floor8ResidualEncounter:
            [
                .init(speaker: "관측 잔류체", text: "“관… 측… 초점… 불일치… 대상… 없음… 그런데… 왜… 보이지…?”")
            ]
        case .floor8ResidualDefeated:
            [
                .init(speaker: "관측 잔류체", text: "“초점… 붕괴… 관측… 실패… 좌표… 전송… 불가…”")
            ]
        case .floor8AdministratorEncounter:
            [
                .init(speaker: "관측 관리자", text: "“관측 기준점 고정. 미등록 하강자의 진입을 확인했습니다.”"),
                .init(speaker: "관측 관리자", text: "“대상의 현재 좌표와 관측 기록이 일치하지 않습니다. 오염 변수로 재분류합니다.”"),
                .init(speaker: "관측 관리자", text: "“관측 차폐막을 전개합니다. 기준에서 벗어난 존재는—시야에서 제거합니다.”")
            ]
        case .floor8AdministratorDefeated:
            [
                .init(speaker: "관측 관리자", text: "“관측 기준점 붕괴… 차폐 절차를 유지할 수 없습니다.”"),
                .init(speaker: "관측 관리자", text: "“최초 관측 기록 복원… 관측자 식별값이 당신과… 일치합니다.”"),
                .init(speaker: "주인공", text: "“최초 관측자… 승인하기 전부터 내가 제0균열을 보고 있었다는 건가.”")
            ]
        }
    }
}

private enum BossNarrativePalette {
    static let speaker = Color(red: 190 / 255, green: 142 / 255, blue: 1)
    static let dialogue = Color(red: 232 / 255, green: 229 / 255, blue: 224 / 255)
    static let prompt = Color(red: 166 / 255, green: 163 / 255, blue: 166 / 255)
    static let counter = Color(red: 196 / 255, green: 184 / 255, blue: 160 / 255)
}

private enum SharedHUDPalette {
    static let brass = Color(red: 184 / 255, green: 139 / 255, blue: 77 / 255)
    static let title = Color(red: 225 / 255, green: 202 / 255, blue: 164 / 255)
    static let icon = Color(red: 222 / 255, green: 216 / 255, blue: 202 / 255)
}
