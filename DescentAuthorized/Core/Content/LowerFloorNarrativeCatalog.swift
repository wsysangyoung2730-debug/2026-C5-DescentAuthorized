import Foundation

extension ExpansionInvestigationCatalog {
    static func lowerRecords(for floor: Int) -> [ExpansionInvestigationRecord] {
        let entries: [(String, String, String)] = switch floor {
        case 4: [
            ("기억 손실 위험 고지", "책임자가 직접 서명한 고지서", "봉인 유지의 대가로 기억이 손실될 수 있다.\n안전장치의 마지막 승인란에는 내 필체가 남아 있다.\n\n서명 모사는 직전 성공 주문을 다시 쓰면 반응한다. 다른 주문을 연결하면 추가타를 피할 수 있다."),
            ("반려 집행 대장", "검수 창구 아래의 붉은 인장", "반려는 판단을 되돌리지 않는다. 책임을 다음 사람에게 넘길 뿐이다.\n\n반격 준비 다음 턴에 공격 주문을 성공하면 추가타가 한 번 도착한다. 방어로 쉬거나 피해를 감수할 수 있다.")]
        case 3: [
            ("격리 동의서", "안쪽을 향한 잠금장치", "격리 요청자와 대상자가 동일하다. 외부 강제 수용 명령은 없다.\n\n봉인 후보 중 한 주문을 직접 선택한다. 기본 대응 공격·방어와 봉인 해제는 보호된다."),
            ("집행 시각표", "비어 있는 개인실의 접수표", "격리가 승인된 순간과 집행되는 순간은 다르다.\n\n예약마다 도착 턴을 확인하라. 강화된 절차에서는 두 건이 같은 턴에 도착한다.")]
        case 2: [
            ("폐쇄 불가 보고", "청록빛 냉각 배관", "탑은 균열을 없애지 못한다. 분산하고 지연하며 무너지는 시점을 늦춘다.\n\n증폭은 예약이 등록되기 전에 지울 수 있다. 이미 확정된 피해는 바뀌지 않는다."),
            ("유지 인계 서약", "과부하 기록이 남은 분배기", "책임자 승인 없이는 다음 구간으로 유지 업무를 넘길 수 없다. 내가 남기로 한 이유가 여기 있다.\n\n한 번의 강타와 두 번의 분할 피해는 다르다. 첫 타격에 쓰이는 보호 효과를 확인하라.")]
        case 1: [
            ("신원 대조 접수증", "정렬된 문서함", "기억은 달라져도 승인자의 서명은 일치한다. 마지막 심사는 하나의 체력 안에서 세 절차로 이어진다.\n\n모사·반격·예약은 이미 겪었던 규칙이다. 새로운 입력 제한은 없다."),
            ("출구 승인 안내", "빛이 새어 나오는 문 앞", "출구 표식 아래에는 세 개의 승인란이 남아 있다.\n\n기본 대응 주문은 봉인되지 않는다. 유지 심사의 절대 방벽은 봉인 해제로 제거할 수 있다.")]
        default: []
        }
        return entries.enumerated().map { index, value in
            .init(id: "floor\(floor).residue.record-\(index)", entityName: "LowerFloorRecord\(index)",
                  title: value.0, detection: value.1, body: value.2, tag: "제\(floor)층 조사 기록")
        }
    }
}

enum LowerFloorNarrativeCatalog {
    static func encounter(_ current: ExpansionProgress) -> [NarrativeDialogue] {
        let enemy = ExpansionEnemyCatalog.enemy(floor: current.floorNumber, isBoss: current.showsBoss, residualIndex: current.residualIndex)
        let defeated = [.residualDefeated, .bossDefeated].contains(current.stage)
        let line: String = switch (current.floorNumber, current.showsBoss, defeated) {
        case (4, true, false): "위험 고지와 책임자 서명이 일치합니다. 자신이 승인한 절차를 감당하십시오."
        case (4, true, true): "기억 손실 위험 고지 완료… 책임자 승인은 철회되지 않았습니다."
        case (3, true, false): "격리 동의자를 확인했습니다. 외부의 명령이 아닌 본인의 요청을 집행합니다."
        case (3, true, true): "강제 수용 명령 없음. 당신은 봉인을 유지하기 위해 스스로 남았습니다."
        case (2, true, false): "균열 폐쇄 불가. 유지 업무를 넘길 자격을 검증합니다."
        case (2, true, true): "분산 유지 승인. 다음 구간의 접수 절차를 진행하십시오."
        case (1, true, false): "신원 심사, 유지 심사, 인계 심사. 마지막 승인 절차를 개시합니다."
        case (1, true, true): "심사 완료. 최종 기록을 열람하고 출구의 세 승인란을 완성하십시오."
        case (_, false, true): current.residualIndex == 0 ? "첫 집행이 멎었다. 같은 방의 다른 조사 구역에서 신호가 남아 있다." : "두 번째 집행이 멎었다. 관리자 구역의 중간문에 접근할 수 있다."
        default: current.residualIndex == 0 ? "기록 속 절차가 형태를 얻었다. 첫 번째 잔류체가 승인자를 대조한다." : "남은 집행이 깨어난다. 이번 절차의 예고를 확인하라."
        }
        return [.init(speaker: defeated && !current.showsBoss ? "주인공" : enemy?.name ?? "승인 기록", text: line)]
    }
}
