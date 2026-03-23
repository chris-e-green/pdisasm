import XCTest
@testable import pdisasm

final class SegDictionaryTests: XCTestCase {

    func testDescriptionContainsTableHeaders() {
        let seg = Segment(codeaddr: 0x0010, codeleng: 512, name: "TESTSEG", segkind: .dataseg, textaddr: 0, segNum: 1, mType: 0, version: 2)
        let dict = SegDictionary(segTable: [0: seg], intrinsics: Set<UInt8>(), comment: "test comment")
        let desc = dict.description

        XCTAssertTrue(desc.contains("## Segment Table"))
        XCTAssertTrue(desc.contains("| slot |"))
        XCTAssertTrue(desc.contains("| segNum |"))
        XCTAssertTrue(desc.contains("| name |"))
        XCTAssertTrue(desc.contains("| codeaddr |"))
    }

    func testDescriptionContainsSegmentRow() {
        let seg = Segment(codeaddr: 0x0010, codeleng: 512, name: "MYSEG", segkind: .dataseg, textaddr: 0, segNum: 1, mType: 0, version: 2)
        let dict = SegDictionary(segTable: [0: seg], intrinsics: Set<UInt8>(), comment: "")
        let desc = dict.description

        XCTAssertTrue(desc.contains("MYSEG"))
        XCTAssertTrue(desc.contains("0010"))  // hex codeaddr
        XCTAssertTrue(desc.contains("512"))   // codeleng
    }

    func testDescriptionContainsComment() {
        let dict = SegDictionary(segTable: [:], intrinsics: Set<UInt8>(), comment: "My Comment")
        XCTAssertTrue(dict.description.contains("My Comment"))
    }

    func testDescriptionContainsIntrinsics() {
        let dict = SegDictionary(segTable: [:], intrinsics: [3, 7], comment: "")
        let desc = dict.description
        XCTAssertTrue(desc.contains("intrinsics:"))
    }

    func testMultipleSegmentsSortedByCodeaddr() {
        let seg1 = Segment(codeaddr: 0x0020, codeleng: 512, name: "SECOND", segkind: .dataseg, textaddr: 0, segNum: 2, mType: 0, version: 0)
        let seg2 = Segment(codeaddr: 0x0010, codeleng: 256, name: "FIRST", segkind: .dataseg, textaddr: 0, segNum: 1, mType: 0, version: 0)
        let dict = SegDictionary(segTable: [0: seg1, 1: seg2], intrinsics: [], comment: "")
        let desc = dict.description

        // FIRST (codeaddr 0x0010) should appear before SECOND (codeaddr 0x0020)
        if let firstRange = desc.range(of: "FIRST"), let secondRange = desc.range(of: "SECOND") {
            XCTAssertTrue(firstRange.lowerBound < secondRange.lowerBound)
        } else {
            XCTFail("Expected both segment names in description")
        }
    }
}
