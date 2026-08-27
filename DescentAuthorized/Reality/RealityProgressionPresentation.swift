import Foundation
import RealityKit

enum RealityDescentPresentationState: Equatable, Sendable {
    case inactive
    case ready
    case drawing
    case failed
    case approved
    case open
}

enum RealityDescentTransitionTiming {
    // The authored scenes describe a 30 fps, 68 frame opening sequence and
    // switch to the fully open model at frame 56.
    static let authoredFrameRate: Double = 30
    static let openStateFrame: Double = 56
    static let interfaceFadeDuration: TimeInterval = 0.28

    static var doorOpeningAnimationDuration: TimeInterval {
        openStateFrame / authoredFrameRate
    }

    static func doorOpeningDelay(reducedMotion: Bool) -> Duration {
        .milliseconds(reducedMotion ? 280 : 1_867)
    }

    static let openStateHold: Duration = .milliseconds(2_400)
}

enum RealityRewardPresentationState: Equatable, Sendable {
    case inactive
    case appearing
    case choosing
    case resolving(selectedIndex: Int)
    case resolved(selectedIndex: Int)
}

enum RealityRewardTransitionTiming {
    // Both reward scenes describe a 30 fps, 66 frame emergence sequence.
    static let authoredFrameRate: Double = 30
    static let appearanceEndFrame: Double = 66
    static let interfaceFadeDuration: TimeInterval = 0.36
    static let scrollBaseDuration: TimeInterval = 1.72
    static let scrollStagger: TimeInterval = 0.18

    static var appearanceDuration: TimeInterval {
        appearanceEndFrame / authoredFrameRate
    }

    static func appearanceDelay(reducedMotion: Bool) -> Duration {
        .milliseconds(reducedMotion ? 20 : Int64(appearanceDuration * 1_000))
    }

    static func scrollDuration(at index: Int, reducedMotion: Bool) -> TimeInterval {
        reducedMotion ? 0.01 : scrollBaseDuration + Double(index) * scrollStagger
    }
}

@MainActor
final class RealityProgressionVFXRenderer {
    private var baseTransforms: [RealityEntityRole: Transform] = [:]
    private var doorControllerBaseTransforms: [String: Transform] = [:]
    private var transitionGeneration = 0
    private var rewardIdleTask: Task<Void, Never>?

    func attach(to registry: RealityEntityRegistry) {
        baseTransforms.removeAll()
        doorControllerBaseTransforms.removeAll()
        for role in controlledRoles {
            if let entity = registry.entity(for: role) {
                baseTransforms[role] = entity.transform
            }
        }
        if let doorAnimation = registry.descriptor?.descentDoorAnimation {
            for name in doorAnimation.controllerNames {
                if let entity = registry.entity(named: name) {
                    doorControllerBaseTransforms[name] = entity.transform
                }
            }
        }
    }

    func presentDescent(
        _ state: RealityDescentPresentationState,
        registry: RealityEntityRegistry,
        reducedMotion: Bool
    ) {
        guard registry.root != nil else { return }
        transitionGeneration += 1
        let generation = transitionGeneration

        registry.setEnabled(state != .inactive, for: .descentStele)
        registry.setEnabled(state != .inactive, for: .descentPedestal)
        registry.setDoorOpen(state == .open)

        if state != .approved, state != .open {
            restoreDoorControllers(in: registry)
        }

        restore(.descentStele, in: registry)
        restore(.descentPedestal, in: registry)

        guard !reducedMotion else { return }
        switch state {
        case .drawing:
            pulse(.descentPedestal, scale: 1.025, duration: 0.18, registry: registry)
        case .failed:
            shake(.descentPedestal, registry: registry, generation: generation)
        case .approved:
            pulse(.descentPedestal, scale: 1.07, duration: 0.28, registry: registry)
            pulse(.descentStele, scale: 1.025, duration: 0.28, registry: registry)
            animateDoorOpening(in: registry)
        case .inactive, .ready, .open:
            break
        }
    }

