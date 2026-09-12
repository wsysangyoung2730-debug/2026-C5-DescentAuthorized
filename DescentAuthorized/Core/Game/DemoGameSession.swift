import Foundation

enum DemoCommand: Sendable {
    case beginExpansion
    case advanceExpansion
    case learnExpansionDebuff(CastingGrade)
    case releaseExpansionSeal(CastingGrade)
    case approveExpansionStage(Int)
    case configureLoadout([SpellID], protectedAttack: SpellID?, protectedDefense: SpellID?)
    case markLoadoutTutorial(LoadoutTutorialFlag)
    case leaveMeetingRoom
    case learnSpell(SpellID)
    case completeScrollLearning(spell: SpellID, grade: CastingGrade)
    case completeTraining(spell: SpellID, grade: CastingGrade)
    case completeProtectionTraining(grade: CastingGrade)
    case approveDescentDoor
    case enterRecordsBattle
    case beginRecordsBattle
    case continueAfterRecordsDefeat
    case enterProtectionRoom
    case beginResidualBattle
    case continueAfterResidualDefeat
    case releaseObservationDoor
    case beginAdministratorBattle
    case continueAfterAdministratorDefeat
    case selectReward(String)
    case completeRewardLearning(candidateID: String, grade: CastingGrade)
    case readRecord(String)
    case startEncounter
    case castSpell(
        spell: SpellID,
        strokes: [DrawnStroke],
        inputMethod: DrawingInputMethod,
        target: ExpansionEffectTarget? = nil
    )
    case finishTurn
    case restartEncounter
    case restartEncounterFromCheckpoint
    case travelToCheckpoint(CheckpointID)
    case beginTutorial(sequence: TutorialSequenceID, step: TutorialStepID)
    case completeTutorialStep(step: TutorialStepID, next: TutorialStepID?)
    case completeTutorial(TutorialSequenceID)
    case skipTutorial(TutorialSequenceID)
    case recordTutorialFailure(TutorialMechanicID)
    case requestTutorialReplay(TutorialSequenceID)
    case resetTutorials
}

enum DemoSessionEvent: Equatable, Sendable {
    case progression(ProgressionEvent)
    case combat(BattleEvent)
    case encounterStarted(EnemyID)
    case encounterWon(EnemyID)
    case encounterLost(EnemyID)
}

enum DemoSessionError: Error, Equatable {
    case encounterAlreadyActive
    case noActiveEncounter
    case encounterNotDefeated
    case noEncounterForScene(SceneID)
}

struct DemoGameSession: Sendable {
    private(set) var progression: GameProgressionController
    private(set) var encounter: EncounterController?

    init(progress: GameProgress = .newGame) {
        progression = GameProgressionController(progress: progress)
        if progression.progress.currentScene == .demoComplete && progression.progress.expansion == nil {
            try? progression.beginExpansion()
        }
    }

    var progress: GameProgress { progression.progress }
    var battleState: BattleState? { encounter?.state }

