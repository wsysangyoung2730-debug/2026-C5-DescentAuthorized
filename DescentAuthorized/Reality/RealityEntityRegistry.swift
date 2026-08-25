import RealityKit

@MainActor
final class RealityEntityRegistry {
    private(set) var root: Entity?
    private(set) var descriptor: RealitySceneDescriptor?
    private var entitiesByRole: [RealityEntityRole: Entity] = [:]

    func rebuild(root: Entity, descriptor: RealitySceneDescriptor) {
        self.root = root
        self.descriptor = descriptor
        entitiesByRole = descriptor.entityNames.reduce(into: [:]) { result, entry in
            if let entity = root.findEntity(named: entry.value) {
                result[entry.key] = entity
            }
        }
    }

    func entity(for role: RealityEntityRole) -> Entity? { entitiesByRole[role] }

    func entity(named name: String) -> Entity? { root?.findEntity(named: name) }

    func setEnabled(_ isEnabled: Bool, for role: RealityEntityRole) {
        entitiesByRole[role]?.isEnabled = isEnabled
    }

    func setDoorOpen(_ isOpen: Bool) {
        setEnabled(!isOpen, for: .descentDoor)
        setEnabled(isOpen, for: .openDescentDoor)
    }

    func reset() {
        root = nil
        descriptor = nil
        entitiesByRole.removeAll()
    }

    var missingRequiredRoles: [RealityEntityRole] {
        guard let descriptor else { return [] }
        return descriptor.entityNames.keys.filter { entitiesByRole[$0] == nil }
    }
}
