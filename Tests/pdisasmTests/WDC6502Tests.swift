import XCTest
@testable import pdisasm
import Foundation

final class WDC6502Tests: XCTestCase {

    // MARK: - Minimal assembler procedure

    func testDecodeMinimalAssemblerProcedure() throws {
        // Build a minimal 6502 procedure:
        // Code: RTS (0x60)
        // Relocation tables: all zero counts
        // Header: enterIC self-ref, procNumber
        var bytes: [UInt8] = []
        bytes += [0x60]          // RTS at offset 0
        // interpRelocs count = 0
        bytes += [0x00, 0x00]
        // procRelocs count = 0
        bytes += [0x00, 0x00]
        // segRelocs count = 0
        bytes += [0x00, 0x00]
        // baseRelocs count = 0
        bytes += [0x00, 0x00]
        // enterIC self-ref: at addr-2. addr will be bytes.count-2
        // We want enterIC=0, so self-ref word = position - 0 = position
        let enterSelfRefPos = bytes.count
        bytes += [UInt8(enterSelfRefPos), 0x00]
        // procNumber, lexLevel
        bytes += [0x01, 0x00]

        let code = Data(bytes)
        var proc = Procedure()
        let addr = code.count - 2 // points to procNumber byte

        try decodeAssemblerProcedure(
            segmentNumber: 1,
            procedureNumber: 1,
            proc: &proc,
            code: code,
            addr: addr
        )

        XCTAssertTrue(proc.identifier?.isAssembly == true)
        XCTAssertEqual(proc.identifier?.segment, 1)
        XCTAssertEqual(proc.identifier?.procedure, 1)
        XCTAssertEqual(proc.enterIC, 0)
        XCTAssertFalse(proc.instructions.isEmpty)
        // Should have at least the RTS instruction
        XCTAssertTrue(proc.instructions.values.contains(where: { $0.mnemonic.contains("RTS") }))
    }

    // MARK: - Branch destination calculation

    func testBranchForwardDestination() throws {
        // BNE (0xD0) with forward offset 0x02
        // At instructionPointer=0: BNE +2 -> dest = instructionPointer + 2 + offset = 0 + 2 + 2 = 4
        var bytes: [UInt8] = []
        bytes += [0xD0, 0x02]   // BNE +2
        bytes += [0xEA]         // NOP (filler at offset 2)
        bytes += [0xEA]         // NOP (filler at offset 3)
        bytes += [0x60]         // RTS at offset 4
        // Relocation tables (all zero)
        bytes += [0x00, 0x00]   // interp
        bytes += [0x00, 0x00]   // proc
        bytes += [0x00, 0x00]   // seg
        bytes += [0x00, 0x00]   // base
        // enterIC self-ref
        let pos = bytes.count
        bytes += [UInt8(pos), 0x00]
        bytes += [0x01, 0x00]   // procNumber, lexLevel

        let code = Data(bytes)
        var proc = Procedure()
        let addr = code.count - 2

        try decodeAssemblerProcedure(
            segmentNumber: 1,
            procedureNumber: 1,
            proc: &proc,
            code: code,
            addr: addr
        )

        // Branch destination (4) should be an entry point
        XCTAssertTrue(proc.entryPoints.contains(4))
    }

    func testBranchBackwardDestination() throws {
        // Put NOP at 0, then BNE with backward offset (0xFE = -2 -> dest = 2 + 2 + (-2) = 2, loop to self)
        var bytes: [UInt8] = []
        bytes += [0xEA]         // NOP at 0
        bytes += [0xEA]         // NOP at 1
        bytes += [0xD0, 0xFE]   // BNE -2 -> dest = 2 + 2 + (-2) = 2 (back to itself)
        bytes += [0x60]         // RTS at 4
        // Relocation tables
        bytes += [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        let pos = bytes.count
        bytes += [UInt8(pos), 0x00]
        bytes += [0x01, 0x00]

        let code = Data(bytes)
        var proc = Procedure()
        let addr = code.count - 2

        try decodeAssemblerProcedure(
            segmentNumber: 1,
            procedureNumber: 1,
            proc: &proc,
            code: code,
            addr: addr
        )

        // Backward branch should create an entry point at offset 2
        XCTAssertTrue(proc.entryPoints.contains(2))
    }

    // MARK: - Opcode table coverage

    func testOpcodeTableContainsCommonInstructions() {
        XCTAssertNotNil(wdc6502[0x60]) // RTS
        XCTAssertNotNil(wdc6502[0xA9]) // LDA imm
        XCTAssertNotNil(wdc6502[0x20]) // JSR
        XCTAssertNotNil(wdc6502[0x4C]) // JMP
        XCTAssertNotNil(wdc6502[0xEA]) // NOP
        XCTAssertNotNil(wdc6502[0x00]) // BRK
    }

    func testOpcodeMnemonics() {
        XCTAssertEqual(wdc6502[0x60]?.mnemonic, "RTS")
        XCTAssertEqual(wdc6502[0xEA]?.mnemonic, "NOP")
        XCTAssertEqual(wdc6502[0x00]?.mnemonic, "BRK")
        XCTAssertEqual(wdc6502[0x18]?.mnemonic, "CLC")
        XCTAssertEqual(wdc6502[0x38]?.mnemonic, "SEC")
    }

    func testOpcodeParamLengths() {
        XCTAssertEqual(wdc6502[0x60]?.paramLength, 0) // RTS: implied
        XCTAssertEqual(wdc6502[0xA9]?.paramLength, 1) // LDA #imm
        XCTAssertEqual(wdc6502[0x20]?.paramLength, 2) // JSR abs
    }
}
