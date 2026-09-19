import SwiftUI

// Source PNGs retain transparent canvas margins. Crop only that canvas once,
// so the visible border and the SwiftUI control have the same bounds.
private enum LoadoutArtwork {
    static let images: [String: UIImage] = {
        let bounds: [String: CGRect] = [
            "LoadoutBackButton": CGRect(x: 47, y: 160, width: 1850, height: 485),
            "LoadoutBattleStartDisabled": CGRect(x: 14, y: 138, width: 1994, height: 459),
            "LoadoutBattleStartEnabled": CGRect(x: 18, y: 181, width: 1921, height: 431),
            "LoadoutMainPanelFrame": CGRect(x: 29, y: 31, width: 1614, height: 872),
            "LoadoutInspectorPanelFrame": CGRect(x: 39, y: 37, width: 947, height: 1460),
            "LoadoutSpellCardDefault": CGRect(x: 41, y: 206, width: 1867, height: 387),
            "LoadoutSpellCardSelected": CGRect(x: 55, y: 96, width: 1984, height: 540),
            "LoadoutProgressBadge": CGRect(x: 59, y: 206, width: 1742, height: 427),
            "LoadoutEquippedSlotEmpty": CGRect(x: 55, y: 275, width: 1503, height: 455),
            "LoadoutEquippedSlotSelected": CGRect(x: 36, y: 265, width: 1542, height: 441),
            "LoadoutProtectionSelector": CGRect(x: 37, y: 83, width: 2023, height: 554),
            "LoadoutEquippedSlotDefault": CGRect(x: 13, y: 91, width: 616, height: 203)
        ]
        return bounds.reduce(into: [:]) { result, entry in
            guard let source = UIImage(named: entry.key),
                  let cropped = source.cgImage?.cropping(to: entry.value) else { return }
            result[entry.key] = UIImage(cgImage: cropped, scale: 2, orientation: .up)
        }
    }()

    static func image(_ name: String) -> Image {
        images[name].map { Image(uiImage: $0) } ?? Image(name)
    }
}

struct LoadoutPreparationView: View {
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var gameFeedback: GameFeedbackManager
    @EnvironmentObject private var gameSession: GameSessionStore

    let onBegin: () -> Void
    let onCancel: () -> Void

    @State private var selected: [SpellID] = []
    @State private var protectedAttack: SpellID?
    @State private var protectedDefense: SpellID?
    @State private var inspected: SpellID?
    @State private var filter: SpellCategory?
    @State private var hasLoaded = false
    @State private var isStarting = false

