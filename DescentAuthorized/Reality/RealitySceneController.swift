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

    let registry = RealityEntityRegistry()

    private weak var arView: ARView?
    private var sceneAnchor: AnchorEntity?
    private var cameraEntity: PerspectiveCamera?
    private var loadCancellable: AnyCancellable?
    private var requestedSceneID: FloorSceneID?
    private var requestedCameraPreset: RealityCameraPreset = .main
    private var requestedErasureZones: [ErasureZone] = []
    private let erasureZoneRenderer = RealityErasureZoneRenderer()

    func attach(to arView: ARView) {
        self.arView = arView
        scheduleBoardProjectionRefresh()
    }

    func load(sceneID: FloorSceneID, cameraPreset: RealityCameraPreset, bundle: Bundle = .main) {
        requestedCameraPreset = cameraPreset
        if requestedSceneID == sceneID, case .ready(sceneID) = loadState {
            applyCameraPreset(cameraPreset)
            return
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
                receiveValue: { [weak self, weak arView] root in
                    guard let self, let arView, self.requestedSceneID == sceneID else { return }
                    self.install(root: root, descriptor: descriptor, in: arView)
                }
            )
    }

    func applyCameraPreset(_ preset: RealityCameraPreset) {
        requestedCameraPreset = preset
        guard
            let root = registry.root,
            let descriptor = registry.descriptor,
            let cameraName = descriptor.cameraName(for: preset),
            let authoredCamera = root.findEntity(named: cameraName),
            let cameraEntity
        else { return }
        cameraEntity.transform = Transform(matrix: authoredCamera.transformMatrix(relativeTo: nil))
        scheduleBoardProjectionRefresh()
    }

    func setErasureZones(_ zones: [ErasureZone]) {
        requestedErasureZones = zones
        guard let board = registry.entity(for: .magicInputBoard) else { return }
        erasureZoneRenderer.render(zones: zones, on: board)
    }

    func normalizedMagicBoardPoint(for screenPoint: CGPoint) -> NormalizedPoint? {
        projectedMagicBoard?.normalizedPoint(for: screenPoint)
    }

    func unload() {
        loadCancellable?.cancel()
        loadCancellable = nil
        if let sceneAnchor, let arView {
            arView.scene.removeAnchor(sceneAnchor)
        }
        sceneAnchor = nil
        cameraEntity = nil
        registry.reset()
        missingEntityRoles = []
        projectedMagicBoard = nil
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
        applyCameraPreset(requestedCameraPreset)
        setErasureZones(requestedErasureZones)
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
