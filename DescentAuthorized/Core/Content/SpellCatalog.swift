import Foundation

enum SpellCatalog {
    static let all: [SpellID: SpellDefinition] = [
        .afterglowErasure: afterglowErasure,
        .riftSeverance: riftSeverance,
        .barrierPiercing: barrierPiercing,
        .basicBarrier: basicBarrier,
        .sealRelease: sealRelease,
        .chainInscription: chainInscription,
        .condensedBarrier: condensedBarrier,
        .purificationGlyph: purificationGlyph,
        .lingeringBarrier: lingeringBarrier,
        .focusedRupture: focusedRupture,
        .axisSeverance: axisSeverance,
        .anchorGuard: anchorGuard,
        .consequenceErasure: consequenceErasure,
        .outputReduction: outputReduction,
        .executionDelay: executionDelay,
        .advanceVerdict: advanceVerdict,
        .causalCushion: causalCushion,
        .memorySeverance: memorySeverance,
        .memorySuture: memorySuture,
        .mimicProhibition: mimicProhibition
    ]

    static func spell(_ id: SpellID) -> SpellDefinition {
        guard let spell = all[id] else {
            preconditionFailure("Missing spell definition: \(id.rawValue)")
        }
        return spell
    }

    static let afterglowErasure = SpellDefinition(
        id: .afterglowErasure,
        name: "잔광 말소",
        category: .attack,
        tier: .worn,
        recommendedMana: 30,
        effect: .damage(minimum: 18, maximum: 25, piercesNormalBarrier: false),
        glyph: GlyphDefinition(
            difficulty: .easy,
            strokes: [
                stroke(
                    points: [(20, 55), (37, 72), (67, 28), (78, 43), (66, 51)],
                    requiredNodeIndices: [1, 2],
                    optionalNodeIndices: [3],
                    nodeRadius: 9,
                    pathRadius: 10,
                    optionalNodeGradeCap: .incomplete
                )
            ],
            crossings: []
        )
    )

    static let riftSeverance = SpellDefinition(
        id: .riftSeverance,
        name: "균열 절단",
        category: .attack,
        tier: .worn,
        recommendedMana: 42,
        effect: .damage(minimum: 28, maximum: 40, piercesNormalBarrier: false),
        glyph: GlyphDefinition(
            difficulty: .normal,
            strokes: [
                stroke(
                    points: [(18, 68), (39, 25), (34, 56), (68, 35), (55, 75), (82, 58), (72, 48)],
                    requiredNodeIndices: [1, 2, 3, 4, 5],
                    nodeRadius: 8,
                    pathRadius: 8.5
                )
            ],
            crossings: []
        )
    )

    static let barrierPiercing = SpellDefinition(
        id: .barrierPiercing,
        name: "방벽 관통",
        category: .attack,
        tier: .engraved,
        recommendedMana: 75,
        effect: .damage(minimum: 34, maximum: 48, piercesNormalBarrier: true),
        glyph: GlyphDefinition(
            difficulty: .hard,
            strokes: [
                stroke(
                    points: [
                        // Rise from the lower left along the right side of the loop,
                        // turn left over the top, then descend through the first pass.
                        (24, 72), (30, 63), (37, 54),
                        (44, 45), (50, 34), (55, 23),
                        (59, 14), (57, 8), (51, 6),
                        (44, 10), (40, 18), (37, 30),
                        (36, 43), (37, 54), (40, 63),
                        (43, 69), (49, 74), (56, 78),
                        (62, 79), (69, 77), (76, 72)
                    ],
                    requiredNodeIndices: [2, 4, 8, 11, 13, 18],
                    nodeRadius: 9,
                    pathRadius: 9
                ),
                stroke(
                    points: [
                        (76, 8), (72, 20), (70, 32),
                        (67, 45), (65, 58), (62, 70),
                        (60, 79), (56, 87), (51, 92), (46, 94)
                    ],
                    requiredNodeIndices: [3, 6],
                    nodeRadius: 9,
                    pathRadius: 9
                )
            ],
            crossings: [
                GlyphCrossingRequirement(
                    firstStrokeIndex: 0,
                    secondStrokeIndex: 1,
                    center: point(60, 78),
                    radius: 10
                )
            ]
        )
    )

