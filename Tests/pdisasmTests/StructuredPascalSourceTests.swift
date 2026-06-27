import XCTest
@testable import pdisasm

final class StructuredPascalSourceTests: XCTestCase {
    private func instruction(
        _ opcode: UInt8 = nop,
        params: [Int] = [],
        location: Location? = nil,
        pseudoCode: String? = nil,
        prePseudoCode: [String] = [],
        forLoopEvidence: ForLoopEvidence? = nil
    ) -> Instruction {
        Instruction(
            opcode: opcode,
            mnemonic: "",
            params: params,
            memLocation: location,
            pseudoCode: pseudoCode,
            prePseudoCode: prePseudoCode,
            forLoopEvidence: forLoopEvidence
        )
    }

    private func procedure(
        _ instructions: [Int: Instruction]
    ) -> Procedure {
        let procedure = Procedure()
        procedure.instructions = instructions
        return procedure
    }

    private func renderedStatements(
        for procedure: Procedure
    ) -> [String] {
        var builder = StructuredPascalSourceBuilder(
            procedure: procedure,
            allLocations: []
        )
        return PascalBlock(statements: builder.build()).rendered()
    }

    func testBuildsIfElseASTWithoutLegacyMarkers() {
        let lines = renderedStatements(
            for: procedure([
                0: instruction(
                    fjp,
                    params: [4],
                    pseudoCode: "IF READY THEN BEGIN"
                ),
                2: instruction(
                    nop,
                    pseudoCode: "VALUE := 1"
                ),
                3: instruction(
                    ujp,
                    params: [6],
                    pseudoCode: "END ELSE BEGIN"
                ),
                4: instruction(
                    nop,
                    pseudoCode: "VALUE := 2"
                ),
                5: instruction(ujp, params: [6]),
                6: instruction(
                    rnp,
                    prePseudoCode: ["END (* IF READY *)"]
                ),
            ])
        )

        XCTAssertEqual(lines, [
            "BEGIN",
            "  IF READY THEN",
            "    BEGIN",
            "      VALUE := 1;",
            "    END",
            "  ELSE",
            "    BEGIN",
            "      VALUE := 2;",
            "    END",
            "END",
        ])
    }

    func testBuildsWhileAndNestedConditionalAST() {
        let lines = renderedStatements(
            for: procedure([
                0: instruction(
                    fjp,
                    params: [10],
                    pseudoCode: "WHILE ACTIVE DO BEGIN"
                ),
                2: instruction(
                    fjp,
                    params: [6],
                    pseudoCode: "IF READY THEN BEGIN"
                ),
                4: instruction(nop, pseudoCode: "WORK()"),
                5: instruction(ujp, params: [8]),
                6: instruction(nop, pseudoCode: "WAIT()"),
                8: instruction(ujp, params: [0]),
                10: instruction(rnp),
            ])
        )

        XCTAssertEqual(lines, [
            "BEGIN",
            "  WHILE ACTIVE DO",
            "    BEGIN",
            "      IF READY THEN",
            "        BEGIN",
            "          WORK();",
            "        END",
            "      ELSE",
            "        BEGIN",
            "          WAIT();",
            "        END",
            "    END",
            "END",
        ])
    }

    func testBuildsRepeatUntilAST() {
        let lines = renderedStatements(
            for: procedure([
                0: instruction(nop, pseudoCode: "STEP()"),
                1: instruction(ujp, params: [4]),
                4: instruction(
                    fjp,
                    params: [0],
                    pseudoCode: "UNTIL DONE"
                ),
                6: instruction(rnp),
            ])
        )

        XCTAssertEqual(lines, [
            "BEGIN",
            "  REPEAT",
            "    STEP();",
            "  UNTIL DONE;",
            "END",
        ])
    }

    func testBuildsForASTAndOmitsSetupAndUpdateStores() {
        let variable = Location(
            segment: 1,
            procedure: 1,
            lexLevel: 0,
            addr: 1,
            name: "I"
        )
        let lines = renderedStatements(
            for: procedure([
                0: instruction(ldci, params: [1]),
                2: instruction(
                    stl,
                    location: variable,
                    pseudoCode: "I := 1"
                ),
                4: instruction(ldl, location: variable),
                6: instruction(ldci, params: [10]),
                8: instruction(leqi),
                9: instruction(
                    fjp,
                    params: [20],
                    pseudoCode: "FOR legacy text is ignored",
                    forLoopEvidence: ForLoopEvidence(
                        direction: .to,
                        variable: StructuredForVariable(variable),
                        startExpression: "1",
                        limitExpression: "10",
                        initializationStoreAddress: 2,
                        setupAddresses: [2],
                        updateStoreAddress: 17
                    )
                ),
                11: instruction(nop, pseudoCode: "USE(I)"),
                12: instruction(ldl, location: variable),
                14: instruction(ldci, params: [1]),
                16: instruction(adi),
                17: instruction(
                    stl,
                    location: variable,
                    pseudoCode: "I := I + 1"
                ),
                19: instruction(ujp, params: [4]),
                20: instruction(rnp),
            ])
        )

        XCTAssertEqual(lines, [
            "BEGIN",
            "  FOR I := 1 TO 10 DO",
            "    BEGIN",
            "      USE(I);",
            "    END",
            "END",
        ])
    }

