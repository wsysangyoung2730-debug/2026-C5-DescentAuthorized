import Foundation

enum DescentDoorGlyphCatalog {
    static let all: [DescentDoorGlyphID: DescentDoorGlyphDefinition] = [
        .floor10: floor10,
        .floor9: floor9,
        .floor8: floor8
    ]

    static func glyph(_ id: DescentDoorGlyphID) -> DescentDoorGlyphDefinition {
        guard let definition = all[id] else {
            preconditionFailure("Missing descent door glyph: \(id.rawValue)")
        }
        return definition
    }

    static let floor10 = DescentDoorGlyphDefinition(
        id: .floor10,
        name: "제10층 하강 승인",
        recommendedMana: 24,
        glyph: GlyphDefinition(
            difficulty: .easy,
            strokes: [
                stroke(
                    points: [(28, 32), (50, 20), (72, 32), (63, 58), (50, 78), (37, 58), (28, 32)],
                    requiredNodeIndices: [1, 2, 3, 4, 5],
                    nodeRadius: 6,
                    pathRadius: 7
                )
            ],
            crossings: []
        )
    )

    static let floor9 = DescentDoorGlyphDefinition(
        id: .floor9,
        name: "제9층 하강 승인",
        recommendedMana: 46,
        glyph: GlyphDefinition(
            difficulty: .normal,
            strokes: [
                stroke(
                    points: [(22, 68), (36, 28), (54, 52), (76, 24), (68, 70)],
                    requiredNodeIndices: [1, 2, 3],
                    nodeRadius: 5,
                    pathRadius: 5.5
                )
            ],
            crossings: []
        )
    )

    static let floor8 = DescentDoorGlyphDefinition(
        id: .floor8,
        name: "제8층 하강 승인",
        recommendedMana: 68,
        glyph: GlyphDefinition(
            difficulty: .hard,
            strokes: [
                stroke(
                    points: [(20, 65), (34, 28), (52, 47), (73, 22), (80, 62)],
                    requiredNodeIndices: [1, 2, 3],
                    nodeRadius: 4.5,
                    pathRadius: 5
                ),
                stroke(
                    points: [(30, 76), (50, 47), (70, 76)],
                    requiredNodeIndices: [1],
                    nodeRadius: 4.5,
                    pathRadius: 5
                )
            ],
            crossings: [
                GlyphCrossingRequirement(
                    firstStrokeIndex: 0,
                    secondStrokeIndex: 1,
                    center: point(50, 47),
                    radius: 6
                )
            ]
        )
    )

    private static func stroke(
        points values: [(Double, Double)],
        requiredNodeIndices: [Int],
        nodeRadius: Double,
        pathRadius: Double
    ) -> GlyphStrokeSpec {
        let points = values.map(point)
        return GlyphStrokeSpec(
            start: points[0],
            end: points[points.count - 1],
            requiredNodes: requiredNodeIndices.map { points[$0] },
            referencePath: points,
            nodeRadius: nodeRadius,
            pathRadius: pathRadius
        )
    }

    private static func point(_ x: Double, _ y: Double) -> NormalizedPoint {
        NormalizedPoint(x: x, y: y)
    }
}