    static let basicBarrier = SpellDefinition(
        id: .basicBarrier,
        name: "초급 방벽",
        category: .defense,
        tier: .worn,
        recommendedMana: 32,
        effect: .fixedBarrier(minimum: 20, maximum: 30, maxStack: 40),
        glyph: GlyphDefinition(
            difficulty: .easy,
            strokes: [
                stroke(
                    points: [(22, 68), (25, 42), (43, 24), (62, 28), (78, 50), (69, 72), (50, 78)],
                    requiredNodeIndices: [2, 4],
                    optionalNodeIndices: [1, 3, 5],
                    nodeRadius: 9,
                    pathRadius: 10
                )
            ],
            crossings: []
        )
    )

    static let sealRelease = SpellDefinition(
        id: .sealRelease,
        name: "봉인 해제",
        category: .dispel,
        tier: .worn,
        recommendedMana: 28,
        effect: .dispelAbsoluteBarrier(minimumCharges: 1, maximumCharges: 2),
        glyph: GlyphDefinition(
            difficulty: .normal,
            strokes: [
                stroke(
                    points: [(25, 72), (42, 57), (51, 48), (70, 27), (62, 55), (81, 68)],
                    requiredNodeIndices: [1, 2, 3, 4],
                    nodeRadius: 8,
                    pathRadius: 8.5
                )
            ],
            crossings: []
        )
    )

    private static func stroke(
        points values: [(Double, Double)],
        requiredNodeIndices: [Int],
        optionalNodeIndices: [Int] = [],
        nodeRadius: Double,
        pathRadius: Double,
        optionalNodeGradeCap: CastingGrade? = nil
    ) -> GlyphStrokeSpec {
        let points = values.map(point)
        return GlyphStrokeSpec(
            start: points[0],
            end: points[points.count - 1],
            requiredNodes: requiredNodeIndices.map { points[$0] },
            optionalNodes: optionalNodeIndices.map { points[$0] },
            referencePath: points,
            nodeRadius: nodeRadius,
            pathRadius: pathRadius,
            optionalNodeGradeCap: optionalNodeGradeCap
        )
    }

    private static func point(_ x: Double, _ y: Double) -> NormalizedPoint {
        NormalizedPoint(x: x, y: y)
    }
}

// MARK: - 7–5F expansion spell definitions

extension SpellCatalog {
    static let chainInscription = SpellDefinition(
        id: .chainInscription,
        name: "연쇄 각인",
        category: .attack,
        tier: .worn,
        recommendedMana: 36,
        effect: .expansion(.chainInscription),
        glyph: expansionGlyph(
            difficulty: .easy,
            paths: [
                [(16, 68), (31, 37), (48, 62), (64, 30), (83, 49)]
            ]
        )
    )

    static let condensedBarrier = SpellDefinition(
        id: .condensedBarrier,
        name: "응축 방벽",
        category: .defense,
        tier: .engraved,
        recommendedMana: 48,
        effect: .fixedBarrier(minimum: 28, maximum: 36, maxStack: 40),
        glyph: expansionGlyph(
            difficulty: .normal,
            paths: [
                [(18, 30), (50, 18), (82, 30), (75, 65), (50, 85), (25, 65), (30, 40), (50, 32), (70, 40), (64, 61), (50, 71)]
            ]
        )
    )

    static let purificationGlyph = SpellDefinition(
        id: .purificationGlyph,
        name: "정화 각인",
        category: .dispel,
        tier: .engraved,
        recommendedMana: 32,
        effect: .expansion(.purificationGlyph),
        glyph: expansionGlyph(
            difficulty: .normal,
            paths: [
                [(23, 72), (49, 22), (77, 72), (50, 56), (34, 77)]
            ]
        )
    )

