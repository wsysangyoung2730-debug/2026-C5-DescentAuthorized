import XCTest
@testable import DescentAuthorizedCore

final class CombatEffectCatalogTests: XCTestCase {
    func testEverySuppliedEffectIsReachableAndPackaged() throws {
        let reachable = (1...9).reduce(into: Set<CombatEffectID>()) { $0.formUnion(CombatEffectCatalog.required(floor: $1)) }
        XCTAssertEqual(reachable, Set(CombatEffectID.allCases))
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("DescentAuthorized/Resources/Reality/VFX/Authored")
        for id in reachable {
            let data = try Data(contentsOf: root.appendingPathComponent(id.rawValue + "/effect.usdc"))
            XCTAssertEqual(String(data: data.prefix(8), encoding: .ascii), "PXR-USDC", id.rawValue)
        }
    }
    func testCounterAndScheduledExecutionUseVerdictRatherThanCopyStroke() {
        let copy = EnemyAction.expansion(name: "renamed", action: .copyReaction(baseDamage: 16, categoryEffects: false, extraDamage: 0))
        let counter = EnemyAction.expansion(name: "renamed", action: .sequence([.directHits([24]), .counterExecute]))
        for floor in [1, 4] {
            XCTAssertEqual(CombatEffectCatalog.projectile(floor: floor, action: copy), .signatureStroke)
            XCTAssertEqual(CombatEffectCatalog.projectile(floor: floor, action: counter), .verdictStamp)
        }
        XCTAssertEqual(CombatEffectCatalog.projectile(floor: 1, action: .expansion(name: "wait", action: .wait), executionOnly: true), .verdictStamp)
    }
    func testAllAttacksAndBarriersArePreloadedForTheirFloor() {
        let attack = EnemyAction.attack(name: "test", damage: 12, isStrong: false)
        for floor in 1...9 {
            let required = CombatEffectCatalog.required(floor: floor)
            XCTAssertTrue(required.contains(CombatEffectCatalog.projectile(floor: floor, action: attack)))
            for absolute in [true, false] {
                XCTAssertTrue(required.contains(CombatEffectCatalog.barrier(floor: floor, absolute: absolute)))
            }
        }
    }
}
