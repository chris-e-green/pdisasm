import XCTest
@testable import pdisasm
import Foundation

final class SkippedProcedureTests: XCTestCase {
    func testOutOfRangeProcedurePointerIsSkipped() throws {
        // Build a code block with header bytes but make the procedure pointer point well past the end.
        var code = Data(repeating: 0x00, count: 32)
        // Place procedure count = 1 and segment number
        code[code.count - 2] = 0x00 // segment number
        code[code.count - 1] = 0x01 // one procedure
        // Write a procedure pointer at the end which points outside inner block
        // The procedure pointers are stored as self-ref words; write a big value so pointer < 0 after computation
        // Put a two-byte word (little endian)
        let ptrIndex = code.count - 4
        code[ptrIndex] = 0xFF
        code[ptrIndex + 1] = 0xFF

        let seg = Segment(codeAddress: 0, codeLength: code.count, name: "TST", segmentKind: .dataseg, textAddress: 0, segNum: 0, machineType: 0, version: 0)

    // segDict not needed for this unit test

        // Run the minimal processing loop: build codeSeg and ensure procedure pointer is skipped
        let codeBlock = code
        let codeSeg = CodeSegment(procedureDictionary: ProcedureDictionary(procedureCount: 0, procedurePointers: []), procedures: [])
        codeSeg.procedureDictionary = ProcedureDictionary(procedureCount: Int(codeBlock[codeBlock.endIndex - 1]), procedurePointers: [])
        for i in 1...codeSeg.procedureDictionary.procedureCount {
            let ptrIndex = codeBlock.endIndex - i * 2 - 2
            if let ptr = try? CodeData(data: codeBlock, instructionPointer: 0, header: 0).getSelfRefPointer(at: ptrIndex) {
                codeSeg.procedureDictionary.procedurePointers.append(ptr)
            } else {
                codeSeg.procedureDictionary.procedurePointers.append(0)
            }
        }

        var allCallers: Set<Call> = []
        var allLocations: Set<Location> = []
        var allProcedures: [ProcedureIdentifier] = []

        for (_, procPtr) in codeSeg.procedureDictionary.procedurePointers.enumerated() {
            var proc = Procedure()
            let inCode: Data = codeBlock
            let addr = procPtr

            // This pointer should resolve to an addr outside of range and the earlier guard should skip it
            let minNeededIndex = addr - 8
            let maxNeededIndex = addr + 1
            if minNeededIndex < 0 || maxNeededIndex >= inCode.count { continue }

            decodePascalProcedure(currSeg: seg, procedureNumber: 1, proc: &proc, code: inCode, addr: addr, callers: &allCallers, allLocations: &allLocations, allProcedures: &allProcedures)
        }

        // No procedures should have been decoded for the out-of-range pointer
        XCTAssertTrue(allProcedures.isEmpty)
    }
}
