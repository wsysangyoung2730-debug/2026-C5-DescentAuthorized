import Foundation

/// Prototype combat values remain independent of the replaceable character stage.
enum ExpansionEnemyCatalog {
    static func enemy(floor: Int, isBoss: Bool) -> EnemyDefinition? {
        switch floor {
        case 7: isBoss ? coordinateCorrectionAdministrator : coordinateDriftResidual
        default: nil
        }
    }

    static func enemy(_ id: EnemyID) -> EnemyDefinition? {
        switch id {
        case .coordinateDriftResidual: coordinateDriftResidual
        case .coordinateCorrectionAdministrator: coordinateCorrectionAdministrator
        default: nil
        }
    }

    static func phaseTwoPattern(for id: EnemyID, firstCycle: Bool) -> [EnemyAction]? {
        switch id {
        case .coordinateCorrectionAdministrator:
            [
                firstCycle
                    ? .grantAbsoluteBarrier(name: "절대 기준점", charges: 1)
                    : .attack(name: "기준점 타격", damage: 18, isStrong: false),
                .expansion(name: "축선 고정", action: .correctionBarrier(amount: 40)),
                .expansion(name: "강제 교정", action: .correctionStrike(normalDamage: 20, strengthenedDamage: 48)),
                .telegraph(name: "재측량", upcomingActionName: "피해 없는 빈틈")
            ]
        default: nil
        }
    }

    static let coordinateDriftResidual = EnemyDefinition(
        id: .coordinateDriftResidual,
        name: "좌표 표류 잔류체",
        maxHP: 160,
        startingAbsoluteBarrierCharges: 0,
        pattern: [
            .attack(name: "표류 충돌", damage: 12, isStrong: false),
            .expansion(name: "임시 좌표 고정", action: .correctionBarrier(amount: 18)),
            .expansion(name: "축선 돌진", action: .correctionStrike(normalDamage: 10, strengthenedDamage: 28)),
            .telegraph(name: "좌표 붕괴", upcomingActionName: "피해 없는 빈틈")
        ],
        thresholdRules: []
    )

    static let coordinateCorrectionAdministrator = EnemyDefinition(
        id: .coordinateCorrectionAdministrator,
        name: "좌표 교정 관리자",
        maxHP: 380,
        startingAbsoluteBarrierCharges: 0,
        pattern: [
            .attack(name: "기준점 타격", damage: 16, isStrong: false),
            .expansion(name: "축선 고정", action: .correctionBarrier(amount: 30)),
            .expansion(name: "강제 교정", action: .correctionStrike(normalDamage: 16, strengthenedDamage: 40)),
            .telegraph(name: "재측량", upcomingActionName: "피해 없는 빈틈")
        ],
        thresholdRules: []
    )
}
