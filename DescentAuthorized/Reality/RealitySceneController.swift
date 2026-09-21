import Combine
import Foundation
import RealityKit
import UIKit
import ImageIO
import os

struct BattleCameraInteractionConfiguration: Equatable, Sendable {
    let maximumYaw: Float
    let maximumUpwardPitch: Float
    let maximumDownwardPitch: Float
    let yawRadiansPerViewport: Float
    let pitchRadiansPerViewport: Float
    let minimumFieldOfViewScale: Float
    let maximumFieldOfViewScale: Float

    static let standard = BattleCameraInteractionConfiguration(
        maximumYaw: .pi * 60 / 180,
        maximumUpwardPitch: .pi * 25 / 180,
        maximumDownwardPitch: .pi * 25 / 180,
        yawRadiansPerViewport: .pi * 120 / 180,
        pitchRadiansPerViewport: .pi * 50 / 180,
        minimumFieldOfViewScale: 0.85,
        maximumFieldOfViewScale: 1.10
    )

    static let floor10Investigation = investigation(maximumYawDegrees: 24)
    static let floor8Investigation = investigation(maximumYawDegrees: 28)
    static let floor9Investigation = investigation(maximumYawDegrees: 65)

    /// Creates a floor investigation camera with a shared drag response while
    /// allowing each scene to expose the horizontal range its clues require.
    static func investigation(maximumYawDegrees: Float) -> Self {
        BattleCameraInteractionConfiguration(
            maximumYaw: .pi * maximumYawDegrees / 180,
            maximumUpwardPitch: .pi * 10 / 180,
            maximumDownwardPitch: .pi * 12 / 180,
            yawRadiansPerViewport: .pi * 48 / 180,
            pitchRadiansPerViewport: .pi * 22 / 180,
            minimumFieldOfViewScale: 1,
            maximumFieldOfViewScale: 1
        )
    }
}

struct RealityProjectedInvestigationAnchor: Equatable, Sendable {
    let point: CGPoint
}

enum Floor10OpeningCameraFocus: Equatable, Sendable {
    case rising
    case trainingTarget
    case surroundingDesk(Int)
    case damagedRoom
    case lockedDoor
    case settled
}

@MainActor
final class RealitySceneController: ObservableObject {
    private struct AuthoredCameraSnapshot {
        let transformMatrix: simd_float4x4
        let camera: PerspectiveCameraComponent
    }

    private struct InvestigationAnchorDefinition {
        let id: String
        let entityName: String
        let normalizedPosition: SIMD3<Float>
    }

    enum LoadState: Equatable {
        case idle
        case loading(FloorSceneID)
        case ready(FloorSceneID)
        case failed(FloorSceneID, String)
    }

    @Published private(set) var loadState: LoadState = .idle
    @Published private(set) var missingEntityRoles: [RealityEntityRole] = []
    @Published private(set) var projectedMagicBoard: RealityProjectedBoard?
    @Published private(set) var projectedEnemyIntentFrame: CGRect?
    @Published private(set) var projectedInvestigationAnchors: [String: RealityProjectedInvestigationAnchor] = [:]
    @Published private(set) var cameraFadeOpacity: Double = 0
    @Published private(set) var isCameraTransitioning = false
    @Published private(set) var isBattleCameraInteractionEnabled = false
    @Published private(set) var isBattleCameraAdjusted = false
    @Published private(set) var isDescentFailurePresentationActive = false
    @Published private(set) var loadingProgress: Double = 0

    @Published private(set) var isRewardAppearanceComplete = false
    private var rewardAppearanceStartTask: Task<Void, Never>?

    let registry = RealityEntityRegistry()

    private weak var arView: ARView?
    private var graphicsQuality: GraphicsQuality = .medium
    private var appliedGraphicsQuality: GraphicsQuality?
    private weak var graphicsQualityView: ARView?
    private var sceneAnchor: AnchorEntity?
    private var cameraEntity: PerspectiveCamera?
    private var loadCancellable: AnyCancellable?
    private var actorLoadCancellable: AnyCancellable?
    private var environmentTask: Task<Void, Never>?
    private var loadStartedAt = Date()
    private var actorStartedAt = Date()
    private static let loadLog = Logger(subsystem: "com.wsysangyoung.DescentAuthorized", category: "SceneLoading")
    private var cameraTransitionTask: Task<Void, Never>?
    private var battleCameraImpactTask: Task<Void, Never>?
    private let actorMotion = RealityActorMotionPlayer()
    private var enemyPreviewRevealTask: Task<Void, Never>?
    private var investigationAnchorEntities: [String: Entity] = [:]
    private var isProjectionRefreshScheduled = false
    private weak var revealingEnemyPreviewActor: Entity?
    private var enemyPreviewFinalTransform: Transform?
    private var sceneLoadGeneration: UInt64 = 0
    private var cameraTransitionGeneration: UInt64 = 0
    private var battleCameraImpactGeneration: UInt64 = 0
    private var descentCameraEffectGeneration: UInt64 = 0
    private var floor10OpeningCameraGeneration: UInt64 = 0
    private var enemyPreviewRevealGeneration: UInt64 = 0
    private var requestedSceneID: FloorSceneID?
    private var requestedCameraPreset: RealityCameraPreset = .main
    private var activeCameraName: String?
    private var pendingCameraName: String?
    private var authoredCameraSnapshots: [String: AuthoredCameraSnapshot] = [:]
    private var battleCameraYaw: Float = 0
    private var battleCameraPitch: Float = 0
    private var battleCameraFieldOfViewScale: Float = 1
    private var battleCameraLookStartYaw: Float = 0
    private var battleCameraLookStartPitch: Float = 0
    private var battleCameraZoomStartFieldOfViewScale: Float = 1
    private var requestedErasureZones: [ErasureZone] = []
    private var requestedBattleState: BattleState?
    private var requestedReducedMotion = false
    private var requestedEnemyPreviewVisibility = true
    private var requestedDescentState: RealityDescentPresentationState = .inactive
    private var requestedRewardState: RealityRewardPresentationState = .inactive
    private var pendingCombatCues: [RealityCombatCue] = []
    private let erasureZoneRenderer = RealityErasureZoneRenderer()
    private let combatVFXRenderer = RealityCombatVFXRenderer()
    private let progressionVFXRenderer = RealityProgressionVFXRenderer()
    private let observatoryAmbientMotion = ObservatoryAmbientMotion()

    func attach(to arView: ARView) {
        combatVFXRenderer.onIntentLayoutChanged = { [weak self] in
            self?.scheduleBoardProjectionRefresh()
        }
        guard self.arView !== arView else {
            scheduleBoardProjectionRefresh()
            return
        }

        if let sceneAnchor {
            self.arView?.scene.removeAnchor(sceneAnchor)
            arView.scene.addAnchor(sceneAnchor)
        }
        self.arView = arView
        scheduleBoardProjectionRefresh()
    }

