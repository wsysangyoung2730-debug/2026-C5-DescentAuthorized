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
    case memoryRecord
    case mimicAttack
    case openingWait
    case scheduledExecution
    case spellSeal
    case amplify
    case damageReservation
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
                if let cue = intentCue(for: intent, battleState: battleState) {
                    cues.append(.intent(cue))
                } else {
                    cues.append(.clearIntent)
                }

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

            case .expansionChanged, .healingApplied:
                break

            default:
                break
            }
        }

        if let battleState {
            cues.append(.shield(shieldState(for: battleState)))
            if let intent = battleState.currentEnemyIntent,
               battleState.phase == .playerTurn {
                if let cue = intentCue(for: intent, battleState: battleState) {
                    cues.append(.intent(cue))
                } else {
                    cues.append(.clearIntent)
                }
            }
        }
        return cues
    }

    static func shieldState(for battleState: BattleState) -> RealityShieldState {
        if battleState.phase == .victory || battleState.phase == .defeat { return .none }
        if battleState.enemy.absoluteBarrierCharges > 0 { return .absolute }
        if battleState.enemy.normalBarrier > 0 { return .general }
        return .none
    }

    static func intentCue(for action: EnemyAction, battleState: BattleState? = nil) -> RealityEnemyIntentCue? {
        switch action {
        case let .attack(_, _, isStrong):
            isStrong ? .heavyAttack : .attack
        case .grantNormalBarrier:
            .generalShield
        case .grantAbsoluteBarrier:
            .absoluteShield
        case let .telegraph(name, upcomingActionName):
            inferredIntentCue(from: "\(name) \(upcomingActionName)")
        case let .expansion(_, action):
            expansionIntentCue(for: action, battleState: battleState)
        }
    }

    private static func expansionIntentCue(for action: ExpansionEnemyAction, battleState: BattleState?) -> RealityEnemyIntentCue? {
        switch action {
        case .correctionBarrier, .timedBarrier: .generalShield
        case .absoluteSeal: .absoluteShield
        case .correctionStrike, .barrierStrike, .directHits, .counterExecute: .heavyAttack
        case .counterPrepare: .openingWait
        case .copyReaction: .mimicAttack
        case let .sequence(actions):
            actions.compactMap { expansionIntentCue(for: $0, battleState: battleState) }.first
        case .amplify, .flatAmplify: .amplify
        case .schedule: .damageReservation
        case .recordLastSpell: .memoryRecord
        case .lockAndSchedule, .preparedLockAndSchedule, .lockCards, .preparedCardSeal: .spellSeal
        case .wait:
            // Delay/erasure spells can change this during the player's turn.
            // Use the live queue rather than the action's display name.
            if let battleState, battleState.expansion.scheduledDamage.contains(where: {
                $0.dueEnemyTurn <= battleState.turnNumber
            }) {
                .scheduledExecution
            } else {
                .openingWait
            }
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
        if text.contains("피해 없는 빈틈") { return .openingWait }
        if text.contains("절대") { return .absoluteShield }
        if text.contains("방어") || text.contains("방벽") { return .generalShield }
        if text.contains("강") { return .heavyAttack }
        return .attack
    }
}

