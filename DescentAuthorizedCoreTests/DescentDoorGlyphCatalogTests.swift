import XCTest
@testable import DescentAuthorizedCore

final class DescentDoorGlyphCatalogTests: XCTestCase {
    func testEveryReferenceDoorGlyphIsAccepted() {
        let evaluator = GlyphEvaluator()

        for definition in DescentDoorGlyphCatalog.all.values {
            let result = evaluator.evaluate(
                glyph: definition.glyph,
                recommendedMana: definition.recommendedMana,
                strokes: definition.glyph.strokes.map {
                    DrawnStroke(points: $0.referencePath)
                },
                inputMethod: .pencil
            )

            XCTAssertEqual(result.grade, .perfect, definition.name)
        }
    }

    func testDoorStrokeComplexityIncreasesByFloor() {
        XCTAssertEqual(DescentDoorGlyphCatalog.floor10.requiredStrokes, 1)
        XCTAssertEqual(DescentDoorGlyphCatalog.floor9.requiredStrokes, 1)
        XCTAssertEqual(DescentDoorGlyphCatalog.floor8.requiredStrokes, 2)
        XCTAssertGreaterThan(
            DescentDoorGlyphCatalog.floor8.recommendedMana,
            DescentDoorGlyphCatalog.floor10.recommendedMana
        )
    }
}