    func load(sceneID: FloorSceneID, cameraPreset: RealityCameraPreset, bundle: Bundle = .main) {
        requestedCameraPreset = cameraPreset
        if requestedSceneID == sceneID {
            switch loadState {
            case .loading:
                return
            case .ready:
                transitionCamera(to: cameraPreset)
                return
            default:
                break
            }
        }

        guard let arView else { return }
        let descriptor = RealitySceneDescriptor.descriptor(for: sceneID)
        guard let url = bundle.url(
            forResource: graphicsQuality.resourceName(for: sceneID),
            withExtension: "usdc",
            subdirectory: descriptor.resourceSubdirectory
        ) else {
            fail(sceneID: sceneID, message: "3D 장면 파일을 찾을 수 없습니다: \(descriptor.resourceName).usdc")
            return
        }

        unload()
        requestedSceneID = sceneID
        requestedCameraPreset = cameraPreset
        loadState = .loading(sceneID)
        loadingProgress = 0.12
        let loadGeneration = sceneLoadGeneration
        loadingProgress = 0.2
        loadStartedAt = Date()
        Self.loadLog.notice("room.begin \(sceneID.rawValue, privacy: .public) quality=\(self.graphicsQuality.rawValue, privacy: .public)")
        loadCancellable = PreparedRealityAssets.shared.takeRoom(url: url)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    guard
                        let self,
                        self.sceneLoadGeneration == loadGeneration,
                        self.requestedSceneID == sceneID,
                        case let .failure(error) = completion
                    else { return }
                    self.fail(sceneID: sceneID, message: error.localizedDescription)
                },
                receiveValue: { [weak self] root in
                    guard
                        let self,
                        let arView = self.arView,
                        self.sceneLoadGeneration == loadGeneration,
                        self.requestedSceneID == sceneID
                    else { return }
                    Self.loadLog.notice("room.decoded seconds=\(Date().timeIntervalSince(self.loadStartedAt))")
                    self.loadingProgress = 0.72
                    self.install(root: root, descriptor: descriptor, in: arView, bundle: bundle)
                }
            )
    }

    func applyCameraPreset(_ preset: RealityCameraPreset) {
        requestedCameraPreset = preset
        transitionCamera(to: preset)
    }

    func prepareFloor10FallenCamera(reducedMotion: Bool) {
        guard requestedSceneID == .floor10ClosedOffice,
              requestedCameraPreset == .tutorial,
              let activeCameraName,
              let snapshot = authoredCameraSnapshots[activeCameraName],
              let cameraEntity else { return }

        floor10OpeningCameraGeneration &+= 1
        cameraEntity.stopAllAnimations(recursive: false)
        let fallen = floor10OpeningTransform(
            from: snapshot,
            yaw: -0.12,
            pitch: 0.2,
            roll: -0.28,
            verticalOffset: reducedMotion ? -0.18 : -0.72,
            forwardOffset: -0.08
        )
        cameraEntity.setTransformMatrix(fallen.matrix, relativeTo: nil)
        scheduleBoardProjectionRefresh()
    }

    func restoreFloor10OpeningCamera() {
        floor10OpeningCameraGeneration &+= 1
        guard requestedSceneID == .floor10ClosedOffice,
              let activeCameraName,
              let snapshot = authoredCameraSnapshots[activeCameraName],
              let cameraEntity else { return }
        cameraEntity.stopAllAnimations(recursive: false)
        cameraEntity.setTransformMatrix(snapshot.transformMatrix, relativeTo: nil)
        cameraEntity.camera = snapshot.camera
        scheduleBoardProjectionRefresh()
    }

    func playFloor10OpeningCamera(
        reducedMotion: Bool,
        onFocus: @escaping @MainActor (Floor10OpeningCameraFocus) -> Void
    ) async {
        guard requestedSceneID == .floor10ClosedOffice,
              requestedCameraPreset == .tutorial,
              let activeCameraName,
              let snapshot = authoredCameraSnapshots[activeCameraName],
              let cameraEntity else { return }

        floor10OpeningCameraGeneration &+= 1
        let generation = floor10OpeningCameraGeneration
        let movementDuration = reducedMotion ? 0.01 : 0.72
        let holdDuration = reducedMotion ? 0.04 : 1.05

        @MainActor
        func move(
            focus: Floor10OpeningCameraFocus,
            yaw: Float = 0,
            pitch: Float = 0,
            roll: Float = 0,
            verticalOffset: Float = 0,
            forwardOffset: Float = 0
        ) async -> Bool {
            guard generation == floor10OpeningCameraGeneration,
                  !Task.isCancelled else { return false }
            onFocus(focus)
            let transform = floor10OpeningTransform(
                from: snapshot,
                yaw: yaw,
                pitch: pitch,
                roll: roll,
                verticalOffset: verticalOffset,
                forwardOffset: forwardOffset
            )
            cameraEntity.move(
                to: transform,
                relativeTo: nil,
                duration: movementDuration,
                timingFunction: .easeInOut
            )
            try? await Task.sleep(for: .seconds(movementDuration + holdDuration))
            return generation == floor10OpeningCameraGeneration && !Task.isCancelled
        }

        guard await move(focus: .rising) else { return }
        guard await move(focus: .trainingTarget, yaw: -0.34, pitch: -0.04) else { return }
        guard await move(focus: .surroundingDesk(1), yaw: 0.28, pitch: 0.05) else { return }
        guard await move(focus: .surroundingDesk(2), yaw: -0.08, pitch: 0.1) else { return }
        guard await move(focus: .damagedRoom, yaw: 0.16, pitch: -0.14) else { return }
        guard await move(focus: .lockedDoor, yaw: 0.02, forwardOffset: 0.34) else { return }
        guard await move(focus: .settled) else { return }

        cameraEntity.stopAllAnimations(recursive: false)
        cameraEntity.setTransformMatrix(snapshot.transformMatrix, relativeTo: nil)
        cameraEntity.camera = snapshot.camera
        scheduleBoardProjectionRefresh()
    }

    func setBattleCameraInteractionEnabled(_ isEnabled: Bool) {
        guard isBattleCameraInteractionEnabled != isEnabled else { return }
        isBattleCameraInteractionEnabled = isEnabled
        if !isEnabled {
            resetBattleCamera(animated: false)
        }
    }

    func setLimitedCameraInteractionEnabled(_ isEnabled: Bool) {
        setBattleCameraInteractionEnabled(isEnabled)
    }

    func setEnemyPreviewVisible(_ isVisible: Bool) {
        cancelEnemyPreviewReveal(restoreActor: true)
        requestedEnemyPreviewVisibility = isVisible
        registry.setEnabled(isVisible, for: .enemyActor)
    }

    func revealEnemyPreview(reducedMotion: Bool) {
        requestedEnemyPreviewVisibility = true
        cancelEnemyPreviewReveal(restoreActor: true)

        guard let actor = registry.entity(for: .enemyActor) else {
            registry.setEnabled(true, for: .enemyActor)
            return
        }
        guard !reducedMotion else {
            actor.components.set(OpacityComponent(opacity: 1))
            registry.setEnabled(true, for: .enemyActor)
            return
        }

        enemyPreviewRevealGeneration &+= 1
        let generation = enemyPreviewRevealGeneration
        let finalTransform = actor.transform
        revealingEnemyPreviewActor = actor
        enemyPreviewFinalTransform = finalTransform
        var concealedTransform = finalTransform
        concealedTransform.scale *= 0.96

        actor.stopAllAnimations(recursive: false)
        actor.transform = concealedTransform
        actor.components.set(OpacityComponent(opacity: 0))
        registry.setEnabled(true, for: .enemyActor)
        actor.move(
            to: finalTransform,
            relativeTo: actor.parent,
            duration: 0.72,
            timingFunction: .easeInOut
        )

        let opacitySteps: [Float]
        let stepDuration: Duration
        if requestedSceneID == .floor08ResidueIsolation {
            // 잔류체는 신호가 끊겼다 이어지듯 잠깐 흔들린 뒤 응집된다.
            opacitySteps = [0.08, 0.2, 0.11, 0.34, 0.28, 0.52, 0.68, 0.84, 1]
            stepDuration = .milliseconds(72)
        } else {
            opacitySteps = [0.08, 0.18, 0.31, 0.46, 0.62, 0.78, 0.91, 1]
            stepDuration = .milliseconds(82)
        }

        enemyPreviewRevealTask = Task { @MainActor [weak self, weak actor] in
            guard let self, let actor else { return }
            for opacity in opacitySteps {
                do {
                    try await Task.sleep(for: stepDuration)
                } catch {
                    return
                }
                guard generation == self.enemyPreviewRevealGeneration else { return }
                actor.components.set(OpacityComponent(opacity: opacity))
            }
            guard generation == self.enemyPreviewRevealGeneration else { return }
            actor.transform = finalTransform
            self.revealingEnemyPreviewActor = nil
            self.enemyPreviewFinalTransform = nil
            self.enemyPreviewRevealTask = nil
        }
    }

    func centerAndLockEntranceCamera(
        previewYaw: Float,
        reducedMotion: Bool,
        completion: @escaping @MainActor () -> Void
    ) {
        isBattleCameraInteractionEnabled = false
        cancelBattleCameraImpact(restoreCamera: false)
        clearBattleCameraAdjustmentState()

        guard [.main, .battle, .tutorial].contains(requestedCameraPreset),
              let activeCameraName,
              let snapshot = authoredCameraSnapshots[activeCameraName],
              let cameraEntity else {
            completion()
            return
        }

        let targetMatrix = adjustedBattleCameraMatrix(
            from: snapshot,
            transientYaw: previewYaw
        )
        cameraEntity.stopAllAnimations(recursive: false)
        cameraEntity.camera = snapshot.camera

        if reducedMotion {
            cameraEntity.setTransformMatrix(targetMatrix, relativeTo: nil)
        } else {
            cameraEntity.move(
                to: Transform(matrix: targetMatrix),
                relativeTo: nil,
                duration: 0.28,
                timingFunction: .easeInOut
            )
        }
        isBattleCameraAdjusted = abs(previewYaw) > 0.001
        scheduleBoardProjectionRefresh()

        guard !reducedMotion else {
            completion()
            return
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(280))
            completion()
        }
    }

    func beginBattleCameraLook() {
        guard canAdjustBattleCamera else { return }
        cancelBattleCameraImpact(restoreCamera: true)
        battleCameraLookStartYaw = battleCameraYaw
        battleCameraLookStartPitch = battleCameraPitch
    }

    func updateBattleCameraLook(
        translation: CGSize,
        viewportSize: CGSize,
        configuration: BattleCameraInteractionConfiguration = .standard
    ) {
        guard canAdjustBattleCamera,
              viewportSize.width > 0,
              viewportSize.height > 0 else { return }

        let horizontalProgress = Float(translation.width / viewportSize.width)
        let verticalProgress = Float(translation.height / viewportSize.height)
        let horizontalSweep = configuration.yawRadiansPerViewport
        let verticalSweep = configuration.pitchRadiansPerViewport

        // 손가락 이동과 시선 이동은 반대 방향이다. 오른쪽으로 끌면 왼쪽을 본다.
        battleCameraYaw = clamp(
            battleCameraLookStartYaw + (horizontalProgress * horizontalSweep),
            minimum: -configuration.maximumYaw,
            maximum: configuration.maximumYaw
        )
        battleCameraPitch = clamp(
            battleCameraLookStartPitch + (verticalProgress * verticalSweep),
            minimum: -configuration.maximumDownwardPitch,
            maximum: configuration.maximumUpwardPitch
        )
        applyBattleCameraTransform()
    }

    func beginBattleCameraZoom() {
        guard canAdjustBattleCamera else { return }
        cancelBattleCameraImpact(restoreCamera: true)
        battleCameraZoomStartFieldOfViewScale = battleCameraFieldOfViewScale
    }

    func updateBattleCameraZoom(
        magnification: CGFloat,
        configuration: BattleCameraInteractionConfiguration = .standard
    ) {
        guard canAdjustBattleCamera, magnification > 0 else { return }
        battleCameraFieldOfViewScale = clamp(
            battleCameraZoomStartFieldOfViewScale / Float(magnification),
            minimum: configuration.minimumFieldOfViewScale,
            maximum: configuration.maximumFieldOfViewScale
        )
        applyBattleCameraTransform()
    }

    func resetBattleCamera(animated: Bool) {
        cancelBattleCameraImpact(restoreCamera: false)
        battleCameraYaw = 0
        battleCameraPitch = 0
        battleCameraFieldOfViewScale = 1
        battleCameraLookStartYaw = 0
        battleCameraLookStartPitch = 0
        battleCameraZoomStartFieldOfViewScale = 1
        isBattleCameraAdjusted = false

        guard [.main, .battle, .tutorial].contains(requestedCameraPreset),
              let activeCameraName,
              let snapshot = authoredCameraSnapshots[activeCameraName],
              let cameraEntity else { return }

        if animated {
            cameraEntity.move(
                to: Transform(matrix: snapshot.transformMatrix),
                relativeTo: nil,
                duration: 0.25,
                timingFunction: .easeInOut
            )
        } else {
            cameraEntity.stopAllAnimations(recursive: false)
            cameraEntity.setTransformMatrix(snapshot.transformMatrix, relativeTo: nil)
        }
        cameraEntity.camera = snapshot.camera
        scheduleBoardProjectionRefresh()
    }

    func playStrongAttackCameraImpact(
        guarded: Bool,
        reducedMotion: Bool
    ) {
        guard !reducedMotion,
              canAdjustBattleCamera,
              let activeCameraName,
              let snapshot = authoredCameraSnapshots[activeCameraName],
              let cameraEntity else { return }

        cancelBattleCameraImpact(restoreCamera: true)
        battleCameraImpactGeneration &+= 1
        let generation = battleCameraImpactGeneration
        let baseMatrix = adjustedBattleCameraMatrix(from: snapshot)
        let strength: Float = guarded ? 0.65 : 1
        let keyframes: [(yawDegrees: Float, milliseconds: Int64)] = [
            (-6.5, 42),
            (7.5, 68),
            (-3.8, 72),
            (1.6, 78),
            (0, 90)
        ]

        battleCameraImpactTask = Task { @MainActor [weak self, weak cameraEntity] in
            guard let self, let cameraEntity else { return }
            for keyframe in keyframes {
                guard !Task.isCancelled,
                      generation == self.battleCameraImpactGeneration else { return }
                let yawOffset = keyframe.yawDegrees * (.pi / 180) * strength
                let impactMatrix = self.adjustedBattleCameraMatrix(
                    from: snapshot,
                    transientYaw: yawOffset
                )
                cameraEntity.move(
                    to: Transform(matrix: impactMatrix),
                    relativeTo: nil,
                    duration: Double(keyframe.milliseconds) / 1_000,
                    timingFunction: .easeInOut
                )
                do {
                    try await Task.sleep(for: .milliseconds(keyframe.milliseconds))
                } catch {
                    return
                }
            }
            guard generation == self.battleCameraImpactGeneration else { return }
            cameraEntity.stopAllAnimations(recursive: false)
            cameraEntity.setTransformMatrix(baseMatrix, relativeTo: nil)
            self.battleCameraImpactTask = nil
            self.scheduleBoardProjectionRefresh()
        }
    }

    func playBattleDefeatCamera(reducedMotion: Bool) async {
        cancelBattleCameraImpact(restoreCamera: false)
        setBattleCameraInteractionEnabled(false)
        guard requestedCameraPreset == .battle,
              let activeCameraName,
              let snapshot = authoredCameraSnapshots[activeCameraName],
              let cameraEntity else { return }

        cameraEntity.stopAllAnimations(recursive: false)
        cameraEntity.setTransformMatrix(snapshot.transformMatrix, relativeTo: nil)
        cameraEntity.camera = snapshot.camera
        clearBattleCameraAdjustmentState()

        let baseTransform = Transform(matrix: snapshot.transformMatrix)
        let settledTransform = battleDefeatCameraTransform(
            from: baseTransform,
            roll: .pi * 7 / 180,
            pitch: -.pi * 3 / 180,
            verticalDrop: 0.12
        )
        let fallenTransform = battleDefeatCameraTransform(
            from: baseTransform,
            roll: .pi * 38 / 180,
            pitch: -.pi * 9 / 180,
            verticalDrop: 0.68
        )

        if reducedMotion {
            cameraEntity.setTransformMatrix(fallenTransform.matrix, relativeTo: nil)
            return
        }

        cameraEntity.move(
            to: settledTransform,
            relativeTo: nil,
            duration: 0.16,
            timingFunction: .easeIn
        )
        do {
            try await Task.sleep(for: .milliseconds(160))
        } catch {
            return
        }
        guard !Task.isCancelled else { return }

        cameraEntity.move(
            to: fallenTransform,
            relativeTo: nil,
            duration: 0.58,
            timingFunction: .easeIn
        )
        do {
            try await Task.sleep(for: .milliseconds(580))
        } catch {
            return
        }
    }

    func playDescentSealRejectionCamera(reducedMotion: Bool) async {
        cancelDescentCameraEffect(restoreCamera: true)
        guard requestedCameraPreset == .descentInput,
              let activeCameraName,
              let snapshot = authoredCameraSnapshots[activeCameraName],
              let cameraEntity else { return }

        descentCameraEffectGeneration &+= 1
        let generation = descentCameraEffectGeneration
        defer {
            if generation == descentCameraEffectGeneration {
                restoreDescentCamera(snapshot: snapshot, cameraEntity: cameraEntity)
            }
        }

        if reducedMotion {
            try? await Task.sleep(for: .milliseconds(280))
            return
        }

        let baseMatrix = snapshot.transformMatrix
        let keyframes: [(horizontalOffset: Float, milliseconds: Int64)] = [
            (-0.045, 48),
            (0.052, 66),
            (-0.028, 70),
            (0.013, 76),
            (0, 88)
        ]

        for keyframe in keyframes {
            guard !Task.isCancelled,
                  generation == descentCameraEffectGeneration else { return }
            let transform = Transform(matrix: descentRejectionCameraMatrix(
                from: baseMatrix,
                horizontalOffset: keyframe.horizontalOffset
            ))
            cameraEntity.move(
                to: transform,
                relativeTo: nil,
                duration: Double(keyframe.milliseconds) / 1_000,
                timingFunction: .easeInOut
            )
            do {
                try await Task.sleep(for: .milliseconds(keyframe.milliseconds))
            } catch {
                return
            }
        }
    }

    func playDescentSealFailureCamera(reducedMotion: Bool) async {
        cancelDescentCameraEffect(restoreCamera: true)
        guard requestedCameraPreset == .descentInput,
              let activeCameraName,
              let snapshot = authoredCameraSnapshots[activeCameraName],
              let cameraEntity else { return }

        descentCameraEffectGeneration &+= 1
        let generation = descentCameraEffectGeneration
        isDescentFailurePresentationActive = true
        let baseTransform = Transform(matrix: snapshot.transformMatrix)
        let bracedTransform = descentCameraTransform(
            from: baseTransform,
            roll: .pi * 4 / 180,
            pitch: -.pi * 1.5 / 180,
            verticalDrop: 0.05
        )
        let fallingTransform = descentCameraTransform(
            from: baseTransform,
            roll: .pi * 20 / 180,
            pitch: -.pi * 6 / 180,
            verticalDrop: 0.44
        )
        let impactTransform = descentCameraTransform(
            from: baseTransform,
            roll: .pi * 34 / 180,
            pitch: -.pi * 11 / 180,
            verticalDrop: 0.74
        )
        let groundedTransform = descentCameraTransform(
            from: baseTransform,
            roll: .pi * 31 / 180,
            pitch: -.pi * 9.5 / 180,
            verticalDrop: 0.69
        )

        cameraEntity.stopAllAnimations(recursive: false)
        cameraEntity.camera = snapshot.camera

        if reducedMotion {
            cameraEntity.setTransformMatrix(groundedTransform.matrix, relativeTo: nil)
            try? await Task.sleep(for: .milliseconds(650))
            return
        }

        cameraEntity.move(
            to: bracedTransform,
            relativeTo: nil,
            duration: 0.24,
            timingFunction: .easeIn
        )
        do {
            try await Task.sleep(for: .milliseconds(240))
        } catch {
            return
        }
        guard !Task.isCancelled,
              generation == descentCameraEffectGeneration else { return }

        cameraEntity.move(
            to: fallingTransform,
            relativeTo: nil,
            duration: 0.86,
            timingFunction: .easeIn
        )
        do {
            try await Task.sleep(for: .milliseconds(860))
        } catch {
            return
        }
        guard !Task.isCancelled,
              generation == descentCameraEffectGeneration else { return }

        cameraEntity.move(
            to: impactTransform,
            relativeTo: nil,
            duration: 0.34,
            timingFunction: .easeIn
        )
        do {
            try await Task.sleep(for: .milliseconds(340))
        } catch {
            return
        }
        guard !Task.isCancelled,
              generation == descentCameraEffectGeneration else { return }

        cameraEntity.move(
            to: groundedTransform,
            relativeTo: nil,
            duration: 0.22,
            timingFunction: .easeOut
        )
        do {
            try await Task.sleep(for: .milliseconds(220))
            try await Task.sleep(for: .milliseconds(700))
        } catch {
            return
        }
    }

    func resetDescentCamera() {
        cancelDescentCameraEffect(restoreCamera: true)
    }

    private func transitionCamera(to preset: RealityCameraPreset) {
        guard
            let descriptor = registry.descriptor,
            let cameraName = descriptor.cameraName(for: preset)
        else { return }
        guard cameraName != pendingCameraName else { return }
        guard cameraName != activeCameraName else {
            if pendingCameraName != nil || isCameraTransitioning {
                cancelCameraTransition()
            }
            return
        }

        cancelBattleCameraImpact(restoreCamera: false)
        cancelDescentCameraEffect(restoreCamera: false)
        cameraTransitionTask?.cancel()
        cameraTransitionGeneration &+= 1
        let transitionGeneration = cameraTransitionGeneration
        pendingCameraName = cameraName
        isCameraTransitioning = true
        cameraTransitionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            cameraFadeOpacity = 1
            do {
                try await Task.sleep(for: .milliseconds(180))
            } catch {
                return
            }
            guard cameraTransitionGeneration == transitionGeneration,
                  pendingCameraName == cameraName else { return }
            applyCamera(named: cameraName)
            guard cameraTransitionGeneration == transitionGeneration else { return }
            pendingCameraName = nil
            cameraFadeOpacity = 0
            isCameraTransitioning = false
            cameraTransitionTask = nil
        }
    }

    private func cancelCameraTransition() {
        cameraTransitionGeneration &+= 1
        cameraTransitionTask?.cancel()
        cameraTransitionTask = nil
        pendingCameraName = nil
        cameraFadeOpacity = 0
        isCameraTransitioning = false
    }

    func isReady(sceneID: FloorSceneID, cameraPreset: RealityCameraPreset) -> Bool {
        guard
            loadState == .ready(sceneID),
            registry.descriptor?.sceneID == sceneID,
            let expectedCameraName = registry.descriptor?.cameraName(for: cameraPreset)
        else { return false }
        return activeCameraName == expectedCameraName && !isCameraTransitioning
    }

    private func applyCamera(named cameraName: String) {
        guard
            let snapshot = authoredCameraSnapshots[cameraName],
            let cameraEntity
        else { return }

        cameraEntity.setTransformMatrix(
            snapshot.transformMatrix,
            relativeTo: nil
        )
        cameraEntity.camera = snapshot.camera
        activeCameraName = cameraName
        clearBattleCameraAdjustmentState()
        scheduleBoardProjectionRefresh()
    }

    private var canAdjustBattleCamera: Bool {
        isBattleCameraInteractionEnabled
            && [.main, .battle, .tutorial].contains(requestedCameraPreset)
            && !isCameraTransitioning
            && activeCameraName != nil
            && cameraEntity != nil
    }

    private func applyBattleCameraTransform() {
        guard canAdjustBattleCamera,
              let activeCameraName,
              let snapshot = authoredCameraSnapshots[activeCameraName],
              let cameraEntity else { return }

        let adjustedMatrix = adjustedBattleCameraMatrix(from: snapshot)
        var adjustedCamera = snapshot.camera
        adjustedCamera.fieldOfViewInDegrees = snapshot.camera.fieldOfViewInDegrees
            * battleCameraFieldOfViewScale

        cameraEntity.stopAllAnimations(recursive: false)
        cameraEntity.setTransformMatrix(adjustedMatrix, relativeTo: nil)
        cameraEntity.camera = adjustedCamera
        isBattleCameraAdjusted = abs(battleCameraYaw) > 0.001
            || abs(battleCameraPitch) > 0.001
            || abs(battleCameraFieldOfViewScale - 1) > 0.001
        scheduleBoardProjectionRefresh()
    }

    private func adjustedBattleCameraMatrix(
        from snapshot: AuthoredCameraSnapshot,
        transientYaw: Float = 0
    ) -> simd_float4x4 {
        let baseMatrix = snapshot.transformMatrix
        let worldUp = SIMD3<Float>(0, 1, 0)
        let yawRotation = simd_quatf(
            angle: battleCameraYaw + transientYaw,
            axis: worldUp
        )
        let baseRight = normalizedAxis(
            baseMatrix.columns.0,
            fallback: SIMD3<Float>(1, 0, 0)
        )
        let pitchAxis = yawRotation.act(baseRight)
        let pitchRotation = simd_quatf(angle: battleCameraPitch, axis: pitchAxis)
        let lookRotation = pitchRotation * yawRotation

        // Blender가 저장한 카메라 위치는 유지하고 시선 축만 회전한다.
        var adjustedMatrix = baseMatrix
        for columnIndex in 0..<3 {
            let column = baseMatrix[columnIndex]
            let axis = SIMD3<Float>(column.x, column.y, column.z)
            let adjustedAxis = lookRotation.act(axis)
            adjustedMatrix[columnIndex] = SIMD4<Float>(adjustedAxis, column.w)
        }

        return adjustedMatrix
    }

    private func floor10OpeningTransform(
        from snapshot: AuthoredCameraSnapshot,
        yaw: Float,
        pitch: Float,
        roll: Float,
        verticalOffset: Float,
        forwardOffset: Float
    ) -> Transform {
        var transform = Transform(matrix: snapshot.transformMatrix)
        let yawRotation = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
        let pitchRotation = simd_quatf(angle: pitch, axis: SIMD3<Float>(1, 0, 0))
        let rollRotation = simd_quatf(angle: roll, axis: SIMD3<Float>(0, 0, 1))
        transform.rotation = transform.rotation * yawRotation * pitchRotation * rollRotation

        let forward = -normalizedAxis(
            snapshot.transformMatrix.columns.2,
            fallback: SIMD3<Float>(0, 0, -1)
        )
        transform.translation += forward * forwardOffset
        transform.translation.y += verticalOffset
        return transform
    }

    private func cancelBattleCameraImpact(restoreCamera: Bool) {
        guard battleCameraImpactTask != nil else { return }
        battleCameraImpactTask?.cancel()
        battleCameraImpactTask = nil
        battleCameraImpactGeneration &+= 1
        if restoreCamera {
            applyBattleCameraTransform()
        }
    }

    private func normalizedAxis(
        _ column: SIMD4<Float>,
        fallback: SIMD3<Float>
    ) -> SIMD3<Float> {
        let axis = SIMD3<Float>(column.x, column.y, column.z)
        let length = simd_length(axis)
        return length > 0.0001 ? axis / length : fallback
    }

    private func battleDefeatCameraTransform(
        from baseTransform: Transform,
        roll: Float,
        pitch: Float,
        verticalDrop: Float
    ) -> Transform {
        var transform = baseTransform
        let rollRotation = simd_quatf(
            angle: roll,
            axis: SIMD3<Float>(0, 0, 1)
        )
        let pitchRotation = simd_quatf(
            angle: pitch,
            axis: SIMD3<Float>(1, 0, 0)
        )
        transform.rotation = baseTransform.rotation * rollRotation * pitchRotation
        transform.translation.y -= verticalDrop
        return transform
    }

    private func descentCameraTransform(
        from baseTransform: Transform,
        roll: Float,
        pitch: Float,
        verticalDrop: Float
    ) -> Transform {
        var transform = baseTransform
        let rollRotation = simd_quatf(angle: roll, axis: SIMD3<Float>(0, 0, 1))
        let pitchRotation = simd_quatf(angle: pitch, axis: SIMD3<Float>(1, 0, 0))
        transform.rotation = baseTransform.rotation * rollRotation * pitchRotation
        transform.translation.y -= verticalDrop
        return transform
    }

    private func descentRejectionCameraMatrix(
        from baseMatrix: simd_float4x4,
        horizontalOffset: Float
    ) -> simd_float4x4 {
        let cameraRight = normalizedAxis(
            baseMatrix.columns.0,
            fallback: SIMD3<Float>(1, 0, 0)
        )
        var matrix = baseMatrix
        let translatedPosition = SIMD3<Float>(
            baseMatrix.columns.3.x,
            baseMatrix.columns.3.y,
            baseMatrix.columns.3.z
        ) + cameraRight * horizontalOffset
        matrix.columns.3 = SIMD4<Float>(translatedPosition, baseMatrix.columns.3.w)
        return matrix
    }

    private func cancelDescentCameraEffect(restoreCamera: Bool) {
        descentCameraEffectGeneration &+= 1
        isDescentFailurePresentationActive = false
        guard restoreCamera,
              requestedCameraPreset == .descentInput,
              let activeCameraName,
              let snapshot = authoredCameraSnapshots[activeCameraName],
              let cameraEntity else { return }
        restoreDescentCamera(snapshot: snapshot, cameraEntity: cameraEntity)
    }

    private func restoreDescentCamera(
        snapshot: AuthoredCameraSnapshot,
        cameraEntity: PerspectiveCamera
    ) {
        cameraEntity.stopAllAnimations(recursive: false)
        cameraEntity.setTransformMatrix(snapshot.transformMatrix, relativeTo: nil)
        cameraEntity.camera = snapshot.camera
        scheduleBoardProjectionRefresh()
    }

    private func clamp(_ value: Float, minimum: Float, maximum: Float) -> Float {
        min(max(value, minimum), maximum)
    }

    private func clearBattleCameraAdjustmentState() {
        battleCameraYaw = 0
        battleCameraPitch = 0
        battleCameraFieldOfViewScale = 1
        battleCameraLookStartYaw = 0
        battleCameraLookStartPitch = 0
        battleCameraZoomStartFieldOfViewScale = 1
        isBattleCameraAdjusted = false
    }

    private func perspectiveCamera(in entity: Entity) -> PerspectiveCamera? {
        if let camera = entity as? PerspectiveCamera {
            return camera
        }
        for child in entity.children {
            if let camera = perspectiveCamera(in: child) {
                return camera
            }
        }
        return nil
    }

    func setErasureZones(_ zones: [ErasureZone]) {
        requestedErasureZones = zones
        guard let board = registry.entity(for: .magicInputBoard) else { return }
        erasureZoneRenderer.render(zones: zones, on: board)
    }

    func prepareExpansionActor() {
        actorMotion.prepareEncounter()
    }

    func setActorMotionSuspended(_ suspended: Bool) {
        actorMotion.setSuspended(suspended)
        combatVFXRenderer.setIntentEffectsSuspended(suspended)
    }

    func playExpansionActorMotion(_ name: String) {
        actorMotion.play(name)
    }

    func setEnemyIdleMotion(reducedMotion: Bool) {
        actorMotion.setReducedMotion(reducedMotion)
        requestedReducedMotion = reducedMotion
        observatoryAmbientMotion.setReducedMotion(reducedMotion)
    }

    func presentCombat(
        events: [DemoSessionEvent],
        battleState: BattleState?,
        reducedMotion: Bool,
        onProjectileLaunch: (() -> Void)? = nil,
        onProjectileImpact: (() -> Void)? = nil
    ) {
        combatVFXRenderer.onProjectileImpact = onProjectileImpact
        var didPlayLaunch = false
        combatVFXRenderer.onProjectileLaunch = {
            guard !didPlayLaunch else { return }
            didPlayLaunch = true
            onProjectileLaunch?()
        }
        requestedBattleState = battleState
        requestedReducedMotion = reducedMotion
        actorMotion.setReducedMotion(reducedMotion)
        actorMotion.present(events, state: battleState)
        observatoryAmbientMotion.setReducedMotion(reducedMotion)
        let cues = RealityCombatPresentationMapper.cues(for: events, battleState: battleState)
        guard registry.root != nil else {
            pendingCombatCues.append(contentsOf: cues)
            return
        }
        combatVFXRenderer.present(
            cues,
            registry: registry,
            reducedMotion: reducedMotion
        )
    }

    func synchronizeCombatState(_ battleState: BattleState?, reducedMotion: Bool) {
        actorMotion.setReducedMotion(reducedMotion)
        if battleState?.phase == .victory {
            actorMotion.play("death")
        } else {
            actorMotion.prepareEncounter()
        }
        requestedBattleState = battleState
        requestedReducedMotion = reducedMotion
        observatoryAmbientMotion.setReducedMotion(reducedMotion)
        guard let battleState, registry.root != nil else { return }
        combatVFXRenderer.present(
            RealityCombatPresentationMapper.cues(for: [], battleState: battleState),
            registry: registry,
            reducedMotion: reducedMotion
        )
    }

    func setDescentPresentation(
        _ state: RealityDescentPresentationState,
        reducedMotion: Bool
    ) {
        requestedDescentState = state
        requestedReducedMotion = reducedMotion
        progressionVFXRenderer.presentDescent(
            state,
            registry: registry,
            reducedMotion: reducedMotion
        )
    }

    func setRewardPresentation(
        _ state: RealityRewardPresentationState,
        reducedMotion: Bool
    ) {
        rewardAppearanceStartTask?.cancel()
        rewardAppearanceStartTask = nil
        requestedRewardState = state
        requestedReducedMotion = reducedMotion
        if state == .inactive || state == .appearing { isRewardAppearanceComplete = false }
        if let sceneID = requestedSceneID,
           ([.floor09ArchiveRedesign, .floor08AdministratorObservatory].contains(sceneID) || sceneID.isExpansion), state == .appearing {
            // Wait for loading and camera travel; otherwise the rise occurs off-screen.
            rewardAppearanceStartTask = Task { @MainActor [weak self] in
                guard let self else { return }
                while !Task.isCancelled {
                    guard self.requestedRewardState == .appearing else { return }
                    if case .failed = self.loadState { return }
                    if case .ready(let readyScene) = self.loadState, readyScene == sceneID,
                       self.isReady(sceneID: sceneID, cameraPreset: .rewardSelection) {
                        self.progressionVFXRenderer.presentReward(.appearing, registry: self.registry, reducedMotion: reducedMotion)
                        return
                    }
                    do { try await Task.sleep(for: .milliseconds(30)) } catch { return }
                }
            }
            return
        }
        progressionVFXRenderer.presentReward(
            state,
            registry: registry,
            reducedMotion: reducedMotion
        )
    }

    func waitForRewardAppearance() async -> Bool {
        while !Task.isCancelled {
            if isRewardAppearanceComplete { return true }
            if case .failed = loadState { return false }
            do { try await Task.sleep(for: .milliseconds(30)) } catch { return false }
        }
        return false
    }

    func resetProgressionPresentation(reducedMotion: Bool) {
        setDescentPresentation(.inactive, reducedMotion: reducedMotion)
        setRewardPresentation(.inactive, reducedMotion: reducedMotion)
    }

    func normalizedMagicBoardPoint(for screenPoint: CGPoint) -> NormalizedPoint? {
        projectedMagicBoard?.normalizedPoint(for: screenPoint)
    }

    func unload() {
        actorMotion.reset()
        observatoryAmbientMotion.reset()
        environmentTask?.cancel()
        environmentTask = nil
        arView?.environment.lighting.resource = nil
        arView?.environment.lighting.intensityExponent = 0
        rewardAppearanceStartTask?.cancel()
        rewardAppearanceStartTask = nil
        isRewardAppearanceComplete = false
        sceneLoadGeneration &+= 1
        floor10OpeningCameraGeneration &+= 1
        loadCancellable?.cancel()
        loadCancellable = nil
        actorLoadCancellable?.cancel()
        actorLoadCancellable = nil
        cancelEnemyPreviewReveal(restoreActor: false)
        cancelBattleCameraImpact(restoreCamera: false)
        cancelDescentCameraEffect(restoreCamera: false)
        cancelCameraTransition()
        if let sceneAnchor, let arView {
            arView.scene.removeAnchor(sceneAnchor)
        }
        sceneAnchor = nil
        cameraEntity = nil
        activeCameraName = nil
        authoredCameraSnapshots = [:]
        isBattleCameraInteractionEnabled = false
        clearBattleCameraAdjustmentState()
        registry.reset()
        missingEntityRoles = []
        projectedMagicBoard = nil
        projectedEnemyIntentFrame = nil
        projectedInvestigationAnchors = [:]
        investigationAnchorEntities = [:]
        isProjectionRefreshScheduled = false
        combatVFXRenderer.reset()
        progressionVFXRenderer.reset()
        requestedSceneID = nil
        requestedCameraPreset = .main
        requestedErasureZones = []
        requestedBattleState = nil
        requestedReducedMotion = false
        requestedDescentState = .inactive
        requestedRewardState = .inactive
        pendingCombatCues.removeAll()
        loadingProgress = 0
        loadState = .idle
    }

    private func install(
        root: Entity,
        descriptor: RealitySceneDescriptor,
        in arView: ARView,
        bundle: Bundle
    ) {
        let anchor = AnchorEntity(world: .zero)
        anchor.name = "DA_RUNTIME_SCENE_ANCHOR"
        // These room exports have an identity default prim, authored in meters/Z-up.
        // Entity.load adds a 0.01 scale without converting the scene's up axis.
        // Normalize that import wrapper before capturing world-space cameras. This
        // also gives physical lights and camera animation offsets meter distances.
        root.transform = Transform(
            scale: SIMD3<Float>(repeating: 1),
            rotation: simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(1, 0, 0)),
            translation: .zero
        )
        anchor.addChild(root)

        authoredCameraSnapshots = captureAuthoredCameras(in: root, descriptor: descriptor)
        removeAuthoredCameras(from: root)
        loadingProgress = 0.82

        let camera = PerspectiveCamera()
        camera.name = "DA_RUNTIME_CAMERA"
        anchor.addChild(camera)
        arView.scene.addAnchor(anchor)

        sceneAnchor = anchor
        cameraEntity = camera
        combatVFXRenderer.cameraEntity = camera
        registry.rebuild(root: root, descriptor: descriptor)
        if descriptor.sceneID.isExpansion, descriptor.entityNames[.rewardStand] != nil {
            do { try installExpansionRewards(bundle: bundle) }
            catch { fail(sceneID: descriptor.sceneID, message: error.localizedDescription); return }
        }
        if descriptor.sceneID == .floor08AdministratorObservatory {
            // Remove the added flat optical discs, keeping the textured sensor pods.
            for entity in Self.observatoryOpticalDiscs(in: root) {
                entity.removeFromParent()
            }
            observatoryAmbientMotion.install(in: root, view: arView)
            observatoryAmbientMotion.setReducedMotion(requestedReducedMotion)
        }
        if descriptor.sceneID == .floor09ArchiveRedesign {
            installFloor9Lighting(in: root)
        } else {
            installPortableRoomLighting(in: root, descriptor: descriptor)
        }
        applyFloor9ShadowQuality()
        installRoomEnvironment(bundle: bundle, sceneID: descriptor.sceneID)
        installInvestigationAnchors(
            in: root,
            sceneAnchor: anchor,
            descriptor: descriptor
        )
        loadingProgress = 0.9
        registry.setDoorOpen(false)
        // The authored entities are the inactive barrier pylons. They remain
        // visible while the renderer adds and removes the active energy shell.
        registry.setEnabled(true, for: .generalShield)
        registry.setEnabled(true, for: .absoluteShield)
        progressionVFXRenderer.onRewardAppearanceCompleted = { [weak self] in
            self?.isRewardAppearanceComplete = true
        }
        progressionVFXRenderer.attach(to: registry, bundle: bundle)
        if let error = progressionVFXRenderer.rewardMotionError {
            fail(sceneID: descriptor.sceneID, message: error)
            return
        }
        if let cameraName = descriptor.cameraName(for: requestedCameraPreset) {
            applyCamera(named: cameraName)
        }

        // Investigation becomes usable without waiting for the hidden boss.
        let isBackgroundActor = descriptor.sceneID == .floor09ArchiveRedesign
            && !requestedEnemyPreviewVisibility
        if isBackgroundActor { completeInstallation(descriptor: descriptor) }
        guard let actor = descriptor.actor else {
            completeInstallation(descriptor: descriptor)
            return
        }
        guard let spawn = registry.entity(for: .enemySpawn) else {
            fail(sceneID: descriptor.sceneID, message: "보스 배치 지점을 찾을 수 없습니다.")
            return
        }
        guard let actorURL = bundle.url(
            forResource: graphicsQuality != .high
                ? actor.resourceName + "_" + graphicsQuality.rawValue : actor.resourceName,
            withExtension: "usdc",
            subdirectory: actor.resourceSubdirectory
        ) else {
            fail(sceneID: descriptor.sceneID, message: "보스 모델을 찾을 수 없습니다: \(actor.resourceName).usdc")
            return
        }

        if !isBackgroundActor { loadingProgress = 0.88 }
        actorStartedAt = Date()
        Self.loadLog.notice("actor.begin background=\(isBackgroundActor)")
        let actorLoadGeneration = sceneLoadGeneration
        actorLoadCancellable = Entity.loadAsync(contentsOf: actorURL)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    guard
                        let self,
                        self.sceneLoadGeneration == actorLoadGeneration,
                        self.requestedSceneID == descriptor.sceneID,
                        case let .failure(error) = completion
                    else { return }
                    self.fail(
                        sceneID: descriptor.sceneID,
                        message: "보스 모델을 불러오지 못했습니다: \(error.localizedDescription)"
                    )
                },
                receiveValue: { [weak self] actorRoot in
                    guard
                        let self,
                        self.sceneLoadGeneration == actorLoadGeneration,
                        self.requestedSceneID == descriptor.sceneID
                    else { return }
                    guard actorRoot.name == actor.expectedEntityName
                            || actorRoot.findEntity(named: actor.expectedEntityName) != nil else {
                        self.fail(
                            sceneID: descriptor.sceneID,
                            message: "보스 모델의 기준 객체가 없습니다: \(actor.expectedEntityName)"
                        )
                        return
                    }

                    let actorContainer = Entity()
                    actorContainer.name = "DA_RUNTIME_ENEMY_ACTOR"
                    let installedActor = actorRoot
                    installedActor.removeFromParent()
                    // Retain skeletal binding paths; the room already owns unit/up-axis conversion.
                    installedActor.transform = .identity
                    actorContainer.addChild(installedActor)
                    self.normalizeActor(
                        installedActor,
                        in: actorContainer,
                        targetHeight: actor.targetHeight
                    )
                    spawn.addChild(actorContainer)
                    self.registry.register(actorContainer, for: .enemyActor)
                    self.registry.setEnabled(
                        self.requestedEnemyPreviewVisibility,
                        for: .enemyActor
                    )
                    do {
                        try self.actorMotion.install(root: installedActor, descriptor: actor, bundle: bundle)
                        self.actorMotion.setReducedMotion(self.requestedReducedMotion)
                    } catch {
                        self.fail(sceneID: descriptor.sceneID, message: error.localizedDescription)
                        return
                    }
                    Self.loadLog.notice("actor.ready seconds=\(Date().timeIntervalSince(self.actorStartedAt))")
                    if !isBackgroundActor {
                        self.loadingProgress = 0.94
                        self.completeInstallation(descriptor: descriptor)
                    } else {
                        self.scheduleBoardProjectionRefresh()
                    }
                }
            )
    }

    private func installExpansionRewards(bundle: Bundle) throws {
        let directory = "Reality/Interactables/RewardDevice"
        let name = graphicsQuality == .high ? "reward_device" : "reward_device_\(graphicsQuality.rawValue)"
        guard let url = bundle.url(forResource: name, withExtension: "usdc", subdirectory: directory),
              let room = registry.root,
              let oldStand = registry.entity(for: .rewardStand) else {
            throw NSError(domain: "RewardAsset", code: 1, userInfo: [NSLocalizedDescriptionKey: "공용 보상 장치가 없습니다."])
        }
        // Room wrappers contain scene offsets. Use the physical pedestal pivot,
        // not the wrapper origin or the frame-one (submerged) scroll anchors.
        func pedestal(in entity: Entity) -> Entity? {
            if entity.name.hasSuffix("RewardStand") { return entity }
            for child in entity.children {
                if let found = pedestal(in: child) { return found }
            }
            return nil
        }
        guard let pivot = pedestal(in: oldStand) else {
            throw NSError(domain: "RewardAsset", code: 2, userInfo: [NSLocalizedDescriptionKey: "보상 장치 배치 기준점이 없습니다."])
        }
        let placement = Transform(matrix: pivot.transformMatrix(relativeTo: room))
        let resource = try Entity.load(contentsOf: url)
        guard let device = resource.findEntity(named: "DA_SharedRewardDevice"),
              let stand = device.findEntity(named: "F08B_RewardStand") else {
            throw NSError(domain: "RewardAsset", code: 3, userInfo: [NSLocalizedDescriptionKey: "공용 보상 장치 구조가 올바르지 않습니다."])
        }
        try configureExpansionRewardScrolls(in: device, bundle: bundle)
        device.removeFromParent()
        device.transform = Transform(scale: placement.scale / SIMD3(repeating: 3),
                                     rotation: placement.rotation, translation: placement.translation)
        room.addChild(device)
        oldStand.isEnabled = false
        registry.register(stand, for: .rewardStand)
        let roles: [RealityEntityRole] = [.rewardScrollLeft, .rewardScrollCenter, .rewardScrollRight]
        for (slot, role) in zip(["Left", "Center", "Right"], roles) {
            registry.entity(for: role)?.isEnabled = false
            guard let scroll = device.findEntity(named: "F08B_RewardScroll_\(slot)_Idle") else {
                throw NSError(domain: "RewardAsset", code: 4, userInfo: [NSLocalizedDescriptionKey: "공용 두루마리 기준점이 없습니다."])
            }
            scroll.isEnabled = false
            registry.register(scroll, for: role)
        }
    }

    /// Replace only the visible models: authored hole, rise and idle pivots stay intact.
    private func configureExpansionRewardScrolls(in device: Entity, bundle: Bundle) throws {
        let floor: Int
        switch registry.descriptor?.sceneID {
        case .floor07CoordinateAdministrator: floor = 7
        case .floor06CausalityAdministrator: floor = 6
        case .floor05OriginalMemoryAdministrator: floor = 5
        default: throw CocoaError(.fileReadCorruptFile)
        }
        let candidates = RewardCatalog.candidates(forFloorNumber: floor)
        let slots = ["Left", "Center", "Right"]
        guard candidates.count == slots.count else { throw CocoaError(.fileReadCorruptFile) }

        let engravedName = graphicsQuality == .high ? "reward_scroll" : "reward_scroll_\(graphicsQuality.rawValue)"
        guard let url = bundle.url(forResource: engravedName, withExtension: "usdc",
                                   subdirectory: "Reality/Interactables/RewardScroll") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let engravedResource = try Entity.load(contentsOf: url)
        guard let engraved = engravedResource.findEntity(named: "F09_RewardScroll_Center"),
              let worn = device.findEntity(named: "F08B_RewardScroll_Left"),
              let sealed = device.findEntity(named: "F08B_RewardScroll_Center"),
              let forbidden = device.findEntity(named: "F08B_RewardScroll_Right") else {
            throw CocoaError(.fileReadCorruptFile)
        }
        // Snapshot before replacing any slot; later slots may reuse the same grade.
        let templates: [ScrollTier: Entity] = [
            .worn: worn.clone(recursive: true), .engraved: engraved.clone(recursive: true),
            .sealed: sealed.clone(recursive: true), .forbidden: forbidden.clone(recursive: true)
        ]
        for (slot, candidate) in zip(slots, candidates) {
            let name = "F08B_RewardScroll_\(slot)"
            guard let oldModel = device.findEntity(named: name), let parent = oldModel.parent,
                  let template = templates[candidate.tier] else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let model = template.clone(recursive: true)
            model.name = name
            // All four source meshes use the same Z-up, base-zero, unit-height convention.
            // Keep the slot's authored size and lean, not the donor slot's placement.
            model.transform = oldModel.transform
            oldModel.removeFromParent()
            parent.addChild(model)
        }
    }

    private func normalizeActor(
        _ actorRoot: Entity,
        in container: Entity,
        targetHeight: Float
    ) {
        enableHierarchy(actorRoot)
        var bounds = actorRoot.visualBounds(relativeTo: container)
        var size = bounds.max - bounds.min
        guard size.x > 0.01, size.y > 0.01, size.z > 0.01 else { return }

        // The authored Reality scenes use Blender's Z-up coordinate system.
        // Scale by the visible Z height so enlarging an actor does not stretch
        // its depth toward the camera instead.
        let uniformScale = targetHeight / size.z
        actorRoot.scale *= SIMD3(repeating: uniformScale)

        bounds = actorRoot.visualBounds(relativeTo: container)
        size = bounds.max - bounds.min
        guard size.x > 0.01, size.y > 0.01, size.z > 0.01 else { return }
        actorRoot.position -= SIMD3(
            (bounds.min.x + bounds.max.x) * 0.5,
            (bounds.min.y + bounds.max.y) * 0.5,
            bounds.min.z
        )
    }

    private func enableHierarchy(_ entity: Entity) {
        entity.isEnabled = true
        for child in entity.children {
            enableHierarchy(child)
        }
    }

    private func cancelEnemyPreviewReveal(restoreActor: Bool) {
        enemyPreviewRevealGeneration &+= 1
        enemyPreviewRevealTask?.cancel()
        enemyPreviewRevealTask = nil
        if restoreActor,
           let actor = revealingEnemyPreviewActor ?? registry.entity(for: .enemyActor) {
            actor.stopAllAnimations(recursive: false)
            if let enemyPreviewFinalTransform {
                actor.transform = enemyPreviewFinalTransform
            }
            actor.components.set(OpacityComponent(opacity: 1))
        }
        revealingEnemyPreviewActor = nil
        enemyPreviewFinalTransform = nil
    }

    private func completeInstallation(descriptor: RealitySceneDescriptor) {
        setErasureZones(requestedErasureZones)
        combatVFXRenderer.attach(to: registry)
        let restoredCues = pendingCombatCues + RealityCombatPresentationMapper.cues(
            for: [],
            battleState: requestedBattleState
        )
        pendingCombatCues.removeAll()
        combatVFXRenderer.present(
            restoredCues,
            registry: registry,
            reducedMotion: requestedReducedMotion
        )
        progressionVFXRenderer.presentDescent(
            requestedDescentState,
            registry: registry,
            reducedMotion: requestedReducedMotion
        )
        if ([.floor09ArchiveRedesign, .floor08AdministratorObservatory].contains(descriptor.sceneID) || descriptor.sceneID.isExpansion), requestedRewardState == .appearing {
            setRewardPresentation(.appearing, reducedMotion: requestedReducedMotion)
        } else {
            progressionVFXRenderer.presentReward(
                requestedRewardState, registry: registry, reducedMotion: requestedReducedMotion
            )
        }
        loadingProgress = 0.97
        missingEntityRoles = registry.missingRequiredRoles
        if descriptor.sceneID.isExpansion, !missingEntityRoles.isEmpty {
            fail(sceneID: descriptor.sceneID, message: "장면의 필수 연결이 누락됐습니다: " + missingEntityRoles.map(\.rawValue).sorted().joined(separator: ", "))
            return
        }
        guard
            let expectedCameraName = descriptor.cameraName(for: requestedCameraPreset),
            activeCameraName == expectedCameraName
        else {
            fail(sceneID: descriptor.sceneID, message: "지정된 카메라를 준비하지 못했습니다.")
            return
        }
        loadingProgress = 1
        scheduleBoardProjectionRefresh()

        let readyGeneration = sceneLoadGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard
                let self,
                self.sceneLoadGeneration == readyGeneration,
                self.requestedSceneID == descriptor.sceneID
            else { return }
            Self.loadLog.notice("room.ready seconds=\(Date().timeIntervalSince(self.loadStartedAt))")
            if case .failed = self.loadState { return }
            self.loadState = .ready(descriptor.sceneID)
        }
    }

    private func captureAuthoredCameras(
        in root: Entity,
        descriptor: RealitySceneDescriptor
    ) -> [String: AuthoredCameraSnapshot] {
        var snapshots: [String: AuthoredCameraSnapshot] = [:]
        for cameraName in Set(descriptor.cameraNames.values) {
            guard
                let cameraContainer = root.findEntity(named: cameraName),
                let authoredCamera = perspectiveCamera(in: cameraContainer)
            else { continue }
            snapshots[cameraName] = AuthoredCameraSnapshot(
                transformMatrix: authoredCamera.transformMatrix(relativeTo: nil),
                camera: authoredCamera.camera
            )
        }
        return snapshots
    }

    private func removeAuthoredCameras(from entity: Entity) {
        for child in Array(entity.children) {
            removeAuthoredCameras(from: child)
        }
        if entity is PerspectiveCamera {
            entity.removeFromParent()
        }
    }

    private func scheduleBoardProjectionRefresh() {
        guard !isProjectionRefreshScheduled else { return }
        isProjectionRefreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.isProjectionRefreshScheduled = false
            self?.refreshBoardProjection()
            self?.refreshEnemyIntentProjection()
            self?.refreshInvestigationProjections()
        }
    }

    private func installInvestigationAnchors(
        in root: Entity,
        sceneAnchor: AnchorEntity,
        descriptor: RealitySceneDescriptor
    ) {
        investigationAnchorEntities = [:]
        projectedInvestigationAnchors = [:]

        let definitions: [InvestigationAnchorDefinition]
        switch descriptor.sceneID {
        case .floor10ClosedOffice:
            definitions = [
                .init(
                    id: "floor10.clue.training-target",
                    entityName: "TargetPanel_R",
                    normalizedPosition: SIMD3(0.5, 0.5, 0.94)
                ),
                .init(
                    id: "floor10.clue.impact-scar",
                    entityName: "BrokenMonitor_R",
                    normalizedPosition: SIMD3(0.5, 0.5, 0.88)
                ),
                .init(
                    id: "floor10.clue.glyph-archive",
                    entityName: "BeginnerSpellCabinet",
                    normalizedPosition: SIMD3(0.5, 0.5, 0.9)
                )
            ]
        case .floor09ArchiveRedesign:
            definitions = [
                .init(
                    id: "9-entrance-01",
                    entityName: "F09_SetDress_CableCoil_LeftRear",
                    normalizedPosition: SIMD3(0.5, 0.62, 0.55)
                ),
                .init(
                    id: "floor9.entrance.erased-monitor",
                    entityName: "F09_SetDress_Monitor_Right",
                    normalizedPosition: SIMD3(0.5, 0.5, 0.9)
                )
            ]
        case .floor08ResidueIsolation:
            definitions = [
                .init(
                    id: "floor8.entrance.warning-tags",
                    entityName: "IsolationWarningTags",
                    normalizedPosition: SIMD3(0.5, 0.55, 0.9)
                ),
                .init(
                    id: "floor8.entrance.floor-anchor",
                    entityName: "Anchor_0",
                    normalizedPosition: SIMD3(0.5, 0.72, 0.5)
                )
            ]
        case .floor07CoordinateResidue, .floor06CausalityResidue, .floor05MemoryOmissionResidue:
            let floor = descriptor.sceneID == .floor07CoordinateResidue ? 7
                : descriptor.sceneID == .floor06CausalityResidue ? 6 : 5
            definitions = ExpansionInvestigationCatalog.records(for: floor).map {
                .init(id: $0.id, entityName: $0.entityName,
                      normalizedPosition: SIMD3(0.5, 0.8, 0.5))
            }
        default:
            definitions = []
        }

        for definition in definitions {
            guard let target = root.findEntity(named: definition.entityName) else { continue }
            let bounds = target.visualBounds(relativeTo: nil)
            let size = bounds.max - bounds.min
            guard size.x > 0.001, size.y > 0.001, size.z > 0.001 else { continue }

            let worldPosition = bounds.min + (size * definition.normalizedPosition)
            let anchor = Entity()
            anchor.name = "DA_INVESTIGATION_\(definition.id)"
            sceneAnchor.addChild(anchor)
            anchor.setPosition(worldPosition, relativeTo: nil)
            investigationAnchorEntities[definition.id] = anchor
        }
    }

    private func refreshInvestigationProjections() {
        guard requestedSceneID != nil,
              let arView,
              let cameraEntity else {
            projectedInvestigationAnchors = [:]
            return
        }

        let cameraMatrix = cameraEntity.transformMatrix(relativeTo: nil)
        let cameraPosition = SIMD3<Float>(
            cameraMatrix.columns.3.x,
            cameraMatrix.columns.3.y,
            cameraMatrix.columns.3.z
        )
        let cameraForward = simd_normalize(-SIMD3<Float>(
            cameraMatrix.columns.2.x,
            cameraMatrix.columns.2.y,
            cameraMatrix.columns.2.z
        ))
        let extendedViewport = arView.bounds.insetBy(dx: -640, dy: -480)

        var next: [String: RealityProjectedInvestigationAnchor] = [:]
        for (id, anchor) in investigationAnchorEntities {
            let worldPosition = anchor.position(relativeTo: nil)
            let direction = worldPosition - cameraPosition
            guard simd_length_squared(direction) > 0.0001,
                  simd_dot(simd_normalize(direction), cameraForward) > 0,
                  let point = arView.project(worldPosition),
                  extendedViewport.contains(point) else { continue }
            next[id] = RealityProjectedInvestigationAnchor(point: point)
        }

        if projectedInvestigationAnchors != next {
            projectedInvestigationAnchors = next
        }
    }

    private func refreshEnemyIntentProjection() {
        guard let arView else {
            projectedEnemyIntentFrame = nil
            return
        }
        let nextFrame = combatVFXRenderer.projectedIntentFrame(in: arView)
        if projectedEnemyIntentFrame != nextFrame {
            projectedEnemyIntentFrame = nextFrame
        }
    }

    private func refreshBoardProjection() {
        guard let arView, let board = registry.entity(for: .magicInputBoard) else {
            projectedMagicBoard = nil
            return
        }

        let bounds = board.visualBounds(relativeTo: nil)
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
        guard projected.count >= 4 else {
            projectedMagicBoard = nil
            return
        }

        let minX = projected.map(\.x).min() ?? 0
        let maxX = projected.map(\.x).max() ?? 0
        let minY = projected.map(\.y).min() ?? 0
        let maxY = projected.map(\.y).max() ?? 0
        let frame = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            .intersection(arView.bounds)
        guard frame.width >= 44, frame.height >= 44 else {
            projectedMagicBoard = nil
            return
        }

        let nextProjection = RealityProjectedBoard(frame: frame)
        if projectedMagicBoard != nextProjection {
            projectedMagicBoard = nextProjection
        }
    }

    private func fail(sceneID: FloorSceneID, message: String) {
        loadCancellable = nil
        actorLoadCancellable = nil
        loadingProgress = 0
        loadState = .failed(sceneID, message)
    }
}