@MainActor
final class RealityCombatVFXRenderer {
    let effects = RealityCombatEffectLibrary()
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DescentAuthorized",
        category: "RealityCombatVFX"
    )
    var onProjectileImpact: (() -> Void)?
    var onProjectileLaunch: (() -> Void)?
    weak var cameraEntity: Entity?
    private var hitGeneration = 0
    private var hitTasks: [UUID: Task<Void, Never>] = [:]
    private var hitEntities: [UUID: Entity] = [:]
    private var hitAnimationControllers: [UUID: [AnimationPlaybackController]] = [:]
    private var enemyAttackTask: Task<Void, Never>?
    private var enemyAttackEntity: Entity?
    private var enemyAttackElapsed = 0.0
    private var enemyAttackReleased = false
    private struct AttackSocketManifest: Decodable {
        struct Socket: Decodable { let joint: String?; let entity: String?; let offset: [Float]? }
        let attackSocket: Socket?
    }
    private weak var attackSocketModel: ModelEntity?
    private weak var attackSocketEntity: Entity?
    private var attackSocketJointIndices: [Int] = []
    private var attackSocketOffset = SIMD3<Float>.zero
    private var effectCache: [String: Entity] = [:]
    private var preloadedHitEffects = false
    private weak var root: Entity?
    private weak var enemyAnchor: Entity?
    private weak var enemyActor: Entity?
    private var intentEffectsSuspended = false
    private var intentReducedMotion = false
    private var currentIntentEntity: Entity?
    private var currentIntentCue: RealityEnemyIntentCue?
    private var pendingIntentCue: RealityEnemyIntentCue?
    private var loadCancellables: Set<AnyCancellable> = []
    private var intentGeneration = 0
    private var intentScale: Float = 1.15
    private var intentVerticalOffset: Float = 0.3
    private var intentHalfHeight: Float = 0
    private var intentShieldClearance: Float?
    private var currentShieldState: RealityShieldState = .none
    private var shieldAuraEntity: Entity?
    private var shieldRestingScale = SIMD3<Float>(repeating: 1)
    private var shieldTransitionTask: Task<Void, Never>?
    private var shieldTransitionGeneration = 0
    var onIntentLayoutChanged: (() -> Void)?

    func projectedIntentFrame(in arView: ARView, clipped: Bool = true) -> CGRect? {
        guard let currentIntentEntity else { return nil }
        let bounds = currentIntentEntity.visualBounds(relativeTo: nil)
        let corners = [
            SIMD3(bounds.min.x, bounds.min.y, bounds.min.z),
            SIMD3(bounds.min.x, bounds.min.y, bounds.max.z),
            SIMD3(bounds.min.x, bounds.max.y, bounds.min.z),
            SIMD3(bounds.min.x, bounds.max.y, bounds.max.z),
            SIMD3(bounds.max.x, bounds.min.y, bounds.min.z),
            SIMD3(bounds.max.x, bounds.min.y, bounds.max.z),
            SIMD3(bounds.max.x, bounds.max.y, bounds.min.z),
            SIMD3(bounds.max.x, bounds.max.y, bounds.max.z)
        ]
        let projected = corners.compactMap(arView.project)
        guard projected.count >= 4 else { return nil }

        let minX = projected.map(\.x).min() ?? 0
        let maxX = projected.map(\.x).max() ?? 0
        let minY = projected.map(\.y).min() ?? 0
        let maxY = projected.map(\.y).max() ?? 0
        let rawFrame = CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
        if !clipped { return rawFrame }
        let minimumTargetSize: CGFloat = 64
        let maximumTargetSize = CGSize(width: 148, height: 176)
        let targetSize = CGSize(
            width: min(
                max(rawFrame.width + 8, minimumTargetSize),
                maximumTargetSize.width
            ),
            height: min(
                max(rawFrame.height + 8, minimumTargetSize),
                maximumTargetSize.height
            )
        )
        let targetFrame = CGRect(
            x: rawFrame.midX - targetSize.width / 2,
            y: rawFrame.midY - targetSize.height / 2,
            width: targetSize.width,
            height: targetSize.height
        ).intersection(arView.bounds)
        guard targetFrame.width >= 44, targetFrame.height >= 44 else { return nil }
        return targetFrame
    }

    #if DEBUG
    var shieldDiagnostics: [String: Any] {
        ["visible": shieldAuraEntity != nil,
         "settled": shieldAuraEntity?.scale == shieldRestingScale,
         "scale": shieldAuraEntity.map { [$0.scale.x, $0.scale.y, $0.scale.z] } ?? [],
         "effect": shieldAuraEntity?.name ?? "none"]
    }
    func intentClearanceDiagnostics() -> [String: Any] {
        guard let anchor = enemyAnchor, let entity = currentIntentEntity,
              let bounds = enemyBounds(relativeTo: anchor) else { return ["loaded": false] }
        let bottom = entity.position.z - intentHalfHeight
        return ["loaded": true, "actorGap": bottom - bounds.max.z,
                "shieldGap": shieldAuraEntity.map { bottom - $0.visualBounds(relativeTo: anchor).max.z } ?? 0]
    }
    #endif

    func attach(to registry: RealityEntityRegistry) {
        root = registry.root
        enemyAnchor = registry.entity(for: .enemySpawn) ?? registry.root
        let actor = registry.entity(for: .enemyActor)
        if enemyActor !== actor {
            enemyActor = actor
            configureAttackSocket(descriptor: registry.descriptor?.actor)
        }
        intentScale = registry.descriptor?.actor?.intentScale ?? 1.15
        intentVerticalOffset = registry.descriptor?.actor?.intentVerticalOffset ?? 0.3
        intentShieldClearance = registry.descriptor?.actor?.intentShieldClearance
        registry.setEnabled(true, for: .generalShield)
        registry.setEnabled(true, for: .absoluteShield)
        if !preloadedHitEffects {
            preloadedHitEffects = true
            for hit in [RealityHitCue.normal, .heavy, .critical, .shield] {
                load(assetID(for: hit), bundle: .main, completion: { _ in }, failure: { _ in })
            }
        }
    }

    func present(
        _ cues: [RealityCombatCue],
        registry: RealityEntityRegistry,
        reducedMotion: Bool,
        bundle: Bundle = .main
    ) {
        attach(to: registry)
        intentReducedMotion = reducedMotion
        if reducedMotion {
            enemyAttackTask?.cancel(); enemyAttackTask = nil
            enemyAttackEntity?.removeFromParent(); enemyAttackEntity = nil
        }
        updateIntentSmokeState()
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
        enemyAttackTask?.cancel()
        enemyAttackTask = nil
        enemyAttackEntity?.removeFromParent()
        enemyAttackEntity = nil
        enemyAttackElapsed = 0
        enemyAttackReleased = false
        attackSocketModel = nil
        attackSocketEntity = nil
        attackSocketJointIndices = []
        attackSocketOffset = .zero
        effectCache = [:]
        effects.reset()
        preloadedHitEffects = false
        hitGeneration += 1
        hitTasks.values.forEach { $0.cancel() }
        hitTasks.removeAll()
        hitEntities.values.forEach { $0.removeFromParent() }
        hitEntities.removeAll()
        hitAnimationControllers.values.flatMap { $0 }.forEach { $0.stop() }
        hitAnimationControllers = [:]
        cameraEntity = nil
        onProjectileLaunch = nil
        onProjectileImpact = nil
        intentEffectsSuspended = false
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
        intentShieldClearance = nil
        intentGeneration += 1
        shieldTransitionTask?.cancel()
        shieldTransitionTask = nil
        shieldAuraEntity?.removeFromParent()
        shieldAuraEntity = nil
        currentShieldState = .none
        shieldTransitionGeneration += 1
        onIntentLayoutChanged?()
    }

    private func applyShield(
        _ state: RealityShieldState,
        registry: RealityEntityRegistry,
        reducedMotion: Bool
    ) {
        guard state != currentShieldState else {
            if reducedMotion {
                shieldTransitionTask?.cancel(); shieldTransitionTask = nil
                if state == .none { shieldAuraEntity?.removeFromParent(); shieldAuraEntity = nil }
                else {
                    shieldAuraEntity?.scale = shieldRestingScale
                    shieldAuraEntity?.components.set(OpacityComponent(opacity: 1))
                }
                repositionCurrentIntent()
            }
            return
        }
        shieldTransitionTask?.cancel()
        shieldTransitionGeneration += 1
        let generation = shieldTransitionGeneration
        let previousAura = shieldAuraEntity
        currentShieldState = state
        if state == .none {
            guard let aura = previousAura else { return }
            if reducedMotion {
                aura.removeFromParent(); shieldAuraEntity = nil; repositionCurrentIntent()
                return
            }
            let scale = aura.scale
            shieldTransitionTask = Task { @MainActor [weak self, weak aura] in
                guard let self, let aura else { return }
                do {
                    try await self.animateEffect(duration: 0.24) { t in
                        aura.scale = scale * (1 + t * 0.07)
                        aura.components.set(OpacityComponent(opacity: 1 - t))
                    }
                } catch { return }
                guard generation == self.shieldTransitionGeneration else { return }
                aura.removeFromParent(); self.shieldAuraEntity = nil
                self.repositionCurrentIntent()
            }
            return
        }
        previousAura?.removeFromParent()
        guard let aura = makeShieldAura(for: state, registry: registry), let enemyAnchor else {
            currentShieldState = .none; shieldAuraEntity = nil
            return
        }
        shieldAuraEntity = aura
        shieldRestingScale = aura.scale
        enemyAnchor.addChild(aura)
        repositionCurrentIntent()
        guard !reducedMotion else { return }
        let scale = aura.scale
        shieldTransitionTask = Task { @MainActor [weak self, weak aura] in
            guard let self, let aura else { return }
            try? await self.animateEffect(duration: 0.32) { t in
                let eased = 1 - pow(1 - t, 3)
                aura.scale = scale * (0.88 + eased * 0.12)
                aura.components.set(OpacityComponent(opacity: t))
            }
        }
    }

    private func makeShieldAura(for state: RealityShieldState, registry: RealityEntityRegistry) -> Entity? {
        guard state != .none, let enemyAnchor,
              let bounds = enemyBounds(relativeTo: enemyAnchor) else { return nil }
        let id = CombatEffectCatalog.barrier(floor: effects.floor, absolute: state == .absolute)
        guard let aura = effects.make(id, size: 1) else { return nil }
        // The supplied correction cage has a solid crosspiece through its center.
        // Keep it spectral so the caster remains readable behind that authored geometry.
        if id == .correctionBarrier {
            aura.children.first?.components.set(OpacityComponent(opacity: 0.38))
        }
        let native = aura.visualBounds(relativeTo: aura).extents
        let clearance: Float = id == .correctionBarrier ? 1.08 : 1
        let diameter = max(max(bounds.extents.x, bounds.extents.y) * 1.20, bounds.extents.z * 0.82) * clearance
        let height = bounds.extents.z * 0.87
        aura.scale = SIMD3(diameter / max(0.01, native.x), diameter / max(0.01, native.y), height / max(0.01, native.z))
        aura.position = bounds.center
        aura.position.z = bounds.min.z + height * 0.51
        // The gap between the physical panels faces the battle camera.
        if let cameraEntity {
            let camera = enemyAnchor.convert(position: .zero, from: cameraEntity)
            let delta = camera - bounds.center
            let opening: Float = id == .generalBarrier || id == .documentBarrier ? .pi : .pi / 4
            aura.orientation = simd_quatf(angle: atan2(delta.x, -delta.y) + opening, axis: [0, 0, 1])
        }
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
                // Different authored cues have different dimensions; keep a common visual height.
                let nativeHeight = container.visualBounds(relativeTo: container).extents.z
                let actorHeight = self.enemyBounds(relativeTo: enemyAnchor)?.extents.z ?? 4
                let displayHeight = min(0.85, max(0.4, actorHeight * 0.20))
                let scale = nativeHeight > 0.001 ? displayHeight / nativeHeight : self.intentScale
                self.makeIntentReadable(entity)
                container.scale = SIMD3(repeating: scale)
                // Measure the authored symbol before smoke/appearance animation changes its bounds.
                let symbolBounds = container.visualBounds(relativeTo: container)
                self.intentHalfHeight = max(0, symbolBounds.extents.z * scale * 0.5)
                container.position = self.intentPosition(relativeTo: enemyAnchor)
                self.pendingIntentCue = nil
                self.currentIntentCue = cue
                self.currentIntentEntity = container
                enemyAnchor.addChild(container)
                self.addIntentSmoke(to: container, cue: cue)
                self.updateIntentSmokeState()
                self.playAuthoredAnimation(on: entity)
                self.animateAppearance(container, reducedMotion: reducedMotion)
                self.onIntentLayoutChanged?()
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
        let generation = hitGeneration
        let launchFeedback = onProjectileLaunch
        let impactFeedback = onProjectileImpact
        load(
            assetID(for: cue), bundle: bundle,
            completion: { [weak self] entity in
                guard let self, generation == self.hitGeneration,
                      let root = self.root, let anchor = self.enemyAnchor else { return }
                let effect = self.normalizedVFXContainer(payload: entity, name: "DA_RUNTIME_PLAYER_PROJECTILE")
                let id = UUID()
                root.addChild(effect)
                self.hitEntities[id] = effect
                // Camera-local right/down/forward follows the view, including combat look-around.
                let target = root.convert(position: self.hitPosition(relativeTo: anchor), from: anchor)
                let start = self.cameraEntity.map {
                    root.convert(position: SIMD3<Float>(0.22, -0.17, -0.65), from: $0)
                } ?? target
                self.hitTasks[id] = Task { @MainActor [weak self, weak effect, weak root] in
                    guard let self, let effect, let root else { return }
                    defer {
                        effect.removeFromParent()
                        self.hitEntities[id] = nil
                        self.hitTasks[id] = nil
                        self.hitAnimationControllers[id] = nil
                    }
                    do {
                        while self.intentEffectsSuspended {
                            try await Task.sleep(for: .milliseconds(16))
                        }
                        effect.position = start
                        launchFeedback?()
                        effect.scale = SIMD3(repeating: 0.18)
                        // Match the staged HP event and freeze the same flight on pause.
                        try await self.animateEffect(duration: CombatPresentationTimeline.playerImpactDelay) { t in
                            effect.position = start + (target - start) * t
                            effect.scale = SIMD3(repeating: 0.18 + 0.24 * t)
                            effect.components.set(OpacityComponent(opacity: reducedMotion ? 0 : 1))
                        }
                        effect.position = target
                        effect.scale = SIMD3(repeating: 0.48)
                        effect.components.set(OpacityComponent(opacity: 1))
                        // Short adhesion follows the actor, then debris falls in room Z-up space.
                        if let actor = self.enemyActor {
                            effect.setParent(actor, preservingWorldTransform: true)
                        }
                        if cue != .shield { impactFeedback?() }
                        self.addImpactAura(to: effect, reducedMotion: reducedMotion)
                        self.hitAnimationControllers[id] = self.playAuthoredAnimation(on: entity)
                        try await self.animateEffect(duration: reducedMotion ? 0.25 : 0.22) { _ in }
                        effect.setParent(root, preservingWorldTransform: true)
                        let impactTransform = effect.transform
                        let duration = reducedMotion ? 0.18 : 0.5
                        try await self.animateEffect(duration: duration) { t in
                            if !reducedMotion {
                                effect.position = impactTransform.translation + SIMD3<Float>(0.08 * t, -0.10 * t, -0.7 * t * t)
                                effect.orientation = impactTransform.rotation * simd_quatf(angle: t * 0.35, axis: SIMD3<Float>(1, 0, 0))
                                effect.scale = impactTransform.scale * (1 - 0.25 * t)
                            }
                            effect.components.set(OpacityComponent(opacity: 1 - t))
                        }
                    } catch { return }
                }
            },
            failure: { [weak self] message in
                guard let self, generation == self.hitGeneration else { return }
                launchFeedback?()
                if cue != .shield { impactFeedback?() }
                self.logger.error("\(message, privacy: .public)")
            }
        )
    }

    // Intent is gameplay information: room beams must not hide it, and room lighting
    // must not turn the attack/defence colors into indistinguishable dark silhouettes.
    private func makeIntentReadable(_ entity: Entity) {
        if var model = entity.components[ModelComponent.self] {
            model.materials = model.materials.map { source in
                var material = UnlitMaterial(color: .white)
                if let pbr = source as? PhysicallyBasedMaterial {
                    material.color = .init(tint: pbr.baseColor.tint, texture: pbr.baseColor.texture)
                } else if let unlit = source as? UnlitMaterial {
                    material = unlit
                }
                material.readsDepth = false
                material.writesDepth = false
                return material
            }
            entity.components.set(model)
        }
        for child in entity.children { makeIntentReadable(child) }
    }

    private func clearIntent() {
        intentGeneration += 1
        currentIntentEntity?.removeFromParent()
        currentIntentEntity = nil
        currentIntentCue = nil
        pendingIntentCue = nil
        onIntentLayoutChanged?()
    }

    private func intentPosition(relativeTo anchor: Entity) -> SIMD3<Float> {
        guard let bounds = enemyBounds(relativeTo: anchor) else {
            return SIMD3(0, -0.16, 2.15)
        }
        let gap = max(0.35, intentVerticalOffset, bounds.extents.z * 0.09)
        let baseHeight = bounds.max.z + gap + intentHalfHeight
        let resolvedHeight: Float
        if let shieldAuraEntity {
            let shieldTop = shieldAuraEntity.visualBounds(relativeTo: anchor).max.z
            resolvedHeight = max(baseHeight, shieldTop + max(gap, intentShieldClearance ?? 0) + intentHalfHeight)
        } else {
            resolvedHeight = baseHeight
        }
        return SIMD3(
            (bounds.min.x + bounds.max.x) * 0.5,
            (bounds.min.y + bounds.max.y) * 0.5,
            resolvedHeight
        )
    }

    private func repositionCurrentIntent() {
        guard let enemyAnchor, let currentIntentEntity else { return }
        currentIntentEntity.position = intentPosition(relativeTo: enemyAnchor)
        onIntentLayoutChanged?()
    }

    private func hitPosition(relativeTo anchor: Entity) -> SIMD3<Float> {
        guard let bounds = enemyBounds(relativeTo: anchor) else {
            return SIMD3(0, -0.16, 1.3)
        }
        let center = (bounds.min + bounds.max) * 0.5
        if let cameraEntity {
            var towardCamera = anchor.convert(position: .zero, from: cameraEntity) - center
            towardCamera.z = 0
            if simd_length(towardCamera) > 0.001 {
                towardCamera = simd_normalize(towardCamera)
                let extent = (bounds.max - bounds.min) * 0.5
                let distance = min(extent.x / max(abs(towardCamera.x), 0.001),
                                   extent.y / max(abs(towardCamera.y), 0.001))
                var point = center + towardCamera * (distance + 0.12)
                point.z = bounds.min.z + (bounds.max.z - bounds.min.z) * 0.56
                return point
            }
        }
        return SIMD3(center.x, bounds.min.y - 0.24,
                     bounds.min.z + (bounds.max.z - bounds.min.z) * 0.56)
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

    private func animateEffect(duration: TimeInterval, update: (Float) -> Void) async throws {
        var elapsed = 0.0
        var previous = ProcessInfo.processInfo.systemUptime
        update(0)
        while elapsed < duration {
            try await Task.sleep(for: .milliseconds(16))
            let now = ProcessInfo.processInfo.systemUptime
            let delta = max(0, now - previous)
            previous = now
            guard !intentEffectsSuspended else { continue }
            elapsed += delta
            update(Float(min(1, elapsed / duration)))
        }
    }

    @discardableResult
    private func playAuthoredAnimation(on entity: Entity) -> [AnimationPlaybackController] {
        entity.availableAnimations.map {
            entity.playAnimation($0, transitionDuration: 0.08, startsPaused: intentEffectsSuspended)
        }
    }

    private func load(
        _ assetID: GameAssetID,
        bundle: Bundle,
        completion: @escaping @MainActor (Entity) -> Void,
        failure: @escaping @MainActor (String) -> Void
    ) {
        if let cached = effectCache[assetID.rawValue] {
            completion(cached.clone(recursive: true))
            return
        }
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
                    self.effectCache[assetID.rawValue] = effectEntity.clone(recursive: true)
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
        case .memoryRecord: .intentMemoryRecord
        case .mimicAttack: .intentMimicAttack
        case .openingWait: .intentOpeningWait
        case .scheduledExecution: .intentScheduledExecution
        case .spellSeal: .intentSpellSeal
        case .amplify: .intentAmplify
        case .damageReservation: .intentDamageReservation
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
        case .intentMemoryRecord:
            (assetID.rawValue, "Reality/VFX/Combat/IntentMemoryRecord", "VFX_IntentMemoryRecord")
        case .intentMimicAttack:
            (assetID.rawValue, "Reality/VFX/Combat/IntentMimicAttack", "VFX_IntentMimicAttack")
        case .intentOpeningWait:
            (assetID.rawValue, "Reality/VFX/Combat/IntentOpeningWait", "VFX_IntentOpeningWait")
        case .intentScheduledExecution:
            (assetID.rawValue, "Reality/VFX/Combat/IntentScheduledExecution", "VFX_IntentScheduledExecution")
        case .intentSpellSeal:
            (assetID.rawValue, "Reality/VFX/Combat/IntentSpellSeal", "VFX_IntentSpellSeal")
        case .intentAmplify:
            (assetID.rawValue, "Reality/VFX/Combat/IntentAmplify", "VFX_IntentAmplify")
        case .intentDamageReservation:
            (assetID.rawValue, "Reality/VFX/Combat/IntentDamageReservation", "VFX_IntentDamageReservation")
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

/// Attack gestures retain rigid equipment. Defeat separates the authored surface
/// into independently moving pieces instead of tipping the whole actor over.
@MainActor
final class RealityActorMotionPlayer {
    // Authored articulation owns the gesture; this clock owns its lifetime.
    private enum MotionProfile {
        static func duration(for name: String) -> Double {
            switch name {
            case "idle", "idleVariant": 4.0
            case "appear": 1.0
            case "attack": EnemyAttackTiming.normal.duration
            case "heavyAttack": EnemyAttackTiming.heavy.duration
            case "telegraph": 1.2
            case "special": 2.0
            case "hit": 0.8
            case "death": CombatPresentationTimeline.deathPoseDuration
            default: 1.0
            }
        }

    }
    private struct JointManifest: Decodable {
        struct Clip: Decodable { let start: Double; let end: Double; let duration: Double? }
        let clips: [String: Clip]
    }
    private var jointManifest: JointManifest?
    private weak var articulated: Entity?
    private weak var animatedEntity: Entity?
    private var jointSource: AnimationResource?
    private var jointPlayback: AnimationPlaybackController?
    private weak var visualRoot: Entity?
    private var baseTransform = Transform.identity
    private var modelHeight: Float = 3
    private var footPivot = SIMD3<Float>.zero
    private var motionTask: Task<Void, Never>?
    private var generation = 0
    private var terminal = false
    private var reduced = false
    private var suspended = false
    private var currentMotion = "idle"
    private var elapsed = 0.0
    private var fragments: [(entity: Entity, closed: Transform, position: SIMD3<Float>)] = []

    func install(root: Entity, descriptor: RealityActorDescriptor, bundle: Bundle) throws {
        reset()
        visualRoot = root
        articulated = root.findEntity(named: "DA_Articulated")
        func findAnimated(_ entity: Entity) -> Entity? {
            if !entity.availableAnimations.isEmpty { return entity }
            return entity.children.lazy.compactMap { findAnimated($0) }.first
        }
        if let articulated {
            animatedEntity = findAnimated(articulated)
            jointSource = animatedEntity?.availableAnimations.first
        }
        if let url = bundle.url(forResource: "motion", withExtension: "json", subdirectory: descriptor.resourceSubdirectory) {
            jointManifest = try JSONDecoder().decode(JointManifest.self, from: Data(contentsOf: url))
        }
        guard articulated != nil, jointSource != nil else {
            throw NSError(domain: "ActorMotion", code: 3, userInfo: [NSLocalizedDescriptionKey: "관절 공격 모션을 불러오지 못했습니다: \(descriptor.resourceName)"])
        }
        baseTransform = root.transform
        let bounds = root.visualBounds(relativeTo: root.parent)
        modelHeight = max(bounds.extents.z, 0.01)
        footPivot = SIMD3((bounds.min.x + bounds.max.x) * 0.5,
                          (bounds.min.y + bounds.max.y) * 0.5, bounds.min.z)
        func collect(_ entity: Entity) {
            if entity.name.hasPrefix("DA_Fragment_") {
                fragments.append((entity, entity.transform, entity.position(relativeTo: root.parent)))
            } else { entity.children.forEach(collect) }
        }
        collect(root)
        restoreFragments()
        root.stopAllAnimations(recursive: true)
        root.components.set(OpacityComponent(opacity: 1))
        play("idle")
    }

    func prepareEncounter() {
        restoreFragments()
        terminal = false
        visualRoot?.isEnabled = true
        visualRoot?.transform = baseTransform
        visualRoot?.components.set(OpacityComponent(opacity: 1))
        play("idle")
    }

    func setReducedMotion(_ value: Bool) {
        guard reduced != value else { return }
        reduced = value
        if value { visualRoot?.transform = baseTransform; restoreFragments() }
        if terminal { return } // Keep death progress; do not restart its fade.
        if value {
            animatedEntity?.stopAllAnimations(recursive: false)
            jointPlayback = nil
            playJoints("idle", paused: true)
        } else {
            playJoints(currentMotion, elapsed: elapsed)
        }
    }

    func setSuspended(_ value: Bool) {
        guard suspended != value else { return }
        suspended = value
        if value { jointPlayback?.pause() }
        else if !reduced, currentMotion == "idle" || currentMotion == "idleVariant" { jointPlayback?.resume() }
    }

    func present(_ events: [DemoSessionEvent], state: BattleState?,
                 enemyActionPresentation: EnemyActionPresentation? = nil) {
        if state?.phase == .victory { play("death"); return }
        var motion: String?
        for event in events {
            guard case let .combat(event) = event else { continue }
            switch event {
            case .victory: motion = "death"
            case let .enemyActionStarted(action):
                if let strong = (enemyActionPresentation
                    ?? EnemyActionPresentation(action: action, state: state)).attackStrength {
                    motion = strong ? "heavyAttack" : "attack"
                } else if case .telegraph = action {
                    motion = "telegraph"
                } else {
                    motion = "special"
                }
            default: break
            }
        }
        if let motion { play(motion) }
    }

    func reactToProjectileImpact() {
        // A slow asset load must never interrupt a later enemy attack or death.
        guard currentMotion == "idle" || currentMotion == "hit" else { return }
        play("hit")
    }

    func play(_ name: String) {
        if terminal {
            // Defeat/record panels can re-enable the preview after victory.
            // Reapply the terminal pose without restarting or resurrecting it.
            if name == "death", let root = visualRoot {
                applyFracture(elapsed: elapsed, root: root)
            }
            return
        }
        if name == "death" { terminal = true }
        // Let RealityKit blend the outgoing pose on the same animation layer.
        stop(stopJoints: name == "death")
        currentMotion = name
        elapsed = 0
        guard let root = visualRoot else { return }
        root.transform = baseTransform
        articulated?.isEnabled = name != "death"
        for piece in fragments { piece.entity.isEnabled = name == "death" }
        if name != "death", !reduced || jointPlayback == nil {
            playJoints(reduced ? "idle" : name, paused: reduced)
        }
        let token = generation
        motionTask = Task { @MainActor [weak self] in
            var previous = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
                let now = ProcessInfo.processInfo.systemUptime
                let delta = max(now - previous, 0)
                previous = now
                guard let self, self.generation == token, let root = self.visualRoot else { return }
                if self.suspended { continue }
                self.elapsed += delta
                let duration = self.duration(for: name)
                if name == "death" {
                    self.applyFracture(elapsed: self.elapsed, root: root)
                    if self.elapsed >= CombatPresentationTimeline.deathDuration { root.components.set(OpacityComponent(opacity: 0)); root.isEnabled = false; return }
                    continue
                }
                // A second rigid lunge over the skeletal arm/torso arc made every
                // cast slide and snap. Preserve the installed transform throughout.
                root.transform = self.baseTransform
                if !self.reduced, name != "idle", name != "idleVariant" {
                    // RealityKit's independent clock can lag while a frame is loaded.
                    // Sample the authored clip from the action clock, including its recovery.
                    self.jointPlayback?.time = min(self.elapsed, duration)
                }
                if name != "idle", name != "idleVariant", self.elapsed >= duration {
                    self.play("idle")
                    return
                }
            }
        }
    }

    private func restoreFragments() {
        for piece in fragments {
            piece.entity.transform = piece.closed
            piece.entity.components.set(OpacityComponent(opacity: 1))
            piece.entity.isEnabled = false
        }
    }

    private func duration(for name: String) -> Double {
        // Attack and special windows are shared with the turn presentation clock.
        if name == "idle" || name == "idleVariant" || name == "hit" || name == "appear",
           let clip = jointManifest?.clips[name] {
            return clip.duration ?? (clip.end - clip.start)
        }
        return MotionProfile.duration(for: name)
    }

    private func playJoints(_ name: String, paused: Bool = false, elapsed: Double = 0) {
        guard let source = jointSource, let entity = animatedEntity,
              let clip = jointManifest?.clips[name] ?? jointManifest?.clips["idle"] else { return }
        do {
            let span = max(0.001, clip.end - clip.start)
            let view = AnimationView(source: source.definition, name: name,
                                     fillMode: .forwards,
                                     trimStart: clip.start, trimEnd: clip.end,
                                     speed: Float(span / max(0.001, duration(for: name))))
            let animation = try AnimationResource.generate(with: view)
            let loops = name == "idle" || name == "idleVariant"
            jointPlayback = entity.playAnimation(loops ? animation.repeat() : animation,
                                                 transitionDuration: paused || !loops ? 0 : 0.08,
                                                 startsPaused: paused || suspended || !loops)
            jointPlayback?.time = loops
                ? elapsed.truncatingRemainder(dividingBy: duration(for: name))
                : min(elapsed, duration(for: name))
        } catch {
            assertionFailure("Articulated animation failed: \(error)")
        }
    }

    private func applyFracture(elapsed: Double, root: Entity) {
        root.transform = baseTransform
        let end = CombatPresentationTimeline.deathDuration
        root.isEnabled = elapsed < end
        if reduced || fragments.isEmpty {
            root.components.set(OpacityComponent(opacity: Float(max(0, 1 - elapsed / end))))
            return
        }
        root.components.set(OpacityComponent(opacity: 1))
        for (index, piece) in fragments.enumerated() {
            let delay = 0.025 + Double(index % 5) * 0.018
            let t = Float(max(0, elapsed - delay)) * 1.8
            let angle = Float(index) * 2.399963
            let velocity = modelHeight * (0.10 + Float(index % 3) * 0.025)
            let lift = modelHeight * (0.12 + Float(index % 4) * 0.025)
            var position = piece.position + SIMD3(cos(angle) * velocity * t, sin(angle) * velocity * t, lift * t - modelHeight * 0.24 * t * t)
            // Dissolve above the floor; fragments never tumble through the room.
            position.z = max(footPivot.z + modelHeight * 0.025, position.z)
            piece.entity.transform = piece.closed
            piece.entity.setPosition(position, relativeTo: root.parent)
            piece.entity.orientation *= simd_quatf(angle: t * (index.isMultiple(of: 2) ? 1.1 : -0.8), axis: simd_normalize(SIMD3<Float>(1, Float(index % 3 + 1), 0.4)))
            let fade = Float(max(0, min(1, (end - elapsed) / 0.42)))
            piece.entity.components.set(OpacityComponent(opacity: fade))
        }
    }

    private func stop(stopJoints: Bool = true) {
        generation += 1
        if stopJoints {
            jointPlayback?.stop()
            jointPlayback = nil
        }
        motionTask?.cancel()
        motionTask = nil
    }

    func reset() {
        stop()
        restoreFragments()
        fragments.removeAll()
        articulated = nil; animatedEntity = nil; jointSource = nil; jointManifest = nil
        visualRoot?.transform = baseTransform
        visualRoot?.components.set(OpacityComponent(opacity: 1))
        visualRoot = nil
        footPivot = .zero
        terminal = false; reduced = false; suspended = false
        currentMotion = "idle"; elapsed = 0
    }

    #if DEBUG
    var attackDiagnostics: [String: Any] {
        ["currentMotion": currentMotion, "clipElapsed": elapsed,
         "clipDuration": duration(for: currentMotion),
         "controllerTime": jointPlayback?.time ?? -1,
         "controllerDuration": jointPlayback.map { $0.duration.isFinite ? $0.duration : -1 } ?? -1,
         "controllerRepeats": jointPlayback.map { !$0.duration.isFinite } ?? false,
         "controllerPaused": jointPlayback?.isPaused ?? true,
         "animatedEntity": animatedEntity?.name ?? "missing",
         "suspended": suspended, "reducedMotion": reduced]
    }
    #endif
}

// Enemy strikes travel from the attacking hand/core toward the player, in room space.
extension RealityCombatVFXRenderer {
    private func configureAttackSocket(descriptor: RealityActorDescriptor?) {
        attackSocketModel = nil
        attackSocketEntity = nil
        attackSocketJointIndices = []
        attackSocketOffset = .zero
        guard let actor = enemyActor, let descriptor,
              let url = Bundle.main.url(forResource: "motion", withExtension: "json",
                                        subdirectory: descriptor.resourceSubdirectory),
              let data = try? Data(contentsOf: url),
              let socket = (try? JSONDecoder().decode(AttackSocketManifest.self, from: data))?.attackSocket else { return }
        if let offset = socket.offset, offset.count == 3 {
            attackSocketOffset = SIMD3(offset[0], offset[1], offset[2])
        }
        if let name = socket.entity { attackSocketEntity = actor.findEntity(named: name) }
        guard let joint = socket.joint else { return }
        func find(_ entity: Entity) -> ModelEntity? {
            if let model = entity as? ModelEntity,
               model.jointNames.contains(where: { $0 == joint || $0.split(separator: "/").last.map(String.init) == joint }) {
                return model
            }
            return entity.children.lazy.compactMap(find).first
        }
        guard let model = find(actor),
              let name = model.jointNames.first(where: { $0 == joint || $0.split(separator: "/").last.map(String.init) == joint }) else { return }
        let pieces = name.split(separator: "/")
        attackSocketJointIndices = (1...pieces.count).compactMap { count in
            model.jointNames.firstIndex(of: pieces.prefix(count).joined(separator: "/"))
        }
        attackSocketModel = model
    }

    private func attackOrigin(relativeTo root: Entity, fallback: SIMD3<Float>) -> SIMD3<Float> {
        if let entity = attackSocketEntity {
            return root.convert(position: attackSocketOffset, from: entity)
        }
        if let model = attackSocketModel, !attackSocketJointIndices.isEmpty {
            let transforms = model.jointTransforms
            guard attackSocketJointIndices.allSatisfy({ transforms.indices.contains($0) }) else { return fallback }
            let matrix = attackSocketJointIndices.reduce(matrix_identity_float4x4) { $0 * transforms[$1].matrix }
            let point = matrix * SIMD4<Float>(attackSocketOffset, 1)
            let origin = root.convert(position: SIMD3(point.x, point.y, point.z), from: model)
            if origin.x.isFinite, origin.y.isFinite, origin.z.isFinite { return origin }
        }
        // Older assets without a named socket still follow the actor throughout preparation.
        if let bounds = enemyBounds(relativeTo: root) {
            return SIMD3(bounds.center.x + bounds.extents.x * 0.20,
                         bounds.min.y - 0.12, bounds.min.z + bounds.extents.z * 0.62)
        }
        return fallback
    }

    func presentEnemyAction(_ events: [DemoSessionEvent], state: BattleState?, reducedMotion: Bool,
                           enemyActionPresentation: EnemyActionPresentation? = nil) {
        guard let action = events.compactMap({ event -> EnemyAction? in
            if case let .combat(.enemyActionStarted(action)) = event { return action }
            return nil
        }).first else { return }
        let presentation = enemyActionPresentation ?? EnemyActionPresentation(action: action, state: state)
        guard let strong = presentation.attackStrength else { return }
        let scheduled = presentation.includesScheduledDamage
        enemyAttackTask?.cancel()
        enemyAttackEntity?.removeFromParent()
        guard !reducedMotion, let root, let cameraEntity,
              let bounds = enemyBounds(relativeTo: root) else { return }

        let effectID = CombatEffectCatalog.projectile(floor: effects.floor, action: action,
            executionOnly: scheduled && effects.floor == 1)
        let size = min(1.45, max(0.6, bounds.extents.z * (strong ? 0.33 : 0.27)))
        let payload = effects.observationResidual
            ? effects.make("glass", size: size * 0.65) : effects.make(effectID, size: size)
        guard let core = payload else { return }
        let strike = Entity()
        strike.name = "DA_ENEMY_STRIKE"
        strike.addChild(core)
        let alignment = simd_quatf(from: simd_normalize(RealityCombatEffectLibrary.forward(effectID)), to: [0, 0, 1])
        core.orientation = alignment
        core.scale = SIMD3(repeating: 0.35)
        let fallbackStart = SIMD3<Float>(
            bounds.center.x + bounds.extents.x * 0.20,
            bounds.min.y - 0.12,
            bounds.min.z + bounds.extents.z * 0.62
        )
        let start = attackOrigin(relativeTo: root, fallback: fallbackStart)
        let end = root.convert(position: SIMD3<Float>(0.08, -0.08, -0.48), from: cameraEntity)
        let direction = simd_normalize(end - start)
        strike.orientation = simd_quatf(from: SIMD3<Float>(0, 0, 1), to: direction)
        strike.position = start
        root.addChild(strike)
        enemyAttackEntity = strike
        enemyAttackElapsed = 0
        enemyAttackReleased = false
        let timing = EnemyAttackTiming.forAttack(strong: strong)
        let impact = timing.impact
        let flight = timing.flightDuration
        let launch = timing.release
        let generation = hitGeneration
        enemyAttackTask = Task { @MainActor [weak self, weak strike] in
            guard let self, let strike else { return }
            defer {
                strike.removeFromParent()
                if self.enemyAttackEntity === strike { self.enemyAttackEntity = nil }
            }
            var elapsed = 0.0
            var releasedFrom: SIMD3<Float>?
            var releasedToward = end
            let clock = ContinuousClock()
            var previous = clock.now
            while elapsed < impact {
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
                guard generation == self.hitGeneration else { return }
                let now = clock.now
                let delta = previous.duration(to: now).components
                previous = now
                guard !self.intentEffectsSuspended else { continue }
                elapsed += Double(delta.seconds) + Double(delta.attoseconds) / 1e18
                self.enemyAttackElapsed = elapsed
                if elapsed < launch {
                    strike.position = self.attackOrigin(relativeTo: root, fallback: start)
                    let charge = Float(elapsed / launch)
                    let eased = charge * charge * (3 - 2 * charge)
                    core.scale = SIMD3(repeating: 0.35 + eased * 0.65)
                    // Hold the silhouette obliquely while gathering, then aim the tip at release.
                    let aim = max(0, (charge - 0.76) / 0.24)
                    core.orientation = simd_quatf(angle: (1 - aim) * 0.95, axis: [0, 1, 0]) * alignment
                    strike.components.set(OpacityComponent(opacity: min(1, charge * 4)))
                } else {
                    if releasedFrom == nil {
                        let origin = self.attackOrigin(relativeTo: root, fallback: strike.position)
                        releasedFrom = origin
                        self.enemyAttackReleased = true
                        releasedToward = root.convert(position: SIMD3<Float>(0.08, -0.08, -0.48), from: cameraEntity)
                        let direction = simd_normalize(releasedToward - origin)
                        strike.orientation = simd_quatf(from: SIMD3<Float>(0, 0, 1), to: direction)
                    }
                    let t = Float(min(1, (elapsed - launch) / flight))
                    let origin = releasedFrom ?? start
                    strike.position = origin + (releasedToward - origin) * t
                    let spin: Float = effectID == .signatureStroke ? 1.15 : (effectID == .isolationRing ? 0.65 : 0.16)
                    core.orientation = simd_quatf(angle: t * spin, axis: [0, 0, 1]) * alignment
                    let contraction: Float = effectID == .memoryCompression || effectID == .isolationRing ? 1 - 0.25 * t : 1
                    core.scale = SIMD3(repeating: contraction)
                    // Disappear just in front of the camera instead of clipping through it.
                    strike.components.set(OpacityComponent(opacity: min(1, (1 - t) * 7)))
                }
            }
        }
    }

    #if DEBUG
    var attackDiagnostics: [String: Any] {
        ["elapsed": enemyAttackElapsed, "released": enemyAttackReleased,
         "hasStrike": enemyAttackEntity != nil,
         "effect": enemyAttackEntity?.children.first?.name ?? "none",
         "socketModel": attackSocketModel?.name ?? "missing",
         "socketEntity": attackSocketEntity?.name ?? "none",
         "socketJoints": attackSocketJointIndices.compactMap { index -> String? in
             guard let model = attackSocketModel, model.jointNames.indices.contains(index) else { return nil }
             return model.jointNames[index]
         }]
    }
    #endif
}

// Shared by all intent types; positions/directions are in the room's Z-up space.
extension RealityCombatVFXRenderer {
    func setIntentEffectsSuspended(_ suspended: Bool) {
        intentEffectsSuspended = suspended
        for playback in hitAnimationControllers.values.flatMap({ $0 }) {
            if suspended { playback.pause() } else { playback.resume() }
        }
        func suspendEmitters(_ entity: Entity) {
            if var emitter = entity.components[ParticleEmitterComponent.self] {
                emitter.simulationState = suspended ? .pause : .play
                entity.components.set(emitter)
            }
            entity.children.forEach(suspendEmitters)
        }
        hitEntities.values.forEach(suspendEmitters)
        updateIntentSmokeState()
    }

    private func updateIntentSmokeState() {
        guard let container = currentIntentEntity else { return }
        if let smoke = container.findEntity(named: "DA_INTENT_SMOKE"),
           var emitter = smoke.components[ParticleEmitterComponent.self] {
            emitter.isEmitting = !intentReducedMotion
            emitter.simulationState = intentEffectsSuspended ? .pause : .play
            smoke.components.set(emitter)
            smoke.isEnabled = !intentReducedMotion
        }
        container.findEntity(named: "DA_INTENT_STATIC_HALO")?.isEnabled = intentReducedMotion
    }

    private func addIntentSmoke(to container: Entity, cue: RealityEnemyIntentCue) {
        let accent = intentColor(cue)
        // Charcoal smoke with only a trace of the action color.
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        accent.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let color = UIColor(red: 0.035 + red * 0.18, green: 0.035 + green * 0.18, blue: 0.035 + blue * 0.18, alpha: 1)
        let smoke = Entity()
        smoke.name = "DA_INTENT_SMOKE"
        // The model faces -Y. Keep smoke behind even the thickest new glyph.
        smoke.position = SIMD3(0, 0.34, -0.14)
        var emitter = ParticleEmitterComponent()
        emitter.emitterShape = .box
        emitter.emitterShapeSize = SIMD3(0.38, 0.02, 0.08)
        emitter.birthLocation = .volume
        emitter.birthDirection = .local
        emitter.emissionDirection = SIMD3(0, 0, 1)
        emitter.speed = 0.13
        emitter.speedVariation = 0.035
        emitter.particlesInheritTransform = true
        emitter.fieldSimulationSpace = .local
        emitter.timing = .repeating(warmUp: 1, emit: .init(duration: 8))
        emitter.mainEmitter.birthRate = 10
        emitter.mainEmitter.lifeSpan = 1.15
        emitter.mainEmitter.lifeSpanVariation = 0.15
        emitter.mainEmitter.size = 0.19
        emitter.mainEmitter.sizeVariation = 0.045
        emitter.mainEmitter.sizeMultiplierAtEndOfLifespan = 1.35
        emitter.mainEmitter.spreadingAngle = 0.12
        emitter.mainEmitter.acceleration = SIMD3(0, 0, 0.015)
        emitter.mainEmitter.noiseStrength = 0.025
        emitter.mainEmitter.noiseScale = 0.8
        emitter.mainEmitter.noiseAnimationSpeed = 0.4
        emitter.mainEmitter.angularSpeed = 0.22
        emitter.mainEmitter.angularSpeedVariation = 0.3
        emitter.mainEmitter.angleVariation = .pi
        emitter.mainEmitter.billboardMode = .billboard
        emitter.mainEmitter.opacityCurve = .gradualFadeInOut
        emitter.mainEmitter.color = .evolving(
            start: .single(color.withAlphaComponent(0.28)),
            end: .single(color.withAlphaComponent(0))
        )
        emitter.mainEmitter.blendMode = .alpha
        emitter.mainEmitter.isLightingEnabled = false
        emitter.mainEmitter.image = Self.intentSmokeTexture
        smoke.components.set(emitter)
        container.addChild(smoke)

        // Preserve color separation without continuous motion when Reduce Motion is on.
        var material = UnlitMaterial(color: color.withAlphaComponent(0.14))
        if let texture = Self.intentSmokeTexture {
            material.color.texture = .init(texture)
        }
        material.blending = .transparent(opacity: .init(floatLiteral: 0.14))
        material.faceCulling = .none
        let halo = ModelEntity(mesh: .generatePlane(width: 0.72, depth: 0.78), materials: [material])
        halo.name = "DA_INTENT_STATIC_HALO"
        halo.position = SIMD3(0, 0.46, 0.04)
        container.addChild(halo)
    }

    private func intentColor(_ cue: RealityEnemyIntentCue) -> UIColor {
        switch cue {
        case .attack: UIColor(red: 1, green: 0.12, blue: 0.2, alpha: 1)
        case .heavyAttack: UIColor(red: 1, green: 0.06, blue: 0.3, alpha: 1)
        case .generalShield: UIColor(red: 0.2, green: 0.65, blue: 1, alpha: 1)
        case .absoluteShield: UIColor(red: 1, green: 0.8, blue: 0.2, alpha: 1)
        case .memoryRecord: UIColor(red: 0.64, green: 0.3, blue: 1, alpha: 1)
        case .mimicAttack: UIColor(red: 1, green: 0.12, blue: 0.55, alpha: 1)
        case .openingWait: UIColor(red: 0.3, green: 0.85, blue: 1, alpha: 1)
        case .scheduledExecution: UIColor(red: 1, green: 0.24, blue: 0.06, alpha: 1)
        case .spellSeal: UIColor(red: 0.85, green: 0.12, blue: 1, alpha: 1)
        case .amplify: UIColor(red: 1, green: 0.5, blue: 0.08, alpha: 1)
        case .damageReservation: UIColor(red: 1, green: 0.72, blue: 0.14, alpha: 1)
        }
    }

    private static let intentSmokeTexture: TextureResource? = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: 128, height: 128), format: format).image { context in
            let colors = [UIColor.white.withAlphaComponent(0.7).cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
            // Overlapping soft lobes avoid hard-edged discs or square particle cards.
            for (x, y, radius) in [(64.0, 62.0, 52.0), (43.0, 52.0, 33.0), (81.0, 75.0, 35.0), (72.0, 40.0, 29.0)] {
                let center = CGPoint(x: x, y: y)
                context.cgContext.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
            }
        }
        guard let cgImage = image.cgImage else { return nil }
        return try? TextureResource.generate(from: cgImage, options: .init(semantic: .color))
    }()
}


