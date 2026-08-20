import Foundation

enum EnemyCatalog {
    static let all: [EnemyID: EnemyDefinition] = [
        .recordsAdministrator: recordsAdministrator,
        .observationResidual: observationResidual,
        .observationAdministrator: observationAdministrator
    ]

    static func enemy(_ id: EnemyID) -> EnemyDefinition {
        guard let enemy = all[id] else {
            preconditionFailure("Missing enemy definition: \(id.rawValue)")
        }
        return enemy
    }

    static let recordsAdministrator = EnemyDefinition(
        id: .recordsAdministrator,
        name: "9층 기록 관리자",
        maxHP: 120,
        startingAbsoluteBarrierCharges: 0,
        pattern: [
            .attack(name: "기록 찌르기", damage: 14, isStrong: false),
            .grantNormalBarrier(name: "문서 방벽", amount: 22)
        ],
        thresholdRules: [
            EnemyThresholdRule(
                id: "records-erasure-zone",
                hpFraction: 0.5,
                effect: .addErasureZone(
                    ErasureZone(
                        id: "records-erasure-zone",
                        bounds: NormalizedRect(minX: 8, minY: 18, maxX: 30, maxY: 48)
                    )
                )
            )
        ]
    )

    static let observationResidual = EnemyDefinition(
        id: .observationResidual,
        name: "관측 잔류체",
        maxHP: 72,
        startingAbsoluteBarrierCharges: 0,
        pattern: [
            .attack(name: "유리 파편", damage: 10, isStrong: false),
            .telegraph(name: "초점 고정", upcomingActionName: "집속 파편"),
            .attack(name: "집속 파편", damage: 26, isStrong: true)
        ],
        thresholdRules: []
    )

    static let observationAdministrator = EnemyDefinition(
        id: .observationAdministrator,
        name: "8층 관측 관리자",
        maxHP: 165,
        startingAbsoluteBarrierCharges: 1,
        pattern: [
            .attack(name: "파편 조사", damage: 18, isStrong: false),
            .telegraph(name: "초점 고정", upcomingActionName: "균열 조사광"),
            .attack(name: "균열 조사광", damage: 42, isStrong: true),
            .grantAbsoluteBarrier(name: "관측 차폐막", charges: 1)
        ],
        thresholdRules: [
            EnemyThresholdRule(
                id: "observation-half-barrier",
                hpFraction: 0.5,
                effect: .grantAbsoluteBarrier(charges: 1)
            )
        ]
    )
}

