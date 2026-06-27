import XCTest
@testable import pdisasm

final class StructuredControlFlowTests: XCTestCase {
    private func instruction(
        _ opcode: UInt8 = nop,
        params: [Int] = []
    ) -> Instruction {
        Instruction(opcode: opcode, mnemonic: "", params: params)
    }

    private func graph(_ instructions: [Int: Instruction]) -> ControlFlowGraph {
        let procedure = Procedure()
        procedure.instructions = instructions
        return ControlFlowGraph(procedure: procedure)
    }

    func testImmediateDominatorAndPostDominator() {
        let graph = graph([
            0: instruction(fjp, params: [4]),
            2: instruction(ujp, params: [6]),
            4: instruction(),
            6: instruction(rnp),
        ])

        XCTAssertEqual(graph.immediateDominator(of: 2), 0)
        XCTAssertEqual(graph.immediateDominator(of: 4), 0)
        XCTAssertEqual(graph.immediateDominator(of: 6), 0)
        XCTAssertEqual(graph.immediatePostDominator(of: 0), 6)
        XCTAssertEqual(graph.immediatePostDominator(of: 2), 6)
    }

    func testIdentifiesIfRegion() {
        let analyzer = StructuredControlFlowAnalyzer(
            graph: graph([
                0: instruction(fjp, params: [4]),
                2: instruction(),
                3: instruction(),
                4: instruction(rnp),
            ])
        )

        XCTAssertEqual(
            analyzer.conditionalRegion(at: 0),
            StructuredControlFlowRegion(
                kind: .ifThen,
                conditionBlock: 0,
                thenBlocks: [2],
                elseBlocks: [],
                continuationBlock: 4
            )
        )
    }

    func testIdentifiesIfElseRegion() {
        let analyzer = StructuredControlFlowAnalyzer(
            graph: graph([
                0: instruction(fjp, params: [4]),
                2: instruction(ujp, params: [6]),
                4: instruction(),
                5: instruction(ujp, params: [6]),
                6: instruction(rnp),
            ])
        )

        XCTAssertEqual(
            analyzer.conditionalRegion(at: 0),
            StructuredControlFlowRegion(
                kind: .ifThenElse,
                conditionBlock: 0,
                thenBlocks: [2],
                elseBlocks: [4],
                continuationBlock: 6
            )
        )
    }

    func testIdentifiesNestedConditionalRegions() {
        let analyzer = StructuredControlFlowAnalyzer(
            graph: graph([
                0: instruction(fjp, params: [8]),
                2: instruction(fjp, params: [6]),
                4: instruction(),
                5: instruction(ujp, params: [6]),
                6: instruction(),
                7: instruction(ujp, params: [10]),
                8: instruction(),
                9: instruction(ujp, params: [10]),
                10: instruction(rnp),
            ])
        )

        let regions = analyzer.conditionalRegions()
        XCTAssertEqual(regions.count, 2)
        XCTAssertEqual(regions[0].conditionBlock, 0)
        XCTAssertEqual(regions[0].kind, .ifThenElse)
        XCTAssertEqual(regions[0].thenBlocks, [2, 4, 6])
        XCTAssertEqual(regions[0].elseBlocks, [8])
        XCTAssertEqual(regions[0].continuationBlock, 10)
        XCTAssertEqual(regions[1].conditionBlock, 2)
        XCTAssertEqual(regions[1].kind, .ifThen)
        XCTAssertEqual(regions[1].thenBlocks, [4])
        XCTAssertEqual(regions[1].continuationBlock, 6)
    }

    func testDoesNotMisidentifyWhileLoopAsIf() {
        let analyzer = StructuredControlFlowAnalyzer(
            graph: graph([
                0: instruction(fjp, params: [6]),
                2: instruction(),
                4: instruction(ujp, params: [0]),
                6: instruction(rnp),
            ])
        )

        XCTAssertNil(analyzer.conditionalRegion(at: 0))
    }

    func testRejectsSideEntryIntoConditionalArm() {
        let procedure = Procedure()
        procedure.externalEntryPoints = [2]
        procedure.instructions = [
            0: instruction(fjp, params: [4]),
            2: instruction(ujp, params: [6]),
            4: instruction(),
            5: instruction(ujp, params: [6]),
            6: instruction(rnp),
        ]
        let analyzer = StructuredControlFlowAnalyzer(procedure: procedure)

        XCTAssertNil(analyzer.conditionalRegion(at: 0))
    }

    func testIrreducibleConditionalFallsBackToUnstructuredFlow() {
        let analyzer = StructuredControlFlowAnalyzer(
            graph: graph([
                0: instruction(fjp, params: [4]),
                2: instruction(ujp, params: [6]),
                4: instruction(ujp, params: [6]),
                6: instruction(fjp, params: [2]),
                8: instruction(rnp),
            ])
        )

        XCTAssertTrue(analyzer.conditionalRegions().isEmpty)
    }
}
