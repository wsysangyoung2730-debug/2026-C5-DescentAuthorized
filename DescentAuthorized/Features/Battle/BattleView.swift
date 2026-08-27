import SwiftUI

private struct BattleUICombatantState {
    let name: String
    let hp: Int
    let maxHP: Int
    let normalBarrier: Int
    let absoluteBarrierCharges: Int

    init(_ combatant: CombatantState) {
        name = combatant.name
        hp = combatant.hp
        maxHP = combatant.maxHP
        normalBarrier = combatant.normalBarrier
        absoluteBarrierCharges = combatant.absoluteBarrierCharges
    }
}

private struct BattleUIResourceState {
    let mana: Double
    let maximumMana: Double
    let strokes: Int
    let maximumStrokes: Int
}

private struct BattleUISpellState: Identifiable {
    let spell: SpellDefinition
    let isSelected: Bool
    let isAffordable: Bool
    let isPermitted: Bool
    let canInteract: Bool

    var id: SpellID { spell.id }

    var visualState: BattleSpellCardVisualState {
        guard canInteract else { return .disabled }
        return isSelected ? .selected : .available
    }
}

private enum BattleSpellCardVisualState {
    case available
    case selected
    case disabled

    var overlayAssetName: String? {
        switch self {
        case .available: nil
        case .selected: "BattleCardFrameSelected"
        case .disabled: "BattleCardFrameDisabled"
        }
    }
}

private struct BattleTurnEndButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            Image(backgroundAssetName(isPressed: configuration.isPressed))
                .resizable()
                .scaledToFill()

            configuration.label
                .foregroundStyle(isEnabled ? DAColor.body : DAColor.secondary)
        }
        .contentShape(Rectangle())
    }

    private func backgroundAssetName(isPressed: Bool) -> String {
        guard isEnabled else { return "BattleTurnEndDisabled" }
        return isPressed ? "BattleTurnEndPressed" : "BattleTurnEndDefault"
    }
}

private extension SpellDefinition {
    var battleCardFrameAssetName: String {
        switch category {
        case .attack: "BattleCardFrameAttack"
        case .defense: "BattleCardFrameDefense"
        case .dispel: "BattleCardFrameSeal"
        }
    }

    var battleGlyphAssetName: String {
        switch id {
        case .afterglowErasure: "BattleGlyphAfterglowErasure"
        case .riftSeverance: "BattleGlyphRiftSeverance"
        case .barrierPiercing: "BattleGlyphBarrierPiercing"
        case .basicBarrier: "BattleGlyphBasicBarrier"
        case .sealRelease: "BattleGlyphSealRelease"
        }
    }

    var battleScrollBadgeAssetName: String {
        switch tier {
        case .worn: "BattleScrollBadgeWorn"
        case .engraved: "BattleScrollBadgeEngraved"
        case .sealed: "BattleScrollBadgeSealed"
        case .forbidden: "BattleScrollBadgeForbidden"
        }
    }

    var battleScrollTierTitle: String {
        switch tier {
        case .worn: "낡은 주문서"
        case .engraved: "각인 주문서"
        case .sealed: "봉인 주문서"
        case .forbidden: "금서"
        }
    }

    var battleEffectRangeTitle: String {
        let range = effect.range
        switch category {
        case .attack: return "공격 \(range.lowerBound)~\(range.upperBound)"
        case .defense: return "방벽 \(range.lowerBound)~\(range.upperBound)"
        case .dispel: return "해제 \(range.lowerBound)~\(range.upperBound)"
        }
    }

    var battleCategoryTitle: String {
        switch category {
        case .attack: return "공격"
        case .defense: return "방어"
        case .dispel: return "해제"
        }
    }

    var battleDetailEffectTitle: String {
        switch category {
        case .attack: return "피해"
        case .defense: return "방벽"
        case .dispel: return "해제 횟수"
        }
    }

    var battleDifficultyTitle: String {
        switch glyph.difficulty {
        case .easy: return "하"
        case .normal: return "중"
        case .hard: return "상"
        }
    }

    var battleRequiredPointTitle: String {
        guard let firstStroke = glyph.strokes.first else { return "-" }
        let nodes = firstStroke.requiredNodes.indices.map { "N\($0 + 1)" }
        return (["S"] + nodes + ["E"]).joined(separator: " · ")
    }

    var battleToleranceTitle: String {
        let tolerance = glyph.strokes
            .map { max($0.nodeRadius, $0.pathRadius) }
            .max() ?? 0
        return "±\(Int(tolerance.rounded()))%"
    }

    var battleDetailDescription: String {
        switch id {
        case .afterglowErasure:
            return "잔류 관측광을 지워 대상에게 피해를 줍니다."
        case .riftSeverance:
            return "균열을 절단해 대상에게 강한 피해를 줍니다."
        case .barrierPiercing:
            return "일반 방벽을 관통하고 제거한 뒤 대상에게 피해를 줍니다."
        case .basicBarrier:
            return "봉인관에게 피해를 흡수하는 일반 방벽을 부여합니다."
        case .sealRelease:
            return "대상에게 적용된 절대 방벽의 충전을 해제합니다."
        }
    }
}

private struct BattleUIPresentation {
    let phase: BattlePhase
    let turnNumber: Int
    let player: BattleUICombatantState
    let enemy: BattleUICombatantState
    let resources: BattleUIResourceState
    let currentEnemyIntent: EnemyAction?
    let activeErasureZones: [ErasureZone]
    let castsThisTurn: [SpellID]
    let spells: [BattleUISpellState]
    let recentLogEntries: [String]

    var selectedSpell: SpellDefinition? {
        spells.first(where: \.isSelected)?.spell
    }
}

struct BattleRestartLoadingPresentation: Equatable {
    let context: LoadingScreenContext
    var progress: Double
    let tip: String
}

struct BattleView: View {
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var gameSession: GameSessionStore
    @ObservedObject var realityController: RealitySceneController
    @Binding var restartLoadingPresentation: BattleRestartLoadingPresentation?

