import Foundation

extension SpellCatalog {
    static let lowerFloorSpells: [SpellID: SpellDefinition] = Dictionary(uniqueKeysWithValues: [
        lower(.bloodSealPiercing, "혈인 관통", .attack, .forbidden, 46,
              [[(25, 77), (50, 23), (72, 44), (42, 55), (76, 77)]]),
        lower(.limitBarrier, "한계 방벽", .defense, .forbidden, 50,
              [[(25, 78), (25, 28), (50, 16), (75, 28), (75, 78), (50, 62), (25, 78)]]),
        lower(.executionNullification, "집행 무효", .dispel, .forbidden, 58,
              [[(24, 30), (76, 30), (76, 70), (24, 70), (24, 30)], [(34, 80), (66, 20)]]),
        lower(.directHitProhibition, "직격 금지", .debuff, .forbidden, 44,
              [[(24, 70), (24, 28), (76, 28), (76, 70), (50, 50), (24, 70)]]),
        lower(.responsibilitySeverance, "책임 절단", .attack, .sealed, 78,
              [[(20, 66), (35, 30), (50, 50), (65, 30), (80, 66)], [(50, 18), (50, 82)]]),
        lower(.isolationBarrier, "격리 방벽", .defense, .sealed, 82,
              [[(35, 78), (22, 65), (22, 25), (78, 25), (78, 65), (65, 78)],
               [(35, 78), (35, 48), (65, 48), (65, 78), (35, 78)]]),
        lower(.pressureRelease, "축압 방출", .attack, .sealed, 92,
              [[(20, 24), (35, 45), (50, 55), (65, 45), (80, 24)],
               [(50, 55), (50, 80), (72, 65), (50, 80), (28, 65)]]),
        lower(.handoffBarrier, "인계 방벽", .defense, .sealed, 86,
              [[(20, 70), (20, 25), (50, 25), (50, 70), (20, 70)],
               [(50, 48), (65, 35), (80, 48), (80, 80), (50, 80), (50, 48)]])
    ].map { ($0.id, $0) })

    private static func lower(_ id: SpellID, _ name: String, _ category: SpellCategory,
                              _ tier: ScrollTier, _ mana: Double,
                              _ paths: [[(Double, Double)]]) -> SpellDefinition {
        SpellDefinition(id: id, name: name, category: category, tier: tier,
                        recommendedMana: mana, effect: .expansion(ExpansionSpellEffect(rawValue: id.rawValue)!),
                        glyph: GlyphDefinition(difficulty: paths.count == 2 ? .hard : .normal,
                            strokes: paths.map { coordinates in
                                let points = coordinates.map { NormalizedPoint(x: $0.0, y: $0.1) }
                                return GlyphStrokeSpec(start: points.first!, end: points.last!,
                                    requiredNodes: Array(points.dropFirst().dropLast()),
                                    referencePath: points, nodeRadius: 8, pathRadius: 9)
                            }, crossings: []))
    }

    static let lowerFloorMetadata: [SpellID: SpellMetadata] = [
        .bloodSealPiercing: .init(acquisitionFloor: 4, acquisitionKind: .recordChoice,
            effectSummary: "HP 8을 소모해 일반 방벽을 무시하고 34~46 피해. 적 방벽은 남습니다.",
            usageNote: "HP 8 초과 필요. 절대 방벽은 먼저 해제하세요. 실패에는 HP 대가가 없습니다."),
        .limitBarrier: .init(acquisitionFloor: 4, acquisitionKind: .choice,
            effectSummary: "HP 8을 소모해 방벽 40~50. 이번 적 행동까지 방벽 상한 60.",
            usageNote: "적 행동 종료 후 남은 방벽도 최대 40으로 복원됩니다. 반복 시전해도 상한 60입니다."),
        .executionNullification: .init(acquisitionFloor: 3, acquisitionKind: .recordChoice,
            effectSummary: "HP 10을 소모해 같은 적 행동에 도착하는 예약 최대 2건을 취소합니다.",
            usageNote: "2획 · 전투당 성공 1회. 등록된 예약 묶음을 지정합니다. 즉시 공격에는 영향이 없습니다."),
        .directHitProhibition: .init(acquisitionFloor: 3, acquisitionKind: .choice,
            effectSummary: "HP 8을 소모해 다음 일반 즉시 공격 1건의 피해를 0으로 만듭니다.",
            usageNote: "전투당 성공 1회 · 이번을 포함한 적 행동 2회. 예약·모사·반격은 막지 않습니다."),
        .responsibilitySeverance: .init(acquisitionFloor: 4, acquisitionKind: .recordChoice,
            effectSummary: "48~62 피해. 이번 적 행동의 다음 모사 또는 반격 1건을 50% 줄입니다.",
            usageNote: "2획 봉인 주문 · HP 대가 없음. 일반 공격과 예약은 줄이지 않으며 보호는 중첩되지 않습니다."),
        .isolationBarrier: .init(acquisitionFloor: 4, acquisitionKind: .choice,
            effectSummary: "방벽 20~28. 이번·다음 적 행동에 도착할 지정 예약 1건을 50% 줄입니다.",
            usageNote: "2획 봉인 주문. 대상이 없으면 방벽만 생성합니다. 취소·만료 시 보호도 사라집니다."),
        .pressureRelease: .init(acquisitionFloor: 3, acquisitionKind: .recordChoice,
            effectSummary: "자기 방벽 최대 16을 소비해 42~56 + 소비량×2 피해를 줍니다.",
            usageNote: "2획 봉인 주문. 실패·절대 방벽 차단 시 방벽을 소비하지 않습니다. 방벽 16이면 74~88 피해."),
        .handoffBarrier: .init(acquisitionFloor: 3, acquisitionKind: .choice,
            effectSummary: "방벽 22~30. 이번 적 행동의 첫 양수 피해 처리 후 방벽 18~24를 한 번 더 생성합니다.",
            usageNote: "2획 봉인 주문. 이미 받은 피해를 되돌리지 않습니다. 피해 0·HP 대가·방벽 소비는 발동하지 않습니다.")
    ]
}

extension SpellDefinition {
    var hpCost: Int {
        switch id {
        case .mimicProhibition: 6
        case .bloodSealPiercing, .limitBarrier, .directHitProhibition: 8
        case .executionNullification: 10
        default: 0
        }
    }
}
