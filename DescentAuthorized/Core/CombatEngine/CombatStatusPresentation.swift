import Foundation

/// Group by the affected combatant; queued enemy attacks remain enemy threats.
struct CombatStatusItem: Identifiable, Equatable, Sendable {
    enum Side: Equatable, Sendable { case player, enemy }
    let id: String
    let title: String
    let detail: String
    var isUrgent: Bool = false

    var artworkID: String {
        if id.hasPrefix("lock-") { return "spell-seal" }
        if id.hasPrefix("scheduled-") { return detail.contains("지연됨") ? "execution-delay" : "scheduled-damage" }
        return ["normal": "normal-barrier", "absolute": "absolute-barrier", "limit": "limit-barrier",
            "direct": "direct-hit-block", "isolation": "isolation-barrier", "handoff": "handoff-barrier",
            "reactive": "reaction-protection", "weakening": "attack-reduction", "guard": "anchor-guard",
            "scheduledGuard": "causal-cushion", "nextBarrier": "lingering-barrier", "chain": "chain-empowerment",
            "phase": "phase-change", "flatAmplification": "amplification", "counter": "counterattack",
            "barrier": "normal-barrier", "amplification": "amplification", "preservation": "preservation",
            "output": "attack-reduction", "record": "spell-record", "mimic": "mimic-prohibition",
            "erasure": "erasure-zone"][id] ?? "focus"
    }
}

extension BattleState {
    var showsCombatStatus: Bool {
        guard phase != .victory, phase != .defeat, phase != .preparing else { return false }
        if case let .enemy(id) = enemy.id, id.lowerFloorNumber != nil { return true }
        return !statusItems(for: .player).isEmpty || !statusItems(for: .enemy).isEmpty
    }

    func statusItems(for side: CombatStatusItem.Side) -> [CombatStatusItem] {
        guard phase != .victory, phase != .defeat, phase != .preparing else { return [] }
        var items: [CombatStatusItem] = []
        func add(_ id: String, _ title: String, _ detail: String, urgent: Bool = false) {
            items.append(.init(id: id, title: title, detail: detail, isUrgent: urgent))
        }
        let combatant = side == .player ? player : enemy
        if combatant.normalBarrier > 0 { add("normal", "일반 방벽", "남은 방벽 \(combatant.normalBarrier)") }
        if combatant.absoluteBarrierCharges > 0 { add("absolute", "절대 방벽", "\(combatant.absoluteBarrierCharges)회 무효화") }
        if side == .player, !activeErasureZones.isEmpty { add("erasure", "말소 구역", "입력 패드에 \(activeErasureZones.count)개 적용") }
        let e = expansion
        switch side {
        case .player:
            if e.limitBarrierThroughTurn != nil { add("limit", "한계 방벽", "상한 60 · 이번 적 턴 후 40으로 복귀") }
            if let through = e.directHitProhibitionThroughTurn { add("direct", "직격 금지", "\(through)턴까지 직접 피해 1회 무효 · 예약 제외") }
            if let id = e.isolationReservationID, let r = e.scheduledDamage.first(where: { $0.id == id }) {
                add("isolation", "격리 방벽", "\(r.name) −50%")
            }
            if e.handoffBarrierAmount > 0 { add("handoff", "인계 방벽", "다음 타격 처리 후 +\(e.handoffBarrierAmount)") }
            if e.reactiveDamageProtection { add("reactive", "책임 단절", "모사·반격 피해 −50%") }
            if e.playerAttackWeakening != nil { add("weakening", "공격 약화", "내 다음 공격 감소 · 정화 가능") }
            if e.nextHitFlatReduction > 0 { add("guard", "기준점 수호", "이번 적 턴 다음 피해 −\(e.nextHitFlatReduction)") }
            if e.scheduledHitReduction != nil { add("scheduledGuard", "인과 완충", "이번 턴 첫 예약 피해 −30%") }
            if e.nextTurnBarrier > 0 { add("nextBarrier", "잔류 방벽", "다음 턴 방벽 +\(e.nextTurnBarrier)") }
            if e.chainAttackBonus > 0 { add("chain", "연쇄 각인", "이번 턴 다음 공격 +\(e.chainAttackBonus)") }
            for id in e.lockedSpells.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
                add("lock-\(id.rawValue)", "\(SpellCatalog.spell(id).name) 봉인", "\(e.lockedSpells[id] ?? 0)턴까지 · 정화 가능")
            }
        case .enemy:
            if e.encounterPhase > 1 { add("phase", "\(e.encounterPhase)단계", "현재 적용 중인 강화 패턴") }
            if e.flatAmplification > 0 { add("flatAmplification", "예약 증폭 +\(e.flatAmplification)", "등록 전 정화 가능") }
            if e.counterDamage > 0 { add("counter", "반격 \(e.counterDamage)", e.counterTriggered ? "공격 감지 · 추가타 예정" : "공격 성공 시 최대 1회") }
            if let turn = e.enemyBarrierExpires { add("barrier", "적 방벽", "\(turn)턴 적 행동 종료 시 만료") }
            if let amplification = e.enemyAmplification { add("amplification", "인과 증폭", "다음 예약 \(Int(amplification * 100))% · 등록 전 정화") }
            if e.enemyPreservation != nil { add("preservation", "원본 보존", "적이 받는 다음 공격 감소 · 정화 가능") }
            if let reduction = e.outputReduction { add("output", "출력 저하", "적 다음 타격 −25% · \(reduction.expiresAfterTurn)턴까지") }
            if let record = e.copyRecord { add("record", "기록: \(SpellCatalog.spell(record.spell).name)", record.reused ? "재사용 감지 · 다음 행동에서 모사" : "재사용하면 추가 반응") }
            if let through = e.mimicProhibitionThroughEnemyTurn { add("mimic", "모사 금지", "\(through)턴까지 적 기록·반응 차단") }
            for pending in e.scheduledDamage {
                add("scheduled-\(pending.id)", pending.name, "\(pending.dueEnemyTurn == turnNumber ? "이번" : "\(pending.dueEnemyTurn)번") 적 턴 · \(pending.damage) 피해\(pending.wasDelayed ? " · 지연됨" : "")", urgent: pending.dueEnemyTurn <= turnNumber)
            }
        }
        return items.filter(\.isUrgent) + items.filter { !$0.isUrgent }
    }
}