    mutating func handle(_ command: DemoCommand) throws -> [DemoSessionEvent] {
        switch command {
        case .advanceExpansion:
            guard encounter == nil else { throw DemoSessionError.encounterAlreadyActive }
            return wrap(try progression.advanceExpansion())
        case let .learnExpansionDebuff(grade):
            return wrap(try progression.learnExpansionDebuff(grade: grade))
        case let .releaseExpansionSeal(grade):
            return wrap(try progression.releaseExpansionSeal(grade: grade))
        case let .approveExpansionStage(count):
            try progression.approveExpansionStage(count)
            return []
        case .beginExpansion:
            try progression.beginExpansion()
            return []
        case let .configureLoadout(spells, attack, defense):
            try progression.configureLoadout(spells, protectedAttack: attack, protectedDefense: defense)
            return []
        case let .markLoadoutTutorial(flag):
            progression.markLoadoutTutorial(flag)
            return []
        case .leaveMeetingRoom:
            return wrap(try progression.leaveMeetingRoom())

        case let .learnSpell(spell):
            let events: [ProgressionEvent]
            switch spell {
            case .afterglowErasure:
                events = try progression.learnAfterglowErasure()
            case .riftSeverance:
                events = try progression.learnRiftSeverance()
            case .basicBarrier:
                events = try progression.learnBasicBarrier()
            default:
                throw ProgressionError.unexpectedSpell(spell)
            }
            return wrap(events)

        case let .completeScrollLearning(spell, grade):
            return wrap(try progression.completeScrollLearning(spell: spell, grade: grade))

        case let .completeTraining(spell, grade):
            return wrap(try progression.completeTraining(spell: spell, grade: grade))

        case let .completeProtectionTraining(grade):
            return wrap(try progression.completeProtectionTraining(grade: grade))

        case .approveDescentDoor:
            return wrap(try progression.approveDescentDoor())

        case .enterRecordsBattle:
            return wrap(try progression.enterRecordsBattle())

        case .beginRecordsBattle:
            return wrap(try progression.beginRecordsBattle())

        case .continueAfterRecordsDefeat:
            return wrap(try progression.continueAfterRecordsDefeat())

        case .enterProtectionRoom:
            return wrap(try progression.enterProtectionRoom())

        case .beginResidualBattle:
            return wrap(try progression.beginResidualBattle())

        case .continueAfterResidualDefeat:
            return wrap(try progression.continueAfterResidualDefeat())

        case .releaseObservationDoor:
            return wrap(try progression.releaseObservationDoor())

        case .beginAdministratorBattle:
            return wrap(try progression.beginAdministratorBattle())

        case .continueAfterAdministratorDefeat:
            return wrap(try progression.continueAfterAdministratorDefeat())

        case let .selectReward(candidateID):
            return wrap(try progression.selectReward(candidateID: candidateID))

        case let .completeRewardLearning(candidateID, grade):
            return wrap(try progression.completeRewardLearning(
                candidateID: candidateID,
                grade: grade
            ))

        case let .readRecord(recordID):
            guard let event = progression.readRecord(id: recordID) else { return [] }
            return [.progression(event)]

        case .startEncounter:
            return try startEncounter()

        case let .castSpell(spell, strokes, inputMethod, target):
            return try castSpell(spell, strokes: strokes, inputMethod: inputMethod, target: target)

        case .finishTurn:
            return try finishTurn()

        case .restartEncounter:
            return try restartDefeatedEncounter()

        case .restartEncounterFromCheckpoint:
            return try restartActiveEncounterFromCheckpoint()

        case let .travelToCheckpoint(checkpoint):
            encounter = nil
            return wrap(try progression.travel(to: checkpoint))

        case let .beginTutorial(sequence, step):
            guard let event = progression.beginTutorial(sequence, at: step) else { return [] }
            return [.progression(event)]

        case let .completeTutorialStep(step, next):
            return [.progression(progression.completeTutorialStep(step, next: next))]

        case let .completeTutorial(sequence):
            return [.progression(progression.completeTutorial(sequence))]

        case let .skipTutorial(sequence):
            return [.progression(progression.skipTutorial(sequence))]

        case let .recordTutorialFailure(mechanic):
            return [.progression(progression.recordTutorialFailure(mechanic))]

        case let .requestTutorialReplay(sequence):
            return [.progression(progression.requestTutorialReplay(sequence))]

        case .resetTutorials:
            return [.progression(progression.resetTutorials())]
        }
    }

    func save(to store: any GameSaveStore) throws {
        try progression.save(to: store)
    }

    static func restore(from store: any GameSaveStore) throws -> DemoGameSession {
        let restored = try GameProgressionController.restore(from: store)
        return DemoGameSession(progress: restored.progress)
    }

    private mutating func startEncounter() throws -> [DemoSessionEvent] {
        guard encounter == nil else {
            throw DemoSessionError.encounterAlreadyActive
        }
        guard progress.loadoutIssues.isEmpty else {
            throw ProgressionError.requirementMissing(progress.loadoutIssues.map(\.message).joined(separator: " "))
        }
        let enemy = try enemyForCurrentScene()
        var newEncounter = EncounterController(
            enemy: enemy,
            playerHP: progress.playerHP,
            playerNormalBarrier: startingPlayerBarrier(for: enemy.id),
            learnedSpells: progress.learnedSpells,
            equippedSpells: progress.equippedSpells,
            protectedSpells: progress.protectedSpells
        )
        let battleEvents = try newEncounter.start()
        encounter = newEncounter
        return [.encounterStarted(enemy.id)] + wrap(battleEvents)
    }

