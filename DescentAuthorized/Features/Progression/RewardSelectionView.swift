import SwiftUI

private enum RewardSelectionPalette {
    static let gold = Color(red: 0.78, green: 0.68, blue: 0.51)
    static let body = Color(red: 0.84, green: 0.82, blue: 0.79)
    static let secondary = Color(red: 0.60, green: 0.59, blue: 0.61)
    static let violet = Color(red: 0.68, green: 0.45, blue: 1.0)
    static let cyan = Color(red: 0.39, green: 0.78, blue: 0.95)
}

private struct RewardConfirmButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            Image(assetName(isPressed: configuration.isPressed))
                .resizable()
                .scaledToFill()
            configuration.label
                .foregroundStyle(isEnabled ? RewardSelectionPalette.gold : .gray)
        }
        .contentShape(Rectangle())
        .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }

    private func assetName(isPressed: Bool) -> String {
        guard isEnabled else { return "RewardScrollConfirmDisabled" }
        return isPressed ? "RewardScrollConfirmPressed" : "RewardScrollConfirmDefault"
    }
}

struct RewardSelectionView: View {
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var gameSession: GameSessionStore

    let floor: FloorID
    let sceneController: RealitySceneController

    @State private var selectedCandidateID: String?
    @State private var isResolving = false
    @State private var rewardState: RealityRewardPresentationState = .appearing
    @State private var transitionTask: Task<Void, Never>?
    @State private var inspectedCandidateID: String?
    @State private var detailPressTask: Task<Void, Never>?

