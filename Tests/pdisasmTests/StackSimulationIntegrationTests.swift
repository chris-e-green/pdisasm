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
            allProcedures: &allProcedures,
            allLocations: &allLocations
        )

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
}
