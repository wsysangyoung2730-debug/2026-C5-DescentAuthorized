import SwiftUI

struct DemoFlowView: View {
    @EnvironmentObject private var gameSession: GameSessionStore
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var gameFeedback: GameFeedbackManager

    let onExit: () -> Void
    let onSystemOverlayVisibilityChange: (Bool) -> Void

    @State private var isShowingPauseMenu = false
    @State private var isShowingSettings = false
    @State private var retryLoadingPresentation: SceneRetryLoadingPresentation?
    @State private var checkpointTravelTask: Task<Void, Never>?
    @State private var battleTutorialStep: TutorialCoachStep?
    @State private var isNarrativeAutoAdvanceEnabled = true
    @StateObject private var sceneController = RealitySceneController()

    private let topHUDRailSourceSize = CGSize(width: 1774, height: 887)
    private let leftHUDPlateSourceCenter = CGPoint(x: 109, y: 433.5)
    private let rightHUDPlateSourceCenter = CGPoint(x: 1665, y: 433.5)
    private let topBarButtonHitWidth: CGFloat = 112
    private let topBarButtonHitHeight: CGFloat = 92
    private let battlePlateToStatusSpacing: CGFloat = 14
    private let battlePlayerStatusLeadingRatio: CGFloat = 0.11
    private var topBarHeight: CGFloat {
        gameSession.battleState == nil ? 96 : 112
    }