    private var candidates: [RewardCandidate] {
        RewardCatalog.candidates(for: floor)
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = RewardLayoutMetrics(size: proxy.size)

            ZStack {
                backgroundTreatment
                header(metrics: metrics)
                cards(metrics: metrics)
                footer(metrics: metrics)

                if let inspectedCandidate {
                    detailPanel(for: inspectedCandidate, metrics: metrics)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        .zIndex(20)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            sceneController.resetProgressionPresentation(reducedMotion: appSettings.reducedMotion)
            setRewardState(.appearing)
            transitionTask?.cancel()
            transitionTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(appSettings.reducedMotion ? 20 : 520))
                guard !Task.isCancelled else { return }
                setRewardState(.choosing)
            }
        }
        .onDisappear {
            transitionTask?.cancel()
            cancelDetailPress()
        }
        .onChange(of: appSettings.reducedMotion) { _, reducedMotion in
            sceneController.setRewardPresentation(rewardState, reducedMotion: reducedMotion)
        }
    }

    private var backgroundTreatment: some View {
        ZStack {
            Color.black.opacity(0.36)
            LinearGradient(
                colors: [.black.opacity(0.76), .clear, .black.opacity(0.24), .black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
            LinearGradient(
                colors: [.black.opacity(0.5), .clear, .black.opacity(0.5)],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func header(metrics: RewardLayoutMetrics) -> some View {
        ZStack {
            VStack(alignment: .leading, spacing: metrics.headerSpacing) {
                Text("제\(floor.rawValue)층 · 기록 보관고")
                    .font(.system(size: metrics.eyebrowSize, weight: .medium, design: .serif))
                    .foregroundStyle(RewardSelectionPalette.gold)
                Text("보상 두루마리 선택")
                    .font(.system(size: metrics.titleSize, weight: .medium, design: .serif))
                    .foregroundStyle(RewardSelectionPalette.gold)
                    .shadow(color: .black, radius: 5)
                Text("승인된 주문 기록 \(candidates.count)건 중 1건을 수령하십시오.")
                    .font(.system(size: metrics.bodySize, weight: .regular, design: .serif))
                    .foregroundStyle(RewardSelectionPalette.body)
                Image("RewardScrollHeaderDivider")
                    .resizable()
                    .scaledToFit()
                    .frame(width: metrics.headerWidth, height: 24)
            }
            .position(
                x: metrics.headerLeading + metrics.headerWidth / 2,
                y: metrics.headerTop + metrics.headerHeight / 2
            )

            Text("선택  \(selectedCandidateID == nil ? 0 : 1)  /  1")
                .font(.system(size: metrics.bodySize, weight: .medium, design: .serif))
                .foregroundStyle(RewardSelectionPalette.gold)
                .position(
                    x: metrics.size.width - metrics.headerLeading - 52,
                    y: metrics.headerTop + metrics.bodySize / 2
                )
        }
        .frame(width: metrics.size.width, height: metrics.size.height)
    }

    private func cards(metrics: RewardLayoutMetrics) -> some View {
        HStack(spacing: metrics.cardSpacing) {
            ForEach(candidates) { candidate in
                rewardScroll(candidate, metrics: metrics)
            }
        }
        .frame(width: metrics.size.width)
        .position(x: metrics.size.width / 2, y: metrics.cardsCenterY)
    }

    private func rewardScroll(
        _ candidate: RewardCandidate,
        metrics: RewardLayoutMetrics
    ) -> some View {
        let isSelected = selectedCandidateID == candidate.id
        let isDiscarded = isResolving && !isSelected
        let spell = displayedSpell(for: candidate)

        return ZStack {
            if isSelected {
                Image("RewardScrollSelectionGlow")
                    .resizable()
                    .scaledToFit()
                    .frame(width: metrics.cardWidth, height: metrics.cardHeight)
                    .blendMode(.screen)
                    .opacity(appSettings.reducedMotion ? 0.68 : 0.82)
                    .allowsHitTesting(false)
            }

            Image(cardFrameAsset(isSelected: isSelected, isDisabled: isDiscarded))
                .resizable()
                .scaledToFill()
                .frame(width: metrics.cardWidth, height: metrics.cardHeight)
                .clipped()

            VStack(spacing: 0) {
                Text("\(categoryTitle(candidate.category)) · \(tierTitle(candidate.tier))")
                    .font(.system(size: metrics.cardCaptionSize, weight: .medium, design: .serif))
                    .foregroundStyle(categoryColor(candidate.category))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .frame(maxWidth: metrics.cardWidth * 0.72)
                    .padding(.top, metrics.cardHeight * 0.18)

                ZStack {
                    Image("RewardScrollGlyphBackplate")
                        .resizable()
                        .scaledToFit()
                        .opacity(0.2)
                    Image(spell.rewardGlyphAssetName)
                        .resizable()
                        .scaledToFit()
                        .blendMode(.screen)
                        .padding(metrics.cardWidth * 0.08)
                }
                .frame(width: metrics.glyphSize, height: metrics.glyphSize)
                .padding(.top, metrics.cardHeight * 0.018)

                Spacer(minLength: 0)
                Rectangle()
                    .fill(RewardSelectionPalette.gold.opacity(0.24))
                    .frame(height: 1)
                    .padding(.horizontal, metrics.cardWidth * 0.11)

                Text(displayedName(for: candidate, spell: spell))
                    .font(.system(size: metrics.cardTitleSize, weight: .medium, design: .serif))
                    .foregroundStyle(RewardSelectionPalette.gold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .frame(maxWidth: metrics.cardWidth * 0.76)
                    .padding(.top, metrics.cardHeight * 0.025)
                Text(summaryLine(for: spell))
                    .font(.system(size: metrics.cardBodySize, design: .serif).monospacedDigit())
                    .foregroundStyle(RewardSelectionPalette.body.opacity(0.86))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: metrics.cardWidth * 0.78)
                    .padding(.top, 7)
                Text(effectDescription(for: spell))
                    .font(.system(size: metrics.cardBodySize, design: .serif))
                    .foregroundStyle(RewardSelectionPalette.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .frame(height: metrics.cardHeight * 0.09, alignment: .top)
                    .frame(maxWidth: metrics.cardWidth * 0.78)
                    .padding(.top, 8)
                tagRow(for: spell, fontSize: metrics.tagSize)
                    .padding(.bottom, isSelected ? metrics.cardHeight * 0.095 : metrics.cardHeight * 0.115)
            }
            .frame(width: metrics.cardWidth, height: metrics.cardHeight)

            if isSelected {
                ZStack {
                    Image("RewardScrollSelectedLabel")
                        .resizable()
                        .scaledToFill()
                    Text("선택됨")
                        .font(.system(size: metrics.cardCaptionSize, weight: .medium, design: .serif))
                        .foregroundStyle(RewardSelectionPalette.violet.opacity(0.96))
                }
                .frame(width: metrics.cardWidth * 0.7, height: metrics.cardHeight * 0.075)
                .clipped()
                .offset(y: metrics.cardHeight * 0.49)
            }
        }
        .frame(width: metrics.cardWidth, height: metrics.cardHeight)
        .contentShape(Rectangle())
        .offset(y: isSelected ? -metrics.selectedLift : 0)
        .scaleEffect(isDiscarded ? 0.9 : 1)
        .opacity(isDiscarded ? 0.18 : 1)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isSelected)
        .onTapGesture {
            guard !isResolving else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                selectedCandidateID = candidate.id
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let movement = hypot(
                        value.location.x - value.startLocation.x,
                        value.location.y - value.startLocation.y
                    )
                    guard movement <= 28 else {
                        cancelDetailPress()
                        return
                    }
                    beginDetailPress(for: candidate.id)
                }
                .onEnded { _ in cancelDetailPress() }
        )
        .allowsHitTesting(!isResolving)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(displayedName(for: candidate, spell: spell)), "
                + "\(categoryTitle(candidate.category)), \(tierTitle(candidate.tier))"
        )
        .accessibilityHint("탭하여 선택하고 길게 눌러 상세 정보를 확인합니다")
    }

    private func footer(metrics: RewardLayoutMetrics) -> some View {
        VStack(spacing: 3) {
            Button(action: confirmSelection) {
                Text(isResolving ? "선택 기록 복원 중" : "선택 두루마리 수령")
                    .font(.system(size: metrics.confirmTextSize, weight: .medium, design: .serif))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(RewardConfirmButtonStyle())
            .frame(width: metrics.confirmWidth, height: metrics.confirmHeight)
            .clipped()
            .disabled(selectedCandidateID == nil || isResolving)

            Text("수령 후 나머지 기록은 즉시 말소됩니다.")
                .font(.system(size: metrics.footerSize, design: .serif))
                .foregroundStyle(RewardSelectionPalette.secondary)
            Label("카드를 길게 눌러 문양 상세 확인", systemImage: "info.circle")
                .font(.system(size: metrics.footerSize, design: .serif))
                .foregroundStyle(RewardSelectionPalette.body.opacity(0.78))
                .frame(width: metrics.size.width - metrics.headerLeading * 2, alignment: .leading)
                .offset(y: -metrics.confirmHeight * 0.58)
        }
        .position(x: metrics.size.width / 2, y: metrics.footerCenterY)
    }

    private func detailPanel(
        for candidate: RewardCandidate,
        metrics: RewardLayoutMetrics
    ) -> some View {
        let spell = displayedSpell(for: candidate)

        return ZStack {
            Image("RewardScrollDetailPanel")
                .resizable()
                .scaledToFill()
            VStack(spacing: 7) {
                Text(displayedName(for: candidate, spell: spell))
                    .font(.system(size: metrics.detailTitleSize, weight: .medium, design: .serif))
                    .foregroundStyle(RewardSelectionPalette.gold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("\(categoryTitle(candidate.category)) · \(tierTitle(candidate.tier)) · \(spell.glyph.difficulty.rewardTitle)")
                    .font(.system(size: metrics.cardBodySize, weight: .medium, design: .serif))
                    .foregroundStyle(categoryColor(candidate.category))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                HStack(spacing: 18) {
                    ZStack {
                        Image("RewardScrollGlyphBackplate")
                            .resizable()
                            .scaledToFit()
                            .opacity(0.22)
                        Image(spell.rewardGlyphAssetName)
                            .resizable()
                            .scaledToFit()
                            .blendMode(.screen)
                            .padding(12)
                    }
                    .frame(width: metrics.detailGlyphSize, height: metrics.detailGlyphSize)
                    Rectangle()
                        .fill(RewardSelectionPalette.gold.opacity(0.28))
                        .frame(width: 1, height: metrics.detailGlyphSize * 0.8)
                    VStack(alignment: .leading, spacing: 5) {
                        detailRow("효과 범위", spell.rewardEffectRangeTitle)
                        detailRow("소모 마나", "\(Int(spell.recommendedMana))%")
                        detailRow("필요 획", "\(spell.requiredStrokes)")
                        Text(effectDescription(for: spell))
                            .foregroundStyle(RewardSelectionPalette.body)
                            .lineLimit(2)
                            .minimumScaleFactor(0.78)
                            .padding(.top, 3)
                    }
                    .font(.system(size: metrics.detailBodySize, design: .serif).monospacedDigit())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
                }
                Text("누르는 동안 상세 표시 · 손을 떼면 닫힘")
                    .font(.system(size: metrics.footerSize, design: .serif))
                    .foregroundStyle(RewardSelectionPalette.secondary)
            }
            .padding(.horizontal, metrics.detailWidth * 0.08)
            .padding(.vertical, metrics.detailHeight * 0.08)
        }
        .frame(width: metrics.detailWidth, height: metrics.detailHeight)
        .clipped()
        .position(x: metrics.size.width / 2, y: metrics.detailCenterY)
        .allowsHitTesting(false)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .foregroundStyle(RewardSelectionPalette.gold)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 28)
        }
        .frame(maxWidth: .infinity)
    }

    private func tagRow(for spell: SpellDefinition, fontSize: CGFloat) -> some View {
        HStack(spacing: 7) {
            ForEach(effectTags(for: spell), id: \.self) { tag in
                Text(tag)
                    .font(.system(size: fontSize, weight: .medium, design: .serif))
                    .foregroundStyle(categoryColor(spell.category))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .overlay {
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(categoryColor(spell.category).opacity(0.6), lineWidth: 1)
                    }
            }
        }
    }

    private var inspectedCandidate: RewardCandidate? {
        guard let inspectedCandidateID else { return nil }
        return candidates.first { $0.id == inspectedCandidateID }
    }

    private func beginDetailPress(for candidateID: String) {
        guard detailPressTask == nil, inspectedCandidateID == nil else { return }
        detailPressTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            inspectedCandidateID = candidateID
        }
    }

    private func cancelDetailPress() {
        detailPressTask?.cancel()
        detailPressTask = nil
        inspectedCandidateID = nil
    }

    private func displayedSpell(for candidate: RewardCandidate) -> SpellDefinition {
        if let id = candidate.resolvedSpell { return SpellCatalog.spell(id) }
        switch candidate.category {
        case .attack: return SpellCatalog.riftSeverance
        case .defense: return SpellCatalog.basicBarrier
        case .dispel: return SpellCatalog.sealRelease
        }
    }

    private func displayedName(for candidate: RewardCandidate, spell: SpellDefinition) -> String {
        candidate.resolvedSpell == nil ? candidate.obscuredName : spell.name
    }

    private func summaryLine(for spell: SpellDefinition) -> String {
        "\(spell.rewardEffectRangeTitle) · 마나 \(Int(spell.recommendedMana))% · \(spell.requiredStrokes)획"
    }

    private func effectDescription(for spell: SpellDefinition) -> String {
        switch spell.effect {
        case let .damage(_, _, piercesNormalBarrier):
            return piercesNormalBarrier
                ? "일반 방벽을 관통하고 피해를 줍니다."
                : "대상에게 직접 피해를 줍니다."
        case .fixedBarrier:
            return "다음 공격을 흡수할 일반 방벽을 생성합니다."
        case .dispelAbsoluteBarrier:
            return "대상의 절대 방벽을 해제합니다."
        }
    }

    private func effectTags(for spell: SpellDefinition) -> [String] {
        switch spell.effect {
        case let .damage(_, _, pierces): return pierces ? ["희귀", "방벽 파괴"] : ["직접 피해"]
        case .fixedBarrier: return ["생존"]
        case .dispelAbsoluteBarrier: return ["해제"]
        }
    }

    private func cardFrameAsset(isSelected: Bool, isDisabled: Bool) -> String {
        if isDisabled { return "RewardScrollCardFrameDisabled" }
        return isSelected ? "RewardScrollCardFrameSelected" : "RewardScrollCardFrameDefault"
    }

    private func categoryTitle(_ category: SpellCategory) -> String {
        switch category {
        case .attack: "공격"
        case .defense: "방어"
        case .dispel: "해제"
        }
    }

    private func tierTitle(_ tier: ScrollTier) -> String {
        switch tier {
        case .worn: "낡은 주문서"
        case .engraved: "각인 주문서"
        case .sealed: "봉인 주문서"
        case .forbidden: "금서"
        }
    }

    private func categoryColor(_ category: SpellCategory) -> Color {
        switch category {
        case .attack: RewardSelectionPalette.violet
        case .defense: RewardSelectionPalette.cyan
        case .dispel: Color(red: 0.94, green: 0.72, blue: 0.22)
        }
    }

    private func confirmSelection() {
        guard let selectedCandidateID, !isResolving else { return }
        guard let selectedIndex = candidates.firstIndex(where: { $0.id == selectedCandidateID }) else {
            return
        }
        withAnimation(.easeInOut(duration: 0.45)) { isResolving = true }
        setRewardState(.resolving(selectedIndex: selectedIndex))
        transitionTask?.cancel()
        transitionTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(appSettings.reducedMotion ? 20 : 460))
            guard !Task.isCancelled else { return }
            setRewardState(.resolved(selectedIndex: selectedIndex))
            try? await Task.sleep(for: .milliseconds(appSettings.reducedMotion ? 20 : 390))
            guard !Task.isCancelled else { return }
            gameSession.send(.selectReward(selectedCandidateID))
        }
    }

    private func setRewardState(_ state: RealityRewardPresentationState) {
        rewardState = state
        sceneController.setRewardPresentation(state, reducedMotion: appSettings.reducedMotion)
    }
}

