import SwiftUI

/// Uses the same dark/gold treatment as the existing battle panels.
struct ExpansionCombatStatusView: View {
    let battle: BattleState
    @State private var showsThreats = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if case let .enemy(id) = battle.enemy.id, id.lowerFloorNumber != nil {
                    Button { showsThreats = true } label: {
                        chip("위협 순서 확인", detail: "직접 → 예약 → 모사·반격", color: DAColor.gold)
                    }.buttonStyle(.plain)
                }
                if battle.expansion.encounterPhase > 1 {
                    chip("\(battle.expansion.encounterPhase)단계", detail: "현재 적용 중인 강화 패턴", color: .orange)
                }
                if battle.expansion.flatAmplification > 0 {
                    chip("예약 증폭 +\(battle.expansion.flatAmplification)", detail: "등록 전 정화 가능", color: .orange)
                }
                if battle.expansion.counterDamage > 0 {
                    chip("반격 \(battle.expansion.counterDamage)", detail: battle.expansion.counterTriggered ? "공격 감지 · 추가타 예정" : "공격 성공 시 최대 1회", color: .red)
                }
                if let turn = battle.expansion.enemyBarrierExpires {
                    chip("적 방벽", detail: "\(turn)턴 적 행동 종료 시 만료", color: .cyan)
                }
                if battle.expansion.limitBarrierThroughTurn != nil {
                    chip("한계 방벽", detail: "상한 60 · 이번 적 턴 후 40으로 복귀", color: .cyan)
                }
                if let through = battle.expansion.directHitProhibitionThroughTurn {
                    chip("직격 금지", detail: "\(through)턴까지 직접 피해 1회 무효 · 예약 제외", color: .purple)
                }
                if let id = battle.expansion.isolationReservationID,
                   let reservation = battle.expansion.scheduledDamage.first(where: { $0.id == id }) {
                    chip("격리 방벽", detail: "\(reservation.name) −50%", color: .cyan)
                }
                if battle.expansion.handoffBarrierAmount > 0 {
                    chip("인계 방벽", detail: "다음 타격 처리 후 +\(battle.expansion.handoffBarrierAmount)", color: .cyan)
                }
                if battle.expansion.reactiveDamageProtection {
                    chip("책임 단절", detail: "모사·반격 피해 −50%", color: .purple)
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
                    chip("\(SpellCatalog.spell(id).name) 봉인", detail: "\(battle.expansion.lockedSpells[id] ?? 0)턴까지 · 정화 가능", color: .red)
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 58)
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
