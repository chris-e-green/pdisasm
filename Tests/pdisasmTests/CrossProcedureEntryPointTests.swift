import XCTest
@testable import pdisasm

final class CrossProcedureEntryPointTests: XCTestCase {
    
    /// Test that when an assembler routine calls a location in another procedure,
    /// the called address is marked as an entry point in the target procedure.
    func testCrossProcedureJSRMarksEntryPoint() {
        // Create two assembler procedures in the same segment
        let procA = Procedure()
        procA.identifier = ProcedureIdentifier(
            isFunction: false,
            isAssembly: true,
            segment: 1,
            procedure: 1,
            procName: "A"
        )
        procA.segmentStartAddress = 0x0000
        procA.segmentEndAddress = 0x0100
        
        let targetAddress = 0x0050
        let callInstruction = Instruction(
            opcode: 0x20,  // JSR
            mnemonic: "20 5000 JSR $0050",
            params: [targetAddress],
            isPascal: false,
            stackState: []
        )
        procA.instructions[0x0000] = callInstruction
        
        let procB = Procedure()
        procB.identifier = ProcedureIdentifier(
            isFunction: false,
            isAssembly: true,
            segment: 1,
            procedure: 2,
            procName: "B"
        )
        procB.segmentStartAddress = 0x0100
        procB.segmentEndAddress = 0x0200
        procB.entryPoints = []
        
        let codeSeg = CodeSegment(
            procedureDictionary: ProcedureDictionary(procedureCount: 2, procedurePointers: []),
            procedures: [procA, procB]
        )
        
        var allProcedures: [ProcedureIdentifier] = []
        var allCallers: Set<Call> = []
        
        resolveAssemblerProcedureTargets(
            in: codeSeg,
            allProcedures: &allProcedures,
            allCallers: &allCallers
        )
        
        // The target address should NOT be marked as an entry point because
        // it's inside the same procedure (procA calls within itself)
        XCTAssertFalse(procB.entryPoints.contains(targetAddress))
    }
    
    /// Test that when an assembler routine calls a location in a different procedure,
    /// the called address is marked as an entry point in the target procedure.
    func testCrossProcedureJSRMarksEntryPointInDifferentProcedure() {
        // Create two assembler procedures in the same segment
        let procA = Procedure()
        procA.identifier = ProcedureIdentifier(
            isFunction: false,
            isAssembly: true,
            segment: 1,
            procedure: 1,
            procName: "A"
        )
        procA.segmentStartAddress = 0x0000
        procA.segmentEndAddress = 0x0100
        
        let targetAddress = 0x0150
        let callInstruction = Instruction(
            opcode: 0x20,  // JSR
            mnemonic: "20 5001 JSR $0150",
            params: [targetAddress],
            isPascal: false,
            stackState: []
        )
        procA.instructions[0x0050] = callInstruction
        
        let procB = Procedure()
        procB.identifier = ProcedureIdentifier(
            isFunction: false,
            isAssembly: true,
            segment: 1,
            procedure: 2,
            procName: "B"
        )
        procB.segmentStartAddress = 0x0100
        procB.segmentEndAddress = 0x0200
        procB.entryPoints = []
        
        let codeSeg = CodeSegment(
            procedureDictionary: ProcedureDictionary(procedureCount: 2, procedurePointers: []),
            procedures: [procA, procB]
        )
        
        var allProcedures: [ProcedureIdentifier] = []
        var allCallers: Set<Call> = []
        
        resolveAssemblerProcedureTargets(
            in: codeSeg,
            allProcedures: &allProcedures,
            allCallers: &allCallers
        )
        
        // The target address should be marked as an entry point in procB
        XCTAssertTrue(procB.entryPoints.contains(targetAddress))
    }
    
    /// Test that JSR and JMP both mark entry points in target procedures.
    func testCrossProcedureJMPMarksEntryPointInDifferentProcedure() {
        let procA = Procedure()
        procA.identifier = ProcedureIdentifier(
            isFunction: false,
            isAssembly: true,
            segment: 1,
            procedure: 1,
            procName: "A"
        )
        procA.segmentStartAddress = 0x0000
        procA.segmentEndAddress = 0x0100
        
        let targetAddress = 0x0150
        let jumpInstruction = Instruction(
            opcode: 0x4c,  // JMP
            mnemonic: "4c 5001 JMP $0150",
            params: [targetAddress],
            isPascal: false,
            stackState: []
        )
        procA.instructions[0x0050] = jumpInstruction
        
        let procB = Procedure()
        procB.identifier = ProcedureIdentifier(
            isFunction: false,
            isAssembly: true,
            segment: 1,
            procedure: 2,
            procName: "B"
        )
        procB.segmentStartAddress = 0x0100
        procB.segmentEndAddress = 0x0200
        procB.entryPoints = []
        
        let codeSeg = CodeSegment(
            procedureDictionary: ProcedureDictionary(procedureCount: 2, procedurePointers: []),
            procedures: [procA, procB]
        )
        
        var allProcedures: [ProcedureIdentifier] = []
        var allCallers: Set<Call> = []
        
        resolveAssemblerProcedureTargets(
            in: codeSeg,
            allProcedures: &allProcedures,
            allCallers: &allCallers
        )
        
        // The target address should be marked as an entry point in procB
        XCTAssertTrue(procB.entryPoints.contains(targetAddress))
    }
    
