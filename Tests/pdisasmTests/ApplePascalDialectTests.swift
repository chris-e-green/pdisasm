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

    func testLegacyOptionsWithoutDialectUseCompatibilityDefault() throws {
        let legacyJSON = """
        {
          "verbose": false,
          "writeMetadata": false,
          "overwriteMetadata": false,
          "showMarkup": true,
          "showPCode": true,
          "showStackState": false,
          "showPseudoCode": true,
          "showPascalSource": false,
          "showDot": false
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(
            DisassemblyOptions.self,
            from: legacyJSON
        )

        XCTAssertEqual(decoded.dialect, .applePascal)
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
            PascalExpr.identifier("SEGMENT").rendered(
                dialect: .applePascal
            ),
            "SEGMENT_"
        )
        XCTAssertEqual(
            PascalExpr.identifier("SEGMENT").rendered(
                dialect: .ucsdPSystem
            ),
            "SEGMENT"
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
        XCTAssertEqual(
            PascalType.parse("TEXT").renderedType(for: .ucsdPSystem),
            "TEXT"
        )
    }

    func testTranscendentalFunctionsAreNotStandardProcedures() {
        for dialect in ApplePascalDialect.allCases {
            for procNum in 25...31 {
                XCTAssertNil(standardProcedures(for: dialect)[procNum])
            }
        }
    }

    func testServiceCarriesSelectedDialectIntoResult() throws {
        let fixture = try XCTUnwrap(
            Bundle.module.url(
                forResource: "SYSTEM.LIBRARY-02-00",
                withExtension: "bin",
                subdirectory: "Fixtures"
            )
        )
        let result = try DisassemblyService().run(
            DisassemblyRunRequest(
                source: .file(fixture),
                options: DisassemblyOptions(dialect: .ucsdPSystem)
            )
        )

        XCTAssertEqual(result.legacyResult.dialect, .ucsdPSystem)
    }
}
