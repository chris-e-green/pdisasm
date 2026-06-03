import XCTest
@testable import pdisasm
import Foundation

final class OpcodeDecoderTests: XCTestCase {

    /// Helper to create an OpcodeDecoder with given bytes and decode at ic=0.
    private func decode(bytes: [UInt8], opcode: UInt8, ic: Int = 0, segment: Int = 1, procedure: Int = 1, addr: Int = 100) throws -> OpcodeDecoder.DecodedInstruction {
        let cd = CodeData(data: Data(bytes), instructionPointer: 0, header: addr)
        let decoder = OpcodeDecoder(codeData: cd)
        let seg = Segment(codeAddress: 0, codeLength: bytes.count, name: "T", segmentKind: .dataseg, textAddress: 0, segNum: segment, machineType: 0, version: 0)
        let proc = Procedure()
        return try decoder.decode(opcode: opcode, at: ic, currSeg: seg, segment: segment, procedure: procedure, proc: proc, addr: addr)
    }

    // MARK: - Trivial single-byte opcodes

    func testSLDC() throws {
        let result = try decode(bytes: [0x05], opcode: 0x05)
        XCTAssertEqual(result.mnemonic, "SLDC")
        XCTAssertEqual(result.params, [5])
        XCTAssertEqual(result.bytesConsumed, 1)
    }

    func testABI() throws {
        let result = try decode(bytes: [0x80], opcode: abi)
        XCTAssertEqual(result.mnemonic, "ABI")
        XCTAssertEqual(result.bytesConsumed, 1)
    }

    func testADI() throws {
        let result = try decode(bytes: [0x82], opcode: adi)
        XCTAssertEqual(result.mnemonic, "ADI")
        XCTAssertEqual(result.bytesConsumed, 1)
    }

    func testSTO() throws {
        let result = try decode(bytes: [0x9A], opcode: sto)
        XCTAssertEqual(result.mnemonic, "STO")
        XCTAssertEqual(result.bytesConsumed, 1)
    }

    func testLDCN() throws {
        let result = try decode(bytes: [0x9F], opcode: ldcn)
        XCTAssertEqual(result.mnemonic, "LDCN")
        XCTAssertEqual(result.bytesConsumed, 1)
    }

    // MARK: - Parameterised opcodes

    func testCSP() throws {
        // CSP opcode followed by procedure number
        let result = try decode(bytes: [0x9E, 0x00], opcode: csp)
        XCTAssertEqual(result.mnemonic, "CSP")
        XCTAssertEqual(result.params, [0])
        XCTAssertEqual(result.bytesConsumed, 2)
        XCTAssertTrue(result.comment?.contains("IOC") == true)
    }

    func testADJ() throws {
        let result = try decode(bytes: [0xA0, 0x03], opcode: adj)
        XCTAssertEqual(result.mnemonic, "ADJ")
        XCTAssertEqual(result.params, [3])
        XCTAssertEqual(result.bytesConsumed, 2)
    }

    func testFJPForwardJump() throws {
        // FJP with forward offset 0x04 at ic=0 -> dest = ic + offset + 2 = 0 + 4 + 2 = 6
        let result = try decode(bytes: [0xA1, 0x04], opcode: fjp)
        XCTAssertEqual(result.mnemonic, "FJP")
        XCTAssertEqual(result.params, [6])
        XCTAssertEqual(result.bytesConsumed, 2)
    }

    func testINCWithBigValue() throws {
        // INC with single-byte BIG value 0x05
        let result = try decode(bytes: [0xA2, 0x05], opcode: inc)
        XCTAssertEqual(result.mnemonic, "INC")
        XCTAssertEqual(result.params, [5])
        XCTAssertEqual(result.bytesConsumed, 2) // 1 opcode + 1 BIG byte
    }

    func testLDOWithBigValue() throws {
        let result = try decode(bytes: [0xA9, 0x02], opcode: ldo)
        XCTAssertEqual(result.mnemonic, "LDO")
        XCTAssertEqual(result.params, [2])
        XCTAssertNotNil(result.memLocation)
        XCTAssertEqual(result.memLocation?.addr, 2)
    }

    func testExtendedGlobalReferencesUseNilProcedureUntilResolved() throws {
        let ldeResult = try decode(bytes: [lde, 0x01, 0x02], opcode: lde)
        XCTAssertEqual(ldeResult.memLocation?.segment, 1)
        XCTAssertNil(ldeResult.memLocation?.procedure)
        XCTAssertEqual(ldeResult.memLocation?.lexLevel, 0)
        XCTAssertEqual(ldeResult.memLocation?.addr, 2)

        let laeResult = try decode(bytes: [lae, 0x01, 0x03], opcode: lae)
        XCTAssertEqual(laeResult.memLocation?.segment, 1)
        XCTAssertNil(laeResult.memLocation?.procedure)
        XCTAssertEqual(laeResult.memLocation?.lexLevel, 0)
        XCTAssertEqual(laeResult.memLocation?.addr, 3)

        let steResult = try decode(bytes: [ste, 0x01, 0x04], opcode: ste)
        XCTAssertEqual(steResult.memLocation?.segment, 1)
        XCTAssertNil(steResult.memLocation?.procedure)
        XCTAssertEqual(steResult.memLocation?.lexLevel, 0)
        XCTAssertEqual(steResult.memLocation?.addr, 4)
    }