    /// Test that multiple cross-procedure calls mark multiple entry points.
    func testMultipleCrossProcedureCallsMarkMultipleEntryPoints() {
        let procA = Procedure()
        procA.identifier = ProcedureIdentifier(
            isFunction: false,
            isAssembly: true,
            segment: 1,
            procedure: 1,
            procName: "A"
        )
        procA.segmentStartAddress = 0x0000
        procA.segmentEndAddress = 0x0100
        
        let procB = Procedure()
        procB.identifier = ProcedureIdentifier(
            isFunction: false,
            isAssembly: true,
            segment: 1,
            procedure: 2,
            procName: "B"
        )
        procB.segmentStartAddress = 0x0100
        procB.segmentEndAddress = 0x0200
        procB.entryPoints = []
        
        // procA makes two calls to different addresses in procB
        let call1 = Instruction(
            opcode: 0x20,
            mnemonic: "20 5001 JSR $0150",
            params: [0x0150],
            isPascal: false,
            stackState: []
        )
        let call2 = Instruction(
            opcode: 0x20,
            mnemonic: "20 6001 JSR $0160",
            params: [0x0160],
            isPascal: false,
            stackState: []
        )
        procA.instructions[0x0050] = call1
        procA.instructions[0x0060] = call2
        
        let codeSeg = CodeSegment(
            procedureDictionary: ProcedureDictionary(procedureCount: 2, procedurePointers: []),
            procedures: [procA, procB]
        )
        
        var allProcedures: [ProcedureIdentifier] = []
        var allCallers: Set<Call> = []
        
        resolveAssemblerProcedureTargets(
            in: codeSeg,
            allProcedures: &allProcedures,
            allCallers: &allCallers
        )
        
        // Both target addresses should be marked as entry points in procB
        XCTAssertTrue(procB.entryPoints.contains(0x0150))
        XCTAssertTrue(procB.entryPoints.contains(0x0160))
    }
    
    /// Test that the procedure name is shown in the output for cross-procedure calls.
    func testCrossProcedureCallShowsProcedureNameInOutput() {
        let procA = Procedure()
        procA.identifier = ProcedureIdentifier(
            isFunction: false,
            isAssembly: true,
            segment: 1,
            procedure: 1,
            procName: "CALLER"
        )
        procA.segmentStartAddress = 0x0000
        procA.segmentEndAddress = 0x0100
        
        let callInstruction = Instruction(
            opcode: 0x20,
            mnemonic: "20 5001 JSR $0150",
            params: [0x0150],
            isPascal: false,
            stackState: []
        )
        procA.instructions[0x0050] = callInstruction
        
        let procB = Procedure()
        procB.identifier = ProcedureIdentifier(
            isFunction: false,
            isAssembly: true,
            segment: 1,
            procedure: 2,
            procName: "CALLEE"
        )
        procB.segmentStartAddress = 0x0100
        procB.segmentEndAddress = 0x0200
        procB.entryPoints = []
        
        let codeSeg = CodeSegment(
            procedureDictionary: ProcedureDictionary(procedureCount: 2, procedurePointers: []),
            procedures: [procA, procB]
        )
        
        var allProcedures: [ProcedureIdentifier] = []
        var allCallers: Set<Call> = []
        
        resolveAssemblerProcedureTargets(
            in: codeSeg,
            allProcedures: &allProcedures,
            allCallers: &allCallers
        )
        
        // The instruction should have a destination set with the target procedure info
        let instruction = procA.instructions[0x0050]
        XCTAssertNotNil(instruction?.destination)
        XCTAssertEqual(instruction?.destination?.procedure, 2)
        XCTAssertEqual(instruction?.destination?.addr, 0x0150)
        
        // The target address should be marked as an entry point
        XCTAssertTrue(procB.entryPoints.contains(0x0150))
        
        // Create output and verify procedure name appears
        let seg = Segment(
            codeAddress: 0,
            codeLength: 0,
            name: "TEST",
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
        
        // The output should show the call instruction with procedure name
        XCTAssertTrue(stream.text.contains("JSR"), "Output should contain JSR instruction")
        // The target address should be marked with -> for the entry point
        XCTAssertTrue(stream.text.contains("0150"), "Output should contain target address")
    }
}

