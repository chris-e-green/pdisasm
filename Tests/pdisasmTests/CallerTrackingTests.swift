import XCTest
@testable import pdisasm
import Foundation

final class CallerTrackingTests: XCTestCase {

    /// Helper to build a synthetic procedure with given bytes and decode it.
    private func decodeSynthetic(bytes: [UInt8], segment: Int = 1, procedureNumber: Int = 1) -> (Procedure, Set<Call>, [ProcIdentifier]) {
        let code = Data(bytes)
        var proc = Procedure()
        var callers: Set<Call> = []
        var allLocations: Set<Location> = []
        var allProcedures: [ProcIdentifier] = []
        let seg = Segment(codeaddr: 0, codeleng: code.count, name: "TEST", segkind: .dataseg, textaddr: 0, segNum: segment, mType: 0, version: 0)
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
        return (proc, callers, allProcedures)
    }

    // MARK: - CIP caller tracking

    func testCIPInsertsIntoCaller() {
        // Build: CIP procNum=3, RNP retCount=0, then header
        // Header: dataSize(2), paramSize(2), exitSelfRef(2), enterSelfRef(2), procNum(1), lexLevel(1)
        var bytes: [UInt8] = []
        bytes += [0xAE, 0x03]   // CIP 3
        bytes += [0xAD, 0x00]   // RNP 0
        // dataSize=0x0002, parameterSize=0x0000
        bytes += [0x02, 0x00, 0x00, 0x00]
        // exit self-ref: at index 8, value points to ic 0 => word = 8
        bytes += [0x08, 0x00]
        // enter self-ref: at index 10, value points to ic 0 => word = 10
        bytes += [0x0A, 0x00]
        // procNumber=1, lexLevel=0
        bytes += [0x01, 0x00]

        let (_, callers, _) = decodeSynthetic(bytes: bytes)
        // Should have one caller entry: proc 1 calling proc 3
        XCTAssertEqual(callers.count, 1)
        if let call = callers.first {
            XCTAssertEqual(call.target.procedure, 3)
            XCTAssertEqual(call.origin.procedure, 1)
        }
    }

    // MARK: - CXP caller tracking

    func testCXPInsertsExternalCaller() {
        // Build: CXP seg=2 proc=5, RNP 0, then header
        var bytes: [UInt8] = []
        bytes += [0xCD, 0x02, 0x05]  // CXP seg=2, proc=5
        bytes += [0xAD, 0x00]        // RNP 0
        bytes += [0x02, 0x00, 0x00, 0x00]
        // exit self-ref at index 9 -> word = 9 => exitIC = 0
        bytes += [0x09, 0x00]
        // enter self-ref at index 11 -> word = 11 => enterIC = 0
        bytes += [0x0B, 0x00]
        bytes += [0x01, 0x00]  // procNumber=1, lexLevel=0

        let (_, callers, _) = decodeSynthetic(bytes: bytes)
        XCTAssertEqual(callers.count, 1)
        if let call = callers.first {
            XCTAssertEqual(call.target.segment, 2)
            XCTAssertEqual(call.target.procedure, 5)
        }
    }

    // MARK: - Recursive call not tracked

    func testRecursiveCIPNotTracked() {
        // Build: CIP procNum=1 (same as current), RNP 0, then header
        var bytes: [UInt8] = []
        bytes += [0xAE, 0x01]   // CIP 1 (self-call)
        bytes += [0xAD, 0x00]   // RNP 0
        bytes += [0x02, 0x00, 0x00, 0x00]
        bytes += [0x08, 0x00]
        bytes += [0x0A, 0x00]
        bytes += [0x01, 0x00]

        let (_, callers, _) = decodeSynthetic(bytes: bytes)
        // Recursive call should NOT be in callers
        XCTAssertEqual(callers.count, 0)
    }

    // MARK: - Function detection

    func testRNPWithRetCountDetectsFunction() {
        // Build: RNP retCount=1 (function), then header
        var bytes: [UInt8] = []
        bytes += [0xAD, 0x01]   // RNP with retCount=1 -> isFunction=true
        bytes += [0x02, 0x00, 0x00, 0x00]
        bytes += [0x06, 0x00]   // exit
        bytes += [0x08, 0x00]   // enter
        bytes += [0x01, 0x00]   // procNumber=1, lexLevel=0

        let (proc, _, _) = decodeSynthetic(bytes: bytes)
        XCTAssertTrue(proc.procType?.isFunction == true)
    }

    func testRNPWithZeroRetCountIsProcedure() {
        // Build: RNP retCount=0 (procedure), then header
        var bytes: [UInt8] = []
        bytes += [0xAD, 0x00]   // RNP with retCount=0 -> isFunction=false
        bytes += [0x02, 0x00, 0x00, 0x00]
        bytes += [0x06, 0x00]
        bytes += [0x08, 0x00]
        bytes += [0x01, 0x00]

        let (proc, _, _) = decodeSynthetic(bytes: bytes)
        XCTAssertFalse(proc.procType?.isFunction == true)
    }

    func testRBPWithRetCountDetectsFunction() {
        // RBP = 0xC1
        var bytes: [UInt8] = []
        bytes += [0xC1, 0x02]   // RBP with retCount=2 -> isFunction=true
        bytes += [0x02, 0x00, 0x00, 0x00]
        bytes += [0x06, 0x00]
        bytes += [0x08, 0x00]
        bytes += [0x01, 0x00]

        let (proc, _, _) = decodeSynthetic(bytes: bytes)
        XCTAssertTrue(proc.procType?.isFunction == true)
    }
}