    private mutating func castSpell(
        _ spell: SpellID,
        strokes: [DrawnStroke],
        inputMethod: DrawingInputMethod,
        target: ExpansionEffectTarget?
    ) throws -> [DemoSessionEvent] {
        guard var activeEncounter = encounter else {
            throw DemoSessionError.noActiveEncounter
        }

        var battleEvents = try activeEncounter.submitSpell(
            spell,
            strokes: strokes,
            inputMethod: inputMethod,
            selectedTarget: target
        )
        if activeEncounter.state.phase == .resolvingEnemyAction {
            battleEvents.append(contentsOf: try activeEncounter.finishTurnAndAdvance())
        }
        encounter = activeEncounter

        var events = wrap(battleEvents)
        if let resolvedGrade = battleEvents.compactMap(resolvedGrade(from:)).last,
           let masteryEvent = try progression.recordCasting(
               spell: spell,
               grade: resolvedGrade,
               succeeded: true
           ) {
            events.append(.progression(masteryEvent))
        }
        if activeEncounter.state.phase == .defeat {
            events.append(.encounterLost(activeEncounter.enemyDefinition.id))
        } else {
            events.append(contentsOf: try finalizeEncounterIfNeeded())
        }
        return events
    }

    private mutating func finishTurn() throws -> [DemoSessionEvent] {
        guard var activeEncounter = encounter else {
            throw DemoSessionError.noActiveEncounter
        }
        let enemyID = activeEncounter.enemyDefinition.id
        let battleEvents = try activeEncounter.finishTurnAndAdvance()
        encounter = activeEncounter

        var events = wrap(battleEvents)
        if activeEncounter.state.phase == .defeat {
            events.append(.encounterLost(enemyID))
        } else {
            events.append(contentsOf: try finalizeEncounterIfNeeded())
        }
        return events
    }

    private mutating func restartDefeatedEncounter() throws -> [DemoSessionEvent] {
        guard let activeEncounter = encounter else {
            throw DemoSessionError.noActiveEncounter
        }
        guard activeEncounter.state.phase == .defeat else {
            throw DemoSessionError.encounterNotDefeated
        }

        encounter = nil
        return wrap(try progression.returnToBattlePreparation())
    }

    private mutating func restartActiveEncounterFromCheckpoint() throws -> [DemoSessionEvent] {
        guard encounter != nil else {
            throw DemoSessionError.noActiveEncounter
        }

        encounter = nil
        return wrap(try progression.returnToBattlePreparation())
    }

    private mutating func finalizeEncounterIfNeeded() throws -> [DemoSessionEvent] {
        guard let activeEncounter = encounter,
              activeEncounter.state.phase == .victory else {
            return []
        }

        let enemyID = activeEncounter.enemyDefinition.id
        let remainingHP = activeEncounter.state.player.hp
        let progressionEvents: [ProgressionEvent]
        if progress.expansion != nil {
            progressionEvents = try progression.recordExpansionVictory(enemy: enemyID, remainingPlayerHP: remainingHP)
        } else {
            progressionEvents = try progression.completeEncounter(enemy: enemyID, remainingPlayerHP: remainingHP)
        }
        encounter = nil
        return [.encounterWon(enemyID)] + wrap(progressionEvents)
    }

    private func enemyForCurrentScene() throws -> EnemyDefinition {
        if let current = progress.expansion, current.stage.isBattle,
           let enemy = ExpansionEnemyCatalog.enemy(floor: current.floorNumber, isBoss: current.stage == .bossBattle) {
            return enemy
        }
        return switch progress.currentScene {
        case .floor9RecordsBattle:
            EnemyCatalog.recordsAdministrator
        case .floor8ResidualBattle:
            EnemyCatalog.observationResidual
        case .floor8AdministratorBattle:
            EnemyCatalog.observationAdministrator
        default:
            throw DemoSessionError.noEncounterForScene(progress.currentScene)
        }
    }

    private func startingPlayerBarrier(for enemy: EnemyID) -> Int {
        enemy == .observationResidual && progress.learnedSpells.contains(.basicBarrier)
            ? 20
            : 0
    }

    private func resolvedGrade(from event: BattleEvent) -> CastingGrade? {
        guard case let .spellResolved(_, grade) = event else { return nil }
        return grade
    }

    private func wrap(_ events: [ProgressionEvent]) -> [DemoSessionEvent] {
        events.map(DemoSessionEvent.progression)
    }

    private func wrap(_ events: [BattleEvent]) -> [DemoSessionEvent] {
        events.map(DemoSessionEvent.combat)
    }
}
