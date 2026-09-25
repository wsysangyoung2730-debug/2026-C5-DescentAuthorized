import Foundation

/// Stable identifiers distinguish two independent rewards on the same floor.
enum ExpansionRewardSite: String, Codable, CaseIterable, Sendable {
    case floor4Record, floor4Boss, floor3Record, floor3Boss, floor2Boss

    var floorNumber: Int {
        switch self {
        case .floor4Record, .floor4Boss: 4
        case .floor3Record, .floor3Boss: 3
        case .floor2Boss: 2
        }
    }

    var isRecord: Bool { self == .floor4Record || self == .floor3Record }
    var title: String { isRecord ? "기록 해독" : "관리자 보상" }
}

extension ExpansionProgress {
    var isLowerFloor: Bool { (1...4).contains(floorNumber) }
    var requiredDescentStages: Int { isLowerFloor ? 3 : 2 }
    var requiredResidualCount: Int { isLowerFloor ? 2 : 1 }
    var rewardSite: ExpansionRewardSite? {
        switch (floorNumber, stage) {
        case (4, .recordReward): .floor4Record
        case (4, .reward): .floor4Boss
        case (3, .recordReward): .floor3Record
        case (3, .reward): .floor3Boss
        case (2, .reward): .floor2Boss
        default: nil
        }
    }
}
