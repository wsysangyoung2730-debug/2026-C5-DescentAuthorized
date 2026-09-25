import Foundation
import XCTest
@testable import DescentAuthorizedCore

final class LowerFloorTests: XCTestCase {
    func testCatalogCountsAndAllNewReferencePaths() {
        XCTAssertEqual(SpellCatalog.all.count, 28)
        XCTAssertEqual(SpellCatalog.all.values.filter { $0.requiredStrokes == 2 }.count, 8)
        XCTAssertEqual(EnemyCatalog.all.count, 21)
        for spell in SpellCatalog.lowerFloorSpells.values {
            let result = GlyphEvaluator(maximumMana: 150).evaluate(spell: spell,
                strokes: strokes(spell), inputMethod: .pencil, erasureZones: [])
            XCTAssertTrue(result.succeeded, spell.name)
        }
        for floor in 1...4 {
            let approvals = DescentDoorGlyphCatalog.lowerFloorApprovals(floor: floor)
            XCTAssertEqual(approvals.count, 3)
            XCTAssertEqual(Set(approvals.map(\.id)).count, 3)
            for approval in approvals {
                let result = GlyphEvaluator(maximumMana: 150).evaluate(glyph: approval.glyph,
                    recommendedMana: approval.recommendedMana,
                    strokes: approval.glyph.strokes.map { .init(points: $0.referencePath) }, inputMethod: .pencil)
                XCTAssertTrue(result.succeeded, "\(floor)F \(approval.name)")
            }
        }
    }

    func testLowerResourcesDoNotChangeUpperFloors() throws {
        var lower = makeEngine()
        _ = try lower.beginPlayerTurn(intent: idle)
        XCTAssertEqual(lower.state.resources.remainingStrokes, 3)
        XCTAssertEqual(lower.state.resources.remainingMana, 150)
        var upper = CombatEngine(enemy: ExpansionEnemyCatalog.memoryOriginalAdministrator)
        _ = try upper.beginPlayerTurn(intent: idle)
        XCTAssertEqual(upper.state.resources.remainingStrokes, 2)
        XCTAssertEqual(upper.state.resources.remainingMana, 100)
    }

    func testThirdForbiddenStaysLearnedWithoutDisplacingEquippedBooks() {
        var progress = GameProgress.newGame
        progress.learnedSpells = [.riftSeverance, .basicBarrier, .sealRelease, .bloodSealPiercing, .limitBarrier]
        let equipped: [SpellID] = [.riftSeverance, .basicBarrier, .sealRelease, .bloodSealPiercing, .limitBarrier]
        XCTAssertTrue(progress.setLoadout(equipped))
        progress.learnedSpells.insert(.directHitProhibition)
        XCTAssertEqual(progress.equippedSpells, equipped)
        XCTAssertTrue(progress.learnedSpells.contains(.directHitProhibition))
        XCTAssertFalse(progress.setLoadout(equipped + [.directHitProhibition]))
        progress.learnedSpells.insert(.handoffBarrier)
        XCTAssertTrue(progress.setLoadout(equipped + [.handoffBarrier]))
        XCTAssertEqual(LoadoutRules.forbiddenCount(progress.equippedSpells), 2)
    }

    func testBloodPiercingKeepsEnemyBarrierAndPaysOnlyOnSuccess() throws {
        var engine = makeEngine()
        _ = try engine.beginPlayerTurn(intent: .expansion(name: "방벽", action: .timedBarrier(amount: 40, turns: 2)))
        try resolve(&engine)
        _ = try engine.beginPlayerTurn(intent: idle)
        _ = try cast(.bloodSealPiercing, &engine)
        XCTAssertEqual(engine.state.enemy.normalBarrier, 40)
        XCTAssertEqual(engine.state.player.hp, 92)
        XCTAssertLessThan(engine.state.enemy.hp, engine.enemyDefinition.maxHP)
        var fragile = makeEngine(hp: 8)
        _ = try fragile.beginPlayerTurn(intent: idle)
        XCTAssertThrowsError(try cast(.bloodSealPiercing, &fragile))
        XCTAssertEqual(fragile.state.player.hp, 8)
        XCTAssertEqual(fragile.state.resources.remainingStrokes, 3)
        var failed = makeEngine()
        _ = try failed.beginPlayerTurn(intent: idle)
        _ = try failed.submitSpell(SpellCatalog.spell(.bloodSealPiercing),
            strokes: [.init(points: [.init(x: 0, y: 0), .init(x: 1, y: 1)])], inputMethod: .pencil)
        XCTAssertEqual(failed.state.player.hp, 100)
    }

