import SwiftUI
import UIKit

/// Uses the same dark/gold treatment as the existing battle panels.
struct ExpansionCombatStatusView: View {
    let battle: BattleState
    var feedbackText: String? = nil
    var feedbackColor: Color = .white
    var feedbackIsEnemy = false
    var enemyActionText: String? = nil
    var enemyActionArtwork = "direct-attack"
    @State private var showsThreats = false
    @State private var expandedSide: CombatStatusItem.Side?

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            statusLane(.player, title: "내 상태", symbol: "person.fill", color: .cyan)
            Spacer(minLength: 32)
            statusLane(.enemy, title: "적 상태 · 위협", symbol: "exclamationmark.shield.fill", color: .orange)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .top)
        .sheet(isPresented: $showsThreats) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        Text("예고: \(battle.currentEnemyIntent?.name ?? "대기")").font(.title2)
                        if case let .expansion(_, action) = battle.currentEnemyIntent {
                            Text(action.detail).foregroundStyle(DAColor.gold)
                        }
                        Text("1 · 직접 공격\n예고된 분할 타격은 왼쪽부터 한 번씩 처리됩니다. 직격 금지는 첫 직접 피해만 무효화합니다.")
                        Text("2 · 도래한 예약").font(.headline)
                        let due = battle.expansion.scheduledDamage.filter { $0.dueEnemyTurn <= battle.turnNumber }
                        if due.isEmpty { Text("이번 적 턴에 도착할 예약 없음").foregroundStyle(DAColor.secondary) }
                        ForEach(due) { pending in
                            Text("\(pending.name) · \(pending.damage) 피해\(pending.wasDelayed ? " · 지연됨" : "")")
                        }
                        Text("3 · 모사와 반격\n재사용 감지 또는 공격 성공 조건을 충족한 추가타만 처리합니다. 모사 금지로 반응을 막을 수 있습니다.")
                        Text("예약 등록은 현재 직접 피해가 아닙니다. HP 대가는 보호·방벽과 별개이며 생존할 수 없는 금서는 시전할 수 없습니다.")
                            .foregroundStyle(DAColor.secondary)
                    }.padding(28)
                }
                .background(DAColor.background).foregroundStyle(DAColor.body)
                .navigationTitle("피해 처리 순서")
                .toolbar { Button("닫기") { showsThreats = false } }
            }.preferredColorScheme(.dark)
        }
    }

    private var isLowerFloorEnemy: Bool {
        if case let .enemy(id) = battle.enemy.id { return id.lowerFloorNumber != nil }
        return false
    }

    private func statusLane(_ side: CombatStatusItem.Side, title: String, symbol: String, color: Color) -> some View {
        let items = battle.statusItems(for: side)
        let showsThreatButton = side == .enemy && isLowerFloorEnemy
            && battle.phase != .victory && battle.phase != .defeat
        return VStack(alignment: side == .player ? .leading : .trailing, spacing: 6) {
            if !items.isEmpty || showsThreatButton {
                HStack(spacing: 8) {
                    Label(title, systemImage: symbol)
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(color)
                    Spacer(minLength: 0)
                    if items.count > 2 || showsThreatButton {
                        Button { expandedSide = side } label: {
                            Text(items.count > 2 ? "+\(items.count - 2) · 전체 상태" : "위협 상세")
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(color)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.black.opacity(0.78), in: Capsule())
                ForEach(Array(items.prefix(2))) { item in
                    statusRow(item, side: side, color: color)
                }
            }
            if side == .enemy, let enemyActionText {
                HStack(spacing: 8) {
                    CombatStatusArtwork.image(enemyActionArtwork)
                        .resizable().scaledToFit().frame(width: 28, height: 28)
                    Text(enemyActionText).font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DAColor.gold).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background { CombatStatusArtwork.panel("enemy-action-plate") }
                .allowsHitTesting(false)
            }
            if let feedbackText, (side == .enemy) == feedbackIsEnemy {
                Text(feedbackText)
                    .font(.system(size: feedbackText.hasPrefix("피격") ? 24 : 15, weight: .bold))
                    .foregroundStyle(feedbackColor)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: side == .player ? .leading : .trailing)
                    .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
                    .allowsHitTesting(false)
            }
        }
        .frame(width: 256, alignment: side == .player ? .topLeading : .topTrailing)
        .popover(isPresented: Binding(get: { expandedSide == side }, set: { if !$0 { expandedSide = nil } })) {
            ScrollView {
                VStack(spacing: 10) {
                    Text(title).font(.headline).foregroundStyle(color)
                    ForEach(items) { item in statusRow(item, side: side, color: color) }
                    if showsThreatButton { Button("피해 처리 순서") { expandedSide = nil; showsThreats = true } }
                }.padding(18)
            }.frame(width: 320, height: 360).background(DAColor.background)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private func statusRow(_ item: CombatStatusItem, side: CombatStatusItem.Side, color: Color) -> some View {
        HStack(spacing: 8) {
            CombatStatusArtwork.image(item.artworkID)
                .resizable().scaledToFit().frame(width: 32, height: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(item.isUrgent ? .orange : color)
                Text(item.detail).font(.system(size: 12)).foregroundStyle(DAColor.body).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if item.isUrgent { Text("임박").font(.system(size: 9, weight: .bold)).foregroundStyle(.orange) }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background {
            CombatStatusArtwork.panel(item.isUrgent ? "urgent-threat-row" : (side == .player ? "player-status-row" : "enemy-status-row"))
        }
        .accessibilityElement(children: .combine)
    }

}

/// Player effects stay near the casting hand, separate from the enemy's status markers.
struct ExpansionPlayerStatusAuraView: View {
    let battle: BattleState

    private var active: Bool { battle.phase != .victory && battle.phase != .defeat && battle.phase != .preparing }
    private var weakened: Bool {
        (battle.expansion.playerAttackWeakening?.expiresAfterTurn ?? -1) >= battle.turnNumber
    }
    private var protected: Bool {
        battle.expansion.nextHitFlatReduction > 0 || battle.expansion.scheduledHitReduction != nil || battle.expansion.nextTurnBarrier > 0
    }
    var body: some View {
        if active && (weakened || protected || battle.expansion.chainAttackBonus > 0) {
            VStack(spacing: 4) {
                Canvas { context, size in
                    let center = CGPoint(x: size.width/2, y: size.height/2)
                    if weakened {
                        var crack = Path()
                        crack.move(to: CGPoint(x: center.x-44,y: center.y+12))
                        crack.addLines([CGPoint(x: center.x-15,y: center.y-12), CGPoint(x: center.x-5,y: center.y+3), CGPoint(x: center.x+17,y: center.y-22), CGPoint(x: center.x+40,y: center.y-4)])
                        context.stroke(crack, with: .color(.purple.opacity(0.65)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    }
                    if protected {
                        var arc = Path()
                        arc.addArc(center: center, radius: 34, startAngle: .degrees(15), endAngle: .degrees(165), clockwise: false)
                        context.stroke(arc, with: .color(.cyan.opacity(0.55)), lineWidth: 2)
                    }
                    if battle.expansion.chainAttackBonus > 0 {
                        for offset in [-12.0, 0.0, 12.0] {
                            let rect = CGRect(x: center.x+offset-2,y: center.y-29,width: 4,height: 4)
                            context.fill(Path(ellipseIn: rect), with: .color(.orange.opacity(0.7)))
                        }
                    }
                }
                .frame(width: 120, height: 78)
                HStack(spacing: 6) {
                    if weakened { Label("약화", systemImage: "bolt.slash").foregroundStyle(.purple) }
                    if protected { Label("보호", systemImage: "shield").foregroundStyle(.cyan) }
                    if battle.expansion.chainAttackBonus > 0 { Label("강화", systemImage: "arrow.up").foregroundStyle(.orange) }
                }
                .font(.caption2)
                .padding(5).background(.black.opacity(0.55), in: Capsule())
            }
            .accessibilityElement(children: .combine)
            .allowsHitTesting(false)
        }
    }
}

/// The chain ends extend past all four card corners and are clipped by the card,
/// so the seal binds the whole card rather than appearing as a small glyph icon.
struct SpellSealChainsOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            SealedCardArtwork.chains.image
                .resizable()
                .frame(width: geometry.size.width + 14, height: geometry.size.height + 48)
                .position(x: geometry.size.width / 2, y: geometry.size.height * 0.4)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Keep the seal and its caption above the glyph; the chains use the full card bounds.
struct SpellSealVisualOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                SealedCardArtwork.emblem.image
                    .resizable().scaledToFit()
                    .frame(width: 44, height: 44)
                    .position(x: geometry.size.width / 2, y: 32)
                Text("시전 불가")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color(red: 0.84, green: 0.74, blue: 0.91))
                    .padding(.horizontal, 7).padding(.vertical, 1)
                    .background(.black.opacity(0.8), in: Capsule())
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct SpellSealTurnBadge: View {
    let turns: Int

    var body: some View {
        Text("봉인 · \(turns)턴")
            .font(.system(size: 10, weight: .semibold).monospacedDigit())
            .foregroundStyle(Color(red: 0.94, green: 0.86, blue: 1))
            .lineLimit(1).minimumScaleFactor(0.7)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 23, maxHeight: 23)
            .background { SealedCardArtwork.badge.image.resizable() }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Preserve the supplied PNGs; remove only their transparent export margins at display time.
@MainActor
private enum SealedCardArtwork: String, CaseIterable {
    case chains = "SealedCardChains", emblem = "SealedCardEmblem", badge = "SealedCardTurnBadge"

    var image: Image { Image(uiImage: Self.images[self] ?? UIImage()) }

    private var crop: CGRect {
        switch self {
        case .chains: CGRect(x: 26, y: 37, width: 1376, height: 1036)
        case .emblem: CGRect(x: 207, y: 194, width: 844, height: 867)
        case .badge: CGRect(x: 223, y: 142, width: 1733, height: 422)
        }
    }

    private static let images: [Self: UIImage] = Dictionary(uniqueKeysWithValues: allCases.map { artwork in
        let original = UIImage(named: artwork.rawValue) ?? UIImage()
        guard let cropped = original.cgImage?.cropping(to: artwork.crop) else { return (artwork, original) }
        return (artwork, UIImage(cgImage: cropped, scale: 3, orientation: .up))
    })
}

/// Crop transparent export margins in memory; original artwork remains intact.
@MainActor
enum CombatStatusArtwork {
    private static let bounds: [String: CGRect] = [
        "direct-attack": CGRect(x: 73, y: 18, width: 1137, height: 1196),
        "heavy-ray": CGRect(x: 49, y: 21, width: 1173, height: 1209),
        "multi-hit": CGRect(x: 21, y: 17, width: 1205, height: 1205),
        "focus": CGRect(x: 39, y: 47, width: 1195, height: 1207),
        "normal-barrier": CGRect(x: 41, y: 21, width: 1157, height: 1169),
        "absolute-barrier": CGRect(x: 69, y: 19, width: 1145, height: 1235),
        "correction-barrier": CGRect(x: 0, y: 21, width: 1232, height: 1225),
        "barrier-break": CGRect(x: 63, y: 21, width: 1161, height: 1233),
        "spell-seal": CGRect(x: 0, y: 7, width: 1210, height: 1247),
        "amplification": CGRect(x: 41, y: 21, width: 1169, height: 1217),
        "scheduled-damage": CGRect(x: 19, y: 9, width: 1191, height: 1211),
        "execution-delay": CGRect(x: 17, y: 19, width: 1223, height: 1211),
        "spell-record": CGRect(x: 89, y: 21, width: 1121, height: 1193),
        "copy-reaction": CGRect(x: 97, y: 53, width: 1101, height: 1161),
        "counterattack": CGRect(x: 69, y: 47, width: 1141, height: 1159),
        "attack-reduction": CGRect(x: 97, y: 21, width: 1113, height: 1201),
        "preservation": CGRect(x: 0, y: 21, width: 1214, height: 1233),
        "mimic-prohibition": CGRect(x: 0, y: 19, width: 1208, height: 1195),
        "phase-change": CGRect(x: 33, y: 21, width: 1165, height: 1205),
        "wait-opening": CGRect(x: 89, y: 9, width: 1045, height: 1203),
        "erasure-zone": CGRect(x: 0, y: 21, width: 1228, height: 1167),
        "purification": CGRect(x: 21, y: 17, width: 1203, height: 1204),
        "execution-nullification": CGRect(x: 33, y: 17, width: 1167, height: 1213),
        "healing": CGRect(x: 0, y: 21, width: 1210, height: 1199),
        "limit-barrier": CGRect(x: 0, y: 23, width: 1234, height: 1231),
        "direct-hit-block": CGRect(x: 97, y: 39, width: 1127, height: 1215),
        "isolation-barrier": CGRect(x: 33, y: 21, width: 1173, height: 1205),
        "handoff-barrier": CGRect(x: 0, y: 21, width: 1210, height: 1225),
        "reaction-protection": CGRect(x: 0, y: 9, width: 1240, height: 1245),
        "anchor-guard": CGRect(x: 81, y: 30, width: 1129, height: 1182),
        "causal-cushion": CGRect(x: 97, y: 21, width: 1103, height: 1193),
        "lingering-barrier": CGRect(x: 89, y: 21, width: 1119, height: 1193),
        "chain-empowerment": CGRect(x: 43, y: 19, width: 1147, height: 1235),
        "player-status-row": CGRect(x: 28, y: 316, width: 1712, height: 256),
        "enemy-status-row": CGRect(x: 64, y: 223, width: 2045, height: 262),
        "urgent-threat-row": CGRect(x: 31, y: 203, width: 2111, height: 318),
        "enemy-action-plate": CGRect(x: 27, y: 243, width: 2119, height: 230),
        "status-effect-chip": CGRect(x: 49, y: 102, width: 1942, height: 620),
        "player-damage-glow": CGRect(x: 33, y: 111, width: 1556, height: 699),
    ]
    /// Preserve corners at the final panel scale; only the center stretches.
    static func panel(_ id: String) -> some View {
        image(id).resizable(capInsets: EdgeInsets(top: 14, leading: 22, bottom: 14, trailing: 22), resizingMode: .stretch)
    }
    private static var cache: [String: UIImage] = [:]
    static func image(_ id: String) -> Image {
        if let cached = cache[id] { return Image(uiImage: cached) }
        guard let original = UIImage(named: "CombatStatus_" + id) else { return Image(systemName: "sparkle") }
        let cropped: UIImage
        if let rect = bounds[id], let cg = original.cgImage?.cropping(to: rect) {
            cropped = UIImage(cgImage: cg, scale: id.hasSuffix("-row") || id == "enemy-action-plate" ? CGFloat(cg.height) / 64 : original.scale, orientation: original.imageOrientation)
        } else { cropped = original }
        cache[id] = cropped
        return Image(uiImage: cropped)
    }
}
