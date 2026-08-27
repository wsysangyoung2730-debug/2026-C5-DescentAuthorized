import Combine
import Foundation
import OSLog
import RealityKit
import UIKit

enum RealityShieldState: Equatable, Sendable {
    case none
    case general
    case absolute
}

enum RealityEnemyIntentCue: Equatable, Sendable {
    case attack
    case heavyAttack
    case generalShield
    case absoluteShield
}

enum RealityHitCue: Equatable, Sendable {
    case normal
    case heavy
    case critical
    case shield
}

enum RealityCombatCue: Equatable, Sendable {
    case intent(RealityEnemyIntentCue)
    case hit(RealityHitCue)
    case shield(RealityShieldState)
    case clearIntent
}

struct RealityCombatPresentationMapper {
    static func cues(
        for events: [DemoSessionEvent],
        battleState: BattleState?
    ) -> [RealityCombatCue] {
        var cues: [RealityCombatCue] = []
        var resolvedGrade: CastingGrade?

        for event in events {
            guard case let .combat(battleEvent) = event else { continue }
            switch battleEvent {
            case let .turnStarted(_, intent):
                cues.append(.intent(intentCue(for: intent)))

            case let .spellResolved(_, grade):
                resolvedGrade = grade

            case let .damageApplied(target, amount, _):
                guard case .enemy = target, amount > 0 else { continue }
                cues.append(.hit(hitCue(for: resolvedGrade)))
                resolvedGrade = nil

            case let .attackNegatedByAbsoluteBarrier(target):
                if case .enemy = target {
                    cues.append(.hit(.shield))
                }

            case let .normalBarrierChanged(target, amount):
                if case .enemy = target {
                    cues.append(.shield(amount > 0 ? .general : .none))
                }

            case let .absoluteBarrierChanged(target, charges):
                if case .enemy = target {
                    cues.append(.shield(charges > 0 ? .absolute : .none))
                }

            case .enemyActionStarted:
                cues.append(.clearIntent)

            case .victory, .defeat:
                cues.append(.clearIntent)

            default:
                break
            }
        }

        if let battleState {
            cues.append(.shield(shieldState(for: battleState)))
            if let intent = battleState.currentEnemyIntent,
               battleState.phase != .victory,
               battleState.phase != .defeat {
                cues.append(.intent(intentCue(for: intent)))
            }
        }
        return cues
    }

    static func shieldState(for battleState: BattleState) -> RealityShieldState {
        if battleState.enemy.absoluteBarrierCharges > 0 { return .absolute }
        if battleState.enemy.normalBarrier > 0 { return .general }
        return .none
    }

    static func intentCue(for action: EnemyAction) -> RealityEnemyIntentCue {
        switch action {
        case let .attack(_, _, isStrong):
            isStrong ? .heavyAttack : .attack
        case .grantNormalBarrier:
            .generalShield
        case .grantAbsoluteBarrier:
            .absoluteShield
        case let .telegraph(name, upcomingActionName):
            inferredIntentCue(from: "\(name) \(upcomingActionName)")
        }
    }

    private static func hitCue(for grade: CastingGrade?) -> RealityHitCue {
        switch grade {
        case .perfect:
            .critical
        case .precise:
            .heavy
        default:
            .normal
        }
    }

    private static func inferredIntentCue(from text: String) -> RealityEnemyIntentCue {
        if text.contains("절대") { return .absoluteShield }
        if text.contains("방어") || text.contains("방벽") { return .generalShield }
        if text.contains("강") { return .heavyAttack }
        return .attack
    }
}

