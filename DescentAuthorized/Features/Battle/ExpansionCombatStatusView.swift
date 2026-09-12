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