    @State private var selectedSpellID: SpellID?
    @State private var enemyHitFlash = false
    @State private var playerHitFlash = false
    @State private var strongAttackFlash = false
    @State private var feedbackText: String?
    @State private var feedbackColor = Color.white
    @State private var showsFirstTurnBriefing = false
    @State private var didExperienceAbsoluteBarrier = false
    @State private var enemyPulseTask: Task<Void, Never>?
    @State private var playerPulseTask: Task<Void, Never>?
    @State private var feedbackTask: Task<Void, Never>?
    @State private var battleLogEntries: [String] = []
    @State private var lastLoggedEventSequence: UInt64?
    @State private var previewMana: Double?
    @State private var previewStrokes: Int?
    @State private var detailedSpell: SpellDefinition?
    @State private var detailPressTask: Task<Void, Never>?
    @State private var pressedSpellID: SpellID?
    @State private var detailPressWasCancelled = false
    @State private var isCameraLooking = false
    @State private var isCameraZooming = false
    @State private var cameraLookTranslationOrigin: CGSize?
    @State private var isDefeatPanelVisible = false
    @State private var defeatPresentationTask: Task<Void, Never>?
    @State private var restartTask: Task<Void, Never>?

    private var isRestartLoading: Bool {
        restartLoadingPresentation != nil
    }