    func testLimitBarrierCapExpiresAfterEnemyWindow() throws {
        var engine = makeEngine()
        _ = try engine.beginPlayerTurn(intent: idle)
        _ = try cast(.limitBarrier, &engine)
        _ = try cast(.basicBarrier, &engine)
        XCTAssertEqual(engine.state.player.normalBarrier, 60)
        XCTAssertEqual(engine.state.player.hp, 92)
        try resolve(&engine)
        XCTAssertEqual(engine.state.player.normalBarrier, 40)
        XCTAssertNil(engine.state.expansion.limitBarrierThroughTurn)
    }

    func testHandoffRegeneratesAfterFirstOfTwoHits() throws {
        var engine = makeEngine()
        _ = try engine.beginPlayerTurn(intent: .expansion(name: "분할", action: .directHits([35, 25])))
        _ = try cast(.handoffBarrier, &engine)
        try resolve(&engine)
        XCTAssertEqual(engine.state.player.hp, 94) // 30 shield, 5 HP; regenerate 24, then 1 HP.
        XCTAssertEqual(engine.state.player.normalBarrier, 0)
        XCTAssertEqual(engine.state.expansion.handoffBarrierAmount, 0)
    }

    func testDirectProhibitionDoesNotCancelReservation() throws {
        var engine = makeEngine()
        _ = try engine.beginPlayerTurn(intent: .expansion(name: "등록", action: .schedule([.init(name: "예약", damage: 20, turnsFromNow: 1)])))
        try resolve(&engine)
        _ = try engine.beginPlayerTurn(intent: .expansion(name: "직접", action: .directHits([30])))
        _ = try cast(.directHitProhibition, &engine)
        try resolve(&engine)
        XCTAssertEqual(engine.state.player.hp, 72) // HP cost 8 + reserved 20, direct 30 negated.
    }

    func testNullificationCancelsOnlyChosenDueGroup() throws {
        var engine = makeEngine()
        _ = try engine.beginPlayerTurn(intent: .expansion(name: "등록", action: .schedule([
            .init(name: "A", damage: 16, turnsFromNow: 1), .init(name: "B", damage: 16, turnsFromNow: 1),
            .init(name: "C", damage: 20, turnsFromNow: 2)])))
        try resolve(&engine)
        _ = try engine.beginPlayerTurn(intent: idle)
        _ = try cast(.executionNullification, &engine, target: .scheduledDamageGroup(2))
        XCTAssertEqual(engine.state.expansion.scheduledDamage.map(\.name), ["C"])
        XCTAssertEqual(engine.state.player.hp, 90)
        XCTAssertEqual(engine.state.expansion.executionNullificationUses, 1)
    }

    func testSealChoiceBlocksInputAndProtectsCoreCards() throws {
        let cards: [SpellID] = [.riftSeverance, .basicBarrier, .sealRelease, .chainInscription, .executionDelay]
        var engine = CombatEngine(enemy: LowerFloorEnemyCatalog.all[.consentCustodianResidual]!,
            equippedSpells: cards, protectedSpells: [.riftSeverance, .basicBarrier, .sealRelease])
        _ = try engine.beginPlayerTurn(intent: .expansion(name: "봉인", action: .lockCards(count: 2, duration: 2, chooseOne: true)))
        XCTAssertEqual(Set(engine.state.expansion.pendingSealChoices), [.chainInscription, .executionDelay])
        XCTAssertThrowsError(try cast(.basicBarrier, &engine))
        XCTAssertThrowsError(try engine.endPlayerTurn())
        try engine.chooseCardSeal(.executionDelay)
        _ = try cast(.basicBarrier, &engine)
        try resolve(&engine)
        XCTAssertEqual(Set(engine.state.expansion.lockedSpells.keys), [.executionDelay])
    }

