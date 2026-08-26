import Foundation

enum SpellCatalog {
    static let all: [SpellID: SpellDefinition] = [
        .afterglowErasure: afterglowErasure,
        .riftSeverance: riftSeverance,
        .barrierPiercing: barrierPiercing,
        .basicBarrier: basicBarrier,
        .sealRelease: sealRelease
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
                        (24, 72), (30, 63), (37, 54),
                        (36, 43), (37, 30), (40, 18),
                        (44, 10), (51, 6), (57, 8),
                        (59, 14), (57, 25), (54, 37),
                        (50, 47), (44, 56), (32, 58),
                        (43, 69), (49, 74), (56, 78),
                        (62, 79), (69, 77), (76, 72)
                    ],
                    requiredNodeIndices: [2, 7, 13, 18],
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