    var body: some View {
        ZStack {
            if realitySceneID != nil {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            } else {
                battleBackground
            }

            if let battle = gameSession.battleState {
                battleContent(presentation(for: battle))
            } else {
                encounterStandby
            }

            Color.red
                .opacity(playerHitFlash ? (appSettings.reducedFlashes ? 0.08 : 0.24) : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            if strongAttackFlash && !appSettings.reducedFlashes {
                Rectangle()
                    .stroke(Color.red.opacity(0.85), lineWidth: 8)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            if let feedbackText {
                castFeedback(text: feedbackText, color: feedbackColor)
                    .transition(.scale.combined(with: .opacity))
                    .allowsHitTesting(false)
            }

            if let detailedSpell {
                spellDetailOverlay(detailedSpell)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    .zIndex(20)
            }

            if showsFirstTurnBriefing {
                battleBriefing
                    .transition(.opacity)
            }

            if gameSession.battleState?.phase == .defeat,
               isDefeatPanelVisible {
                defeatOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    .zIndex(30)
            }

        }
        .task(id: gameSession.progress.currentScene) {
            battleLogEntries = []
            lastLoggedEventSequence = nil
            previewMana = nil
            previewStrokes = nil
            detailedSpell = nil
            startEncounterIfNeeded()
            appendBattleLog(
                gameSession.latestEvents,
                sequence: gameSession.eventSequence
            )
            selectAvailableSpell()
            if shouldShowFirstTurnBriefing,
               gameSession.battleState?.turnNumber == 1 {
                showsFirstTurnBriefing = true
            }
            realityController.synchronizeCombatState(
                gameSession.battleState,
                reducedMotion: appSettings.reducedMotion
            )
            realityController.resetProgressionPresentation(reducedMotion: appSettings.reducedMotion)
            realityController.setBattleCameraInteractionEnabled(isBattleScene)
            if isBattleScene {
                realityController.resetBattleCamera(animated: false)
            }
            updateDefeatPresentation(for: gameSession.battleState?.phase)
        }
        .onChange(of: gameSession.eventSequence) { _, _ in
            appendBattleLog(
                gameSession.latestEvents,
                sequence: gameSession.eventSequence
            )
            present(gameSession.latestEvents)
            selectAvailableSpell()
            autoFinishPlayerTurnIfNeeded()
            updateDefeatPresentation(for: gameSession.battleState?.phase)
        }
        .onDisappear {
            enemyPulseTask?.cancel()
            playerPulseTask?.cancel()
            feedbackTask?.cancel()
            detailPressTask?.cancel()
            defeatPresentationTask?.cancel()
            defeatPresentationTask = nil
            restartTask?.cancel()
            restartTask = nil
            isCameraLooking = false
            isCameraZooming = false
            cameraLookTranslationOrigin = nil
            isDefeatPanelVisible = false
            restartLoadingPresentation = nil
            realityController.setBattleCameraInteractionEnabled(false)
        }
        .preferredColorScheme(.dark)
    }

    private func battleContent(_ presentation: BattleUIPresentation) -> some View {
        GeometryReader { proxy in
            let isDefeated = presentation.phase == .defeat
            let bottomBarHeight: CGFloat = isDefeated ? 0 : 242
            let horizontalContentInset: CGFloat = 18
            let contentWidth = max(0, proxy.size.width - (horizontalContentInset * 2))
            let inputPanelWidth = min(520, max(390, contentWidth * 0.36))
            let inputPanelHeight = min(390, max(280, inputPanelWidth * 0.76))
            let stageHeight = proxy.size.height - bottomBarHeight
            let inputPanelCenterY = min(
                stageHeight * 0.55,
                stageHeight - (inputPanelHeight / 2) - 12
            )

            ZStack(alignment: .bottom) {
                enemyStage(presentation)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, bottomBarHeight)

                if !isDefeated {
                    if isBattleScene, realitySceneID != nil {
                        battleCameraInteractionSurface(
                            viewportSize: CGSize(
                                width: contentWidth,
                                height: max(stageHeight, 1)
                            )
                        )
                        .frame(width: contentWidth, height: max(stageHeight, 1))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }

                    if isBattleScene,
                       realitySceneID != nil,
                       realityController.isBattleCameraAdjusted {
                        battleCameraResetButton
                            .padding(.top, 14)
                            .padding(.trailing, 16)
                            .frame(
                                width: contentWidth,
                                height: max(stageHeight, 1),
                                alignment: .topTrailing
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .transition(.opacity.combined(with: .scale(scale: 0.94)))
                            .zIndex(4)
                    }

                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: Color.black.opacity(0.16), location: 0.34),
                            .init(color: Color.black.opacity(0.68), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: bottomBarHeight + 74)
                    .allowsHitTesting(false)

                    glyphInputPanel(presentation)
                        .frame(width: inputPanelWidth, height: inputPanelHeight)
                        .position(
                            x: inputPanelX(
                                availableWidth: contentWidth,
                                panelWidth: inputPanelWidth
                            ),
                            y: inputPanelCenterY
                        )

                    spellBar(presentation)
                        .frame(height: 218)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                }
            }
            .overlay {
                Rectangle()
                    .stroke(DAColor.gold.opacity(0.28), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, horizontalContentInset)
            .padding(.vertical, 10)
        }
    }

    private func battleCameraInteractionSurface(viewportSize: CGSize) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        guard !isCameraZooming else { return }
                        if !isCameraLooking {
                            isCameraLooking = true
                            cameraLookTranslationOrigin = value.translation
                            realityController.beginBattleCameraLook()
                        }
                        let origin = cameraLookTranslationOrigin ?? .zero
                        realityController.updateBattleCameraLook(
                            translation: CGSize(
                                width: value.translation.width - origin.width,
                                height: value.translation.height - origin.height
                            ),
                            viewportSize: viewportSize
                        )
                    }
                    .onEnded { _ in
                        isCameraLooking = false
                        cameraLookTranslationOrigin = nil
                    }
            )
            .simultaneousGesture(
                MagnifyGesture(minimumScaleDelta: 0.01)
                    .onChanged { value in
                        if !isCameraZooming {
                            isCameraZooming = true
                            isCameraLooking = false
                            cameraLookTranslationOrigin = nil
                            realityController.beginBattleCameraZoom()
                        }
                        realityController.updateBattleCameraZoom(
                            magnification: value.magnification
                        )
                    }
                    .onEnded { _ in
                        isCameraZooming = false
                    }
            )
            .accessibilityHidden(true)
    }

    private var battleCameraResetButton: some View {
        Button {
            withAnimation(.easeOut(duration: appSettings.reducedMotion ? 0 : 0.18)) {
                realityController.resetBattleCamera(animated: !appSettings.reducedMotion)
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "viewfinder")
                Text("기본 시점")
            }
            .font(.system(size: 13, weight: .semibold, design: .serif))
            .foregroundStyle(DAColor.body)
            .padding(.horizontal, 13)
            .frame(height: 38)
            .background(Color.black.opacity(0.76))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(DAColor.gold.opacity(0.72), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.55), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("전투 카메라 기본 시점으로 복귀")
        .accessibilityHint("블렌더에 저장된 전투 시점으로 돌아갑니다")
    }

    @ViewBuilder
    private func glyphInputPanel(_ presentation: BattleUIPresentation) -> some View {
        if let spell = presentation.selectedSpell {
            GlyphCastingPanel(
                spell: spell,
                inputPreference: appSettings.inputPreference,
                availableMana: presentation.resources.mana,
                availableStrokes: presentation.resources.strokes,
                erasureZones: presentation.activeErasureZones,
                showsResourceHeader: false,
                surfaceOpacity: 0.76,
                usesBattleArtwork: true,
                onResourcePreviewChanged: { mana, strokes in
                    previewMana = mana
                    previewStrokes = strokes
                },
                onCast: { submission in
                    gameSession.send(.castSpell(
                        spell: spell.id,
                        strokes: submission.strokes,
                        inputMethod: submission.inputMethod
                    ))
                }
            )
        } else {
            Text("시전할 수 있는 주문이 없습니다")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DAColor.background.opacity(0.94))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func inputPanelX(
        availableWidth: CGFloat,
        panelWidth: CGFloat
    ) -> CGFloat {
        let edgeInset: CGFloat = 16
        switch appSettings.drawingPadPosition {
        case .left:
            return (panelWidth / 2) + edgeInset
        case .right:
            return availableWidth - (panelWidth / 2) - edgeInset
        }
    }

    private func enemyStage(_ presentation: BattleUIPresentation) -> some View {
        ZStack {
            if realitySceneID == nil {
                stageGrid
            }

            VStack(spacing: 8) {
                if realitySceneID == nil {
                    ZStack {
                        Image(systemName: enemySymbol)
                            .font(.system(size: 104, weight: .thin))
                            .foregroundStyle(Color.purple.opacity(0.18))
                            .offset(x: -7, y: 4)
                        Image(systemName: enemySymbol)
                            .font(.system(size: 104, weight: .thin))
                            .foregroundStyle(.white.opacity(0.82))
                            .shadow(color: .purple.opacity(0.85), radius: enemyHitFlash ? 28 : 12)
                            .scaleEffect(enemyHitFlash ? 1.08 : 1)
                    }
                } else {
                    Spacer(minLength: 74)
                }
            }
        }
        .background(realitySceneID == nil ? Color.black.opacity(0.28) : Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DAColor.gold.opacity(0.22))
                .frame(height: 1)
        }
    }

    private func spellBar(_ presentation: BattleUIPresentation) -> some View {
        HStack(alignment: .bottom, spacing: 28) {
            battleLogPanel(presentation)
                .frame(width: 248, height: 176)

            VStack(alignment: .leading, spacing: 8) {
                battleResourceBar(presentation)
                    .frame(height: 42)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(presentation.spells) { spellState in
                            spellCard(spellState)
                        }
                    }
                }
                .frame(height: 176)
            }

            turnEndControl(presentation)
                .frame(width: 184, height: 94, alignment: .bottomTrailing)
        }
    }

    private func battleResourceBar(_ presentation: BattleUIPresentation) -> some View {
        let maximumMana = max(presentation.resources.maximumMana, 1)
        let displayedMana = previewMana ?? presentation.resources.mana
        let displayedStrokes = previewStrokes ?? presentation.resources.strokes
        let manaRatio = min(max(displayedMana / maximumMana, 0), 1)

        return HStack(spacing: 10) {
            Text("마나 \(Int((manaRatio * 100).rounded()))%")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(DAColor.magicGlow)

            manaMeter(ratio: manaRatio)
                .frame(minWidth: 280, idealWidth: 460, maxWidth: 560)
                .frame(height: 18)

            Text(resourceSummary(presentation, strokes: displayedStrokes))
                .font(.caption.monospacedDigit())
                .foregroundStyle(DAColor.body.opacity(0.84))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .background(DAColor.card.opacity(0.9))
        .overlay {
            Rectangle()
                .stroke(DAColor.gold.opacity(0.28), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private func manaMeter(ratio: Double) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let markerWidth: CGFloat = 3
            let fillWidth = width * ratio
            let markerX = min(
                max(fillWidth - (markerWidth / 2), 0),
                max(width - markerWidth, 0)
            )

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.07))

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [DAColor.magic.opacity(0.72), DAColor.magicGlow],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: fillWidth)
                    .clipShape(RoundedRectangle(cornerRadius: 2))

                ForEach(1..<4, id: \.self) { division in
                    Rectangle()
                        .fill(Color.black.opacity(0.48))
                        .frame(width: 2, height: height)
                        .position(
                            x: width * CGFloat(division) / 4,
                            y: height / 2
                        )
                }

                Rectangle()
                    .fill(Color.white)
                    .frame(width: markerWidth, height: height)
                    .offset(x: markerX)
                    .shadow(color: .white.opacity(0.75), radius: 2)

                RoundedRectangle(cornerRadius: 2)
                    .stroke(DAColor.gold.opacity(0.38), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .animation(.easeOut(duration: 0.24), value: ratio)
        }
    }

    private func resourceSummary(
        _ presentation: BattleUIPresentation,
        strokes: Int
    ) -> String {
        let strokeSummary = "잔여 획 \(strokes) / \(presentation.resources.maximumStrokes)"
        guard let selectedSpell = presentation.selectedSpell else { return strokeSummary }
        return "\(strokeSummary) · \(selectedSpell.name)"
    }

    private func turnEndControl(_ presentation: BattleUIPresentation) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            Text("손패 \(presentation.spells.count) · 남은 획 \(presentation.resources.strokes)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(DAColor.secondary)

            Button {
                gameSession.send(.finishTurn)
            } label: {
                Text("턴 종료")
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .frame(width: 176, height: 60)
            }
            .buttonStyle(BattleTurnEndButtonStyle())
            .disabled(presentation.phase != .playerTurn)
            .accessibilityHint("현재 봉인관 차례를 종료합니다")
        }
    }

    private func battleLogPanel(_ presentation: BattleUIPresentation) -> some View {
        ZStack {
            Image("BattleLogPanelFrame")
                .resizable()
                .scaledToFill()

            VStack(alignment: .leading, spacing: 8) {
                Text("전투 기록")
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(DAColor.body)

                Rectangle()
                    .fill(DAColor.gold.opacity(0.32))
                    .frame(height: 1)

                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            if presentation.recentLogEntries.isEmpty {
                                Text("· 전투 기록 대기")
                                    .foregroundStyle(DAColor.secondary)
                            } else {
                                ForEach(
                                    Array(presentation.recentLogEntries.enumerated()),
                                    id: \.offset
                                ) { index, entry in
                                    Text("· \(entry)")
                                        .foregroundStyle(logColor(for: entry))
                                        .lineLimit(1)
                                        .id(index)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .mask(alignment: .top) {
                        VStack(spacing: 0) {
                            LinearGradient(
                                colors: presentation.recentLogEntries.count > 5
                                    ? [.clear, .black]
                                    : [.black, .black],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 14)

                            Color.black
                        }
                    }
                    .onAppear {
                        scrollBattleLogToLatest(presentation.recentLogEntries, proxy: proxy)
                    }
                    .onChange(of: presentation.recentLogEntries.count) { _, _ in
                        scrollBattleLogToLatest(presentation.recentLogEntries, proxy: proxy)
                    }
                }
            }
            .font(.caption)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .clipped()
        .accessibilityElement(children: .combine)
    }

    private func logColor(for entry: String) -> Color {
        if entry.contains("피해") || entry.contains("취소") || entry.contains("거부") {
            return DAColor.attack.opacity(0.95)
        }
        if entry.contains("방벽") {
            return DAColor.defense.opacity(0.95)
        }
        return DAColor.body.opacity(0.86)
    }

    private func spellCard(_ state: BattleUISpellState) -> some View {
        let spell = state.spell

        return ZStack {
            Image(spell.battleCardFrameAssetName)
                .resizable()
                .scaledToFill()

            if let overlayAssetName = state.visualState.overlayAssetName {
                Image(overlayAssetName)
                    .resizable()
                    .scaledToFill()
            }

            VStack(spacing: 5) {
                Spacer(minLength: 30)

                Image(spell.battleGlyphAssetName)
                    .resizable()
                    .scaledToFit()
                    .blendMode(.screen)
                    .frame(width: 76, height: 76)

                Spacer(minLength: 2)

                Text(spell.name)
                    .font(.system(size: 14, weight: .semibold, design: .serif))
                    .foregroundStyle(DAColor.body)
                    .lineLimit(1)

                Text("\(spell.battleEffectRangeTitle) · \(spell.requiredStrokes)획")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(DAColor.body.opacity(0.82))
                    .lineLimit(1)

                Spacer(minLength: 10)
            }
            .padding(.horizontal, 12)

            VStack {
                HStack {
                    Spacer()
                    Image(spell.battleScrollBadgeAssetName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 34, height: 34)
                        .clipShape(Circle())
                        .overlay {
                            Circle()
                                .stroke(DAColor.gold.opacity(0.7), lineWidth: 1)
                        }
                        .accessibilityLabel(spell.battleScrollTierTitle)
                }
                Spacer()
            }
            .padding(10)
        }
        .frame(width: 132, height: 176)
        .clipped()
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    updateSpellCardPress(spell, translation: value.translation)
                }
                .onEnded { _ in
                    finishSpellCardPress(spell, canSelect: state.canInteract)
                }
        )
        .accessibilityLabel(
            "\(spell.name), \(spell.battleScrollTierTitle), "
                + "\(spell.battleEffectRangeTitle), \(spell.requiredStrokes)획"
        )
        .accessibilityHint("길게 누르면 주문 상세 정보를 표시합니다")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            if state.canInteract {
                selectedSpellID = spell.id
            }
        }
    }

    private func updateSpellCardPress(_ spell: SpellDefinition, translation: CGSize) {
        let distance = hypot(translation.width, translation.height)

        if distance > 24 {
            detailPressWasCancelled = true
            detailPressTask?.cancel()
            if detailedSpell?.id == spell.id {
                detailedSpell = nil
            }
            return
        }

        guard pressedSpellID == nil else { return }
        pressedSpellID = spell.id
        detailPressWasCancelled = false
        detailPressTask?.cancel()
        detailPressTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled,
                  pressedSpellID == spell.id,
                  !detailPressWasCancelled else { return }
            withAnimation(.easeOut(duration: 0.16)) {
                detailedSpell = spell
            }
        }
    }

    private func finishSpellCardPress(_ spell: SpellDefinition, canSelect: Bool) {
        let showedDetails = detailedSpell?.id == spell.id
        let shouldSelect = !showedDetails && !detailPressWasCancelled && canSelect

        detailPressTask?.cancel()
        detailPressTask = nil
        pressedSpellID = nil
        detailPressWasCancelled = false

        if showedDetails {
            withAnimation(.easeOut(duration: 0.14)) {
                detailedSpell = nil
            }
        } else if shouldSelect {
            selectedSpellID = spell.id
        }
    }

    private func spellDetailOverlay(_ spell: SpellDefinition) -> some View {
        GeometryReader { proxy in
            let panelWidth = min(760, proxy.size.width * 0.58)
            let panelHeight = panelWidth * 0.75
            let effectRange = spell.effect.range

            ZStack {
                Color.black.opacity(0.42)
                    .ignoresSafeArea()

                ZStack {
                    Image("BattleSpellDetailPanel")
                        .resizable()
                        .scaledToFit()

                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Text(spell.name)
                            .font(.system(size: 26, weight: .semibold, design: .serif))
                            .foregroundStyle(DAColor.body)
                            .fixedSize(horizontal: true, vertical: false)

                        Text("\(spell.battleCategoryTitle) 주문 · \(spell.battleScrollTierTitle) · \(spell.requiredStrokes)획")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(DAColor.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)

                        Spacer(minLength: 0)
                    }
                    .frame(width: panelWidth * 0.86, height: panelHeight * 0.12, alignment: .leading)
                    .position(x: panelWidth * 0.50, y: panelHeight * 0.135)

                    Image(spell.battleGlyphAssetName)
                        .resizable()
                        .scaledToFit()
                        .blendMode(.screen)
                        .frame(width: panelWidth * 0.20, height: panelHeight * 0.25)
                        .position(x: panelWidth * 0.228, y: panelHeight * 0.46)

                    VStack(spacing: 0) {
                        spellDetailRow(
                            spell.battleDetailEffectTitle,
                            "\(effectRange.lowerBound)~\(effectRange.upperBound)"
                        )
                        spellDetailRow("소모 마나", "\(Int(spell.recommendedMana.rounded()))%")
                        spellDetailRow("필요 획", "\(spell.requiredStrokes)")
                        spellDetailRow("구현 난이도", spell.battleDifficultyTitle)
                        spellDetailRow("필수 핵심점", spell.battleRequiredPointTitle)
                        spellDetailRow("허용 오차", spell.battleToleranceTitle)
                    }
                    .frame(width: panelWidth * 0.50, height: panelHeight * 0.35)
                    .position(x: panelWidth * 0.66, y: panelHeight * 0.465)

                    Text(spell.battleDetailDescription)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(DAColor.body.opacity(0.9))
                        .frame(width: panelWidth * 0.86, height: panelHeight * 0.08, alignment: .leading)
                        .position(x: panelWidth * 0.50, y: panelHeight * 0.77)

                    Text("누르는 동안 상세 표시 · 손을 떼면 닫힘")
                        .font(.caption)
                        .foregroundStyle(DAColor.secondary.opacity(0.86))
                        .frame(width: panelWidth * 0.82, alignment: .trailing)
                        .position(x: panelWidth * 0.50, y: panelHeight * 0.85)
                }
                .frame(width: panelWidth, height: panelHeight)
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(spell.name) 주문 상세 정보")
    }

    private func spellDetailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(DAColor.secondary)
            Spacer(minLength: 8)
            Text(value)
                .foregroundStyle(DAColor.body)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
        }
        .font(.system(size: 15, weight: .medium).monospacedDigit())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 4)
        .offset(y: -14)
    }

    private var encounterStandby: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("층 관리자 전투 절차를 준비 중입니다")
                .font(.headline)
            Button("전투 시작") {
                startEncounterIfNeeded()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var battleBackground: some View {
        LinearGradient(
            colors: [
                DAColor.background,
                DAColor.panel,
                Color.black
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private func presentation(for battle: BattleState) -> BattleUIPresentation {
        let spellStates = availableSpells(in: battle).map { spell in
            let isAffordable = spell.requiredStrokes <= battle.resources.remainingStrokes
            let isPermitted = isSpellPermitted(spell, battle: battle)
            return BattleUISpellState(
                spell: spell,
                isSelected: selectedSpellID == spell.id,
                isAffordable: isAffordable,
                isPermitted: isPermitted,
                canInteract: battle.phase == .playerTurn && isAffordable && isPermitted
            )
        }

        return BattleUIPresentation(
            phase: battle.phase,
            turnNumber: battle.turnNumber,
            player: BattleUICombatantState(battle.player),
            enemy: BattleUICombatantState(battle.enemy),
            resources: BattleUIResourceState(
                mana: battle.resources.remainingMana,
                maximumMana: battle.resources.maximumMana,
                strokes: battle.resources.remainingStrokes,
                maximumStrokes: battle.resources.maximumStrokes
            ),
            currentEnemyIntent: battle.currentEnemyIntent,
            activeErasureZones: battle.activeErasureZones,
            castsThisTurn: battle.castsThisTurn,
            spells: spellStates,
            recentLogEntries: battleLogEntries
        )
    }

    private func appendBattleLog(_ events: [DemoSessionEvent], sequence: UInt64) {
        guard lastLoggedEventSequence != sequence else { return }
        lastLoggedEventSequence = sequence

        let beginsNewBattle = events.contains { event in
            guard case let .combat(combatEvent) = event else { return false }
            guard case .battleStarted = combatEvent else { return false }
            return true
        }
        if beginsNewBattle {
            battleLogEntries.removeAll(keepingCapacity: true)
        }

        let newEntries = events.compactMap(combatLogEntry)
        guard !newEntries.isEmpty else { return }

        battleLogEntries.append(contentsOf: newEntries)
        if battleLogEntries.count > 50 {
            battleLogEntries.removeFirst(battleLogEntries.count - 50)
        }
    }

    private func scrollBattleLogToLatest(
        _ entries: [String],
        proxy: ScrollViewProxy
    ) {
        guard let lastIndex = entries.indices.last else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(lastIndex, anchor: .bottom)
        }
    }

    private func combatLogEntry(for event: DemoSessionEvent) -> String? {
        guard case let .combat(event) = event else { return nil }
        switch event {
        case let .turnStarted(number, intent):
            return "TURN \(number) · \(intent.name) 예고"
        case let .spellResolved(spell, grade):
            return "\(SpellCatalog.spell(spell).name) · \(gradeTitle(grade))"
        case let .spellRejected(spell, reason):
            return "\(SpellCatalog.spell(spell).name) · \(failureTitle(reason))"
        case let .resourcesChanged(mana, strokes):
            return "마나 \(Int(mana.rounded())) · 남은 획 \(strokes)"
        case let .damageApplied(target, amount, _):
            return target == .player ? "플레이어 피해 \(amount)" : "관리자 피해 \(amount)"
        case let .normalBarrierChanged(target, amount):
            return target == .player ? "플레이어 방벽 \(amount)" : "관리자 방벽 \(amount)"
        case let .absoluteBarrierChanged(_, charges):
            return "절대 방벽 \(charges)회"
        case .attackNegatedByAbsoluteBarrier:
            return "절대 방벽으로 공격 무효화"
        case .erasureZoneAdded:
            return "말소 구역 발생"
        case let .enemyActionStarted(action):
            return "관리자 행동 · \(action.name)"
        case .enemyActionCancelled:
            return "관리자 행동 취소"
        case .battleStarted:
            return "전투 개시"
        case .victory:
            return "관리자 무력화"
        case .defeat:
            return "하강 봉인 절차 중단"
        }
    }

    private var stageGrid: some View {
        Canvas { context, size in
            var path = Path()
            for column in 0...12 {
                let x = size.width * CGFloat(column) / 12
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            for row in 0...5 {
                let y = size.height * CGFloat(row) / 5
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(.white.opacity(0.035)), lineWidth: 1)
        }
        .background(Color.black.opacity(0.28))
    }

    private func castFeedback(text: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "seal.fill")
                .font(.title)
            Text(text)
                .font(.title3.weight(.bold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.black.opacity(0.84))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func startEncounterIfNeeded() {
        guard gameSession.battleState == nil, isBattleScene else { return }
        gameSession.send(.startEncounter)
    }

    private func selectAvailableSpell() {
        guard let battle = gameSession.battleState else {
            selectedSpellID = nil
            return
        }
        if let selectedSpellID,
           battle.learnedSpells.contains(selectedSpellID),
           SpellCatalog.spell(selectedSpellID).requiredStrokes <= battle.resources.remainingStrokes,
           isSpellPermitted(SpellCatalog.spell(selectedSpellID), battle: battle) {
            return
        }
        selectedSpellID = availableSpells(in: battle).first(where: {
            $0.requiredStrokes <= battle.resources.remainingStrokes
                && isSpellPermitted($0, battle: battle)
        })?.id
    }

    private func autoFinishPlayerTurnIfNeeded() {
        guard let battle = gameSession.battleState else { return }
        guard battle.phase == .playerTurn else { return }
        guard availableSpells(in: battle).contains(where: {
            $0.requiredStrokes <= battle.resources.remainingStrokes
                && isSpellPermitted($0, battle: battle)
        }) == false else { return }
        gameSession.send(.finishTurn)
    }

    private func availableSpells(in battle: BattleState) -> [SpellDefinition] {
        SpellID.allCases
            .filter(battle.learnedSpells.contains)
            .map(SpellCatalog.spell)
    }

    private func present(_ events: [DemoSessionEvent]) {
        realityController.presentCombat(
            events: events,
            battleState: gameSession.battleState,
            reducedMotion: appSettings.reducedMotion
        )
        var enemyWasHit = false
        var playerWasHit = false
        var playerBarrierWasHit = false
        var strongAttack = false
        var banner: (String, Color)?

        for event in events {
            guard case let .combat(battleEvent) = event else { continue }
            switch battleEvent {
            case let .damageApplied(target, amount, _):
                switch target {
                case .player:
                    playerWasHit = amount > 0
                case .enemy:
                    enemyWasHit = amount > 0
                }
            case let .spellResolved(_, grade):
                banner = (gradeTitle(grade), gradeColor(grade))
            case let .spellRejected(_, reason):
                banner = (failureTitle(reason), .red)
            case .attackNegatedByAbsoluteBarrier:
                banner = ("절대 방벽으로 무효화", .yellow)
                didExperienceAbsoluteBarrier = true
            case let .normalBarrierChanged(target, amount):
                if case .player = target {
                    playerBarrierWasHit = true
                } else if case .enemy = target, amount > 0 {
                    banner = ("문서 방벽 전개", .cyan)
                }
            case .erasureZoneAdded:
                banner = ("말소 구역 발생", .red)
            case let .enemyActionStarted(action):
                if case let .attack(_, _, isStrong) = action {
                    strongAttack = isStrong
                }
            default:
                break
            }
        }

        if enemyWasHit { pulseEnemy() }
        if playerWasHit { pulsePlayer(strong: strongAttack) }
        if strongAttack, playerWasHit || playerBarrierWasHit {
            realityController.playStrongAttackCameraImpact(
                guarded: playerBarrierWasHit && !playerWasHit,
                reducedMotion: appSettings.reducedMotion
            )
        }
        if let banner { showFeedback(banner.0, color: banner.1) }
    }

    private func pulseEnemy() {
        enemyPulseTask?.cancel()
        animate(.easeOut(duration: 0.12)) { enemyHitFlash = true }
        enemyPulseTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled else { return }
            animate(.easeIn(duration: 0.2)) { enemyHitFlash = false }
        }
    }

    private func pulsePlayer(strong: Bool) {
        playerPulseTask?.cancel()
        animate(.easeOut(duration: 0.08)) {
            playerHitFlash = true
            strongAttackFlash = strong
        }
        playerPulseTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(strong ? 420 : 260))
            guard !Task.isCancelled else { return }
            animate(.easeIn(duration: 0.2)) {
                playerHitFlash = false
                strongAttackFlash = false
            }
        }
    }

    private func showFeedback(_ text: String, color: Color) {
        feedbackTask?.cancel()
        animate(.spring(response: 0.24)) {
            feedbackText = text
            feedbackColor = color
        }
        feedbackTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            animate(.easeOut(duration: 0.2)) { feedbackText = nil }
        }
    }

    private func animate(
        _ animation: Animation,
        changes: () -> Void
    ) {
        if appSettings.reducedMotion {
            changes()
        } else {
            withAnimation(animation, changes)
        }
    }

    private var isBattleScene: Bool {
        switch gameSession.progress.currentScene {
        case .floor9RecordsBattle, .floor8ResidualBattle, .floor8AdministratorBattle:
            true
        default:
            false
        }
    }

    private var realitySceneID: FloorSceneID? {
        gameSession.presentation.floorSceneID
    }

    private var isRecordsBattle: Bool {
        gameSession.progress.currentScene == .floor9RecordsBattle
    }

    private var isResidualBattle: Bool {
        gameSession.progress.currentScene == .floor8ResidualBattle
    }

    private var isObservationBattle: Bool {
        gameSession.progress.currentScene == .floor8AdministratorBattle
    }

    private var shouldShowFirstTurnBriefing: Bool {
        isRecordsBattle || isResidualBattle || isObservationBattle
    }

    @ViewBuilder
    private var battleBriefing: some View {
        if isResidualBattle {
            residualBriefing
        } else if isObservationBattle {
            observationBriefing
        } else {
            firstTurnBriefing
        }
    }

    private var firstTurnBriefing: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                Label("9층 전투 절차", systemImage: "exclamationmark.shield.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.purple)

                briefingRow(
                    icon: "eye.fill",
                    title: "관리자의 다음 행동을 먼저 확인",
                    detail: "공격이 예고되면 피해를 감수할지, 턴을 어떻게 사용할지 결정한다."
                )
                briefingRow(
                    icon: "scribble.variable",
                    title: "마나는 남은 선의 길이",
                    detail: "문양을 그리는 동안 실시간으로 줄며, 우회하거나 길게 그릴수록 더 소모된다."
                )
                briefingRow(
                    icon: "pencil.and.outline",
                    title: "이번 턴은 2획",
                    detail: "현재의 1획 공격 주문은 한 턴에 두 번까지 조합할 수 있다."
                )

                Button("전투 시작") {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showsFirstTurnBriefing = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .frame(maxWidth: .infinity)
            }
            .padding(24)
            .frame(maxWidth: 520)
            .background(Color(red: 0.035, green: 0.04, blue: 0.055))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.purple.opacity(0.35), lineWidth: 1)
            }
        }
    }

    private func briefingRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 28)
                .foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var defeatOverlay: some View {
        GeometryReader { proxy in
            let panelWidth = min(760, proxy.size.width * 0.58)
            let panelHeight = panelWidth * (2.0 / 3.0)
            let retryButtonWidth = panelWidth * 0.7
            let retryButtonHeight = panelHeight * 0.19
            let retryIconCenterXRatio = 326.5 / 1_774.0
            let retryLabelCenterXRatio = (0.24 + 0.96) / 2.0

            ZStack {
                Color.black.opacity(0.68)
                    .ignoresSafeArea()

                ZStack {
                    Image("BattleDefeatPanel")
                        .resizable()
                        .scaledToFit()
                        .frame(width: panelWidth, height: panelHeight)

                    Image("BattleDefeatSeal")
                        .resizable()
                        .scaledToFit()
                        .frame(width: panelWidth * 0.37, height: panelWidth * 0.37)
                        .position(
                            x: panelWidth * 0.5,
                            y: panelHeight * 0.085
                        )
                        .shadow(color: .black.opacity(0.66), radius: 12, y: 6)

                    Image("BattleDefeatTitle")
                        .resizable()
                        .scaledToFill()
                        .frame(width: panelWidth * 0.64, height: panelHeight * 0.13)
                        .clipped()
                        .position(
                            x: panelWidth * 0.5,
                            y: panelHeight * 0.345
                        )

                    Rectangle()
                        .fill(DAColor.gold.opacity(0.42))
                        .frame(width: panelWidth * 0.67, height: 1)
                        .position(
                            x: panelWidth * 0.5,
                            y: panelHeight * 0.43
                        )

                    Text("생체 반응이 한계치 아래로 감소했습니다.")
                        .font(.system(size: 17, weight: .semibold, design: .serif))
                        .foregroundStyle(DAColor.attack)
                        .position(
                            x: panelWidth * 0.5,
                            y: panelHeight * 0.495
                        )

                    Text("전투 진입 직전의 기록으로 복원하여 다시 시작합니다.")
                        .font(.system(size: 14, weight: .medium, design: .serif))
                        .foregroundStyle(DAColor.body.opacity(0.86))
                        .position(
                            x: panelWidth * 0.5,
                            y: panelHeight * 0.56
                        )

                    Button {
                        restartDefeatedBattle()
                    } label: {
                        ZStack {
                            Image("BattleDefeatRetryButton")
                                .resizable()
                                .scaledToFill()
                                .frame(
                                    width: retryButtonWidth,
                                    height: retryButtonHeight
                                )
                                .clipped()

                            Image("BattleDefeatRetryIcon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 56, height: 56)
                                .position(
                                    x: retryButtonWidth * retryIconCenterXRatio,
                                    y: retryButtonHeight * 0.5
                                )

                            Text("전투 재시작")
                                .font(.system(size: 24, weight: .semibold, design: .serif))
                                .foregroundStyle(DAColor.body)
                                .position(
                                    x: retryButtonWidth * retryLabelCenterXRatio - 15,
                                    y: retryButtonHeight * 0.5
                                )
                        }
                        .frame(width: retryButtonWidth, height: retryButtonHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("전투 재시작")
                    .accessibilityHint("전투 진입 직전 상태로 복원합니다")
                    .position(
                        x: panelWidth * 0.5,
                        y: panelHeight * 0.73
                    )
                }
                .frame(width: panelWidth, height: panelHeight)
                .shadow(color: .black.opacity(0.78), radius: 22, y: 10)
            }
        }
    }

    private func updateDefeatPresentation(for phase: BattlePhase?) {
        guard phase == .defeat else {
            defeatPresentationTask?.cancel()
            defeatPresentationTask = nil
            if isDefeatPanelVisible {
                withAnimation(.easeOut(duration: 0.16)) {
                    isDefeatPanelVisible = false
                }
            }
            if isBattleScene,
               !isRestartLoading {
                realityController.resetBattleCamera(animated: false)
                realityController.setBattleCameraInteractionEnabled(true)
            }
            return
        }

        guard defeatPresentationTask == nil,
              !isDefeatPanelVisible else { return }

        enemyPulseTask?.cancel()
        playerPulseTask?.cancel()
        feedbackTask?.cancel()
        detailPressTask?.cancel()
        clearTransientBattleEffects()
        detailedSpell = nil
        feedbackText = nil
        showsFirstTurnBriefing = false
        isCameraLooking = false
        isCameraZooming = false
        cameraLookTranslationOrigin = nil
        realityController.setBattleCameraInteractionEnabled(false)

        defeatPresentationTask = Task { @MainActor in
            defer { defeatPresentationTask = nil }
            await realityController.playBattleDefeatCamera(
                reducedMotion: appSettings.reducedMotion
            )
            guard !Task.isCancelled,
                  gameSession.battleState?.phase == .defeat else { return }
            withAnimation(.easeOut(duration: appSettings.reducedMotion ? 0 : 0.24)) {
                isDefeatPanelVisible = true
            }
        }
    }

    private var restartLoadingContext: LoadingScreenContext {
        guard let realitySceneID else { return .floor9 }
        return LoadingScreenContext(sceneID: realitySceneID)
    }

    private func restartDefeatedBattle() {
        guard !isRestartLoading else { return }

        defeatPresentationTask?.cancel()
        defeatPresentationTask = nil
        restartTask?.cancel()
        clearTransientBattleEffects()
        let loadingContext = restartLoadingContext
        let loadingTip = LoadingTipCatalog.randomTip(for: loadingContext)
        realityController.setBattleCameraInteractionEnabled(false)

        withAnimation(.easeInOut(duration: appSettings.reducedMotion ? 0 : 0.18)) {
            isDefeatPanelVisible = false
            restartLoadingPresentation = BattleRestartLoadingPresentation(
                context: loadingContext,
                progress: 0.08,
                tip: loadingTip
            )
        }

        restartTask = Task { @MainActor in
            defer { restartTask = nil }

            guard await waitForRestartStep(milliseconds: 180) else { return }
            restartLoadingPresentation?.progress = 0.34

            gameSession.send(.restartEncounter)
            guard gameSession.battleState?.phase != .defeat else {
                restoreDefeatPanelAfterRestartFailure()
                return
            }

            battleLogEntries.removeAll(keepingCapacity: true)
            clearTransientBattleEffects()
            previewMana = nil
            previewStrokes = nil
            detailedSpell = nil
            selectedSpellID = nil
            realityController.resetBattleCamera(animated: false)
            realityController.synchronizeCombatState(
                gameSession.battleState,
                reducedMotion: appSettings.reducedMotion
            )
            restartLoadingPresentation?.progress = 0.82

            guard await waitForRestartStep(milliseconds: 420) else { return }
            selectAvailableSpell()
            restartLoadingPresentation?.progress = 1

            guard await waitForRestartStep(milliseconds: 180) else { return }
            realityController.setBattleCameraInteractionEnabled(isBattleScene)
            withAnimation(.easeOut(duration: appSettings.reducedMotion ? 0 : 0.2)) {
                restartLoadingPresentation = nil
            }
        }
    }

    private func waitForRestartStep(milliseconds: Int) async -> Bool {
        guard !appSettings.reducedMotion else { return !Task.isCancelled }
        do {
            try await Task.sleep(for: .milliseconds(milliseconds))
            return !Task.isCancelled
        } catch {
            return false
        }
    }

    private func restoreDefeatPanelAfterRestartFailure() {
        withAnimation(.easeOut(duration: appSettings.reducedMotion ? 0 : 0.18)) {
            restartLoadingPresentation = nil
            isDefeatPanelVisible = true
        }
    }

    private func clearTransientBattleEffects() {
        enemyHitFlash = false
        playerHitFlash = false
        strongAttackFlash = false
    }

    private var residualBriefing: some View {
        briefingOverlay(
            title: "관측 잔류체 대응",
            accent: .cyan,
            rows: [
                ("shield.fill", "훈련 방벽 20 유지", "보호 절차실에서 만든 방벽이 이번 전투의 첫 피해를 먼저 막는다."),
                ("scope", "강공격은 한 턴 전에 예고", "초점 고정이 보이면 다음 집속 파편에 대비할 수 있다."),
                ("pencil.and.outline", "공격과 방어를 같은 턴에 조합", "1획 공격과 1획 방어를 선택해 2획 안에서 대응한다.")
            ]
        )
    }

    private var observationBriefing: some View {
        briefingOverlay(
            title: "관측 관리자 절대 차폐",
            accent: .yellow,
            rows: [
                ("shield.checkered", "절대 방벽 1회", "방벽이 유지되는 동안 공격과 부가 효과가 전부 무효화된다."),
                ("sparkles", "먼저 공격 효과를 확인", "공격 주문을 한 번 시전해 절대 방벽의 차단 규칙을 직접 확인한다."),
                ("lock.open.fill", "체험 후 봉인 해제", "차단을 확인하면 봉인 해제 카드가 활성화된다.")
            ]
        )
    }

    private func briefingOverlay(
        title: String,
        accent: Color,
        rows: [(String, String, String)]
    ) -> some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                Label(title, systemImage: "exclamationmark.shield.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(accent)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    briefingRow(icon: row.0, title: row.1, detail: row.2)
                }
                Button("전투 시작") {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showsFirstTurnBriefing = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .frame(maxWidth: .infinity)
            }
            .padding(24)
            .frame(maxWidth: 520)
            .background(Color(red: 0.035, green: 0.04, blue: 0.055))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(accent.opacity(0.35), lineWidth: 1)
            }
        }
    }

    private func isSpellPermitted(_ spell: SpellDefinition, battle: BattleState) -> Bool {
        if isObservationBattle, spell.id == .sealRelease {
            return battle.enemy.absoluteBarrierCharges > 0
                && didExperienceAbsoluteBarrier
        }
        return true
    }

    private var enemySymbol: String {
        switch gameSession.progress.currentScene {
        case .floor8ResidualBattle: "eye.trianglebadge.exclamationmark"
        case .floor8AdministratorBattle: "eye.circle.fill"
        default: "person.text.rectangle.fill"
        }
    }

    private func spellSymbol(_ category: SpellCategory) -> String {
        switch category {
        case .attack: "sparkles"
        case .defense: "shield.fill"
        case .dispel: "lock.open.fill"
        }
    }

    private func spellColor(_ category: SpellCategory) -> Color {
        switch category {
        case .attack: DAColor.attack
        case .defense: DAColor.defense
        case .dispel: DAColor.dispel
        }
    }

    private func categoryTitle(_ category: SpellCategory) -> String {
        switch category {
        case .attack: "공격"
        case .defense: "방어"
        case .dispel: "해제"
        }
    }

    private func gradeTitle(_ grade: CastingGrade) -> String {
        switch grade {
        case .perfect: "완전 시전"
        case .precise: "정밀 시전"
        case .approved: "승인 시전"
        case .incomplete: "불완전 시전"
        case .rejected: "시전 거부"
        }
    }

    private func gradeColor(_ grade: CastingGrade) -> Color {
        switch grade {
        case .perfect: .white
        case .precise: .purple
        case .approved: .cyan
        case .incomplete: .orange
        case .rejected: .red
        }
    }

    private func failureTitle(_ failure: CastingFailure) -> String {
        switch failure {
        case .noInput: "문양 없음"
        case .wrongStrokeCount: "획 불일치"
        case .invalidStart: "시작점 오류"
        case .missingRequiredNode: "필수 지점 누락"
        case .invalidEnd: "종료점 오류"
        case .missingCrossing: "교차점 누락"
        case .manaDepleted: "마나 고갈"
        case .incompleteGlyph: "문양 불완전"
        }
    }
}
