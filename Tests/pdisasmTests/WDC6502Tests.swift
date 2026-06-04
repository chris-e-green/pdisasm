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
        var assemblerEntryPoints: Set<Int> = []
        let addr = code.count - 2 // points to procNumber byte

        try decodeAssemblerProcedure(
            segmentNumber: 1,
            procedureNumber: 1,
            proc: &proc,
            code: code,
            addr: addr,
            assemblerEntryPoints: &assemblerEntryPoints
        )

        XCTAssertTrue(proc.identifier?.isAssembly == true)
        XCTAssertEqual(proc.identifier?.segment, 1)
        XCTAssertEqual(proc.identifier?.procedure, 1)
        XCTAssertEqual(proc.enterIC, 0)
        XCTAssertFalse(proc.instructions.isEmpty)
        // Should have at least the RTS instruction
        XCTAssertTrue(proc.instructions.values.contains(where: { $0.mnemonic.contains("RTS") }))
    }

    func testDecodedJSRStoresResolvedTargetInParams() throws {
        var bytes: [UInt8] = []
        bytes += [0x20, 0x87, 0x0B]  // JSR $0b87
        bytes += [0x60]              // RTS
        bytes += [0x00, 0x00]        // interp
        bytes += [0x00, 0x00]        // proc
        bytes += [0x00, 0x00]        // seg
        bytes += [0x00, 0x00]        // base
        let enterSelfRefPos = bytes.count
        bytes += [UInt8(enterSelfRefPos), 0x00]  // enterIC = 0
        bytes += [0x01, 0x00]

        let code = Data(bytes)
        var proc = Procedure()
        var assemblerEntryPoints: Set<Int> = []
        let addr = code.count - 2

        try decodeAssemblerProcedure(
            segmentNumber: 1,
            procedureNumber: 1,
            proc: &proc,
            code: code,
            addr: addr,
            assemblerEntryPoints: &assemblerEntryPoints
        )

        XCTAssertEqual(proc.instructions[0]?.opcode, 0x20)
        XCTAssertEqual(proc.instructions[0]?.params, [0x0B87])
    }

    func testDecodeAssemblerProcedurePreservesPredefinedFunctionIdentifier() throws {
        var bytes: [UInt8] = []
        bytes += [0x60]          // RTS
        bytes += [0x00, 0x00]    // interp
        bytes += [0x00, 0x00]    // proc
        bytes += [0x00, 0x00]    // seg
        bytes += [0x00, 0x00]    // base
        let enterSelfRefPos = bytes.count
        bytes += [UInt8(enterSelfRefPos), 0x00]  // enterIC = 0
        bytes += [0x1F, 0x00]    // proc num / lex level

        let code = Data(bytes)
        var proc = Procedure()
        proc.identifier = ProcedureIdentifier(
            isFunction: true,
            isAssembly: true,
            segment: 20,
            segmentName: "TURTLEGR",
            procedure: 31,
            procName: "PROC31",
            returnType: "INTEGER"
        )
        var assemblerEntryPoints: Set<Int> = []

        try decodeAssemblerProcedure(
            segmentNumber: 20,
            procedureNumber: 31,
            proc: &proc,
            code: code,
            addr: code.count - 2,
            assemblerEntryPoints: &assemblerEntryPoints
        )

        XCTAssertEqual(proc.identifier?.isAssembly, true)
        XCTAssertEqual(proc.identifier?.isFunction, true)
        XCTAssertEqual(proc.identifier?.segmentName, "TURTLEGR")
        XCTAssertEqual(proc.identifier?.procName, "PROC31")
    }

    func testDecodeAssemblerProcedureUsesSegmentTableNameForDefaultIdentifier() throws {
        var bytes: [UInt8] = []
        bytes += [0x60]          // RTS
        bytes += [0x00, 0x00]    // interp
        bytes += [0x00, 0x00]    // proc
        bytes += [0x00, 0x00]    // seg
        bytes += [0x00, 0x00]    // base
        let enterSelfRefPos = bytes.count
        bytes += [UInt8(enterSelfRefPos), 0x00]  // enterIC = 0
        bytes += [0x1F, 0x00]    // proc num / lex level

        let code = Data(bytes)
        var proc = Procedure()
        var assemblerEntryPoints: Set<Int> = []

        try decodeAssemblerProcedure(
            segmentNumber: 20,
            segmentName: "GRAPHICS",
            procedureNumber: 31,
            proc: &proc,
            code: code,
            addr: code.count - 2,
            assemblerEntryPoints: &assemblerEntryPoints
        )

        XCTAssertEqual(proc.identifier?.segmentName, "GRAPHICS")
        XCTAssertEqual(proc.identifier?.shortDescription, "GRAPHICS.PROC31")
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
        var assemblerEntryPoints: Set<Int> = []
        let addr = code.count - 2

        try decodeAssemblerProcedure(
            segmentNumber: 1,
            procedureNumber: 1,
            proc: &proc,
            code: code,
            addr: addr,
            assemblerEntryPoints: &assemblerEntryPoints
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
        var assemblerEntryPoints: Set<Int> = []
        let addr = code.count - 2

        try decodeAssemblerProcedure(
            segmentNumber: 1,
            procedureNumber: 1,
            proc: &proc,
            code: code,
            addr: addr,
            assemblerEntryPoints: &assemblerEntryPoints
        )

        // Backward branch should create an entry point at offset 2
        XCTAssertTrue(proc.entryPoints.contains(2))
    }

    func testBackwardBranchEntryPointAtOrAfterEnterICIsDisassembled() throws {
        var bytes: [UInt8] = []
        bytes += [0x4C, 0x10, 0x00] // JMP $0010
        bytes += Array("ABCDE".utf8) // filler/data bytes at 3..7
        bytes += [0xEA, 0x60] // code that will be jumped backward to at 8..9
        bytes += Array("FGHIJK".utf8) // filler/data bytes at 10..15
        bytes += [0xD0, 0xF6] // BNE $0008 from 0x10 (18 + -10 = 8)
        bytes += [0x60] // RTS at 0x12
        bytes += [0x00, 0x00]   // interp
        bytes += [0x00, 0x00]   // proc
        bytes += [0x00, 0x00]   // seg
        bytes += [0x00, 0x00]   // base
        let pos = bytes.count
        bytes += [UInt8(pos), 0x00] // enterIC = 0
        bytes += [0x01, 0x00]

        let code = Data(bytes)
        var proc = Procedure()
        var assemblerEntryPoints: Set<Int> = []
        let addr = code.count - 2

        try decodeAssemblerProcedure(
            segmentNumber: 1,
            procedureNumber: 1,
            proc: &proc,
            code: code,
            addr: addr,
            assemblerEntryPoints: &assemblerEntryPoints
        )

        XCTAssertTrue(proc.entryPoints.contains(8))
        XCTAssertTrue(proc.instructions[8]?.mnemonic.contains("NOP") == true)
        XCTAssertTrue(proc.instructions[9]?.mnemonic.contains("RTS") == true)
        XCTAssertTrue(proc.instructions[16]?.mnemonic.contains("BNE") == true)
    }

    func testBackwardEntryPointBeforeEnterICIsDisassembled() throws {
        var bytes: [UInt8] = []
        bytes += [0xEA]         // NOP at 0
        bytes += [0x60]         // RTS at 1
        bytes += [0xD0, 0xFC]   // BNE -4 -> target 0
        bytes += [0x60]         // RTS at 4
        bytes += [0x00, 0x00]   // interp
        bytes += [0x00, 0x00]   // proc
        bytes += [0x00, 0x00]   // seg
        bytes += [0x00, 0x00]   // base
        let enterSelfRefPos = bytes.count
        bytes += [UInt8(enterSelfRefPos - 2), 0x00]  // enterIC = 2
        bytes += [0x01, 0x00]

        let code = Data(bytes)
        var proc = Procedure()
        var assemblerEntryPoints: Set<Int> = []
        let addr = code.count - 2

        try decodeAssemblerProcedure(
            segmentNumber: 1,
            procedureNumber: 1,
            proc: &proc,
            code: code,
            addr: addr,
            assemblerEntryPoints: &assemblerEntryPoints
        )

        XCTAssertEqual(proc.enterIC, 2)
        XCTAssertTrue(proc.entryPoints.contains(0))
        XCTAssertTrue(proc.instructions[0]?.mnemonic.contains("NOP") == true)
        XCTAssertTrue(proc.instructions[1]?.mnemonic.contains("RTS") == true)
        XCTAssertTrue(proc.instructions[2]?.mnemonic.contains("BNE") == true)
        XCTAssertTrue(proc.instructions[4]?.mnemonic.contains("RTS") == true)
    }

    func testOutOfBoundsReferenceIsNotDecodedAsLocalProcedureCode() throws {
        var bytes: [UInt8] = []
        bytes += [0xEA]         // NOP at 0 (outside local bounds for this test)
        bytes += [0x60]         // RTS at 1
        bytes += [0xD0, 0xFC]   // BNE -4 -> target 0
        bytes += [0x60]         // RTS at 4
        bytes += [0x00, 0x00]   // interp
        bytes += [0x00, 0x00]   // proc
        bytes += [0x00, 0x00]   // seg
        bytes += [0x00, 0x00]   // base
        let enterSelfRefPos = bytes.count
        bytes += [UInt8(enterSelfRefPos - 2), 0x00]  // enterIC = 2
        bytes += [0x01, 0x00]

        let code = Data(bytes)
        var proc = Procedure()
        var assemblerEntryPoints: Set<Int> = []
        let addr = code.count - 2

        try decodeAssemblerProcedure(
            segmentNumber: 1,
            procedureNumber: 1,
            proc: &proc,
            code: code,
            addr: addr,
            assemblerEntryPoints: &assemblerEntryPoints,
            procedureBounds: 2..<5
        )

        XCTAssertEqual(proc.enterIC, 2)
        XCTAssertTrue(assemblerEntryPoints.contains(0))
        XCTAssertFalse(proc.entryPoints.contains(0))
        XCTAssertNil(proc.instructions[0])
        XCTAssertNil(proc.instructions[1])
        XCTAssertTrue(proc.instructions[2]?.mnemonic.contains("BNE") == true)
        XCTAssertTrue(proc.instructions[4]?.mnemonic.contains("RTS") == true)
    }

    func testBranchKeepsParsingCodeWhenNextInstructionIsNotComplementaryBranch() throws {
        var bytes: [UInt8] = []
        bytes += [0xB0, 0x02]   // BCS +2 (target 4)
        bytes += [0xEA]         // NOP at 2
        bytes += [0xEA]         // NOP at 3
        bytes += [0x60]         // RTS at 4
        bytes += [0x00, 0x00]   // interp
        bytes += [0x00, 0x00]   // proc
        bytes += [0x00, 0x00]   // seg
        bytes += [0x00, 0x00]   // base
        let pos = bytes.count
        bytes += [UInt8(pos), 0x00]
        bytes += [0x01, 0x00]

        let code = Data(bytes)
        var proc = Procedure()
        var assemblerEntryPoints: Set<Int> = []
        let addr = code.count - 2

        try decodeAssemblerProcedure(
            segmentNumber: 1,
            procedureNumber: 1,
            proc: &proc,
            code: code,
            addr: addr,
            assemblerEntryPoints: &assemblerEntryPoints
        )

        XCTAssertTrue(proc.instructions[0]?.mnemonic.contains("BCS") == true)
        XCTAssertTrue(proc.instructions[2]?.mnemonic.contains("NOP") == true)
        XCTAssertTrue(proc.instructions[3]?.mnemonic.contains("NOP") == true)
        XCTAssertTrue(proc.instructions[4]?.mnemonic.contains("RTS") == true)
    }

    func testComplementaryAdjacentBranchSwitchesToDataRegion() throws {
        var bytes: [UInt8] = []
        bytes += [0xB0, 0x04]   // BCS +4 (target 6)
        bytes += [0x90, 0x02]   // BCC +2 (complementary adjacent branch)
        bytes += [0x41, 0x42]   // data at 4..5
        bytes += [0x60]         // RTS at 6
        bytes += [0x00, 0x00]   // interp
        bytes += [0x00, 0x00]   // proc
        bytes += [0x00, 0x00]   // seg
        bytes += [0x00, 0x00]   // base
        let pos = bytes.count
        bytes += [UInt8(pos), 0x00]
        bytes += [0x01, 0x00]

        let code = Data(bytes)
        var proc = Procedure()
        var assemblerEntryPoints: Set<Int> = []
        let addr = code.count - 2

        try decodeAssemblerProcedure(
            segmentNumber: 1,
            procedureNumber: 1,
            proc: &proc,
            code: code,
            addr: addr,
            assemblerEntryPoints: &assemblerEntryPoints
        )

        XCTAssertTrue(proc.instructions[0]?.mnemonic.contains("BCS") == true)
        XCTAssertTrue(proc.instructions[2]?.mnemonic.contains("90 02") == true)
        XCTAssertTrue(proc.instructions[6]?.mnemonic.contains("RTS") == true)
    }

    func testDataBlocksArePlacedAtActualAddressesBetweenJumpTargets() throws {
        var bytes: [UInt8] = []
        bytes += [0x4c, 0x0a, 0x00] // JMP $000a
        bytes += Array("ABCDEFG".utf8) // data at 0x0003..0x0009
        bytes += [0x4c, 0x10, 0x00] // JMP $0010
        bytes += Array("hij".utf8) // data at 0x000d..0x000f
        bytes += [0xea, 0x60] // NOP/RTS at 0x0010/0x0011

        // Relocation tables: all zero counts
        bytes += [0x00, 0x00]   // interp
        bytes += [0x00, 0x00]   // proc
        bytes += [0x00, 0x00]   // seg
        bytes += [0x00, 0x00]   // base

        // enterIC self-ref => 0
        let enterSelfRefPos = bytes.count
        bytes += [UInt8(enterSelfRefPos), 0x00]
        bytes += [0x01, 0x00]

        let code = Data(bytes)
        var proc = Procedure()
        var assemblerEntryPoints: Set<Int> = []
        let addr = code.count - 2

        try decodeAssemblerProcedure(
            segmentNumber: 1,
            procedureNumber: 1,
            proc: &proc,
            code: code,
            addr: addr,
            assemblerEntryPoints: &assemblerEntryPoints
        )

        XCTAssertTrue(proc.instructions[0]?.mnemonic.contains("JMP") == true)
        XCTAssertTrue(proc.instructions[10]?.mnemonic.contains("JMP") == true)
        XCTAssertTrue(proc.instructions[16]?.mnemonic.contains("NOP") == true)

        XCTAssertTrue(proc.instructions[3]?.mnemonic.contains("41 42 43") == true)
        XCTAssertTrue(proc.instructions[13]?.mnemonic.contains("68 69 6a") == true)
    }

    func testDataRowsOverlappedByLaterDecodedInstructionOperandsAreRemoved() throws {
        var bytes: [UInt8] = []
        bytes += [0x4c, 0x20, 0x00] // JMP $0020
        bytes += Array(repeating: 0xea, count: 12) // initially data at 0x0003..0x000e
        bytes += [0x84, 0x85] // later decoded as STY $85 at 0x000f, crossing row 0x0010
        bytes += [0x60] // RTS at 0x0011
        bytes += Array(repeating: 0xea, count: 14) // initially data at 0x0012..0x001f
        bytes += [0xd0, 0xed] // BNE $000f from 0x0020
        bytes += [0x60] // RTS at 0x0022

        bytes += [0x00, 0x00]   // interp
        bytes += [0x00, 0x00]   // proc
        bytes += [0x00, 0x00]   // seg
        bytes += [0x00, 0x00]   // base
        let enterSelfRefPos = bytes.count
        bytes += [UInt8(enterSelfRefPos), 0x00]
        bytes += [0x01, 0x00]

        let code = Data(bytes)
        var proc = Procedure()
        var assemblerEntryPoints: Set<Int> = []

        try decodeAssemblerProcedure(
            segmentNumber: 1,
            procedureNumber: 1,
            proc: &proc,
            code: code,
            addr: code.count - 2,
            assemblerEntryPoints: &assemblerEntryPoints
        )

        XCTAssertTrue(proc.instructions[0x000f]?.mnemonic.contains("STY $85") == true)
        XCTAssertTrue(proc.instructions[0x0011]?.mnemonic.contains("RTS") == true)
        XCTAssertFalse(proc.instructions[0x0010]?.mnemonic.contains(" | ") == true)
    }

    func testDecodesFinalOpcodeAtCodeRegionEnd() throws {
        var bytes: [UInt8] = []
        bytes += [0xea, 0x60] // NOP, RTS
        // Relocation tables: all zero counts
        bytes += [0x00, 0x00]   // interp
        bytes += [0x00, 0x00]   // proc
        bytes += [0x00, 0x00]   // seg
        bytes += [0x00, 0x00]   // base
        // enterIC self-ref => 0
        let enterSelfRefPos = bytes.count
        bytes += [UInt8(enterSelfRefPos), 0x00]
        bytes += [0x01, 0x00]

        let code = Data(bytes)
        var proc = Procedure()
        var assemblerEntryPoints: Set<Int> = []
        let addr = code.count - 2

        try decodeAssemblerProcedure(
            segmentNumber: 1,
            procedureNumber: 1,
            proc: &proc,
            code: code,
            addr: addr,
            assemblerEntryPoints: &assemblerEntryPoints
        )

        XCTAssertTrue(proc.instructions[0]?.mnemonic.contains("NOP") == true)
        XCTAssertTrue(proc.instructions[1]?.mnemonic.contains("RTS") == true)
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

    func testComplementaryBranchHasAlwaysTakenComment() throws {
        var bytes: [UInt8] = []
        bytes += [0xB0, 0x04]   // BCS +4 (target 6)
        bytes += [0x90, 0x02]   // BCC +2 (complementary adjacent branch)
        bytes += [0x41, 0x42]   // data at 4..5
        bytes += [0x60]         // RTS at 6
        bytes += [0x00, 0x00]   // interp
        bytes += [0x00, 0x00]   // proc
        bytes += [0x00, 0x00]   // seg
        bytes += [0x00, 0x00]   // base
        let pos = bytes.count
        bytes += [UInt8(pos), 0x00]
        bytes += [0x01, 0x00]

        let code = Data(bytes)
        var proc = Procedure()
        var assemblerEntryPoints: Set<Int> = []
        let addr = code.count - 2

        try decodeAssemblerProcedure(
            segmentNumber: 1,
            procedureNumber: 1,
            proc: &proc,
            code: code,
            addr: addr,
            assemblerEntryPoints: &assemblerEntryPoints
        )

        // Verify first branch (BCS) does not have "always taken" comment
        XCTAssertTrue(proc.instructions[0]?.mnemonic.contains("BCS") == true)
        XCTAssertNil(proc.instructions[0]?.comment)
        
        // Verify second branch (BCC) has "always taken" comment
        XCTAssertTrue(proc.instructions[2]?.mnemonic.contains("90 02") == true)
        XCTAssertEqual(proc.instructions[2]?.comment, "always taken")
    }

    // MARK: - Data region alignment

    /// Helper: build minimal assembler procedure bytes and decode them.
    private func decodeBytes(_ bytes: [UInt8], enterIC: Int) throws -> Procedure {
        var b = bytes
        // relocation tables (all zero counts: base, seg, proc, interp)
        b += [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        // enterIC self-ref: distance from current position back to enterIC
        let selfRef = b.count - enterIC
        b += [UInt8(selfRef), 0x00]
        b += [0x01, 0x00]   // procNumber, lexLevel
        let code = Data(b)
        var proc = Procedure()
        var asm: Set<Int> = []
        try decodeAssemblerProcedure(
            segmentNumber: 1, procedureNumber: 1,
            proc: &proc, code: code, addr: code.count - 2,
            assemblerEntryPoints: &asm
        )
        return proc
    }

    /// Data block starting at column 3 (addr % 16 == 3): the bytes section
    /// must be padded by 3 blank byte-slots (9 leading spaces).
    func testDataRegionAlignmentWhenStartIsAtColumn3() throws {
        // addr 0: JMP $0010  (addrs 0,1,2) → data starts at addr 3
        // addr 3..15: 13 data bytes
        // addr 16: RTS (entry point from JMP)
        var bytes: [UInt8] = []
        bytes += [0x4C, 0x10, 0x00]                                    // JMP $0010
        bytes += Array(0x41...0x4D)                                     // 13 data bytes (3..15)
        bytes += [0x60]                                                 // RTS at 16

        let proc = try decodeBytes(bytes, enterIC: 0)

        let dataInsts = proc.instructions
            .filter { $0.value.mnemonic.contains(" | ") }
            .sorted { $0.key < $1.key }
        XCTAssertFalse(dataInsts.isEmpty, "Expected a data-region instruction")

        let bytesPart = dataInsts.first!.value.mnemonic
            .components(separatedBy: " | ").first ?? ""

        // 3 blank byte-slots = 3 × "   " = 9 leading spaces
        XCTAssertTrue(bytesPart.hasPrefix("         "),
            "Expected 9-space prefix for column-3 start; got: '\(bytesPart)'")
        // The separator " -" must appear exactly once (at the col-8 boundary)
        XCTAssertEqual(bytesPart.components(separatedBy: " -").count - 1, 1,
            "Expected exactly one ' -' separator; got: '\(bytesPart)'")
    }

    /// Data block starting at column 8 (addr % 16 == 8): the bytes section
    /// must be padded by 8 blank slots plus the mid-row separator (26 chars total).
    /// No extra separator should appear from the loop.
    func testDataRegionAlignmentWhenStartIsAtColumn8() throws {
        // addr 0..4: 5 NOPs
        // addr 5: JMP $0010  (addrs 5,6,7) → data starts at addr 8
        // addr 8..15: 8 data bytes
        // addr 16: RTS (entry point from JMP)
        var bytes: [UInt8] = []
        bytes += Array(repeating: 0xEA, count: 5)                      // NOPs at 0..4
        bytes += [0x4C, 0x10, 0x00]                                    // JMP $0010 at 5
        bytes += Array(0x41...0x48)                                    // 8 data bytes (8..15)
        bytes += [0x60]                                                // RTS at 16

        let proc = try decodeBytes(bytes, enterIC: 0)

        let dataInsts = proc.instructions
            .filter { $0.value.mnemonic.contains(" | ") }
            .sorted { $0.key < $1.key }
        XCTAssertFalse(dataInsts.isEmpty, "Expected a data-region instruction")

        let bytesPart = dataInsts.first!.value.mnemonic
            .components(separatedBy: " | ").first ?? ""

        // 8 blank byte-slots = 8 × "   " = 24 spaces,
        // followed by the mid-row separator " -" (space + dash) = 26 chars total.
        let expected = String(repeating: " ", count: 24) + " -"       // 26 chars
        XCTAssertTrue(bytesPart.hasPrefix(expected),
            "Expected 26-char prefix (24 spaces + ' -') for column-8 start; got: '\(bytesPart)'")
        // Only one separator " -" must appear (from pre-padding; loop must not add another)
        XCTAssertEqual(bytesPart.components(separatedBy: " -").count - 1, 1,
            "Expected exactly one ' -' separator; got: '\(bytesPart)'")
    }

    // MARK: - Indexed indirect jump-table recognition

    func testIndexedRelocatedJumpTableViaZpPointerAddsEntryPoints() throws {
        func writeWord(_ value: Int, at position: Int, in bytes: inout [UInt8]) {
            bytes[position] = UInt8(value & 0xff)
            bytes[position + 1] = UInt8((value >> 8) & 0xff)
        }

        // Pattern under test:
        //   LDA $0010,X
        //   STA $78
        //   LDA $0011,X
        //   STA $79
        //   JMP ($78)
        // with relocated words at $0010/$0012 used as jump-table targets.
        var bytes: [UInt8] = []
        bytes += [0xBD, 0x10, 0x00]
        bytes += [0x85, 0x78]
        bytes += [0xBD, 0x11, 0x00]
        bytes += [0x85, 0x79]
        bytes += [0x6C, 0x78, 0x00]
        bytes += [0xEA, 0xEA, 0xEA] // filler to reach table address 0x0010
        bytes += [0x00, 0x00]       // relocated word @ 0x0010 -> target 0x0020
        bytes += [0x00, 0x00]       // relocated word @ 0x0012 -> target 0x0022
        bytes += [0xEA, 0xEA, 0xEA, 0xEA, 0xEA, 0xEA, 0xEA, 0xEA, 0xEA, 0xEA, 0xEA, 0xEA]
        bytes += [0x60]             // RTS at 0x0020
        bytes += [0xEA]
        bytes += [0x60]             // RTS at 0x0022

        // Footer: interp count, proc relocation pointers + count, seg/base counts, enterIC self-ref, proc header.
        bytes += [0x00, 0x00]       // interpRelocCount = 0

        let procRelocPtrPosA = bytes.count
        bytes += [0x00, 0x00]       // proc relocation pointer (for table addr 0x0010)
        let procRelocPtrPosB = bytes.count
        bytes += [0x00, 0x00]       // proc relocation pointer (for table addr 0x0012)
        bytes += [0x02, 0x00]       // procRelocCount = 2

        bytes += [0x00, 0x00]       // segRelocCount = 0
        bytes += [0x00, 0x00]       // baseRelocCount = 0

        let enterSelfRefPos = bytes.count
        bytes += [0x00, 0x00]       // enterIC self-ref (patched below)
        bytes += [0x01, 0x00]       // procNumber, lexLevel

        // enterIC = 0
        writeWord(enterSelfRefPos, at: enterSelfRefPos, in: &bytes)

        // Relocated table words encode target offsets from enterIC.
        writeWord(0x0020, at: 0x0010, in: &bytes)
        writeWord(0x0022, at: 0x0012, in: &bytes)

        // Encode self-referenced pointers so parseAssemblerFooter resolves them
        // to table addresses 0x0010 and 0x0012.
        writeWord(procRelocPtrPosA - 0x0010, at: procRelocPtrPosA, in: &bytes)
        writeWord(procRelocPtrPosB - 0x0012, at: procRelocPtrPosB, in: &bytes)

        let code = Data(bytes)
        var proc = Procedure()
        var assemblerEntryPoints: Set<Int> = []
        let addr = code.count - 2

        try decodeAssemblerProcedure(
            segmentNumber: 1,
            procedureNumber: 1,
            proc: &proc,
            code: code,
            addr: addr,
            assemblerEntryPoints: &assemblerEntryPoints
        )

        // Targets recovered from relocated jump-table words should be considered entry points.
        XCTAssertTrue(proc.entryPoints.contains(0x0020), "Expected inferred entry point at 0x0020")
        XCTAssertTrue(proc.entryPoints.contains(0x0022), "Expected inferred entry point at 0x0022")
    }
}
