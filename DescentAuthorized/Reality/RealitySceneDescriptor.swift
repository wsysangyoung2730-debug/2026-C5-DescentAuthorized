import Foundation

enum RealityCameraPreset: String, CaseIterable, Sendable {
    case main
    case battle
    case tutorial
    case descentInput
    case rewardSelection
}

enum RealityEntityRole: String, CaseIterable, Sendable {
    case magicInputBoard
    case enemySpawn
    case descentDoor
    case openDescentDoor
    case descentStele
    case descentPedestal
    case rewardStand
    case rewardScrollLeft
    case rewardScrollCenter
    case rewardScrollRight
    case generalShield
    case absoluteShield
}

struct RealitySceneDescriptor: Sendable {
    let sceneID: FloorSceneID
    let resourceSubdirectory: String
    let cameraNames: [RealityCameraPreset: String]
    let entityNames: [RealityEntityRole: String]

    var resourceName: String { sceneID.rawValue }

    func cameraName(for preset: RealityCameraPreset) -> String? {
        cameraNames[preset] ?? cameraNames[.main] ?? cameraNames[.battle]
    }

    static func descriptor(for sceneID: FloorSceneID) -> RealitySceneDescriptor {
        descriptors[sceneID]!
    }

    private static let descriptors: [FloorSceneID: RealitySceneDescriptor] = [
        .floor10ClosedOffice: .init(
            sceneID: .floor10ClosedOffice,
            resourceSubdirectory: "Reality/Scenes/Floor10/ClosedOffice",
            cameraNames: [
                .main: "F10_iPad_MainCamera",
                .tutorial: "F10_iPad_MainCamera",
                .battle: "F10_iPad_MainCamera"
            ],
            entityNames: [
                .magicInputBoard: "F10_MagicInputBoard",
                .descentDoor: "F10_DescentDoor",
                .openDescentDoor: "DA_STATE_OpenDoor_F10",
                .descentStele: "F10_DescentStele",
                .descentPedestal: "F10_DescentPedestal"
            ]
        ),
        .floor09ArchiveRedesign: .init(
            sceneID: .floor09ArchiveRedesign,
            resourceSubdirectory: "Reality/Scenes/Floor09/ArchiveRedesign",
            cameraNames: [
                .main: "F09_iPad_MainCamera",
                .battle: "F09_iPad_MainCamera",
                .rewardSelection: "CAM_ANCHOR_F09_RewardSelection",
                .descentInput: "CAM_ANCHOR_F09_DescentInput"
            ],
            entityNames: [
                .magicInputBoard: "F09_MagicInputBoard",
                .enemySpawn: "SPAWN_RecordAdministrator",
                .descentDoor: "F09_DescentDoor",
                .openDescentDoor: "DA_STATE_OpenDoor_F09",
                .descentStele: "F09_DescentStele",
                .descentPedestal: "F09_DescentPedestal",
                .rewardStand: "F09_RewardStand",
                .rewardScrollLeft: "F09_RewardScroll_Left_HoleAnchor",
                .rewardScrollCenter: "F09_RewardScroll_Center_HoleAnchor",
                .rewardScrollRight: "F09_RewardScroll_Right_HoleAnchor",
                .generalShield: "F09_GeneralShield"
            ]
        ),
        .floor08ResidueIsolation: .init(
            sceneID: .floor08ResidueIsolation,
            resourceSubdirectory: "Reality/Scenes/Floor08/ResidueIsolation",
            cameraNames: [
                .main: "F08A_iPadCamera",
                .battle: "F08A_iPadCamera"
            ],
            entityNames: [
                .magicInputBoard: "F08A_MagicInputBoard",
                .enemySpawn: "SPAWN_ObservationResidue"
            ]
        ),
        .floor08AdministratorObservatory: .init(
            sceneID: .floor08AdministratorObservatory,
            resourceSubdirectory: "Reality/Scenes/Floor08/AdministratorObservatory",
            cameraNames: [
                .main: "F08_iPad_MainCamera",
                .battle: "F08_iPad_MainCamera",
                .rewardSelection: "CAM_ANCHOR_F08B_RewardSelection",
                .descentInput: "CAM_ANCHOR_F08B_DescentInput"
            ],
            entityNames: [
                .magicInputBoard: "F08B_MagicInputBoard",
                .enemySpawn: "SPAWN_ObservationAdministrator",
                .descentDoor: "F08B_DescentDoor",
                .openDescentDoor: "DA_STATE_OpenDoor_F08B",
                .descentStele: "F08B_DescentStele",
                .descentPedestal: "F08B_DescentPedestal",
                .rewardStand: "F08B_RewardStand",
                .rewardScrollLeft: "F08B_RewardScroll_Left_HoleAnchor",
                .rewardScrollCenter: "F08B_RewardScroll_Center_HoleAnchor",
                .rewardScrollRight: "F08B_RewardScroll_Right_HoleAnchor",
                .absoluteShield: "F08B_AbsoluteShield"
            ]
        )
    ]
}
