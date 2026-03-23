import XCTest
@testable import pdisasm
import Foundation

final class LocationTests: XCTestCase {

    // MARK: - init(from str:) parsing

    func testInitFromStringFullyQualified() {
        let loc = Location(from: "S1_P2_L3_A4")
        XCTAssertEqual(loc.segment, 1)
        XCTAssertEqual(loc.procedure, 2)
        XCTAssertEqual(loc.lexLevel, 3)
        XCTAssertEqual(loc.addr, 4)
    }

    func testInitFromStringPartial() {
        let loc = Location(from: "S5_A10")
        XCTAssertEqual(loc.segment, 5)
        XCTAssertNil(loc.procedure)
        XCTAssertNil(loc.lexLevel)
        XCTAssertEqual(loc.addr, 10)
    }

    func testInitFromStringNoUnderscoreDefaultsToZero() {
        let loc = Location(from: "nounderscores")
        XCTAssertEqual(loc.segment, 0)
        XCTAssertNil(loc.procedure)
        XCTAssertNil(loc.lexLevel)
        XCTAssertNil(loc.addr)
    }

    // MARK: - Equality & Hashing

    func testEqualityByStructure() {
        let a = Location(segment: 1, procedure: 2, lexLevel: 3, addr: 4, name: "foo", type: "INT")
        let b = Location(segment: 1, procedure: 2, lexLevel: 3, addr: 4, name: "bar", type: "BOOL")
        // Equality ignores name and type
        XCTAssertEqual(a, b)
    }

    func testInequalityBySegment() {
        let a = Location(segment: 1, procedure: 2)
        let b = Location(segment: 2, procedure: 2)
        XCTAssertNotEqual(a, b)
    }

    func testHashableInSet() {
        let a = Location(segment: 1, procedure: 2, addr: 3)
        let b = Location(segment: 1, procedure: 2, addr: 3)
        let set: Set<Location> = [a, b]
        XCTAssertEqual(set.count, 1)
    }

    // MARK: - Comparable

    func testComparableBySegment() {
        let a = Location(segment: 0, procedure: 1)
        let b = Location(segment: 1, procedure: 0)
        XCTAssertTrue(a < b)
    }

    func testComparableByProcedure() {
        let a = Location(segment: 1, procedure: 1)
        let b = Location(segment: 1, procedure: 2)
        XCTAssertTrue(a < b)
    }

    func testComparableByAddr() {
        let a = Location(segment: 1, procedure: 1, lexLevel: 0, addr: 5)
        let b = Location(segment: 1, procedure: 1, lexLevel: 0, addr: 10)
        XCTAssertTrue(a < b)
    }

    func testComparableNilProcedureLessThanNonNil() {
        let a = Location(segment: 1) // procedure == nil -> -1
        let b = Location(segment: 1, procedure: 0)
        XCTAssertTrue(a < b)
    }

    // MARK: - dispName

    func testDispNameWithName() {
        let loc = Location(segment: 1, procedure: 2, addr: 3, name: "MYVAR")
        XCTAssertEqual(loc.dispName, "MYVAR")
    }

    func testDispNameWithoutName() {
        let loc = Location(segment: 1, procedure: 2, lexLevel: 3, addr: 4)
        XCTAssertEqual(loc.dispName, "S1_P2_L3_A4")
    }

    func testDispNameMinimal() {
        let loc = Location(segment: 0)
        XCTAssertEqual(loc.dispName, "S0")
    }

    // MARK: - dispType

    func testDispTypeWithType() {
        let loc = Location(segment: 0, type: "INTEGER")
        XCTAssertEqual(loc.dispType, "INTEGER")
    }

    func testDispTypeEmpty() {
        let loc = Location(segment: 0)
        XCTAssertEqual(loc.dispType, "UNKNOWN")
    }

    // MARK: - description

    func testDescriptionWithNameAndType() {
        let loc = Location(segment: 1, name: "FOO", type: "CHAR")
        XCTAssertEqual(loc.description, "FOO:CHAR")
    }

    func testDescriptionWithoutName() {
        let loc = Location(segment: 1, procedure: 2, addr: 3)
        XCTAssertEqual(loc.description, "S1_P2_A3")
    }

    func testDescriptionWithNameWithoutType() {
        let loc = Location(segment: 1, name: "BAR")
        XCTAssertEqual(loc.description, "BAR")
    }

    // MARK: - Codable round-trip

    func testCodableRoundTrip() throws {
        let original = Location(segment: 2, procedure: 3, lexLevel: 1, addr: 42, name: "TEST", type: "INTEGER")
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Location.self, from: data)
        XCTAssertEqual(decoded.segment, 2)
        XCTAssertEqual(decoded.procedure, 3)
        XCTAssertEqual(decoded.lexLevel, 1)
        XCTAssertEqual(decoded.addr, 42)
        XCTAssertEqual(decoded.name, "TEST")
        XCTAssertEqual(decoded.type, "INTEGER")
        XCTAssertEqual(original, decoded)
    }

    func testCodableRoundTripWithNils() throws {
        let original = Location(segment: 0, name: "", type: "")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Location.self, from: data)
        XCTAssertEqual(decoded.segment, 0)
        XCTAssertNil(decoded.procedure)
        XCTAssertNil(decoded.lexLevel)
        XCTAssertNil(decoded.addr)
    }
}
