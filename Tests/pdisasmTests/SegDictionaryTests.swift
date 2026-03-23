import XCTest
@testable import pdisasm

final class SegDictionaryTests: XCTestCase {

    func testDescriptionContainsTableHeaders() {
        let seg = Segment(codeAddress: 0x0010, codeLength: 512, name: "TESTSEG", segmentKind: .dataseg, textAddress: 0, segNum: 1, machineType: 0, version: 2)
        let dict = SegDictionary(segTable: [0: seg], intrinsics: Set<UInt8>(), comment: "test comment")
        let desc = dict.description

        XCTAssertTrue(desc.contains("## Segment Table"))
        XCTAssertTrue(desc.contains("| slot |"))
        XCTAssertTrue(desc.contains("| segNum |"))
        XCTAssertTrue(desc.contains("| name |"))
        XCTAssertTrue(desc.contains("| codeAddress |"))
    }

    func testDescriptionContainsSegmentRow() {
        let seg = Segment(codeAddress: 0x0010, codeLength: 512, name: "MYSEG", segmentKind: .dataseg, textAddress: 0, segNum: 1, machineType: 0, version: 2)
        let dict = SegDictionary(segTable: [0: seg], intrinsics: Set<UInt8>(), comment: "")
        let desc = dict.description

        XCTAssertTrue(desc.contains("MYSEG"))
        XCTAssertTrue(desc.contains("0010"))  // hex codeAddress
        XCTAssertTrue(desc.contains("512"))   // codeLength
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
        let seg1 = Segment(codeAddress: 0x0020, codeLength: 512, name: "SECOND", segmentKind: .dataseg, textAddress: 0, segNum: 2, machineType: 0, version: 0)
        let seg2 = Segment(codeAddress: 0x0010, codeLength: 256, name: "FIRST", segmentKind: .dataseg, textAddress: 0, segNum: 1, machineType: 0, version: 0)
        let dict = SegDictionary(segTable: [0: seg1, 1: seg2], intrinsics: [], comment: "")
        let desc = dict.description

        // FIRST (codeAddress 0x0010) should appear before SECOND (codeAddress 0x0020)
        if let firstRange = desc.range(of: "FIRST"), let secondRange = desc.range(of: "SECOND") {
            XCTAssertTrue(firstRange.lowerBound < secondRange.lowerBound)
        } else {
            XCTFail("Expected both segment names in description")
        }
    }
}
