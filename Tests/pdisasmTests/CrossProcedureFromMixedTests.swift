import XCTest
@testable import pdisasm

final class CrossProcedureFromMixedTests: XCTestCase {
    
    /// Test that calls from any procedure (including Pascal) to assembler procedures
    /// mark entry points in the target assembler procedure.
    func testCallsFromAnyProcedureMarkEntryPoints() {
        // Simulate a scenario where:
        // - procA is any type of procedure at 0x0000-0x0100
        // - procB is an assembler procedure at 0x0100-0x0200
        // - procA has instructions with JSR at address 0x0050 calling 0x0150 in procB
        
        let procA = Procedure()
        procA.identifier = ProcedureIdentifier(
            isFunction: false,
            isAssembly: false,  // This could be Pascal or mixed
            segment: 1,
            procedure: 1,
            procName: "MIXED_PROC"
        )
        procA.segmentStartAddress = 0x0000
        procA.segmentEndAddress = 0x0100
        
        let jsrInstruction = Instruction(
            opcode: 0x20,  // JSR
            mnemonic: "20 5001 JSR $0150",
            params: [0x0150],
            isPascal: false,  // This is inline assembly or mixed code
            stackState: []
        )
        procA.instructions[0x0050] = jsrInstruction
        
        let procB = Procedure()
        procB.identifier = ProcedureIdentifier(
            isFunction: false,
            isAssembly: true,
            segment: 1,
            procedure: 2,
            procName: "ASSEMBLER_PROC"
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
        
        // The target address should be marked as an entry point
        XCTAssertTrue(procB.entryPoints.contains(0x0150),
                      "Address 0x0150 should be marked as entry point even when called from non-assembler procedure")
        
        // The caller should be recorded
        XCTAssertEqual(allCallers.count, 1,
                       "Should have recorded the cross-procedure call")
    }
}