extension RealitySceneController {
    /// Blender's Cycles area lights do not survive the RealityKit USD import.
    /// Positions and aim points use the authored F09 scene's local, Z-up coordinates.
    private func installFloor9Lighting(in root: Entity) {
        struct Fixture {
            let name: String
            let position: SIMD3<Float>
            let target: SIMD3<Float>
            let color: UIColor
            let intensity: Float
            let radius: Float
            let outerAngle: Float
        }

        let ceiling = UIColor(red: 1, green: 0.95, blue: 0.87, alpha: 1)
        let warm = UIColor(red: 1, green: 0.94, blue: 0.84, alpha: 1)
        let door = UIColor(red: 1, green: 0.70, blue: 0.36, alpha: 1)
        // The room root maps authored Z-up coordinates into the Y-up runtime.
        // Local fixture coordinates remain exactly as exported from Blender.
        // Six working fluorescent fixtures from DA_F09_Archive_Redesign in v022.
        let fixtures: [Fixture] = [
            Fixture(name: "CEILING_0", position: [-6, -3, 6.93], target: [-6, -3, 0], color: ceiling, intensity: 2700, radius: 12, outerAngle: 105),
            Fixture(name: "CEILING_1", position: [2, -3, 6.93], target: [2, -3, 0], color: ceiling, intensity: 2700, radius: 12, outerAngle: 105),
            Fixture(name: "CEILING_3", position: [-5, 4, 6.93], target: [-5, 4, 0], color: ceiling, intensity: 2700, radius: 12, outerAngle: 105),
            Fixture(name: "CEILING_4", position: [1, 7, 6.93], target: [1, 7, 0], color: ceiling, intensity: 2700, radius: 12, outerAngle: 105),
            Fixture(name: "CEILING_6", position: [4, 12, 6.93], target: [4, 12, 0], color: ceiling, intensity: 2700, radius: 12, outerAngle: 105),
            Fixture(name: "CEILING_7", position: [-2, 15, 6.93], target: [-2, 15, 0], color: ceiling, intensity: 2700, radius: 12, outerAngle: 105),
            // These broad spotlights stand in for the six 5 m Cycles area lights.
            Fixture(name: "BOSS_KEY", position: [-4.5, 8.5, 7.1], target: [-0.26, 10.29, 1.82], color: warm, intensity: 1500, radius: 12, outerAngle: 115),
            Fixture(name: "BOSS_RIM", position: [4.8, 13.8, 5.8], target: [0.15, 10.51, 1.73], color: warm, intensity: 1500, radius: 12, outerAngle: 115),
            Fixture(name: "INPUT_KEY", position: [-3.8, -3.5, 6.5], target: [-0.36, -1.87, 0.62], color: warm, intensity: 1500, radius: 12, outerAngle: 115),
            Fixture(name: "DOOR", position: [8, 12, 5.7], target: [8.2, 13.3, -0.15], color: door, intensity: 1700, radius: 10, outerAngle: 110),
            Fixture(name: "REWARD", position: [-8, 10.2, 5.4], target: [-8, 12.22, -0.25], color: warm, intensity: 1500, radius: 10, outerAngle: 110),
            Fixture(name: "FRONT_FILL", position: [0, -11, 4.5], target: [0, -2.31, 2.16], color: warm, intensity: 1900, radius: 16, outerAngle: 120)
        ]
        for fixture in fixtures {
            let lamp = SpotLight()
            lamp.name = "F09_RUNTIME_\(fixture.name)"
            lamp.light.color = fixture.color
            // Fixed -0.5 EV direct-light gain avoids flattening the material with added fill.
            lamp.light.intensity = fixture.intensity * pow(2, -0.5)
            lamp.light.innerAngleInDegrees = fixture.outerAngle * 0.64
            lamp.light.outerAngleInDegrees = fixture.outerAngle
            lamp.light.attenuationRadius = fixture.radius
            root.addChild(lamp)
            lamp.look(
                at: fixture.target,
                from: fixture.position,
                upVector: [0, 1, 0],
                relativeTo: root
            )
        }
    }