    func testCounterIsSingleConditionalAndMimicProhibitionCancelsIt() throws {
        var engine = makeEngine()
        _ = try engine.beginPlayerTurn(intent: .expansion(name: "준비", action: .counterPrepare(damage: 24)))
        try resolve(&engine)
        _ = try engine.beginPlayerTurn(intent: .expansion(name: "집행", action: .counterExecute))
        _ = try cast(.riftSeverance, &engine)
        _ = try cast(.riftSeverance, &engine)
        try resolve(&engine)
        XCTAssertEqual(engine.state.player.hp, 76)
        _ = try engine.beginPlayerTurn(intent: .expansion(name: "준비", action: .counterPrepare(damage: 24)))
        try resolve(&engine)
        _ = try engine.beginPlayerTurn(intent: .expansion(name: "집행", action: .counterExecute))
        _ = try cast(.mimicProhibition, &engine)
        _ = try cast(.riftSeverance, &engine)
        try resolve(&engine)
        XCTAssertEqual(engine.state.player.hp, 70) // Only the existing mimic prohibition HP cost.
    }

    func testAllLowerFloorsReachEndingWithDurableRewardsAndApprovals() throws {
        var controller = try lowerController()
        for floor in stride(from: 4, through: 1, by: -1) {
            XCTAssertEqual(controller.progress.expansion?.floorNumber, floor)
            _ = try controller.advanceExpansion() // Entrance to preparation.
            for residual in 0...1 {
                _ = try controller.advanceExpansion()
                _ = try controller.advanceExpansion()
                let enemy = try XCTUnwrap(ExpansionEnemyCatalog.enemy(floor: floor, isBoss: false, residualIndex: residual))
                _ = try controller.recordExpansionVictory(enemy: enemy.id, remainingPlayerHP: 30)
                _ = try controller.advanceExpansion()
                if residual == 0 {
                    XCTAssertEqual(controller.progress.expansion?.stage, .residualInvestigation)
                    _ = try controller.advanceExpansion()
                    controller = try restored(controller)
                    XCTAssertEqual(controller.progress.expansion?.residualIndex, 1)
                }
            }
            if [3,4].contains(floor) { try learnReward(&controller) }
            _ = try controller.releaseExpansionSeal(grade: .approved)
            _ = try controller.advanceExpansion()
            _ = try controller.advanceExpansion()
            _ = try controller.recordExpansionVictory(enemy: XCTUnwrap(ExpansionEnemyCatalog.enemy(floor: floor, isBoss: true)).id, remainingPlayerHP: 20)
            _ = try controller.advanceExpansion()
            if floor == 1 {
                XCTAssertEqual(controller.progress.expansion?.stage, .finalRecord)
                _ = try controller.advanceExpansion()
                XCTAssertFalse(controller.progress.readRecordIDs.contains("floor1.tower-handoff"))
            } else { try learnReward(&controller) }
            XCTAssertThrowsError(try controller.approveExpansionStage(3))
            try controller.approveExpansionStage(1)
            try controller.approveExpansionStage(2)
            controller = try restored(controller)
            XCTAssertEqual(controller.progress.expansion?.descentStage, 2)
            XCTAssertThrowsError(try controller.advanceExpansion())
            try controller.approveExpansionStage(3)
            _ = try controller.advanceExpansion()
            try GameProgressValidator().validate(controller.progress)
        }
        XCTAssertTrue(controller.progress.expansion?.isComplete == true)
        XCTAssertTrue(controller.progress.readRecordIDs.contains("floor1.tower-handoff"))
        XCTAssertEqual(controller.progress.completedLowerRewardSites.count, 5)
        _ = try controller.travel(to: .recordsBattle)
        try GameProgressValidator().validate(controller.progress)
        XCTAssertTrue(controller.progress.completedLowerRewardSites.isEmpty)
    }

    func testEveryLowerCheckpointCanBeRestoredAndValidated() throws {
        var controller = try lowerController()
        for checkpoint in CheckpointID.allCases where checkpoint.lowerFloorDestination != nil {
            _ = try controller.travel(to: checkpoint)
            controller = try restored(controller)
            try GameProgressValidator().validate(controller.progress)
        }
    }

