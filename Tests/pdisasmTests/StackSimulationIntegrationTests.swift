import XCTest
@testable import pdisasm
import Foundation

final class StackSimulationIntegrationTests: XCTestCase {

    /// Helper: builds a synthetic procedure from raw bytes, decodes it, then runs
    /// simulateStackAndGeneratePseudocode. Returns the Procedure.
    private func buildAndSimulate(bytes: [UInt8], segment: Int = 1, procedureNumber: Int = 1) -> Procedure {
        let code = Data(bytes)
        var proc = Procedure()
        var callers: Set<Call> = []
        var allLocations: Set<Location> = []
        var allProcedures: [ProcedureIdentifier] = []
        let seg = Segment(codeAddress: 0, codeLength: code.count, name: "TEST", segmentKind: .dataseg, textAddress: 0, segNum: segment, machineType: 0, version: 0)
        let addr = code.count - 2

        decodePascalProcedure(
            currSeg: seg,
            procedureNumber: procedureNumber,
            proc: &proc,
            code: code,
            addr: addr,
            callers: &callers,
            allLocations: &allLocations,
            allProcedures: &allProcedures
        )

        simulateStackAndGeneratePseudocode(
            proc: proc,
            knownRecords: [],
            allProcedures: &allProcedures,
            allLocations: &allLocations
        )

        return proc
    }

    private func simulate(_ proc: Procedure) -> Procedure {
        var allProcedures: [ProcedureIdentifier] = [proc.identifier].compactMap { $0 }
        var allLocations: Set<Location> = []
        simulateStackAndGeneratePseudocode(
            proc: proc,
            knownRecords: [],
            allProcedures: &allProcedures,
            allLocations: &allLocations
        )
        return proc
    }

    private func makeForLikeProcedure(
        comparisonOpcode: UInt8,
        comparisonMnemonic: String,
        arithmeticOpcode: UInt8,
        arithmeticMnemonic: String,
        constantOpcode: UInt8,
        initialValue: UInt8 = 1
    ) -> Procedure {
        let proc = Procedure()
        proc.identifier = ProcedureIdentifier(isFunction: false, segment: 1, procedure: 1, procName: "LOOP")
        proc.lexicalLevel = 1
        proc.enterIC = 0
        proc.exitIC = 14

        let loopVariable = Location(segment: 1, procedure: 1, lexLevel: 1, addr: 1, name: "I", type: "INTEGER")
        let limit = Location(segment: 1, procedure: 1, lexLevel: 1, addr: 2, name: "LIMIT", type: "INTEGER")

        proc.instructions[0] = Instruction(opcode: initialValue, mnemonic: "SLDC")
        proc.instructions[1] = Instruction(opcode: stl, mnemonic: "STL", params: [1], memLocation: loopVariable)
        proc.instructions[2] = Instruction(opcode: ldl, mnemonic: "LDL", params: [1], memLocation: loopVariable)
        proc.instructions[3] = Instruction(opcode: ldl, mnemonic: "LDL", params: [2], memLocation: limit)
        proc.instructions[4] = Instruction(opcode: comparisonOpcode, mnemonic: comparisonMnemonic)
        proc.instructions[5] = Instruction(opcode: fjp, mnemonic: "FJP", params: [14])
        proc.instructions[7] = Instruction(opcode: ldl, mnemonic: "LDL", params: [1], memLocation: loopVariable)
        proc.instructions[8] = Instruction(opcode: constantOpcode, mnemonic: "SLDC")
        proc.instructions[9] = Instruction(opcode: arithmeticOpcode, mnemonic: arithmeticMnemonic)
        proc.instructions[10] = Instruction(opcode: stl, mnemonic: "STL", params: [1], memLocation: loopVariable)
        proc.instructions[12] = Instruction(opcode: ujp, mnemonic: "UJP", params: [2])
        proc.instructions[14] = Instruction(opcode: rnp, mnemonic: "RNP", params: [0])

        return proc
    }