    var body: some View {
        ZStack(alignment: .top) {
            if let floorSceneID = gameSession.presentation.floorSceneID {
                RealityStageView(
                    sceneID: floorSceneID,
                    cameraPreset: gameSession.presentation.cameraPreset,
                    erasureZones: gameSession.battleState?.activeErasureZones ?? [],
                    reducedMotion: appSettings.reducedMotion,
                    controller: sceneController
                )
            } else {
                Color.black.ignoresSafeArea()
            }

            if isPresentationReady {
                if showsFloor10Opening {
                    Floor10OpeningExperienceView(
                        sceneController: sceneController,
                        isSceneReady: isPresentationReady
                    )
                    .transition(.opacity)
                } else if isNarrativePresentation {
                    sceneView
                        .id(gameSession.presentation.progressSceneID)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 0) {
                        if !sceneController.isDescentFailurePresentationActive {
                            topBar
                                .frame(height: topBarHeight)
                                .clipped()
                                .transition(.opacity)
                        }

                        sceneView
                            .id(gameSession.presentation.progressSceneID)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .animation(
                        .easeOut(duration: appSettings.reducedMotion ? 0 : 0.24),
                        value: sceneController.isDescentFailurePresentationActive
                    )
                }
            }

            Color.black
                .opacity(sceneController.cameraFadeOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.18), value: sceneController.cameraFadeOpacity)

            if let loading = retryLoadingPresentation {
                ZStack {
                    LoadingScreenView(
                        context: loading.context,
                        progress: loading.progress,
                        tip: loading.tip
                    )

                    Color.clear
                        .contentShape(Rectangle())
                }
                .ignoresSafeArea()
                .transition(.opacity)
                .zIndex(50)
            }
        }
        .tutorialCoach(
            step: battleTutorialStep,
            onNext: advanceBattleTutorial,
            onSkip: skipBattleTutorial
        )
        .ignoresSafeArea(edges: .top)
        .sheet(isPresented: $isShowingPauseMenu) {
            PauseMenuView(
                onTravelToCheckpoint: { checkpoint in
                    beginCheckpointTravel(to: checkpoint)
                },
                onExitToTitle: onExit
            )
        }
        .fullScreenCover(isPresented: $isShowingSettings) {
            SettingsView()
        }
        .onAppear {
            reportSystemOverlayVisibility()
            synchronizeFloorMusic()
            synchronizeRecordsBattleTutorial()
        }
        .onDisappear {
            checkpointTravelTask?.cancel()
            checkpointTravelTask = nil
            onSystemOverlayVisibilityChange(false)
            gameFeedback.stopAllAudio()
        }
        .onChange(of: isShowingPauseMenu) { _, _ in
            reportSystemOverlayVisibility()
        }
        .onChange(of: isShowingSettings) { _, _ in
            reportSystemOverlayVisibility()
        }
        .onChange(of: gameSession.presentation.floorSceneID) { _, floorSceneID in
            if floorSceneID == nil {
                sceneController.unload()
            }
            synchronizeFloorMusic()
        }
        .onChange(of: sceneController.loadState) { _, _ in
            synchronizeFloorMusic()
        }
        .onChange(of: gameSession.progress.currentFloor) { _, _ in
            synchronizeFloorMusic()
        }
        .onChange(of: gameSession.progress.currentScene) { _, _ in
            synchronizeFloorMusic()
            synchronizeRecordsBattleTutorial()
        }
        .onChange(of: gameSession.eventSequence) { _, _ in
            synchronizeRecordsBattleTutorial()
        }
        .onChange(of: retryLoadingPresentation) { _, loading in
            if loading == nil {
                synchronizeFloorMusic()
            } else {
                gameFeedback.suspendMusicForLoading()
            }
        }
    }

    private func reportSystemOverlayVisibility() {
        onSystemOverlayVisibilityChange(isShowingPauseMenu || isShowingSettings)
    }

    private func beginCheckpointTravel(to checkpoint: CheckpointID) {
        checkpointTravelTask?.cancel()
        let context = checkpoint.loadingContext
        let tip = LoadingTipCatalog.randomTip(for: context)

        withAnimation(.easeInOut(duration: appSettings.reducedMotion ? 0 : 0.18)) {
            retryLoadingPresentation = SceneRetryLoadingPresentation(
                context: context,
                progress: 0.08,
                tip: tip
            )
        }

        checkpointTravelTask = Task { @MainActor in
            defer { checkpointTravelTask = nil }

            guard await waitForCheckpointTravel(milliseconds: 180) else { return }
            retryLoadingPresentation?.progress = 0.3

            gameSession.send(.travelToCheckpoint(checkpoint))
            guard gameSession.progress.checkpoint == checkpoint else {
                retryLoadingPresentation = nil
                return
            }

            sceneController.resetProgressionPresentation(
                reducedMotion: appSettings.reducedMotion
            )
            retryLoadingPresentation?.progress = 0.58

            for step in 0..<24 {
                guard !isCurrentSceneReady else { break }
                guard await waitForCheckpointTravel(milliseconds: 100) else { return }
                retryLoadingPresentation?.progress = min(0.92, 0.58 + Double(step + 1) * 0.014)
            }

            retryLoadingPresentation?.progress = 1
            guard await waitForCheckpointTravel(milliseconds: 180) else { return }
            withAnimation(.easeOut(duration: appSettings.reducedMotion ? 0 : 0.2)) {
                retryLoadingPresentation = nil
            }
        }
    }

    private var isCurrentSceneReady: Bool {
        guard let sceneID = gameSession.presentation.floorSceneID else { return true }
        return sceneController.isReady(
            sceneID: sceneID,
            cameraPreset: gameSession.presentation.cameraPreset
        )
    }

    private func waitForCheckpointTravel(milliseconds: Int) async -> Bool {
        let duration = appSettings.reducedMotion ? min(milliseconds, 60) : milliseconds
        do {
            try await Task.sleep(for: .milliseconds(duration))
            return !Task.isCancelled
        } catch {
            return false
        }
    }

    private func synchronizeFloorMusic() {
        let isFloorModelReady: Bool
        if let sceneID = gameSession.presentation.floorSceneID,
           case let .ready(readySceneID) = sceneController.loadState,
           readySceneID == sceneID {
            isFloorModelReady = true
        } else {
            isFloorModelReady = false
        }

        gameFeedback.synchronizeFloorMusic(
            floor: gameSession.progress.currentFloor,
            isPresentationReady: isFloorModelReady
                && retryLoadingPresentation == nil,
            keepsOutcomeMusic: keepsBattleOutcomeMusic,
            settings: appSettings.settings
        )
    }

    private func synchronizeRecordsBattleTutorial() {
        guard gameSession.progress.currentScene == .floor9RecordsBattle,
              gameSession.battleState != nil else {
            battleTutorialStep = nil
            return
        }

        let progress = gameSession.progress.tutorialProgress
        guard progress.shouldPresent(.recordsBattleBasics) else {
            battleTutorialStep = nil
            return
        }
        let step = progress.activeSequence == .recordsBattleBasics
            ? (progress.activeStep ?? .battlePlayerHP)
            : .battlePlayerHP
        if progress.activeSequence != .recordsBattleBasics {
            gameSession.send(.beginTutorial(sequence: .recordsBattleBasics, step: step))
        }
        battleTutorialStep = recordsBattleCoach(for: step)
    }

    private func recordsBattleCoach(for step: TutorialStepID) -> TutorialCoachStep? {
        switch step {
        case .battlePlayerHP:
            TutorialCoachStep(
                id: step,
                title: "전투 현황",
                message: "상단에서 전투의 전체 상태를 확인합니다. 왼쪽은 봉인관의 체력과 방벽, 가운데는 현재 턴, 오른쪽은 관리자의 체력과 방벽입니다. 방벽은 체력보다 먼저 피해를 흡수합니다.",
                targetIDs: ["battle.status"],
                placement: .bottom
            )
        case .battleTurnAndEnemyHP:
            // 이전 버전에서 이 단계에 머문 저장 데이터도 통합 안내로 안전하게 복구한다.
            TutorialCoachStep(
                id: step,
                title: "전투 현황",
                message: "상단에서 전투의 전체 상태를 확인합니다. 왼쪽은 봉인관의 체력과 방벽, 가운데는 현재 턴, 오른쪽은 관리자의 체력과 방벽입니다. 관리자 체력을 0으로 만들면 전투가 끝납니다.",
                targetIDs: ["battle.status"],
                placement: .bottom
            )
        case .battleIntent:
            TutorialCoachStep(
                id: step,
                title: "다음 행동 예고",
                message: "관리자 머리 위 심볼과 오른쪽 예고는 같은 행동을 가리킵니다. 붉은 공격은 일반 피해, 강하게 점멸하는 공격은 강공격, 푸른 방패는 일반 방벽, 금빛 방패는 절대 방벽, 보라색 예고는 다음 행동 준비입니다.",
                targetIDs: ["battle.next-action", "battle.intent-symbol"],
                placement: .bottom
            )
        case .battleResourcesAndSpells:
            TutorialCoachStep(
                id: step,
                title: "마나와 마법 선택",
                message: "마나는 선의 길이에 따라 줄고, 잔여 획은 이번 턴에 그릴 수 있는 횟수입니다. 아래 주문을 눌러 선택하고 길게 눌러 상세 정보를 확인할 수 있습니다.",
                targetIDs: ["battle.resources-and-spells"],
                placement: .top
            )
        case .battleInput:
            TutorialCoachStep(
                id: step,
                title: "문양 입력 패드",
                message: "선택한 주문의 시작점과 핵심점을 따라 문양을 그린 뒤 시전하십시오. 입력 중 예상 마나와 남은 획이 바로 반영됩니다.",
                targetIDs: ["battle.input"],
                placement: .top
            )
        case .battleLogAndEndTurn:
            TutorialCoachStep(
                id: step,
                title: "전투 기록과 턴 종료",
                message: "왼쪽 기록에서 피해와 방벽 변화를 확인합니다. 더 행동하지 않으려면 오른쪽 턴 종료를 눌러 관리자의 차례로 넘기십시오.",
                targetIDs: ["battle.log", "battle.turn-end"],
                placement: .top
            )
        default:
            nil
        }
    }

    private func advanceBattleTutorial() {
        guard let step = battleTutorialStep?.id else { return }
        let next: TutorialStepID?
        switch step {
        case .battlePlayerHP: next = .battleIntent
        case .battleTurnAndEnemyHP: next = .battleIntent
        case .battleIntent: next = .battleResourcesAndSpells
        case .battleResourcesAndSpells: next = .battleInput
        case .battleInput: next = .battleLogAndEndTurn
        case .battleLogAndEndTurn: next = nil
        default: next = nil
        }
        gameSession.send(.completeTutorialStep(step: step, next: next))
        if let next {
            battleTutorialStep = recordsBattleCoach(for: next)
        } else {
            gameSession.send(.completeTutorial(.recordsBattleBasics))
            battleTutorialStep = nil
        }
    }

    private func skipBattleTutorial() {
        gameSession.send(.skipTutorial(.recordsBattleBasics))
        battleTutorialStep = nil
    }

    private var keepsBattleOutcomeMusic: Bool {
        if gameSession.battleState?.phase == .defeat {
            return true
        }

        switch gameSession.progress.currentScene {
        case .floor9RecordsDefeated,
             .floor8ResidualDefeated,
             .floor8AdministratorDefeated:
            return true
        default:
            return false
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
        switch gameSession.presentation.experience {
        case .narrative, .reward:
            return true
        default:
            return false
        }
    }

    private var showsFloor10Opening: Bool {
        gameSession.progress.currentScene == .floor10MeetingRoom
            && gameSession.progress.tutorialProgress.shouldPresent(.floor10Intro)
    }

    private var descentTopHUDConfiguration: DescentTopHUDConfiguration? {
        if gameSession.progress.currentScene == .floor10DescentDoor {
            return DescentTopHUDConfiguration(
                areaTitle: "제10층 · 승인 관리 구역",
                inspectionTitle: "단일 문양 검수"
            )
        }

        guard case let .descent(floor) = gameSession.presentation.experience else {
            return nil
        }

        switch floor {
        case .floor10:
            return DescentTopHUDConfiguration(
                areaTitle: "제10층 · 승인 관리 구역",
                inspectionTitle: "단일 문양 검수"
            )
        case .floor9:
            return DescentTopHUDConfiguration(
                areaTitle: "제9층 · 기록 관리 구역",
                inspectionTitle: "이중 문양 검수"
            )
        case .floor8:
            return DescentTopHUDConfiguration(
                areaTitle: "제8층 · 관측 관리 구역",
                inspectionTitle: "이중 문양 검수"
            )
        case .floor7:
            return DescentTopHUDConfiguration(
                areaTitle: "제7층 · 미확인 구역",
                inspectionTitle: "봉인 문양 검수"
            )
        }
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

            if let battle = gameSession.battleState {
                battleTopBarControls(battle)
            } else {
                defaultTopBarControls
            }
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

    private var defaultTopBarControls: some View {
        GeometryReader { proxy in
            let leftHUDPlateCenter = topHUDRailPoint(
                sourcePoint: leftHUDPlateSourceCenter,
                in: proxy.size
            )
            let rightHUDPlateCenter = topHUDRailPoint(
                sourcePoint: rightHUDPlateSourceCenter,
                in: proxy.size
            )
            let topHUDCenterY = (leftHUDPlateCenter.y + rightHUDPlateCenter.y) / 2
            let sideLabelWidth = min(max(proxy.size.width * 0.2, 190), 270)
            let buttonHalfWidth = topBarButtonHitWidth / 2
            let topHUDConfiguration = descentTopHUDConfiguration
            let sideGap = max(14, proxy.size.width * 0.012)
                + (topHUDConfiguration?.sideGapAdjustment ?? 0)

            ZStack {
                if let configuration = topHUDConfiguration {
                    descentGateTitle
                        .frame(width: min(proxy.size.width * 0.36, 460), height: 72)
                        .position(
                            x: proxy.size.width * 0.5,
                            y: topHUDCenterY
                        )

                    descentAreaLabel(configuration.areaTitle)
                        .frame(width: sideLabelWidth, alignment: .leading)
                        .position(
                            x: leftHUDPlateCenter.x
                                + buttonHalfWidth
                                + sideGap
                                + (sideLabelWidth / 2),
                            y: topHUDCenterY
                        )

                    Text(configuration.inspectionTitle)
                    .font(.system(size: 15, weight: .medium, design: .serif))
                    .foregroundStyle(SharedHUDPalette.title.opacity(0.86))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .frame(width: sideLabelWidth, alignment: .trailing)
                    .position(
                        x: rightHUDPlateCenter.x
                            - buttonHalfWidth
                            - sideGap
                            - configuration.inspectionGapAdjustment
                            - (sideLabelWidth / 2),
                        y: topHUDCenterY
                    )
                } else {
                    FloorTitleAssetView(
                        floor: gameSession.progress.currentFloor,
                        size: .standard
                    )
                    .frame(width: min(proxy.size.width * 0.54, 560), height: 72)
                    .position(
                        x: proxy.size.width * 0.5,
                        y: topHUDCenterY
                    )
                }

                topBarButton(systemImage: "pause.fill") {
                    presentPauseMenu()
                }
                .help("일시정지")
                .accessibilityLabel("일시정지")
                .position(
                    x: leftHUDPlateCenter.x,
                    y: leftHUDPlateCenter.y
                )

                topBarButton(systemImage: "gearshape") {
                    presentSettings()
                }
                .help("설정")
                .accessibilityLabel("설정")
                .position(
                    x: rightHUDPlateCenter.x,
                    y: rightHUDPlateCenter.y
                )
            }
        }
    }

    private var descentGateTitle: some View {
        Image("SharedDescentGateTitle")
            .resizable()
            .scaledToFit()
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("층 이동 봉인문")
    }

    private func descentAreaLabel(_ title: String) -> some View {
        HStack(spacing: 9) {
            Image("SharedDescentGateSymbol")
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 44)

            Text(title)
                .font(.system(size: 15, weight: .medium, design: .serif))
                .foregroundStyle(SharedHUDPalette.title.opacity(0.86))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }

    private func battleTopBarControls(_ battle: BattleState) -> some View {
        GeometryReader { proxy in
            let leftHUDPlateCenter = topHUDRailPoint(
                sourcePoint: leftHUDPlateSourceCenter,
                in: proxy.size
            )
            let rightHUDPlateCenter = topHUDRailPoint(
                sourcePoint: rightHUDPlateSourceCenter,
                in: proxy.size
            )
            let topHUDCenterY = (leftHUDPlateCenter.y + rightHUDPlateCenter.y) / 2
            let buttonHalfWidth = topBarButtonHitWidth / 2
            let leftPauseRightX = leftHUDPlateCenter.x + buttonHalfWidth
            let battleTrailingPadding = leftPauseRightX + battlePlateToStatusSpacing
            let playerStatusLeadingX = proxy.size.width * battlePlayerStatusLeadingRatio
            let statusAreaWidth = max(
                proxy.size.width - playerStatusLeadingX - battleTrailingPadding,
                0
            )
            let statusAreaCenterX = playerStatusLeadingX + (statusAreaWidth / 2)
            let statusAreaHeight = min(proxy.size.height * 0.82, 92)

            ZStack {
                BattleTopHUDView(
                    battle: battle,
                    floor: gameSession.progress.currentFloor,
                    enemyToNextActionSpacing: battlePlateToStatusSpacing
                )
                .frame(
                    width: statusAreaWidth,
                    height: statusAreaHeight,
                    alignment: .center
                )
                .position(
                    x: statusAreaCenterX,
                    y: topHUDCenterY
                )

                topBarButton(systemImage: "pause.fill") {
                    presentPauseMenu()
                }
                .help("일시정지")
                .accessibilityLabel("일시정지")
                .position(
                    x: leftHUDPlateCenter.x,
                    y: leftHUDPlateCenter.y
                )

                topBarButton(systemImage: "gearshape") {
                    presentSettings()
                }
                .help("설정")
                .accessibilityLabel("설정")
                .position(
                    x: rightHUDPlateCenter.x,
                    y: rightHUDPlateCenter.y
                )
            }
        }
    }

    private func topHUDRailPoint(
        sourcePoint: CGPoint,
        in destinationSize: CGSize
    ) -> CGPoint {
        let scale = max(
            destinationSize.width / topHUDRailSourceSize.width,
            destinationSize.height / topHUDRailSourceSize.height
        )
        let scaledSize = CGSize(
            width: topHUDRailSourceSize.width * scale,
            height: topHUDRailSourceSize.height * scale
        )
        let cropOffset = CGPoint(
            x: (scaledSize.width - destinationSize.width) / 2,
            y: (scaledSize.height - destinationSize.height) / 2
        )

        return CGPoint(
            x: sourcePoint.x * scale - cropOffset.x,
            y: sourcePoint.y * scale - cropOffset.y
        )
    }

    private func topBarButton(
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(SharedHUDPalette.icon)
                .frame(
                    width: topBarButtonHitWidth,
                    height: topBarButtonHitHeight
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func presentPauseMenu() {
        gameFeedback.playInterface(.select, settings: appSettings.settings)
        isShowingPauseMenu = true
    }

    private func presentSettings() {
        gameFeedback.playInterface(.select, settings: appSettings.settings)
        isShowingSettings = true
    }

    @ViewBuilder
    private var sceneView: some View {
        switch gameSession.presentation.experience {
        case .floor10Tutorial:
            Floor10TutorialView(
                sceneController: sceneController,
                retryLoadingPresentation: $retryLoadingPresentation
            )
        case .floor9Entrance:
            Floor9EntranceView(sceneController: sceneController)
        case let .narrative(sequence):
            BossNarrativeView(
                sequence: sequence,
                isAutoAdvanceEnabled: $isNarrativeAutoAdvanceEnabled
            ) {
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
            BattleView(
                realityController: sceneController,
                restartLoadingPresentation: $retryLoadingPresentation
            )
        case let .reward(floor):
            RewardSelectionView(floor: floor, sceneController: sceneController)
        case .floor8Exploration:
            Floor8ExplorationView(sceneController: sceneController)
        case let .descent(floor):
            if floor == .floor9 {
                Floor9DescentDoorView(
                    sceneController: sceneController,
                    retryLoadingPresentation: $retryLoadingPresentation
                )
            } else {
                Floor8DescentDoorView(
                    sceneController: sceneController,
                    retryLoadingPresentation: $retryLoadingPresentation
                )
            }
        case .completion:
            DemoCompleteView(onReturnToTitle: onExit)
        }
    }
}

private extension CheckpointID {
    var loadingContext: LoadingScreenContext {
        switch self {
        case .floor10Start:
            .floor10
        case .floor10Complete, .recordsBattle, .recordsDefeated:
            .floor9
        case .floor8Start, .residualBattle, .residualDefeated,
             .observationBattle, .observationDefeated, .demoComplete:
            .floor8
        }
    }
}

private struct DescentTopHUDConfiguration {
    let areaTitle: String
    let inspectionTitle: String
    let sideGapAdjustment: CGFloat
    let inspectionGapAdjustment: CGFloat

    init(
        areaTitle: String,
        inspectionTitle: String,
        sideGapAdjustment: CGFloat = 10,
        inspectionGapAdjustment: CGFloat = 12
    ) {
        self.areaTitle = areaTitle
        self.inspectionTitle = inspectionTitle
        self.sideGapAdjustment = sideGapAdjustment
        self.inspectionGapAdjustment = inspectionGapAdjustment
    }
}

private struct BossNarrativeView: View {
    @EnvironmentObject private var appSettings: AppSettings

    let sequence: BossNarrativeSequence
    @Binding var isAutoAdvanceEnabled: Bool
    let onFinished: () -> Void

    @State private var dialogueIndex = 0

    var body: some View {
        ZStack {
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
            .accessibilityLabel("\(currentDialogue.speaker). \(currentDialogue.text)")
            .accessibilityHint(dialogueIndex == sequence.dialogues.count - 1 ? sequence.finalAccessibilityHint : "다음 대화")

            autoAdvanceControl
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 102)
                .padding(.bottom, 70)
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .task(id: autoAdvanceTaskID) {
            await scheduleAutoAdvanceIfNeeded()
        }
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
            .padding(.trailing, 198)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, minHeight: 148, maxHeight: 148)
    }

    private var autoAdvanceControl: some View {
        Button {
            withAnimation(.easeInOut(duration: appSettings.reducedMotion ? 0 : 0.18)) {
                isAutoAdvanceEnabled.toggle()
            }
        } label: {
            HStack(spacing: 9) {
                if isAutoAdvanceEnabled {
                    AutoAdvanceSpinner(reducedMotion: appSettings.reducedMotion)
                } else {
                    Image(systemName: "hand.tap")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 22, height: 22)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("자동 진행")
                        .font(.system(size: 13, weight: .semibold, design: .serif))
                    Text(isAutoAdvanceEnabled ? "켜짐" : "꺼짐 · 수동")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(BossNarrativePalette.prompt)
                }
            }
            .foregroundStyle(isAutoAdvanceEnabled ? BossNarrativePalette.speaker : BossNarrativePalette.dialogue)
            .frame(width: 142, height: 42)
            .background(Color.black.opacity(0.62))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        isAutoAdvanceEnabled
                            ? BossNarrativePalette.speaker.opacity(0.72)
                            : BossNarrativePalette.counter.opacity(0.5),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("대화 자동 진행")
        .accessibilityValue(isAutoAdvanceEnabled ? "켜짐" : "꺼짐")
        .accessibilityHint(isAutoAdvanceEnabled ? "두 번 탭하여 수동 진행으로 전환" : "두 번 탭하여 자동 진행 켜기")
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

    private var autoAdvanceTaskID: Int {
        dialogueIndex * 2 + (isAutoAdvanceEnabled ? 1 : 0)
    }

    private var autoAdvanceDelay: Duration {
        let readingTime = min(max(Double(currentDialogue.text.count) * 0.035, 0.8), 2.3)
        return .seconds(3.2 + readingTime)
    }

    @MainActor
    private func scheduleAutoAdvanceIfNeeded() async {
        guard isAutoAdvanceEnabled else { return }
        let scheduledIndex = dialogueIndex

        do {
            try await Task.sleep(for: autoAdvanceDelay)
        } catch {
            return
        }

        guard !Task.isCancelled,
              isAutoAdvanceEnabled,
              scheduledIndex == dialogueIndex else { return }
        advance()
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

private struct AutoAdvanceSpinner: View {
    let reducedMotion: Bool

    @State private var rotation = 0.0

    var body: some View {
        ZStack {
            Circle()
                .stroke(BossNarrativePalette.speaker.opacity(0.2), lineWidth: 2)

            Circle()
                .trim(from: 0.08, to: 0.76)
                .stroke(
                    BossNarrativePalette.speaker,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )

            Image(systemName: "arrowtriangle.forward.fill")
                .font(.system(size: 5, weight: .bold))
                .offset(x: 8.5, y: -3.5)
        }
        .frame(width: 22, height: 22)
        .rotationEffect(.degrees(rotation))
        .shadow(color: BossNarrativePalette.speaker.opacity(0.55), radius: 4)
        .onAppear {
            guard !reducedMotion else { return }
            withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                rotation = 360
            }
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
