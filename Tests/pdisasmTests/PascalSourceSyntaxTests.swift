import XCTest
@testable import pdisasm

final class PascalSourceSyntaxTests: XCTestCase {
    func testFunctionResultAssignmentUsesLocalFunctionName() {
        let resultLocation = Location(
            segment: 1,
            procedure: 2,
            lexLevel: 1,
            addr: 1,
            isParam: true,
            name: "MATH.CALCULATE",
            type: "INTEGER"
        )
        let function = ProcedureIdentifier(
            isFunction: true,
            segment: 1,
            segmentName: "MATH",
            procedure: 2,
            procName: "CALCULATE",
            returnType: "INTEGER"
        )
        function.returnLocation = resultLocation
        let statement = PseudoCodeStatement.assignment(
            targetValue: StackValue(
                text: resultLocation.displayName,
                type: "INTEGER",
                kind: .address,
                location: resultLocation
            ),
            targetText: resultLocation.displayName,
            source: "42"
        )

        XCTAssertEqual(
            statement.pascalSourceStatement(
                functionResultStorage: function.functionResultStorage,
                functionName: "CALCULATE"
            ).rendered(),
            ["CALCULATE := 42;"]
        )
    }

    func testBinaryExpressionRendererPreservesPrecedence() {
        let expr = PascalExpr.binary(
            .multiply,
            .binary(.add, .identifier("A"), .identifier("B")),
            .identifier("C")
        )

        XCTAssertEqual(expr.rendered(), "(A + B) * C")
    }

    func testRightNestedSubtractionIsParenthesized() {
        let expr = PascalExpr.binary(
            .subtract,
            .identifier("A"),
            .binary(.subtract, .identifier("B"), .identifier("C"))
        )

        XCTAssertEqual(expr.rendered(), "A - (B - C)")
    }


    func testBooleanExpressionRendererPreservesPrecedence() {
        let expr = PascalExpr.binary(
            .or,
            .identifier("A"),
            .binary(.and, .identifier("B"), .unary(.not, .identifier("C")))
        )

        XCTAssertEqual(expr.rendered(), "A OR B AND NOT C")
    }

    func testComparisonExpressionRendererParenthesizesArithmeticOperands() {
        let expr = PascalExpr.binary(
            .lessThanOrEqual,
            .binary(.add, .identifier("I"), .integer(1)),
            .identifier("LIMIT")
        )

        XCTAssertEqual(expr.rendered(), "I + 1 <= LIMIT")
    }

    func testCallIndexAndFieldRendering() {
        let expr = PascalExpr.field(
            base: .index(
                base: .call(name: "GETREC", arguments: [.integer(1), .string("O'Brien")]),
                index: .identifier("I")
            ),
            name: "NAME"
        )

        XCTAssertEqual(expr.rendered(), "GETREC(1, 'O''Brien')[I].NAME")
    }

    func testCharacterLiteralRenderingUsesCHRForControlAndHighBitCharacters() {
        XCTAssertEqual(renderPascalCharLiteral(65), "'A'")
        XCTAssertEqual(renderPascalCharLiteral(39), "''''")
        XCTAssertEqual(renderPascalCharLiteral(10), "CHR(10)")
        XCTAssertEqual(renderPascalCharLiteral(128), "CHR(128)")
    }

    func testStringLiteralRenderingEscapesQuotesAndUsesCHRForUnsafeScalars() {
        XCTAssertEqual(renderPascalStringLiteral(""), "''")
        XCTAssertEqual(renderPascalStringLiteral("O'Brien"), "'O''Brien'")
        XCTAssertEqual(renderPascalStringLiteral("A\nB"), "'A' + CHR(10) + 'B'")
        XCTAssertEqual(renderPascalStringLiteral("A" + String(UnicodeScalar(0x80)!) + "B"), "'A' + CHR(128) + 'B'")
    }

    func testIdentifierRenderingSanitizesInvalidNamesAndKeywords() {
        XCTAssertTrue(isValidPascalIdentifier("GOOD_NAME1"))
        XCTAssertFalse(isValidPascalIdentifier("1BAD"))
        XCTAssertEqual(renderPascalIdentifier("BEGIN"), "BEGIN_")
        XCTAssertEqual(renderPascalIdentifier("1 bad-name"), "_1_bad_name")
        XCTAssertEqual(renderPascalIdentifier(""), "_")
    }

    func testSourceIdentifiersAreSanitizedInExpressionsAndStatements() {
        XCTAssertEqual(PascalExpr.identifier("BEGIN").rendered(), "BEGIN_")
        XCTAssertEqual(PascalExpr.field(base: .identifier("rec value"), name: "1field").rendered(), "rec_value._1field")
        XCTAssertEqual(PascalStmt.goto(label: "END").rendered(), ["GOTO END_;"])
    }

