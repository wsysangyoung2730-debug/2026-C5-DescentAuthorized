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
        case .absoluteSeal: .generalShield
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
    private var enemyAttackTask: Task<Void, Never>?
    private var enemyAttackEntity: Entity?
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
    private var intentShieldClearance: Float?
    private var currentShieldState: RealityShieldState = .none
    private var shieldAuraEntity: Entity?
    private var shieldTransitionTask: Task<Void, Never>?
    private var shieldTransitionGeneration = 0
    var onIntentLayoutChanged: (() -> Void)?

    func projectedIntentFrame(in arView: ARView) -> CGRect? {
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

    func attach(to registry: RealityEntityRegistry) {
        root = registry.root
        enemyAnchor = registry.entity(for: .enemySpawn) ?? registry.root
        enemyActor = registry.entity(for: .enemyActor)
        intentScale = registry.descriptor?.actor?.intentScale ?? 1.15
        intentVerticalOffset = registry.descriptor?.actor?.intentVerticalOffset ?? 0.3
        intentShieldClearance = registry.descriptor?.actor?.intentShieldClearance
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
        intentReducedMotion = reducedMotion
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
        hitGeneration += 1
        hitTasks.values.forEach { $0.cancel() }
        hitTasks.removeAll()
        hitEntities.values.forEach { $0.removeFromParent() }
        hitEntities.removeAll()
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
                shieldTransitionTask?.cancel()
                shieldTransitionTask = nil
                if state == .none {
                    shieldAuraEntity?.removeFromParent()
                    shieldAuraEntity = nil
                    repositionCurrentIntent()
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
                self.repositionCurrentIntent()
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
        repositionCurrentIntent()
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
        let actorSize = actorBounds.max - actorBounds.min
        let barrierBounds = registry.entity(for: role)?.visualBounds(relativeTo: enemyAnchor)
        let barrierSize = barrierBounds.map { $0.max - $0.min } ?? actorSize
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
                    }
                    do {
                        effect.position = start
                        launchFeedback?()
                        if !reducedMotion, self.cameraEntity != nil {
                            effect.scale = SIMD3(repeating: 0.18)
                            // Fast, straight magical bolt; no gravity or ballistic arc.
                            let duration = min(0.19, max(0.12, Double(simd_distance(start, target)) / 85))
                            let began = ProcessInfo.processInfo.systemUptime
                            while true {
                                try Task.checkCancellation()
                                let t = min(1, Float((ProcessInfo.processInfo.systemUptime - began) / duration))
                                let progress = t
                                effect.position = start + (target - start) * progress
                                effect.scale = SIMD3(repeating: 0.18 + 0.24 * progress)
                                if t >= 1 { break }
                                try await Task.sleep(for: .milliseconds(16))
                            }
                        }
                        effect.position = target
                        effect.scale = SIMD3(repeating: 0.48)
                        // Short adhesion follows the actor, then debris falls in room Z-up space.
                        if let actor = self.enemyActor {
                            effect.setParent(actor, preservingWorldTransform: true)
                        }
                        if cue != .shield { impactFeedback?() }
                        self.addImpactAura(to: effect, reducedMotion: reducedMotion)
                        self.playAuthoredAnimation(on: entity)
                        try await Task.sleep(for: .milliseconds(reducedMotion ? 250 : 220))
                        effect.setParent(root, preservingWorldTransform: true)
                        let impactTransform = effect.transform
                        let began = ProcessInfo.processInfo.systemUptime
                        let duration = reducedMotion ? 0.18 : 0.5
                        while true {
                            try Task.checkCancellation()
                            let t = min(1, Float((ProcessInfo.processInfo.systemUptime - began) / duration))
                            if !reducedMotion {
                                effect.position = impactTransform.translation + SIMD3<Float>(0.08 * t, -0.10 * t, -0.7 * t * t)
                                effect.orientation = impactTransform.rotation * simd_quatf(angle: t * 0.35, axis: SIMD3<Float>(1, 0, 0))
                                effect.scale = impactTransform.scale * (1 - 0.25 * t)
                            }
                            effect.components.set(OpacityComponent(opacity: 1 - t))
                            if t >= 1 { break }
                            try await Task.sleep(for: .milliseconds(16))
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
        let baseHeight = bounds.max.z + intentVerticalOffset
        let resolvedHeight: Float
        if let intentShieldClearance, let shieldAuraEntity {
            let shieldTop = shieldAuraEntity.visualBounds(relativeTo: anchor).max.z
            resolvedHeight = max(baseHeight, shieldTop + intentShieldClearance)
        } else {
            resolvedHeight = baseHeight
        }
        return SIMD3(
            (bounds.min.x + bounds.max.x) * 0.5,
            bounds.min.y - 0.35,
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

/// Plays Blender-authored skeletal ranges on the original imported root, so
/// animation binding paths survive actor normalization and scene installation.
@MainActor
final class RealityActorMotionPlayer {
    private struct Manifest: Decodable {
        struct Clip: Decodable { let start: Double; let end: Double; let duration: Double }
        let clips: [String: Clip]
        let initialIdleOffset: Double?
    }
    private weak var root: Entity?
    private weak var visualRoot: Entity?
    private var source: AnimationResource?
    private var manifest: Manifest?
    private var playback: AnimationPlaybackController?
    private var returnTask: Task<Void, Never>?
    private var generation = 0
    private var terminal = false
    private var terminalMotionStarted = false
    private var reduced = false
    private var suspended = false
    private var currentMotion = "idle"

    func install(root: Entity, descriptor: RealityActorDescriptor, bundle: Bundle) throws {
        reset()
        guard let url = bundle.url(forResource: "motion", withExtension: "json",
                                   subdirectory: descriptor.resourceSubdirectory) else {
            throw NSError(domain: "ActorMotion", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "캐릭터 모션 목록이 없습니다."])
        }
        manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
        func animatedEntity(_ entity: Entity) -> Entity? {
            if !entity.availableAnimations.isEmpty { return entity }
            return entity.children.lazy.compactMap { animatedEntity($0) }.first
        }
        guard let animated = animatedEntity(root), let animation = animated.availableAnimations.first else {
            throw NSError(domain: "ActorMotion", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "캐릭터의 관절 애니메이션을 읽지 못했습니다."])
        }
        self.root = animated
        self.visualRoot = root
        root.components.set(OpacityComponent(opacity: 1))
        source = animation
        play("idle")
    }

    func prepareEncounter() {
        visualRoot?.isEnabled = true
        terminal = false
        terminalMotionStarted = false
        visualRoot?.components.set(OpacityComponent(opacity: 1))
        play("idle")
    }

    func setReducedMotion(_ value: Bool) {
        guard reduced != value else { return }
        reduced = value
        if value {
            stop()
            if terminal { terminalMotionStarted = false; play("death") }
        }
        else if terminal && !terminalMotionStarted { play("death") }
        else if !terminal { play("idle") }
    }

    func setSuspended(_ value: Bool) {
        guard suspended != value else { return }
        suspended = value
        if value {
            playback?.pause()
        } else if playback != nil {
            playback?.resume()
        } else if terminal {
            play("death")
        } else {
            play("idle")
        }
    }

    func present(_ events: [DemoSessionEvent], state: BattleState?) {
        if state?.phase == .victory { play("death"); return }
        var motion: String?
        for event in events {
            guard case let .combat(event) = event else { continue }
            switch event {
            case .victory: motion = "death"
            case let .enemyActionStarted(action):
                let cues = GameFeedbackMapper().cues(for: [.combat(.enemyActionStarted(action))])
                if let attack = cues.first(where: { if case .enemyAttack = $0 { return true }; return false }),
                   case let .enemyAttack(strong) = attack {
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
        guard !terminal || name == "death" else { return }
        if name == "death" {
            guard !terminalMotionStarted else { return }
            terminal = true
        }
        guard !suspended, (!reduced || name == "death"),
              let root, let source, let clip = manifest?.clips[name] else { return }
        stop()
        currentMotion = name
        if name == "death" { terminalMotionStarted = true }
        do {
            let view = AnimationView(source: source.definition, name: name,
                fillMode: name == "death" ? .forwards : [],
                trimStart: reduced ? max(clip.start, clip.end - 1.0 / 30) : clip.start,
                trimEnd: clip.end)
            let animation = try AnimationResource.generate(with: view)
            playback = root.playAnimation(name == "idle" ? animation.repeat() : animation,
                                          transitionDuration: 0.12, startsPaused: false)
            if name == "death" {
                let token = generation
                returnTask = Task { @MainActor [weak self] in
                    var elapsed = 0.0
                    let pose = self?.reduced == true ? 0 : clip.duration
                    let fade = self?.reduced == true ? 0.15 : CombatPresentationTimeline.dissolveDuration
                    while elapsed < pose + fade {
                        do { try await Task.sleep(for: .milliseconds(20)) } catch { return }
                        guard let self, self.generation == token else { return }
                        if self.suspended { continue }
                        elapsed += 0.02
                        let progress = max(0, min(1, (elapsed - pose) / fade))
                        self.visualRoot?.components.set(OpacityComponent(opacity: Float(1 - progress)))
                    }
                    guard let self, self.generation == token else { return }
                    self.visualRoot?.components.set(OpacityComponent(opacity: 0))
                    self.visualRoot?.isEnabled = false
                }
                return
            }
            let hasVariation = manifest?.clips["idleVariant"] != nil
            if name == "idle", !hasVariation { return }
            let wait = name == "idle" ? clip.duration * 2 + (manifest?.initialIdleOffset ?? 0) : clip.duration
            let next = name == "idle" ? "idleVariant" : "idle"
            let token = generation
            returnTask = Task { @MainActor [weak self] in
                var remaining = wait
                while remaining > 0 {
                    do { try await Task.sleep(for: .milliseconds(20)) } catch { return }
                    guard let self, self.generation == token else { return }
                    if !self.suspended { remaining -= 0.02 }
                }
                guard let self, self.generation == token else { return }
                self.play(next)
            }
        } catch {
            // A malformed clip does not leave a previous attack looping.
            playback = nil
        }
    }

    private func stop() {
        generation += 1
        returnTask?.cancel(); returnTask = nil
        playback?.stop(); playback = nil
    }

    func reset() {
        stop(); visualRoot?.components.set(OpacityComponent(opacity: 1))
        root = nil; visualRoot = nil; source = nil; manifest = nil
        terminal = false; terminalMotionStarted = false; reduced = false; suspended = false
        currentMotion = "idle"
    }
}

// Enemy strikes travel from the attacking hand/core toward the player, in room space.
extension RealityCombatVFXRenderer {
    func presentEnemyAction(_ events: [DemoSessionEvent], state: BattleState?, reducedMotion: Bool) {
        guard let action = events.compactMap({ event -> EnemyAction? in
            if case let .combat(.enemyActionStarted(action)) = event { return action }
            return nil
        }).first else { return }
        let attack = GameFeedbackMapper().cues(for: [.combat(.enemyActionStarted(action))])
            .compactMap { cue -> Bool? in
                if case let .enemyAttack(strong) = cue { return strong }
                return nil
            }.first
        let scheduled = state?.expansion.scheduledDamage.contains {
            $0.dueEnemyTurn <= (state?.turnNumber ?? 0)
        } ?? false
        guard attack != nil || scheduled else { return }
        enemyAttackTask?.cancel()
        enemyAttackEntity?.removeFromParent()
        guard !reducedMotion, let root, let cameraEntity,
              let bounds = enemyBounds(relativeTo: root) else { return }

        let strong = attack ?? false
        let color: UIColor
        if scheduled { color = UIColor(red: 1, green: 0.52, blue: 0.12, alpha: 1) }
        else if strong { color = UIColor(red: 1, green: 0.24, blue: 0.18, alpha: 1) }
        else { color = UIColor(red: 0.70, green: 0.42, blue: 1, alpha: 1) }
        var material = UnlitMaterial(color: color)
        material.blending = .transparent(opacity: .init(scale: 0.85))
        let strike = Entity()
        strike.name = "DA_ENEMY_STRIKE"
        let core = ModelEntity(mesh: .generateSphere(radius: 1), materials: [material])
        core.scale = SIMD3(0.055, 0.055, strong ? 0.24 : 0.17)
        strike.addChild(core)
        var trail: [ModelEntity] = []
        for index in 0..<4 {
            let spark = ModelEntity(mesh: .generateSphere(radius: 1), materials: [material])
            let radius: Float = 0.045 - Float(index) * 0.007
            spark.scale = SIMD3(radius, radius, 0.10)
            spark.components.set(OpacityComponent(opacity: 0.40 - Float(index) * 0.07))
            strike.addChild(spark)
            trail.append(spark)
        }
        let start = SIMD3<Float>(
            bounds.center.x + bounds.extents.x * 0.20,
            bounds.min.y - 0.12,
            bounds.min.z + bounds.extents.z * 0.62
        )
        let end = root.convert(position: SIMD3<Float>(0.08, -0.08, -0.48), from: cameraEntity)
        let direction = simd_normalize(end - start)
        strike.orientation = simd_quatf(from: SIMD3<Float>(0, 0, 1), to: direction)
        strike.position = start
        root.addChild(strike)
        enemyAttackEntity = strike
        let impact = strong ? 0.62 : 0.46
        let flight = 0.16
        let launch = impact - flight
        let generation = hitGeneration
        enemyAttackTask = Task { @MainActor [weak self, weak strike] in
            guard let self, let strike else { return }
            defer {
                strike.removeFromParent()
                if self.enemyAttackEntity === strike { self.enemyAttackEntity = nil }
            }
            var elapsed = 0.0
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
                if elapsed < launch {
                    let charge = Float(elapsed / launch)
                    core.scale = SIMD3(repeating: 0.035 + charge * 0.065)
                    trail.forEach { $0.isEnabled = false }
                } else {
                    let t = Float(min(1, (elapsed - launch) / flight))
                    strike.position = start + (end - start) * t
                    core.scale = SIMD3(0.055, 0.055, strong ? 0.24 : 0.17)
                    for (index, spark) in trail.enumerated() {
                        spark.isEnabled = true
                        spark.position.z = -Float(index + 1) * 0.15
                    }
                    // Disappear just in front of the camera instead of clipping through it.
                    strike.components.set(OpacityComponent(opacity: min(1, (1 - t) * 7)))
                }
            }
        }
    }
}

// Shared by all intent types; positions/directions are in the room's Z-up space.
extension RealityCombatVFXRenderer {
    func setIntentEffectsSuspended(_ suspended: Bool) {
        intentEffectsSuspended = suspended
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
        guard registry.descriptor?.sceneID.isExpansion == true,
              let state, state.phase != .victory, state.phase != .defeat,
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
        let now = ProcessInfo.processInfo.systemUptime
        var wanted: Set<String> = []
        func add(_ key: String, position: SIMD3<Float>, color: UIColor, urgent: Bool = false, make: () -> Entity) {
            wanted.insert(key)
            if var existing = entries[key] {
                existing.retiringAt = nil
                existing.destination = nil
                existing.entity.scale = SIMD3(repeating: 1)
                existing.entity.position = position
                entries[key] = existing
                return
            }
            let node = make(); node.position = position; node.name = "DA_STATUS_" + key
            root.addChild(node)
            node.components.set(OpacityComponent(opacity: reduced ? 0.55 : 0))
            entries[key] = Entry(entity: node, base: position, born: now, urgent: urgent)
        }
        let e = state.expansion
        if e.enemyAmplification != nil {
            add("amplify", position: back, color: .orange) {
                let node = Entity()
                self.ring(on: node, radius: 0.56, color: .orange)
                self.ring(on: node, radius: 0.7, color: .orange)
                for x: Float in [-0.3, 0, 0.3] {
                    self.line(on: node, from: [x,0,-0.3], to: [x,0,0.3], color: .orange)
                    self.line(on: node, from: [x-0.08,0,0.18], to: [x,0,0.3], color: .orange)
                }
                return node
            }
        }
        if e.retainsCorrectionBarrier && state.enemy.normalBarrier > 0 {
            add("correction", position: front, color: .cyan) {
                let node = Entity()
                for i in 0..<4 {
                    let a = Float(i) * .pi / 2
                    let v = SIMD3<Float>(cos(a),0,sin(a))
                    self.line(on: node, from: v * 0.65, to: v * 0.18, color: .cyan)
                }
                return node
            }
        }
        if let value = e.enemyPreservation, value.expiresAfterTurn >= state.turnNumber {
            add("preservation", position: front, color: .purple) {
                let node = Entity()
                for i in 0..<8 {
                    let a = Float(i) * .pi / 4
                    let piece = self.segment(from: [0,0,-0.08], to: [0,0,0.08], color: .init(red: 0.8, green: 0.7, blue: 0.95, alpha: 1), thickness: 0.055)
                    piece.position = [cos(a)*0.52,0,sin(a)*0.7]
                    piece.orientation = simd_quatf(angle: -a, axis: [0,1,0])
                    node.addChild(piece)
                }
                return node
            }
        }
        if let value = e.outputReduction, value.expiresAfterTurn >= state.turnNumber {
            add("outputReduction", position: front + [0,0,0.25], color: .cyan) {
                let node = Entity()
                self.ring(on: node, radius: 0.3, color: .cyan)
                self.line(on: node, from: [-0.24,0,0.24], to: [0.24,0,-0.24], color: .cyan)
                return node
            }
        }
        if let record = e.copyRecord {
            add("record-\(record.spell.rawValue)-\(record.reused)", position: front + [-side,0,height*0.22], color: .purple, urgent: record.reused) {
                let node = Entity()
                self.ring(on: node, radius: 0.33, color: .purple)
                for stroke in SpellCatalog.spell(record.spell).glyph.strokes {
                    let points = stroke.referencePath
                    for i in 1..<points.count {
                        self.line(on: node, from: [Float(points[i-1].x-0.5)*0.45,0,Float(0.5-points[i-1].y)*0.45], to: [Float(points[i].x-0.5)*0.45,0,Float(0.5-points[i].y)*0.45], color: .purple)
                    }
                }
                return node
            }
        }
        if let through = e.mimicProhibitionThroughEnemyTurn, through >= state.turnNumber {
            add("mimicProhibition", position: front + [-side,0,height*0.22], color: .systemPurple) {
                let node = Entity()
                self.ring(on: node, radius: 0.3, color: .systemPurple)
                self.line(on: node, from: [-0.23,0,-0.23], to: [0.23,0,0.23], color: .systemPurple)
                self.line(on: node, from: [-0.23,0,0.23], to: [0.23,0,-0.23], color: .systemPurple)
                return node
            }
        }
        let reservations = e.scheduledDamage.sorted { ($0.dueEnemyTurn, $0.id) < ($1.dueEnemyTurn, $1.id) }
        for (index, reservation) in reservations.prefix(3).enumerated() {
            let urgent = reservation.dueEnemyTurn <= state.turnNumber
            let color: UIColor = urgent ? .systemRed : (reservation.wasDelayed ? .cyan : .orange)
            add("reservation-\(reservation.id)-\(reservation.dueEnemyTurn)-\(urgent)", position: front + [side,0,height*0.25-Float(index)*0.48], color: color, urgent: urgent) {
                let node = Entity()
                let points: [SIMD3<Float>] = [[-0.17,0,0.2],[0.17,0,0.2],[-0.17,0,-0.2],[0.17,0,-0.2],[-0.17,0,0.2]]
                for i in 1..<points.count { self.line(on: node, from: points[i-1], to: points[i], color: color) }
                if reservation.wasDelayed { self.ring(on: node, radius: 0.25, color: color) }
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
        if reduced || suspended || entries.isEmpty {
            tickerGeneration &+= 1
            ticker?.cancel(); ticker = nil
            for key in Array(entries.keys) {
                guard let entry = entries[key] else { continue }
                if entry.retiringAt != nil { entry.entity.removeFromParent(); entries[key] = nil }
                else { entry.entity.components.set(OpacityComponent(opacity: entry.urgent ? 0.7 : 0.5)) }
            }
            return
        }
        guard ticker == nil else { return }
        let generation = tickerGeneration
        ticker = Task { @MainActor [weak self] in
            defer {
                if self?.tickerGeneration == generation { self?.ticker = nil }
            }
            while !Task.isCancelled {
                guard let self else { return }
                let now = ProcessInfo.processInfo.systemUptime
                for key in Array(self.entries.keys) {
                    guard let e = self.entries[key] else { continue }
                    if let retired = e.retiringAt {
                        let t = min(1, Float((now-retired)/0.3))
                        e.entity.components.set(OpacityComponent(opacity: (1-t)*0.5))
                        e.entity.scale = SIMD3(repeating: 1-t*0.4)
                        e.entity.position = e.base + ((e.destination ?? (e.base + SIMD3(0,0,-0.1)))-e.base)*t
                        if t == 1 { e.entity.removeFromParent(); self.entries[key] = nil }
                    } else {
                        let fade = min(1, Float((now-e.born)/0.25))
                        let pulse = Float(sin((now-e.born)*(e.urgent ? 3 : 1.5)))
                        e.entity.components.set(OpacityComponent(opacity: fade * ((e.urgent ? 0.65 : 0.42) + pulse*0.08)))
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
