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

        case .barrierPiercing:
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
        case .barrierPiercing, .basicBarrier, .sealRelease:
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
            progress.checkpoint = .floor10Complete
            return [
                .checkpointChanged(.floor10Complete),
                .sceneChanged(setScene(.floor9Entrance))
            ]

        case .floor9DescentDoor:
            guard progress.learnedSpells.contains(.barrierPiercing) else {
                throw ProgressionError.requirementMissing("floor 9 reward")
            }
            let recovery = restoreHP(by: 30)
            progress.currentFloor = .floor8
            progress.checkpoint = .floor8Start
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
            progress.checkpoint = .demoComplete
            progress.isDemoComplete = true
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
        progress.checkpoint = .recordsBattle
        progress.tutorials.formUnion([.mana, .strokeCount, .enemyIntent, .hp])
        return [
            .checkpointChanged(.recordsBattle),
            .sceneChanged(setScene(.floor9RecordsEncounter))
        ]
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
            progress.checkpoint = .residualBattle
            return [
                .checkpointChanged(.residualBattle),
                .sceneChanged(setScene(.floor8ResidualEncounter))
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
        progress.checkpoint = .residualBattle
        return [
            .trainingCompleted(spell: .basicBarrier, grade: grade),
            updateMastery(spell: .basicBarrier, grade: grade),
            .checkpointChanged(.residualBattle),
            .sceneChanged(setScene(.floor8ResidualEncounter))
        ]
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
        progress.checkpoint = .observationBattle
        progress.tutorials.formUnion([.absoluteBarrier, .dispel, .strongAttack])
        return [
            .checkpointChanged(.observationBattle),
            .sceneChanged(setScene(.floor8AdministratorEncounter))
        ]
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
            progress.checkpoint = .recordsDefeated
            progress.tutorials.formUnion([.normalBarrier, .erasureZone, .rewardSelection])
            return [
                .enemyDefeated(enemy),
                .checkpointChanged(.recordsDefeated),
                .sceneChanged(setScene(.floor9RecordsDefeated))
            ]

        case .observationResidual:
            let recovery = restoreHP(by: 20, minimum: 60)
            progress.checkpoint = .residualDefeated
            return [
                .enemyDefeated(enemy),
                recovery,
                .checkpointChanged(.residualDefeated),
                .sceneChanged(setScene(.floor8ResidualDefeated))
            ]

        case .observationAdministrator:
            progress.checkpoint = .observationDefeated
            return [
                .enemyDefeated(enemy),
                .checkpointChanged(.observationDefeated),
                .sceneChanged(setScene(.floor8AdministratorDefeated))
            ]
        }
    }

    mutating func selectReward(candidateID: String) throws -> [ProgressionEvent] {
        let floor: FloorID
        switch progress.currentScene {
        case .floor9RewardVault:
            floor = .floor9
        case .floor8Reward:
            floor = .floor8
        default:
            throw ProgressionError.invalidScene(
                expected: [.floor9RewardVault, .floor8Reward],
                actual: progress.currentScene
            )
        }

        let candidates = RewardCatalog.candidates(for: floor)
        guard !candidates.contains(where: { progress.selectedRewardIDs.contains($0.id) }) else {
            throw ProgressionError.rewardAlreadySelected
        }
        guard let selected = candidates.first(where: { $0.id == candidateID }) else {
            throw ProgressionError.unknownReward(candidateID)
        }

        progress.selectedRewardIDs.append(selected.id)
        return [
            .rewardSelected(candidateID: selected.id, spell: selected.resolvedSpell)
        ]
    }

    mutating func completeRewardLearning(
        candidateID: String,
        grade: CastingGrade
    ) throws -> [ProgressionEvent] {
        guard grade != .rejected else {
            throw ProgressionError.requirementMissing("successful reward scroll tracing")
        }

        let floor: FloorID
        let destination: SceneID
        switch progress.currentScene {
        case .floor9RewardVault:
            floor = .floor9
            destination = .floor9DescentDoor
        case .floor8Reward:
            floor = .floor8
            destination = .floor8DescentDoor
        default:
            throw ProgressionError.invalidScene(
                expected: [.floor9RewardVault, .floor8Reward],
                actual: progress.currentScene
            )
        }

        guard progress.selectedRewardIDs.contains(candidateID) else {
            throw ProgressionError.requirementMissing("selected reward scroll")
        }
        guard let selected = RewardCatalog.candidates(for: floor)
            .first(where: { $0.id == candidateID }) else {
            throw ProgressionError.unknownReward(candidateID)
        }

        let spell = RewardCatalog.learningSpell(for: selected)
        let isNewSpell = progress.learnedSpells.insert(spell).inserted
        progress.completedTrainingSpells.insert(spell)

        var events: [ProgressionEvent] = []
        if isNewSpell {
            events.append(.spellLearned(spell))
        }
        events.append(.trainingCompleted(spell: spell, grade: grade))
        events.append(updateMastery(spell: spell, grade: grade))
        events.append(.sceneChanged(setScene(destination)))
        return events
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
