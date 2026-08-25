import Foundation
import RealityKit

enum FloorSceneID: String, CaseIterable {
    case floor10ClosedOffice = "floor10_closed_office"
    case floor09ArchiveRedesign = "floor09_archive_redesign"
    case floor08ResidueIsolation = "floor08_residue_isolation"
    case floor08AdministratorObservatory = "floor08_administrator_observatory"
}

enum GameAssetID: String, CaseIterable {
    case recordAdministrator = "record_administrator"
    case observationResidue = "observation_residue"
    case observationAdministrator = "observation_administrator"
    case hitNormal = "hit_normal"
    case hitHeavy = "hit_heavy"
    case hitCritical = "hit_critical"
    case hitShield = "hit_shield"
    case intentAttack = "intent_attack"
    case intentHeavyAttack = "intent_heavy_attack"
    case intentShield = "intent_shield"
    case intentAbsoluteShield = "intent_absolute_shield"
    case erasureSquare = "erasure_square"
    case erasureInkLarge = "erasure_ink_large"
    case erasureInkMedium = "erasure_ink_medium"
    case erasureInkSmall = "erasure_ink_small"
}

enum SceneCameraID: String, CaseIterable {
    case floor10Combat = "F10_iPad_MainCamera"
    case floor10Reward = "CAM_F10_RewardSelection"
    case floor10DescentDoor = "CAM_F10_DescentDoor"
    case floor09Combat = "F09_iPad_MainCamera"
    case floor09Reward = "CAM_F09_RewardSelection"
    case floor09DescentDoor = "CAM_F09_DescentDoor"
    case floor08ResidueCombat = "F08A_iPadCamera"
    case floor08AdministratorCombat = "F08_iPad_MainCamera"
    case floor08AdministratorReward = "CAM_F08_RewardSelection"
    case floor08AdministratorDescentDoor = "CAM_F08_DescentDoor"
}

struct DoorStateTransition {
    let closedEntityName: String
    let openEntityName: String
    let authoredSwapFrame: Int
    let authoredFPS: Double
}

enum DoorStateTransitions {
    static let byScene: [FloorSceneID: DoorStateTransition] = [
        .floor10ClosedOffice: .init(
            closedEntityName: "F10_DescentDoor",
            openEntityName: "DA_STATE_OpenDoor_F10",
            authoredSwapFrame: 56,
            authoredFPS: 30
        ),
        .floor09ArchiveRedesign: .init(
            closedEntityName: "F09_DescentDoor",
            openEntityName: "DA_STATE_OpenDoor_F09",
            authoredSwapFrame: 56,
            authoredFPS: 30
        ),
        .floor08AdministratorObservatory: .init(
            closedEntityName: "F08B_DescentDoor",
            openEntityName: "DA_STATE_OpenDoor_F08B",
            authoredSwapFrame: 56,
            authoredFPS: 30
        )
    ]

    static func setDoorOpen(
        _ isOpen: Bool,
        in root: Entity,
        sceneID: FloorSceneID
    ) {
        guard let transition = byScene[sceneID] else { return }
        root.findEntity(named: transition.closedEntityName)?.isEnabled = !isOpen
        root.findEntity(named: transition.openEntityName)?.isEnabled = isOpen
    }
}
