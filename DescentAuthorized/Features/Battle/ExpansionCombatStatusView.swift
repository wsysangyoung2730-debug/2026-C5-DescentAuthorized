import SwiftUI

/// Uses the same dark/gold treatment as the existing battle panels.
struct ExpansionCombatStatusView: View {
    let battle: BattleState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if battle.expansion.encounterPhase > 1 {
                    chip("2단계", detail: "다음 주기부터 강화된 패턴", color: .orange)
                }
                if let amplification = battle.expansion.enemyAmplification {
                    chip("인과 증폭", detail: "다음 예약 \(Int(amplification * 100))% · 등록 전 정화", color: .orange)
                }
                if battle.expansion.enemyPreservation != nil {
                    chip("원본 보존", detail: "적이 받는 다음 공격 감소 · 정화 가능", color: .purple)
                }
                if battle.expansion.playerAttackWeakening != nil {
                    chip("공격 약화", detail: "다음 공격 감소 · 정화 가능", color: .red)
                }
                if let reduction = battle.expansion.outputReduction {
                    chip("출력 저하", detail: "다음 타격 −25% · \(reduction.expiresAfterTurn)턴까지", color: .cyan)
                }
                if battle.expansion.nextHitFlatReduction > 0 {
                    chip("기준점 수호", detail: "이번 적 턴 다음 피해 −6", color: .cyan)
                }
                if battle.expansion.scheduledHitReduction != nil {
                    chip("인과 완충", detail: "이번 턴 첫 예약 피해 −30%", color: .cyan)
                }
                if battle.expansion.nextTurnBarrier > 0 {
                    chip("잔류 방벽", detail: "다음 턴 방벽 +10", color: .cyan)
                }
                if battle.expansion.chainAttackBonus > 0 {
                    chip("연쇄 각인", detail: "이번 턴 다음 공격 +12", color: .orange)
                }
                if let record = battle.expansion.copyRecord {
                    chip("기록: \(SpellCatalog.spell(record.spell).name)", detail: record.reused ? "재사용 감지 · 다음 행동에서 모사" : "재사용하면 추가 반응", color: .purple)
                }
                if let through = battle.expansion.mimicProhibitionThroughEnemyTurn {
                    chip("모사 금지", detail: "\(through)턴까지 기록·반응 차단", color: .purple)
                }
                ForEach(battle.expansion.scheduledDamage) { pending in
                    chip(pending.name, detail: "\(pending.dueEnemyTurn == battle.turnNumber ? "이번" : "\(pending.dueEnemyTurn)번") 적 턴 · \(pending.damage) 피해\(pending.wasDelayed ? " · 지연됨" : "")", color: .orange)
                }
                ForEach(battle.expansion.lockedSpells.keys.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { id in
                    chip("\(SpellCatalog.spell(id).name) 봉인", detail: "기억 압착 종료 또는 정화 시 해제", color: .red)
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 58)
    }

    private func chip(_ title: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(color)
            Text(detail).font(.caption2).foregroundStyle(DAColor.body)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.black.opacity(0.86), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(color.opacity(0.35)))
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

struct SpellSealVisualOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: 10,y: 30))
                    path.addLine(to: CGPoint(x: geometry.size.width-10,y: geometry.size.height-30))
                    path.move(to: CGPoint(x: geometry.size.width-10,y: 30))
                    path.addLine(to: CGPoint(x: 10,y: geometry.size.height-30))
                }
                .stroke(.purple.opacity(0.65), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [5,4]))
                Image(systemName: "lock.fill")
                    .font(.title3).foregroundStyle(.purple)
                    .padding(10).background(.black.opacity(0.8), in: Circle())
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