    private func installPortableRoomLighting(in root: Entity, descriptor: RealitySceneDescriptor) {
        // Blender area lights do not illuminate RealityKit. Keep a bounded set
        // of broad spots; the captured environment supplies indirect light.
        func removeImportedLights(from entity: Entity) {
            entity.components.remove(PointLightComponent.self)
            entity.components.remove(SpotLightComponent.self)
            entity.components.remove(DirectionalLightComponent.self)
            for child in entity.children { removeImportedLights(from: child) }
        }
        removeImportedLights(from: root)
        typealias Fixture = (position: SIMD3<Float>, target: SIMD3<Float>, power: Float)
        let fixtures: [Fixture]
        switch descriptor.sceneID {
        case .floor10ClosedOffice:
            fixtures = [([-4.8,1.2,6.82],[-4.8,1.2,0],2200), ([5,2.8,6.82],[5,2.8,0],2600),
                        ([-4.6,8.5,6.82],[-4.6,8.5,0],2300), ([4.8,8,6.82],[4.8,8,0],2000),
                        ([0,-6,6.82],[0,-6,0],2400), ([-10.6,4,6.1],[0,5,2],1600)]
        case .floor08ResidueIsolation:
            fixtures = [([-5,1,6.4],[0,5,1],2300), ([5,3,6.4],[0,6,1],2300),
                        ([0,11,6.4],[0,9,1],2000), ([0,-5,6],[0,2,1],1600)]
        case .floor08AdministratorObservatory:
            fixtures = [([-6,1,8],[0,7,2],2600), ([6,1,8],[0,7,2],2600),
                        ([0,12,9],[0,11,1],3000), ([0,-8,6],[0,7,3],1800),
                        ([-8,9,6],[-8,12,1],1700), ([8,10,6],[8,13,1],1700)]
        case .floor07CoordinateResidue, .floor06CausalityResidue, .floor05MemoryOmissionResidue:
            fixtures = [([-5,1,6],[0,5,1],2000), ([5,3,6],[0,6,1],2000),
                        ([0,11,6],[0,9,1],1800), ([0,-5,6],[0,2,1],1600)]
        case .floor07CoordinateAdministrator, .floor06CausalityAdministrator, .floor05OriginalMemoryAdministrator:
            fixtures = [([-6,1,8],[0,7,2],2500), ([6,1,8],[0,7,2],2500),
                        ([0,12,9],[0,11,1],2600), ([0,-8,6],[0,7,3],1800),
                        ([-8,2,6],[-7,2,1],1700), ([8,10,6],[8,13,1],1700)]
        default: return
        }
        for (index, fixture) in fixtures.enumerated() {
            let lamp = SpotLight(); lamp.name = "ROOM_RUNTIME_\(index)"
            lamp.light.color = UIColor(red: 1, green: 0.95, blue: 0.88, alpha: 1)
            lamp.light.intensity = fixture.power * pow(2, 0.5)
            lamp.light.innerAngleInDegrees = 70; lamp.light.outerAngleInDegrees = 115
            lamp.light.attenuationRadius = 20
            root.addChild(lamp)
            lamp.look(at: fixture.target, from: fixture.position,
                      upVector: [0, 1, 0], relativeTo: root)
        }
    }
}


