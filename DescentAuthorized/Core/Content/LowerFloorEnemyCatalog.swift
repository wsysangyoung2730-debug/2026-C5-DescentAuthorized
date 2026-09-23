import Foundation

enum EnemyDamageOrigin: Equatable, Sendable {
    case direct, reservation(String), copy, counter
}
struct ReactiveDamage: Equatable, Sendable {
    let amount: Int
    let origin: EnemyDamageOrigin
}

extension EnemyID {
    var lowerFloorNumber: Int? {
        switch self {
        case .signatureMimicResidual, .rejectionExecutionResidual, .responsibilityAuditAdministrator: 4
        case .consentCustodianResidual, .quarantineEnforcerResidual, .voluntaryQuarantineAdministrator: 3
        case .overloadResidual, .backflowBlockerResidual, .sealMaintenanceAdministrator: 2
        case .identityComparisonResidual, .exitReviewResidual, .finalAuthorizationAdministrator: 1
        default: nil
        }
    }
    var isLowerFloorBoss: Bool {
        [.responsibilityAuditAdministrator, .voluntaryQuarantineAdministrator,
         .sealMaintenanceAdministrator, .finalAuthorizationAdministrator].contains(self)
    }
}

enum LowerFloorEnemyCatalog {
    static let entries: [(Int, EnemyID, String, Int)] = [
        (4, .signatureMimicResidual, "서명 모사 잔류체", 190),
        (4, .rejectionExecutionResidual, "반려 집행 잔류체", 220),
        (4, .responsibilityAuditAdministrator, "책임 심사 관리자", 600),
        (3, .consentCustodianResidual, "동의 보관 잔류체", 210),
        (3, .quarantineEnforcerResidual, "격리 집행 잔류체", 240),
        (3, .voluntaryQuarantineAdministrator, "자발 격리 관리자", 660),
        (2, .overloadResidual, "과부하 잔류체", 230),
        (2, .backflowBlockerResidual, "역류 차단 잔류체", 260),
        (2, .sealMaintenanceAdministrator, "봉인 유지 관리자", 720),
        (1, .identityComparisonResidual, "신원 대조 잔류체", 250),
        (1, .exitReviewResidual, "퇴거 심사 잔류체", 280),
        (1, .finalAuthorizationAdministrator, "최종 승인 관리자", 800)
    ]
    static let all = Dictionary(uniqueKeysWithValues: entries.map { entry in
        (entry.1, EnemyDefinition(id: entry.1, name: entry.2, maxHP: entry.3,
            startingAbsoluteBarrierCharges: 0, pattern: pattern(for: entry.1), thresholdRules: []))
    })
    static func enemy(floor: Int, isBoss: Bool, residualIndex: Int) -> EnemyDefinition? {
        let entries = entries.filter { $0.0 == floor }
        let index = isBoss ? 2 : residualIndex
        guard entries.indices.contains(index) else { return nil }
        return all[entries[index].1]
    }

    static func pattern(for id: EnemyID, phase: Int = 1, cycle: Int = 0) -> [EnemyAction] {
        func action(_ name: String, _ actions: ExpansionEnemyAction...) -> EnemyAction {
            .expansion(name: name, action: .sequence(actions))
        }
        func hit(_ name: String, _ damage: Int) -> EnemyAction { action(name, .directHits([damage])) }
        func schedule(_ name: String, _ damage: Int, _ delay: Int) -> ScheduledDamageSpec {
            .init(name: name, damage: damage, turnsFromNow: delay)
        }
        let rest = action("기록 정리 · 빈틈", .wait)
        switch id {
        case .signatureMimicResidual, .identityComparisonResidual:
            return [action("서명 기록", .recordLastSpell), action("원본 대조", .copyReaction(
                baseDamage: id == .signatureMimicResidual ? 12 : 16, categoryEffects: false,
                extraDamage: id == .signatureMimicResidual ? 8 : 10)), rest]
        case .rejectionExecutionResidual:
            return [action("반려 준비", .counterPrepare(damage: 10)), action("반려 집행", .directHits([16]), .counterExecute), rest]
        case .consentCustodianResidual:
            return [action("동의 대상 제시", .lockCards(count: 2, duration: 1, chooseOne: true)), hit("동의 집행", 14), rest]
        case .quarantineEnforcerResidual:
            return [action("격리 등록", .directHits([8]), .schedule([schedule("격리 A",12,1), schedule("격리 B",18,2)])), rest, rest, rest]
        case .overloadResidual:
            return [action("출력 증폭", .flatAmplify(8)), action("과부하 등록", .schedule([schedule("과부하 집행",22,2)])), hit("누출 경고",8), rest, rest]
        case .backflowBlockerResidual:
            return [action("역류 차폐", .timedBarrier(amount: 20, turns: 1), .counterPrepare(damage: 8)),
                    action("역류 집행", .barrierStrike(base: 18, bonus: 8), .counterExecute), rest]
        case .exitReviewResidual:
            return [action("퇴거 차폐", .timedBarrier(amount: 24, turns: 2)), action("퇴거 예약", .schedule([schedule("퇴거 집행",32,1)])), rest, rest]
        case .responsibilityAuditAdministrator:
            return [action("서명 채취", .directHits([phase == 1 ? 12 : 16]), .recordLastSpell),
                    action("원본 대조", .copyReaction(baseDamage: phase == 1 ? 16 : 18, categoryEffects: false, extraDamage: phase == 1 ? 8 : 10)),
                    action("반격 준비", .counterPrepare(damage: phase == 1 ? 16 : 20)),
                    action("반려 집행", .directHits([phase == 1 ? 24 : 28]), .counterExecute), rest]
        case .voluntaryQuarantineAdministrator:
            let specs = phase == 1 ? [schedule("격리 A",16,1),schedule("격리 B",16,2)] : [schedule("격리 A",20,2),schedule("격리 B",24,2)]
            return [action("동의 대상 제시", .lockCards(count: 2, duration: 3, chooseOne: true)),
                    action("집행 예약", .schedule(specs)), hit("경고 공격",8), rest, rest]
        case .sealMaintenanceAdministrator:
            let specs = phase == 1 ? [schedule("유지 집행",32,2)] : cycle.isMultiple(of: 2)
                ? [schedule("유지 강타",36,2)] : [schedule("유지 A",18,2),schedule("유지 B",18,2)]
            return [action("출력 분배", .flatAmplify(phase == 1 ? 8 : 12)), action("큰 예약 확정", .schedule(specs)),
                    action("누출 경고", .directHits([8]), phase == 1 ? .wait : .counterPrepare(damage: 12)),
                    action("유지 집행", phase == 1 ? .wait : .counterExecute), rest]
        case .finalAuthorizationAdministrator:
            if phase == 1 {
                return [action("신원 채취", .directHits([12]), .recordLastSpell),
                    action("신원 대조", .copyReaction(baseDamage: 20, categoryEffects: false, extraDamage: 8)),
                    action("반격 준비", .counterPrepare(damage: 16)), action("심사 집행", .directHits([24]), .counterExecute), rest]
            }
            if phase == 2 {
                return [action("유지 심사", .lockCards(count: 1, duration: 3, chooseOne: false), cycle == 0 ? .absoluteSeal(1) : .wait),
                    action("인계 예약", .schedule([schedule("인계 A",16,2),schedule("인계 B",16,2)])), hit("유지 경고",8), rest, rest]
            }
            return [action("인계 심사", .lockCards(count: 2, duration: 3, chooseOne: false)),
                    action("분할 집행", .directHits([24,24])), rest, hit("최종 집행",44), rest]
        default: return []
        }
    }
}
