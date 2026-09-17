import Combine
import RealityKit
import UIKit

/// One bounded animation clock for the observatory's existing decorative props.
/// Entries use the room's authored Z-up local space; the room root handles Y-up.
@MainActor
final class ObservatoryAmbientMotion {
    private struct Entry {
        let entity: Entity
        let rest: Transform
        let isSensor: Bool
        let phase: Float
        let frequency: Float
        let amplitude: Float
    }

    private var entries: [Entry] = []
    private var timer: AnyCancellable?
    private weak var view: ARView?
    private var elapsed: Float = 0
    private var lastTick: TimeInterval = 0

    func install(in root: Entity, view: ARView) {
        reset()
        self.view = view
        let sensorNames = (0..<4).map { "SensorPod_\($0)" } + ["F08B_SensorPod_Upper"]
        for (index, name) in sensorNames.enumerated() {
            guard let sensor = root.findEntity(named: name) else { continue }
            addGroup(name: "F08B_AmbientSensor_\(index)", parts: [sensor], root: root,
                     isSensor: true, index: index)
        }
        for index in 0..<13 {
            let name = String(format: "F08B_FloatingGlassShard_%02d", index)
            guard let glass = root.findEntity(named: name) else { continue }
            // Each exported triangular shard has three independently exported edges.
            let edges = (index * 3..<index * 3 + 3).compactMap { edge -> Entity? in
                let name = edge == 0 ? "F08B_Shard_ThinEdge"
                    : String(format: "F08B_Shard_ThinEdge_%03d", edge)
                return root.findEntity(named: name)
            }
            addGroup(name: "F08B_AmbientShard_\(index)", parts: [glass] + edges,
                     root: root, isSensor: false, index: index)
        }
    }

    private func addGroup(name: String, parts: [Entity], root: Entity, isSensor: Bool, index: Int) {
        let group = Entity()
        group.name = name
        group.position = parts[0].visualBounds(relativeTo: root).center
        root.addChild(group)
        for part in parts { part.setParent(group, preservingWorldTransform: true) }
        entries.append(Entry(entity: group, rest: group.transform, isSensor: isSensor,
            phase: Float(index) * 2.399963 + (isSensor ? 0.7 : 1.9),
            frequency: 2 * .pi / (isSensor ? 7.2 + Float(index) * 0.83 : 5.3 + Float((index * 7) % 11) * 0.51),
            amplitude: isSensor ? 0.12 : 0.07 + Float((index * 3) % 7) * 0.015))
    }

    func setReducedMotion(_ reduced: Bool) {
        if reduced {
            timer?.cancel()
            timer = nil
            elapsed = 0
            for entry in entries { entry.entity.transform = entry.rest }
            return
        }
        guard timer == nil, !entries.isEmpty else { return }
        lastTick = ProcessInfo.processInfo.systemUptime
        timer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let delta = Float(min(max(now - lastTick, 0), 0.05))
        lastTick = now
        guard UIApplication.shared.applicationState == .active, view?.window != nil else { return }
        elapsed += delta
        let fade = min(elapsed / 2, 1)
        // Always evaluate from rest: no drift, random jumps, physics, or mesh updates.
        for entry in entries {
            var transform = entry.rest
            let wave = elapsed * entry.frequency + entry.phase
            transform.translation.z += entry.amplitude * sin(wave) * fade
            if entry.isSensor {
                transform.translation.x += 0.18 * sin(elapsed * 0.43 + entry.phase) * fade
                transform.translation.y += 0.12 * sin(elapsed * 0.31 + entry.phase * 1.7) * fade
                let yaw = simd_quatf(angle: 0.085 * sin(wave * 0.67) * fade, axis: [0, 0, 1])
                let tilt = simd_quatf(angle: 0.025 * sin(wave * 0.89) * fade, axis: [1, 0, 0])
                transform.rotation = entry.rest.rotation * yaw * tilt
            }
            entry.entity.transform = transform
        }
    }

    func reset() {
        timer?.cancel()
        timer = nil
        for entry in entries { entry.entity.transform = entry.rest }
        entries.removeAll()
        view = nil
        elapsed = 0
    }
}

#if DEBUG
extension ObservatoryAmbientMotion {
    var diagnosticSnapshot: [String: Any] {
        ["clockActive": timer != nil, "elapsed": elapsed, "entries": entries.map { entry in
            ["name": entry.entity.name, "sensor": entry.isSensor,
             "position": [entry.entity.position.x, entry.entity.position.y, entry.entity.position.z],
             "rest": [entry.rest.translation.x, entry.rest.translation.y, entry.rest.translation.z],
             "rotation": [entry.entity.orientation.vector.x, entry.entity.orientation.vector.y,
                          entry.entity.orientation.vector.z, entry.entity.orientation.vector.w],
             "children": entry.entity.children.map { child in
                 ["name": child.name, "matrix": (0..<4).flatMap { c in
                     (0..<4).map { r in child.transform.matrix[c][r] }
                 }] as [String: Any]
             }] as [String: Any]
        }]
    }
}
#endif