extension RealitySceneController {
    func setGraphicsQuality(_ quality: GraphicsQuality) {
        graphicsQuality = quality
        guard appliedGraphicsQuality != quality || graphicsQualityView !== arView else { return }
        appliedGraphicsQuality = quality
        graphicsQualityView = arView
        // Preserve HDR brightness and UI resolution across all presets.
        arView?.renderOptions.insert(.disableMotionBlur)
        if quality == .low {
            arView?.renderOptions.formUnion([.disableDepthOfField, .disableGroundingShadows])
        } else {
            arView?.renderOptions.subtract([.disableDepthOfField, .disableGroundingShadows])
        }
        applyFloor9ShadowQuality()
    }

    private func applyFloor9ShadowQuality() {
        for index in 0..<6 {
            guard let lamp = registry.entity(named: "ROOM_RUNTIME_\(index)") as? SpotLight else { continue }
            lamp.shadow = index < graphicsQuality.shadowLightCount ? SpotLightComponent.Shadow() : nil
        }
        // Alternate fixtures retain even coverage when only two shadows are enabled.
        for (rank, index) in [3, 4, 0, 7].enumerated() {
            guard let lamp = registry.entity(named: "F09_RUNTIME_CEILING_\(index)") as? SpotLight else { continue }
            lamp.shadow = rank < graphicsQuality.shadowLightCount ? SpotLightComponent.Shadow() : nil
        }
    }
}


