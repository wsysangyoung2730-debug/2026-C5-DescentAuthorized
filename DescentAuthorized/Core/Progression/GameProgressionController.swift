import Foundation

enum ProgressionError: Error, Equatable {
    case invalidScene(expected: [SceneID], actual: SceneID)
    case unexpectedSpell(SpellID)
    case unexpectedEnemy(EnemyID)
    case unknownReward(String)
    case rewardAlreadySelected
    case requirementMissing(String)
}

enum ProgressionEvent: Equatable, Sendable {
    case sceneChanged(SceneID)
    case spellLearned(SpellID)
    case trainingCompleted(spell: SpellID, grade: CastingGrade)
    case enemyDefeated(EnemyID)
    case rewardCandidates([RewardCandidate])
    case rewardSelected(candidateID: String, spell: SpellID?)
    case hpRestored(amount: Int, currentHP: Int)
    case checkpointChanged(CheckpointID)
    case recordRead(String)
    case masteryUpdated(spell: SpellID, mastery: SpellMastery)
    case tutorialStarted(sequence: TutorialSequenceID, step: TutorialStepID)
    case tutorialStepCompleted(TutorialStepID)
    case tutorialCompleted(TutorialSequenceID)
    case tutorialSkipped(TutorialSequenceID)
    case tutorialFailureRecorded(mechanic: TutorialMechanicID, count: Int)
    case tutorialReplayRequested(TutorialSequenceID)
    case tutorialsReset
    case demoCompleted
}

struct GameProgressionController: Sendable {
    static let maximumPlayerHP = 100

    private(set) var progress: GameProgress

    init(progress: GameProgress = .newGame) {
        self.progress = progress
        self.progress.synchronizeLoadout()
        self.progress.rememberCheckpointRewards()
        self.progress.migrateExpansionCheckpoint()
        self.progress.ensureLowerRewardOffer()
        switch self.progress.currentScene {
        case .floor9RecordsBattle: self.progress.currentScene = .floor9RecordsPreparation; self.progress.playerHP = 100
        case .floor8ResidualBattle: self.progress.currentScene = .floor8ResidualPreparation; self.progress.playerHP = 100
        case .floor8AdministratorBattle: self.progress.currentScene = .floor8AdministratorPreparation; self.progress.playerHP = 100
        case .floor9RecordsEncounter: self.progress.currentScene = .floor9RecordsPreparation
        case .floor8ResidualEncounter: self.progress.currentScene = .floor8ResidualPreparation
        case .floor8AdministratorEncounter: self.progress.currentScene = .floor8AdministratorPreparation
        default: break
        }
        if let expansion = self.progress.expansion {
            self.progress.expansion?.stage = expansion.resumableStage
            if expansion.stage.isBattle {
                self.progress.playerHP = Self.maximumPlayerHP
            }
        }
    }

    // MARK: - 7–5F extension foundation

    /// The completed 8F save remains the compatibility anchor for the extension.
    mutating func beginExpansion() throws {
        try requireScene(.demoComplete)
        guard progress.isDemoComplete else {
            throw ProgressionError.requirementMissing("8층 하강 승인 완료")
        }
        if progress.expansion == nil {
            progress.expansion = ExpansionProgress()
            progress.playerHP = Self.maximumPlayerHP
        }
        progress.synchronizeLoadout()
        progress.migrateExpansionCheckpoint()
    }

    mutating func advanceExpansion() throws -> [ProgressionEvent] {
        guard var current = progress.expansion else {
            try beginExpansion()
            return []
        }
        switch current.stage {
        case .entrance:
            current.stage = current.floorNumber == 6 && !progress.learnedSpells.contains(.outputReduction) ? .learnDebuff : .preparation
        case .preparation, .bossPreparation:
            if current.stage == .preparation, current.floorNumber == 6,
               !progress.learnedSpells.contains(.outputReduction) {
                current.stage = .learnDebuff
                break
            }
            guard progress.loadoutIssues.isEmpty,
                  ExpansionEnemyCatalog.enemy(floor: current.floorNumber, isBoss: current.stage == .bossPreparation, residualIndex: current.residualIndex) != nil else {
                throw ProgressionError.requirementMissing("유효한 출전 준비")
            }
            current.stage = current.stage == .preparation ? .residualEncounter : .bossEncounter
        case .residualEncounter, .bossEncounter:
            guard progress.loadoutIssues.isEmpty else {
                throw ProgressionError.requirementMissing("유효한 출전 준비")
            }
            current.stage = current.stage == .residualEncounter ? .residualBattle : .bossBattle
        case .residualDefeated:
            if current.isLowerFloor && current.residualIndex == 0 { current.stage = .residualInvestigation }
            else { current.stage = [3,4].contains(current.floorNumber) ? .recordReward : .sealedDoor }
        case .residualInvestigation:
            current.residualIndex = 1
            current.stage = .preparation
        case .bossDefeated: current.stage = current.floorNumber == 1 ? .finalRecord : .reward
        case .finalRecord:
            progress.readRecordIDs.insert("floor1.final-approval")
            current.stage = .descent
        case .recordReward, .reward:
            guard let site = current.rewardSite, progress.currentRewardCandidates.isEmpty else {
                throw ProgressionError.requirementMissing("보상 주문을 선택하고 학습하세요.")
            }
            progress.completedLowerRewardSites.insert(site.rawValue)
            current.stage = site.isRecord ? .sealedDoor : .descent
        case .descent:
            guard current.descentStage == current.requiredDescentStages else { throw ProgressionError.requirementMissing("하강 승인 \(current.requiredDescentStages)단계 완료") }
            if current.floorNumber == 1 {
                current.stage = .complete
                progress.readRecordIDs.insert("floor1.tower-handoff")
            } else {
                let lower = current.floorNumber <= 5
                current.floorNumber -= 1
                current.stage = .entrance
                current.descentStage = 0
                current.residualIndex = 0
                progress.playerHP = lower ? min(Self.maximumPlayerHP, progress.playerHP + 30) : Self.maximumPlayerHP
            }
        default: throw ProgressionError.requirementMissing("현재 단계의 절차를 먼저 완료하세요.")
        }
        try updateExpansion(current)
        return []
    }

