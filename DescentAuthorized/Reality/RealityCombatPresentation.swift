import Combine
import Foundation
import RealityKit

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
    private weak var root: Entity?
    private weak var enemyAnchor: Entity?
    private var currentIntentEntity: Entity?
    private var loadCancellables: Set<AnyCancellable> = []
    private var intentGeneration = 0

    func attach(to registry: RealityEntityRegistry) {
        root = registry.root
        enemyAnchor = registry.entity(for: .enemySpawn) ?? registry.root
    }

    func present(
        _ cues: [RealityCombatCue],
        registry: RealityEntityRegistry,
        reducedMotion: Bool,
        bundle: Bundle = .main
    ) {
        attach(to: registry)
        for cue in cues {
            switch cue {
            case let .intent(intent):
                showIntent(intent, reducedMotion: reducedMotion, bundle: bundle)
            case let .hit(hit):
                showHit(hit, reducedMotion: reducedMotion, bundle: bundle)
            case let .shield(state):
                applyShield(state, registry: registry)
            case .clearIntent:
                clearIntent()
            }
        }
    }

    func reset() {
        loadCancellables.forEach { $0.cancel() }
        loadCancellables.removeAll()
        currentIntentEntity?.removeFromParent()
        currentIntentEntity = nil
        root = nil
        enemyAnchor = nil
        intentGeneration += 1
    }

    private func applyShield(_ state: RealityShieldState, registry: RealityEntityRegistry) {
        registry.setEnabled(state == .general, for: .generalShield)
        registry.setEnabled(state == .absolute, for: .absoluteShield)
    }

    private func showIntent(
        _ cue: RealityEnemyIntentCue,
        reducedMotion: Bool,
        bundle: Bundle
    ) {
        intentGeneration += 1
        let generation = intentGeneration
        currentIntentEntity?.removeFromParent()
        currentIntentEntity = nil

        load(assetID(for: cue), bundle: bundle) { [weak self] entity in
            guard let self, generation == self.intentGeneration, let enemyAnchor = self.enemyAnchor else { return }
            entity.name = "DA_RUNTIME_ENEMY_INTENT"
            entity.position.y += 2.15
            self.currentIntentEntity = entity
            enemyAnchor.addChild(entity)
            self.playAuthoredAnimation(on: entity)
            self.animateAppearance(entity, reducedMotion: reducedMotion)
        }
    }

    private func showHit(
        _ cue: RealityHitCue,
        reducedMotion: Bool,
        bundle: Bundle
    ) {
        load(assetID(for: cue), bundle: bundle) { [weak self] entity in
            guard let self, let enemyAnchor = self.enemyAnchor else { return }
            entity.name = "DA_RUNTIME_ENEMY_HIT"
            enemyAnchor.addChild(entity)
            self.playAuthoredAnimation(on: entity)
            self.animateAppearance(entity, reducedMotion: reducedMotion)

            Task { @MainActor [weak entity] in
                try? await Task.sleep(for: .milliseconds(reducedMotion ? 450 : 950))
                entity?.removeFromParent()
            }
        }
    }

    private func clearIntent() {
        intentGeneration += 1
        currentIntentEntity?.removeFromParent()
        currentIntentEntity = nil
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
        completion: @escaping @MainActor (Entity) -> Void
    ) {
        guard let resource = Self.resource(for: assetID),
              let url = bundle.url(
                forResource: resource.name,
                withExtension: "usdc",
                subdirectory: resource.subdirectory
              ) else { return }

        Entity.loadAsync(contentsOf: url)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { _ in }, receiveValue: completion)
            .store(in: &loadCancellables)
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

    private static func resource(for assetID: GameAssetID) -> (name: String, subdirectory: String)? {
        switch assetID {
        case .hitNormal:
            (assetID.rawValue, "Reality/VFX/Combat/HitNormal")
        case .hitHeavy:
            (assetID.rawValue, "Reality/VFX/Combat/HitHeavy")
        case .hitCritical:
            (assetID.rawValue, "Reality/VFX/Combat/HitCritical")
        case .hitShield:
            (assetID.rawValue, "Reality/VFX/Combat/HitShield")
        case .intentAttack:
            (assetID.rawValue, "Reality/VFX/Combat/IntentAttack")
        case .intentHeavyAttack:
            (assetID.rawValue, "Reality/VFX/Combat/IntentHeavyAttack")
        case .intentShield:
            (assetID.rawValue, "Reality/VFX/Combat/IntentShield")
        case .intentAbsoluteShield:
            (assetID.rawValue, "Reality/VFX/Combat/IntentAbsoluteShield")
        default:
            nil
        }
    }
}
