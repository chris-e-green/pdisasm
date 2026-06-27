import XCTest
@testable import pdisasm

final class PascalTypeDefinitionParserTests: XCTestCase {
    func testPhase35DeclarationFixture() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: "types_phase_3_5",
                withExtension: "pas",
                subdirectory: "Fixtures"
            )
        )
        let source = try String(contentsOf: url, encoding: .utf8)

        let definitions = PascalTypeDefinitionParser.parse(source)

        XCTAssertTrue(definitions.diagnostics.isEmpty)
        XCTAssertEqual(definitions.constants["LIMIT"], 8)
        XCTAssertEqual(definitions.constantValues["LIMIT"], .integer(8))
        XCTAssertEqual(definitions.constantValues["GREETING"], .string("'HELLO'"))
        XCTAssertEqual(definitions.constantValues["LETTER_A"], .character("'A'"))
        XCTAssertEqual(definitions.constantValues["ENABLED"], .boolean(true))
        XCTAssertEqual(definitions.constantValues["RATIO"], .real("3.125"))
        XCTAssertEqual(definitions.constantValues["DEFAULT_LIMIT"], .identifier("LIMIT"))
        XCTAssertEqual(definitions.constantValues["MASK"], .raw("LIMIT + 1"))

        XCTAssertEqual(definitions.aliases["BYTEFILE"], "FILE OF BYTE")
        XCTAssertEqual(definitions.aliases["TEXTFILE"], "TEXT")
        XCTAssertEqual(definitions.aliases["COLORSET"], "SET OF COLORS")
        XCTAssertEqual(definitions.aliases["NODEPTR"], "^NODE")
        XCTAssertEqual(definitions.aliases["LEFTPTR"], "^LEFTREC")
        XCTAssertEqual(definitions.aliases["RIGHTPTR"], "^RIGHTREC")
        XCTAssertEqual(
            definitions.aliases["COLORGRID"],
            "PACKED ARRAY[COLORS, 1..8] OF CHAR"
        )
        XCTAssertEqual(
            definitions.aliases["CALLBACK"],
            "PROCEDURE(VAR VALUE: INTEGER; FLAG: BOOLEAN)"
        )
        XCTAssertEqual(
            definitions.aliases["MAPPER"],
            "FUNCTION(VALUE: INTEGER; BASE: INTEGER): INTEGER"
        )

        XCTAssertEqual(definitions.scalarTypes["COLORS"]?.cases, ["RED", "GREEN", "BLUE"])
        XCTAssertEqual(record(named: "NODE", in: definitions)?.members[0]?.type, "NODEPTR")
        XCTAssertEqual(record(named: "LEFTREC", in: definitions)?.members[0]?.type, "RIGHTPTR")
        XCTAssertEqual(record(named: "RIGHTREC", in: definitions)?.members[0]?.type, "LEFTPTR")
    }

    func testMalformedDeclarationsProduceDiagnostics() {
        let definitions = PascalTypeDefinitionParser.parse(
            """
            TYPE
              BADSET = SET INTEGER;
              BADARRAY = ARRAY[1..3] CHAR;
              BROKEN = RECORD
                VALUE: INTEGER;
            """
        )

        XCTAssertTrue(definitions.diagnostics.contains {
            $0.message.contains("BADSET") && $0.message.contains("missing OF")
        })
        XCTAssertTrue(definitions.diagnostics.contains {
            $0.message.contains("BADARRAY") && $0.message.contains("missing OF")
        })
        XCTAssertTrue(definitions.diagnostics.contains {
            $0.message.contains("BROKEN") && $0.message.contains("missing END")
        })
    }

    func testNestedRecordEndDoesNotTerminateOuterDeclaration() {
        let definitions = PascalTypeDefinitionParser.parse(
            """
            TYPE
              OUTER = RECORD
                CHILD: RECORD
                  VALUE: INTEGER
                END;
                NEXT: INTEGER
              END;
              AFTER = INTEGER;
            """
        )

        XCTAssertNotNil(record(named: "OUTER", in: definitions))
        XCTAssertEqual(definitions.aliases["AFTER"], "INTEGER")
        XCTAssertFalse(definitions.diagnostics.contains { $0.severity == .error })
    }

    func testMetadataConstantDecodesLegacyIntegerShape() throws {
        let data = try XCTUnwrap(#"{"name":"MAX","value":15}"#.data(using: .utf8))

        let constant = try JSONDecoder().decode(MetadataConstant.self, from: data)

        XCTAssertEqual(constant.name, "MAX")
        XCTAssertEqual(constant.value, 15)
        XCTAssertEqual(constant.constantValue, .integer(15))
    }

    func testMetadataConstantRoundTripsRichValue() throws {
        let original = MetadataConstant(
            name: "GREETING",
            constantValue: .string("'HELLO'")
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MetadataConstant.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.constantValue.sourceText, "'HELLO'")
    }

    func testMetadataSnapshotPreservesParserDiagnostics() {
        let diagnostic = Diagnostic(
            severity: .warning,
            message: "Unsupported declaration form."
        )

        let snapshot = MetadataSnapshot(merging: [
            MetadataBundle(diagnostics: [diagnostic]),
            MetadataBundle(diagnostics: [diagnostic])
        ])

        XCTAssertEqual(snapshot.diagnostics, [diagnostic])
    }

    func testMetadataContainersDecodeWithoutLegacyDiagnosticsField() throws {
        let encoder = JSONEncoder()
        let bundleData = try encoder.encode(MetadataBundle())
        let snapshotData = try encoder.encode(MetadataSnapshot())

        for (data, decode) in [
            (bundleData, { data in
                try JSONDecoder().decode(MetadataBundle.self, from: data).diagnostics
            }),
            (snapshotData, { data in
                try JSONDecoder().decode(MetadataSnapshot.self, from: data).diagnostics
            })
        ] {
            var object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: data) as? [String: Any]
            )
            object.removeValue(forKey: "diagnostics")
            let legacyData = try JSONSerialization.data(withJSONObject: object)

            XCTAssertEqual(try decode(legacyData), [])
        }
    }

    func testFileBackedMetadataPreservesRichConstantsAndDiagnostics() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdisasm-phase-3-5-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try """
            CONST
              GREETING = 'HELLO';
            TYPE
              BADSET = SET INTEGER;
            """.write(
                to: directory.appendingPathComponent("types_SAMPLE.pas"),
                atomically: true,
                encoding: .utf8
            )

        let snapshot = try MetadataScopeResolver(
            repository: FileBackedMetadataRepository(
                workspace: MetadataWorkspace(writableDirectory: directory)
            )
        ).resolve(fileIdentifier: "SAMPLE", version: 1)

        XCTAssertEqual(
            snapshot.constants.first { $0.value.name == "GREETING" }?.value.constantValue,
            .string("'HELLO'")
        )
        XCTAssertTrue(snapshot.diagnostics.contains {
            $0.message.contains("BADSET") && $0.message.contains("missing OF")
        })
    }

    private func record(
        named name: String,
        in definitions: PascalTypeDefinitions
    ) -> PascalRecord? {
        definitions.records.first { $0.name == name }
    }
}