    mutating func learnExpansionDebuff(grade: CastingGrade) throws -> [ProgressionEvent] {
        guard progress.expansion?.floorNumber == 6, progress.expansion?.stage == .learnDebuff else {
            throw ProgressionError.requirementMissing("6층 고정 주문 학습")
        }
        let events = try learnExpansionSpell(.outputReduction, grade: grade)
        progress.expansion?.stage = .preparation
        progress.migrateExpansionCheckpoint()
        return events
    }

    mutating func releaseExpansionSeal(grade: CastingGrade) throws -> [ProgressionEvent] {
        guard progress.expansion?.stage == .sealedDoor,
              progress.learnedSpells.contains(.sealRelease), grade != .rejected else {
            throw ProgressionError.requirementMissing("봉인 해제 각인 성공")
        }
        progress.expansion?.stage = .bossPreparation
        progress.migrateExpansionCheckpoint()
        return [updateMastery(spell: .sealRelease, grade: grade)]
    }

    mutating func approveExpansionStage(_ count: Int) throws {
        guard let current = progress.expansion, current.stage == .descent,
              (1...current.requiredDescentStages).contains(count), count == current.descentStage || count == current.descentStage + 1 else {
            throw ProgressionError.requirementMissing("순서에 맞는 하강 승인")
        }
        progress.expansion?.descentStage = count
    }

    mutating func updateExpansion(_ expansion: ExpansionProgress) throws {
        try requireScene(.demoComplete)
        guard progress.expansion != nil else {
            throw ProgressionError.requirementMissing("확장 구간 진입")
        }
        guard expansion.isValid else {
            throw ProgressionError.requirementMissing("유효한 확장 진행 단계")
        }
        progress.expansion = expansion
        progress.ensureLowerRewardOffer()
        progress.migrateExpansionCheckpoint()
    }

    mutating func configureLoadout(
        _ spells: [SpellID], protectedAttack: SpellID? = nil, protectedDefense: SpellID? = nil
    ) throws {
        let legacyBattleScenes: Set<SceneID> = [
            .floor9RecordsBattle, .floor8ResidualBattle, .floor8AdministratorBattle
        ]
        guard progress.expansion?.stage.isBattle != true,
              progress.expansion?.stage.isEncounter != true,
              !legacyBattleScenes.contains(progress.currentScene) else {
            throw ProgressionError.requirementMissing("전투 시작 전에만 주문 변경 가능")
        }
        guard progress.setLoadout(
            spells, protectedAttack: protectedAttack, protectedDefense: protectedDefense
        ) else {
            throw ProgressionError.requirementMissing(
                LoadoutRules.issues(for: spells, learned: progress.learnedSpells)
                    .map(\.message).joined(separator: " ")
            )
        }
    }

    mutating func markLoadoutTutorial(_ flag: LoadoutTutorialFlag) {
        progress.loadoutTutorials.insert(flag)
    }

    mutating func learnExpansionSpell(
        _ spell: SpellID, grade: CastingGrade = .approved
    ) throws -> [ProgressionEvent] {
        guard progress.expansion != nil, grade != .rejected else {
            throw ProgressionError.requirementMissing("확장 구간 주문 학습 완료")
        }
        var events: [ProgressionEvent] = []
        if progress.learnedSpells.insert(spell).inserted {
            events.append(.spellLearned(spell))
        }
        progress.completedTrainingSpells.insert(spell)
        events.append(updateMastery(spell: spell, grade: grade))
        events.append(.trainingCompleted(spell: spell, grade: grade))
        return events
    }