    static let lingeringBarrier = SpellDefinition(
        id: .lingeringBarrier,
        name: "잔류 방벽",
        category: .defense,
        tier: .engraved,
        recommendedMana: 38,
        effect: .expansion(.lingeringBarrier),
        glyph: expansionGlyph(
            difficulty: .normal,
            paths: [
                [(20, 70), (22, 39), (47, 20), (78, 39), (76, 70), (49, 83), (37, 62), (51, 44), (65, 58)]
            ]
        )
    )

    static let focusedRupture = SpellDefinition(
        id: .focusedRupture,
        name: "집속 파열",
        category: .attack,
        tier: .sealed,
        recommendedMana: 85,
        effect: .damage(minimum: 62, maximum: 82, piercesNormalBarrier: false),
        glyph: expansionGlyph(
            difficulty: .hard,
            paths: [
                [(50, 14), (81, 50), (50, 86), (19, 50), (50, 14)],
                [(12, 50), (50, 50), (88, 50)]
            ],
            crossings: [point(19, 50), point(81, 50)]
        )
    )

    static let axisSeverance = SpellDefinition(
        id: .axisSeverance,
        name: "축선 절단",
        category: .attack,
        tier: .engraved,
        recommendedMana: 46,
        effect: .expansion(.axisSeverance),
        glyph: expansionGlyph(
            difficulty: .normal,
            paths: [
                [(19, 74), (42, 50), (29, 25), (68, 25), (55, 50), (82, 74), (63, 80), (45, 62)]
            ]
        )
    )

    static let anchorGuard = SpellDefinition(
        id: .anchorGuard,
        name: "기준점 수호",
        category: .defense,
        tier: .sealed,
        recommendedMana: 42,
        effect: .expansion(.anchorGuard),
        glyph: expansionGlyph(
            difficulty: .hard,
            paths: [
                [(50, 16), (50, 69), (24, 49), (21, 71), (50, 85), (79, 71), (76, 49), (61, 61)]
            ]
        )
    )

    static let consequenceErasure = SpellDefinition(
        id: .consequenceErasure,
        name: "결과 말소",
        category: .dispel,
        tier: .sealed,
        recommendedMana: 58,
        effect: .expansion(.consequenceErasure),
        glyph: expansionGlyph(
            difficulty: .hard,
            paths: [
                [(18, 24), (72, 24), (82, 40), (70, 56), (36, 56), (20, 76), (76, 76)],
                [(77, 16), (58, 45), (42, 68), (26, 88)]
            ],
            crossings: [point(71.8, 24), point(50.3, 56), point(36.2, 76)]
        )
    )

    static let outputReduction = SpellDefinition(
        id: .outputReduction,
        name: "출력 저하",
        category: .debuff,
        tier: .worn,
        recommendedMana: 30,
        effect: .expansion(.outputReduction),
        glyph: expansionGlyph(
            difficulty: .easy,
            paths: [
                [(25, 24), (50, 52), (75, 24), (75, 54), (50, 80), (25, 54)]
            ]
        )
    )

    static let executionDelay = SpellDefinition(
        id: .executionDelay,
        name: "집행 지연",
        category: .debuff,
        tier: .sealed,
        recommendedMana: 42,
        effect: .expansion(.executionDelay),
        glyph: expansionGlyph(
            difficulty: .hard,
            paths: [
                [(77, 27), (31, 27), (20, 50), (35, 74), (77, 74), (61, 56), (45, 72)]
            ]
        )
    )

