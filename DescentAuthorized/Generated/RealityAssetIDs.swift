import Foundation
import RealityKit

enum FloorSceneID: String, CaseIterable {
    case floor04SignatureMimicResidual = "floor04_signature_mimic_residual"
    case floor04RejectionExecutionResidual = "floor04_rejection_execution_residual"
    case floor04ResponsibilityAuditAdministrator = "floor04_responsibility_audit_administrator"
    case floor03ConsentCustodianResidual = "floor03_consent_custodian_residual"
    case floor03QuarantineEnforcerResidual = "floor03_quarantine_enforcer_residual"
    case floor03VoluntaryQuarantineAdministrator = "floor03_voluntary_quarantine_administrator"
    case floor02OverloadResidual = "floor02_overload_residual"
    case floor02BackflowBlockerResidual = "floor02_backflow_blocker_residual"
    case floor02SealMaintenanceAdministrator = "floor02_seal_maintenance_administrator"
    case floor01IdentityComparisonResidual = "floor01_identity_comparison_residual"
    case floor01ExitReviewResidual = "floor01_exit_review_residual"
    case floor01FinalAuthorizationAdministrator = "floor01_final_authorization_administrator"
    case floor07CoordinateResidue = "floor07_coordinate_residue"
    case floor07CoordinateAdministrator = "floor07_coordinate_administrator"
    case floor06CausalityResidue = "floor06_causality_residue"
    case floor06CausalityAdministrator = "floor06_causality_administrator"
    case floor05MemoryOmissionResidue = "floor05_memory_omission_residue"
    case floor05OriginalMemoryAdministrator = "floor05_original_memory_administrator"
    var isExpansion: Bool {
        (1...7).contains { rawValue.hasPrefix("floor0\($0)_") }
    }

    case floor10ClosedOffice = "floor10_closed_office"
    case floor09ArchiveRedesign = "floor09_archive_redesign"
    case floor08ResidueIsolation = "floor08_residue_isolation"
    case floor08AdministratorObservatory = "floor08_administrator_observatory"
}

enum GameAssetID: String, CaseIterable {
    case signatureMimicResidual = "signature_mimic_residual"
    case rejectionExecutionResidual = "rejection_execution_residual"
    case responsibilityAuditAdministrator = "responsibility_audit_administrator"
    case consentCustodianResidual = "consent_custodian_residual"
    case quarantineEnforcerResidual = "quarantine_enforcer_residual"
    case voluntaryQuarantineAdministrator = "voluntary_quarantine_administrator"
    case overloadResidual = "overload_residual"
    case backflowBlockerResidual = "backflow_blocker_residual"
    case sealMaintenanceAdministrator = "seal_maintenance_administrator"
    case identityComparisonResidual = "identity_comparison_residual"
    case exitReviewResidual = "exit_review_residual"
    case finalAuthorizationAdministrator = "final_authorization_administrator"
    case coordinateResidue = "coordinate_residue"
    case coordinateAdministrator = "coordinate_administrator"
    case causalityResidue = "causality_residue"
    case causalityAdministrator = "causality_administrator"
    case memoryOmissionResidue = "memory_omission_residue"
    case originalMemoryAdministrator = "original_memory_administrator"
    case recordAdministrator = "record_administrator"
    case observationResidue = "observation_residue"
    case observationAdministrator = "observation_administrator"
    case hitNormal = "hit_normal"
    case hitHeavy = "hit_heavy"
    case hitCritical = "hit_critical"
    case hitShield = "hit_shield"
    case intentMemoryRecord = "intent_memory_record"
    case intentMimicAttack = "intent_mimic_attack"
    case intentOpeningWait = "intent_opening_wait"
    case intentScheduledExecution = "intent_scheduled_execution"
    case intentSpellSeal = "intent_spell_seal"
    case intentAmplify = "intent_amplify"
    case intentDamageReservation = "intent_damage_reservation"
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
    case floor10TrainingBoard = "CAM_F10_TrainingBoard"
    case floor10Reward = "CAM_F10_RewardSelection"
    case floor10DescentDoor = "CAM_F10_DescentDoor"
    case floor09Combat = "F09_iPad_MainCamera"
    case floor09Reward = "CAM_F09_RewardSelection"
    case floor09DescentDoor = "CAM_F09_DescentDoor"
    case floor08ResidueCombat = "F08A_iPadCamera"
    case floor08ResidueBossAccess = "CAM_F08A_BossAccessDoor"
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