    /// Effects remain in combat; only the durable encounter result is recorded here.
    mutating func recordExpansionVictory(
        enemy: EnemyID, remainingPlayerHP: Int
    ) throws -> [ProgressionEvent] {
        guard let expansion = progress.expansion, expansion.stage.isBattle else {
            throw ProgressionError.requirementMissing("진행 중인 확장 전투")
        }
        guard ExpansionEnemyCatalog.enemy(floor: expansion.floorNumber, isBoss: expansion.stage == .bossBattle,
            residualIndex: expansion.residualIndex)?.id == enemy else { throw ProgressionError.unexpectedEnemy(enemy) }
        let remaining = min(max(remainingPlayerHP, 1), Self.maximumPlayerHP)
        progress.playerHP = expansion.stage == .residualBattle ? min(100, max(60, remaining + 20)) : remaining
        progress.defeatedEnemies.insert(enemy)
        progress.expansion?.stage = expansion.stage == .residualBattle
            ? .residualDefeated : .bossDefeated
        progress.migrateExpansionCheckpoint()
        return [.enemyDefeated(enemy)]
    }

    mutating func setExpansionPlayerHP(_ hp: Int) {
        guard progress.expansion != nil else { return }
        progress.playerHP = min(max(hp, 1), Self.maximumPlayerHP)
    }

    mutating func retryExpansionBattle() throws {
        guard let expansion = progress.expansion, expansion.stage.isBattle else {
            throw ProgressionError.requirementMissing("재도전할 확장 전투")
        }
        progress.expansion?.stage = expansion.resumableStage
        progress.playerHP = Self.maximumPlayerHP
    }

    mutating func leaveMeetingRoom() throws -> [ProgressionEvent] {
        try requireScene(.floor10MeetingRoom)
        return move(to: .floor10Office)
    }

    mutating func learnAfterglowErasure() throws -> [ProgressionEvent] {
        try requireScene(.floor10Office)
        progress.learnedSpells.insert(.afterglowErasure)
        progress.tutorials.formUnion([.cardSelection, .drawing])
        return [
            .spellLearned(.afterglowErasure),
            .sceneChanged(setScene(.floor10TrainingWall))
        ]
    }

    mutating func learnRiftSeverance() throws -> [ProgressionEvent] {
        try requireScene(.floor10GlyphArchive)
        progress.learnedSpells.insert(.riftSeverance)
        return [
            .spellLearned(.riftSeverance),
            .sceneChanged(setScene(.floor10TrainingWall))
        ]
    }

    mutating func completeScrollLearning(
        spell: SpellID,
        grade: CastingGrade
    ) throws -> [ProgressionEvent] {
        guard grade != .rejected else {
            throw ProgressionError.requirementMissing("successful scroll tracing")
        }

        let destination: SceneID?
        switch spell {
        case .afterglowErasure:
            try requireScene(.floor10Office)
            progress.tutorials.formUnion([.cardSelection, .drawing])
            destination = .floor10GlyphArchive

        case .riftSeverance:
            try requireScene(.floor10GlyphArchive)
            guard progress.completedTrainingSpells.contains(.afterglowErasure) else {
                throw ProgressionError.requirementMissing("afterglow scroll learning")
            }
            destination = .floor10DescentDoor

        case .basicBarrier:
            try requireScene(.floor8Antechamber)
            progress.tutorials.insert(.defense)
            destination = nil

        case .sealRelease:
            try requireScene(.floor8SealedDoor)
            destination = nil

        default:
            throw ProgressionError.unexpectedSpell(spell)
        }

        progress.learnedSpells.insert(spell)
        progress.completedTrainingSpells.insert(spell)

        var events: [ProgressionEvent] = [
            .spellLearned(spell),
            .trainingCompleted(spell: spell, grade: grade),
            updateMastery(spell: spell, grade: grade)
        ]
        if let destination {
            events.append(.sceneChanged(setScene(destination)))
        }
        return events
    }

    mutating func completeTraining(
        spell: SpellID,
        grade: CastingGrade
    ) throws -> [ProgressionEvent] {
        try requireScene(.floor10TrainingWall)
        guard progress.learnedSpells.contains(spell) else {
            throw ProgressionError.requirementMissing("learned spell: \(spell.rawValue)")
        }
        guard grade != .rejected else {
            throw ProgressionError.requirementMissing("successful training cast")
        }

        let destination: SceneID
        switch spell {
        case .afterglowErasure:
            destination = .floor10GlyphArchive
        case .riftSeverance:
            guard progress.completedTrainingSpells.contains(.afterglowErasure) else {
                throw ProgressionError.requirementMissing("afterglow training")
            }
            destination = .floor10DescentDoor
        default:
            throw ProgressionError.unexpectedSpell(spell)
        }

        progress.completedTrainingSpells.insert(spell)
        let masteryEvent = updateMastery(spell: spell, grade: grade)
        return [
            .trainingCompleted(spell: spell, grade: grade),
            masteryEvent,
            .sceneChanged(setScene(destination))
        ]
    }

