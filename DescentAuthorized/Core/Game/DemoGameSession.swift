import Foundation

enum DemoCommand: Sendable {
    case leaveMeetingRoom
    case learnSpell(SpellID)
    case completeTraining(spell: SpellID, grade: CastingGrade)
    case completeProtectionTraining(grade: CastingGrade)
    case approveDescentDoor
    case enterRecordsBattle
    case beginRecordsBattle
    case continueAfterRecordsDefeat
    case enterProtectionRoom
    case beginResidualBattle
    case releaseObservationDoor
    case selectReward(String)
    case readRecord(String)
    case startEncounter
    case castSpell(
        spell: SpellID,
        strokes: [DrawnStroke],
        inputMethod: DrawingInputMethod
    )
    case finishTurn
    case restartEncounter
    case restartEncounterFromCheckpoint
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
    }

    var progress: GameProgress { progression.progress }
    var battleState: BattleState? { encounter?.state }

    mutating func handle(_ command: DemoCommand) throws -> [DemoSessionEvent] {
        switch command {
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
            case .barrierPiercing, .sealRelease:
                throw ProgressionError.unexpectedSpell(spell)
            }
            return wrap(events)

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

        case .releaseObservationDoor:
            return wrap(try progression.releaseObservationDoor())

        case let .selectReward(candidateID):
            return wrap(try progression.selectReward(candidateID: candidateID))

        case let .readRecord(recordID):
            guard let event = progression.readRecord(id: recordID) else { return [] }
            return [.progression(event)]

        case .startEncounter:
            return try startEncounter()

        case let .castSpell(spell, strokes, inputMethod):
            return try castSpell(spell, strokes: strokes, inputMethod: inputMethod)

        case .finishTurn:
            return try finishTurn()

        case .restartEncounter:
            return try restartDefeatedEncounter()

        case .restartEncounterFromCheckpoint:
            return try restartActiveEncounterFromCheckpoint()
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
        let enemy = try enemyForCurrentScene()
        var newEncounter = EncounterController(
            enemy: enemy,
            playerHP: progress.playerHP,
            playerNormalBarrier: startingPlayerBarrier(for: enemy.id),
            learnedSpells: progress.learnedSpells
        )
        let battleEvents = try newEncounter.start()
        encounter = newEncounter
        return [.encounterStarted(enemy.id)] + wrap(battleEvents)
    }

    private mutating func castSpell(
        _ spell: SpellID,
        strokes: [DrawnStroke],
        inputMethod: DrawingInputMethod
    ) throws -> [DemoSessionEvent] {
        guard var activeEncounter = encounter else {
            throw DemoSessionError.noActiveEncounter
        }

        var battleEvents = try activeEncounter.submitSpell(
            spell,
            strokes: strokes,
            inputMethod: inputMethod
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
        var events = wrap(try progression.restartCurrentEncounter())
        events.append(contentsOf: try startEncounter())
        return events
    }

    private mutating func restartActiveEncounterFromCheckpoint() throws -> [DemoSessionEvent] {
        guard encounter != nil else {
            throw DemoSessionError.noActiveEncounter
        }

        encounter = nil
        return try startEncounter()
    }

    private mutating func finalizeEncounterIfNeeded() throws -> [DemoSessionEvent] {
        guard let activeEncounter = encounter,
              activeEncounter.state.phase == .victory else {
            return []
        }

        let enemyID = activeEncounter.enemyDefinition.id
        let remainingHP = activeEncounter.state.player.hp
        let progressionEvents = try progression.completeEncounter(
            enemy: enemyID,
            remainingPlayerHP: remainingHP
        )
        encounter = nil
        return [.encounterWon(enemyID)] + wrap(progressionEvents)
    }

    private func enemyForCurrentScene() throws -> EnemyDefinition {
        switch progress.currentScene {
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