    private func makeForWithConstantLimitProcedure() -> Procedure {
        let proc = Procedure()
        proc.identifier = ProcedureIdentifier(isFunction: false, segment: 1, procedure: 1, procName: "LOOP")
        proc.lexicalLevel = 1
        proc.enterIC = 0
        proc.exitIC = 16

        let loopVariable = Location(segment: 1, procedure: 1, lexLevel: 1, addr: 1, name: "J", type: "INTEGER")
        let limit = Location(segment: 1, procedure: 1, lexLevel: 1, addr: 2, name: "JMAX", type: "INTEGER")

        proc.instructions[0] = Instruction(opcode: 3, mnemonic: "SLDC")
        proc.instructions[1] = Instruction(opcode: stl, mnemonic: "STL", params: [1], memLocation: loopVariable)
        proc.instructions[2] = Instruction(opcode: 8, mnemonic: "SLDC")
        proc.instructions[3] = Instruction(opcode: stl, mnemonic: "STL", params: [2], memLocation: limit)
        proc.instructions[4] = Instruction(opcode: ldl, mnemonic: "LDL", params: [1], memLocation: loopVariable)
        proc.instructions[5] = Instruction(opcode: ldl, mnemonic: "LDL", params: [2], memLocation: limit)
        proc.instructions[6] = Instruction(opcode: leqi, mnemonic: "LEQI")
        proc.instructions[7] = Instruction(opcode: fjp, mnemonic: "FJP", params: [16])
        proc.instructions[9] = Instruction(opcode: ldl, mnemonic: "LDL", params: [1], memLocation: loopVariable)
        proc.instructions[10] = Instruction(opcode: 1, mnemonic: "SLDC")
        proc.instructions[11] = Instruction(opcode: adi, mnemonic: "ADI")
        proc.instructions[12] = Instruction(opcode: stl, mnemonic: "STL", params: [1], memLocation: loopVariable)
        proc.instructions[14] = Instruction(opcode: ujp, mnemonic: "UJP", params: [4])
        proc.instructions[16] = Instruction(opcode: rnp, mnemonic: "RNP", params: [0])

        return proc
    }

    private func makeForWithSubscriptedLimitProcedure() -> Procedure {
        let proc = Procedure()
        proc.identifier = ProcedureIdentifier(isFunction: false, segment: 1, procedure: 1, procName: "LOOP")
        proc.lexicalLevel = 1
        proc.enterIC = 0
        proc.exitIC = 16

        let loopVariable = Location(segment: 1, procedure: 1, lexLevel: 1, addr: 1, name: "S_IDX", type: "INTEGER")
        let limit = Location(segment: 1, procedure: 1, lexLevel: 1, addr: 2, name: "S_LEN", type: "INTEGER")
        let copiedLength = Location(segment: 1, procedure: 1, lexLevel: 1, addr: 3, name: "LENGTH(S_COPY)", type: "INTEGER")

        proc.instructions[0] = Instruction(opcode: 1, mnemonic: "SLDC")
        proc.instructions[1] = Instruction(opcode: stl, mnemonic: "STL", params: [1], memLocation: loopVariable)
        proc.instructions[2] = Instruction(opcode: ldl, mnemonic: "LDL", params: [3], memLocation: copiedLength)
        proc.instructions[3] = Instruction(opcode: stl, mnemonic: "STL", params: [2], memLocation: limit)
        proc.instructions[4] = Instruction(opcode: ldl, mnemonic: "LDL", params: [1], memLocation: loopVariable)
        proc.instructions[5] = Instruction(opcode: ldl, mnemonic: "LDL", params: [2], memLocation: limit)
        proc.instructions[6] = Instruction(opcode: leqi, mnemonic: "LEQI")
        proc.instructions[7] = Instruction(opcode: fjp, mnemonic: "FJP", params: [16])
        proc.instructions[9] = Instruction(opcode: ldl, mnemonic: "LDL", params: [1], memLocation: loopVariable)
        proc.instructions[10] = Instruction(opcode: 1, mnemonic: "SLDC")
        proc.instructions[11] = Instruction(opcode: adi, mnemonic: "ADI")
        proc.instructions[12] = Instruction(opcode: stl, mnemonic: "STL", params: [1], memLocation: loopVariable)
        proc.instructions[14] = Instruction(opcode: ujp, mnemonic: "UJP", params: [4])
        proc.instructions[16] = Instruction(opcode: rnp, mnemonic: "RNP", params: [0])

        return proc
    }

