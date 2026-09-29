import SwiftUI
import UIKit

/// Uses the same dark/gold treatment as the existing battle panels.
struct ExpansionCombatStatusView: View {
    let battle: BattleState
    @State private var showsThreats = false

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            statusLane(.player, title: "내 상태", symbol: "person.fill", color: .cyan)
            statusLane(.enemy, title: "적 상태 · 위협", symbol: "exclamationmark.shield.fill", color: .orange)
        }
        .padding(.horizontal, 16)
        .frame(height: 76, alignment: .top)
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
        return VStack(alignment: side == .player ? .leading : .trailing, spacing: 4) {
            if !items.isEmpty || showsThreatButton {
                Label(title, systemImage: symbol)
                    .font(.caption2.weight(.bold)).foregroundStyle(color)
                    .padding(.horizontal, 8)
                    .background(.black.opacity(0.65), in: Capsule())
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        if showsThreatButton {
                            Button { showsThreats = true } label: {
                                chip("위협 순서 확인", detail: "직접 → 예약 → 모사·반격", color: color)
                            }.buttonStyle(.plain)
                        }
                        ForEach(items) { item in
                            chip(item.title, detail: item.detail, color: color)
                        }
                    }
                }
                .defaultScrollAnchor(side == .player ? .leading : .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: side == .player ? .topLeading : .topTrailing)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private func chip(_ title: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(color)
            Text(detail).font(.caption2).foregroundStyle(DAColor.body)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(color.opacity(0.65)))
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
