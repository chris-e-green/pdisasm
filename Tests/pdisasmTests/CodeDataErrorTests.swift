import XCTest
@testable import pdisasm

final class CodeDataErrorTests: XCTestCase {
    func testReadByteThrowsOnEOF() {
        let cd = CodeData(data: Data([]), instructionPointer: 0, header: 0)
        XCTAssertThrowsError(try cd.readByte(at: 0)) { error in
            XCTAssertEqual(error as? CodeDataError, CodeDataError.unexpectedEndOfData)
        }
    }

    func testReadWordThrowsOnEOF() {
        let cd = CodeData(data: Data([0x01]), instructionPointer: 0, header: 0)
        XCTAssertThrowsError(try cd.readWord(at: 0)) { error in
            XCTAssertEqual(error as? CodeDataError, CodeDataError.unexpectedEndOfData)
        }
    }

    func testReadBigThrowsOnEOFForTwoByte() {
        let cd = CodeData(data: Data([0xFF]), instructionPointer: 0, header: 0)
        // 0xFF indicates a two-byte BIG; the next byte is missing
        XCTAssertThrowsError(try cd.readBig(at: 0)) { error in
            XCTAssertEqual(error as? CodeDataError, CodeDataError.unexpectedEndOfData)
        }
    }

    func testReadAddressJumpTableOutOfBoundsThrows() {
        let cd = CodeData(data: Data([0x80]), instructionPointer: 0, header: 10) // offset 0x80 -> jte = header + 128 - 256 = header - 128 => negative
        // readAddress should attempt to read a word at a computed jte, which will be out-of-bounds and throw
        XCTAssertThrowsError(try cd.readAddress(at: 0)) { error in
            XCTAssertEqual(error as? CodeDataError, CodeDataError.unexpectedEndOfData)
        }
    }
}
