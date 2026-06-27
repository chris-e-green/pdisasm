import XCTest
@testable import pdisasm

final class ApplePascalDialectTests: XCTestCase {
    func testDisassemblyOptionsDefaultToCurrentApplePascalBehavior() {
        XCTAssertEqual(
            DisassemblyOptions().dialect,
            .applePascal
        )
    }

    func testDialectRoundTripsThroughCodableOptions() throws {
        let options = DisassemblyOptions(dialect: .ucsdPSystem)
        let data = try JSONEncoder().encode(options)
        let decoded = try JSONDecoder().decode(
            DisassemblyOptions.self,
            from: data
        )

        XCTAssertEqual(decoded.dialect, .ucsdPSystem)
    }

    func testAppleSegmentKeywordIsProfileSpecific() {
        XCTAssertEqual(
            renderPascalIdentifier("SEGMENT", dialect: .applePascal),
            "SEGMENT_"
        )
        XCTAssertEqual(
            renderPascalIdentifier("SEGMENT", dialect: .ucsdPSystem),
            "SEGMENT"
        )
        XCTAssertEqual(
            renderPascalIdentifier("BEGIN", dialect: .applePascal),
            "BEGIN_"
        )
        XCTAssertEqual(
            renderPascalIdentifier("BEGIN", dialect: .ucsdPSystem),
            "BEGIN_"
        )
    }

    func testDialectSelectionChangesOnlyProfileSpecificIdentifier() {
        let statements: [PascalStmt] = [
            .call(name: "SEGMENT", arguments: []),
            .call(name: "WRITELN", arguments: [.integer(1)]),
        ]

        XCTAssertEqual(
            PascalBlock(statements: statements).rendered(
                dialect: .applePascal
            ),
            [
                "BEGIN",
                "  SEGMENT_();",
                "  WRITELN(1);",
                "END",
            ]
        )
        XCTAssertEqual(
            PascalBlock(statements: statements).rendered(
                dialect: .ucsdPSystem
            ),
            [
                "BEGIN",
                "  SEGMENT();",
                "  WRITELN(1);",
                "END",
            ]
        )
    }

    func testUnverifiedRuntimePoliciesRetainCompatibility() {
        XCTAssertEqual(
            standardProcedures(for: .applePascal)[1]?.0,
            standardProcedures(for: .ucsdPSystem)[1]?.0
        )
        XCTAssertEqual(
            ApplePascalDialect.applePascal.policy.caseDefaultKeyword,
            "OTHERWISE"
        )
        XCTAssertEqual(
            ApplePascalDialect.ucsdPSystem.policy.caseDefaultKeyword,
            "OTHERWISE"
        )
        XCTAssertTrue(ApplePascalDialect.applePascal.policy.supportsUnitSyntax)
        XCTAssertTrue(ApplePascalDialect.ucsdPSystem.policy.supportsUnitSyntax)
        XCTAssertEqual(
            ApplePascalDialect.applePascal.policy.textFileTypeName,
            "TEXT"
        )
    }
}