    static let advanceVerdict = SpellDefinition(
        id: .advanceVerdict,
        name: "선행 판결",
        category: .attack,
        tier: .engraved,
        recommendedMana: 48,
        effect: .expansion(.advanceVerdict),
        glyph: expansionGlyph(
            difficulty: .normal,
            paths: [
                [(18, 76), (52, 21), (85, 76), (61, 58), (39, 58), (30, 40), (72, 40)]
            ]
        )
    )

    static let causalCushion = SpellDefinition(
        id: .causalCushion,
        name: "인과 완충",
        category: .defense,
        tier: .sealed,
        recommendedMana: 40,
        effect: .expansion(.causalCushion),
        glyph: expansionGlyph(
            difficulty: .hard,
            paths: [
                [(19, 29), (21, 62), (41, 81), (66, 76), (81, 54), (74, 26), (60, 43), (61, 63), (43, 61), (37, 42)]
            ]
        )
    )

    static let memorySeverance = SpellDefinition(
        id: .memorySeverance,
        name: "기억 절단",
        category: .attack,
        tier: .engraved,
        recommendedMana: 44,
        effect: .expansion(.memorySeverance),
        glyph: expansionGlyph(
            difficulty: .normal,
            paths: [
                [(20, 22), (41, 41), (29, 61), (48, 79), (67, 58), (55, 38), (79, 19)]
            ]
        )
    )

    static let memorySuture = SpellDefinition(
        id: .memorySuture,
        name: "기억 봉합",
        category: .defense,
        tier: .sealed,
        recommendedMana: 50,
        effect: .expansion(.memorySuture),
        glyph: expansionGlyph(
            difficulty: .hard,
            paths: [
                [(21, 29), (76, 45), (25, 60), (76, 78), (59, 83), (44, 67), (60, 51), (45, 34), (58, 18)]
            ]
        )
    )

    static let mimicProhibition = SpellDefinition(
        id: .mimicProhibition,
        name: "모사 금지",
        category: .debuff,
        tier: .forbidden,
        recommendedMana: 38,
        effect: .expansion(.mimicProhibition),
        glyph: expansionGlyph(
            difficulty: .hard,
            paths: [
                [(20, 75), (22, 31), (43, 21), (49, 45), (57, 21), (78, 31), (80, 75), (51, 58), (33, 81), (71, 18)]
            ]
        )
    )

    /// Prototype paths are deliberately distinct; every corner must be traced in order.
    /// Existing five glyph definitions above remain unchanged.
    private static func expansionGlyph(
        difficulty: GlyphDifficulty,
        paths: [[(Double, Double)]],
        crossings: [NormalizedPoint] = []
    ) -> GlyphDefinition {
        let radius: Double = difficulty == .easy ? 9 : 8
        return GlyphDefinition(
            difficulty: difficulty,
            strokes: paths.map { values in
                stroke(
                    points: values,
                    requiredNodeIndices: Array(1..<(values.count - 1)),
                    nodeRadius: radius,
                    pathRadius: radius + 1
                )
            },
            crossings: crossings.map {
                GlyphCrossingRequirement(
                    firstStrokeIndex: 0,
                    secondStrokeIndex: 1,
                    center: $0,
                    radius: 8
                )
            }
        )
    }
}

// MARK: - Spell acquisition and player-facing rules

enum SpellAcquisitionKind: String, Codable, Sendable {
    case automatic
    case choice
    case fixedLesson
}

struct SpellMetadata: Equatable, Sendable {
    let acquisitionFloor: Int
    let acquisitionKind: SpellAcquisitionKind
    let effectSummary: String
    let usageNote: String

    var acquisitionLabel: String {
        switch acquisitionKind {
        case .automatic: "\(acquisitionFloor)층 학습 완료 시 자동 획득"
        case .choice: "\(acquisitionFloor)층 관리자 보상 · 두루마리 3종 중 1종 선택"
        case .fixedLesson: "\(acquisitionFloor)층 학습용 두루마리 · 시험 각인 후 자동 획득"
        }
    }
}

