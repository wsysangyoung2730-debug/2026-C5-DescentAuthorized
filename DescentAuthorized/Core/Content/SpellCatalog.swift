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
        effect: .damage(base: 18, piercesNormalBarrier: false),
        glyph: GlyphDefinition(
            difficulty: .easy,
            strokes: [
                stroke(
                    points: [(20, 55), (37, 72), (67, 28), (78, 43), (66, 51)],
                    requiredNodeIndices: [1, 2],
                    optionalNodeIndices: [3],
                    nodeRadius: 6,
                    pathRadius: 7,
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
        effect: .damage(base: 28, piercesNormalBarrier: false),
        glyph: GlyphDefinition(
            difficulty: .normal,
            strokes: [
                stroke(
                    points: [(18, 68), (39, 25), (34, 56), (68, 35), (55, 75), (82, 58), (72, 48)],
                    requiredNodeIndices: [1, 2, 3, 4, 5],
                    nodeRadius: 5,
                    pathRadius: 5.5
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
        effect: .damage(base: 34, piercesNormalBarrier: true),
        glyph: GlyphDefinition(
            difficulty: .hard,
            strokes: [
                stroke(
                    points: [(24, 70), (17, 43), (35, 22), (59, 26), (82, 45), (76, 69)],
                    requiredNodeIndices: [1, 2, 3, 4],
                    nodeRadius: 4,
                    pathRadius: 4.5
                ),
                stroke(
                    points: [(37, 82), (50, 52), (62, 34), (73, 18)],
                    requiredNodeIndices: [1, 2],
                    nodeRadius: 4,
                    pathRadius: 4.5
                )
            ],
            crossings: [
                GlyphCrossingRequirement(
                    firstStrokeIndex: 0,
                    secondStrokeIndex: 1,
                    center: point(62, 34),
                    radius: 6
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
        effect: .fixedBarrier(amount: 20, maxStack: 40),
        glyph: GlyphDefinition(
            difficulty: .easy,
            strokes: [
                stroke(
                    points: [(22, 68), (25, 42), (43, 24), (62, 28), (78, 50), (69, 72), (50, 78)],
                    requiredNodeIndices: [2, 4],
                    optionalNodeIndices: [1, 3, 5],
                    nodeRadius: 6,
                    pathRadius: 7
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
        effect: .dispelAbsoluteBarrier(charges: 1),
        glyph: GlyphDefinition(
            difficulty: .normal,
            strokes: [
                stroke(
                    points: [(25, 72), (42, 57), (51, 48), (70, 27), (62, 55), (81, 68)],
                    requiredNodeIndices: [1, 2, 3, 4],
                    nodeRadius: 5,
                    pathRadius: 5.5
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
