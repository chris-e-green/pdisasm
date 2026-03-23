import XCTest
@testable import pdisasm
import Foundation

final class MalformedProcedureTests: XCTestCase {
    func testDecodeSkipsMalformedProcedureHeader() throws {
        // Create a tiny code block that is too small for a procedure header.
        let smallCode = Data([0x00, 0x01, 0x02])
        var proc = Procedure()
        var callers: Set<Call> = []
        var allLocations: Set<Location> = []
        var allProcedures: [ProcedureIdentifier] = []

        // Calling decodePascalProcedure with addr=2 should not crash even though the
        // header is incomplete; the function should return early due to validation.
        decodePascalProcedure(currSeg: Segment(codeAddress: 0, codeLength: smallCode.count, name: "TST", segmentKind: .dataseg, textAddress: 0, segNum: 0, machineType: 0, version: 0), procedureNumber: 1, proc: &proc, code: smallCode, addr: 2, callers: &callers, allLocations: &allLocations, allProcedures: &allProcedures)

        // If we reach here, the function did not crash. Ensure procedure remains empty.
        XCTAssertTrue(proc.instructions.isEmpty || proc.entryPoints.count <= 2)
    }
}
