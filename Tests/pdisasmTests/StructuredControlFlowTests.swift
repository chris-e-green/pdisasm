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

    func testIdentifiesWhileLoopAndItsControlTransfers() {
        let analyzer = StructuredControlFlowAnalyzer(
            graph: graph([
                0: instruction(fjp, params: [8]),
                2: instruction(fjp, params: [6]),
                4: instruction(ujp, params: [0]),
                6: instruction(ujp, params: [0]),
                8: instruction(rnp),
            ])
        )

        let loop = try? XCTUnwrap(analyzer.loopRegions().first)
        XCTAssertEqual(loop?.kind, .whileLoop)
        XCTAssertEqual(loop?.headerBlock, 0)
        XCTAssertEqual(loop?.conditionBlock, 0)
        XCTAssertEqual(loop?.bodyBlocks, [2, 4, 6])
        XCTAssertEqual(loop?.continuationBlock, 8)
        XCTAssertEqual(loop?.backEdges.count, 2)
        XCTAssertEqual(loop?.continueEdges.count, 2)
        XCTAssertEqual(loop?.exitEdges.count, 1)
    }

    func testIdentifiesRepeatUntilLoop() {
        let analyzer = StructuredControlFlowAnalyzer(
            graph: graph([
                0: instruction(),
                1: instruction(ujp, params: [4]),
                4: instruction(fjp, params: [0]),
                6: instruction(rnp),
            ])
        )

        let loop = try? XCTUnwrap(analyzer.loopRegions().first)
        XCTAssertEqual(loop?.kind, .repeatUntilLoop)
        XCTAssertEqual(loop?.headerBlock, 0)
        XCTAssertEqual(loop?.conditionBlock, 4)
        XCTAssertEqual(loop?.bodyBlocks, [0])
        XCTAssertEqual(loop?.continuationBlock, 6)
        XCTAssertEqual(loop?.continueEdges.count, 1)
        XCTAssertEqual(loop?.exitEdges.count, 1)
    }

    func testWhileLoopRecordsAdditionalExitEdges() {
        let analyzer = StructuredControlFlowAnalyzer(
            graph: graph([
                0: instruction(fjp, params: [10]),
                2: instruction(fjp, params: [8]),
                4: instruction(ujp, params: [0]),
                8: instruction(ujp, params: [12]),
                10: instruction(ujp, params: [12]),
                12: instruction(rnp),
            ])
        )

        let loop = try? XCTUnwrap(analyzer.loopRegions().first)
        XCTAssertEqual(loop?.kind, .whileLoop)
        XCTAssertEqual(loop?.bodyBlocks, [2, 4])
        XCTAssertEqual(loop?.exitEdges.count, 2)
        XCTAssertTrue(
            loop?.exitEdges.contains(
                ControlFlowEdge(
                    source: 2,
                    destination: 8,
                    kind: .conditionalBranch
                )
            ) == true
        )
    }

    func testLoopContainingConditionalRecoversBothRegions() {
        let analyzer = StructuredControlFlowAnalyzer(
            graph: graph([
                0: instruction(fjp, params: [10]),
                2: instruction(fjp, params: [6]),
                4: instruction(),
                5: instruction(ujp, params: [8]),
                6: instruction(),
                8: instruction(ujp, params: [0]),
                10: instruction(rnp),
            ])
        )

        XCTAssertEqual(analyzer.loopRegions().map(\.kind), [.whileLoop])
        XCTAssertEqual(analyzer.conditionalRegions().map(\.conditionBlock), [2])
    }

    func testConditionalContainingLoopRecoversBothRegions() {
        let analyzer = StructuredControlFlowAnalyzer(
            graph: graph([
                0: instruction(fjp, params: [10]),
                2: instruction(fjp, params: [8]),
                4: instruction(),
                6: instruction(ujp, params: [2]),
                8: instruction(ujp, params: [12]),
                10: instruction(),
                11: instruction(ujp, params: [12]),
                12: instruction(rnp),
            ])
        )

        XCTAssertEqual(analyzer.loopRegions().map(\.headerBlock), [2])
        let conditional = analyzer.conditionalRegion(at: 0)
        XCTAssertEqual(conditional?.kind, .ifThenElse)
        XCTAssertEqual(conditional?.thenBlocks, [2, 4, 8])
        XCTAssertEqual(conditional?.elseBlocks, [10])
    }

    func testRejectsIrreducibleLoopWithSideEntry() {
        let procedure = Procedure()
        procedure.externalEntryPoints = [4]
        procedure.instructions = [
            0: instruction(fjp, params: [8]),
            2: instruction(),
            4: instruction(ujp, params: [0]),
            8: instruction(rnp),
        ]

        XCTAssertTrue(
            StructuredControlFlowAnalyzer(procedure: procedure)
                .loopRegions().isEmpty
        )
    }

    func testIdentifiesCaseRegionAndGroupsSharedCaseTargets() {
        let analyzer = StructuredControlFlowAnalyzer(
            graph: graph([
                0: instruction(ujp, params: [10]),
                2: instruction(),
                3: instruction(ujp, params: [14]),
                4: instruction(),
                5: instruction(ujp, params: [14]),
                6: instruction(),
                7: instruction(ujp, params: [14]),
                10: instruction(
                    xjp,
                    params: [1, 3, 100, 6, 2, 4, 4]
                ),
                14: instruction(rnp),
            ])
        )

        let region = analyzer.caseRegion(at: 10)
        XCTAssertEqual(region?.continuationBlock, 14)
        XCTAssertEqual(region?.defaultEntryBlock, 6)
        XCTAssertEqual(region?.defaultBlocks, [6])
        XCTAssertEqual(region?.arms.count, 2)
        XCTAssertEqual(region?.arms[0].values, [1])
        XCTAssertEqual(region?.arms[0].entryBlock, 2)
        XCTAssertEqual(region?.arms[0].blocks, [2])
        XCTAssertEqual(region?.arms[1].values, [2, 3])
        XCTAssertEqual(region?.arms[1].entryBlock, 4)
        XCTAssertEqual(region?.arms[1].blocks, [4])
    }

    func testCaseRegionSupportsNoOpDefaultArm() {
        let analyzer = StructuredControlFlowAnalyzer(
            graph: graph([
                0: instruction(ujp, params: [6]),
                2: instruction(),
                3: instruction(ujp, params: [10]),
                6: instruction(
                    xjp,
                    params: [5, 5, 100, 10, 2]
                ),
                10: instruction(rnp),
            ])
        )

        let region = analyzer.caseRegion(at: 6)
        XCTAssertEqual(region?.arms.count, 1)
        XCTAssertEqual(region?.defaultEntryBlock, 10)
        XCTAssertEqual(region?.defaultBlocks, [])
        XCTAssertEqual(region?.continuationBlock, 10)
    }

    func testCaseRegionRejectsExternalArmEntry() {
        let procedure = Procedure()
        procedure.externalEntryPoints = [2]
        procedure.instructions = [
            0: instruction(ujp, params: [6]),
            2: instruction(),
            3: instruction(ujp, params: [10]),
            4: instruction(),
            5: instruction(ujp, params: [10]),
            6: instruction(
                xjp,
                params: [1, 1, 100, 4, 2]
            ),
            10: instruction(rnp),
        ]

        XCTAssertNil(
            StructuredControlFlowAnalyzer(procedure: procedure)
                .caseRegion(at: 6)
        )
    }

    func testCaseRegionsFindsOnlyDispatchBlocks() {
        let analyzer = StructuredControlFlowAnalyzer(
            graph: graph([
                0: instruction(ujp, params: [6]),
                2: instruction(),
                3: instruction(ujp, params: [10]),
                6: instruction(
                    xjp,
                    params: [1, 1, 100, 10, 2]
                ),
                10: instruction(rnp),
            ])
        )

        XCTAssertEqual(analyzer.caseRegions().map(\.dispatchBlock), [6])
    }
}
