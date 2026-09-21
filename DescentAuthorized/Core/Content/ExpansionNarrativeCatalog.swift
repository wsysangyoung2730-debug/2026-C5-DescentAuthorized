import Foundation

struct NarrativeDialogue: Equatable, Sendable {
    let speaker: String
    let text: String
}

/// One authored sequence for each floor, enemy and encounter outcome.
struct ExpansionNarrative: Equatable, Sendable {
    let floorNumber: Int
    let isBoss: Bool
    let isDefeated: Bool

    var backgroundAsset: String {
        "Floor\(floorNumber)\(isBoss ? "Administrator" : "Residual")\(isDefeated ? "Defeated" : "Encounter")"
    }

    var recordTitle: String { isDefeated ? "처치 기록" : "조우 기록" }

    var finalAccessibilityHint: String {
        if !isDefeated { return "전투 시작" }
        return isBoss ? "두루마리 선택으로 이동" : "관리자 구역 봉인문으로 이동"
    }

    var dialogues: [NarrativeDialogue] {
        switch (floorNumber, isBoss, isDefeated) {
        case (7, false, false):
            [
                .init(speaker: "좌표 표류 잔류체", text: "“좌표… 표류… 기준점… 없음… 그런데… 왜… 당신을 중심으로… 돌아오지…?”")
            ]
        case (7, false, true):
            [
                .init(speaker: "좌표 표류 잔류체", text: "“기준점… 복귀… 표류 종료… 좌표 기록을… 아래로… 반환…”")
            ]
        case (7, true, false):
            [
                .init(speaker: "좌표 교정 관리자", text: "“외부 기준 좌표 고정, 미등록 하강자의 재진입을 확인했습니다.”"),
                .init(speaker: "좌표 교정 관리자", text: "“대상의 생체 파형이 최초 기준점 기록과 일치합니다.”"),
                .init(speaker: "좌표 교정 관리자", text: "“좌표 교정 절차를 실행합니다, 기준에서 벗어난 존재는—원점으로 반환합니다.”")
            ]
        case (7, true, true):
            [
                .init(speaker: "좌표 교정 관리자", text: "“외부 기준 좌표 붕괴… 교정 절차를 유지할 수 없습니다.”"),
                .init(speaker: "좌표 교정 관리자", text: "“최초 고정자 생체 파형 확인… 기준점은 이미… 당신…”"),
                .init(speaker: "주인공", text: "“이 탑이 나를 가둔 게 아니라, 나를 기준으로 버티고 있었다는 건가.”")
            ]
        case (6, false, false):
            [
                .init(speaker: "결과 지연 잔류체", text: "“결과… 도착… 원인… 미발생… 승인자는… 아직… 오지 않았는데…?”")
            ]
        case (6, false, true):
            [
                .init(speaker: "결과 지연 잔류체", text: "“집행… 지연… 승인 시각… 절차 설계보다… 먼저…”")
            ]
        case (6, true, false):
            [
                .init(speaker: "인과 검증 관리자", text: "“인과 기록 검증, 대상의 진입 결과가 원인보다 먼저 등록되었습니다.”"),
                .init(speaker: "인과 검증 관리자", text: "“선행 승인자의 필체가 현재 대상과 일치합니다.”"),
                .init(speaker: "인과 검증 관리자", text: "“결과 집행 절차를 실행합니다, 아직 선택하지 않은 원인은—회수합니다.”")
            ]
        case (6, true, true):
            [
                .init(speaker: "인과 검증 관리자", text: "“인과 기록 역전… 결과를 원인으로 되돌릴 수 없습니다.”"),
                .init(speaker: "인과 검증 관리자", text: "“선행 승인자 확인… 당신의 결과가… 당신의 원인을 생성했습니다.”"),
                .init(speaker: "주인공", text: "“내가 만들기도 전에 들어오겠다고 승인했다면… 먼저 이곳에 온 나는 누구지.”")
            ]
        case (5, false, false):
            [
                .init(speaker: "기억 누락 잔류체", text: "“원본… 없음… 복원… 반복… 같은 필체… 그런데… 기억은… 전부 달라…”")
            ]
        case (5, false, true):
            [
                .init(speaker: "기억 누락 잔류체", text: "“누락… 아님… 분리… 기억 원본은… 아래에… 보관…”")
            ]
        case (5, true, false):
            [
                .init(speaker: "기억 원본 관리자", text: "“기억 원본 대조, 현재 개체의 필체가 등록된 원본과 일치합니다.”"),
                .init(speaker: "기억 원본 관리자", text: "“권한 정보 소실, 복원 이력은 열람 제한 상태입니다.”"),
                .init(speaker: "기억 원본 관리자", text: "“허용 범위를 벗어난 자아 기록을 확인했습니다, 대조 완료 후—말소합니다.”")
            ]
        case (5, true, true):
            [
                .init(speaker: "기억 원본 관리자", text: "“필체 일치… 권한 불일치… 복원 회차를 확인할 수 없습니다.”"),
                .init(speaker: "기억 원본 관리자", text: "“원본과 현재 개체의 구분에 실패했습니다… 하위 보관소에서 재대조하십시오.”"),
                .init(speaker: "주인공", text: "“기억을 잃은 게 아니라 떼어 낸 뒤 다시 만들어진 거라면… 지금의 나는 몇 번째지.”")
            ]
        default:
            []
        }
    }
}
