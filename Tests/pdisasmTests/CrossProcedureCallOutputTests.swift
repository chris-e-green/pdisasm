import XCTest
@testable import pdisasm

final class CrossProcedureCallOutputTests: XCTestCase {
    
    /// Test that demonstrates the cross-procedure call feature working end-to-end.
    /// This shows:
    /// 1. The called address is marked as an entry point (shown with -> prefix)
    /// 2. The procedure name is displayed in the output via the destination field
    func testCrossProcedureCallOutputShowsEntryPointAndProcedureName() {
        // Create a scenario with two assembler procedures
        // Procedure A (at addresses 0x0000-0x0100) calls into Procedure B (at 0x0100-0x0200)
        
        let procA = Procedure()
        procA.identifier = ProcedureIdentifier(
            isFunction: false,
            isAssembly: true,
            segment: 1,
            procedure: 1,
            procName: "PROC_A"
        )
        procA.segmentStartAddress = 0x0000
        procA.segmentEndAddress = 0x0100
        
        // JSR instruction at address 0x0050 that calls into procB at address 0x0150
        let jsrInstruction = Instruction(
            opcode: 0x20,  // JSR opcode
            mnemonic: "20 5001 JSR $0150",
            params: [0x0150],
            isPascal: false,
            stackState: []
        )
        procA.instructions[0x0050] = jsrInstruction
        
        let procB = Procedure()
        procB.identifier = ProcedureIdentifier(
            isFunction: false,
            isAssembly: true,
            segment: 1,
            procedure: 2,
            procName: "PROC_B"
        )
        procB.segmentStartAddress = 0x0100
        procB.segmentEndAddress = 0x0200
        procB.entryPoints = []  // Initially empty
        
        let codeSeg = CodeSegment(
            procedureDictionary: ProcedureDictionary(procedureCount: 2, procedurePointers: []),
            procedures: [procA, procB]
        )
        
        var allProcedures: [ProcedureIdentifier] = []
        var allCallers: Set<Call> = []
        
        // This is the key function that implements the feature
        resolveAssemblerProcedureTargets(
            in: codeSeg,
            allProcedures: &allProcedures,
            allCallers: &allCallers
        )
        
        // VERIFICATION 1: Entry point is marked in target procedure
        XCTAssertTrue(procB.entryPoints.contains(0x0150), 
                      "The called address 0x0150 should be marked as an entry point in PROC_B")
        
        // VERIFICATION 2: The calling instruction has destination info
        XCTAssertNotNil(procA.instructions[0x0050]?.destination,
                        "The JSR instruction should have destination info set")
        XCTAssertEqual(procA.instructions[0x0050]?.destination?.procedure, 2,
                       "Destination should point to procedure 2")
        XCTAssertEqual(procA.instructions[0x0050]?.destination?.addr, 0x0150,
                       "Destination should point to address 0x0150")
        
        // VERIFICATION 3: Output shows entry point and procedure name
        let seg = Segment(
            codeAddress: 0,
            codeLength: 0,
            name: "CODESEG",
            segmentKind: .dataseg,
            textAddress: 0,
            segNum: 1,
            machineType: 7,
            version: 0
        )
        let segDict = SegDictionary(segTable: [1: seg], intrinsics: [], comment: "")
        let codeSegs: [Int: CodeSegment] = [1: codeSeg]
        var stream = StringStream()
        
        outputResults(
            to: &stream,
            sourceFilename: "test.bin",
            segDictionary: segDict,
            codeSegs: codeSegs,
            dataSegs: [],
            allLocations: [],
            allProcedures: allProcedures,
            allCallers: allCallers,
            verbose: false,
            showMarkup: true,
            showPCode: true,
            showPseudoCode: false,
            showDot: false
        )
        
        // The output should contain:
        // 1. The JSR instruction
        XCTAssertTrue(stream.text.contains("JSR"), 
                      "Output should show JSR instruction")
        
        // 2. The target address with entry point marker (->)
        XCTAssertTrue(stream.text.contains("0150"),
                      "Output should show target address 0x0150")
        
        // 3. The procedure names
        XCTAssertTrue(stream.text.contains("PROC_A"),
                      "Output should show calling procedure name")
        XCTAssertTrue(stream.text.contains("PROC_B"),
                      "Output should show called procedure name")
    }
    
    /// Test demonstrating multiple entry points from different callers
    func testMultipleCallersCauseMultipleEntryPoints() {
        let procA = Procedure()
        procA.identifier = ProcedureIdentifier(
            isFunction: false,
            isAssembly: true,
            segment: 1,
            procedure: 1,
            procName: "CALLER_ONE"
        )
        procA.segmentStartAddress = 0x0000
        procA.segmentEndAddress = 0x0050
        
        // First call to address 0x0100
        let call1 = Instruction(
            opcode: 0x20,
            mnemonic: "20 0001 JSR $0100",
            params: [0x0100],
            isPascal: false,
            stackState: []
        )
        procA.instructions[0x0010] = call1
        
        let procB = Procedure()
        procB.identifier = ProcedureIdentifier(
            isFunction: false,
            isAssembly: true,
            segment: 1,
            procedure: 2,
            procName: "CALLER_TWO"
        )
        procB.segmentStartAddress = 0x0050
        procB.segmentEndAddress = 0x0100
        
        // Second call to address 0x0120
        let call2 = Instruction(
            opcode: 0x20,
            mnemonic: "20 2001 JSR $0120",
            params: [0x0120],
            isPascal: false,
            stackState: []
        )
        procB.instructions[0x0080] = call2
        
        let procC = Procedure()
        procC.identifier = ProcedureIdentifier(
            isFunction: false,
            isAssembly: true,
            segment: 1,
            procedure: 3,
            procName: "CALLEE"
        )
        procC.segmentStartAddress = 0x0100
        procC.segmentEndAddress = 0x0200
        procC.entryPoints = []
        
        let codeSeg = CodeSegment(
            procedureDictionary: ProcedureDictionary(procedureCount: 3, procedurePointers: []),
            procedures: [procA, procB, procC]
        )
        
        var allProcedures: [ProcedureIdentifier] = []
        var allCallers: Set<Call> = []
        
        resolveAssemblerProcedureTargets(
            in: codeSeg,
            allProcedures: &allProcedures,
            allCallers: &allCallers
        )
        
        // Both addresses should be marked as entry points
        XCTAssertTrue(procC.entryPoints.contains(0x0100),
                      "Address 0x0100 should be marked as entry point from CALLER_ONE")
        XCTAssertTrue(procC.entryPoints.contains(0x0120),
                      "Address 0x0120 should be marked as entry point from CALLER_TWO")
        
        // Both callers should be registered
        XCTAssertEqual(allCallers.count, 2,
                       "Should have recorded both cross-procedure calls")
    }
}