private struct RewardLayoutMetrics {
    let size: CGSize

    private var scale: CGFloat {
        min(size.width / 1366, size.height / 768).clamped(to: 0.72...1.2)
    }

    var headerLeading: CGFloat { max(34, size.width * 0.035) }
    var headerTop: CGFloat { max(24, size.height * 0.035) }
    var headerWidth: CGFloat { min(480, size.width * 0.36) }
    var headerHeight: CGFloat { 126 * scale }
    var headerSpacing: CGFloat { 4 * scale }
    var eyebrowSize: CGFloat { 17 * scale }
    var titleSize: CGFloat { 34 * scale }
    var bodySize: CGFloat { 16 * scale }
    var cardWidth: CGFloat { min(350, (size.width - 64) / 3.18) }
    var cardHeight: CGFloat { cardWidth * 1.333 }
    var cardSpacing: CGFloat { max(22, 30 * scale) }
    var cardsCenterY: CGFloat { size.height * 0.54 }
    var selectedLift: CGFloat { 18 * scale }
    var glyphSize: CGFloat { cardWidth * 0.52 }
    var cardCaptionSize: CGFloat { 15 * scale }
    var cardTitleSize: CGFloat { 24 * scale }
    var cardBodySize: CGFloat { 13 * scale }
    var tagSize: CGFloat { 11 * scale }
    var confirmWidth: CGFloat { min(390 * scale, size.width * 0.33) }
    var confirmHeight: CGFloat { 74 * scale }
    var confirmTextSize: CGFloat { 23 * scale }
    var footerSize: CGFloat { 13 * scale }
    var footerCenterY: CGFloat { size.height - confirmHeight * 0.67 }
    var detailWidth: CGFloat { min(580 * scale, size.width * 0.48) }
    var detailHeight: CGFloat { 245 * scale }
    var detailCenterY: CGFloat { headerTop + detailHeight * 0.58 }
    var detailGlyphSize: CGFloat { 118 * scale }
    var detailTitleSize: CGFloat { 23 * scale }
    var detailBodySize: CGFloat { 13 * scale }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}

private extension GlyphDifficulty {
    var rewardTitle: String {
        switch self {
        case .easy: "쉬움"
        case .normal: "보통"
        case .hard: "어려움"
        }
    }
}

private extension SpellDefinition {
    var rewardGlyphAssetName: String {
        switch id {
        case .afterglowErasure: "BattleGlyphAfterglowErasure"
        case .riftSeverance: "BattleGlyphRiftSeverance"
        case .barrierPiercing: "BattleGlyphBarrierPiercing"
        case .basicBarrier: "BattleGlyphBasicBarrier"
        case .sealRelease: "BattleGlyphSealRelease"
        }
    }

    var rewardEffectRangeTitle: String {
        let range = effect.range
        switch category {
        case .attack: return "피해 \(range.lowerBound)~\(range.upperBound)"
        case .defense: return "방어막 \(range.lowerBound)~\(range.upperBound)"
        case .dispel: return "해제 \(range.lowerBound)~\(range.upperBound)"
        }
    }
}
