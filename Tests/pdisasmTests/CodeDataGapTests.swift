import XCTest
@testable import pdisasm
import Foundation

final class CodeDataGapTests: XCTestCase {

    // MARK: - readInt signed handling

    func testReadIntPositive() throws {
        // 0x1234 = 4660 (positive, < 32767)
        let cd = CodeData(data: Data([0x34, 0x12]))
        let val = try cd.readInt(at: 0)
        XCTAssertEqual(val, 0x1234)
    }

    func testReadIntNegative() throws {
        // 0xFFFF = 65535 > 32767 -> should be -1
        let cd = CodeData(data: Data([0xFF, 0xFF]))
        let val = try cd.readInt(at: 0)
        XCTAssertEqual(val, -1)
    }

    func testReadIntBoundary32767() throws {
        // 0x7FFF = 32767 (exactly at boundary, should stay positive)
        let cd = CodeData(data: Data([0xFF, 0x7F]))
        let val = try cd.readInt(at: 0)
        XCTAssertEqual(val, 32767)
    }

    func testReadIntBoundary32768() throws {
        // 0x8000 = 32768 > 32767 -> should be -32768
        let cd = CodeData(data: Data([0x00, 0x80]))
        let val = try cd.readInt(at: 0)
        XCTAssertEqual(val, -32768)
    }

    func testReadIntOutOfBoundsThrows() {
        let cd = CodeData(data: Data([0x01]))
        XCTAssertThrowsError(try cd.readInt(at: 0)) { error in
            XCTAssertEqual(error as? CodeDataError, CodeDataError.unexpectedEndOfData)
        }
    }

    func testReadIntNegativePositionThrows() {
        let cd = CodeData(data: Data([0x01, 0x02]))
        XCTAssertThrowsError(try cd.readInt(at: -1)) { error in
            XCTAssertEqual(error as? CodeDataError, CodeDataError.unexpectedEndOfData)
        }
    }

    // MARK: - readByte(at:) bounds

    func testReadByteAtValidPosition() throws {
        let cd = CodeData(data: Data([0xAB, 0xCD]))
        XCTAssertEqual(try cd.readByte(at: 0), 0xAB)
        XCTAssertEqual(try cd.readByte(at: 1), 0xCD)
    }

    func testReadByteAtOutOfBoundsThrows() {
        let cd = CodeData(data: Data([0x01]))
        XCTAssertThrowsError(try cd.readByte(at: 1))
    }

    func testReadByteAtNegativeThrows() {
        let cd = CodeData(data: Data([0x01]))
        XCTAssertThrowsError(try cd.readByte(at: -1))
    }

    // MARK: - getCodeBlock boundaries

    func testGetCodeBlockValid() {
        let data = Data(repeating: 0xAA, count: 1024)
        let cd = CodeData(data: data)
        let block = cd.getCodeBlock(at: 1, length: 512)
        XCTAssertEqual(block.count, 512)
        XCTAssertTrue(block.allSatisfy { $0 == 0xAA })
    }

    func testGetCodeBlockOutOfBoundsReturnsEmpty() {
        let data = Data(repeating: 0x00, count: 100)
        let cd = CodeData(data: data)
        let block = cd.getCodeBlock(at: 1, length: 512)
        XCTAssertEqual(block.count, 0)
    }

    func testGetCodeBlockAtZero() {
        let data = Data(repeating: 0xBB, count: 512)
        let cd = CodeData(data: data)
        let block = cd.getCodeBlock(at: 0, length: 256)
        XCTAssertEqual(block.count, 256)
    }

    func testGetCodeBlockExactBoundary() {
        let data = Data(repeating: 0xCC, count: 1024)
        let cd = CodeData(data: data)
        let block = cd.getCodeBlock(at: 0, length: 1024)
        XCTAssertEqual(block.count, 1024)
    }

    // MARK: - readBig at position bounds

    func testReadBigAtOutOfBoundsThrows() {
        let cd = CodeData(data: Data())
        XCTAssertThrowsError(try cd.readBig(at: 0))
    }

    func testReadBigTwoByteAtBoundaryThrows() {
        // First byte > 127 but no second byte
        let cd = CodeData(data: Data([0x80]))
        XCTAssertThrowsError(try cd.readBig(at: 0))
    }

    // MARK: - readWord(at:) bounds

    func testReadWordAtNegativePositionThrows() {
        let cd = CodeData(data: Data([0x01, 0x02]))
        XCTAssertThrowsError(try cd.readWord(at: -1))
    }
}
