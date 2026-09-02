import Foundation

enum GameProgressValidationError: Error, Equatable, Sendable {
    case unsupportedVersion(Int)
    case invalidPlayerHP(Int)
    case floorSceneMismatch(floor: FloorID, scene: SceneID)
    case checkpointSceneMismatch(checkpoint: CheckpointID, scene: SceneID)
    case missingRequirement(String)
    case unknownReward(String)
    case duplicateReward(String)
    case invalidMastery(SpellID)
    case invalidTutorialState(String)
    case completionStateMismatch
}

struct GameProgressValidator: Sendable {
    let supportedSaveVersion: Int

    init(supportedSaveVersion: Int = GameProgress.newGame.saveVersion) {
        self.supportedSaveVersion = supportedSaveVersion
    }

    func validate(_ progress: GameProgress) throws {
        guard (1...supportedSaveVersion).contains(progress.saveVersion) else {
            throw GameProgressValidationError.unsupportedVersion(progress.saveVersion)
        }
        guard (1...GameProgressionController.maximumPlayerHP).contains(progress.playerHP) else {
            throw GameProgressValidationError.invalidPlayerHP(progress.playerHP)
        }

        try validateLocation(progress)
        try validateCollectionIntegrity(progress)
        try validateTutorialState(progress.tutorialProgress)
        try validateProgressionRequirements(progress)
    }

    private func validateLocation(_ progress: GameProgress) throws {
        let expectedFloor = floor(for: progress.currentScene)
        guard progress.currentFloor == expectedFloor else {
            throw GameProgressValidationError.floorSceneMismatch(
                floor: progress.currentFloor,
                scene: progress.currentScene
            )
        }

        let allowedCheckpoints = checkpoints(for: progress.currentScene)
        guard allowedCheckpoints.contains(progress.checkpoint) else {
            throw GameProgressValidationError.checkpointSceneMismatch(
                checkpoint: progress.checkpoint,
                scene: progress.currentScene
            )
        }

        let isCompletionScene = progress.currentScene == .demoComplete
        guard progress.isDemoComplete == isCompletionScene else {
            throw GameProgressValidationError.completionStateMismatch
        }
    }

    private func validateCollectionIntegrity(_ progress: GameProgress) throws {
        guard progress.completedTrainingSpells.isSubset(of: progress.learnedSpells) else {
            throw GameProgressValidationError.missingRequirement("trained spells must be learned")
        }

        for (spell, mastery) in progress.spellMastery {
            guard progress.learnedSpells.contains(spell),
                  mastery.successfulCasts > 0,
                  mastery.bestGrade != .rejected else {
                throw GameProgressValidationError.invalidMastery(spell)
            }
        }

        let knownRewards = Dictionary(
            uniqueKeysWithValues: [FloorID.floor9, .floor8]
                .flatMap { RewardCatalog.candidates(for: $0) }
                .map { ($0.id, $0) }
        )
        var selectedRewards = Set<String>()
        for rewardID in progress.selectedRewardIDs {
            guard knownRewards[rewardID] != nil else {
                throw GameProgressValidationError.unknownReward(rewardID)
            }
            guard selectedRewards.insert(rewardID).inserted else {
                throw GameProgressValidationError.duplicateReward(rewardID)
            }
        }

        for floor in [FloorID.floor9, .floor8] {
            let floorRewardIDs = Set(RewardCatalog.candidates(for: floor).map(\.id))
            let count = progress.selectedRewardIDs.filter(floorRewardIDs.contains).count
            guard count <= 1 else {
                throw GameProgressValidationError.duplicateReward("floor\(floor.rawValue)")
            }
        }
    }

    private func validateTutorialState(_ tutorial: TutorialProgress) throws {
        guard tutorial.completedSequences.isDisjoint(with: tutorial.skippedSequences) else {
            throw GameProgressValidationError.invalidTutorialState(
                "completed and skipped sequences must be disjoint"
            )
        }
        guard (tutorial.activeSequence == nil) == (tutorial.activeStep == nil) else {
            throw GameProgressValidationError.invalidTutorialState(
                "active sequence and step must be stored together"
            )
        }
        if let activeSequence = tutorial.activeSequence,
           tutorial.completedSequences.contains(activeSequence)
            || tutorial.skippedSequences.contains(activeSequence) {
            throw GameProgressValidationError.invalidTutorialState(
                "finished sequence cannot remain active"
            )
        }
        guard tutorial.failureCounts.values.allSatisfy({ $0 >= 0 }) else {
            throw GameProgressValidationError.invalidTutorialState(
                "failure count cannot be negative"
            )
        }
    }