    mutating func approveDescentDoor() throws -> [ProgressionEvent] {
        switch progress.currentScene {
        case .floor10DescentDoor:
            let required: Set<SpellID> = [.afterglowErasure, .riftSeverance]
            guard progress.completedTrainingSpells.isSuperset(of: required) else {
                throw ProgressionError.requirementMissing("two floor 10 training spells")
            }
            progress.currentFloor = .floor9
            reachCheckpoint(.floor10Complete)
            return [
                .checkpointChanged(.floor10Complete),
                .sceneChanged(setScene(.floor9Entrance))
            ]

        case .floor9DescentDoor:
            guard RewardCatalog.candidates(for: .floor9).contains(where: {
                progress.selectedRewardIDs.contains($0.id)
                    && progress.learnedSpells.contains(RewardCatalog.learningSpell(for: $0))
            }) else {
                throw ProgressionError.requirementMissing("9층 보상 주문 학습 완료")
            }
            let recovery = restoreHP(by: 30)
            progress.currentFloor = .floor8
            reachCheckpoint(.floor8Start)
            return [
                recovery,
                .checkpointChanged(.floor8Start),
                .sceneChanged(setScene(.floor8Antechamber))
            ]

        case .floor8DescentDoor:
            guard RewardCatalog.candidates(for: .floor8).contains(where: {
                progress.selectedRewardIDs.contains($0.id)
            }) else {
                throw ProgressionError.requirementMissing("floor 8 reward selection")
            }
            progress.currentFloor = .floor7
            progress.currentScene = .demoComplete
            reachCheckpoint(.demoComplete)
            progress.isDemoComplete = true
            try beginExpansion()
            return [
                .checkpointChanged(.demoComplete),
                .sceneChanged(.demoComplete),
                .demoCompleted
            ]

        default:
            throw ProgressionError.invalidScene(
                expected: [.floor10DescentDoor, .floor9DescentDoor, .floor8DescentDoor],
                actual: progress.currentScene
            )
        }
    }

    mutating func enterRecordsBattle() throws -> [ProgressionEvent] {
        try requireScene(.floor9Entrance)
        reachCheckpoint(.recordsBattle)
        progress.tutorials.formUnion([.mana, .strokeCount, .enemyIntent, .hp])
        return [
            .checkpointChanged(.recordsBattle),
            .sceneChanged(setScene(.floor9RecordsPreparation))
        ]
    }

    mutating func enterRecordsEncounter() throws -> [ProgressionEvent] {
        try requireScene(.floor9RecordsPreparation)
        return [.sceneChanged(setScene(.floor9RecordsEncounter))]
    }

    mutating func beginRecordsBattle() throws -> [ProgressionEvent] {
        try requireScene(.floor9RecordsEncounter)
        return [.sceneChanged(setScene(.floor9RecordsBattle))]
    }

    mutating func continueAfterRecordsDefeat() throws -> [ProgressionEvent] {
        try requireScene(.floor9RecordsDefeated)
        return [
            .sceneChanged(setScene(.floor9RewardVault)),
            .rewardCandidates(RewardCatalog.candidates(for: .floor9))
        ]
    }

    mutating func enterProtectionRoom() throws -> [ProgressionEvent] {
        try requireScene(.floor8Antechamber)
        if progress.completedTrainingSpells.contains(.basicBarrier) {
            reachCheckpoint(.residualBattle)
            return [
                .checkpointChanged(.residualBattle),
                .sceneChanged(setScene(.floor8ResidualPreparation))
            ]
        }
        return move(to: .floor8ProtectionRoom)
    }

    mutating func learnBasicBarrier() throws -> [ProgressionEvent] {
        try requireScene(.floor8ProtectionRoom)
        progress.learnedSpells.insert(.basicBarrier)
        progress.tutorials.insert(.defense)
        return [.spellLearned(.basicBarrier)]
    }

    mutating func completeProtectionTraining(
        grade: CastingGrade
    ) throws -> [ProgressionEvent] {
        try requireScene(.floor8ProtectionRoom)
        guard progress.learnedSpells.contains(.basicBarrier) else {
            throw ProgressionError.requirementMissing("learned basic barrier")
        }
        guard grade != .rejected else {
            throw ProgressionError.requirementMissing("successful barrier training cast")
        }

        progress.completedTrainingSpells.insert(.basicBarrier)
        reachCheckpoint(.residualBattle)
        return [
            .trainingCompleted(spell: .basicBarrier, grade: grade),
            updateMastery(spell: .basicBarrier, grade: grade),
            .checkpointChanged(.residualBattle),
            .sceneChanged(setScene(.floor8ResidualPreparation))
        ]
    }

    mutating func enterResidualEncounter() throws -> [ProgressionEvent] {
        try requireScene(.floor8ResidualPreparation)
        return [.sceneChanged(setScene(.floor8ResidualEncounter))]
    }