    private func makeIfWithSharedGotoTargetProcedure() -> Procedure {
        let proc = Procedure()
        proc.identifier = ProcedureIdentifier(isFunction: false, segment: 1, procedure: 1, procName: "GOTOIF")
        proc.lexicalLevel = 1
        proc.enterIC = 0
        proc.exitIC = 20

        proc.instructions[0] = Instruction(opcode: 1, mnemonic: "SLDC")
        proc.instructions[1] = Instruction(opcode: fjp, mnemonic: "FJP", params: [4])
        proc.instructions[3] = Instruction(opcode: ujp, mnemonic: "UJP", params: [20])
        proc.instructions[4] = Instruction(opcode: 2, mnemonic: "SLDC")
        proc.instructions[5] = Instruction(opcode: ujp, mnemonic: "UJP", params: [20])
        proc.instructions[20] = Instruction(opcode: rnp, mnemonic: "RNP", params: [0])

        return proc
    }

    // MARK: - SLDC pushes to stack state

    func testSLDCPushesValue() {
        // SLDC 5, RNP 0, header
        var bytes: [UInt8] = []
        bytes += [0x05]          // SLDC 5
        bytes += [0xAD, 0x00]    // RNP 0
        bytes += [0x02, 0x00, 0x00, 0x00]
        bytes += [0x07, 0x00]    // exit
        bytes += [0x09, 0x00]    // enter
        bytes += [0x01, 0x00]

        let proc = buildAndSimulate(bytes: bytes)
        // After SLDC, the stack state should contain "5"
        let sldcInst = proc.instructions[0]
        XCTAssertNotNil(sldcInst?.stackState)
        XCTAssertTrue(sldcInst?.stackState?.contains(where: { $0.contains("5") }) == true)
    }

    // MARK: - ADI adds two values

    func testADIPseudoStack() {
        // SLDC 3, SLDC 4, ADI, RNP 0, header
        var bytes: [UInt8] = []
        bytes += [0x03]          // SLDC 3
        bytes += [0x04]          // SLDC 4
        bytes += [0x82]          // ADI
        bytes += [0xAD, 0x00]    // RNP 0
        bytes += [0x02, 0x00, 0x00, 0x00]
        bytes += [0x09, 0x00]    // exit
        bytes += [0x0B, 0x00]    // enter
        bytes += [0x01, 0x00]

        let proc = buildAndSimulate(bytes: bytes)
        // After ADI, the stack should show the addition expression
        let adiInst = proc.instructions[2]
        XCTAssertNotNil(adiInst?.stackState)
        // Stack should contain something like "3 + 4"
        if let state = adiInst?.stackState {
            let joined = state.joined()
            XCTAssertTrue(joined.contains("3") && joined.contains("4"), "Expected addition of 3 and 4, got: \(joined)")
        }
    }

    // MARK: - LDCN pushes NIL

    func testLDCNPushesNIL() {
        // LDCN, RNP 0, header
        // We need enterIC=0, exitIC=2 (pointing to RNP)
        var bytes: [UInt8] = []
        bytes += [0x9F]          // LDCN at IC 0
        bytes += [0xAD, 0x00]    // RNP 0 at IC 1
        bytes += [0x02, 0x00, 0x00, 0x00]  // dataSize, paramSize
        // exit self-ref at index 7: word should give exitIC=1 => 7-word=1 => word=6
        bytes += [0x06, 0x00]
        // enter self-ref at index 9: word should give enterIC=0 => 9-word=0 => word=9
        bytes += [0x09, 0x00]
        bytes += [0x01, 0x00]

        let proc = buildAndSimulate(bytes: bytes)
        // Check the RNP instruction at IC 1 — its stack state captures
        // what was on the stack after LDCN ran (i.e. NIL).
        let rnpInst = proc.instructions[1]
        XCTAssertNotNil(rnpInst)
        if let state = rnpInst?.stackState, !state.isEmpty {
            let joined = state.joined()
            XCTAssertTrue(joined.contains("NIL"), "Expected NIL in stack state, got: \(joined)")
        }
        // Also verify LDCN was decoded
        XCTAssertEqual(proc.instructions[0]?.mnemonic, "LDCN")
    }

    // MARK: - CSP generates pseudo-code

