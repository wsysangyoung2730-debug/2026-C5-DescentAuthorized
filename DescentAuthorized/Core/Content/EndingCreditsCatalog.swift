import Foundation

struct EndingCreditsEntry: Identifiable, Equatable, Sendable {
    let floorNumber: Int
    let subtitle: String
    let text: String

    var id: Int { floorNumber }
    var title: String { "제\(floorNumber)층" }
}

enum EndingCreditsCatalog {
    static let title = "하강 기록"

    static let entries: [EndingCreditsEntry] = [
        .init(
            floorNumber: 10,
            subtitle: "첫 승인",
            text: "이름은 기억나지 않았다.\n손은 문을 여는 선을 기억하고 있었다."
        ),
        .init(
            floorNumber: 9,
            subtitle: "남겨진 필체",
            text: "나를 지우려던 기록 속에,\n나의 서명이 남아 있었다."
        ),
        .init(
            floorNumber: 8,
            subtitle: "최초의 관측",
            text: "처음 균열을 바라본 사람도 나였다.\n무엇을 보았는지는 아직 기억하지 못한다."
        ),
        .init(
            floorNumber: 7,
            subtitle: "기준점",
            text: "탑은 나를 기준으로 버티고 있었다.\n내가 떠나면 무엇이 남는지 확인해야 했다."
        ),
        .init(
            floorNumber: 6,
            subtitle: "먼저 도착한 결과",
            text: "아직 하지 않은 선택에,\n이미 나의 승인이 남아 있었다."
        ),
        .init(
            floorNumber: 5,
            subtitle: "기억의 원본",
            text: "같은 필체가 같은 나를 뜻하는 걸까.\n그 답은 끝내 확인하지 못했다."
        ),
        .init(
            floorNumber: 4,
            subtitle: "책임",
            text: "내 서명은 지우지 않았다.\n읽고도 외면한 이들의 이름도 함께 남겼다."
        ),
        .init(
            floorNumber: 3,
            subtitle: "동의",
            text: "그때 동의한 사실과,\n지금 마음이 달라진 사실은 함께 남을 수 있었다."
        ),
        .init(
            floorNumber: 2,
            subtitle: "교대",
            text: "“교대를 요청했다고 전해라.\n탈주했다고 적지 말고.”"
        ),
        .init(
            floorNumber: 1,
            subtitle: "마지막 승인",
            text: "모든 기억을 되찾지는 못했다.\n이번에는 지금의 내 뜻으로 서명했다."
        )
    ]

    static let handoffBody = "철회 요청. 교대 요청. 확인되지 않은 외부 교신.\n끝나지 않은 일들을 그대로 남겼다."
    static let finalQuote = "이번 승인을 앞으로의 모든 동의로 취급하지 말 것."
    static let creatorCredit = "Made by SangYoung Woo"
}