    private func validateProgressionRequirements(_ progress: GameProgress) throws {
        let scene = progress.currentScene
        let floor10Learned: Set<SpellID> = [.afterglowErasure, .riftSeverance]
        let floor9RewardIDs = Set(RewardCatalog.candidates(for: .floor9).map(\.id))
        let floor8RewardIDs = Set(RewardCatalog.candidates(for: .floor8).map(\.id))

        if ![SceneID.floor10MeetingRoom, .floor10Office].contains(scene) {
            try require(
                progress.learnedSpells.contains(.afterglowErasure),
                "잔광 말소 습득"
            )
        }

        if scene == .floor10GlyphArchive
            || progress.learnedSpells.contains(.riftSeverance) {
            try require(
                progress.completedTrainingSpells.contains(.afterglowErasure),
                "잔광 말소 훈련 완료"
            )
        }

        if scene == .floor10DescentDoor || progress.currentFloor != .floor10 {
            try require(
                progress.learnedSpells.isSuperset(of: floor10Learned)
                    && progress.completedTrainingSpells.isSuperset(of: floor10Learned),
                "10층 공격 주문 훈련 완료"
            )
        }

        if [
            SceneID.floor9RecordsDefeated,
            SceneID.floor9RewardVault,
            .floor9DescentDoor,
            .floor8Antechamber,
            .floor8ProtectionRoom,
            .floor8ResidualEncounter,
            .floor8ResidualBattle,
            .floor8ResidualDefeated,
            .floor8SealedDoor,
            .floor8AdministratorEncounter,
            .floor8AdministratorBattle,
            .floor8AdministratorDefeated,
            .floor8Reward,
            .floor8DescentDoor,
            .demoComplete
        ].contains(scene) {
            try require(
                progress.defeatedEnemies.contains(.recordsAdministrator),
                "기록 관리자 처치"
            )
        }

        if scene == .floor9DescentDoor || progress.currentFloor.rawValue <= FloorID.floor8.rawValue {
            try require(
                progress.selectedRewardIDs.contains(where: floor9RewardIDs.contains)
                    && progress.learnedSpells.contains(.barrierPiercing),
                "9층 주문서 선택"
            )
        }

        if [
            SceneID.floor8ResidualEncounter,
            .floor8ResidualBattle,
            .floor8ResidualDefeated,
            .floor8SealedDoor,
            .floor8AdministratorBattle,
            .floor8Reward,
            .floor8DescentDoor,
            .demoComplete
        ].contains(scene) {
            try require(
                progress.learnedSpells.contains(.basicBarrier)
                    && progress.completedTrainingSpells.contains(.basicBarrier),
                "초급 방벽 훈련 완료"
            )
        }

        if [
            SceneID.floor8ResidualDefeated,
            .floor8SealedDoor,
            .floor8AdministratorEncounter,
            .floor8AdministratorBattle,
            .floor8AdministratorDefeated,
            .floor8Reward,
            .floor8DescentDoor,
            .demoComplete
        ].contains(scene) {
            try require(
                progress.defeatedEnemies.contains(.observationResidual),
                "관측 잔류체 처치"
            )
        }

        if [
            SceneID.floor8AdministratorEncounter,
            .floor8AdministratorBattle,
            .floor8AdministratorDefeated,
            .floor8Reward,
            .floor8DescentDoor,
            .demoComplete
        ].contains(scene) {
            try require(
                progress.learnedSpells.contains(.sealRelease),
                "봉인 해제 습득"
            )
        }

        if [
            SceneID.floor8AdministratorDefeated,
            .floor8Reward,
            .floor8DescentDoor,
            .demoComplete
        ].contains(scene) {
            try require(
                progress.defeatedEnemies.contains(.observationAdministrator),
                "관측 관리자 처치"
            )
        }

        if [SceneID.floor8DescentDoor, .demoComplete].contains(scene) {
            try require(
                progress.selectedRewardIDs.contains(where: floor8RewardIDs.contains),
                "8층 주문서 선택"
            )
        }

        if progress.defeatedEnemies.contains(.observationResidual) {
            try require(
                progress.defeatedEnemies.contains(.recordsAdministrator),
                "9층 선행 전투 완료"
            )
        }
        if progress.defeatedEnemies.contains(.observationAdministrator) {
            try require(
                progress.defeatedEnemies.isSuperset(of: [
                    .recordsAdministrator,
                    .observationResidual
                ]),
                "8층 선행 전투 완료"
            )
        }
    }

    private func require(_ condition: @autoclosure () -> Bool, _ name: String) throws {
        guard condition() else {
            throw GameProgressValidationError.missingRequirement(name)
        }
    }

    private func floor(for scene: SceneID) -> FloorID {
        switch scene {
        case .floor10MeetingRoom,
             .floor10Office,
             .floor10GlyphArchive,
             .floor10TrainingWall,
             .floor10DescentDoor:
            .floor10
        case .floor9Entrance,
             .floor9RecordsEncounter,
             .floor9RecordsBattle,
             .floor9RecordsDefeated,
             .floor9RewardVault,
             .floor9DescentDoor:
            .floor9
        case .floor8Antechamber,
             .floor8ProtectionRoom,
             .floor8ResidualEncounter,
             .floor8ResidualBattle,
             .floor8ResidualDefeated,
             .floor8SealedDoor,
             .floor8AdministratorEncounter,
             .floor8AdministratorBattle,
             .floor8AdministratorDefeated,
             .floor8Reward,
             .floor8DescentDoor:
            .floor8
        case .demoComplete:
            .floor7
        }
    }

    private func checkpoints(for scene: SceneID) -> Set<CheckpointID> {
        switch scene {
        case .floor10MeetingRoom,
             .floor10Office,
             .floor10GlyphArchive,
             .floor10TrainingWall,
             .floor10DescentDoor:
            [.floor10Start]
        case .floor9Entrance:
            [.floor10Complete]
        case .floor9RecordsEncounter, .floor9RecordsBattle:
            [.recordsBattle]
        case .floor9RecordsDefeated, .floor9RewardVault, .floor9DescentDoor:
            [.recordsDefeated]
        case .floor8Antechamber, .floor8ProtectionRoom:
            [.floor8Start]
        case .floor8ResidualEncounter, .floor8ResidualBattle:
            [.residualBattle]
        case .floor8ResidualDefeated, .floor8SealedDoor:
            [.residualDefeated]
        case .floor8AdministratorEncounter, .floor8AdministratorBattle:
            [.observationBattle]
        case .floor8AdministratorDefeated, .floor8Reward, .floor8DescentDoor:
            [.observationDefeated]
        case .demoComplete:
            [.demoComplete]
        }
    }

}