    func presentReward(
        _ state: RealityRewardPresentationState,
        registry: RealityEntityRegistry,
        reducedMotion: Bool
    ) {
        guard registry.root != nil else { return }
        rewardIdleTask?.cancel()
        rewardIdleTask = nil
        transitionGeneration += 1
        let generation = transitionGeneration
        let roles = rewardRoles

        restore(.rewardStand, in: registry)
        registry.setEnabled(state != .inactive, for: .rewardStand)
        for role in roles {
            restore(role, in: registry)
            registry.setEnabled(state != .inactive, for: role)
        }

        switch state {
        case .inactive:
            return
        case .appearing:
            animateRewardStandAppearance(in: registry, reducedMotion: reducedMotion)
            for (index, role) in roles.enumerated() {
                guard let entity = registry.entity(for: role), let base = baseTransforms[role] else { continue }
                var hidden = base
                hidden.translation.y -= reducedMotion ? 0 : 0.44
                hidden.scale *= reducedMotion ? 1 : 0.68
                entity.transform = hidden
                entity.move(
                    to: base,
                    relativeTo: entity.parent,
                    duration: RealityRewardTransitionTiming.scrollDuration(
                        at: index,
                        reducedMotion: reducedMotion
                    ),
                    timingFunction: .easeOut
                )
            }
        case .choosing:
            startRewardIdleMotion(in: registry, generation: generation, reducedMotion: reducedMotion)
        case let .resolving(selectedIndex), let .resolved(selectedIndex):
            for (index, role) in roles.enumerated() {
                guard let entity = registry.entity(for: role), let base = baseTransforms[role] else { continue }
                var destination = base
                if index == selectedIndex {
                    destination.translation.y += reducedMotion ? 0 : 0.14
                    destination.scale *= reducedMotion ? 1 : 1.08
                } else {
                    destination.translation.y -= reducedMotion ? 0 : 0.22
                    destination.scale = SIMD3(repeating: reducedMotion ? 0.01 : 0.04)
                }
                entity.move(
                    to: destination,
                    relativeTo: entity.parent,
                    duration: reducedMotion ? 0.01 : 0.42,
                    timingFunction: .easeInOut
                )
            }

            if case .resolved = state {
                disableDiscardedRewards(
                    selectedIndex: selectedIndex,
                    registry: registry,
                    generation: generation,
                    delay: reducedMotion ? 0 : 0.42
                )
            }
        }
    }

    func reset() {
        rewardIdleTask?.cancel()
        rewardIdleTask = nil
        transitionGeneration += 1
        baseTransforms.removeAll()
        doorControllerBaseTransforms.removeAll()
    }

    private var controlledRoles: [RealityEntityRole] {
        [.descentStele, .descentPedestal, .rewardStand] + rewardRoles
    }

    private var rewardRoles: [RealityEntityRole] {
        [.rewardScrollLeft, .rewardScrollCenter, .rewardScrollRight]
    }

    private func restore(_ role: RealityEntityRole, in registry: RealityEntityRegistry) {
        guard let entity = registry.entity(for: role), let transform = baseTransforms[role] else { return }
        entity.stopAllAnimations(recursive: false)
        entity.transform = transform
    }

    private func restoreDoorControllers(in registry: RealityEntityRegistry) {
        for (name, transform) in doorControllerBaseTransforms {
            guard let entity = registry.entity(named: name) else { continue }
            entity.stopAllAnimations(recursive: false)
            entity.transform = transform
        }
    }

    private func animateDoorOpening(in registry: RealityEntityRegistry) {
        guard let descriptor = registry.descriptor?.descentDoorAnimation else { return }
        restoreDoorControllers(in: registry)

        moveDoorController(
            named: descriptor.leftPanelName,
            translationX: -descriptor.panelTravelDistance,
            registry: registry
        )
        moveDoorController(
            named: descriptor.rightPanelName,
            translationX: descriptor.panelTravelDistance,
            registry: registry
        )

        if let entity = registry.entity(named: descriptor.lockCoreName),
           var target = doorControllerBaseTransforms[descriptor.lockCoreName] {
            target.scale *= 0.12
            target.translation.z += 0.08
            target.rotation *= simd_quatf(angle: .pi * 0.75, axis: SIMD3(0, 0, 1))
            entity.move(
                to: target,
                relativeTo: entity.parent,
                duration: RealityDescentTransitionTiming.doorOpeningAnimationDuration,
                timingFunction: .easeInOut
            )
        }

        if let entity = registry.entity(named: descriptor.logoLightName),
           var target = doorControllerBaseTransforms[descriptor.logoLightName] {
            target.scale *= 1.16
            entity.move(
                to: target,
                relativeTo: entity.parent,
                duration: RealityDescentTransitionTiming.doorOpeningAnimationDuration,
                timingFunction: .easeInOut
            )
        }
    }

