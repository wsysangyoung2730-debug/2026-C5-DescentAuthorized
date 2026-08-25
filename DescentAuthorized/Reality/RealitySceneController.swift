import Combine
import Foundation
import RealityKit

@MainActor
final class RealitySceneController: ObservableObject {
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

    let registry = RealityEntityRegistry()

    private weak var arView: ARView?
    private var sceneAnchor: AnchorEntity?
    private var cameraEntity: PerspectiveCamera?
    private var loadCancellable: AnyCancellable?
    private var cameraTransitionTask: Task<Void, Never>?
    private var requestedSceneID: FloorSceneID?
    private var requestedCameraPreset: RealityCameraPreset = .main
    private var activeCameraName: String?
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
        loadState = .loading(sceneID)
        loadCancellable = Entity.loadAsync(contentsOf: url)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case let .failure(error) = completion {
                        self?.fail(sceneID: sceneID, message: error.localizedDescription)
                    }
                },
                receiveValue: { [weak self] root in
                    guard
                        let self,
                        let arView = self.arView,
                        self.requestedSceneID == sceneID
                    else { return }
                    self.install(root: root, descriptor: descriptor, in: arView)
                }
            )
    }

    func applyCameraPreset(_ preset: RealityCameraPreset) {
        requestedCameraPreset = preset
        transitionCamera(to: preset)
    }

    private func transitionCamera(to preset: RealityCameraPreset) {
        guard
            let descriptor = registry.descriptor,
            let cameraName = descriptor.cameraName(for: preset)
        else { return }
        guard cameraName != activeCameraName else { return }

        cameraTransitionTask?.cancel()
        cameraTransitionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            cameraFadeOpacity = 1
            defer {
                cameraFadeOpacity = 0
                cameraTransitionTask = nil
            }
            do {
                try await Task.sleep(for: .milliseconds(180))
            } catch {
                return
            }
            applyCamera(named: cameraName)
        }
    }

    private func applyCamera(named cameraName: String) {
        guard
            let root = registry.root,
            let authoredCameraContainer = root.findEntity(named: cameraName),
            let cameraEntity
        else { return }

        let authoredPerspectiveCamera = perspectiveCamera(in: authoredCameraContainer)
        let authoredCamera = authoredPerspectiveCamera ?? authoredCameraContainer
        cameraEntity.setTransformMatrix(
            authoredCamera.transformMatrix(relativeTo: nil),
            relativeTo: nil
        )
        if let authoredPerspectiveCamera {
            cameraEntity.camera = authoredPerspectiveCamera.camera
        }
        activeCameraName = cameraName
        scheduleBoardProjectionRefresh()
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

    func presentCombat(
        events: [DemoSessionEvent],
        battleState: BattleState?,
        reducedMotion: Bool
    ) {
        requestedBattleState = battleState
        requestedReducedMotion = reducedMotion
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
        loadCancellable?.cancel()
        loadCancellable = nil
        cameraTransitionTask?.cancel()
        cameraTransitionTask = nil
        if let sceneAnchor, let arView {
            arView.scene.removeAnchor(sceneAnchor)
        }
        sceneAnchor = nil
        cameraEntity = nil
        activeCameraName = nil
        cameraFadeOpacity = 0
        registry.reset()
        missingEntityRoles = []
        projectedMagicBoard = nil
        combatVFXRenderer.reset()
        progressionVFXRenderer.reset()
        requestedSceneID = nil
        loadState = .idle
    }

    private func install(root: Entity, descriptor: RealitySceneDescriptor, in arView: ARView) {
        let anchor = AnchorEntity(world: .zero)
        anchor.name = "DA_RUNTIME_SCENE_ANCHOR"
        anchor.addChild(root)

        let camera = PerspectiveCamera()
        camera.name = "DA_RUNTIME_CAMERA"
        anchor.addChild(camera)
        arView.scene.addAnchor(anchor)

        sceneAnchor = anchor
        cameraEntity = camera
        registry.rebuild(root: root, descriptor: descriptor)
        registry.setDoorOpen(false)
        registry.setEnabled(false, for: .generalShield)
        registry.setEnabled(false, for: .absoluteShield)
        progressionVFXRenderer.attach(to: registry)
        if let cameraName = descriptor.cameraName(for: requestedCameraPreset) {
            applyCamera(named: cameraName)
        }
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
        missingEntityRoles = registry.missingRequiredRoles
        loadState = .ready(descriptor.sceneID)
        scheduleBoardProjectionRefresh()
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
        loadState = .failed(sceneID, message)
    }
}