extension RealityCombatVFXRenderer {
    private func addImpactAura(to impact: Entity, reducedMotion: Bool) {
        guard !reducedMotion else { return }
        let aura = Entity()
        aura.name = "DA_IMPACT_CHARCOAL_AURA"
        aura.position = SIMD3(0, 0.12, 0)
        var emitter = ParticleEmitterComponent()
        emitter.emitterShape = .sphere
        emitter.emitterShapeSize = SIMD3(repeating: 0.18)
        emitter.birthDirection = .local
        emitter.emissionDirection = SIMD3(0, 0, 1)
        emitter.speed = 0.12
        emitter.speedVariation = 0.04
        emitter.mainEmitter.birthRate = 0
        emitter.burstCount = 9
        emitter.mainEmitter.lifeSpan = 0.6
        emitter.mainEmitter.size = 0.22
        emitter.mainEmitter.sizeVariation = 0.05
        emitter.mainEmitter.sizeMultiplierAtEndOfLifespan = 1.4
        emitter.mainEmitter.noiseStrength = 0.035
        emitter.mainEmitter.opacityCurve = .gradualFadeInOut
        emitter.mainEmitter.color = .evolving(
            start: .single(UIColor(white: 0.035, alpha: 0.32)),
            end: .single(UIColor(white: 0.035, alpha: 0))
        )
        emitter.mainEmitter.blendMode = .alpha
        emitter.mainEmitter.isLightingEnabled = false
        emitter.mainEmitter.image = Self.intentSmokeTexture
        emitter.burst()
        aura.components.set(emitter)
        impact.addChild(aura)
    }
}

