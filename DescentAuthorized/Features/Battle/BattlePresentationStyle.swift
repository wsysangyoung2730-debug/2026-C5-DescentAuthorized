import SwiftUI

enum DAColor {
    static let background = Color(red: 8 / 255, green: 11 / 255, blue: 16 / 255)
    static let panel = Color(red: 11 / 255, green: 16 / 255, blue: 23 / 255)
    static let card = Color(red: 13 / 255, green: 18 / 255, blue: 26 / 255)
    static let divider = Color(red: 42 / 255, green: 53 / 255, blue: 66 / 255)
    static let body = Color(red: 216 / 255, green: 226 / 255, blue: 232 / 255)
    static let secondary = Color(red: 126 / 255, green: 141 / 255, blue: 155 / 255)
    static let magic = Color(red: 123 / 255, green: 93 / 255, blue: 211 / 255)
    static let magicGlow = Color(red: 192 / 255, green: 166 / 255, blue: 250 / 255)
    static let attack = Color(red: 196 / 255, green: 69 / 255, blue: 63 / 255)
    static let defense = Color(red: 111 / 255, green: 182 / 255, blue: 217 / 255)
    static let dispel = Color(red: 201 / 255, green: 162 / 255, blue: 39 / 255)
    static let gold = Color(red: 213 / 255, green: 174 / 255, blue: 67 / 255)
}

struct BattleTopHUDView: View {
    let battle: BattleState
    let floor: FloorID
    let enemyToNextActionSpacing: CGFloat

    var body: some View {
        HStack(spacing: 14) {
            combatantBlock(
                battle.player,
                barrierAccent: DAColor.defense,
                alignment: .leading
            )

            Spacer(minLength: 8)

            VStack(spacing: 3) {
                Text("제\(floor.rawValue)층")
                    .font(.system(size: 18, weight: .medium, design: .serif))
                    .foregroundStyle(DAColor.gold)
                Text("TURN \(battle.turnNumber)")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(DAColor.body)
                Text(phaseTitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(DAColor.secondary)
            }
            .frame(width: 112)

            Spacer(minLength: 8)

            HStack(spacing: enemyToNextActionSpacing) {
                combatantBlock(
                    battle.enemy,
                    barrierAccent: DAColor.magic,
                    alignment: .trailing
                )

                nextActionBlock
                    .frame(width: 142)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func combatantBlock(
        _ combatant: CombatantState,
        barrierAccent: Color,
        alignment: HorizontalAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            HStack(spacing: 6) {
                if alignment == .trailing, combatant.absoluteBarrierCharges > 0 {
                    absoluteBarrierIcon(combatant.absoluteBarrierCharges)
                }
                Text(combatant.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                if alignment == .leading, combatant.absoluteBarrierCharges > 0 {
                    absoluteBarrierIcon(combatant.absoluteBarrierCharges)
                }
            }

            layeredVitalityBar(combatant, barrierAccent: barrierAccent)
                .frame(width: 210, height: 9)

            Text(vitalityCaption(combatant))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(DAColor.secondary)
        }
        .frame(width: 220, alignment: alignment == .leading ? .leading : .trailing)
        .accessibilityElement(children: .combine)
    }

    private func layeredVitalityBar(
        _ combatant: CombatantState,
        barrierAccent: Color
    ) -> some View {
        GeometryReader { proxy in
            let healthFraction = min(max(combatant.hpFraction, 0), 1)
            let barrierFraction = min(
                max(Double(combatant.normalBarrier) / Double(combatant.maxHP), 0),
                healthFraction
            )
            let healthWidth = proxy.size.width * healthFraction
            let barrierWidth = proxy.size.width * barrierFraction

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.1))

                if combatant.absoluteBarrierCharges > 0 {
                    Capsule()
                        .fill(DAColor.gold)
                } else {
                    Capsule()
                        .fill(DAColor.attack)
                        .frame(width: healthWidth)

                    if barrierWidth > 0 {
                        Capsule()
                            .fill(barrierAccent)
                            .frame(width: barrierWidth)
                            .offset(x: max(0, healthWidth - barrierWidth))
                    }
                }

                Capsule()
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            }
        }
    }

    private var nextActionBlock: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text("다음 행동")
                .font(.caption2)
                .foregroundStyle(DAColor.secondary)

            if let intent = battle.currentEnemyIntent {
                Text(intent.name)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(intentColor(intent))
                    .lineLimit(1)
                Text(intentDetail(intent))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(DAColor.body)
                    .lineLimit(1)
            } else {
                Text("분석 중")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DAColor.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(DAColor.card.opacity(0.72))
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .stroke(DAColor.gold.opacity(0.25), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .accessibilityElement(children: .combine)
    }

    private func vitalityCaption(_ combatant: CombatantState) -> String {
        let hp = "\(combatant.hp) / \(combatant.maxHP)"
        if combatant.absoluteBarrierCharges > 0 {
            return "\(hp) · 절대 방벽 \(combatant.absoluteBarrierCharges)"
        }
        guard combatant.normalBarrier > 0 else { return hp }
        return "\(hp) · 방벽 \(combatant.normalBarrier)"
    }

    private func absoluteBarrierIcon(_ charges: Int) -> some View {
        Label("\(charges)", systemImage: "shield.checkered")
            .font(.caption2.monospacedDigit().weight(.bold))
            .foregroundStyle(DAColor.gold)
    }

    private var phaseTitle: String {
        switch battle.phase {
        case .preparing: "절차 준비"
        case .playerTurn: "봉인관 차례"
        case .resolvingPlayerSpell: "주문 해석"
        case .resolvingEnemyAction: "관리자 차례"
        case .victory: "관리자 무력화"
        case .defeat: "절차 중단"
        }
    }

    private func intentDetail(_ action: EnemyAction) -> String {
        switch action {
        case let .attack(_, damage, isStrong):
            isStrong ? "강공격 · 피해 \(damage)" : "공격 · 피해 \(damage)"
        case let .grantNormalBarrier(_, amount):
            "일반 방벽 \(amount)"
        case let .grantAbsoluteBarrier(_, charges):
            "절대 방벽 \(charges)회"
        case let .telegraph(_, upcoming):
            upcoming
        }
    }

    private func intentColor(_ action: EnemyAction) -> Color {
        switch action {
        case .attack: DAColor.attack
        case .grantNormalBarrier: DAColor.defense
        case .grantAbsoluteBarrier: DAColor.gold
        case .telegraph: DAColor.magicGlow
        }
    }
}

struct DAStatusPanel: ViewModifier {
    var accent: Color = DAColor.divider

    func body(content: Content) -> some View {
        content
            .padding(10)
            .background(DAColor.panel.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(accent.opacity(0.65), lineWidth: 1)
            }
    }
}

extension View {
    func daStatusPanel(accent: Color = DAColor.divider) -> some View {
        modifier(DAStatusPanel(accent: accent))
    }
}

struct BattleResourceReadout: View {
    let mana: Double
    let strokes: Int

    var body: some View {
        HStack(spacing: 14) {
            resource(icon: "scribble.variable", title: "마나", value: "\(Int(mana.rounded()))")
            Rectangle().fill(DAColor.divider).frame(width: 1, height: 28)
            resource(icon: "pencil.and.outline", title: "남은 획", value: "\(strokes)")
        }
        .daStatusPanel(accent: DAColor.magic)
        .accessibilityElement(children: .combine)
    }

    private func resource(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon).foregroundStyle(DAColor.magicGlow)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption2).foregroundStyle(DAColor.secondary)
                Text(value).font(.subheadline.monospacedDigit().weight(.bold))
            }
        }
    }
}