    mutating func beginResidualBattle() throws -> [ProgressionEvent] {
        try requireScene(.floor8ResidualEncounter)
        return [.sceneChanged(setScene(.floor8ResidualBattle))]
    }

    mutating func continueAfterResidualDefeat() throws -> [ProgressionEvent] {
        try requireScene(.floor8ResidualDefeated)
        return [.sceneChanged(setScene(.floor8SealedDoor))]
    }

    mutating func releaseObservationDoor() throws -> [ProgressionEvent] {
        try requireScene(.floor8SealedDoor)
        guard progress.learnedSpells.contains(.sealRelease) else {
            throw ProgressionError.requirementMissing("seal release spell")
        }
        reachCheckpoint(.observationBattle)
        progress.tutorials.formUnion([.absoluteBarrier, .dispel, .strongAttack])
        return [
            .checkpointChanged(.observationBattle),
            .sceneChanged(setScene(.floor8AdministratorPreparation))
        ]
    }

    mutating func enterAdministratorEncounter() throws -> [ProgressionEvent] {
        try requireScene(.floor8AdministratorPreparation)
        return [.sceneChanged(setScene(.floor8AdministratorEncounter))]
    }

    mutating func beginAdministratorBattle() throws -> [ProgressionEvent] {
        try requireScene(.floor8AdministratorEncounter)
        return [.sceneChanged(setScene(.floor8AdministratorBattle))]
    }

    mutating func continueAfterAdministratorDefeat() throws -> [ProgressionEvent] {
        try requireScene(.floor8AdministratorDefeated)
        return [
            .sceneChanged(setScene(.floor8Reward)),
            .rewardCandidates(RewardCatalog.candidates(for: .floor8))
        ]
    }

    mutating func restartCurrentEncounter() throws -> [ProgressionEvent] {
        let battleScenes: [SceneID] = [
            .floor9RecordsBattle,
            .floor8ResidualBattle,
            .floor8AdministratorBattle
        ]
        guard battleScenes.contains(progress.currentScene) else {
            throw ProgressionError.invalidScene(
                expected: battleScenes,
                actual: progress.currentScene
            )
        }

        let previousHP = progress.playerHP
        progress.playerHP = Self.maximumPlayerHP
        return [
            .hpRestored(
                amount: Self.maximumPlayerHP - previousHP,
                currentHP: Self.maximumPlayerHP
            )
        ]
    }

    mutating func returnToBattlePreparation() throws -> [ProgressionEvent] {
        if progress.expansion != nil {
            try retryExpansionBattle()
            return []
        }
        var events = try restartCurrentEncounter()
        let scene: SceneID
        switch progress.currentScene {
        case .floor9RecordsBattle: scene = .floor9RecordsPreparation
        case .floor8ResidualBattle: scene = .floor8ResidualPreparation
        case .floor8AdministratorBattle: scene = .floor8AdministratorPreparation
        default: throw ProgressionError.requirementMissing("재도전할 전투")
        }
        events.append(.sceneChanged(setScene(scene)))
        return events
    }

    mutating func completeEncounter(
        enemy: EnemyID,
        remainingPlayerHP: Int
    ) throws -> [ProgressionEvent] {
        let expectedEnemy: EnemyID
        switch progress.currentScene {
        case .floor9RecordsBattle:
            expectedEnemy = .recordsAdministrator
        case .floor8ResidualBattle:
            expectedEnemy = .observationResidual
        case .floor8AdministratorBattle:
            expectedEnemy = .observationAdministrator
        default:
            throw ProgressionError.invalidScene(
                expected: [
                    .floor9RecordsBattle,
                    .floor8ResidualBattle,
                    .floor8AdministratorBattle
                ],
                actual: progress.currentScene
            )
        }
        guard enemy == expectedEnemy else {
            throw ProgressionError.unexpectedEnemy(enemy)
        }
        guard !progress.defeatedEnemies.contains(enemy) else {
            throw ProgressionError.requirementMissing("undefeated enemy")
        }

        progress.playerHP = min(max(remainingPlayerHP, 1), Self.maximumPlayerHP)
        progress.defeatedEnemies.insert(enemy)

        switch enemy {
        case .recordsAdministrator:
            reachCheckpoint(.recordsDefeated)
            progress.tutorials.formUnion([.normalBarrier, .erasureZone, .rewardSelection])
            return [
                .enemyDefeated(enemy),
                .checkpointChanged(.recordsDefeated),
                .sceneChanged(setScene(.floor9RecordsDefeated))
            ]

        case .observationResidual:
            let recovery = restoreHP(by: 20, minimum: 60)
            reachCheckpoint(.residualDefeated)
            return [
                .enemyDefeated(enemy),
                recovery,
                .checkpointChanged(.residualDefeated),
                .sceneChanged(setScene(.floor8ResidualDefeated))
            ]

        case .observationAdministrator:
            reachCheckpoint(.observationDefeated)
            return [
                .enemyDefeated(enemy),
                .checkpointChanged(.observationDefeated),
                .sceneChanged(setScene(.floor8AdministratorDefeated))
            ]
        default:
            throw ProgressionError.unexpectedEnemy(enemy)
        }
    }