extension RealitySceneController {
    func prefetchRoom(
        sceneID: FloorSceneID,
        quality: GraphicsQuality,
        bundle: Bundle = .main
    ) {
        let descriptor = RealitySceneDescriptor.descriptor(for: sceneID)
        guard let url = bundle.url(
            forResource: quality.resourceName(for: sceneID),
            withExtension: "usdc",
            subdirectory: descriptor.resourceSubdirectory
        ) else { return }
        PreparedRealityAssets.shared.preloadRoom(url: url)
    }

    func prefetchFloor9(quality: GraphicsQuality, bundle: Bundle = .main) {
        prefetchRoom(sceneID: .floor09ArchiveRedesign, quality: quality, bundle: bundle)
        PreparedRealityAssets.shared.prepareEnvironment(bundle: bundle)
    }

    func waitForEnemyReady() async -> Bool {
        let generation = sceneLoadGeneration
        while !Task.isCancelled, generation == sceneLoadGeneration {
            if registry.entity(for: .enemyActor) != nil { return true }
            if case .failed = loadState { return false }
            if registry.descriptor?.actor == nil, case .ready = loadState { return true }
            do { try await Task.sleep(for: .milliseconds(30)) } catch { return false }
        }
        return false
    }

    private func installRoomEnvironment(bundle: Bundle, sceneID: FloorSceneID) {
        let generation = sceneLoadGeneration
        environmentTask?.cancel()
        environmentTask = Task { @MainActor [weak self] in
            let resource = await PreparedRealityAssets.shared.environment(bundle: bundle, sceneID: sceneID)
            guard let self, !Task.isCancelled, self.sceneLoadGeneration == generation,
                  self.requestedSceneID == sceneID else { return }
            self.arView?.environment.lighting.resource = resource
            // Calibrate captured radiance for RealityKit; fixtures shape local shadows.
            self.arView?.environment.lighting.intensityExponent = 2.5
        }
    }
}

