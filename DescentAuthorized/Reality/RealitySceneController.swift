import Combine
import Foundation
import RealityKit

struct BattleCameraInteractionConfiguration: Equatable, Sendable {
    let maximumYaw: Float
    let maximumUpwardPitch: Float
    let maximumDownwardPitch: Float
    let minimumFieldOfViewScale: Float
    let maximumFieldOfViewScale: Float

    static let standard = BattleCameraInteractionConfiguration(
        maximumYaw: .pi * 60 / 180,
        maximumUpwardPitch: .pi * 25 / 180,
        maximumDownwardPitch: .pi * 25 / 180,
        minimumFieldOfViewScale: 0.85,
        maximumFieldOfViewScale: 1.10
    )

    static let floorExploration = BattleCameraInteractionConfiguration(
        maximumYaw: .pi * 24 / 180,
        maximumUpwardPitch: .pi * 10 / 180,
        maximumDownwardPitch: .pi * 12 / 180,
        minimumFieldOfViewScale: 1,
        maximumFieldOfViewScale: 1
    )

    static let floorEntranceInvestigation = BattleCameraInteractionConfiguration(
        maximumYaw: .pi * 28 / 180,
        maximumUpwardPitch: .pi * 10 / 180,
        maximumDownwardPitch: .pi * 12 / 180,
        minimumFieldOfViewScale: 1,
        maximumFieldOfViewScale: 1
    )
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

    let registry = RealityEntityRegistry()