@MainActor
final class RealityCombatVFXRenderer {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DescentAuthorized",
        category: "RealityCombatVFX"
    )
    private weak var root: Entity?
    private weak var enemyAnchor: Entity?
    private weak var enemyActor: Entity?
    private var currentIntentEntity: Entity?
    private var currentIntentCue: RealityEnemyIntentCue?
    private var pendingIntentCue: RealityEnemyIntentCue?
    private var loadCancellables: Set<AnyCancellable> = []
    private var intentGeneration = 0
    private var intentScale: Float = 1.15
    private var intentVerticalOffset: Float = 0.3
    private var currentShieldState: RealityShieldState = .none
    private var shieldAuraEntity: Entity?
    private var shieldTransitionTask: Task<Void, Never>?
    private var shieldTransitionGeneration = 0

    func attach(to registry: RealityEntityRegistry) {
        root = registry.root
        enemyAnchor = registry.entity(for: .enemySpawn) ?? registry.root
        enemyActor = registry.entity(for: .enemyActor)
        intentScale = registry.descriptor?.actor?.intentScale ?? 1.15
        intentVerticalOffset = registry.descriptor?.actor?.intentVerticalOffset ?? 0.3
        registry.setEnabled(true, for: .generalShield)
        registry.setEnabled(true, for: .absoluteShield)
    }

    func present(
        _ cues: [RealityCombatCue],
        registry: RealityEntityRegistry,
        reducedMotion: Bool,
        bundle: Bundle = .main
    ) {
        attach(to: registry)
        var synchronizedShieldState: RealityShieldState?
        for cue in cues {
            switch cue {
            case let .intent(intent):
                showIntent(intent, reducedMotion: reducedMotion, bundle: bundle)
            case let .hit(hit):
                showHit(hit, reducedMotion: reducedMotion, bundle: bundle)
            case let .shield(state):
                synchronizedShieldState = state
            case .clearIntent:
                clearIntent()
            }
        }
        if let synchronizedShieldState {
            applyShield(
                synchronizedShieldState,
                registry: registry,
                reducedMotion: reducedMotion
            )
        }
    }

    func reset() {
        loadCancellables.forEach { $0.cancel() }
        loadCancellables.removeAll()
        currentIntentEntity?.removeFromParent()
        currentIntentEntity = nil
        currentIntentCue = nil
        pendingIntentCue = nil
        root = nil
        enemyAnchor = nil
        enemyActor = nil
        intentScale = 1.15
        intentVerticalOffset = 0.3
        intentGeneration += 1
        shieldTransitionTask?.cancel()
        shieldTransitionTask = nil
        shieldAuraEntity?.removeFromParent()
        shieldAuraEntity = nil
        currentShieldState = .none
        shieldTransitionGeneration += 1
    }

    private func applyShield(
        _ state: RealityShieldState,
        registry: RealityEntityRegistry,
        reducedMotion: Bool
    ) {
        guard state != currentShieldState else {
            if reducedMotion {
                shieldTransitionTask?.cancel()
                shieldTransitionTask = nil
                if state == .none {
                    shieldAuraEntity?.removeFromParent()
                    shieldAuraEntity = nil
                } else {
                    shieldAuraEntity?.components.set(OpacityComponent(opacity: 1))
                }
            }
            return
        }

        shieldTransitionTask?.cancel()
        shieldTransitionTask = nil
        shieldTransitionGeneration += 1
        let generation = shieldTransitionGeneration
        let previousAura = shieldAuraEntity
        currentShieldState = state

        guard state != .none else {
            guard let previousAura else { return }
            if reducedMotion {
                previousAura.removeFromParent()
                shieldAuraEntity = nil
                return
            }

            var dismissalTransform = previousAura.transform
            dismissalTransform.scale *= 1.04
            previousAura.move(
                to: dismissalTransform,
                relativeTo: previousAura.parent,
                duration: 0.24,
                timingFunction: .easeIn
            )
            shieldTransitionTask = Task { @MainActor [weak self, weak previousAura] in
                guard let self, let previousAura else { return }
                let steps = 6
                for step in 1...steps {
                    do {
                        try await Task.sleep(for: .milliseconds(40))
                    } catch {
                        return
                    }
                    guard generation == self.shieldTransitionGeneration else { return }
                    previousAura.components.set(
                        OpacityComponent(opacity: Float(steps - step) / Float(steps))
                    )
                }
                previousAura.removeFromParent()
                if self.shieldAuraEntity === previousAura {
                    self.shieldAuraEntity = nil
                }
                self.shieldTransitionTask = nil
            }
            return
        }

        previousAura?.removeFromParent()
        guard let aura = makeShieldAura(for: state, registry: registry),
              let enemyAnchor else {
            currentShieldState = .none
            shieldAuraEntity = nil
            return
        }

        shieldAuraEntity = aura
        enemyAnchor.addChild(aura)
        guard !reducedMotion else {
            aura.components.set(OpacityComponent(opacity: 1))
            return
        }

        let finalTransform = aura.transform
        var appearanceTransform = finalTransform
        appearanceTransform.scale *= 0.9
        aura.transform = appearanceTransform
        aura.components.set(OpacityComponent(opacity: 0))
        aura.move(
            to: finalTransform,
            relativeTo: enemyAnchor,
            duration: 0.32,
            timingFunction: .easeOut
        )
        shieldTransitionTask = Task { @MainActor [weak self, weak aura] in
            guard let self, let aura else { return }
            let steps = 8
            for step in 1...steps {
                do {
                    try await Task.sleep(for: .milliseconds(40))
                } catch {
                    return
                }
                guard generation == self.shieldTransitionGeneration else { return }
                aura.components.set(OpacityComponent(opacity: Float(step) / Float(steps)))
            }
            self.shieldTransitionTask = nil
        }
    }

    private func makeShieldAura(
        for state: RealityShieldState,
        registry: RealityEntityRegistry
    ) -> Entity? {
        guard let enemyAnchor,
              let actorBounds = enemyBounds(relativeTo: enemyAnchor) else { return nil }

        let role: RealityEntityRole
        let tint: UIColor
        let materialOpacity: Float
        switch state {
        case .general:
            role = .generalShield
            tint = UIColor(red: 0.2, green: 0.72, blue: 1, alpha: 1)
            materialOpacity = 0.14
        case .absolute:
            role = .absoluteShield
            tint = UIColor(red: 1, green: 0.7, blue: 0.16, alpha: 1)
            materialOpacity = 0.17
        case .none:
            return nil
        }
        guard let barrierBase = registry.entity(for: role) else { return nil }

        let barrierBounds = barrierBase.visualBounds(relativeTo: enemyAnchor)
        let actorSize = actorBounds.max - actorBounds.min
        let barrierSize = barrierBounds.max - barrierBounds.min
        let horizontalDiameter = max(
            max(barrierSize.x, barrierSize.y),
            max(actorSize.x, actorSize.y) * 1.45,
            4.6
        )
        let verticalDiameter = max(actorSize.z + 0.4, horizontalDiameter * 0.8)

        var material = UnlitMaterial(color: tint)
        material.blending = .transparent(opacity: .init(scale: materialOpacity))
        material.triangleFillMode = .lines
        material.faceCulling = .none
        material.writesDepth = false
        material.readsDepth = true

        let aura = ModelEntity(
            mesh: .generateSphere(radius: 0.5),
            materials: [material]
        )
        aura.name = "DA_RUNTIME_SHIELD_AURA"
        aura.scale = SIMD3(horizontalDiameter, horizontalDiameter, verticalDiameter)
        aura.position = SIMD3(
            (actorBounds.min.x + actorBounds.max.x) * 0.5,
            (actorBounds.min.y + actorBounds.max.y) * 0.5,
            actorBounds.min.z + verticalDiameter * 0.44
        )
        return aura
    }

    private func showIntent(
        _ cue: RealityEnemyIntentCue,
        reducedMotion: Bool,
        bundle: Bundle
    ) {
        guard currentIntentCue != cue, pendingIntentCue != cue else { return }
        intentGeneration += 1
        let generation = intentGeneration
        currentIntentEntity?.removeFromParent()
        currentIntentEntity = nil
        currentIntentCue = nil
        pendingIntentCue = cue

        load(
            assetID(for: cue),
            bundle: bundle,
            completion: { [weak self] entity in
                guard let self, generation == self.intentGeneration, let enemyAnchor = self.enemyAnchor else { return }
                let container = self.normalizedVFXContainer(
                    payload: entity,
                    name: "DA_RUNTIME_ENEMY_INTENT"
                )
                container.scale = SIMD3(repeating: self.intentScale)
                container.position = self.intentPosition(relativeTo: enemyAnchor)
                self.pendingIntentCue = nil
                self.currentIntentCue = cue
                self.currentIntentEntity = container
                enemyAnchor.addChild(container)
                self.playAuthoredAnimation(on: entity)
                self.animateAppearance(container, reducedMotion: reducedMotion)
            },
            failure: { [weak self] message in
                guard let self, generation == self.intentGeneration else { return }
                self.pendingIntentCue = nil
                self.logger.error("\(message, privacy: .public)")
            }
        )
    }

    private func showHit(
        _ cue: RealityHitCue,
        reducedMotion: Bool,
        bundle: Bundle
    ) {
        load(
            assetID(for: cue),
            bundle: bundle,
            completion: { [weak self] entity in
                guard let self, let enemyAnchor = self.enemyAnchor else { return }
                let container = self.normalizedVFXContainer(
                    payload: entity,
                    name: "DA_RUNTIME_ENEMY_HIT"
                )
                container.scale = SIMD3(repeating: 0.82)
                container.position = self.hitPosition(relativeTo: enemyAnchor)
                enemyAnchor.addChild(container)
                self.playAuthoredAnimation(on: entity)
                self.animateAppearance(container, reducedMotion: reducedMotion)

                Task { @MainActor [weak container] in
                    try? await Task.sleep(for: .milliseconds(reducedMotion ? 1_000 : 1_500))
                    guard let container else { return }
                    if reducedMotion {
                        container.removeFromParent()
                    } else {
                        await self.fadeOutAndRemove(container)
                    }
                }
            },
            failure: { [weak self] message in
                self?.logger.error("\(message, privacy: .public)")
            }
        )
    }

    private func clearIntent() {
        intentGeneration += 1
        currentIntentEntity?.removeFromParent()
        currentIntentEntity = nil
        currentIntentCue = nil
        pendingIntentCue = nil
    }

    private func intentPosition(relativeTo anchor: Entity) -> SIMD3<Float> {
        guard let bounds = enemyBounds(relativeTo: anchor) else {
            return SIMD3(0, -0.16, 2.15)
        }
        return SIMD3(
            (bounds.min.x + bounds.max.x) * 0.5,
            bounds.min.y - 0.35,
            bounds.max.z + intentVerticalOffset
        )
    }

    private func hitPosition(relativeTo anchor: Entity) -> SIMD3<Float> {
        guard let bounds = enemyBounds(relativeTo: anchor) else {
            return SIMD3(0, -0.16, 1.3)
        }
        return SIMD3(
            (bounds.min.x + bounds.max.x) * 0.5,
            bounds.min.y - 0.24,
            bounds.min.z + (bounds.max.z - bounds.min.z) * 0.56
        )
    }

    private func enemyBounds(relativeTo anchor: Entity) -> BoundingBox? {
        guard let enemyActor else { return nil }
        let bounds = enemyActor.visualBounds(relativeTo: anchor)
        let size = bounds.max - bounds.min
        guard size.x > 0.01, size.y > 0.01, size.z > 0.01 else { return nil }
        return bounds
    }

    private func normalizedVFXContainer(payload: Entity, name: String) -> Entity {
        let container = Entity()
        container.name = name
        payload.isEnabled = true
        container.addChild(payload)

        let bounds = payload.visualBounds(relativeTo: container)
        let size = bounds.max - bounds.min
        if size.x > 0.01, size.y > 0.01, size.z > 0.01 {
            payload.position -= (bounds.min + bounds.max) * 0.5
        }
        return container
    }

    private func animateAppearance(_ entity: Entity, reducedMotion: Bool) {
        guard !reducedMotion else { return }
        let finalTransform = entity.transform
        entity.scale *= 0.72
        entity.move(to: finalTransform, relativeTo: entity.parent, duration: 0.18, timingFunction: .easeOut)
    }

    private func fadeOutAndRemove(_ entity: Entity) async {
        let steps = 10
        for step in 1...steps {
            guard entity.parent != nil else { return }
            let opacity = Float(steps - step) / Float(steps)
            entity.components.set(OpacityComponent(opacity: opacity))
            try? await Task.sleep(for: .milliseconds(50))
        }
        entity.removeFromParent()
    }

    private func playAuthoredAnimation(on entity: Entity) {
        for animation in entity.availableAnimations {
            entity.playAnimation(animation, transitionDuration: 0.08, startsPaused: false)
        }
    }

    private func load(
        _ assetID: GameAssetID,
        bundle: Bundle,
        completion: @escaping @MainActor (Entity) -> Void,
        failure: @escaping @MainActor (String) -> Void
    ) {
        guard let resource = Self.resource(for: assetID) else {
            failure("3D 전투 효과 매핑이 없습니다: \(assetID.rawValue)")
            return
        }
        guard let url = bundle.url(
                forResource: resource.name,
                withExtension: "usdc",
                subdirectory: resource.subdirectory
        ) else {
            failure("3D 전투 효과 파일이 없습니다: \(resource.subdirectory)/\(resource.name).usdc")
            return
        }

        Entity.loadAsync(contentsOf: url)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { result in
                    if case let .failure(error) = result {
                        failure("3D 전투 효과를 불러오지 못했습니다: \(error.localizedDescription)")
                    }
                },
                receiveValue: { [weak self] loadedRoot in
                    guard let self else { return }
                    guard let effectEntity = loadedRoot.name == resource.entityName
                            ? loadedRoot
                            : loadedRoot.findEntity(named: resource.entityName) else {
                        failure("3D 전투 효과의 기준 객체가 없습니다: \(resource.entityName)")
                        return
                    }
                    effectEntity.removeFromParent()
                    self.enableHierarchy(effectEntity)
                    completion(effectEntity)
                }
            )
            .store(in: &loadCancellables)
    }

    private func enableHierarchy(_ entity: Entity) {
        entity.isEnabled = true
        for child in entity.children {
            enableHierarchy(child)
        }
    }

    private func assetID(for cue: RealityEnemyIntentCue) -> GameAssetID {
        switch cue {
        case .attack: .intentAttack
        case .heavyAttack: .intentHeavyAttack
        case .generalShield: .intentShield
        case .absoluteShield: .intentAbsoluteShield
        }
    }

    private func assetID(for cue: RealityHitCue) -> GameAssetID {
        switch cue {
        case .normal: .hitNormal
        case .heavy: .hitHeavy
        case .critical: .hitCritical
        case .shield: .hitShield
        }
    }

    private static func resource(
        for assetID: GameAssetID
    ) -> (name: String, subdirectory: String, entityName: String)? {
        switch assetID {
        case .hitNormal:
            (assetID.rawValue, "Reality/VFX/Combat/HitNormal", "VFX_HitNormal")
        case .hitHeavy:
            (assetID.rawValue, "Reality/VFX/Combat/HitHeavy", "VFX_HitHeavy")
        case .hitCritical:
            (assetID.rawValue, "Reality/VFX/Combat/HitCritical", "VFX_HitCritical")
        case .hitShield:
            (assetID.rawValue, "Reality/VFX/Combat/HitShield", "VFX_HitShield")
        case .intentAttack:
            (assetID.rawValue, "Reality/VFX/Combat/IntentAttack", "VFX_IntentAttack")
        case .intentHeavyAttack:
            (assetID.rawValue, "Reality/VFX/Combat/IntentHeavyAttack", "VFX_IntentHeavyAttack")
        case .intentShield:
            (assetID.rawValue, "Reality/VFX/Combat/IntentShield", "VFX_IntentShield")
        case .intentAbsoluteShield:
            (
                assetID.rawValue,
                "Reality/VFX/Combat/IntentAbsoluteShield",
                "VFX_IntentAbsoluteShield"
            )
        default:
            nil
        }
    }
}