/// At most one upcoming room. Consuming it releases the unmodified template;
/// the live scene receives a clone sharing mesh/texture resources.
@MainActor
private final class PreparedRealityAssets {
    static let shared = PreparedRealityAssets()
    private final class Entry {
        let url: URL
        let result = CurrentValueSubject<Entity?, Error>(nil)
        var request: AnyCancellable?
        init(url: URL) {
            self.url = url
            request = Entity.loadAsync(contentsOf: url).receive(on: DispatchQueue.main).sink(
                receiveCompletion: { [weak self] completion in
                    if case let .failure(error) = completion { self?.result.send(completion: .failure(error)) }
                }, receiveValue: { [weak self] root in self?.result.send(root) })
        }
    }
    private var room: Entry?
    private var memoryWarning: AnyCancellable?
    private var environmentTasks: [FloorSceneID: Task<EnvironmentResource?, Never>] = [:]
    private init() {
        memoryWarning = NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .receive(on: DispatchQueue.main).sink { [weak self] _ in self?.room = nil }
    }
    func preloadRoom(url: URL) {
        guard room?.url != url else { return }
        room = Entry(url: url)
    }
    func takeRoom(url: URL) -> AnyPublisher<Entity, Error> {
        guard let entry = room, entry.url == url else {
            room = nil
            return Entity.loadAsync(contentsOf: url).eraseToAnyPublisher()
        }
        room = nil
        return entry.result.compactMap { $0 }.prefix(1)
            .map { $0.clone(recursive: true) }
            .handleEvents(receiveCompletion: { _ in _ = entry }, receiveCancel: { _ = entry })
            .eraseToAnyPublisher()
    }
    func prepareEnvironment(bundle: Bundle, sceneID: FloorSceneID = .floor09ArchiveRedesign) {
        guard environmentTasks[sceneID] == nil else { return }
        let name: String
        switch sceneID {
        case .floor09ArchiveRedesign: name = "floor09_environment"
        case .floor10ClosedOffice: name = "floor10_environment"
        case .floor08ResidueIsolation: name = "floor08_residue_environment"
        case .floor08AdministratorObservatory: name = "floor08_boss_environment"
        default:
            guard sceneID.isExpansion else { return }
            name = "environment"
        }
        let directory = RealitySceneDescriptor.descriptor(for: sceneID).resourceSubdirectory
        environmentTasks[sceneID] = Task { @MainActor in
            guard let url = bundle.url(forResource: name, withExtension: "hdr",
                                       subdirectory: directory),
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
            do { return try await EnvironmentResource(equirectangular: image, withName: name) }
            catch {
                Logger(subsystem: "com.wsysangyoung.DescentAuthorized", category: "SceneLoading")
                    .error("environment.failed \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }
    func environment(bundle: Bundle, sceneID: FloorSceneID = .floor09ArchiveRedesign) async -> EnvironmentResource? {
        prepareEnvironment(bundle: bundle, sceneID: sceneID)
        return await environmentTasks[sceneID]?.value
    }
}


#if DEBUG
extension RealitySceneController {
    /// Opt-in, fixed-input comparison. Runs only inside the asset preview.
    /// Writes diagnostic images and transforms, never gameplay progress.
    func runDeviceRenderDiagnostics() async {
        guard ProcessInfo.processInfo.arguments.contains("--render-diagnostics"),
              let cameraEntity, let activeCameraName,
              let snapshot = authoredCameraSnapshots[activeCameraName], let arView else { return }
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RenderDiagnostics", isDirectory: true)
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { print("C5_RENDER_DIAGNOSTICS error=\(error)"); return }
        let initialMatrix = cameraEntity.transformMatrix(relativeTo: nil)
        let initialYaw = battleCameraYaw
        let initialPitch = battleCameraPitch
        defer {
            cameraEntity.setTransformMatrix(initialMatrix, relativeTo: nil)
            battleCameraYaw = initialYaw
            battleCameraPitch = initialPitch
        }
        func values(_ matrix: simd_float4x4) -> [Float] {
            (0..<4).flatMap { column in (0..<4).map { matrix[column][$0] } }
        }
        func capture(_ label: String) async {
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            let matrix = cameraEntity.transformMatrix(relativeTo: nil)
            let report: [String: Any] = [
                "event": label, "os": UIDevice.current.systemVersion,
                "scene": requestedSceneID?.rawValue ?? "", "quality": graphicsQuality.rawValue,
                "camera": activeCameraName, "yaw": battleCameraYaw, "pitch": battleCameraPitch,
                "rootMatrix": values(registry.root?.transformMatrix(relativeTo: nil) ?? matrix_identity_float4x4),
                "authoredCamera": values(snapshot.transformMatrix),
                "decomposedAuthored": values(Transform(matrix: snapshot.transformMatrix).matrix),
                "entityCamera": values(matrix), "renderedCamera": values(arView.cameraTransform.matrix),
                "fov": cameraEntity.camera.fieldOfViewInDegrees,
                "environmentExponent": arView.environment.lighting.intensityExponent,
                "environmentLoaded": arView.environment.lighting.resource != nil,
                "viewportWidth": arView.bounds.width, "viewportHeight": arView.bounds.height
            ]
            do {
                let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: directory.appendingPathComponent(label + ".json"), options: .atomic)
                print("C5_RENDER_DIAGNOSTICS \(String(decoding: data, as: UTF8.self))")
            } catch { print("C5_RENDER_DIAGNOSTICS error=\(error)") }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                arView.snapshot(saveToHDR: false) { image in
                    if let data = image?.pngData() {
                        try? data.write(to: directory.appendingPathComponent(label + ".png"), options: .atomic)
                    }
                    continuation.resume()
                }
            }
        }
        // Await the existing lighting task so both captures include the same environment.
        await environmentTask?.value
        guard !Task.isCancelled else { return }
        await capture("01-baseline")
        battleCameraYaw = 0.2
        battleCameraPitch = 0
        cameraEntity.setTransformMatrix(adjustedBattleCameraMatrix(from: snapshot), relativeTo: nil)
        await capture("02-yaw")
        guard !Task.isCancelled else { return }
        if requestedCameraPreset == .battle {
            await playBattleDefeatCamera(reducedMotion: false)
        } else {
            cameraEntity.setTransformMatrix(floor10OpeningTransform(from: snapshot, yaw: -0.12,
                pitch: 0.2, roll: -0.28, verticalOffset: -0.72, forwardOffset: -0.08).matrix, relativeTo: nil)
        }
        await capture("03-fallen")
        print("C5_RENDER_DIAGNOSTICS complete")
    }
}
#endif

#if DEBUG
extension RealitySceneController {
    func runObservatoryAmbientDiagnostics() async {
        guard requestedSceneID == .floor08AdministratorObservatory,
              let root = registry.root, let cameraEntity, let arView else { return }
        await environmentTask?.value
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AmbientDiagnostics", isDirectory: true)
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { print("C5_AMBIENT error=\(error)"); return }
        cameraEntity.look(at: [0, 10, 7.3], from: [0, -5, 4.8], upVector: [0, 0, 1], relativeTo: root)
        cameraEntity.camera.fieldOfViewInDegrees = 65
        var frames: [[String: Any]] = []
        observatoryAmbientMotion.setReducedMotion(true)
        frames.append(observatoryAmbientMotion.diagnosticSnapshot)
        observatoryAmbientMotion.setReducedMotion(false)
        for index in 1...2 {
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            frames.append(observatoryAmbientMotion.diagnosticSnapshot)
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                arView.snapshot(saveToHDR: false) { image in
                    if let data = image?.pngData() {
                        try? data.write(to: directory.appendingPathComponent("motion-\(index).png"), options: .atomic)
                    }
                    continuation.resume()
                }
            }
        }
        observatoryAmbientMotion.setReducedMotion(true)
        frames.append(observatoryAmbientMotion.diagnosticSnapshot)
        do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
        frames.append(observatoryAmbientMotion.diagnosticSnapshot)
        let report: [String: Any] = ["frames": frames,
            "remainingDiscs": Self.observatoryOpticalDiscs(in: root).count]
        do {
            try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted])
                .write(to: directory.appendingPathComponent("report.json"), options: .atomic)
            print("C5_AMBIENT complete")
        } catch { print("C5_AMBIENT error=\(error)") }
        observatoryAmbientMotion.setReducedMotion(requestedReducedMotion)
    }
}
#endif

