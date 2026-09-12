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
    @State private var practiceSpell: SpellID?
    @State private var showsPractice = false
    @State private var hasLoaded = false
    @State private var isStarting = false

    private let categories: [SpellCategory] = [.attack, .defense, .dispel, .debuff]

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 12) {
                header
                if !tutorialFlags.isEmpty { tutorialBanner }
                equippedStrip

                HStack(alignment: .top, spacing: 18) {
                    collection
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    detailPanel
                        .frame(width: min(360, proxy.size.width * 0.34))
                        .frame(maxHeight: .infinity)
                }
                footer
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background {
                LinearGradient(
                    colors: [DAColor.background.opacity(0.98), DAColor.panel.opacity(0.97)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: loadSavedSelection)
        .sheet(isPresented: $showsPractice) {
            if let practiceSpell {
                SpellPracticeSheet(spell: SpellCatalog.spell(practiceSpell))
            }
        }
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

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("제\(gameSession.progress.expansion?.floorNumber ?? gameSession.progress.currentFloor.rawValue)층 · 출전 준비")
                    .font(.system(size: 25, weight: .semibold, design: .serif))
                    .foregroundStyle(DAColor.gold)
                Text("전투에 사용할 주문을 가방에서 선택하세요. 시작 후에는 교체할 수 없습니다.")
                    .font(.callout)
                    .foregroundStyle(DAColor.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            Text("\(selected.count) / 6")
                .font(.title2.monospacedDigit().weight(.semibold))
                .foregroundStyle(DAColor.body)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .daStatusPanel(accent: DAColor.gold)
        }
        .accessibilityElement(children: .combine)
    }

    private var tutorialBanner: some View {
        HStack(spacing: 16) {
            Image(systemName: "bag.fill")
                .font(.title2)
                .foregroundStyle(DAColor.gold)
            VStack(alignment: .leading, spacing: 5) {
                Text(tutorialFlags.contains(.firstOverflowLoadout) ? "이제 사용할 주문을 골라 준비하세요" : "전투에는 최대 6개의 주문을 가져갑니다")
                    .font(.headline)
                    .foregroundStyle(DAColor.body)
                Text(tutorialFlags.contains(.firstOverflowLoadout)
                     ? "보유한 \(learned.count)종 중 최대 6종을 선택합니다. 준비 중인 주문을 빼고 새 주문을 넣을 수 있으며, 출력 저하 장착은 자유입니다. 봉인 해제와 공격·방어 각 1종은 반드시 남겨 주세요."
                     : "봉인 해제와 공격·방어 각 1종을 포함하세요. 공격·방어는 원하는 주문으로 지정할 수 있습니다. 여섯 칸을 모두 채우거나 지금 구성을 바꿀 필요는 없습니다.")
                    .font(.caption)
                    .foregroundStyle(DAColor.body.opacity(0.87))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button("확인") { acknowledgeTutorials() }
                .buttonStyle(.bordered)
                .tint(DAColor.gold)
                .frame(minWidth: 72, minHeight: 44)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(DAColor.magic.opacity(0.12))
        .overlay { RoundedRectangle(cornerRadius: 6).stroke(DAColor.gold.opacity(0.38)) }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var equippedStrip: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("준비한 주문")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DAColor.body)
                Spacer()
                Text("배치 순서대로 전투에 표시됩니다")
                    .font(.caption)
                    .foregroundStyle(DAColor.secondary)
            }
            HStack(spacing: 8) {
                ForEach(0..<LoadoutRules.maximumEquipped, id: \.self) { index in
                    if selected.indices.contains(index) {
                        equippedSlot(selected[index], index: index)
                    } else {
                        VStack(spacing: 7) {
                            Text("\(index + 1)").font(.caption.monospacedDigit())
                            Image(systemName: "plus").font(.title3.weight(.light))
                            Text("빈 자리").font(.caption)
                        }
                        .foregroundStyle(DAColor.secondary.opacity(0.65))
                        .frame(maxWidth: .infinity)
                        .frame(height: 103)
                        .overlay {
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(DAColor.divider, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        }
                        .accessibilityLabel("\(index + 1)번 빈 주문 자리")
                    }
                }
            }
        }
    }

    private func equippedSlot(_ id: SpellID, index: Int) -> some View {
        let spell = SpellCatalog.spell(id)
        return Button {
            inspected = id
            playSelection()
        } label: {
            VStack(spacing: 3) {
                HStack {
                    Text("\(index + 1)").font(.caption.monospacedDigit())
                    Spacer(minLength: 2)
                    if protectedIDs.contains(id) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(DAColor.gold)
                    }
                }
                .font(.caption)
                .foregroundStyle(DAColor.secondary)
                SpellGlyphPreview(spell: spell)
                    .frame(height: 43)
                Text(spell.name)
                    .font(.system(size: 12, weight: .medium, design: .serif))
                    .foregroundStyle(DAColor.body)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("\(categoryTitle(spell.category)) · \(spell.requiredStrokes)획")
                    .font(.system(size: 10))
                    .foregroundStyle(categoryColor(spell.category))
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 103)
            .background(DAColor.card)
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(inspected == id ? DAColor.gold : DAColor.divider, lineWidth: inspected == id ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(index + 1)번 \(spell.name)\(protectedIDs.contains(id) ? ", 봉인 보호" : "")")
    }

    private var collection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("가방 · 보유 \(learned.count)종")
                    .font(.headline)
                    .foregroundStyle(DAColor.body)
                Spacer(minLength: 0)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    categoryButton(nil)
                    ForEach(categories, id: \.rawValue) { category in categoryButton(category) }
                }
            }
            ScrollView {
                if visibleSpells.isEmpty {
                    Text("아직 배운 \(filter.map(categoryTitle) ?? "") 주문이 없습니다.")
                        .font(.callout)
                        .foregroundStyle(DAColor.secondary)
                        .frame(maxWidth: .infinity, minHeight: 100)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 135, maximum: 185), spacing: 10)], spacing: 10) {
                        ForEach(visibleSpells, id: \.rawValue) { id in collectionCard(id) }
                    }
                    .padding(.vertical, 3)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func categoryButton(_ category: SpellCategory?) -> some View {
        Button {
            filter = category
            playSelection()
        } label: {
            Text(category.map(categoryTitle) ?? "전체")
                .font(.caption.weight(.semibold))
                .foregroundStyle(filter == category ? DAColor.body : DAColor.secondary)
                .padding(.horizontal, 13)
                .frame(minHeight: 36)
                .background(filter == category ? DAColor.magic.opacity(0.25) : DAColor.card)
                .overlay { RoundedRectangle(cornerRadius: 4).stroke(filter == category ? DAColor.gold.opacity(0.7) : DAColor.divider) }
        }
        .buttonStyle(.plain)
    }

    private func collectionCard(_ id: SpellID) -> some View {
        let spell = SpellCatalog.spell(id)
        let isEquipped = selected.contains(id)
        return VStack(spacing: 0) {
            Button {
                inspected = id
                playSelection()
            } label: {
                VStack(spacing: 5) {
                    SpellGlyphPreview(spell: spell).frame(height: 60)
                    Text(spell.name)
                        .font(.system(size: 14, weight: .semibold, design: .serif))
                        .foregroundStyle(DAColor.body)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("\(tierTitle(spell.tier)) · \(spell.requiredStrokes)획")
                        .font(.system(size: 10))
                        .foregroundStyle(DAColor.gold)
                    Text(spell.compactEffectDescription)
                        .font(.caption2)
                        .foregroundStyle(categoryColor(spell.category))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.horizontal, 10)
                .padding(.top, 18)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            Button {
                toggle(id)
            } label: {
                Label(isEquipped ? "준비에서 빼기" : "준비하기", systemImage: isEquipped ? "minus.circle" : "plus.circle")
                    .font(.caption.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 38)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isEquipped ? DAColor.gold : DAColor.body)
            .disabled(!isEquipped && selected.count >= LoadoutRules.maximumEquipped)
            .opacity(!isEquipped && selected.count >= LoadoutRules.maximumEquipped ? 0.35 : 1)
        }
        .background {
            Image(frameAsset(for: spell.category))
                .resizable()
                .opacity(0.8)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(inspected == id ? DAColor.gold : DAColor.divider, lineWidth: inspected == id ? 2 : 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var detailPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let id = inspected, learned.contains(id) {
                    inspectedDetail(SpellCatalog.spell(id))
                } else {
                    Text("주문을 선택하면 상세 정보를 확인할 수 있습니다.")
                        .font(.callout)
                        .foregroundStyle(DAColor.secondary)
                }
                Rectangle().fill(DAColor.divider).frame(height: 1)
                protectionSelection
            }
            .padding(16)
        }
        .background(DAColor.panel)
        .overlay {
            RoundedRectangle(cornerRadius: 6).stroke(DAColor.gold.opacity(0.35))
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func inspectedDetail(_ spell: SpellDefinition) -> some View {
        let metadata = SpellCatalog.metadata(for: spell.id)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                SpellGlyphPreview(spell: spell).frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 5) {
                    Text(spell.name)
                        .font(.system(size: 19, weight: .semibold, design: .serif))
                        .foregroundStyle(DAColor.body)
                    Text("\(categoryTitle(spell.category)) · \(tierTitle(spell.tier))")
                        .font(.caption)
                        .foregroundStyle(categoryColor(spell.category))
                    Text("\(spell.requiredStrokes)획 · 기준 마나 약 \(Int(spell.recommendedMana))%")
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

            Button {
                practiceSpell = spell.id
                showsPractice = true
                playSelection()
            } label: {
                Label("시험 각인", systemImage: "pencil.and.outline")
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.bordered)
            .tint(DAColor.magicGlow)

            if let index = selected.firstIndex(of: spell.id) {
                HStack {
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
        VStack(alignment: .leading, spacing: 10) {
            Label("기본 대응 주문", systemImage: "lock.shield")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DAColor.gold)
            Text("지정한 공격·방어와 봉인 해제는 적의 카드 봉인에서 보호됩니다.")
                .font(.caption)
                .foregroundStyle(DAColor.secondary)
                .fixedSize(horizontal: false, vertical: true)
            protectedRole(.attack, selectedID: $protectedAttack)
            protectedRole(.defense, selectedID: $protectedDefense)
            if gameSession.progress.learnedSpells.contains(.sealRelease) {
                Label("봉인 해제 · 필수", systemImage: selected.contains(.sealRelease) ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(selected.contains(.sealRelease) ? DAColor.gold : DAColor.attack)
            }
        }
    }

    private func protectedRole(_ category: SpellCategory, selectedID: Binding<SpellID?>) -> some View {
        let options = selected.filter { SpellCatalog.spell($0).category == category }
        return VStack(alignment: .leading, spacing: 5) {
            Text("보호할 \(categoryTitle(category)) 주문")
                .font(.caption.weight(.semibold))
                .foregroundStyle(categoryColor(category))
            if options.isEmpty {
                Text("먼저 \(categoryTitle(category)) 주문을 준비하세요.")
                    .font(.caption)
                    .foregroundStyle(DAColor.attack)
            } else {
                ForEach(options, id: \.rawValue) { id in
                    Button {
                        selectedID.wrappedValue = id
                        playSelection()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: selectedID.wrappedValue == id ? "checkmark.circle.fill" : "circle")
                            Text(SpellCatalog.spell(id).name)
                            Spacer(minLength: 0)
                        }
                        .font(.caption)
                        .foregroundStyle(selectedID.wrappedValue == id ? DAColor.gold : DAColor.body)
                        .frame(minHeight: 34)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 18) {
            Button("돌아가기") {
                gameFeedback.playInterface(.back, settings: appSettings.settings)
                onCancel()
            }
            .buttonStyle(.bordered)
            .tint(DAColor.secondary)
            .frame(minHeight: 44)

            VStack(alignment: .leading, spacing: 3) {
                if !issues.isEmpty {
                    Text(issues.map(\.message).joined(separator: " "))
                        .foregroundStyle(DAColor.attack)
                } else if !tutorialFlags.isEmpty {
                    Text("안내를 확인하면 전투를 시작할 수 있습니다.")
                        .foregroundStyle(DAColor.gold)
                } else {
                    Text("출전 준비 완료")
                        .foregroundStyle(DAColor.body)
                }
                Text(selected.count == 6 ? "새 주문을 넣으려면 준비한 주문 하나를 먼저 빼 주세요." : "빈 자리를 남겨 두어도 전투를 시작할 수 있습니다.")
                    .foregroundStyle(DAColor.secondary)
            }
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: beginBattle) {
                Label("전투 시작", systemImage: "arrow.right")
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .foregroundStyle(DAColor.body)
                    .frame(width: 220, height: 58)
                    .background {
                        Image("Floor9EntryButtonPlate").resizable().scaledToFill()
                    }
                    .clipped()
            }
            .buttonStyle(.plain)
            .disabled(!issues.isEmpty || !tutorialFlags.isEmpty || isStarting)
            .opacity(issues.isEmpty && tutorialFlags.isEmpty && !isStarting ? 1 : 0.4)
        }
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
