import Foundation

/// Stable record IDs are shared by save progress, scroll content and spatial anchors.
struct ExpansionInvestigationRecord: Equatable, Sendable {
    let id: String
    let entityName: String
    let title: String
    let detection: String
    let body: String
    let tag: String
}

enum ExpansionInvestigationCatalog {
    static func records(for floor: Int) -> [ExpansionInvestigationRecord] {
        switch floor {
        case 7: [
            .init(id: "floor7.residue.fractured-map", entityName: "F07A_FracturedMap",
                  title: "제자리에서 어긋난 지도", detection: "좌표 불일치 기록 감지",
                  body: "지도에는 같은 방이 서로 다른 위치에 겹쳐 있다.\n측량자는 기준점을 세 번 고쳤지만,\n마지막 표식은 처음 위치로 돌아와 있다.\n\n여백에는 짧은 경고가 남아 있다.\n‘움직이는 것은 방이 아니라 관측의 기준이다.’",
                  tag: "좌표 표류의 흔적"),
            .init(id: "floor7.residue.calibration-log", entityName: "F07A_Console",
                  title: "완료되지 않은 좌표 교정", detection: "교정 장치의 잔류 신호 감지",
                  body: "교정 단말은 존재하지 않는 대상을 계속 추적한다.\n대상을 고정한 직후에는 측정치가 급격히 치솟았다.\n\n‘임시 방벽 유지 중 축선 돌진 위험.\n방벽을 먼저 무너뜨리면 충돌이 약해진다.’\n기록 아래에서 새로운 좌표가 천천히 떠오른다.",
                  tag: "방벽과 강공격의 연결")
        ]
        case 6: [
            .init(id: "floor6.residue.delayed-evidence", entityName: "F06A_EvidenceBank03",
                  title: "원인보다 늦게 도착한 흔적", detection: "집행 시각이 어긋난 기록 감지",
                  body: "증거 보관함에는 충격이 없는 순간의 파편과\n아무것도 닿지 않은 순간의 파손 기록이 함께 있다.\n\n원인은 끝났어도 결과는 아직 남아 있다.\n접수표에 적힌 집행 턴이 되면\n예약된 충격이 뒤늦게 도착하는 듯하다.",
                  tag: "예약 피해의 집행 시각"),
            .init(id: "floor6.residue.result-reel", entityName: "F06A_ReelBank03",
                  title: "되감기지 않는 결과", detection: "중복 집행 테이프 반응 감지",
                  body: "기록 릴은 같은 구간을 돌지만\n결과가 찍히는 칸은 매번 앞으로 밀린다.\n\n‘예고를 지웠다고 집행까지 사라지는 것은 아니다.\n남은 시간을 확인하고 충격을 받아낼 준비를 하라.’\n멈춰 있던 릴의 끝이 가늘게 떨린다.",
                  tag: "방어와 출력 저하로 충격 대비")
        ]
        case 5: [
            .init(id: "floor5.residue.missing-voice", entityName: "F05A_Playback",
                  title: "이름만 사라진 목소리", detection: "기억 재생 장치의 누락 구간 감지",
                  body: "목소리는 자신의 이름을 말하려는 순간마다 끊긴다.\n남아 있는 것은 누군가의 주문을\n같은 억양으로 따라 읽는 소리뿐이다.\n\n‘방금 성공한 문양을 기억한다.\n같은 문양을 되풀이하면 그것도 따라 한다.’\n재생이 끝났는데도 뒤에서 한 번 더 소리가 난다.",
                  tag: "같은 주문의 반복에 반응"),
            .init(id: "floor5.residue.blank-name-tags", entityName: "F05A_LostTags",
                  title: "주인을 잃은 이름표", detection: "식별 기록의 공백 감지",
                  body: "이름표의 봉인은 멀쩡하지만 이름만 비어 있다.\n보관 번호를 대조해도 원본은 나오지 않는다.\n\n빈칸 아래에는 다른 필체의 메모가 있다.\n‘기록을 정화하거나 다른 문양으로 연결할 것.\n잃어버린 기억은 남의 행동으로 빈자리를 채운다.’",
                  tag: "정화 또는 다른 주문으로 대응")
        ]
        default: lowerRecords(for: floor)
        }
    }

    static func isComplete(floor: Int, readRecordIDs: Set<String>) -> Bool {
        let records = records(for: floor)
        return !records.isEmpty && records.allSatisfy { readRecordIDs.contains($0.id) }
    }
}
