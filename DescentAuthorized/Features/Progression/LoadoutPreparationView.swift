import SwiftUI

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
                        collection
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    commandPanel
                        .frame(width: min(max(proxy.size.width * 0.29, 330), 410))
                        .frame(maxHeight: .infinity)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
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
        .preferredColorScheme(.dark)
        .onAppear(perform: loadSavedSelection)
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
                Label("돌아가기", systemImage: "chevron.left")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(DAColor.secondary)
                    .frame(minWidth: 104, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(DAColor.secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text("제\(floorNumber)층 · 출전 준비")
                    .font(.system(size: 26, weight: .semibold, design: .serif))
                    .foregroundStyle(DAColor.gold)
                Text("전투에 가져갈 주문과 봉인에서 보호할 주문을 정하세요.")
                    .font(.callout)
                    .foregroundStyle(DAColor.secondary)
            }

            Spacer(minLength: 12)

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
            .daStatusPanel(accent: DAColor.gold)
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
                Text("공격과 방어 주문은 각각 하나씩 봉인에서 보호할 수 있습니다.")
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
        .background(DAColor.panel.opacity(0.82))
        .overlay { RoundedRectangle(cornerRadius: 8).stroke(DAColor.divider) }
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(DAColor.divider, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
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
            .background(inspected == id ? DAColor.magic.opacity(0.14) : DAColor.card)
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(inspected == id ? DAColor.gold : DAColor.divider, lineWidth: inspected == id ? 2 : 1)
            }
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
        .background(DAColor.panel.opacity(0.62))
        .overlay { RoundedRectangle(cornerRadius: 8).stroke(DAColor.divider) }
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
                HStack(spacing: 10) {
                    SpellGlyphPreview(spell: spell)
                        .frame(width: 62, height: 62)
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
                .padding(.vertical, 10)
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
        .background {
            Image(frameAsset(for: spell.category))
                .resizable()
                .scaledToFill()
                .opacity(isEquipped ? 0.62 : 0.32)
        }
        .background(DAColor.card)
        .overlay(alignment: .topLeading) {
            if isEquipped {
                Text("편성 \((selected.firstIndex(of: id) ?? 0) + 1)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(DAColor.gold)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(DAColor.background.opacity(0.9))
                    .clipShape(Capsule())
                    .padding(6)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(inspected == id ? DAColor.gold : isEquipped ? DAColor.gold.opacity(0.5) : DAColor.divider,
                        lineWidth: inspected == id ? 2 : 1)
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
            .background(DAColor.card.opacity(0.8))

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
                    protectionSelection
                }
                .padding(16)
            }

            Rectangle().fill(DAColor.divider).frame(height: 1)
            launchControls
        }
        .background(DAColor.panel)
        .overlay { RoundedRectangle(cornerRadius: 8).stroke(DAColor.gold.opacity(0.42)) }
        .clipShape(RoundedRectangle(cornerRadius: 8))
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

    private var protectionSelection: some View {
        VStack(alignment: .leading, spacing: 11) {
            VStack(alignment: .leading, spacing: 4) {
                Label("봉인 보호", systemImage: "lock.shield.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DAColor.gold)
                Text("선택한 공격·방어 주문과 봉인 해제는 카드 봉인 대상에서 제외됩니다.")
                    .font(.caption)
                    .foregroundStyle(DAColor.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            protectedRole(.attack, selectedID: $protectedAttack)
            protectedRole(.defense, selectedID: $protectedDefense)

            if gameSession.progress.learnedSpells.contains(.sealRelease) {
                HStack(spacing: 9) {
                    Image(systemName: selected.contains(.sealRelease) ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(selected.contains(.sealRelease) ? DAColor.gold : DAColor.attack)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("봉인 해제")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(DAColor.body)
                        Text(selected.contains(.sealRelease) ? "필수 보호 적용" : "전투 편성에 추가해야 합니다")
                            .font(.caption2)
                            .foregroundStyle(selected.contains(.sealRelease) ? DAColor.gold : DAColor.attack)
                    }
                    Spacer()
                }
                .padding(10)
                .background(DAColor.card.opacity(0.72))
                .overlay { RoundedRectangle(cornerRadius: 6).stroke(DAColor.divider) }
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func protectedRole(_ category: SpellCategory, selectedID: Binding<SpellID?>) -> some View {
        let options = selected.filter { SpellCatalog.spell($0).category == category }
        let currentName = selectedID.wrappedValue.map { SpellCatalog.spell($0).name }
        return Menu {
            ForEach(options, id: \.rawValue) { id in
                Button {
                    selectedID.wrappedValue = id
                    playSelection()
                } label: {
                    if selectedID.wrappedValue == id {
                        Label(SpellCatalog.spell(id).name, systemImage: "checkmark")
                    } else {
                        Text(SpellCatalog.spell(id).name)
                    }
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: category == .attack ? "burst.fill" : "shield.fill")
                    .foregroundStyle(categoryColor(category))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("보호할 \(categoryTitle(category)) 주문")
                        .font(.caption2)
                        .foregroundStyle(DAColor.secondary)
                    Text(currentName ?? "편성된 주문이 없습니다")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(currentName == nil ? DAColor.attack : DAColor.body)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(DAColor.secondary)
            }
            .padding(.horizontal, 11)
            .frame(minHeight: 52)
            .background(DAColor.card)
            .overlay { RoundedRectangle(cornerRadius: 6).stroke(DAColor.divider) }
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(options.isEmpty)
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
                Label("전투 시작", systemImage: "arrow.right")
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .foregroundStyle(DAColor.body)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background {
                        Image("Floor9EntryButtonPlate")
                            .resizable()
                            .scaledToFill()
                    }
                    .clipped()
            }
            .buttonStyle(.plain)
            .disabled(!readyToBegin || isStarting)
            .opacity(readyToBegin && !isStarting ? 1 : 0.38)
        }
        .padding(16)
        .background(DAColor.background.opacity(0.42))
    }

    private var readyToBegin: Bool {
        issues.isEmpty && tutorialFlags.isEmpty
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
        guard issues.isEmpty, tutorialFlags.isEmpty, !isStarting else { return }
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

    private func frameAsset(for category: SpellCategory) -> String {
        switch category {
        case .attack: "BattleCardFrameAttack"
        case .defense: "BattleCardFrameDefense"
        case .dispel, .debuff: "BattleCardFrameSeal"
        }
    }
}
