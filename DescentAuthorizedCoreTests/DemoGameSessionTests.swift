import XCTest
@testable import DescentAuthorizedCore

final class DemoGameSessionTests: XCTestCase {
    func testResidualEncounterKeepsBarrierFromProtectionTraining() throws {
        var progress = GameProgress.newGame
        progress.currentFloor = .floor8
        progress.currentScene = .floor8ResidualBattle
        progress.learnedSpells = [.afterglowErasure, .basicBarrier]
        var session = DemoGameSession(progress: progress)

        let events = try session.handle(.startEncounter)

        XCTAssertEqual(session.battleState?.player.normalBarrier, 20)
        XCTAssertTrue(events.contains(.combat(
            .normalBarrierChanged(target: .player, amount: 20)
        )))
    }

    func testSessionConnectsRealCombatVictoryToFloorProgression() throws {
        var session = try makeRecordsBattleSession()
        let startEvents = try session.handle(.startEncounter)

        XCTAssertTrue(startEvents.contains(.encounterStarted(.recordsAdministrator)))
        XCTAssertEqual(session.battleState?.phase, .playerTurn)

        var safetyCounter = 0
        while session.encounter != nil {
            safetyCounter += 1
            XCTAssertLessThan(safetyCounter, 12)

            if session.battleState?.phase == .playerTurn {
                for spellID in [SpellID.riftSeverance, .afterglowErasure] {
                    guard session.encounter != nil,
                          session.battleState?.phase == .playerTurn else {
                        break
                    }
                    let spell = SpellCatalog.spell(spellID)
                    _ = try session.handle(.castSpell(
                        spell: spellID,
                        strokes: referenceStrokes(for: spell),
                        inputMethod: .pencil
                    ))
                }
            }

            if session.encounter != nil {
                _ = try session.handle(.finishTurn)
            }
        }

        XCTAssertEqual(session.progress.currentScene, .floor9RewardVault)
        XCTAssertTrue(session.progress.defeatedEnemies.contains(.recordsAdministrator))
        XCTAssertGreaterThan(
            session.progress.spellMastery[.riftSeverance]?.successfulCasts ?? 0,
            0
        )
    }

    func testDefeatCanRestartEncounterAtFullHP() throws {
        var session = try makeRecordsBattleSession()
        _ = try session.handle(.startEncounter)

        var safetyCounter = 0
        while session.battleState?.phase != .defeat {
            safetyCounter += 1
            XCTAssertLessThan(safetyCounter, 30)
            _ = try session.handle(.finishTurn)
        }

        let restartEvents = try session.handle(.restartEncounter)

        XCTAssertEqual(session.progress.playerHP, 100)
        XCTAssertEqual(session.battleState?.player.hp, 100)
        XCTAssertEqual(session.battleState?.phase, .playerTurn)
        XCTAssertTrue(restartEvents.contains(.encounterStarted(.recordsAdministrator)))
    }

    func testActiveEncounterRestartsAtCheckpointHPAndResetsEnemy() throws {
        var progress = GameProgress.newGame
        progress.currentFloor = .floor9
        progress.currentScene = .floor9RecordsBattle
        progress.checkpoint = .recordsBattle
        progress.playerHP = 63
        progress.learnedSpells = [.afterglowErasure, .riftSeverance]
        progress.completedTrainingSpells = [.afterglowErasure, .riftSeverance]
        var session = DemoGameSession(progress: progress)
        _ = try session.handle(.startEncounter)
        let spell = SpellCatalog.spell(.afterglowErasure)
        _ = try session.handle(.castSpell(
            spell: spell.id,
            strokes: referenceStrokes(for: spell),
            inputMethod: .pencil
        ))
        XCTAssertLessThan(
            session.battleState?.enemy.hp ?? Int.max,
            EnemyCatalog.recordsAdministrator.maxHP
        )

        let events = try session.handle(.restartEncounterFromCheckpoint)

        XCTAssertEqual(session.progress.playerHP, 63)
        XCTAssertEqual(session.battleState?.player.hp, 63)
        XCTAssertEqual(
            session.battleState?.enemy.hp,
            EnemyCatalog.recordsAdministrator.maxHP
        )
        XCTAssertTrue(events.contains(.encounterStarted(.recordsAdministrator)))
    }

    func testCheckpointRestartRequiresActiveEncounter() throws {
        var session = try makeRecordsBattleSession()

        XCTAssertThrowsError(try session.handle(.restartEncounterFromCheckpoint)) { error in
            XCTAssertEqual(error as? DemoSessionError, .noActiveEncounter)
        }
    }

    func testSessionRejectsCombatCommandsWithoutEncounter() throws {
        var session = DemoGameSession()

        XCTAssertThrowsError(try session.handle(.finishTurn)) { error in
            XCTAssertEqual(error as? DemoSessionError, .noActiveEncounter)
        }
        XCTAssertThrowsError(try session.handle(.startEncounter)) { error in
            XCTAssertEqual(
                error as? DemoSessionError,
                .noEncounterForScene(.floor10MeetingRoom)
            )
        }
    }

    func testSessionSaveRestoresCheckpointStateWithoutMidBattleState() throws {
        let session = try makeRecordsBattleSession()
        let store = InMemoryGameSaveStore()
        try session.save(to: store)

        let restored = try DemoGameSession.restore(from: store)

        XCTAssertEqual(restored.progress, session.progress)
        XCTAssertNil(restored.encounter)
        XCTAssertEqual(restored.progress.checkpoint, .recordsBattle)
    }

    private func makeRecordsBattleSession() throws -> DemoGameSession {
        var session = DemoGameSession()
        _ = try session.handle(.leaveMeetingRoom)
        _ = try session.handle(.learnSpell(.afterglowErasure))
        _ = try session.handle(.completeTraining(
            spell: .afterglowErasure,
            grade: .approved
        ))
        _ = try session.handle(.learnSpell(.riftSeverance))
        _ = try session.handle(.completeTraining(
            spell: .riftSeverance,
            grade: .approved
        ))
        _ = try session.handle(.approveDescentDoor)
        _ = try session.handle(.enterRecordsBattle)
        return session
    }

    private func referenceStrokes(for spell: SpellDefinition) -> [DrawnStroke] {
        spell.glyph.strokes.map { DrawnStroke(points: $0.referencePath) }
    }
}