    private func currentRewardFloor() throws -> Int {
        if let expansion = progress.expansion, [.reward, .recordReward].contains(expansion.stage) {
            return expansion.floorNumber
        }
        switch progress.currentScene {
        case .floor9RewardVault: return 9
        case .floor8Reward: return 8
        default: throw ProgressionError.requirementMissing("보상 선택 단계")
        }
    }

    mutating func selectReward(candidateID: String) throws -> [ProgressionEvent] {
        let floor = try currentRewardFloor()
        let candidates = progress.expansion?.rewardSite != nil ? progress.currentRewardCandidates : RewardCatalog.candidates(forFloorNumber: floor)
        guard !candidates.contains(where: { progress.selectedRewardIDs.contains($0.id) }) else {
            throw ProgressionError.rewardAlreadySelected
        }
        guard let selected = candidates.first(where: { $0.id == candidateID }) else {
            throw ProgressionError.unknownReward(candidateID)
        }
        progress.selectedRewardIDs.append(selected.id)
        if let site = progress.expansion?.rewardSite { progress.lowerRewardChoices[site.rawValue] = selected.id }
        else { progress.checkpointRewardChoices[floor] = selected.id }
        return [.rewardSelected(candidateID: selected.id, spell: selected.resolvedSpell)]
    }

    mutating func completeRewardLearning(candidateID: String, grade: CastingGrade) throws -> [ProgressionEvent] {
        guard grade != .rejected else { throw ProgressionError.requirementMissing("성공한 시험 각인") }
        let floor = try currentRewardFloor()
        let candidates = progress.expansion?.rewardSite != nil ? progress.currentRewardCandidates : RewardCatalog.candidates(forFloorNumber: floor)
        guard progress.selectedRewardIDs.contains(candidateID),
              let selected = candidates.first(where: { $0.id == candidateID }) else {
            throw ProgressionError.requirementMissing("선택한 보상 두루마리")
        }
        let spell = RewardCatalog.learningSpell(for: selected)
        let isNew = progress.learnedSpells.insert(spell).inserted
        progress.completedTrainingSpells.insert(spell)
        var events: [ProgressionEvent] = isNew ? [.spellLearned(spell)] : []
        events.append(.trainingCompleted(spell: spell, grade: grade))
        events.append(updateMastery(spell: spell, grade: grade))
        if progress.expansion != nil {
            let site = progress.expansion?.rewardSite
            if let site { progress.completedLowerRewardSites.insert(site.rawValue) }
            progress.expansion?.stage = site?.isRecord == true ? .sealedDoor : .descent
            progress.expansion?.descentStage = 0
            progress.migrateExpansionCheckpoint()
        } else {
            events.append(.sceneChanged(setScene(floor == 9 ? .floor9DescentDoor : .floor8DescentDoor)))
        }
        return events
    }

