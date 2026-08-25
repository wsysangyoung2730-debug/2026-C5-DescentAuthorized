import Foundation
import RealityKit

@MainActor
final class RealityErasureZoneRenderer {
    private let containerName = "DA_RUNTIME_ERASURE_ZONES"
    private var renderedZones: [ErasureZone] = []

    func render(
        zones: [ErasureZone],
        on board: Entity,
        bundle: Bundle = .main
    ) {
        guard zones != renderedZones else { return }
        removeAll(from: board)
        renderedZones = zones
        guard !zones.isEmpty else { return }

        let container = Entity()
        container.name = containerName
        board.addChild(container)

        let boardBounds = board.visualBounds(relativeTo: board)
        for zone in zones {
            guard let url = resourceURL(for: zone, bundle: bundle),
                  let entity = try? Entity.load(contentsOf: url) else { continue }
            configure(entity, for: zone, boardBounds: boardBounds)
            container.addChild(entity)
        }
    }

    func removeAll(from board: Entity?) {
        board?.findEntity(named: containerName)?.removeFromParent()
        renderedZones.removeAll()
    }

    private func configure(
        _ entity: Entity,
        for zone: ErasureZone,
        boardBounds: BoundingBox
    ) {
        entity.name = "DA_RUNTIME_ERASURE_\(zone.id)"

        let centerX = Float((zone.bounds.minX + zone.bounds.maxX) * 0.5)
        let centerY = Float((zone.bounds.minY + zone.bounds.maxY) * 0.5)
        let zoneWidth = Float(zone.bounds.maxX - zone.bounds.minX) * boardBounds.extents.x
        let zoneDepth = Float(zone.bounds.maxY - zone.bounds.minY) * boardBounds.extents.z

        entity.position = SIMD3(
            boardBounds.min.x + centerX * boardBounds.extents.x,
            boardBounds.max.y + max(boardBounds.extents.y * 0.02, 0.002),
            boardBounds.max.z - centerY * boardBounds.extents.z
        )

        let assetBounds = entity.visualBounds(relativeTo: entity)
        let assetFootprint = max(assetBounds.extents.x, assetBounds.extents.z, 0.001)
        let requestedFootprint = max(min(zoneWidth, zoneDepth), 0.001)
        entity.scale = SIMD3(repeating: requestedFootprint / assetFootprint)
    }

    private func resourceURL(for zone: ErasureZone, bundle: Bundle) -> URL? {
        let lowercasedID = zone.id.lowercased()
        if lowercasedID.contains("ink") && lowercasedID.contains("large") {
            return bundle.url(
                forResource: "erasure_ink_large",
                withExtension: "usdc",
                subdirectory: "Reality/VFX/Erasure/ErasureInkLarge"
            )
        }
        if lowercasedID.contains("ink") && lowercasedID.contains("medium") {
            return bundle.url(
                forResource: "erasure_ink_medium",
                withExtension: "usdc",
                subdirectory: "Reality/VFX/Erasure/ErasureInkMedium"
            )
        }
        if lowercasedID.contains("ink") && lowercasedID.contains("small") {
            return bundle.url(
                forResource: "erasure_ink_small",
                withExtension: "usdc",
                subdirectory: "Reality/VFX/Erasure/ErasureInkSmall"
            )
        }
        return bundle.url(
            forResource: "erasure_square",
            withExtension: "usdc",
            subdirectory: "Reality/VFX/Erasure/ErasureSquare"
        )
    }
}