private extension RealitySceneController {
    static func observatoryOpticalDiscs(in root: Entity) -> [Entity] {
        var result: [Entity] = []
        for child in root.children {
            if child.name == "F08B_Sensor_Lens" || child.name.hasPrefix("F08B_Sensor_Lens_") {
                result.append(child)
            } else {
                result.append(contentsOf: observatoryOpticalDiscs(in: child))
            }
        }
        return result
    }
}

#if DEBUG
extension RealitySceneController {
    /// Isolated preview diagnostics never modify gameplay or its save store.
    /// Runs only in isolated DEBUG previews. Exercises the actual loaded camera
    /// and entity hierarchy without synthesizing touches or changing player saves.
    func runExpansionExplorationDiagnostics(isBattle: Bool) async {
        guard let id = requestedSceneID, id.isExpansion, let cameraEntity,
              let arView else { return }
        await environmentTask?.value
        let mode = isBattle ? "battle" : "investigation"
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ExpansionExplorationDiagnostics/\(id.rawValue)/\(mode)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        func capture(_ name: String) async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                arView.snapshot(saveToHDR: false) { image in
                    try? image?.pngData()?.write(to: directory.appendingPathComponent(name + ".png"))
                    continuation.resume()
                }
            }
        }
        // Allow SwiftUI's nested investigation onAppear to finish before sampling.
        do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
        let enabledOnEntry = isBattleCameraInteractionEnabled
        let actorVisibleOnEntry = registry.entity(for: .enemyActor)?.isEnabled == true
        let base = cameraEntity.transformMatrix(relativeTo: nil)
        let viewport = CGSize(width: 1000, height: 700)
        let config: BattleCameraInteractionConfiguration = isBattle ? .standard : .investigation(maximumYawDegrees: 65)
        await capture("entry")
        beginBattleCameraLook()
        updateBattleCameraLook(translation: CGSize(width: 500, height: 60), viewportSize: viewport, configuration: config)
        let left = cameraEntity.transformMatrix(relativeTo: nil)
        await capture("look-left")
        resetBattleCamera(animated: false)
        beginBattleCameraLook()
        updateBattleCameraLook(translation: CGSize(width: -500, height: -60), viewportSize: viewport, configuration: config)
        let right = cameraEntity.transformMatrix(relativeTo: nil)
        await capture("look-right")
        resetBattleCamera(animated: false)
        let reset = cameraEntity.transformMatrix(relativeTo: nil)
        centerAndLockEntranceCamera(previewYaw: 0, reducedMotion: true, completion: {})
        beginBattleCameraLook()
        updateBattleCameraLook(translation: CGSize(width: 400, height: 0), viewportSize: viewport)
        let locked = cameraEntity.transformMatrix(relativeTo: nil)
        let report: [String: Any] = [
            "scene": id.rawValue, "mode": mode,
            "enabledOnEntry": enabledOnEntry, "actorVisibleOnEntry": actorVisibleOnEntry,
            "lookLeftChanged": base != left, "lookRightChanged": base != right,
            "resetRestoredCamera": base == reset, "lockedCameraRejectsLook": base == locked,
            "anchorIDs": investigationAnchorEntities.keys.sorted(),
            "missingRoles": missingEntityRoles.map(\.rawValue)
        ]
        try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("report.json"))
        setBattleCameraInteractionEnabled(enabledOnEntry)
        print("C5_EXPLORATION_DIAGNOSTICS \(id.rawValue) \(mode) complete")
    }

    func runExpansionDiagnostics() async {
        guard let id = requestedSceneID, id.isExpansion, let arView else { return }
        let preset = requestedCameraPreset
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ExpansionDiagnostics/\(id.rawValue)/\(graphicsQuality.rawValue)-\(preset.rawValue)")
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { return }
        await environmentTask?.value
        func joints(_ entity: Entity?) -> [[Float]] {
            guard let entity else { return [] }
            var result: [[Float]] = []
            if let model = entity as? ModelEntity {
                result += model.jointTransforms.map {
                    [$0.rotation.vector.x, $0.rotation.vector.y, $0.rotation.vector.z, $0.rotation.vector.w,
                     $0.translation.x, $0.translation.y, $0.translation.z]
                }
            }
            return result + entity.children.flatMap { joints($0) }
        }
        func capture(_ name: String) async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                arView.snapshot(saveToHDR: false) { image in
                    if let data = image?.pngData() { try? data.write(to: directory.appendingPathComponent(name + ".png")) }
                    continuation.resume()
                }
            }
        }
        try? await Task.sleep(for: .milliseconds(350))
        let actor = registry.entity(for: .enemyActor)
        let before = joints(actor)
        await capture("ready")
        var animated: [[Float]] = []
        if preset == .battle {
            actorMotion.play("attack")
            try? await Task.sleep(for: .milliseconds(500))
            animated = joints(actor)
            await capture("attack")
            actorMotion.setReducedMotion(true)
            try? await Task.sleep(for: .milliseconds(200))
            await capture("reduced-motion")
        }
        let report: [String: Any] = ["scene": id.rawValue, "quality": graphicsQuality.rawValue,
            "camera": activeCameraName ?? "", "preset": preset.rawValue,
            "missingRoles": missingEntityRoles.map(\.rawValue),
            "jointCount": before.count, "jointMotionObserved": before != animated && !animated.isEmpty,
            "environmentReady": arView.environment.lighting.resource != nil,
            "actorPresent": actor != nil,
            "rewardReady": preset != .rewardSelection || isRewardAppearanceComplete]
        do {
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: directory.appendingPathComponent("report.json"))
            print("C5_EXPANSION_DIAGNOSTICS \(id.rawValue) \(preset.rawValue) complete")
        } catch { print("C5_EXPANSION_DIAGNOSTICS error \(error)") }
    }
}
#endif
