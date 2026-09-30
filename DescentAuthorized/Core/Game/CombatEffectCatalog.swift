import Foundation

/// Authored bodies are separate from the existing overhead intent vocabulary.
enum CombatEffectID: String, CaseIterable, Sendable {
    case recordLance = "01-record-lance", focusLens = "02-focus-lens", riftRay = "03-rift-ray"
    case coordinateWedge = "04-coordinate-wedge", axisAnchors = "05-axis-anchors"
    case causalityBolt = "06-causality-bolt", memoryCompression = "07-memory-compression"
    case signatureStroke = "08-signature-stroke", verdictStamp = "09-verdict-stamp"
    case isolationRing = "10-isolation-ring", sealEnergyCore = "11-seal-energy-core"
    case identityScanner = "12-identity-scanner", suppressionBand = "13-suppression-band"
    case preservationBand = "14-preservation-band", documentBarrier = "15-document-barrier"
    case observationBarrier = "16-observation-barrier", correctionBarrier = "17-correction-barrier"
    case generalBarrier = "18-general-barrier"
}

struct CombatEffectCatalog {
    static func projectile(floor: Int, action: EnemyAction, executionOnly: Bool = false) -> CombatEffectID {
        switch floor {
        case 9: .recordLance
        case 8: .riftRay
        case 7: .coordinateWedge
        case 6: .causalityBolt
        case 5: .memoryCompression
        case 4, 1: isVerdict(action) || executionOnly ? .verdictStamp : .signatureStroke
        case 3: .isolationRing
        default: .sealEnergyCore
        }
    }

    static func barrier(floor: Int, absolute: Bool) -> CombatEffectID {
        if absolute { return .observationBarrier }
        switch floor {
        case 9: return .documentBarrier
        case 7: return .correctionBarrier
        default: return .generalBarrier
        }
    }

    static func required(floor: Int) -> Set<CombatEffectID> {
        var result: Set<CombatEffectID> = [.generalBarrier, .observationBarrier, .suppressionBand]
        switch floor {
        case 9: result.formUnion([.recordLance, .documentBarrier])
        case 8: result.formUnion([.focusLens, .riftRay])
        case 7: result.formUnion([.coordinateWedge, .axisAnchors, .correctionBarrier])
        case 6: result.insert(.causalityBolt)
        case 5: result.formUnion([.memoryCompression, .preservationBand])
        case 4: result.formUnion([.signatureStroke, .verdictStamp])
        case 3: result.insert(.isolationRing)
        case 2: result.formUnion([.sealEnergyCore, .verdictStamp])
        case 1: result.formUnion([.signatureStroke, .verdictStamp, .identityScanner])
        default: break
        }
        return result
    }

    static func isVerdict(_ action: EnemyAction) -> Bool {
        guard case let .expansion(_, expanded) = action else { return false }
        func contains(_ value: ExpansionEnemyAction) -> Bool {
            switch value {
            case .counterExecute: return true
            case let .sequence(actions): return actions.contains(where: contains)
            default: return false
            }
        }
        return contains(expanded)
    }
}
