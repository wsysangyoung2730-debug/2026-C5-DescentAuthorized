import Combine
import Foundation
import RealityKit

struct BattleCameraInteractionConfiguration: Equatable, Sendable {
    let maximumYaw: Float
    let maximumUpwardPitch: Float
    let maximumDownwardPitch: Float
    let minimumDistanceScale: Float
    let maximumDistanceScale: Float

    static let standard = BattleCameraInteractionConfiguration(
        maximumYaw: .pi * 35 / 180,
        maximumUpwardPitch: .pi * 10 / 180,
        maximumDownwardPitch: .pi * 15 / 180,
        minimumDistanceScale: 0.85,
        maximumDistanceScale: 1.15
    )
}

@MainActor
final class RealitySceneController: ObservableObject {
    private struct AuthoredCameraSnapshot {
        let transformMatrix: simd_float4x4
        let camera: PerspectiveCameraComponent
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
    @Published private(set) var cameraFadeOpacity: Double = 0
    @Published private(set) var isCameraTransitioning = false
    @Published private(set) var isBattleCameraInteractionEnabled = false
    @Published private(set) var isBattleCameraAdjusted = false
    @Published private(set) var loadingProgress: Double = 0

    let registry = RealityEntityRegistry()

    private weak var arView: ARView?
    private var sceneAnchor: AnchorEntity?
    private var cameraEntity: PerspectiveCamera?
    private var loadCancellable: AnyCancellable?
    private var actorLoadCancellable: AnyCancellable?
    private var cameraTransitionTask: Task<Void, Never>?
    private var actorIdleMotionTask: Task<Void, Never>?
    private weak var animatedEnemyAnchor: Entity?
    private var enemyAnchorRestingTransform: Transform?
    private var enemyIdleMotionAmplitude: Float = 0
    private var sceneLoadGeneration: UInt64 = 0
    private var cameraTransitionGeneration: UInt64 = 0
    private var requestedSceneID: FloorSceneID?
    private var requestedCameraPreset: RealityCameraPreset = .main
    private var activeCameraName: String?
    private var pendingCameraName: String?
    private var authoredCameraSnapshots: [String: AuthoredCameraSnapshot] = [:]
    private var battleCameraYaw: Float = 0
    private var battleCameraPitch: Float = 0
    private var battleCameraDistanceScale: Float = 1
    private var battleCameraOrbitStartYaw: Float = 0
    private var battleCameraOrbitStartPitch: Float = 0
    private var battleCameraZoomStartScale: Float = 1
    private var requestedErasureZones: [ErasureZone] = []
    private var requestedBattleState: BattleState?
    private var requestedReducedMotion = false
    private var requestedDescentState: RealityDescentPresentationState = .inactive
    private var requestedRewardState: RealityRewardPresentationState = .inactive
    private var pendingCombatCues: [RealityCombatCue] = []
    private let erasureZoneRenderer = RealityErasureZoneRenderer()
    private let combatVFXRenderer = RealityCombatVFXRenderer()
    private let progressionVFXRenderer = RealityProgressionVFXRenderer()