extension SpellCatalog {
    static func metadata(for id: SpellID) -> SpellMetadata {
        switch id {
        case .afterglowErasure:
            SpellMetadata(
                acquisitionFloor: 10, acquisitionKind: .automatic,
                effectSummary: "적에게 18~25 피해를 줍니다.",
                usageNote: "짧은 1획의 기본 공격입니다. 방어·해제 뒤에 연결하기 좋습니다."
            )
        case .riftSeverance:
            SpellMetadata(
                acquisitionFloor: 10, acquisitionKind: .automatic,
                effectSummary: "적에게 28~40 피해를 줍니다.",
                usageNote: "잔광 말소보다 길고 정밀한 1획 문양입니다."
            )
        case .barrierPiercing:
            SpellMetadata(
                acquisitionFloor: 9, acquisitionKind: .choice,
                effectSummary: "일반 방어막을 무시하고 34~48 피해를 준 뒤 해당 방어막을 제거합니다.",
                usageNote: "2획을 모두 사용합니다. 절대 방어막은 먼저 봉인 해제로 풀어야 합니다."
            )
        case .chainInscription:
            SpellMetadata(
                acquisitionFloor: 9, acquisitionKind: .choice,
                effectSummary: "14~20 피해를 주고, 이번 턴 다음 성공 공격의 피해를 12 높입니다.",
                usageNote: "강화는 중첩되지 않고 턴 종료 시 사라집니다. 실패한 공격은 강화를 소비하지 않습니다."
            )
        case .condensedBarrier:
            SpellMetadata(
                acquisitionFloor: 9, acquisitionKind: .choice,
                effectSummary: "일반 방어막을 28~36 얻습니다. 누적 최대치는 40입니다.",
                usageNote: "초급 방벽보다 긴 문양입니다. 남은 마나를 고려해 후속 주문을 선택하세요."
            )
        case .basicBarrier:
            SpellMetadata(
                acquisitionFloor: 8, acquisitionKind: .automatic,
                effectSummary: "일반 방어막을 20~30 얻습니다. 누적 최대치는 40입니다.",
                usageNote: "방어막은 피해를 먼저 흡수하며 전투 종료 시 사라집니다."
            )
        case .sealRelease:
            SpellMetadata(
                acquisitionFloor: 8, acquisitionKind: .automatic,
                effectSummary: "적의 절대 방어막을 1~2회 제거합니다.",
                usageNote: "보스방의 봉인도 같은 문양으로 해제합니다. 일반 버프·약화·예약 피해에는 적용되지 않습니다."
            )
        case .purificationGlyph:
            SpellMetadata(
                acquisitionFloor: 8, acquisitionKind: .choice,
                effectSummary: "자신의 약화·카드 봉인 또는 적의 해제 가능한 버프 중 하나를 골라 제거합니다.",
                usageNote: "한 번에 한 대상만 해제합니다. 방어막·이미 등록된 예약 피해·단계 전환은 대상이 아닙니다."
            )
        case .lingeringBarrier:
            SpellMetadata(
                acquisitionFloor: 8, acquisitionKind: .choice,
                effectSummary: "방어막 14~20을 얻고 다음 턴 시작에 방어막 10을 추가로 얻습니다.",
                usageNote: "다음 턴 추가분은 중첩되지 않습니다. 일반 방어막의 누적 최대치는 40입니다."
            )
        case .focusedRupture:
            SpellMetadata(
                acquisitionFloor: 8, acquisitionKind: .choice,
                effectSummary: "적에게 62~82 피해를 줍니다.",
                usageNote: "2획과 긴 경로를 쓰는 집중 공격입니다. 일반 방어막을 관통하지 않습니다."
            )
        case .axisSeverance:
            SpellMetadata(
                acquisitionFloor: 7, acquisitionKind: .choice,
                effectSummary: "28~40 피해를 줍니다. 적에게 일반 방어막이나 해제 가능한 버프가 있으면 피해가 12 증가합니다.",
                usageNote: "추가 피해는 한 번만 적용하며 버프 자체는 제거하지 않습니다. 절대 방어막에는 막힙니다."
            )
        case .anchorGuard:
            SpellMetadata(
                acquisitionFloor: 7, acquisitionKind: .choice,
                effectSummary: "방어막 18~26을 얻고 이번 적 행동 단계의 다음 피해 한 건을 6 줄입니다.",
                usageNote: "피해 감소는 중첩되지 않으며 이번 적 행동 단계가 끝나면 사라집니다."
            )
        case .consequenceErasure:
            SpellMetadata(
                acquisitionFloor: 7, acquisitionKind: .choice,
                effectSummary: "등록된 예약 피해 한 건을 취소하거나 적의 일반 방어막 하나를 제거합니다.",
                usageNote: "2획을 사용하며 두 효과 중 하나만 적용합니다. 아직 등록되지 않은 공격과 절대 방어막은 지울 수 없습니다."
            )
        case .outputReduction:
            SpellMetadata(
                acquisitionFloor: 6, acquisitionKind: .fixedLesson,
                effectSummary: "적이 다음에 가하는 피해 한 건을 25% 줄입니다.",
                usageNote: "이번을 포함한 적 행동 단계 2회 동안 유지됩니다. 작은 공격에 먼저 소모될 수 있으며 중첩되지 않습니다."
            )
        case .executionDelay:
            SpellMetadata(
                acquisitionFloor: 6, acquisitionKind: .choice,
                effectSummary: "선택한 예약 피해 한 건의 집행을 한 턴 미룹니다.",
                usageNote: "같은 예약에는 한 번만 사용할 수 있습니다. 다른 예약과 겹칠 수 있으며 피해량은 줄지 않습니다."
            )
        case .advanceVerdict:
            SpellMetadata(
                acquisitionFloor: 6, acquisitionKind: .choice,
                effectSummary: "26~36 피해를 줍니다. 이번 적 행동 단계에 도착할 예약 피해가 있으면 피해가 12 증가합니다.",
                usageNote: "시전 시 남아 있는 예약을 확인합니다. 먼저 취소하거나 미룬 예약은 추가 피해 조건에서 제외됩니다."
            )
        case .causalCushion:
            SpellMetadata(
                acquisitionFloor: 6, acquisitionKind: .choice,
                effectSummary: "방어막 16~24를 얻고 이번 적 행동 단계의 첫 예약 피해를 30% 줄입니다.",
                usageNote: "추가 감소는 일반 즉시 공격에 적용되지 않으며 이번 적 행동 단계가 끝나면 사라집니다."
            )
        case .memorySeverance:
            SpellMetadata(
                acquisitionFloor: 5, acquisitionKind: .choice,
                effectSummary: "28~38 피해를 줍니다. 직전 성공 주문과 다른 주문이면 피해가 10 증가합니다.",
                usageNote: "전투의 첫 성공 주문에는 보너스가 없습니다. 방어·해제·디버프 뒤에도 연결할 수 있습니다."
            )
        case .memorySuture:
            SpellMetadata(
                acquisitionFloor: 5, acquisitionKind: .choice,
                effectSummary: "HP를 8 회복하고 방어막 12~18을 얻습니다.",
                usageNote: "전투당 성공 사용 2회입니다. 실패는 사용 제한을 소비하지 않으며 HP·방어막 최대치를 넘지 않습니다."
            )
        case .mimicProhibition:
            SpellMetadata(
                acquisitionFloor: 5, acquisitionKind: .choice,
                effectSummary: "현재 모사·반격 준비를 제거하고 적 행동 단계 2회 동안 모사·반격을 차단합니다.",
                usageNote: "성공 시 HP 6을 소모하며 HP 6 이하에서는 사용할 수 없습니다. 일반 공격·예약 피해·카드 봉인은 막지 않습니다."
            )
        }
    }
}