/// Persistent status visuals are reconstructed from BattleState, including checkpoint restores.
@MainActor
final class RealityCombatStatusRenderer {
    var effects: RealityCombatEffectLibrary?
    private static let segmentMesh = MeshResource.generateBox(size: 1)
    private static var ringMeshes: [Float: MeshResource] = [:]
    private struct Entry {
        let entity: Entity
        let base: SIMD3<Float>
        let born: Double
        var retiringAt: Double?
        var destination: SIMD3<Float>?
        let urgent: Bool
    }
    private var root: Entity?
    private var entries: [String: Entry] = [:]
    private var ticker: Task<Void, Never>?
    private var tickerGeneration: UInt64 = 0
    private var reduced = false
    private var suspended = false
    private var effectTime = 0.0

    func reset() {
        tickerGeneration &+= 1
        ticker?.cancel(); ticker = nil
        root?.removeFromParent(); root = nil
        entries.removeAll()
    }

    func setSuspended(_ value: Bool) {
        guard suspended != value else { return }
        suspended = value
        updateTicker()
    }

    func present(_ state: BattleState?, registry: RealityEntityRegistry, reducedMotion: Bool) {
        reduced = reducedMotion
        guard let state, state.phase != .victory, state.phase != .defeat,
              state.phase != .preparing,
              let anchor = registry.entity(for: .enemySpawn),
              let actor = registry.entity(for: .enemyActor) else { reset(); return }
        if root?.parent !== anchor {
            reset()
            let group = Entity(); group.name = "DA_PERSISTENT_COMBAT_STATUS"
            anchor.addChild(group); root = group
        }
        guard let root else { return }
        let b = actor.visualBounds(relativeTo: anchor)
        let center = (b.min + b.max) * 0.5
        let height = max(1, b.max.z - b.min.z)
        let side = min(1.65, max(0.7, (b.max.x - b.min.x) * 0.55))
        let back = SIMD3<Float>(center.x, b.max.y + 0.12, center.z + height * 0.08)
        let front = SIMD3<Float>(center.x, b.min.y - 0.16, center.z)
        let now = effectTime
        var wanted: Set<String> = []
        func add(_ key: String, position: SIMD3<Float>, color: UIColor, urgent: Bool = false, make: () -> Entity?) {
            wanted.insert(key)
            if var existing = entries[key] {
                existing.retiringAt = nil
                existing.destination = nil
                existing.entity.scale = SIMD3(repeating: 1)
                existing.entity.position = position
                entries[key] = existing
                return
            }
            guard let node = make() else { return }
            node.position = position; node.name = "DA_STATUS_" + key
            root.addChild(node)
            node.components.set(OpacityComponent(opacity: reduced ? 0.85 : 0))
            entries[key] = Entry(entity: node, base: position, born: now, urgent: urgent)
        }
        let e = state.expansion
        let deviceSize = min(0.9, max(0.5, height * 0.22))
        if effects?.floor == 8, let intent = state.currentEnemyIntent {
            let focused: Bool
            switch intent {
            case .telegraph, .attack(_, _, true): focused = true
            default: focused = false
            }
            if focused {
                add("focus", position: front + [side * 0.7, -0.05, height * 0.25], color: .cyan) {
                    self.effects?.make(.focusLens, size: deviceSize)
                }
            }
        }
        if e.enemyAmplification != nil || e.flatAmplification > 0 {
            add("amplify", position: back + [side, 0, height * 0.15], color: .orange) {
                self.effects?.make("amplify", size: deviceSize)
            }
        }
        if e.retainsCorrectionBarrier && state.enemy.normalBarrier > 0 {
            add("correction", position: front + [side, 0, height * 0.12], color: .cyan) {
                self.effects?.make(.axisAnchors, size: deviceSize)
            }
        }
        if let value = e.enemyPreservation, value.expiresAfterTurn >= state.turnNumber {
            add("preservation", position: center + [0, 0, -height * 0.12], color: .purple) {
                self.effects?.make(.preservationBand, size: max(height * 0.85, side * 2))
            }
        }
        if let value = e.outputReduction, value.expiresAfterTurn >= state.turnNumber {
            add("outputReduction", position: front + [-side, 0, -height * 0.18], color: .purple) {
                self.effects?.make(.suppressionBand, size: deviceSize)
            }
        }
        if let record = e.copyRecord {
            add("record-\(record.spell.rawValue)-\(record.reused)", position: front + [-side, 0, height * 0.22], color: .purple, urgent: record.reused) {
                let node = Entity()
                let frame = self.effects?.floor == 1
                    ? self.effects?.make(.identityScanner, size: deviceSize)
                    : self.effects?.make("record", size: deviceSize)
                guard let frame else { return nil }
                node.addChild(frame)
                for stroke in SpellCatalog.spell(record.spell).glyph.strokes {
                    let points = stroke.referencePath
                    for i in 1..<points.count {
                        self.line(on: node,
                            from: [Float(points[i-1].x-0.5)*deviceSize*0.48, -0.14, Float(0.5-points[i-1].y)*deviceSize*0.48],
                            to: [Float(points[i].x-0.5)*deviceSize*0.48, -0.14, Float(0.5-points[i].y)*deviceSize*0.48], color: .purple)
                    }
                }
                return node
            }
        }
        if let through = e.mimicProhibitionThroughEnemyTurn, through >= state.turnNumber {
            add("mimicProhibition", position: front + [-side, 0, -height * 0.05], color: .systemPurple) {
                self.effects?.make(.suppressionBand, size: deviceSize)
            }
        }
        if e.lockedSpells.values.contains(where: { $0 >= state.turnNumber }) {
            add("cardSeal", position: front + [side, 0, -height * 0.23], color: .purple) {
                self.effects?.make("seal", size: deviceSize * 0.8)
            }
        }
        let reservations = e.scheduledDamage.sorted { ($0.dueEnemyTurn, $0.id) < ($1.dueEnemyTurn, $1.id) }
        for (index, reservation) in reservations.prefix(3).enumerated() {
            let urgent = reservation.dueEnemyTurn <= state.turnNumber
            let color: UIColor = urgent ? .systemRed : (reservation.wasDelayed ? .cyan : .orange)
            add("reservation-\(reservation.id)-\(reservation.dueEnemyTurn)-\(urgent)",
                position: front + [side, 0, height * 0.3 - Float(index) * deviceSize * 0.72], color: color, urgent: urgent) {
                guard let node = self.effects?.make(urgent ? "execution" : "reservation", size: deviceSize * 0.65) else { return nil }
                if reservation.wasDelayed { self.ring(on: node, radius: deviceSize * 0.38, color: color) }
                return node
            }
        }
        for key in Array(entries.keys) where !wanted.contains(key) {
            guard var entry = entries[key], entry.retiringAt == nil else { continue }
            if reduced { entry.entity.removeFromParent(); entries[key] = nil; continue }
            entry.retiringAt = now
            if key == "amplify", let target = entries.first(where: { wanted.contains($0.key) && $0.key.hasPrefix("reservation-") })?.value {
                entry.destination = target.base
            }
            entries[key] = entry
        }
        updateTicker()
    }