    func testOldFourthFloorCompletionMigratesToEntrance() throws {
        let data = Data(#"{"floorNumber":4,"stage":"complete","descentStage":2}"#.utf8)
        let current = try JSONDecoder().decode(ExpansionProgress.self, from: data)
        XCTAssertEqual(current.stage, .entrance)
        XCTAssertEqual(current.descentStage, 0)
        XCTAssertEqual(current.residualIndex, 0)
        XCTAssertFalse(current.isComplete)
    }

    func testFinalBossUsesThreePhasesWithoutHPReset() throws {
        let protected: Set<SpellID> = [.riftSeverance, .basicBarrier, .sealRelease]
        // Isolate phase scheduling from survival balance; HP is correctly capped at 100.
        var encounter = EncounterController(enemy: LowerFloorEnemyCatalog.all[.finalAuthorizationAdministrator]!,
            playerNormalBarrier: 10_000, equippedSpells: [.riftSeverance, .basicBarrier, .sealRelease], protectedSpells: protected)
        _ = try encounter.start()
        var phases = [encounter.state.expansion.encounterPhase]
        var previousHP = encounter.state.enemy.hp
        for _ in 0..<20 {
            XCTAssertEqual(encounter.state.phase, .playerTurn)
            if encounter.state.enemy.absoluteBarrierCharges > 0 {
                _ = try encounter.submitSpell(.sealRelease, strokes: strokes(SpellCatalog.sealRelease))
            }
            while encounter.state.enemy.hp > 210, encounter.state.resources.remainingStrokes > 0,
                  encounter.state.resources.remainingMana >= SpellCatalog.riftSeverance.recommendedMana {
                _ = try encounter.submitSpell(.riftSeverance, strokes: strokes(SpellCatalog.riftSeverance))
            }
            _ = try encounter.finishTurnAndAdvance()
            XCTAssertLessThanOrEqual(encounter.state.enemy.hp, previousHP)
            previousHP = encounter.state.enemy.hp
            if phases.last != encounter.state.expansion.encounterPhase { phases.append(encounter.state.expansion.encounterPhase) }
            if phases.last == 3 { break }
        }
        XCTAssertEqual(phases, [1, 2, 3])
        XCTAssertGreaterThan(encounter.state.enemy.hp, 0)
    }

    func testDamageEventsFollowDirectThenReservationThenCounter() throws {
        var engine = makeEngine()
        _ = try engine.beginPlayerTurn(intent: .expansion(name: "준비", action: .sequence([
            .schedule([.init(name: "예약", damage: 20, turnsFromNow: 1)]), .counterPrepare(damage: 30)])))
        try resolve(&engine)
        _ = try engine.beginPlayerTurn(intent: .expansion(name: "집행", action: .sequence([.directHits([10]), .counterExecute])))
        _ = try cast(.riftSeverance, &engine)
        _ = try engine.endPlayerTurn()
        let events = try engine.resolveEnemyIntent()
        let hits = events.compactMap { event -> Int? in
            if case let .damageApplied(.player, amount, _) = event { return amount }
            return nil
        }
        XCTAssertEqual(hits, [10, 20, 30])
    }

    func testIsolationReducesOnlyChosenReservationAndPressurePreservesShieldWhenBlocked() throws {
        var engine = makeEngine()
        _ = try engine.beginPlayerTurn(intent: .expansion(name: "등록", action: .schedule([
            .init(name: "A", damage: 40, turnsFromNow: 1), .init(name: "B", damage: 20, turnsFromNow: 1)])))
        try resolve(&engine)
        _ = try engine.beginPlayerTurn(intent: idle)
        let id = try XCTUnwrap(engine.state.expansion.scheduledDamage.first?.id)
        _ = try cast(.isolationBarrier, &engine, target: .scheduledDamage(id))
        try resolve(&engine)
        XCTAssertEqual(engine.state.player.hp, 88) // 20 + 20 - 28 shield.
        XCTAssertNil(engine.state.expansion.isolationReservationID)
        _ = try engine.beginPlayerTurn(intent: idle)
        _ = try cast(.basicBarrier, &engine)
        _ = engine.grantEnemyAbsoluteBarrier(charges: 1)
        _ = try cast(.pressureRelease, &engine)
        XCTAssertEqual(engine.state.player.normalBarrier, 30)
    }

    func testResidualBRetryDoesNotRepeatA() throws {
        var controller = try lowerController()
        _ = try controller.travel(to: .floor4SecondEncounter)
        _ = try controller.advanceExpansion()
        _ = try controller.advanceExpansion()
        try controller.retryExpansionBattle()
        XCTAssertEqual(controller.progress.expansion?.residualIndex, 1)
        XCTAssertEqual(controller.progress.expansion?.stage, .preparation)
        XCTAssertTrue(controller.progress.defeatedEnemies.contains(.signatureMimicResidual))
        XCTAssertFalse(controller.progress.defeatedEnemies.contains(.rejectionExecutionResidual))
        XCTAssertEqual(controller.progress.playerHP, 100)
    }

    func testEveryLowerApprovalCountSurvivesReloadWithoutPrematureDescent() throws {
        let checkpoints: [CheckpointID] = [.floor4Descent, .floor3Descent, .floor2Descent, .floor1Descent]
        for checkpoint in checkpoints {
            for approved in 0...3 {
                var controller = try lowerController()
                _ = try controller.travel(to: checkpoint)
                let floor = try XCTUnwrap(controller.progress.expansion).floorNumber
                for stage in 1..<(approved + 1) { try controller.approveExpansionStage(stage) }
                controller = try restored(controller)
                let progress = try XCTUnwrap(controller.progress.expansion)
                XCTAssertEqual(progress.descentStage, approved)
                XCTAssertEqual(ExpansionSceneRoute(progress)?.room, .administrator)
                XCTAssertEqual(ExpansionSceneRoute(progress)?.camera, .descentInput)
                if approved < 3 {
                    XCTAssertThrowsError(try controller.advanceExpansion())
                    XCTAssertEqual(controller.progress.expansion?.floorNumber, floor)
                } else {
                    _ = try controller.advanceExpansion()
                    if floor == 1 { XCTAssertTrue(controller.progress.expansion?.isComplete == true) }
                    else { XCTAssertEqual(controller.progress.expansion?.floorNumber, floor - 1) }
                }
            }
        }
    }

    private func learnReward(_ controller: inout GameProgressionController) throws {
        let candidates = controller.progress.currentRewardCandidates
        XCTAssertEqual(candidates.count, 3)
        let choice = try XCTUnwrap(candidates.first)
        _ = try controller.selectReward(candidateID: choice.id)
        controller = try restored(controller)
        XCTAssertEqual(controller.progress.currentRewardCandidates, candidates)
        XCTAssertTrue(controller.progress.selectedRewardIDs.contains(choice.id))
        _ = try controller.completeRewardLearning(candidateID: choice.id, grade: .approved)
        try GameProgressValidator().validate(controller.progress)
    }

    private func lowerController() throws -> GameProgressionController {
        var seed = GameProgress.newGame
        seed.furthestCheckpoint = .towerHandoffComplete
        var controller = GameProgressionController(progress: seed)
        _ = try controller.travel(to: .floor5Complete)
        return controller
    }
    private func restored(_ controller: GameProgressionController) throws -> GameProgressionController {
        let restored = try JSONDecoder().decode(GameProgress.self, from: JSONEncoder().encode(controller.progress))
        try GameProgressValidator().validate(restored)
        return GameProgressionController(progress: restored)
    }
    private func makeEngine(hp: Int = 100) -> CombatEngine {
        CombatEngine(enemy: LowerFloorEnemyCatalog.all[.responsibilityAuditAdministrator]!, playerHP: hp)
    }
    private var idle: EnemyAction { .expansion(name: "대기", action: .wait) }
    private func strokes(_ spell: SpellDefinition) -> [DrawnStroke] { spell.glyph.strokes.map { .init(points: $0.referencePath) } }
    @discardableResult private func cast(_ id: SpellID, _ engine: inout CombatEngine, target: ExpansionEffectTarget? = nil) throws -> [BattleEvent] {
        let spell = SpellCatalog.spell(id)
        return try engine.submitSpell(spell, strokes: strokes(spell), inputMethod: .pencil, selectedTarget: target)
    }
    private func resolve(_ engine: inout CombatEngine) throws {
        if engine.state.phase == .playerTurn { _ = try engine.endPlayerTurn() }
        if engine.state.phase == .resolvingEnemyAction { _ = try engine.resolveEnemyIntent() }
    }
}