    func testBuildsCaseASTWithRangesAndDefaultArm() {
        let lines = renderedStatements(
            for: procedure([
                0: instruction(
                    ujp,
                    params: [10],
                    pseudoCode: "CASE CHOICE OF"
                ),
                2: instruction(nop, pseudoCode: "ONE()"),
                3: instruction(ujp, params: [14]),
                4: instruction(nop, pseudoCode: "MANY()"),
                5: instruction(ujp, params: [14]),
                6: instruction(nop, pseudoCode: "OTHER()"),
                7: instruction(ujp, params: [14]),
                10: instruction(
                    xjp,
                    params: [1, 3, 100, 6, 2, 4, 4]
                ),
                14: instruction(rnp),
            ])
        )

        XCTAssertEqual(lines, [
            "BEGIN",
            "  CASE CHOICE OF",
            "    1:",
            "      ONE();",
            "    2..3:",
            "      MANY();",
            "    OTHERWISE",
            "      OTHER();",
            "  END",
            "END",
        ])
    }

    func testDoesNotActivateForUnstructuredProcedure() {
        let procedure = procedure([
            0: instruction(nop, pseudoCode: "VALUE := 1"),
            1: instruction(rnp),
        ])
        var builder = StructuredPascalSourceBuilder(
            procedure: procedure,
            allLocations: []
        )

        XCTAssertFalse(builder.hasStructuredRegions)
        XCTAssertTrue(builder.build().isEmpty)
    }

    func testConditionalLoopExitRemainsConditionalGoto() {
        let lines = renderedStatements(
            for: procedure([
                0: instruction(
                    fjp,
                    params: [12],
                    pseudoCode: "WHILE ACTIVE DO BEGIN"
                ),
                2: instruction(
                    fjp,
                    params: [10],
                    pseudoCode: "IF READY THEN BEGIN"
                ),
                4: instruction(nop, pseudoCode: "WORK()"),
                6: instruction(ujp, params: [0]),
                10: instruction(ujp, params: [14]),
                12: instruction(ujp, params: [14]),
                14: instruction(rnp),
            ])
        )

        XCTAssertTrue(lines.contains("      IF NOT READY THEN"))
        XCTAssertTrue(lines.contains("        GOTO LAB10;"))
        XCTAssertFalse(lines.contains("      GOTO LAB10;"))
    }

    func testBuildsNestedForLoopsFromStructuredEvidence() {
        let outer = Location(
            segment: 1,
            procedure: 1,
            lexLevel: 0,
            addr: 1,
            name: "I"
        )
        let inner = Location(
            segment: 1,
            procedure: 1,
            lexLevel: 0,
            addr: 2,
            name: "J"
        )
        let lines = renderedStatements(
            for: procedure([
                0: instruction(ldci, params: [1]),
                2: instruction(stl, location: outer, pseudoCode: "I := 1"),
                4: instruction(ldl, location: outer),
                6: instruction(ldci, params: [2]),
                8: instruction(leqi),
                9: instruction(
                    fjp,
                    params: [40],
                    forLoopEvidence: ForLoopEvidence(
                        direction: .to,
                        variable: StructuredForVariable(outer),
                        startExpression: "1",
                        limitExpression: "2",
                        initializationStoreAddress: 2,
                        setupAddresses: [2],
                        updateStoreAddress: 35
                    )
                ),
                11: instruction(ldci, params: [1]),
                12: instruction(stl, location: inner, pseudoCode: "J := 1"),
                14: instruction(ldl, location: inner),
                16: instruction(ldci, params: [3]),
                18: instruction(leqi),
                19: instruction(
                    fjp,
                    params: [30],
                    forLoopEvidence: ForLoopEvidence(
                        direction: .to,
                        variable: StructuredForVariable(inner),
                        startExpression: "1",
                        limitExpression: "3",
                        initializationStoreAddress: 12,
                        setupAddresses: [12],
                        updateStoreAddress: 27
                    )
                ),
                21: instruction(nop, pseudoCode: "USE(I, J)"),
                22: instruction(ldl, location: inner),
                24: instruction(ldci, params: [1]),
                26: instruction(adi),
                27: instruction(stl, location: inner),
                29: instruction(ujp, params: [14]),
                30: instruction(ldl, location: outer),
                32: instruction(ldci, params: [1]),
                34: instruction(adi),
                35: instruction(stl, location: outer),
                37: instruction(ujp, params: [4]),
                40: instruction(rnp),
            ])
        )

        XCTAssertTrue(lines.contains("  FOR I := 1 TO 2 DO"))
        XCTAssertTrue(lines.contains("      FOR J := 1 TO 3 DO"))
        XCTAssertTrue(lines.contains("          USE(I, J);"))
    }

    func testNonUnitUpdateRemainsWhileWithVisibleAssignment() {
        let variable = Location(
            segment: 1,
            procedure: 1,
            lexLevel: 0,
            addr: 1,
            name: "I"
        )
        let lines = renderedStatements(
            for: procedure([
                0: instruction(
                    fjp,
                    params: [12],
                    pseudoCode: "WHILE I <= 10 DO BEGIN"
                ),
                2: instruction(nop, pseudoCode: "WORK()"),
                4: instruction(
                    stl,
                    location: variable,
                    pseudoCode: "I := I + 2"
                ),
                6: instruction(ujp, params: [0]),
                12: instruction(rnp),
            ])
        )

        XCTAssertTrue(lines.contains("  WHILE I <= 10 DO"))
        XCTAssertTrue(lines.contains("      I := I + 2;"))
        XCTAssertFalse(lines.contains { $0.contains("FOR I") })
    }
}
