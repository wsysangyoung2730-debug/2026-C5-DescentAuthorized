import Foundation

/// Expansion effects share the existing glyph evaluation and two-stroke budget.
enum ExpansionSpellEffect: String, Codable, CaseIterable, Sendable {
    case chainInscription, purificationGlyph, lingeringBarrier, axisSeverance
    case anchorGuard, consequenceErasure, outputReduction, executionDelay
    case advanceVerdict, causalCushion, memorySeverance, memorySuture, mimicProhibition

    var range: ClosedRange<Int> {
        switch self {
        case .chainInscription: 14...20
        case .purificationGlyph, .consequenceErasure, .executionDelay: 1...1
        case .lingeringBarrier: 14...20
        case .axisSeverance: 28...40
        case .anchorGuard: 18...26
        case .outputReduction: 25...25
        case .advanceVerdict: 26...36
        case .causalCushion: 16...24
        case .memorySeverance: 28...38
        case .memorySuture: 12...18
        case .mimicProhibition: 2...2
        }
    }
}

struct ScheduledDamageSpec: Codable, Equatable, Sendable {
    let name: String
    let damage: Int
    let turnsFromNow: Int
}

struct ScheduledEnemyDamage: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let damage: Int
    var dueEnemyTurn: Int
    var wasDelayed: Bool = false
}

indirect enum ExpansionEnemyAction: Codable, Equatable, Sendable {
    case correctionBarrier(amount: Int)
    case correctionStrike(normalDamage: Int, strengthenedDamage: Int)
    case amplify(multiplier: Double)
    case schedule([ScheduledDamageSpec])
    case recordLastSpell
    case copyReaction(baseDamage: Int, categoryEffects: Bool, extraDamage: Int)
    case lockAndSchedule(count: Int, damage: Int)
    case preparedLockAndSchedule(spells: [SpellID], damage: Int)
    case sequence([ExpansionEnemyAction])
    case wait

    var detail: String {
        switch self {
        case let .correctionBarrier(amount): "교정 방벽 \(amount) · 다음 강공격 강화"
        case let .correctionStrike(normal, strong): "방벽 파괴 시 \(normal) · 방벽 유지 시 \(strong) 피해"
        case let .amplify(multiplier): "다음 예약 피해 \(Int((multiplier * 100).rounded()))% · 예약 전 정화 가능"
        case let .schedule(specs): specs.map { "\($0.turnsFromNow)턴 뒤 \($0.damage) 피해 예약" }.joined(separator: " / ")
        case .recordLastSpell: "이번 턴 마지막 성공 주문 기록"
        case let .copyReaction(damage, category, extra): category ? "피해 \(damage) · 기록 주문 재사용 시 유형별 모사" : "피해 \(damage) · 같은 주문 재사용 시 추가 \(extra)"
        case let .lockAndSchedule(count, damage): "선택 주문 최대 \(count)개 봉인 · 다음 턴 \(damage) 피해 예약"
        case let .preparedLockAndSchedule(spells, damage): "\(spells.isEmpty ? "봉인 대상 없음" : spells.map { SpellCatalog.spell($0).name }.joined(separator: ", ")) · 다음 턴 \(damage) 피해 예약"
        case let .sequence(actions): actions.map(\.detail).joined(separator: " · ")
        case .wait: "새로운 공격 없음 · 도래한 예약만 집행"
        }
    }
}

enum ExpansionEffectTarget: Hashable, Sendable, Identifiable {
    case playerAttackWeakening
    case cardSeal(SpellID)
    case enemyAmplification
    case enemyPreservation
    case enemyCopyRecord
    case scheduledDamage(String)
    case enemyNormalBarrier

    var id: String {
        switch self {
        case .playerAttackWeakening: "player-weakening"
        case let .cardSeal(spell): "seal-\(spell.rawValue)"
        case .enemyAmplification: "enemy-amplification"
        case .enemyPreservation: "enemy-preservation"
        case .enemyCopyRecord: "enemy-copy"
        case let .scheduledDamage(id): "scheduled-\(id)"
        case .enemyNormalBarrier: "enemy-barrier"
        }
    }
}

struct ExpansionTargetOption: Identifiable, Equatable, Sendable {
    let id: ExpansionEffectTarget
    let title: String
    let detail: String
}

struct TimedCombatModifier: Equatable, Sendable {
    let multiplier: Double
    let expiresAfterTurn: Int
}

struct CopySpellRecord: Equatable, Sendable {
    let spell: SpellID
    let category: SpellCategory
    var reused: Bool = false
}

struct ExpansionBattleState: Equatable, Sendable {
    var equippedSpells: [SpellID]? = nil
    var protectedSpells: Set<SpellID> = []
    var scheduledDamage: [ScheduledEnemyDamage] = []
    var nextReservationID = 0
    var enemyAmplification: Double? = nil
    var enemyPreservation: TimedCombatModifier? = nil
    var playerAttackWeakening: TimedCombatModifier? = nil
    var outputReduction: TimedCombatModifier? = nil
    var nextHitFlatReduction = 0
    var scheduledHitReduction: Double? = nil
    var chainAttackBonus = 0
    var nextTurnBarrier = 0
    var mimicProhibitionThroughEnemyTurn: Int? = nil
    var copyRecord: CopySpellRecord? = nil
    var lockedSpells: [SpellID: Int] = [:]
    var lastSuccessfulSpell: SpellID? = nil
    var lastSuccessfulSpellThisTurn: SpellID? = nil
    var successfulSpellHistory: [SpellID] = []
    var memorySutureUses = 0
    var retainsCorrectionBarrier = false
    var encounterPhase = 1

