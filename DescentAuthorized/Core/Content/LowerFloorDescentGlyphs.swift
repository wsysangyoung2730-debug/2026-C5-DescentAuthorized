import Foundation

struct LowerDescentApprovalPattern {
    let title: String
    let sequence: [Int]

    /// Indices address the same ten-node plate used on 8F and 9F.
    static func patterns(floor: Int) -> [Self] {
        let entries: [(String, [Int])] = switch floor {
        case 4: [("서명 대조", [1,0,2,5,6,7]), ("책임 인계", [0,3,4,7,9,8,5]), ("집행 승인", [2,3,1,4,6,8,9])]
        case 3: [("대상 확인", [7,4,1,0,2,5,8]), ("격리 동의", [1,3,2,5,6,9]), ("잠금 인계", [0,2,5,8,6,7,4])]
        case 2: [("분산 연결", [0,1,4,6,5,2]), ("기준 고정", [3,1,4,7,9,8,5,2]), ("유지 인계", [7,6,4,1,0,2,5,8])]
        case 1: [("신원 승인", [1,0,2,3,4,7,6,8]), ("출구 승인", [7,4,1,3,2,5,8,9]), ("최종 인계", [0,3,1,4,7,6,8,5,2])]
        default: []
        }
        return entries.map { Self(title: $0.0, sequence: $0.1) }
    }

    static let nodes: [NormalizedPoint] = [
        .init(x:50,y:8), .init(x:22,y:25), .init(x:78,y:25), .init(x:50,y:33),
        .init(x:27,y:50), .init(x:73,y:50), .init(x:50,y:68), .init(x:30,y:82),
        .init(x:70,y:82), .init(x:50,y:94)
    ]
}

extension DescentDoorGlyphCatalog {
    static func lowerFloorApprovals(floor: Int) -> [DescentDoorGlyphDefinition] {
        LowerDescentApprovalPattern.patterns(floor: floor).enumerated().map { index, entry in
            let points = entry.sequence.map { LowerDescentApprovalPattern.nodes[$0] }
            return DescentDoorGlyphDefinition(id: DescentDoorGlyphID(rawValue: "floor\(floor)Approval\(index + 1)")!,
                name: entry.title, recommendedMana: 45,
                glyph: GlyphDefinition(difficulty: .normal, strokes: [
                    GlyphStrokeSpec(start: points.first!, end: points.last!,
                        requiredNodes: Array(points.dropFirst().dropLast()), referencePath: points,
                        nodeRadius: 8, pathRadius: 9)
                ], crossings: []))
        }
    }
}


extension SpellCatalog {
    /// Door-only glyphs. Combat seal-release remains the learned spell.
    static func middleDoor(floor: Int, residualTransfer: Bool = false) -> SpellDefinition {
        let coordinates: [(Double, Double)] = switch floor {
        case 7: [(20,75),(20,25),(50,25),(50,65),(80,65),(80,35)]
        case 6: [(20,25),(50,25),(50,75),(80,75),(80,45),(65,45)]
        case 5: [(20,70),(35,25),(50,60),(65,25),(80,70)]
        case 4: [(20,25),(50,45),(80,25),(80,75),(50,55),(20,75)]
        case 3: [(20,75),(20,25),(80,25),(80,75),(50,75),(50,50)]
        case 2: [(20,30),(40,30),(40,70),(60,70),(60,30),(80,30)]
        default: [(20,75),(35,45),(50,25),(65,45),(80,75),(50,65)]
        }
        let points = coordinates.map { NormalizedPoint(x: residualTransfer ? 100 - $0.0 : $0.0, y: $0.1) }
        return SpellDefinition(id: .sealRelease, name: "제\(floor)층 중앙문 승인",
            category: .dispel, tier: .worn, recommendedMana: 28,
            effect: sealRelease.effect,
            glyph: GlyphDefinition(difficulty: .normal,
                strokes: [GlyphStrokeSpec(start: points.first!, end: points.last!,
                    requiredNodes: Array(points.dropFirst().dropLast()), referencePath: points,
                    nodeRadius: 8, pathRadius: 9)], crossings: []))
    }
}