    private let categories: [SpellCategory] = [.attack, .defense, .dispel, .debuff]

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 14) {
                header
                if !tutorialFlags.isEmpty { tutorialBanner }

                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 14) {
                        equippedSection
                            .tutorialTarget("loadout.slots")
                        collection
                            .tutorialTarget("loadout.collection")
                    }
                    .padding(24)
                    .background {
                        LoadoutArtwork.image("LoadoutMainPanelFrame")
                            .resizable(
                                capInsets: EdgeInsets(top: 28, leading: 28, bottom: 28, trailing: 28),
                                resizingMode: .stretch
                            )
                            .renderingMode(.original)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    commandPanel
                        .frame(width: min(max(proxy.size.width * 0.29, 330), 410))
                        .frame(maxHeight: .infinity)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .allowsHitTesting(preparationCoachStep == nil)
            .accessibilityHidden(preparationCoachStep != nil)
            .background {
                ZStack {
                    LinearGradient(
                        colors: [DAColor.background.opacity(0.99), DAColor.panel.opacity(0.98)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    RadialGradient(
                        colors: [DAColor.magic.opacity(0.09), .clear],
                        center: .center,
                        startRadius: 30,
                        endRadius: proxy.size.width * 0.55
                    )
                }
                .ignoresSafeArea()
            }
        }
        .tutorialCoach(
            step: preparationCoachStep,
            nextTitle: guideStep == .loadoutStart ? "준비하기" : "다음",
            onNext: advancePreparationGuide,
            onSkip: {}
        )
        .preferredColorScheme(.dark)
        .onAppear {
            loadSavedSelection()
            synchronizePreparationGuide()
        }
        .onChange(of: gameSession.progress.tutorialProgress.requestedReplay) { _, _ in
            synchronizePreparationGuide()
        }
    }

    private var guideStep: TutorialStepID? {
        Floor9LoadoutGuide.currentStep(in: gameSession.progress)
    }

    private var preparationCoachStep: TutorialCoachStep? {
        guard let step = guideStep else { return nil }
        let page = (Floor9LoadoutGuide.steps.firstIndex(of: step) ?? 0) + 1
        let title: String
        let message: String
        let targets: [TutorialTargetID]
        let placement: TutorialCoachStep.Placement
        switch step {
        case .loadoutOverview:
            title = "전투에 가져갈 주문을 준비하세요"
            message = "이곳에서 배운 주문을 골라 전투에 가져갑니다. 지금은 알고 있는 주문만으로 준비할 수 있습니다. 화면을 차례로 살펴볼게요."
            targets = []
            placement = .center
        case .loadoutCollection:
            title = "보유 주문에서 골라 담기"
            message = "주문을 누르면 오른쪽에서 효과를 확인할 수 있습니다. 카드의 + 버튼으로 편성하고, − 버튼으로 뺄 수 있습니다."
            targets = ["loadout.collection"]
            placement = .top
        case .loadoutSlots:
            title = "최대 여섯 칸, 원하는 순서로"
            message = "위쪽 슬롯의 왼쪽부터 전투 카드에 표시됩니다. 선택 주문의 ‘앞으로·뒤로’로 순서를 바꿀 수 있습니다. 여섯 칸을 모두 채울 필요는 없지만 공격 주문은 하나 이상 남겨 주세요."
            targets = ["loadout.slots"]
            placement = .bottom
        default:
            title = "준비가 끝나면 시작하기"
            message = "아래 ‘준비하기’를 누르면 직접 편성할 수 있습니다. ‘시작하기’를 눌러야 관리자의 대화가 시작됩니다. ‘돌아가기’를 누르면 진입 화면으로 돌아갑니다."
            targets = ["loadout.start"]
            placement = .top
        }
        return TutorialCoachStep(id: step, title: "\(page) / 4 · \(title)", message: message,
                                 targetIDs: targets, placement: placement, showsSkip: false)
    }

    private func synchronizePreparationGuide() {
        guard let step = guideStep,
              gameSession.progress.tutorialProgress.activeSequence != .floor9Loadout else { return }
        gameSession.send(.beginTutorial(sequence: .floor9Loadout, step: step))
    }

    private func advancePreparationGuide() {
        guard let step = guideStep else { return }
        let next = Floor9LoadoutGuide.next(after: step)
        // Keep a valid resumable step until completing the sequence is saved.
        guard gameSession.sendChecked(.completeTutorialStep(step: step, next: next ?? step)) else { return }
        if next == nil {
            guard gameSession.sendChecked(.completeTutorial(.floor9Loadout)) else { return }
        }
        gameFeedback.playInterface(.confirm, settings: appSettings.settings)
    }

    private var learned: [SpellID] {
        SpellID.allCases.filter(gameSession.progress.learnedSpells.contains)
    }

    private var visibleSpells: [SpellID] {
        learned.filter { filter == nil || SpellCatalog.spell($0).category == filter }
    }

    private var issues: [LoadoutValidationIssue] {
        LoadoutRules.issues(for: selected, learned: gameSession.progress.learnedSpells)
    }

    private var tutorialFlags: [LoadoutTutorialFlag] {
        var flags: [LoadoutTutorialFlag] = []
        if learned.count >= 6, !gameSession.progress.loadoutTutorials.contains(.firstSixLoadout) {
            flags.append(.firstSixLoadout)
        }
        if learned.count > 6, !gameSession.progress.loadoutTutorials.contains(.firstOverflowLoadout) {
            flags.append(.firstOverflowLoadout)
        }
        return flags
    }

    private var floorNumber: Int {
        gameSession.progress.expansion?.floorNumber ?? gameSession.progress.currentFloor.rawValue
    }

    private var header: some View {
        HStack(spacing: 16) {
            Button {
                gameFeedback.playInterface(.back, settings: appSettings.settings)
                onCancel()
            } label: {
                ZStack {
                    LoadoutArtwork.image("LoadoutBackButton")
                        .resizable()

                    Label("돌아가기", systemImage: "chevron.left")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(DAColor.secondary)
                }
                .frame(width: 124, height: 48)
                .clipped()
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text("제\(floorNumber)층 · 출전 준비")
                    .font(.system(size: 26, weight: .semibold, design: .serif))
                    .foregroundStyle(DAColor.gold)
                Text("전투에 가져갈 주문을 선택하세요.")
                    .font(.callout)
                    .foregroundStyle(DAColor.secondary)
            }

            Spacer(minLength: 12)

            if floorNumber == 9 {
                Button("사용법") {
                    gameSession.send(.requestTutorialReplay(.floor9Loadout))
                }
                .buttonStyle(.bordered)
                .tint(DAColor.gold)
                .accessibilityLabel("출전 준비 사용법 다시 보기")
            }

            VStack(alignment: .trailing, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(selected.count)")
                        .font(.title2.monospacedDigit().weight(.bold))
                        .foregroundStyle(DAColor.body)
                    Text("/ \(LoadoutRules.maximumEquipped)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(DAColor.secondary)
                }
                ProgressView(value: Double(selected.count), total: Double(LoadoutRules.maximumEquipped))
                    .tint(DAColor.gold)
                    .frame(width: 116)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background {
                LoadoutArtwork.image("LoadoutProgressBadge")
                    .resizable()

            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("준비한 주문 \(selected.count)개, 최대 \(LoadoutRules.maximumEquipped)개")
        }
    }

    private var tutorialBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles.rectangle.stack.fill")
                .font(.title3)
                .foregroundStyle(DAColor.gold)
            VStack(alignment: .leading, spacing: 2) {
                Text(tutorialFlags.contains(.firstOverflowLoadout) ? "보유 주문 중 최대 6종을 선택합니다" : "공격·방어·봉인 해제를 포함해 준비하세요")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DAColor.body)
                Text("공격과 방어 주문은 각각 하나씩 자동으로 봉인에서 보호됩니다.")
                    .font(.caption)
                    .foregroundStyle(DAColor.secondary)
            }
            Spacer(minLength: 0)
            Button("안내 확인") { acknowledgeTutorials() }
                .buttonStyle(.borderedProminent)
                .tint(DAColor.magic.opacity(0.72))
                .frame(minWidth: 96, minHeight: 42)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(DAColor.magic.opacity(0.12))
        .overlay { RoundedRectangle(cornerRadius: 8).stroke(DAColor.gold.opacity(0.38)) }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var equippedSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionHeader(title: "전투 편성", note: "왼쪽부터 전투 카드에 표시됩니다")
            HStack(spacing: 8) {
                ForEach(0..<LoadoutRules.maximumEquipped, id: \.self) { index in
                    if selected.indices.contains(index) {
                        equippedSlot(selected[index], index: index)
                    } else {
                        emptyEquippedSlot(index: index)
                    }
                }
            }
        }
        .padding(14)
        .background(DAColor.background.opacity(0.36))
    }

    private func sectionHeader(title: String, note: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
                .foregroundStyle(DAColor.body)
            Spacer(minLength: 8)
            Text(note)
                .font(.caption)
                .foregroundStyle(DAColor.secondary)
        }
    }

    private func emptyEquippedSlot(index: Int) -> some View {
        VStack(spacing: 5) {
            Text("\(index + 1)")
                .font(.caption2.monospacedDigit())
            Image(systemName: "plus")
                .font(.callout.weight(.light))
            Text("빈 자리")
                .font(.caption2)
        }
        .foregroundStyle(DAColor.secondary.opacity(0.58))
        .frame(maxWidth: .infinity)
        .frame(height: 78)
        .background {
            LoadoutArtwork.image("LoadoutEquippedSlotEmpty")
                .resizable()

        }
        .clipped()
        .accessibilityLabel("\(index + 1)번 빈 주문 자리")
    }

    private func equippedSlot(_ id: SpellID, index: Int) -> some View {
        let spell = SpellCatalog.spell(id)
        return Button {
            inspected = id
            playSelection()
        } label: {
            VStack(spacing: 2) {
                HStack(spacing: 3) {
                    Text("\(index + 1)")
                        .font(.caption2.monospacedDigit())
                    Spacer(minLength: 0)
                    if protectedIDs.contains(id) {
                        Image(systemName: "lock.shield.fill")
                            .font(.caption2)
                            .foregroundStyle(DAColor.gold)
                    }
                }
                .foregroundStyle(DAColor.secondary)
                SpellGlyphPreview(spell: spell)
                    .frame(height: 34)
                Text(spell.name)
                    .font(.system(size: 11, weight: .semibold, design: .serif))
                    .foregroundStyle(DAColor.body)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(height: 78)
            .background {
                LoadoutArtwork.image(inspected == id ? "LoadoutEquippedSlotSelected" : "LoadoutEquippedSlotDefault")
                    .resizable()

            }
            .clipped()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(index + 1)번 \(spell.name)\(protectedIDs.contains(id) ? ", 봉인 보호" : "")")
    }

    private var collection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text("보유 주문 \(learned.count)종")
                    .font(.headline)
                    .foregroundStyle(DAColor.body)
                Spacer(minLength: 0)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        categoryButton(nil)
                        ForEach(categories, id: \.rawValue) { category in categoryButton(category) }
                    }
                }
            }

            ScrollView {
                if visibleSpells.isEmpty {
                    Text("아직 배운 \(filter.map(categoryTitle) ?? "") 주문이 없습니다.")
                        .font(.callout)
                        .foregroundStyle(DAColor.secondary)
                        .frame(maxWidth: .infinity, minHeight: 140)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 220, maximum: 300), spacing: 10)],
                        spacing: 10
                    ) {
                        ForEach(visibleSpells, id: \.rawValue) { id in collectionCard(id) }
                    }
                    .padding(.vertical, 2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(14)
        .background(DAColor.background.opacity(0.28))
    }

    private func categoryButton(_ category: SpellCategory?) -> some View {
        Button {
            filter = category
            playSelection()
        } label: {
            Text(category.map(categoryTitle) ?? "전체")
                .font(.caption.weight(.semibold))
                .foregroundStyle(filter == category ? DAColor.body : DAColor.secondary)
                .padding(.horizontal, 12)
                .frame(minHeight: 34)
                .background(filter == category ? DAColor.magic.opacity(0.25) : DAColor.card)
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(filter == category ? DAColor.gold.opacity(0.75) : DAColor.divider)
                }
        }
        .buttonStyle(.plain)
    }

    private func collectionCard(_ id: SpellID) -> some View {
        let spell = SpellCatalog.spell(id)
        let isEquipped = selected.contains(id)
        let isFull = selected.count >= LoadoutRules.maximumEquipped
        return HStack(spacing: 0) {
            Button {
                inspected = id
                playSelection()
            } label: {
                HStack(spacing: 14) {
                    SpellGlyphPreview(spell: spell)
                        .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 5) {
                            Text(spell.name)
                                .font(.system(size: 15, weight: .semibold, design: .serif))
                                .foregroundStyle(DAColor.body)
                                .lineLimit(1)
                            if protectedIDs.contains(id) {
                                Image(systemName: "lock.shield.fill")
                                    .font(.caption2)
                                    .foregroundStyle(DAColor.gold)
                            }
                        }
                        Text("\(categoryTitle(spell.category)) · \(tierTitle(spell.tier)) · \(spell.requiredStrokes)획")
                            .font(.caption2)
                            .foregroundStyle(categoryColor(spell.category))
                            .lineLimit(1)
                        Text(spell.compactEffectDescription)
                            .font(.caption)
                            .foregroundStyle(DAColor.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 2)
                }
                .padding(.leading, 12)
                .padding(.top, 24)
                .padding(.bottom, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button { toggle(id) } label: {
                Image(systemName: isEquipped ? "minus" : "plus")
                    .font(.headline)
                    .foregroundStyle(isEquipped ? DAColor.gold : DAColor.body)
                    .frame(width: 44)
                    .frame(maxHeight: .infinity)
                    .background(isEquipped ? DAColor.gold.opacity(0.09) : DAColor.magic.opacity(0.09))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isEquipped && isFull)
            .opacity(!isEquipped && isFull ? 0.28 : 1)
            .accessibilityLabel(isEquipped ? "\(spell.name) 준비에서 빼기" : "\(spell.name) 준비하기")
        }
        .frame(minHeight: 100)
        .padding(10)
        .background {
            LoadoutArtwork.image(inspected == id ? "LoadoutSpellCardSelected" : "LoadoutSpellCardDefault")
                .resizable()

        }
        .overlay(alignment: .topLeading) {
            if isEquipped {
                Text("편성 \((selected.firstIndex(of: id) ?? 0) + 1)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(DAColor.gold)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(DAColor.background.opacity(0.9))
                    .clipShape(Capsule())
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private var commandPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("선택 주문")
                    .font(.headline)
                    .foregroundStyle(DAColor.body)
                Spacer()
                if let id = inspected, selected.contains(id) {
                    Label("편성됨", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DAColor.gold)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(DAColor.card.opacity(0.46))

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let id = inspected, learned.contains(id) {
                        inspectedDetail(SpellCatalog.spell(id))
                    } else {
                        Text("주문을 선택하면 상세 정보를 확인할 수 있습니다.")
                            .font(.callout)
                            .foregroundStyle(DAColor.secondary)
                            .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                    }
                    Rectangle().fill(DAColor.divider).frame(height: 1)
                    protectionStatus
                }
                .padding(16)
            }

            Rectangle().fill(DAColor.divider).frame(height: 1)
            launchControls
        }
        .padding(24)
        .background {
            ZStack {
                DAColor.background.opacity(0.5)
                LoadoutArtwork.image("LoadoutInspectorPanelFrame")
                    .resizable(
                        capInsets: EdgeInsets(top: 44, leading: 28, bottom: 44, trailing: 28),
                        resizingMode: .stretch
                    )
                    .renderingMode(.original)
            }
        }
    }

    private func inspectedDetail(_ spell: SpellDefinition) -> some View {
        let metadata = SpellCatalog.metadata(for: spell.id)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                SpellGlyphPreview(spell: spell)
                    .frame(width: 70, height: 70)
                    .padding(5)
                    .background(DAColor.magic.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 5) {
                    Text(spell.name)
                        .font(.system(size: 20, weight: .semibold, design: .serif))
                        .foregroundStyle(DAColor.body)
                    Text("\(categoryTitle(spell.category)) · \(tierTitle(spell.tier))")
                        .font(.caption)
                        .foregroundStyle(categoryColor(spell.category))
                    Text("\(spell.requiredStrokes)획 · 기준 마나 \(Int(spell.recommendedMana))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(DAColor.secondary)
                }
            }

            Text(metadata.effectSummary)
                .font(.callout)
                .foregroundStyle(DAColor.body)
                .fixedSize(horizontal: false, vertical: true)
            Text(metadata.usageNote)
                .font(.caption)
                .foregroundStyle(DAColor.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(metadata.acquisitionLabel)
                .font(.caption2)
                .foregroundStyle(DAColor.gold.opacity(0.9))

            if let index = selected.firstIndex(of: spell.id) {
                HStack(spacing: 8) {
                    Button { move(spell.id, direction: -1) } label: {
                        Label("앞으로", systemImage: "arrow.left")
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .disabled(index == 0)
                    Button { move(spell.id, direction: 1) } label: {
                        Label("뒤로", systemImage: "arrow.right")
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .disabled(index == selected.count - 1)
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .tint(DAColor.gold)
            }
        }
    }

    private var protectionStatus: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("봉인 보호", systemImage: "lock.shield.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DAColor.gold)
            Text(LoadoutRules.protectionSummary(for: gameSession.progress.learnedSpells))
                .font(.caption)
                .foregroundStyle(DAColor.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(LoadoutRules.learnedProtectionCategories(in: gameSession.progress.learnedSpells), id: \.self) { category in
                protectionRow(
                    title: "보호 중인 \(categoryTitle(category)) 주문",
                    name: (category == .attack ? protectedAttack : protectedDefense).map { SpellCatalog.spell($0).name },
                    missing: "\(categoryTitle(category)) 주문을 추가해 주세요",
                    icon: category == .attack ? "burst.fill" : "shield.fill",
                    color: categoryColor(category)
                )
            }
            if gameSession.progress.learnedSpells.contains(.sealRelease) {
                protectionRow(title: "봉인 해제", name: selected.contains(.sealRelease) ? "필수 보호 적용" : nil,
                              missing: "전투 편성에 추가해야 합니다", icon: "lock.shield.fill", color: DAColor.gold)
            }
        }
    }

    private func protectionRow(title: String, name: String?, missing: String, icon: String, color: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .foregroundStyle(color.opacity(name == nil ? 0.45 : 1))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(DAColor.secondary)
                Text(name ?? missing)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(name == nil ? DAColor.attack : DAColor.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .background {
            LoadoutArtwork.image("LoadoutProtectionSelector")
                .resizable()
                .opacity(name == nil ? 0.4 : 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var launchControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: readyToBegin ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(readyToBegin ? DAColor.gold : DAColor.attack)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(readyToBegin ? "출전 준비 완료" : "준비를 확인하세요")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(readyToBegin ? DAColor.body : DAColor.attack)
                    Text(readinessMessage)
                        .font(.caption2)
                        .foregroundStyle(DAColor.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button(action: beginBattle) {
                Label("시작하기", systemImage: "arrow.right")
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .foregroundStyle(readyToBegin && !isStarting ? DAColor.body : DAColor.secondary.opacity(0.62))
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background {
                        LoadoutArtwork.image(readyToBegin && !isStarting
                              ? "LoadoutBattleStartEnabled"
                              : "LoadoutBattleStartDisabled")
                            .resizable()

                    }
                    .clipped()
            }
            .buttonStyle(.plain)
            .disabled(!readyToBegin || isStarting)
            .tutorialTarget("loadout.start")
        }
        .padding(16)
        .background(DAColor.background.opacity(0.42))
    }

    private var readyToBegin: Bool {
        issues.isEmpty && tutorialFlags.isEmpty && guideStep == nil
    }

    private var readinessMessage: String {
        if !issues.isEmpty {
            return issues.map(\.message).joined(separator: " ")
        }
        if !tutorialFlags.isEmpty {
            return "상단 안내를 확인하면 전투를 시작할 수 있습니다."
        }
        return selected.count == LoadoutRules.maximumEquipped
            ? "여섯 주문의 순서와 봉인 보호 설정이 저장됩니다."
            : "빈 자리를 남긴 현재 편성으로도 시작할 수 있습니다."
    }

    private var protectedIDs: Set<SpellID> {
        var ids = Set([protectedAttack, protectedDefense].compactMap { $0 })
        if selected.contains(.sealRelease) { ids.insert(.sealRelease) }
        return ids
    }

    private func loadSavedSelection() {
        guard !hasLoaded else { return }
        hasLoaded = true
        selected = LoadoutRules.normalized(gameSession.progress.equippedSpells, learned: gameSession.progress.learnedSpells)
        protectedAttack = gameSession.progress.protectedAttack
        protectedDefense = gameSession.progress.protectedDefense
        normalizeProtection()
        inspected = selected.first ?? learned.first
    }

    private func toggle(_ id: SpellID) {
        if let index = selected.firstIndex(of: id) {
            selected.remove(at: index)
        } else {
            guard selected.count < LoadoutRules.maximumEquipped else { return }
            selected.append(id)
        }
        inspected = id
        normalizeProtection()
        playSelection()
    }

    private func move(_ id: SpellID, direction: Int) {
        guard let index = selected.firstIndex(of: id), selected.indices.contains(index + direction) else { return }
        selected.swapAt(index, index + direction)
        playSelection()
    }

    private func normalizeProtection() {
        protectedAttack = LoadoutRules.protectedSpell(preferred: protectedAttack, category: .attack, equipped: selected)
        protectedDefense = LoadoutRules.protectedSpell(preferred: protectedDefense, category: .defense, equipped: selected)
    }

    private func acknowledgeTutorials() {
        for flag in tutorialFlags {
            guard gameSession.sendChecked(.markLoadoutTutorial(flag)) else { return }
        }
        gameFeedback.playInterface(.confirm, settings: appSettings.settings)
    }

    private func beginBattle() {
        guard readyToBegin, !isStarting else { return }
        isStarting = true
        guard gameSession.sendChecked(.configureLoadout(selected, protectedAttack: protectedAttack, protectedDefense: protectedDefense)) else {
            isStarting = false
            return
        }
        gameFeedback.playInterface(.confirm, settings: appSettings.settings)
        onBegin()
        isStarting = false
    }

    private func playSelection() {
        gameFeedback.playInterface(.select, settings: appSettings.settings)
    }

    private func categoryTitle(_ category: SpellCategory) -> String {
        switch category {
        case .attack: "공격"
        case .defense: "방어"
        case .dispel: "해제"
        case .debuff: "디버프"
        }
    }

    private func categoryColor(_ category: SpellCategory) -> Color {
        switch category {
        case .attack: DAColor.attack
        case .defense: DAColor.defense
        case .dispel: DAColor.dispel
        case .debuff: DAColor.debuff
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

}
