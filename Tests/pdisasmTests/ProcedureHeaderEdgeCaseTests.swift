import XCTest
@testable import pdisasm
import Foundation

final class ProcedureHeaderEdgeCaseTests: XCTestCase {

    /// Helper to build and decode a procedure from raw bytes.
    private func decodeProc(bytes: [UInt8], segment: Int = 1, procedureNumber: Int = 1) -> Procedure {
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
        return proc
    }

    // MARK: - Lex level > 127 wraps to negative

    func testLexLevelGreaterThan127WrapsNegative() {
        // Build: RNP 0, header with lexLevel = 0xFF (255 -> wraps to -1)
        var bytes: [UInt8] = []
        bytes += [0xAD, 0x00]   // RNP 0
        bytes += [0x02, 0x00]   // dataSize = 2 -> >>1 = 1
        bytes += [0x00, 0x00]   // paramSize = 0
        bytes += [0x06, 0x00]   // exit self-ref (exitIC = 0)
        bytes += [0x08, 0x00]   // enter self-ref (enterIC = 0)
        bytes += [0x01, 0xFF]   // procNumber=1, lexLevel=0xFF

        let proc = decodeProc(bytes: bytes)
        XCTAssertEqual(proc.lexicalLevel, -1)
    }

    func testLexLevelExactly128WrapsToNegative128() {
        var bytes: [UInt8] = []
        bytes += [0xAD, 0x00]
        bytes += [0x02, 0x00, 0x00, 0x00]
        bytes += [0x06, 0x00]
        bytes += [0x08, 0x00]
        bytes += [0x01, 0x80]   // lexLevel=128 -> wraps to -128

        let proc = decodeProc(bytes: bytes)
        XCTAssertEqual(proc.lexicalLevel, -128)
    }

    func testLexLevel127StaysPositive() {
        var bytes: [UInt8] = []
        bytes += [0xAD, 0x00]
        bytes += [0x02, 0x00, 0x00, 0x00]
        bytes += [0x06, 0x00]
        bytes += [0x08, 0x00]
        bytes += [0x01, 0x7F]   // lexLevel=127 -> stays 127

        let proc = decodeProc(bytes: bytes)
        XCTAssertEqual(proc.lexicalLevel, 127)
    }

    // MARK: - enterIC == exitIC (single instruction)

    func testEnterICEqualsExitIC() {
        // A procedure where enter and exit both point to the same address (IC 0)
        var bytes: [UInt8] = []
        bytes += [0xAD, 0x00]   // RNP 0 at IC 0
        bytes += [0x02, 0x00]   // dataSize
        bytes += [0x00, 0x00]   // paramSize
        // exit self-ref at index 6: word=6 -> exitIC = 6-6 = 0
        bytes += [0x06, 0x00]
        // enter self-ref at index 8: word=8 -> enterIC = 8-8 = 0
        bytes += [0x08, 0x00]
        bytes += [0x01, 0x00]

        let proc = decodeProc(bytes: bytes)
        XCTAssertEqual(proc.enterIC, 0)
        XCTAssertEqual(proc.exitIC, 0)
        XCTAssertEqual(proc.enterIC, proc.exitIC)
        // Should still decode the single RNP instruction
        XCTAssertEqual(proc.instructions.count, 1)
        XCTAssertEqual(proc.instructions[0]?.mnemonic, "RNP")
    }

    // MARK: - Negative addr rejected

    func testNegativeAddrEarlyReturn() {
        let code = Data([0xAD, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00])
        var proc = Procedure()
        var callers: Set<Call> = []
        var allLocations: Set<Location> = []
        var allProcedures: [ProcedureIdentifier] = []
        let seg = Segment(codeAddress: 0, codeLength: code.count, name: "T", segmentKind: .dataseg, textAddress: 0, segNum: 0, machineType: 0, version: 0)

        decodePascalProcedure(
            currSeg: seg,
            procedureNumber: 1,
            proc: &proc,
            code: code,
            addr: -1,
            callers: &callers,
            allLocations: &allLocations,
            allProcedures: &allProcedures
        )

        // Should return early, no instructions decoded
        XCTAssertTrue(proc.instructions.isEmpty)
    }

    // MARK: - Procedure with parameters detected from header

    func testParameterSizeDetected() {
        var bytes: [UInt8] = []
        bytes += [0xAD, 0x00]        // RNP 0
        bytes += [0x02, 0x00]        // dataSize = 2 -> >>1 = 1
        bytes += [0x06, 0x00]        // paramSize = 6 -> >>1 = 3
        bytes += [0x06, 0x00]        // exit
        bytes += [0x08, 0x00]        // enter
        bytes += [0x01, 0x02]        // procNumber=1, lexLevel=2

        let proc = decodeProc(bytes: bytes)
        XCTAssertEqual(proc.parameterSize, 3)
        XCTAssertEqual(proc.dataSize, 1)
        XCTAssertEqual(proc.lexicalLevel, 2)
    }
}