    private func updateTicker() {
        if suspended {
            tickerGeneration &+= 1; ticker?.cancel(); ticker = nil
            return
        }
        if reduced || entries.isEmpty {
            tickerGeneration &+= 1
            ticker?.cancel(); ticker = nil
            for key in Array(entries.keys) {
                guard let entry = entries[key] else { continue }
                if entry.retiringAt != nil { entry.entity.removeFromParent(); entries[key] = nil }
                else { entry.entity.components.set(OpacityComponent(opacity: entry.urgent ? 1 : 0.85)) }
            }
            return
        }
        guard ticker == nil else { return }
        let generation = tickerGeneration
        ticker = Task { @MainActor [weak self] in
            defer {
                if self?.tickerGeneration == generation { self?.ticker = nil }
            }
            var previous = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                guard let self else { return }
                let clock = ProcessInfo.processInfo.systemUptime
                self.effectTime += max(0, clock - previous)
                previous = clock
                let now = self.effectTime
                for key in Array(self.entries.keys) {
                    guard let e = self.entries[key] else { continue }
                    if let retired = e.retiringAt {
                        let t = min(1, Float((now-retired)/0.3))
                        e.entity.components.set(OpacityComponent(opacity: (1-t)*0.85))
                        e.entity.scale = SIMD3(repeating: 1-t*0.4)
                        e.entity.position = e.base + ((e.destination ?? (e.base + SIMD3(0,0,-0.1)))-e.base)*t
                        if t == 1 { e.entity.removeFromParent(); self.entries[key] = nil }
                    } else {
                        let fade = min(1, Float((now-e.born)/0.25))
                        let pulse = Float(sin((now-e.born)*(e.urgent ? 3 : 1.5)))
                        if key == "correction" || key == "preservation" {
                            e.entity.orientation = simd_quatf(angle: Float(now - e.born) * 0.12, axis: [0, 0, 1])
                        }
                        e.entity.components.set(OpacityComponent(opacity: fade * ((e.urgent ? 0.93 : 0.85) + pulse*0.06)))
                    }
                }
                if self.entries.isEmpty { return }
                do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
            }
        }
    }

    private func ring(on node: Entity, radius: Float, color: UIColor) {
        if let mesh = Self.ringMesh(radius: radius) {
            node.addChild(ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: color)]))
            return
        }
        for i in 0..<32 {
            let a = Float(i)*2 * .pi/32, b = Float(i+1)*2 * .pi/32
            line(on: node, from: [cos(a)*radius,0,sin(a)*radius], to: [cos(b)*radius,0,sin(b)*radius], color: color)
        }
    }
    /// One closed tube replaces 32 independently rendered box entities per ring.
    /// Only geometry is shared; opacity and transforms remain local to each status.
    private static func ringMesh(radius: Float) -> MeshResource? {
        if let mesh = ringMeshes[radius] { return mesh }
        let sides = 32, tubeSides = 4
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        for i in 0..<sides {
            let angle = Float(i) * 2 * .pi / Float(sides)
            let radial = SIMD3<Float>(cos(angle), 0, sin(angle))
            for j in 0..<tubeSides {
                let tubeAngle = Float(j) * 2 * .pi / Float(tubeSides)
                let normal = radial * cos(tubeAngle) + SIMD3<Float>(0, sin(tubeAngle), 0)
                positions.append(radial * radius + normal * 0.006)
                normals.append(normal)
                let a = UInt32(i * tubeSides + j)
                let b = UInt32(((i + 1) % sides) * tubeSides + j)
                let c = UInt32(i * tubeSides + (j + 1) % tubeSides)
                let d = UInt32(((i + 1) % sides) * tubeSides + (j + 1) % tubeSides)
                indices.append(contentsOf: [a, c, b, b, c, d])
            }
        }
        var descriptor = MeshDescriptor(name: "CombatStatusRing")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        guard let mesh = try? MeshResource.generate(from: [descriptor]) else { return nil }
        ringMeshes[radius] = mesh
        return mesh
    }
    private func line(on node: Entity, from: SIMD3<Float>, to: SIMD3<Float>, color: UIColor) {
        node.addChild(segment(from: from, to: to, color: color, thickness: 0.012))
    }
    private func segment(from: SIMD3<Float>, to: SIMD3<Float>, color: UIColor, thickness: Float) -> Entity {
        let delta = to-from
        let length = max(0.0001, simd_length(delta))
        let entity = ModelEntity(mesh: Self.segmentMesh, materials: [UnlitMaterial(color: color)])
        entity.scale = [length, thickness, thickness]
        entity.position = (from+to)*0.5
        entity.orientation = simd_quatf(from: [1,0,0], to: delta/length)
        return entity
    }
}