    func attach(to arView: ARView) {
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

    func setBattleCameraInteractionEnabled(_ isEnabled: Bool) {
        guard isBattleCameraInteractionEnabled != isEnabled else { return }
        isBattleCameraInteractionEnabled = isEnabled
        if !isEnabled {
            resetBattleCamera(animated: false)
        }
    }

    func beginBattleCameraOrbit() {
        guard canAdjustBattleCamera else { return }
        battleCameraOrbitStartYaw = battleCameraYaw
        battleCameraOrbitStartPitch = battleCameraPitch
    }

    func updateBattleCameraOrbit(
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

        battleCameraYaw = clamp(
            battleCameraOrbitStartYaw - (horizontalProgress * horizontalSweep),
            minimum: -configuration.maximumYaw,
            maximum: configuration.maximumYaw
        )
        battleCameraPitch = clamp(
            battleCameraOrbitStartPitch + (verticalProgress * verticalSweep),
            minimum: -configuration.maximumUpwardPitch,
            maximum: configuration.maximumDownwardPitch
        )
        applyBattleCameraTransform()
    }

    func beginBattleCameraZoom() {
        guard canAdjustBattleCamera else { return }
        battleCameraZoomStartScale = battleCameraDistanceScale
    }

    func updateBattleCameraZoom(
        magnification: CGFloat,
        configuration: BattleCameraInteractionConfiguration = .standard
    ) {
        guard canAdjustBattleCamera, magnification > 0 else { return }
        battleCameraDistanceScale = clamp(
            battleCameraZoomStartScale / Float(magnification),
            minimum: configuration.minimumDistanceScale,
            maximum: configuration.maximumDistanceScale
        )
        applyBattleCameraTransform()
    }

    func resetBattleCamera(animated: Bool) {
        battleCameraYaw = 0
        battleCameraPitch = 0
        battleCameraDistanceScale = 1
        battleCameraOrbitStartYaw = 0
        battleCameraOrbitStartPitch = 0
        battleCameraZoomStartScale = 1
        isBattleCameraAdjusted = false

        guard requestedCameraPreset == .battle,
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
            && requestedCameraPreset == .battle
            && !isCameraTransitioning
            && activeCameraName != nil
            && cameraEntity != nil
    }

    private func applyBattleCameraTransform() {
        guard canAdjustBattleCamera,
              let activeCameraName,
              let snapshot = authoredCameraSnapshots[activeCameraName],
              let cameraEntity else { return }

        let baseMatrix = snapshot.transformMatrix
        let basePosition = SIMD3<Float>(
            baseMatrix.columns.3.x,
            baseMatrix.columns.3.y,
            baseMatrix.columns.3.z
        )
        let pivot = battleCameraPivot(baseMatrix: baseMatrix)
        let worldUp = SIMD3<Float>(0, 0, 1)
        let yawRotation = simd_quatf(angle: battleCameraYaw, axis: worldUp)
        let baseRight = normalizedAxis(baseMatrix.columns.0, fallback: SIMD3<Float>(1, 0, 0))
        let pitchAxis = yawRotation.act(baseRight)
        let pitchRotation = simd_quatf(angle: battleCameraPitch, axis: pitchAxis)
        let orbitRotation = pitchRotation * yawRotation

        var adjustedMatrix = baseMatrix
        for columnIndex in 0..<3 {
            let column = baseMatrix[columnIndex]
            let axis = SIMD3<Float>(column.x, column.y, column.z)
            let adjustedAxis = orbitRotation.act(axis)
            adjustedMatrix[columnIndex] = SIMD4<Float>(adjustedAxis, column.w)
        }

        let baseOffset = basePosition - pivot
        let adjustedPosition = pivot
            + orbitRotation.act(baseOffset) * battleCameraDistanceScale
        adjustedMatrix.columns.3 = SIMD4<Float>(adjustedPosition, 1)

        cameraEntity.stopAllAnimations(recursive: false)
        cameraEntity.setTransformMatrix(adjustedMatrix, relativeTo: nil)
        cameraEntity.camera = snapshot.camera
        isBattleCameraAdjusted = abs(battleCameraYaw) > 0.001
            || abs(battleCameraPitch) > 0.001
            || abs(battleCameraDistanceScale - 1) > 0.001
        scheduleBoardProjectionRefresh()
    }

    private func battleCameraPivot(baseMatrix: simd_float4x4) -> SIMD3<Float> {
        if let enemy = registry.entity(for: .enemyActor) {
            let bounds = enemy.visualBounds(relativeTo: nil)
            return (bounds.min + bounds.max) * 0.5
        }

        let basePosition = SIMD3<Float>(
            baseMatrix.columns.3.x,
            baseMatrix.columns.3.y,
            baseMatrix.columns.3.z
        )
        let backward = normalizedAxis(
            baseMatrix.columns.2,
            fallback: SIMD3<Float>(0, 1, 0)
        )
        return basePosition - (backward * 5)
    }

    private func normalizedAxis(
        _ column: SIMD4<Float>,
        fallback: SIMD3<Float>
    ) -> SIMD3<Float> {
        let axis = SIMD3<Float>(column.x, column.y, column.z)
        let length = simd_length(axis)
        return length > 0.0001 ? axis / length : fallback
    }

    private func clamp(_ value: Float, minimum: Float, maximum: Float) -> Float {
        min(max(value, minimum), maximum)
    }

    private func clearBattleCameraAdjustmentState() {
        battleCameraYaw = 0
        battleCameraPitch = 0
        battleCameraDistanceScale = 1
        battleCameraOrbitStartYaw = 0
        battleCameraOrbitStartPitch = 0
        battleCameraZoomStartScale = 1
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
        loadCancellable?.cancel()
        loadCancellable = nil
        actorLoadCancellable?.cancel()
        actorLoadCancellable = nil
        stopEnemyIdleMotion(resetTransform: true)
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
        DispatchQueue.main.async { [weak self] in self?.refreshBoardProjection() }
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