    private func moveDoorController(
        named name: String,
        translationX: Float,
        registry: RealityEntityRegistry
    ) {
        guard let entity = registry.entity(named: name),
              var target = doorControllerBaseTransforms[name] else { return }
        target.translation.x += translationX
        entity.move(
            to: target,
            relativeTo: entity.parent,
            duration: RealityDescentTransitionTiming.doorOpeningAnimationDuration,
            timingFunction: .easeInOut
        )
    }

    private func animateRewardStandAppearance(
        in registry: RealityEntityRegistry,
        reducedMotion: Bool
    ) {
        guard let entity = registry.entity(for: .rewardStand),
              let base = baseTransforms[.rewardStand] else { return }
        var hidden = base
        hidden.translation.y -= reducedMotion ? 0 : 0.1
        hidden.scale *= reducedMotion ? 1 : 0.97
        entity.transform = hidden
        entity.move(
            to: base,
            relativeTo: entity.parent,
            duration: reducedMotion ? 0.01 : 0.62,
            timingFunction: .easeOut
        )
    }

    private func startRewardIdleMotion(
        in registry: RealityEntityRegistry,
        generation: Int,
        reducedMotion: Bool
    ) {
        guard !reducedMotion else { return }
        let roles = rewardRoles
        rewardIdleTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var isRaised = true
            while !Task.isCancelled, self.transitionGeneration == generation {
                for (index, role) in roles.enumerated() {
                    guard let entity = registry.entity(for: role),
                          var target = self.baseTransforms[role] else { continue }
                    target.translation.y += isRaised
                        ? 0.018 + Float(index) * 0.004
                        : -0.006
                    entity.move(
                        to: target,
                        relativeTo: entity.parent,
                        duration: 1.25,
                        timingFunction: .easeInOut
                    )
                }
                do {
                    try await Task.sleep(for: .milliseconds(1_250))
                } catch {
                    return
                }
                isRaised.toggle()
            }
        }
    }

    private func pulse(
        _ role: RealityEntityRole,
        scale: Float,
        duration: TimeInterval,
        registry: RealityEntityRegistry
    ) {
        guard let entity = registry.entity(for: role), var target = baseTransforms[role] else { return }
        target.scale *= scale
        entity.move(to: target, relativeTo: entity.parent, duration: duration, timingFunction: .easeInOut)
    }

    private func shake(
        _ role: RealityEntityRole,
        registry: RealityEntityRegistry,
        generation: Int
    ) {
        guard let entity = registry.entity(for: role), let base = baseTransforms[role] else { return }
        var offset = base
        offset.translation.x += 0.035
        entity.move(to: offset, relativeTo: entity.parent, duration: 0.08, timingFunction: .easeInOut)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { [weak self, weak entity] in
            guard let self, self.transitionGeneration == generation, let entity else { return }
            var opposite = base
            opposite.translation.x -= 0.035
            entity.move(to: opposite, relativeTo: entity.parent, duration: 0.1, timingFunction: .easeInOut)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) { [weak self, weak entity] in
                guard let self, self.transitionGeneration == generation, let entity else { return }
                entity.move(to: base, relativeTo: entity.parent, duration: 0.1, timingFunction: .easeOut)
            }
        }
    }

    private func disableDiscardedRewards(
        selectedIndex: Int,
        registry: RealityEntityRegistry,
        generation: Int,
        delay: TimeInterval
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak registry] in
            guard let self, self.transitionGeneration == generation, let registry else { return }
            for (index, role) in self.rewardRoles.enumerated() where index != selectedIndex {
                registry.setEnabled(false, for: role)
            }
        }
    }
}