    mutating func travel(to checkpoint: CheckpointID) throws -> [ProgressionEvent] {
        guard checkpoint.progressionIndex <= progress.furthestCheckpoint.progressionIndex else {
            throw ProgressionError.requirementMissing("unlocked checkpoint")
        }

        progress.rememberCheckpointRewards()
        let oldEquipped = progress.equippedSpells
        func rememberedReward(_ floor: Int) -> RewardCandidate? {
            let candidates = RewardCatalog.candidates(forFloorNumber: floor)
            return candidates.first { $0.id == progress.checkpointRewardChoices[floor] } ?? candidates.first
        }
        let destination = checkpoint.destination
        let targetIndex = checkpoint.progressionIndex

        progress.currentFloor = destination.floor
        progress.currentScene = destination.scene
        progress.checkpoint = checkpoint
        progress.playerHP = Self.maximumPlayerHP
        progress.isDemoComplete = checkpoint.expansionDestination != nil
        progress.expansion = checkpoint.expansionDestination
        progress.learnedSpells = []
        progress.completedTrainingSpells = []
        progress.defeatedEnemies = []
        progress.selectedRewardIDs = []
        progress.completedLowerRewardSites = []

        if targetIndex >= CheckpointID.floor10Complete.progressionIndex {
            let floor10Spells: Set<SpellID> = [.afterglowErasure, .riftSeverance]
            progress.learnedSpells.formUnion(floor10Spells)
            progress.completedTrainingSpells.formUnion(floor10Spells)
        }
        if targetIndex >= CheckpointID.recordsDefeated.progressionIndex {
            progress.defeatedEnemies.insert(.recordsAdministrator)
        }
        if targetIndex >= CheckpointID.floor8Start.progressionIndex {
            let reward = rememberedReward(9)
                ?? RewardCatalog.candidates(for: .floor9)[0]
            progress.selectedRewardIDs.append(reward.id)
            progress.learnedSpells.insert(RewardCatalog.learningSpell(for: reward))
            progress.completedTrainingSpells.insert(RewardCatalog.learningSpell(for: reward))
        }
        if targetIndex >= CheckpointID.residualBattle.progressionIndex {
            progress.learnedSpells.insert(.basicBarrier)
            progress.completedTrainingSpells.insert(.basicBarrier)
        }
        if targetIndex >= CheckpointID.residualDefeated.progressionIndex {
            progress.defeatedEnemies.insert(.observationResidual)
        }
        if targetIndex >= CheckpointID.observationBattle.progressionIndex {
            progress.learnedSpells.insert(.sealRelease)
            progress.completedTrainingSpells.insert(.sealRelease)
        }
        if targetIndex >= CheckpointID.observationDefeated.progressionIndex {
            progress.defeatedEnemies.insert(.observationAdministrator)
        }
        if targetIndex >= CheckpointID.demoComplete.progressionIndex {
            let reward = rememberedReward(8)
                ?? RewardCatalog.candidates(for: .floor8)[0]
            progress.selectedRewardIDs.append(reward.id)
            let rewardSpell = RewardCatalog.learningSpell(for: reward)
            progress.learnedSpells.insert(rewardSpell)
            progress.completedTrainingSpells.insert(rewardSpell)
        }

        if let expansion = checkpoint.expansionDestination {
            for floor in stride(from: 7, through: 5, by: -1) {
                let current = expansion.floorNumber == floor
                let completed = floor > expansion.floorNumber
                if completed || (current && [.sealedDoor, .bossPreparation, .reward, .descent].contains(expansion.stage)) {
                    if let enemy = ExpansionEnemyCatalog.enemy(floor: floor, isBoss: false) {
                        progress.defeatedEnemies.insert(enemy.id)
                    }
                }
                if completed || (current && [.reward, .descent].contains(expansion.stage)) {
                    if let enemy = ExpansionEnemyCatalog.enemy(floor: floor, isBoss: true) {
                        progress.defeatedEnemies.insert(enemy.id)
                    }
                }
                if completed || (current && expansion.stage == .descent), let reward = rememberedReward(floor) {
                    progress.selectedRewardIDs.append(reward.id)
                    let spell = RewardCatalog.learningSpell(for: reward)
                    progress.learnedSpells.insert(spell)
                    progress.completedTrainingSpells.insert(spell)
                }
            }
            if expansion.floorNumber < 6 || (expansion.floorNumber == 6 && ![.entrance, .learnDebuff].contains(expansion.stage)) {
                progress.learnedSpells.insert(.outputReduction)
                progress.completedTrainingSpells.insert(.outputReduction)
            }
            if expansion.isLowerFloor { progress.restoreLowerMilestones(to: expansion) }
        }

        // Keep records from earlier floors, reset the destination investigation and all later floors.
        let targetFloor = checkpoint.expansionDestination?.floorNumber ?? destination.floor.rawValue
        progress.readRecordIDs = progress.readRecordIDs.filter { id in
            let floor = (1...10).first { id.hasPrefix("floor\($0).") || id.hasPrefix("\($0)-") }
            return floor.map { $0 > targetFloor } ?? false
        }
        if targetIndex >= CheckpointID.recordsBattle.progressionIndex {
            progress.readRecordIDs.formUnion(["9-entrance-01", "floor9.entrance.erased-monitor"])
        }
        if targetIndex >= CheckpointID.residualBattle.progressionIndex {
            progress.readRecordIDs.formUnion(["floor8.entrance.warning-tags", "floor8.entrance.floor-anchor"])
        }
        for floor in 1...7 {
            if floor > targetFloor || (floor == targetFloor && checkpoint.expansionDestination?.stage != .entrance) {
                progress.readRecordIDs.formUnion(ExpansionInvestigationCatalog.records(for: floor).map(\.id))
            }
        }
        // Preserve card ordering, replacing a superseded reward card with the new choice for that floor.
        progress.equippedSpells = oldEquipped.compactMap { spell in
            if progress.learnedSpells.contains(spell) { return spell }
            for floor in 5...9 where RewardCatalog.candidates(forFloorNumber: floor).contains(where: { $0.resolvedSpell == spell }) {
                if let replacement = rememberedReward(floor)?.resolvedSpell, progress.learnedSpells.contains(replacement) { return replacement }
            }
            return nil
        }
        progress.synchronizeLoadout(automaticallyEquipNewSpells: true)
        progress.ensureLowerRewardOffer()

        let retainedLearnedSpells = progress.learnedSpells
        progress.spellMastery = progress.spellMastery.filter {
            retainedLearnedSpells.contains($0.key)
        }
        progress.tutorialProgress.activeSequence = nil
        progress.tutorialProgress.activeStep = nil
        progress.tutorialProgress.requestedReplay = nil

        return [
            .checkpointChanged(checkpoint),
            .sceneChanged(destination.scene)
        ]
    }

