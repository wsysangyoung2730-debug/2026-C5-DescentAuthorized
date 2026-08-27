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
    case enemyActor
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

struct RealityActorDescriptor: Sendable {
    let assetID: GameAssetID
    let expectedEntityName: String
    let resourceSubdirectory: String
    let targetHeight: Float
    let intentScale: Float
    let intentVerticalOffset: Float

    init(
        assetID: GameAssetID,
        expectedEntityName: String,
        resourceSubdirectory: String,
        targetHeight: Float,
        intentScale: Float = 1.15,
        intentVerticalOffset: Float = 0.3
    ) {
        self.assetID = assetID
        self.expectedEntityName = expectedEntityName
        self.resourceSubdirectory = resourceSubdirectory
        self.targetHeight = targetHeight
        self.intentScale = intentScale
        self.intentVerticalOffset = intentVerticalOffset
    }

    var resourceName: String { assetID.rawValue }
}

struct RealitySceneDescriptor: Sendable {
    let sceneID: FloorSceneID
    let resourceSubdirectory: String
    let cameraNames: [RealityCameraPreset: String]
    let entityNames: [RealityEntityRole: String]
    let actor: RealityActorDescriptor?

    init(
        sceneID: FloorSceneID,
        resourceSubdirectory: String,
        cameraNames: [RealityCameraPreset: String],
        entityNames: [RealityEntityRole: String],
        actor: RealityActorDescriptor? = nil
    ) {
        self.sceneID = sceneID
        self.resourceSubdirectory = resourceSubdirectory
        self.cameraNames = cameraNames
        self.entityNames = entityNames
        self.actor = actor
    }

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
                .battle: "F10_iPad_MainCamera",
                .rewardSelection: "CAM_F10_RewardSelection",
                .descentInput: "CAM_F10_DescentDoor"
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
                .rewardSelection: "CAM_F09_RewardSelection",
                .descentInput: "CAM_F09_DescentDoor"
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
            ],
            actor: .init(
                assetID: .recordAdministrator,
                expectedEntityName: "ACTOR_RecordAdministrator",
                resourceSubdirectory: "Reality/Actors/RecordAdministrator",
                targetHeight: 6.5,
                intentVerticalOffset: -0.8
            )
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
            ],
            actor: .init(
                assetID: .observationResidue,
                expectedEntityName: "ACTOR_ObservationResidue",
                resourceSubdirectory: "Reality/Actors/ObservationResidue",
                targetHeight: 2.35,
                intentScale: 0.64,
                intentVerticalOffset: 0.34
            )
        ),
        .floor08AdministratorObservatory: .init(
            sceneID: .floor08AdministratorObservatory,
            resourceSubdirectory: "Reality/Scenes/Floor08/AdministratorObservatory",
            cameraNames: [
                .main: "F08_iPad_MainCamera",
                .battle: "F08_iPad_MainCamera",
                .rewardSelection: "CAM_F08_RewardSelection",
                .descentInput: "CAM_F08_DescentDoor"
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
            ],
            actor: .init(
                assetID: .observationAdministrator,
                expectedEntityName: "ACTOR_ObservationAdministrator",
                resourceSubdirectory: "Reality/Actors/ObservationAdministrator",
                targetHeight: 4.2
            )
        )
    ]
}

enum DemoSceneExperience: Equatable, Sendable {
    case floor10Tutorial
    case floor9Entrance
    case narrative(BossNarrativeSequence)
    case battle
    case reward(FloorID)
    case floor8Exploration
    case descent(FloorID)
    case completion
}

enum BossNarrativeSequence: Equatable, Sendable {
    case floor9Encounter
    case floor9Defeated
    case floor8ResidualEncounter
    case floor8ResidualDefeated
    case floor8AdministratorEncounter
    case floor8AdministratorDefeated
}

struct DemoScenePresentation: Equatable, Sendable {
    let progressSceneID: SceneID
    let floorSceneID: FloorSceneID?
    let cameraPreset: RealityCameraPreset
    let experience: DemoSceneExperience

