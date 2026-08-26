import XCTest
@testable import DescentAuthorizedCore

final class DemoFlowIntegrationTests: XCTestCase {
    func testReferencePlaythroughReachesDemoEndingThroughAllBattles() throws {
        var session = DemoGameSession()

        _ = try session.handle(.leaveMeetingRoom)
        _ = try session.handle(.learnSpell(.afterglowErasure))
        _ = try session.handle(.completeTraining(
            spell: .afterglowErasure,
            grade: .perfect
        ))
        _ = try session.handle(.learnSpell(.riftSeverance))
        _ = try session.handle(.completeTraining(
            spell: .riftSeverance,
            grade: .perfect
        ))
        _ = try session.handle(.approveDescentDoor)

        _ = try session.handle(.enterRecordsBattle)
        _ = try session.handle(.beginRecordsBattle)
        try winCurrentEncounter(in: &session)
        _ = try session.handle(.continueAfterRecordsDefeat)
        _ = try session.handle(.selectReward("floor9-worn-a"))
        _ = try session.handle(.approveDescentDoor)

        _ = try session.handle(.enterProtectionRoom)
        _ = try session.handle(.learnSpell(.basicBarrier))
        _ = try session.handle(.completeProtectionTraining(grade: .perfect))
        _ = try session.handle(.beginResidualBattle)
        try winCurrentEncounter(in: &session)

        _ = try session.handle(.continueAfterResidualDefeat)

        _ = try session.handle(.releaseObservationDoor)
        _ = try session.handle(.beginAdministratorBattle)
        try winCurrentEncounter(in: &session)
        _ = try session.handle(.selectReward("floor8-forbidden"))
        let endingEvents = try session.handle(.approveDescentDoor)

        XCTAssertEqual(session.progress.currentFloor, .floor7)
        XCTAssertEqual(session.progress.currentScene, .demoComplete)
        XCTAssertEqual(session.progress.defeatedEnemies, Set(EnemyID.allCases))
        XCTAssertEqual(session.progress.learnedSpells, Set(SpellID.allCases))
        XCTAssertTrue(session.progress.isDemoComplete)
        XCTAssertTrue(endingEvents.contains(.progression(.demoCompleted)))
        XCTAssertNoThrow(try GameProgressValidator().validate(session.progress))
    }

    private func winCurrentEncounter(
        in session: inout DemoGameSession,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        _ = try session.handle(.startEncounter)
        var turnSafetyCounter = 0

        while session.encounter != nil {
            turnSafetyCounter += 1
            XCTAssertLessThan(turnSafetyCounter, 24, file: file, line: line)
            guard let battle = session.battleState else {
                XCTFail("전투 상태가 사라졌습니다.", file: file, line: line)
                return
            }
            if battle.phase == .defeat {
                XCTFail("기준 문양 플레이가 패배했습니다.", file: file, line: line)
                return
            }

            let turnBeforeCasting = battle.turnNumber
            if battle.phase == .playerTurn {
                try castTurn(in: &session)
            }
            if session.encounter != nil,
               session.battleState?.phase == .playerTurn,
               session.battleState?.turnNumber == turnBeforeCasting {
                _ = try session.handle(.finishTurn)
            }
        }
    }

    private func castTurn(in session: inout DemoGameSession) throws {
        guard let initialState = session.battleState else { return }

        if initialState.enemy.absoluteBarrierCharges > 0 {
            if initialState.enemy.id == .enemy(.observationAdministrator),
               session.progress.spellMastery[.sealRelease] == nil {
                try cast(.afterglowErasure, in: &session)
            }
            if canCast(.sealRelease, in: session) {
                try cast(.sealRelease, in: &session)
            }
        }

        guard let state = session.battleState,
              state.phase == .playerTurn,
              state.resources.remainingStrokes > 0 else {
            return
        }

        if isStrongAttack(state.currentEnemyIntent), canCast(.basicBarrier, in: session) {
            try cast(.basicBarrier, in: &session)
        } else if canCast(.riftSeverance, in: session) {
            try cast(.riftSeverance, in: &session)
        } else if canCast(.afterglowErasure, in: session) {
            try cast(.afterglowErasure, in: &session)
        }

        if let updatedState = session.battleState,
           !isStrongAttack(updatedState.currentEnemyIntent),
           canCast(.afterglowErasure, in: session) {
            try cast(.afterglowErasure, in: &session)
        }
    }

    private func canCast(_ spellID: SpellID, in session: DemoGameSession) -> Bool {
        guard let state = session.battleState,
              state.phase == .playerTurn,
              state.learnedSpells.contains(spellID) else {
            return false
        }
        let spell = SpellCatalog.spell(spellID)
        return state.resources.remainingStrokes >= spell.requiredStrokes
            && state.resources.remainingMana >= spell.recommendedMana
    }

    private func cast(_ spellID: SpellID, in session: inout DemoGameSession) throws {
        let spell = SpellCatalog.spell(spellID)
        _ = try session.handle(.castSpell(
            spell: spellID,
            strokes: spell.glyph.strokes.map { DrawnStroke(points: $0.referencePath) },
            inputMethod: .pencil
        ))
    }

    private func isStrongAttack(_ action: EnemyAction?) -> Bool {
        guard case let .attack(_, _, isStrong) = action else { return false }
        return isStrong
    }
}