    mutating func recordCasting(
        spell: SpellID,
        grade: CastingGrade,
        succeeded: Bool
    ) throws -> ProgressionEvent? {
        guard progress.learnedSpells.contains(spell) else {
            throw ProgressionError.unexpectedSpell(spell)
        }
        guard succeeded, grade != .rejected else { return nil }
        return updateMastery(spell: spell, grade: grade)
    }

    mutating func readRecord(id: String) -> ProgressionEvent? {
        let inserted = progress.readRecordIDs.insert(id).inserted
        progress.migrateExpansionCheckpoint()
        return inserted ? .recordRead(id) : nil
    }

    mutating func beginTutorial(
        _ sequence: TutorialSequenceID,
        at step: TutorialStepID
    ) -> ProgressionEvent? {
        guard progress.tutorialProgress.shouldPresent(sequence) else { return nil }
        progress.tutorialProgress.begin(sequence, at: step)
        return .tutorialStarted(sequence: sequence, step: step)
    }

    mutating func completeTutorialStep(
        _ step: TutorialStepID,
        next: TutorialStepID?
    ) -> ProgressionEvent {
        progress.tutorialProgress.completeStep(step, next: next)
        return .tutorialStepCompleted(step)
    }

    mutating func completeTutorial(_ sequence: TutorialSequenceID) -> ProgressionEvent {
        progress.tutorialProgress.complete(sequence)
        return .tutorialCompleted(sequence)
    }

    mutating func skipTutorial(_ sequence: TutorialSequenceID) -> ProgressionEvent {
        progress.tutorialProgress.skip(sequence)
        return .tutorialSkipped(sequence)
    }

    mutating func recordTutorialFailure(
        _ mechanic: TutorialMechanicID
    ) -> ProgressionEvent {
        let count = progress.tutorialProgress.recordFailure(mechanic)
        return .tutorialFailureRecorded(mechanic: mechanic, count: count)
    }

    mutating func requestTutorialReplay(
        _ sequence: TutorialSequenceID
    ) -> ProgressionEvent {
        progress.tutorialProgress.requestReplay(sequence)
        return .tutorialReplayRequested(sequence)
    }

    mutating func resetTutorials() -> ProgressionEvent {
        progress.tutorialProgress.reset()
        return .tutorialsReset
    }

    private mutating func updateMastery(
        spell: SpellID,
        grade: CastingGrade
    ) -> ProgressionEvent {
        var mastery = progress.spellMastery[spell] ?? SpellMastery(
            bestGrade: grade,
            successfulCasts: 0
        )
        mastery.bestGrade = max(mastery.bestGrade, grade)
        mastery.successfulCasts += 1
        progress.spellMastery[spell] = mastery
        return .masteryUpdated(spell: spell, mastery: mastery)
    }

    private mutating func restoreHP(
        by amount: Int,
        minimum: Int? = nil
    ) -> ProgressionEvent {
        let previousHP = progress.playerHP
        var restoredHP = min(previousHP + amount, Self.maximumPlayerHP)
        if let minimum {
            restoredHP = max(restoredHP, minimum)
        }
        progress.playerHP = restoredHP
        return .hpRestored(amount: restoredHP - previousHP, currentHP: restoredHP)
    }

    private mutating func reachCheckpoint(_ checkpoint: CheckpointID) {
        progress.checkpoint = checkpoint
        if checkpoint.progressionIndex > progress.furthestCheckpoint.progressionIndex {
            progress.furthestCheckpoint = checkpoint
        }
    }

    @discardableResult
    private mutating func setScene(_ scene: SceneID) -> SceneID {
        progress.currentScene = scene
        return scene
    }

    private mutating func move(to scene: SceneID) -> [ProgressionEvent] {
        [.sceneChanged(setScene(scene))]
    }

    private func requireScene(_ expected: SceneID) throws {
        guard progress.currentScene == expected else {
            throw ProgressionError.invalidScene(
                expected: [expected],
                actual: progress.currentScene
            )
        }
    }
}

private extension CheckpointID {
    var destination: (floor: FloorID, scene: SceneID) {
        if expansionDestination != nil { return (.floor7, .demoComplete) }
        return switch self {
        case .floor10Start:
            (.floor10, .floor10MeetingRoom)
        case .floor10Complete:
            (.floor9, .floor9Entrance)
        case .recordsBattle:
            (.floor9, .floor9RecordsPreparation)
        case .recordsDefeated:
            (.floor9, .floor9RecordsDefeated)
        case .floor8Start:
            (.floor8, .floor8Antechamber)
        case .residualBattle:
            (.floor8, .floor8ResidualPreparation)
        case .residualDefeated:
            (.floor8, .floor8ResidualDefeated)
        case .observationBattle:
            (.floor8, .floor8AdministratorPreparation)
        case .observationDefeated:
            (.floor8, .floor8AdministratorDefeated)
        default:
            (.floor7, .demoComplete)
        }
    }
}