    func testNestedProcedureGlobalReferenceUsesNilProcedureUntilResolved() throws {
        let cd = CodeData(data: Data([sldo1]), instructionPointer: 0, header: 0)
        let decoder = OpcodeDecoder(codeData: cd)
        let seg = Segment(
            codeAddress: 0,
            codeLength: 1,
            name: "T",
            segmentKind: .dataseg,
            textAddress: 0,
            segNum: 1,
            machineType: 0,
            version: 0
        )
        let proc = Procedure()
        proc.identifier = ProcedureIdentifier(isFunction: false, segment: 1, procedure: 2)
        proc.lexicalLevel = 1

        let result = try decoder.decode(
            opcode: sldo1,
            at: 0,
            currSeg: seg,
            segment: 1,
            procedure: 2,
            proc: proc,
            addr: 0
        )

        XCTAssertEqual(result.memLocation?.segment, 1)
        XCTAssertNil(result.memLocation?.procedure)
        XCTAssertEqual(result.memLocation?.lexLevel, 0)
        XCTAssertEqual(result.memLocation?.addr, 1)
    }

    func testNormaliseMemoryLocationsResolvesNilProcedureGlobalReference() {
        let proc = Procedure()
        proc.identifier = ProcedureIdentifier(isFunction: false, segment: 1, procedure: 2)
        proc.lexicalLevel = 1
        proc.instructions[0] = Instruction(
            opcode: lde,
            mnemonic: "LDE",
            memLocation: Location(segment: 1, procedure: nil, lexLevel: 0, addr: 2)
        )

        normaliseMemoryLocations(
            proc,
            [
                Call(
                    from: Location(segment: 1, procedure: 1, lexLevel: 0),
                    to: Location(segment: 1, procedure: 2, lexLevel: 1)
                )
            ]
        )

        XCTAssertEqual(proc.instructions[0]?.memLocation?.segment, 1)
        XCTAssertEqual(proc.instructions[0]?.memLocation?.procedure, 1)
        XCTAssertEqual(proc.instructions[0]?.memLocation?.lexLevel, 0)
        XCTAssertEqual(proc.instructions[0]?.memLocation?.addr, 2)
    }

    func testNormaliseMemoryLocationsPreservesExplicitExternalDataSegment() {
        let proc = Procedure()
        proc.identifier = ProcedureIdentifier(isFunction: false, segment: 20, procedure: 12)
        proc.lexicalLevel = 1
        proc.instructions[0] = Instruction(
            opcode: lde,
            mnemonic: "LDE",
            memLocation: Location(segment: 21, procedure: nil, lexLevel: 0, addr: 193)
        )

        normaliseMemoryLocations(
            proc,
            [
                Call(
                    from: Location(segment: 20, procedure: 16, lexLevel: 0),
                    to: Location(segment: 20, procedure: 12, lexLevel: 1)
                )
            ]
        )

        XCTAssertEqual(proc.instructions[0]?.memLocation?.segment, 21)
        XCTAssertNil(proc.instructions[0]?.memLocation?.procedure)
        XCTAssertEqual(proc.instructions[0]?.memLocation?.lexLevel, 0)
        XCTAssertEqual(proc.instructions[0]?.memLocation?.addr, 193)
    }

    func testLSA() throws {
        // LSA: length=3, then "abc"
        let result = try decode(bytes: [0xA6, 0x03, 0x61, 0x62, 0x63], opcode: lsa)
        XCTAssertEqual(result.mnemonic, "LSA")
        XCTAssertEqual(result.stringParameter, "abc")
        XCTAssertEqual(result.bytesConsumed, 5) // 1 opcode + 1 len + 3 chars
    }

    func testRNP() throws {
        let result = try decode(bytes: [0xAD, 0x00], opcode: rnp)
        XCTAssertEqual(result.mnemonic, "RNP")
        XCTAssertEqual(result.params, [0])
        XCTAssertEqual(result.bytesConsumed, 2)
    }

    func testCIP() throws {
        let result = try decode(bytes: [0xAE, 0x05], opcode: cip)
        XCTAssertEqual(result.mnemonic, "CIP")
        XCTAssertEqual(result.params, [5])
        XCTAssertNotNil(result.destination)
        XCTAssertEqual(result.destination?.procedure, 5)
    }

