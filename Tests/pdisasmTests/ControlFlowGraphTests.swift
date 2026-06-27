import XCTest
@testable import pdisasm

final class ControlFlowGraphTests: XCTestCase {
    private func instruction(
        _ opcode: UInt8 = nop,
        params: [Int] = [],
        destination: Location? = nil
    ) -> Instruction {
        Instruction(
            opcode: opcode,
            mnemonic: "",
            params: params,
            destination: destination
        )
    }

    private func procedure(
        enterIC: Int = 0,
        entryPoints: Set<Int> = [],
        instructions: [Int: Instruction]
    ) -> Procedure {
        let procedure = Procedure()
        procedure.enterIC = enterIC
        procedure.externalEntryPoints = entryPoints
        procedure.instructions = instructions
        return procedure
    }

    func testStraightLineProcedureFormsOneBlock() {
        let graph = ControlFlowGraph(
            procedure: procedure(
                instructions: [
                    0: instruction(),
                    1: instruction(),
                    2: instruction(rnp),
                ]
            )
        )

        XCTAssertEqual(graph.blocks.count, 1)
        XCTAssertEqual(graph.blocks[0]?.instructionAddresses, [0, 1, 2])
        XCTAssertEqual(graph.entryBlocks, [0])
        XCTAssertEqual(graph.exitBlocks, [0])
        XCTAssertTrue(
            graph.edges.contains(
                ControlFlowEdge(source: 0, destination: nil, kind: .return)
            )
        )
    }

    func testConditionalBranchSplitsBlocksAndComputesDominators() {
        let graph = ControlFlowGraph(
            procedure: procedure(
                instructions: [
                    0: instruction(fjp, params: [4]),
                    2: instruction(),
                    3: instruction(ujp, params: [5]),
                    4: instruction(),
                    5: instruction(rnp),
                ]
            )
        )

        XCTAssertEqual(Set(graph.blocks.keys), [0, 2, 4, 5])
        XCTAssertEqual(graph.successors(of: 0), [2, 4])
        XCTAssertEqual(graph.successors(of: 2), [5])
        XCTAssertEqual(graph.successors(of: 4), [5])
        XCTAssertEqual(graph.dominators[5], [0, 5])
        XCTAssertTrue(graph.postDominates(5, block: 0))
        XCTAssertFalse(graph.postDominates(2, block: 0))
    }

    func testLoopProducesBackEdge() {
        let graph = ControlFlowGraph(
            procedure: procedure(
                instructions: [
                    0: instruction(),
                    1: instruction(fjp, params: [5]),
                    3: instruction(),
                    4: instruction(ujp, params: [0]),
                    5: instruction(rnp),
                ]
            )
        )

        XCTAssertEqual(Set(graph.blocks.keys), [0, 3, 5])
        XCTAssertTrue(
            graph.edges.contains(
                ControlFlowEdge(
                    source: 3,
                    destination: 0,
                    kind: .unconditionalBranch
                )
            )
        )
        XCTAssertTrue(graph.dominates(0, block: 3))
        XCTAssertTrue(graph.postDominates(5, block: 0))
    }

    func testMultipleEntriesUseSyntheticRootSemantics() {
        let graph = ControlFlowGraph(
            procedure: procedure(
                entryPoints: [0, 3, 9],
                instructions: [
                    0: instruction(ujp, params: [4]),
                    3: instruction(),
                    4: instruction(rnp),
                ]
            )
        )

        XCTAssertEqual(graph.entryBlocks, [0, 3])
        XCTAssertEqual(graph.externalEntryBlocks, [3])
        XCTAssertEqual(graph.dominators[4], [4])
        XCTAssertTrue(graph.blocks[3]?.isExternalEntry == true)
    }

    func testIrreducibleGraphHasNoFalseSharedLoopDominator() {
        let graph = ControlFlowGraph(
            procedure: procedure(
                instructions: [
                    0: instruction(fjp, params: [4]),
                    2: instruction(ujp, params: [6]),
                    4: instruction(ujp, params: [6]),
                    6: instruction(fjp, params: [2]),
                    8: instruction(rnp),
                ]
            )
        )

        XCTAssertEqual(graph.predecessors(of: 6), [2, 4])
        XCTAssertEqual(graph.dominators[6], [0, 6])
        XCTAssertFalse(graph.dominates(2, block: 6))
        XCTAssertFalse(graph.dominates(4, block: 6))
    }

    func testCaseAndCallEdgesRetainTheirTargets() {
        let callTarget = Location(segment: 2, procedure: 7)
        let graph = ControlFlowGraph(
            procedure: procedure(
                instructions: [
                    0: instruction(cip, destination: callTarget),
                    2: instruction(
                        xjp,
                        params: [1, 3, 100, 10, 8, 8, 10]
                    ),
                    8: instruction(rnp),
                    10: instruction(rnp),
                ]
            )
        )

        XCTAssertTrue(
            graph.edges.contains(
                ControlFlowEdge(
                    source: 0,
                    destination: nil,
                    kind: .call(
                        ControlFlowCallTarget(
                            segment: 2,
                            procedure: 7,
                            address: nil
                        )
                    )
                )
            )
        )
        XCTAssertTrue(
            graph.edges.contains(
                ControlFlowEdge(
                    source: 0,
                    destination: 8,
                    kind: .caseBranch(values: [1, 2])
                )
            )
        )
        XCTAssertTrue(
            graph.edges.contains(
                ControlFlowEdge(source: 0, destination: 10, kind: .caseDefault)
            )
        )
    }

    func testStandardProcedureCallProducesCallEdge() {
        let graph = ControlFlowGraph(
            procedure: procedure(
                instructions: [
                    0: instruction(csp, params: [17]),
                    2: instruction(rnp),
                ]
            )
        )

        XCTAssertTrue(
            graph.edges.contains(
                ControlFlowEdge(
                    source: 0,
                    destination: nil,
                    kind: .call(
                        ControlFlowCallTarget(
                            segment: nil,
                            procedure: nil,
                            address: nil,
                            standardProcedure: 17
                        )
                    )
                )
            )
        )
    }
}