    private weak var arView: ARView?
    private var sceneAnchor: AnchorEntity?
    private var cameraEntity: PerspectiveCamera?
    private var loadCancellable: AnyCancellable?
    private var actorLoadCancellable: AnyCancellable?
    private var cameraTransitionTask: Task<Void, Never>?
    private var battleCameraImpactTask: Task<Void, Never>?
    private var actorIdleMotionTask: Task<Void, Never>?
    private var investigationAnchorEntities: [String: Entity] = [:]
    private var isProjectionRefreshScheduled = false
    private weak var animatedEnemyAnchor: Entity?
    private var enemyAnchorRestingTransform: Transform?
    private var enemyIdleMotionAmplitude: Float = 0
    private var sceneLoadGeneration: UInt64 = 0
    private var cameraTransitionGeneration: UInt64 = 0
    private var battleCameraImpactGeneration: UInt64 = 0
    private var descentCameraEffectGeneration: UInt64 = 0
    private var floor10OpeningCameraGeneration: UInt64 = 0
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
            forResource: descriptor.resourceName,
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
        loadCancellable = Entity.loadAsync(contentsOf: url)
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
        requestedEnemyPreviewVisibility = isVisible
        registry.setEnabled(isVisible, for: .enemyActor)
    }

    func centerAndLockEntranceCamera(
        reducedMotion: Bool,
        completion: @escaping @MainActor () -> Void
    ) {
        isBattleCameraInteractionEnabled = false
        resetBattleCamera(animated: !reducedMotion)

        guard !reducedMotion,
              [.main, .battle, .tutorial].contains(requestedCameraPreset),
              activeCameraName != nil,
              cameraEntity != nil else {
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
        let horizontalSweep = configuration.maximumYaw * 2
        let verticalSweep = configuration.maximumUpwardPitch
            + configuration.maximumDownwardPitch

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

    func setEnemyIdleMotion(reducedMotion: Bool) {
        requestedReducedMotion = reducedMotion
        updateEnemyIdleMotion(reducedMotion: reducedMotion)
    }

    func presentCombat(
        events: [DemoSessionEvent],
        battleState: BattleState?,
        reducedMotion: Bool
    ) {
        requestedBattleState = battleState
        requestedReducedMotion = reducedMotion
        updateEnemyIdleMotion(reducedMotion: reducedMotion)
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
        requestedBattleState = battleState
        requestedReducedMotion = reducedMotion
        updateEnemyIdleMotion(reducedMotion: reducedMotion)
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
        requestedRewardState = state
        requestedReducedMotion = reducedMotion
        progressionVFXRenderer.presentReward(
            state,
            registry: registry,
            reducedMotion: reducedMotion
        )
    }

    func resetProgressionPresentation(reducedMotion: Bool) {
        setDescentPresentation(.inactive, reducedMotion: reducedMotion)
        setRewardPresentation(.inactive, reducedMotion: reducedMotion)
    }

    func normalizedMagicBoardPoint(for screenPoint: CGPoint) -> NormalizedPoint? {
        projectedMagicBoard?.normalizedPoint(for: screenPoint)
    }

    func unload() {
        sceneLoadGeneration &+= 1
        floor10OpeningCameraGeneration &+= 1
        loadCancellable?.cancel()
        loadCancellable = nil
        actorLoadCancellable?.cancel()
        actorLoadCancellable = nil
        stopEnemyIdleMotion(resetTransform: true)
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
        registry.rebuild(root: root, descriptor: descriptor)
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
        progressionVFXRenderer.attach(to: registry)
        if let cameraName = descriptor.cameraName(for: requestedCameraPreset) {
            applyCamera(named: cameraName)
        }

        guard let actor = descriptor.actor else {
            completeInstallation(descriptor: descriptor)
            return
        }
        guard let spawn = registry.entity(for: .enemySpawn) else {
            fail(sceneID: descriptor.sceneID, message: "보스 배치 지점을 찾을 수 없습니다.")
            return
        }
        guard let actorURL = bundle.url(
            forResource: actor.resourceName,
            withExtension: "usdc",
            subdirectory: actor.resourceSubdirectory
        ) else {
            fail(sceneID: descriptor.sceneID, message: "보스 모델을 찾을 수 없습니다: \(actor.resourceName).usdc")
            return
        }

        loadingProgress = 0.88
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
                    guard let actorEntity = actorRoot.name == actor.expectedEntityName
                            ? actorRoot
                            : actorRoot.findEntity(named: actor.expectedEntityName) else {
                        self.fail(
                            sceneID: descriptor.sceneID,
                            message: "보스 모델의 기준 객체가 없습니다: \(actor.expectedEntityName)"
                        )
                        return
                    }

                    let actorContainer = Entity()
                    actorContainer.name = "DA_RUNTIME_ENEMY_ACTOR"
                    actorEntity.removeFromParent()
                    actorContainer.addChild(actorEntity)
                    self.normalizeActor(
                        actorEntity,
                        in: actorContainer,
                        targetHeight: actor.targetHeight
                    )
                    spawn.addChild(actorContainer)
                    self.registry.register(actorContainer, for: .enemyActor)
                    self.registry.setEnabled(
                        self.requestedEnemyPreviewVisibility,
                        for: .enemyActor
                    )
                    self.prepareEnemyIdleMotion(
                        spawn,
                        targetHeight: actor.targetHeight,
                        reducedMotion: self.requestedReducedMotion
                    )
                    self.loadingProgress = 0.94
                    self.completeInstallation(descriptor: descriptor)
                }
            )
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

    private func prepareEnemyIdleMotion(
        _ anchor: Entity,
        targetHeight: Float,
        reducedMotion: Bool
    ) {
        stopEnemyIdleMotion(resetTransform: true)
        animatedEnemyAnchor = anchor
        enemyAnchorRestingTransform = anchor.transform
        enemyIdleMotionAmplitude = min(max(targetHeight * 0.014, 0.035), 0.09)
        updateEnemyIdleMotion(reducedMotion: reducedMotion)
    }

    private func updateEnemyIdleMotion(reducedMotion: Bool) {
        guard let anchor = animatedEnemyAnchor,
              let restingTransform = enemyAnchorRestingTransform else { return }

        if reducedMotion {
            actorIdleMotionTask?.cancel()
            actorIdleMotionTask = nil
            anchor.stopAllAnimations(recursive: false)
            anchor.transform = restingTransform
            return
        }
        guard actorIdleMotionTask == nil else { return }

        let amplitude = enemyIdleMotionAmplitude
        actorIdleMotionTask = Task { @MainActor [weak anchor] in
            guard let anchor else { return }
            var isRaised = true
            while !Task.isCancelled, anchor.parent != nil {
                var target = restingTransform
                target.translation.z += isRaised ? amplitude : 0
                anchor.move(
                    to: target,
                    relativeTo: anchor.parent,
                    duration: 1.9,
                    timingFunction: .easeInOut
                )
                do {
                    try await Task.sleep(for: .milliseconds(1_900))
                } catch {
                    return
                }
                isRaised.toggle()
            }
        }
    }

    private func stopEnemyIdleMotion(resetTransform: Bool) {
        actorIdleMotionTask?.cancel()
        actorIdleMotionTask = nil
        if resetTransform,
           let anchor = animatedEnemyAnchor,
           let restingTransform = enemyAnchorRestingTransform {
            anchor.stopAllAnimations(recursive: false)
            anchor.transform = restingTransform
        }
        animatedEnemyAnchor = nil
        enemyAnchorRestingTransform = nil
        enemyIdleMotionAmplitude = 0
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
        progressionVFXRenderer.presentReward(
            requestedRewardState,
            registry: registry,
            reducedMotion: requestedReducedMotion
        )
        loadingProgress = 0.97
        missingEntityRoles = registry.missingRequiredRoles
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
                    entityName: "BlackBoundDocuments_L",
                    normalizedPosition: SIMD3(0.5, 0.72, 0.52)
                ),
                .init(
                    id: "floor9.entrance.erased-monitor",
                    entityName: "SmallWallMonitor",
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
        case .floor08AdministratorObservatory:
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
