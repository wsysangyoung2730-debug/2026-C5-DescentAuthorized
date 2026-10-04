import Foundation
import RealityKit

/// Room-scoped decoded templates. Every display receives a clone, so fading one
/// reservation or projectile cannot mutate another instance or the cached source.
@MainActor
final class RealityCombatEffectLibrary {
    private var templates: [String: Entity] = [:]
    private(set) var floor = 9
    private(set) var observationResidual = false

    static let reused: [String: (String, String)] = [
        "glass": ("HitShield", "hit_shield"),
        "record": ("IntentMemoryRecord", "intent_memory_record"),
        "amplify": ("IntentAmplify", "intent_amplify"),
        "reservation": ("IntentDamageReservation", "intent_damage_reservation"),
        "execution": ("IntentScheduledExecution", "intent_scheduled_execution"),
        "seal": ("IntentSpellSeal", "intent_spell_seal")
    ]
    static func floor(for descriptor: RealitySceneDescriptor) -> Int {
        FinalSceneContract.contract(for: descriptor.sceneID)?.floor
            ?? (descriptor.sceneID.rawValue.contains("08") ? 8 : 9)
    }
    static func resources(for descriptor: RealitySceneDescriptor, bundle: Bundle) -> [String: URL] {
        guard descriptor.actor != nil else { return [:] }
        var result: [String: URL] = [:]
        for id in CombatEffectCatalog.required(floor: floor(for: descriptor)) {
            result[id.rawValue] = bundle.url(forResource: "effect", withExtension: "usdc",
                subdirectory: "Reality/VFX/Authored/\(id.rawValue)")
        }
        for (id, resource) in reused {
            result[id] = bundle.url(forResource: resource.1, withExtension: "usdc",
                subdirectory: "Reality/VFX/Combat/\(resource.0)")
        }
        return result
    }
    func install(descriptor: RealitySceneDescriptor, resources: [URL: Entity], bundle: Bundle) {
        templates.removeAll()
        floor = Self.floor(for: descriptor)
        observationResidual = descriptor.actor?.assetID == .observationResidue
        for (id, url) in Self.resources(for: descriptor, bundle: bundle) {
            if let source = resources[url] { templates[id] = source }
        }
    }
    func reset() { templates.removeAll() }
    func make(_ id: CombatEffectID, size: Float) -> Entity? { make(id.rawValue, size: size) }
    func make(_ id: String, size: Float) -> Entity? {
        guard let source = templates[id] else { return nil }
        let payload = source.clone(recursive: true)
        // USD import wrappers use centimeters. Geometry below is already meters/Z-up.
        payload.transform = .identity
        let bounds = payload.visualBounds(relativeTo: payload)
        let longest = max(bounds.extents.x, max(bounds.extents.y, bounds.extents.z))
        guard longest.isFinite, longest > 0.00001 else { return nil }
        payload.position = -bounds.center
        let normalized = Entity(); normalized.addChild(payload)
        normalized.scale = SIMD3(repeating: size / longest)
        let container = Entity(); container.name = "DA_EFFECT_" + id
        container.addChild(normalized)
        return container
    }
    /// Direction of the authored tip in the normalized Z-up model.
    static func forward(_ id: CombatEffectID) -> SIMD3<Float> {
        switch id {
        case .recordLance: [-1, 0, 0.78]
        case .riftRay: [1, 0, -0.52]
        case .coordinateWedge: [1, 0, -0.75]
        case .causalityBolt: [1, 0, -0.54]
        case .sealEnergyCore: [0.89, 0, -1]
        case .isolationRing: [0, 0, 1]
        default: [0, -1, 0]
        }
    }
}