    func testLDCI() throws {
        // LDCI: opcode 0xC7 followed by a word (little-endian)
        let result = try decode(bytes: [0xC7, 0x34, 0x12], opcode: ldci)
        XCTAssertEqual(result.mnemonic, "LDCI")
        XCTAssertEqual(result.params, [0x1234])
        XCTAssertEqual(result.bytesConsumed, 3)
    }

    func testSLDL() throws {
        // SLDL1 = 0xD8 -> local word 1
        let result = try decode(bytes: [0xD8], opcode: sldl1)
        XCTAssertEqual(result.mnemonic, "SLDL")
        XCTAssertEqual(result.params, [1])
        XCTAssertEqual(result.bytesConsumed, 1)
        XCTAssertNotNil(result.memLocation)
    }

    func testSLDO() throws {
        // SLDO1 = 0xE8 -> global word 1
        let result = try decode(bytes: [0xE8], opcode: sldo1)
        XCTAssertEqual(result.mnemonic, "SLDO")
        XCTAssertEqual(result.params, [1])
        XCTAssertEqual(result.bytesConsumed, 1)
    }

    func testSIND() throws {
        // SIND0 = 0xF8
        let result = try decode(bytes: [0xF8], opcode: sind0)
        XCTAssertEqual(result.mnemonic, "SIND")
        XCTAssertEqual(result.params, [0])
        XCTAssertEqual(result.bytesConsumed, 1)
    }

    // MARK: - Comparator opcodes

    func testEQLRequiresComparator() throws {
        // EQL opcode 0xAF followed by comparator byte
        let result = try decode(bytes: [0xAF, 0x02], opcode: eql)
        XCTAssertEqual(result.mnemonic, "EQL")
        XCTAssertTrue(result.requiresComparator)
    }

    // MARK: - decodeComparator

    func testDecodeComparatorReal() {
        let cd = CodeData(data: Data([0x02]), instructionPointer: 0, header: 0)
        let decoder = OpcodeDecoder(codeData: cd)
        let (suffix, prefix, inc, dataType) = decoder.decodeComparator(at: 0)
        XCTAssertEqual(suffix, "REAL")
        XCTAssertEqual(prefix, "Real")
        XCTAssertEqual(inc, 1)
        XCTAssertEqual(dataType, "REAL")
    }

    func testDecodeComparatorString() {
        let cd = CodeData(data: Data([0x04]), instructionPointer: 0, header: 0)
        let decoder = OpcodeDecoder(codeData: cd)
        let (suffix, _, _, dataType) = decoder.decodeComparator(at: 0)
        XCTAssertEqual(suffix, "STR")
        XCTAssertEqual(dataType, "STRING")
    }

    func testDecodeComparatorBool() {
        let cd = CodeData(data: Data([0x06]), instructionPointer: 0, header: 0)
        let decoder = OpcodeDecoder(codeData: cd)
        let (suffix, _, _, dataType) = decoder.decodeComparator(at: 0)
        XCTAssertEqual(suffix, "BOOL")
        XCTAssertEqual(dataType, "BOOLEAN")
    }

    func testDecodeComparatorSet() {
        let cd = CodeData(data: Data([0x08]), instructionPointer: 0, header: 0)
        let decoder = OpcodeDecoder(codeData: cd)
        let (suffix, _, _, dataType) = decoder.decodeComparator(at: 0)
        XCTAssertEqual(suffix, "SET")
        XCTAssertEqual(dataType, "SET")
    }

    func testDecodeComparatorByteArray() {
        // Byte array: 0x0A followed by BIG value 5
        let cd = CodeData(data: Data([0x0A, 0x05]), instructionPointer: 0, header: 0)
        let decoder = OpcodeDecoder(codeData: cd)
        let (suffix, prefix, inc, dataType) = decoder.decodeComparator(at: 0)
        XCTAssertEqual(suffix, "BYTE")
        XCTAssertTrue(prefix.contains("5"))
        XCTAssertEqual(inc, 2) // 1 for comparator byte + 1 for BIG
        XCTAssertTrue(dataType.contains("BYTE"))
    }

    func testDecodeComparatorWordArray() {
        // Word array: 0x0C followed by BIG value 3
        let cd = CodeData(data: Data([0x0C, 0x03]), instructionPointer: 0, header: 0)
        let decoder = OpcodeDecoder(codeData: cd)
        let (suffix, _, _, dataType) = decoder.decodeComparator(at: 0)
        XCTAssertEqual(suffix, "WORD")
        XCTAssertTrue(dataType.contains("WORD"))
    }

    func testDecodeComparatorUnknown() {
        let cd = CodeData(data: Data([0xFF]), instructionPointer: 0, header: 0)
        let decoder = OpcodeDecoder(codeData: cd)
        let (suffix, _, inc, dataType) = decoder.decodeComparator(at: 0)
        XCTAssertEqual(suffix, "")
        XCTAssertEqual(dataType, "")
        XCTAssertEqual(inc, 1)
    }
}