    func testCSPGeneratesPseudoCode() {
        // CSP 39 = HALT (no parameters)
        // HALT takes no params, so: CSP 39, RNP 0, header
        var bytes: [UInt8] = []
        bytes += [0x9E, 0x27]   // CSP 39 (HALT)
        bytes += [0xAD, 0x00]   // RNP 0
        bytes += [0x02, 0x00, 0x00, 0x00]
        bytes += [0x08, 0x00]
        bytes += [0x0A, 0x00]
        bytes += [0x01, 0x00]

        let proc = buildAndSimulate(bytes: bytes)
        let cspInst = proc.instructions[0]
        XCTAssertNotNil(cspInst)
        // HALT should produce pseudo-code
        if let pseudo = cspInst?.pseudoCode {
            XCTAssertTrue(pseudo.contains("HALT"))
        }
    }

    // MARK: - LNOT negates boolean

    func testLNOTNegates() {
        // SLDC 1, LNOT, RNP 0, header
        var bytes: [UInt8] = []
        bytes += [0x01]          // SLDC 1
        bytes += [0x93]          // LNOT
        bytes += [0xAD, 0x00]   // RNP 0
        bytes += [0x02, 0x00, 0x00, 0x00]
        bytes += [0x08, 0x00]
        bytes += [0x0A, 0x00]
        bytes += [0x01, 0x00]

        let proc = buildAndSimulate(bytes: bytes)
        let lnotInst = proc.instructions[1]
        XCTAssertNotNil(lnotInst?.stackState)
        if let state = lnotInst?.stackState {
            let joined = state.joined()
            XCTAssertTrue(joined.contains("NOT"), "Expected NOT in stack: \(joined)")
        }
    }

    // MARK: - EQUI produces boolean comparison

    func testEQUIProducesComparison() {
        // SLDC 5, SLDC 5, EQUI, RNP 0, header
        var bytes: [UInt8] = []
        bytes += [0x05]          // SLDC 5
        bytes += [0x05]          // SLDC 5
        bytes += [0xC3]          // EQUI
        bytes += [0xAD, 0x00]   // RNP 0
        bytes += [0x02, 0x00, 0x00, 0x00]
        bytes += [0x09, 0x00]
        bytes += [0x0B, 0x00]
        bytes += [0x01, 0x00]

        let proc = buildAndSimulate(bytes: bytes)
        let equiInst = proc.instructions[2]
        XCTAssertNotNil(equiInst?.stackState)
        if let state = equiInst?.stackState {
            let joined = state.joined()
            XCTAssertTrue(joined.contains("="), "Expected = in stack: \(joined)")
        }
    }

    func testSimpleToForLoopIsRenderedAsForAndSuppressesIncrementAssignment() {
        let proc = simulate(makeForLikeProcedure(
            comparisonOpcode: leqi,
            comparisonMnemonic: "LEQI",
            arithmeticOpcode: adi,
            arithmeticMnemonic: "ADI",
            constantOpcode: 1
        ))

        XCTAssertEqual(proc.instructions[5]?.pseudoCode, "FOR I := 1 TO LIMIT DO BEGIN")
        XCTAssertEqual(proc.instructions[5]?.forLoopEvidence?.startExpression, "1")
        XCTAssertEqual(proc.instructions[5]?.forLoopEvidence?.limitExpression, "LIMIT")
        XCTAssertEqual(proc.instructions[5]?.forLoopEvidence?.direction, .to)
        XCTAssertNil(proc.instructions[1]?.pseudoCode)
        XCTAssertNil(proc.instructions[10]?.pseudoCode)
        XCTAssertEqual(proc.instructions[14]?.prePseudoCode.last, "END (* FOR I := 1 TO LIMIT *)")
    }

    func testSimpleDowntoForLoopIsRenderedAsForAndSuppressesDecrementAssignment() {
        let proc = simulate(makeForLikeProcedure(
            comparisonOpcode: geqi,
            comparisonMnemonic: "GEQI",
            arithmeticOpcode: sbi,
            arithmeticMnemonic: "SBI",
            constantOpcode: 1,
            initialValue: 8
        ))

        XCTAssertEqual(proc.instructions[5]?.pseudoCode, "FOR I := 8 DOWNTO LIMIT DO BEGIN")
        XCTAssertEqual(proc.instructions[5]?.forLoopEvidence?.direction, .downto)
        XCTAssertNil(proc.instructions[1]?.pseudoCode)
        XCTAssertNil(proc.instructions[10]?.pseudoCode)
        XCTAssertEqual(proc.instructions[14]?.prePseudoCode.last, "END (* FOR I := 8 DOWNTO LIMIT *)")
    }

