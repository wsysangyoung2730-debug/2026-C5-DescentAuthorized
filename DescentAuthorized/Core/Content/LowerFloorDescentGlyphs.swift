import Foundation

extension DescentDoorGlyphCatalog {
    /// Each definition is an independent submission, demonstration and durable approval.
    static func lowerFloorApprovals(floor: Int) -> [DescentDoorGlyphDefinition] {
        let entries: [(String, [[(Double, Double)]])] = switch floor {
        case 4: [
            ("서명 대조", [[(22, 72), (36, 28), (50, 48), (64, 28), (78, 72)]]),
            ("책임 인계", [[(22, 35), (50, 60), (78, 35)], [(50, 20), (50, 82)]]),
            ("집행 승인", [[(25, 25), (25, 72), (50, 82), (75, 72), (75, 25)], [(32, 60), (68, 60)]])]
        case 3: [
            ("대상 확인", [[(30, 75), (22, 25), (78, 25), (70, 75)]]),
            ("격리 동의", [[(25, 25), (50, 52), (75, 25)], [(50, 52), (50, 80)]]),
            ("잠금 인계", [[(25, 30), (75, 30), (75, 75), (25, 75), (25, 30)], [(50, 18), (50, 60)]])]
        case 2: [
            ("분산 연결", [[(20, 30), (50, 52), (80, 30)], [(50, 52), (50, 80)]]),
            ("기준 고정", [[(50, 20), (75, 50), (50, 80), (25, 50), (50, 20)]]),
            ("유지 인계", [[(20, 70), (50, 28), (80, 70)], [(20, 70), (50, 55), (80, 70)]])]
        case 1: [
            ("신원 승인", [[(28, 32), (50, 20), (72, 32), (63, 58), (50, 78), (37, 58), (28, 32)]]),
            ("출구 승인", [[(25, 76), (25, 26), (75, 26), (75, 76)], [(50, 75), (50, 45), (65, 60)]]),
            ("최종 인계", [[(22, 28), (50, 50), (78, 28)], [(22, 72), (50, 50), (78, 72), (22, 72)]])]
        default: []
        }
        return entries.enumerated().map { index, entry in
            DescentDoorGlyphDefinition(id: DescentDoorGlyphID(rawValue: "floor\(floor)Approval\(index + 1)")!,
                name: entry.0, recommendedMana: entry.1.count == 1 ? 45 : 70,
                glyph: GlyphDefinition(difficulty: .normal, strokes: entry.1.map { coordinates in
                    let points = coordinates.map { NormalizedPoint(x: $0.0, y: $0.1) }
                    return GlyphStrokeSpec(start: points.first!, end: points.last!,
                        requiredNodes: Array(points.dropFirst().dropLast()), referencePath: points,
                        nodeRadius: 8, pathRadius: 9)
                }, crossings: []))
        }
    }
}