    var statusSummary: String {
        var parts: [String] = []
        if enemyAmplification != nil { parts.append("인과 증폭") }
        if enemyPreservation != nil { parts.append("원본 보존") }
        if playerAttackWeakening != nil { parts.append("공격 약화") }
        if outputReduction != nil { parts.append("출력 저하") }
        if copyRecord != nil { parts.append("모사 기록") }
        if !lockedSpells.isEmpty { parts.append("주문 봉인 \(lockedSpells.count)개") }
        if !scheduledDamage.isEmpty { parts.append("예약 피해 \(scheduledDamage.count)건") }
        return parts.isEmpty ? "임시 상태 없음" : parts.joined(separator: " · ")
    }

    var hasRemovableEnemyBuff: Bool {
        enemyAmplification != nil || enemyPreservation != nil || copyRecord != nil
    }

    mutating func clearTransientEffects() {
        let equipped = equippedSpells
        let protected = protectedSpells
        let phase = encounterPhase
        self = ExpansionBattleState()
        equippedSpells = equipped
        protectedSpells = protected
        encounterPhase = phase
    }
}

extension BattleState {
    func availableEffectTargets(for spell: SpellDefinition) -> [ExpansionTargetOption] {
        guard case let .expansion(effect) = spell.effect else { return [] }
        var options: [ExpansionTargetOption] = []
        switch effect {
        case .purificationGlyph:
            if expansion.playerAttackWeakening != nil {
                options.append(.init(id: .playerAttackWeakening, title: "공격 약화", detail: "자신의 다음 공격 약화 제거"))
            }
            for spell in SpellID.allCases where expansion.lockedSpells[spell] != nil {
                options.append(.init(id: .cardSeal(spell), title: "\(SpellCatalog.spell(spell).name) 봉인", detail: "해당 주문의 봉인 1개 제거"))
            }
            // An enemy absolute barrier never prevents cleansing oneself.
            if enemy.absoluteBarrierCharges == 0 {
                if expansion.enemyAmplification != nil {
                    options.append(.init(id: .enemyAmplification, title: "인과 증폭", detail: "예약 등록 전 증폭 제거"))
                }
                if expansion.enemyPreservation != nil {
                    options.append(.init(id: .enemyPreservation, title: "원본 보존", detail: "적의 다음 공격 피해 감소 버프 제거"))
                }
                if let record = expansion.copyRecord {
                    options.append(.init(id: .enemyCopyRecord, title: "모사 기록", detail: "\(SpellCatalog.spell(record.spell).name) 기록 제거"))
                }
            }
        case .consequenceErasure, .executionDelay:
            guard enemy.absoluteBarrierCharges == 0 else { return [] }
            for reservation in expansion.scheduledDamage.sorted(by: { $0.dueEnemyTurn < $1.dueEnemyTurn }) {
                guard effect != .executionDelay || !reservation.wasDelayed else { continue }
                let extra = effect == .executionDelay ? " → \(reservation.dueEnemyTurn + 1)턴에 집행" : " 취소"
                options.append(.init(id: .scheduledDamage(reservation.id), title: reservation.name, detail: "\(reservation.dueEnemyTurn)턴 · \(reservation.damage) 피해\(extra)"))
            }
            if effect == .consequenceErasure, enemy.normalBarrier > 0 {
                options.append(.init(id: .enemyNormalBarrier, title: "일반 방벽", detail: "방벽 \(enemy.normalBarrier) 소멸"))
            }
        default: break
        }
        return options
    }

    func spellUnavailabilityReason(for spell: SpellDefinition) -> String? {
        if !learnedSpells.contains(spell.id) { return "아직 배우지 않은 주문입니다." }
        if let equipped = expansion.equippedSpells, !equipped.contains(spell.id) { return "출전 가방에 없는 주문입니다." }
        if expansion.lockedSpells[spell.id] != nil { return "이번 턴 봉인된 주문입니다." }
        guard case let .expansion(effect) = spell.effect else { return nil }
        switch effect {
        case .purificationGlyph, .consequenceErasure, .executionDelay:
            if availableEffectTargets(for: spell).isEmpty { return "현재 선택할 수 있는 대상이 없습니다." }
        case .memorySuture:
            if expansion.memorySutureUses >= 2 { return "이 전투의 사용 횟수 2회를 모두 사용했습니다." }
        case .mimicProhibition:
            if player.hp <= 6 { return "HP가 6보다 많아야 사용할 수 있습니다." }
            if enemy.absoluteBarrierCharges > 0 { return "먼저 절대 방벽을 해제해야 합니다." }
        case .outputReduction:
            if enemy.absoluteBarrierCharges > 0 { return "먼저 절대 방벽을 해제해야 합니다." }
        default: break
        }
        return nil
    }
}
