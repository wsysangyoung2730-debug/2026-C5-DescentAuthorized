import SwiftUI
import UIKit

/// Selection stays local until confirmation; the enemy still seals the card on its action.
struct BattleSealChoiceView: View {
    let battle: BattleState
    let onConfirm: (SpellID) -> Void

    @State private var selectedID: SpellID?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AccessibilityFocusState private var headingFocused: Bool

    private var choices: [SpellID] { battle.expansion.pendingSealChoices }
    private var selection: SpellDefinition? {
        guard let selectedID, choices.contains(selectedID) else { return nil }
        return SpellCatalog.spell(selectedID)
    }

    private var duration: Int? {
        guard case let .expansion(_, action) = battle.currentEnemyIntent else { return nil }
        return sealDuration(in: action)
    }

    private func sealDuration(in action: ExpansionEnemyAction) -> Int? {
        switch action {
        case let .preparedCardSeal(_, duration, chooseOne): return chooseOne ? duration : nil
        case let .sequence(actions): return actions.compactMap { sealDuration(in: $0) }.first
        default: return nil
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let panelWidth = min(560, max(0, geometry.size.width - 32))
            let availableHeight = max(0, geometry.size.height - 32)
            ZStack {
                Color.black.opacity(0.52)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { }
                    .accessibilityHidden(true)

                ViewThatFits(in: .vertical) {
                    content(width: panelWidth)
                    ScrollView {
                        content(width: panelWidth)
                    }
                    .frame(height: availableHeight)
                }
                .frame(width: panelWidth)
                .background {
                    SealChoiceArtwork.panel.image
                        .resizable(capInsets: EdgeInsets(top: 36, leading: 36, bottom: 36, trailing: 36))
                        .accessibilityHidden(true)
                }
                .frame(maxHeight: availableHeight)
                .shadow(color: .black.opacity(0.55), radius: 18, y: 8)
                .accessibilityIdentifier("seal-choice-panel")
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .accessibilityAddTraits(.isModal)
        .onAppear {
            headingFocused = true
            #if DEBUG
            // Preview-only selection for checking artwork without changing the combat state.
            if ExpansionPreviewSupport.floor != nil,
               let id = ExpansionPreviewSupport.sealChoice, choices.contains(id) { selectedID = id }
            #endif
        }
        .onChange(of: choices) { _, _ in
            if let selectedID, !choices.contains(selectedID) { self.selectedID = nil }
        }
    }

    private func content(width: CGFloat) -> some View {
        VStack(spacing: 10) {
            SealChoiceArtwork.crest.image
                .resizable().scaledToFit().frame(width: 112, height: 30)
                .accessibilityHidden(true)
            Text("봉인할 주문 선택")
                .font(.title3.weight(.semibold))
                .foregroundStyle(DAColor.gold)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($headingFocused)
            Text("선택한 주문은 다음 적 행동 시 봉인됩니다.")
                .font(.subheadline).foregroundStyle(DAColor.body)
                .multilineTextAlignment(.center)
            if let duration {
                Text("봉인 지속 · \(duration)턴")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DAColor.gold)
                    .padding(.horizontal, 30).padding(.vertical, 7)
                    .frame(minWidth: 170, minHeight: 28)
                    .background { SealChoiceArtwork.label.image.resizable() }
            }

            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(choices, id: \.self) { id in
                        choiceCard(SpellCatalog.spell(id), width: min(166, max(140, (width - 70) / 2)))
                    }
                }
                .padding(4)
                .frame(minWidth: max(0, width - 48))
            }
            .scrollBounceBehavior(.basedOnSize)
            .accessibilityIdentifier("seal-choice-candidates")

            Text(selection.map { "\($0.name)을 봉인 대상으로 지정합니다." } ?? "봉인할 주문을 하나 선택하세요.")
                .font(.subheadline)
                .foregroundStyle(selection == nil ? DAColor.body : DAColor.gold)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("seal-choice-summary")

            Button {
                guard let selection else { return }
                onConfirm(selection.id)
            } label: {
                Text("이 주문 봉인")
                    .font(.headline)
                    .foregroundStyle(selection == nil ? DAColor.body : Color.black)
                    .padding(.horizontal, 28).padding(.vertical, 12)
                    .frame(maxWidth: 340, minHeight: 48)
                    .background {
                        SealChoiceArtwork.confirm.image.resizable(
                            capInsets: EdgeInsets(top: 12, leading: 26, bottom: 12, trailing: 26))
                            .saturation(selection == nil ? 0.15 : 1)
                            .opacity(selection == nil ? 0.35 : 1)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(selection == nil)
            .accessibilityIdentifier("seal-choice-confirm")
            .accessibilityHint("선택한 주문을 봉인 대상으로 확정하고 전투로 돌아갑니다.")

            Text("보호한 공격·방어 주문과 봉인 해제는 후보에서 제외됩니다.")
                .font(.caption2).foregroundStyle(DAColor.body.opacity(0.8))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24).padding(.vertical, 20)
        .frame(width: width)
    }

    private func choiceCard(_ spell: SpellDefinition, width: CGFloat) -> some View {
        let isSelected = selectedID == spell.id
        return Button {
            selectedID = spell.id
        } label: {
            VStack(spacing: 8) {
                SpellGlyphPreview(spell: spell).frame(width: 68, height: 68)
                Text(categoryTitle(spell.category))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(categoryColor(spell.category))
                    .padding(.horizontal, 12).padding(.vertical, 3)
                    .overlay(Capsule().stroke(categoryColor(spell.category).opacity(0.75)))
                Text(spell.name).font(.headline).foregroundStyle(DAColor.body)
                Text("\(spell.compactEffectDescription) · \(spell.requiredStrokes)획")
                    .font(.caption).foregroundStyle(DAColor.body.opacity(0.85))
                Text(isSelected ? "선택됨" : " ")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? DAColor.gold : DAColor.body.opacity(0.7))
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 15).padding(.vertical, 20)
            .frame(width: width)
            .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 280 : 218)
            .background {
                (isSelected ? SealChoiceArtwork.cardSelected : .cardIdle).image.resizable(
                    capInsets: EdgeInsets(top: 26, leading: 26, bottom: 26, trailing: 26))
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    SealChoiceArtwork.check.image.resizable().scaledToFit()
                        .frame(width: 24, height: 24).padding(7)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(spell.name), \(categoryTitle(spell.category)), \(spell.compactEffectDescription), \(spell.requiredStrokes)획")
        .accessibilityValue(isSelected ? "선택됨" : "선택 안 됨")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint("봉인할 후보로 선택합니다. 아래 이 주문 봉인 버튼으로 확정하세요.")
        .accessibilityIdentifier("seal-choice-\(spell.id.rawValue)")
    }

    private func categoryTitle(_ category: SpellCategory) -> String {
        switch category {
        case .attack: "공격"
        case .defense: "방어"
        case .debuff: "디버프"
        case .dispel: "해제"
        }
    }

    private func categoryColor(_ category: SpellCategory) -> Color {
        switch category {
        case .attack: DAColor.attack
        case .defense: DAColor.defense
        case .debuff: DAColor.debuff
        case .dispel: DAColor.dispel
        }
    }
}

/// Trim only transparent export margins at display time; keep the supplied PNGs unchanged.
/// Three pixels per point keeps the engraved corners small when stretching the empty centers.
@MainActor
private enum SealChoiceArtwork: String, CaseIterable {
    case panel = "SealChoicePanel", crest = "SealChoiceCrest"
    case cardIdle = "SealChoiceCardIdle", cardSelected = "SealChoiceCardSelected"
    case confirm = "SealChoiceConfirm", check = "SealChoiceCheck", label = "SealChoiceLabel"

    var image: Image { Image(uiImage: Self.images[self] ?? UIImage()) }

    private var crop: CGRect {
        switch self {
        case .panel: CGRect(x: 21, y: 81, width: 1520, height: 816)
        case .crest: CGRect(x: 11, y: 43, width: 2150, height: 603)
        case .cardIdle, .cardSelected: CGRect(x: 12, y: 15, width: 1104, height: 1346)
        case .confirm: CGRect(x: 14, y: 195, width: 2071, height: 323)
        case .check: CGRect(x: 39, y: 32, width: 1176, height: 1183)
        case .label: CGRect(x: 21, y: 182, width: 2130, height: 349)
        }
    }

    private static let images: [Self: UIImage] = Dictionary(uniqueKeysWithValues: allCases.map { artwork in
        let original = UIImage(named: artwork.rawValue) ?? UIImage()
        guard let cropped = original.cgImage?.cropping(to: artwork.crop) else { return (artwork, original) }
        return (artwork, UIImage(cgImage: cropped, scale: 3, orientation: .up))
    })
}