    func testCaseStatementRendererUsesPascalRangeSyntax() {
        let statement = PascalStmt.caseStatement(
            PascalCaseStatement(
                expression: .identifier("CHOICE"),
                arms: [
                    PascalCaseArm(labels: [.integer(1)], body: [.call(name: "ONE", arguments: [])]),
                    PascalCaseArm(labels: [.range(.integer(2), .integer(4)), .integer(7)], body: [.call(name: "MANY", arguments: [])]),
                ],
                defaultBody: nil
            )
        )

        XCTAssertEqual(statement.rendered(), [
            "CASE CHOICE OF",
            "  1:",
            "    ONE();",
            "  2..4, 7:",
            "    MANY();",
            "END",
        ])
    }

    func testCaseRendererTerminatesArmsAndUsesDefaultPolicy() {
        let statement = PascalStmt.caseStatement(
            PascalCaseStatement(
                expression: .identifier("CHOICE"),
                arms: [
                    PascalCaseArm(
                        labels: [.integer(1)],
                        body: [
                            .call(name: "FIRST", arguments: []),
                            .call(name: "SECOND", arguments: []),
                        ]
                    )
                ],
                defaultBody: [
                    .call(name: "OTHER", arguments: [])
                ]
            )
        )

        XCTAssertEqual(statement.rendered(), [
            "CASE CHOICE OF",
            "  1:",
            "    BEGIN",
            "      FIRST();",
            "      SECOND();",
            "    END;",
            "  OTHERWISE",
            "    OTHER();",
            "END",
        ])
    }

    func testStatementRendererAddsSemicolonsToStatements() {
        let statement = PascalStmt.assignment(target: .identifier("DEST"), source: .binary(.add, .identifier("A"), .integer(1)))

        XCTAssertEqual(statement.rendered(), ["DEST := A + 1;"])
    }

    func testForRendererUnwrapsSingleStatementBlock() {
        let statement = PascalStmt.forLoop(
            variable: "S_IDX",
            start: .integer(1),
            limit: .call(name: "LENGTH", arguments: [.identifier("S_COPY")]),
            direction: .to,
            body: .block([
                .raw("TURTLEGR.WCHAR(S_COPY[S_IDX])")
            ])
        )

        XCTAssertEqual(statement.rendered(), [
            "FOR S_IDX := 1 TO LENGTH(S_COPY) DO",
            "  TURTLEGR.WCHAR(S_COPY[S_IDX]);",
        ])
    }

    func testForRendererKeepsMultiStatementBlock() {
        let statement = PascalStmt.forLoop(
            variable: "I",
            start: .integer(1),
            limit: .integer(2),
            direction: .to,
            body: .block([
                .call(name: "FIRST", arguments: []),
                .call(name: "SECOND", arguments: []),
            ])
        )

        XCTAssertEqual(statement.rendered(), [
            "FOR I := 1 TO 2 DO",
            "  BEGIN",
            "    FIRST();",
            "    SECOND();",
            "  END",
        ])
    }

    func testIfElseRendererUnwrapsSingleStatementBlocks() {
        let statement = PascalStmt.ifElse(
            condition: .identifier("READY"),
            thenBlock: .block([
                .assignment(target: .identifier("VALUE"), source: .integer(1))
            ]),
            elseBlock: .block([
                .assignment(target: .identifier("VALUE"), source: .integer(0))
            ])
        )

        XCTAssertEqual(statement.rendered(), [
            "IF READY THEN",
            "  VALUE := 1;",
            "ELSE",
            "  VALUE := 0;",
        ])
    }

    func testWhileRendererUnwrapsSingleStatementBlock() {
        let statement = PascalStmt.whileDo(
            condition: .identifier("READY"),
            body: .block([
                .assignment(
                    target: .identifier("COUNT"),
                    source: .binary(
                        .add,
                        .identifier("COUNT"),
                        .integer(1)
                    )
                )
            ])
        )

        XCTAssertEqual(statement.rendered(), [
            "WHILE READY DO",
            "  COUNT := COUNT + 1;",
        ])
    }


    func testIfElseRendererDoesNotPutSemicolonBeforeElse() {
        let statement = PascalStmt.ifElse(
            condition: .identifier("FLAG"),
            thenBlock: .assignment(target: .identifier("A"), source: .integer(1)),
            elseBlock: .assignment(target: .identifier("A"), source: .integer(0))
        )

        XCTAssertEqual(statement.rendered(), [
            "IF FLAG THEN",
            "  A := 1;",
            "ELSE",
            "  A := 0;",
        ])
    }

    func testBlockRendererOwnsBeginEndAndIndentation() {
        let block = PascalBlock(statements: [
            .assignment(target: .identifier("A"), source: .integer(1)),
            .call(name: "WRITELN", arguments: [.identifier("A")]),
        ])

        XCTAssertEqual(block.rendered(), [
            "BEGIN",
            "  A := 1;",
            "  WRITELN(A);",
            "END",
        ])
    }

    func testPseudoCodeAssignmentBridgesToPascalStatement() {
        let statement = PseudoCodeStatement.assignment(targetLocation: nil, targetText: "DEST", source: "SRC + 1")
            .pascalSourceStatement

        XCTAssertEqual(statement.rendered(), ["DEST := SRC + 1;"])
    }
}