    static func presentation(for sceneID: SceneID) -> DemoScenePresentation {
        switch sceneID {
        case .floor10MeetingRoom, .floor10Office, .floor10GlyphArchive:
            .init(
                progressSceneID: sceneID,
                floorSceneID: .floor10ClosedOffice,
                cameraPreset: .tutorial,
                experience: .floor10Tutorial
            )
        case .floor10TrainingWall:
            .init(
                progressSceneID: sceneID,
                floorSceneID: .floor10ClosedOffice,
                cameraPreset: .battle,
                experience: .floor10Tutorial
            )
        case .floor10DescentDoor:
            .init(
                progressSceneID: sceneID,
                floorSceneID: .floor10ClosedOffice,
                cameraPreset: .descentInput,
                experience: .floor10Tutorial
            )
        case .floor9Entrance:
            .init(
                progressSceneID: sceneID,
                floorSceneID: .floor09ArchiveRedesign,
                cameraPreset: .main,
                experience: .floor9Entrance
            )
        case .floor9RecordsEncounter:
            .init(
                progressSceneID: sceneID,
                floorSceneID: .floor09ArchiveRedesign,
                cameraPreset: .battle,
                experience: .narrative(.floor9Encounter)
            )
        case .floor9RecordsBattle:
            .init(
                progressSceneID: sceneID,
                floorSceneID: .floor09ArchiveRedesign,
                cameraPreset: .battle,
                experience: .battle
            )
        case .floor9RecordsDefeated:
            .init(
                progressSceneID: sceneID,
                floorSceneID: .floor09ArchiveRedesign,
                cameraPreset: .battle,
                experience: .narrative(.floor9Defeated)
            )
        case .floor9RewardVault:
            .init(
                progressSceneID: sceneID,
                floorSceneID: .floor09ArchiveRedesign,
                cameraPreset: .rewardSelection,
                experience: .reward(.floor9)
            )
        case .floor9DescentDoor:
            .init(
                progressSceneID: sceneID,
                floorSceneID: .floor09ArchiveRedesign,
                cameraPreset: .descentInput,
                experience: .descent(.floor9)
            )
        case .floor8Antechamber, .floor8ProtectionRoom:
            .init(
                progressSceneID: sceneID,
                floorSceneID: .floor08ResidueIsolation,
                cameraPreset: .tutorial,
                experience: .floor8Exploration
            )
        case .floor8ResidualEncounter:
            .init(
                progressSceneID: sceneID,
                floorSceneID: .floor08ResidueIsolation,
                cameraPreset: .battle,
                experience: .narrative(.floor8ResidualEncounter)
            )
        case .floor8ResidualBattle:
            .init(
                progressSceneID: sceneID,
                floorSceneID: .floor08ResidueIsolation,
                cameraPreset: .battle,
                experience: .battle
            )
        case .floor8ResidualDefeated:
            .init(
                progressSceneID: sceneID,
                floorSceneID: .floor08ResidueIsolation,
                cameraPreset: .battle,
                experience: .narrative(.floor8ResidualDefeated)
            )
        case .floor8SealedDoor:
            .init(
                progressSceneID: sceneID,
                floorSceneID: .floor08AdministratorObservatory,
                cameraPreset: .descentInput,
                experience: .floor8Exploration
            )
        case .floor8AdministratorEncounter:
            .init(
                progressSceneID: sceneID,
                floorSceneID: .floor08AdministratorObservatory,
                cameraPreset: .battle,
                experience: .narrative(.floor8AdministratorEncounter)
            )
        case .floor8AdministratorBattle:
            .init(
                progressSceneID: sceneID,
                floorSceneID: .floor08AdministratorObservatory,
                cameraPreset: .battle,
                experience: .battle
            )
        case .floor8AdministratorDefeated:
            .init(
                progressSceneID: sceneID,
                floorSceneID: .floor08AdministratorObservatory,
                cameraPreset: .battle,
                experience: .narrative(.floor8AdministratorDefeated)
            )
        case .floor8Reward:
            .init(
                progressSceneID: sceneID,
                floorSceneID: .floor08AdministratorObservatory,
                cameraPreset: .rewardSelection,
                experience: .reward(.floor8)
            )
        case .floor8DescentDoor:
            .init(
                progressSceneID: sceneID,
                floorSceneID: .floor08AdministratorObservatory,
                cameraPreset: .descentInput,
                experience: .descent(.floor8)
            )
        case .demoComplete:
            .init(
                progressSceneID: sceneID,
                floorSceneID: nil,
                cameraPreset: .main,
                experience: .completion
            )
        }
    }
}