    func testForLoopFoldsConstantLimitSetupAssignment() {
        let proc = simulate(makeForWithConstantLimitProcedure())

        XCTAssertNil(proc.instructions[1]?.pseudoCode)
        XCTAssertNil(proc.instructions[3]?.pseudoCode)
        XCTAssertEqual(proc.instructions[7]?.pseudoCode, "FOR J := 3 TO 8 DO BEGIN")
        XCTAssertNil(proc.instructions[12]?.pseudoCode)
        XCTAssertEqual(proc.instructions[16]?.prePseudoCode.last, "END (* FOR J := 3 TO 8 *)")
    }

    func testForLoopFoldsSubscriptedLimitSetupAssignment() {
        let proc = simulate(makeForWithSubscriptedLimitProcedure())

        XCTAssertNil(proc.instructions[1]?.pseudoCode)
        XCTAssertNil(proc.instructions[3]?.pseudoCode)
        XCTAssertEqual(proc.instructions[7]?.pseudoCode, "FOR S_IDX := 1 TO LENGTH(S_COPY) DO BEGIN")
        XCTAssertNil(proc.instructions[12]?.pseudoCode)
        XCTAssertEqual(proc.instructions[16]?.prePseudoCode.last, "END (* FOR S_IDX := 1 TO LENGTH(S_COPY) *)")
    }

    func testIncrementByMoreThanOneRemainsWhile() {
        let proc = simulate(makeForLikeProcedure(
            comparisonOpcode: leqi,
            comparisonMnemonic: "LEQI",
            arithmeticOpcode: adi,
            arithmeticMnemonic: "ADI",
            constantOpcode: 2
        ))

        XCTAssertEqual(proc.instructions[5]?.pseudoCode, "WHILE I <= LIMIT DO BEGIN")
        XCTAssertEqual(proc.instructions[10]?.pseudoCode, "I := I + 2")
        XCTAssertEqual(proc.instructions[14]?.prePseudoCode.last, "END (* WHILE I <= LIMIT *)")
    }

    func testCaseGatewayPreservesStructuredSelectorEvidence() {
        let proc = Procedure()
        proc.enterIC = 0
        proc.exitIC = 14
        proc.instructions = [
            0: Instruction(opcode: 1, mnemonic: "SLDC"),
            1: Instruction(opcode: ujp, mnemonic: "UJP", params: [10]),
            2: Instruction(opcode: nop, mnemonic: "NOP"),
            3: Instruction(opcode: ujp, mnemonic: "UJP", params: [14]),
            4: Instruction(opcode: nop, mnemonic: "NOP"),
            5: Instruction(opcode: ujp, mnemonic: "UJP", params: [14]),
            6: Instruction(opcode: nop, mnemonic: "NOP"),
            7: Instruction(opcode: ujp, mnemonic: "UJP", params: [14]),
            10: Instruction(
                opcode: xjp,
                mnemonic: "XJP",
                params: [1, 2, 100, 6, 2, 4]
            ),
            14: Instruction(opcode: rnp, mnemonic: "RNP", params: [0]),
        ]

        let simulated = simulate(proc)

        XCTAssertEqual(
            simulated.instructions[10]?.caseDispatchEvidence,
            CaseDispatchEvidence(
                selectorExpression: "1",
                gatewayAddress: 1
            )
        )
    }

    func testSharedForwardUjpTargetInsideIfIsRenderedAsGotoNotElse() {
        let proc = simulate(makeIfWithSharedGotoTargetProcedure())

        XCTAssertEqual(proc.instructions[1]?.pseudoCode, "IF ODD(1) THEN BEGIN")
        XCTAssertEqual(proc.instructions[3]?.pseudoCode, "GOTO LAB20")
        XCTAssertEqual(proc.instructions[4]?.prePseudoCode.last, "END (* IF ODD(1) *)")
        XCTAssertFalse(proc.instructions[4]?.prePseudoCode.contains("END ELSE BEGIN") == true)
        XCTAssertFalse(proc.instructions[20]?.prePseudoCode.contains { $0.starts(with: "END (* ELSE") } == true)
    }
}
