import XCTest
@testable import pdisasm
import Foundation

final class CodeDataStringFailureTests: XCTestCase {

    func testReadStringDecodingFailed() {
        // Feed bytes that are valid length but contain bytes that cannot decode as ASCII.
        // ASCII encoding in Swift's String(data:encoding:.ascii) fails if any byte >= 0x80.
        // Length = 2, then two bytes with high bit set.
        let cd = CodeData(data: Data([0x02, 0x80, 0x81]), instructionPointer: 0, header: 0)
        XCTAssertThrowsError(try cd.readString(at: 0)) { error in
            XCTAssertEqual(error as? CodeDataError, CodeDataError.stringDecodingFailed)
        }
    }

    func testReadStringSucceedsWithValidASCII() throws {
        let cd = CodeData(data: Data([0x03, 0x41, 0x42, 0x43]), instructionPointer: 0, header: 0)
        let result = try cd.readString(at: 0)
        XCTAssertEqual(result, "ABC")
    }

    func testReadStringEmptyString() throws {
        let cd = CodeData(data: Data([0x00]), instructionPointer: 0, header: 0)
        let result = try cd.readString(at: 0)
        XCTAssertEqual(result, "")
    }

    func testReadStringTruncated() {
        // Length says 5 but only 2 bytes follow
        let cd = CodeData(data: Data([0x05, 0x41, 0x42]), instructionPointer: 0, header: 0)
        XCTAssertThrowsError(try cd.readString(at: 0)) { error in
            XCTAssertEqual(error as? CodeDataError, CodeDataError.unexpectedEndOfData)
        }
    }
}
