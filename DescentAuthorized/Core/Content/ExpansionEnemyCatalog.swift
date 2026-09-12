import Foundation

/// Prototype combat values remain independent of the replaceable character stage.
enum ExpansionEnemyCatalog {
    static func enemy(floor: Int, isBoss: Bool) -> EnemyDefinition? {
        switch floor {
        case 7: isBoss ? coordinateCorrectionAdministrator : coordinateDriftResidual
        case 6: isBoss ? causalityVerificationAdministrator : delayedConsequenceResidual
        default: nil
        }
    }

    static func enemy(_ id: EnemyID) -> EnemyDefinition? {
        switch id {
        case .coordinateDriftResidual: coordinateDriftResidual
        case .coordinateCorrectionAdministrator: coordinateCorrectionAdministrator
        case .delayedConsequenceResidual: delayedConsequenceResidual
        case .causalityVerificationAdministrator: causalityVerificationAdministrator
        default: nil
        }
    }

    static func phaseTwoPattern(for id: EnemyID, firstCycle: Bool) -> [EnemyAction]? {
        switch id {
        case .causalityVerificationAdministrator:
            causalityPattern(phaseTwo: true)
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
    static let delayedConsequenceResidual = EnemyDefinition(
        id: .delayedConsequenceResidual, name: "결과 지연 잔류체", maxHP: 180,
        startingAbsoluteBarrierCharges: 0,
        pattern: [
            .expansion(name: "잔류 증폭", action: .amplify(multiplier: 1.5)),
            .expansion(name: "결과 각인", action: .schedule([.init(name: "지연 충돌", damage: 24, turnsFromNow: 2)])),
            .attack(name: "늦은 잔격", damage: 10, isStrong: false),
            .expansion(name: "지연 충돌", action: .wait)
        ], thresholdRules: []
    )

    static let causalityVerificationAdministrator = EnemyDefinition(
        id: .causalityVerificationAdministrator, name: "인과 검증 관리자", maxHP: 420,
        startingAbsoluteBarrierCharges: 0, pattern: causalityPattern(phaseTwo: false), thresholdRules: []
    )

    private static func causalityPattern(phaseTwo: Bool) -> [EnemyAction] {
        let reservations: [ScheduledDamageSpec] = phaseTwo
            ? [.init(name: "제1결과 집행", damage: 34, turnsFromNow: 2),
               .init(name: "제2결과 집행", damage: 16, turnsFromNow: 3)]
            : [.init(name: "제1결과 집행", damage: 32, turnsFromNow: 2)]
        return [
            .expansion(name: "인과 증폭", action: .amplify(multiplier: 1.5)),
            .expansion(name: "집행 등록", action: .schedule(reservations)),
            .attack(name: "원인 추궁", damage: phaseTwo ? 14 : 12, isStrong: false),
            .expansion(name: "제1결과 집행", action: .wait),
            .expansion(name: phaseTwo ? "제2결과 집행" : "기록 정리", action: .wait)
        ]
    }

}
