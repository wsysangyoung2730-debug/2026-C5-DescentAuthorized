import SwiftUI

struct ExpansionCombatGuide {
    let flag: LoadoutTutorialFlag
    let title: String
    let detail: String

    static func current(progress: GameProgress, battle: BattleState?, events: [DemoSessionEvent]) -> Self? {
        guard let current = progress.expansion, let battle, battle.phase == .playerTurn else { return nil }
        let seen = progress.loadoutTutorials
        if current.floorNumber == 6 {
            if battle.expansion.enemyAmplification != nil, !seen.contains(.statusEffects) {
                return .init(flag: .statusEffects, title: "적에게 강화 상태가 걸렸습니다", detail: "인과 증폭은 다음 예약 피해를 강화합니다. 정화 각인이 있다면 예약이 등록되기 전에 지울 수 있습니다. 방어로 받아내는 방법도 가능합니다.")
            }
            if !battle.expansion.scheduledDamage.isEmpty, !seen.contains(.scheduledDamage) {
                return .init(flag: .scheduledDamage, title: "피해가 예약되었습니다", detail: "상태 표시에서 집행 턴과 피해량을 확인하세요. 증폭은 이미 예약 수치에 반영되었습니다. 이제 증폭을 지우더라도 예약된 피해량은 줄어들지 않습니다.")
            }
            if battle.expansion.scheduledDamage.contains(where: { $0.dueEnemyTurn == battle.turnNumber }), !seen.contains(.reservationCounter) {
                let counter = progress.equippedSpells.contains(.outputReduction)
                    ? "출력 저하는 다음 타격을 25% 약화시킵니다. 방어 주문과 함께 사용할 수 있습니다."
                    : "방어 주문으로 피해를 흡수하세요. 출력 저하를 장착하지 않아도 전투를 진행할 수 있습니다."
                return .init(flag: .reservationCounter, title: "이번 적 턴에 예약이 집행됩니다", detail: counter + " 예약이 없는 약한 공격 턴에 미리 사용하면 감소 효과가 먼저 소모될 수 있습니다.")
            }
            let executed = events.contains { event in
                if case let .combat(.expansionChanged(message)) = event { return message.contains("예약 피해") && message.contains("집행") }
                return false
            }
            if executed, !seen.contains(.reservationResult) {
                let hpDamage = events.reduce(0) { sum, event in
                    if case let .combat(.damageApplied(target, amount, _)) = event, target == .player { return sum + amount }
                    return sum
                }
                return .init(flag: .reservationResult, title: "예약 처리 결과를 확인하세요", detail: "이번 처리에서 HP 피해는 \(hpDamage), 남은 방벽은 \(battle.player.normalBarrier)입니다. 피해 감소가 먼저 적용되고 방벽이 남은 피해를 흡수합니다. 사용한 감소 효과와 처리된 예약은 사라집니다.")
            }
        }
        return nil
    }
}

struct ExpansionCombatGuideView: View {
    @EnvironmentObject private var gameSession: GameSessionStore
    let guide: ExpansionCombatGuide

    var body: some View {
        ZStack {
            Color.black.opacity(0.62).ignoresSafeArea().contentShape(Rectangle())
            VStack(alignment: .leading, spacing: 18) {
                Label("전투 규칙", systemImage: "info.circle").font(.caption).foregroundStyle(DAColor.gold)
                Text(guide.title).font(.title2.weight(.semibold)).foregroundStyle(DAColor.body)
                Text(guide.detail).font(.body).foregroundStyle(DAColor.body).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("확인") { gameSession.send(.markLoadoutTutorial(guide.flag)) }
                        .buttonStyle(.borderedProminent).tint(DAColor.magic).controlSize(.large)
                }
            }
            .padding(28).frame(maxWidth: 610)
            .background(DAColor.panel, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(DAColor.gold.opacity(0.5)))
            .padding(24)
        }
    }
}
