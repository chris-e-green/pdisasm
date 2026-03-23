import XCTest
@testable import pdisasm

final class CallTests: XCTestCase {

    // MARK: - Equality

    func testEqualCalls() {
        let from = Location(segment: 1, procedure: 1)
        let to = Location(segment: 1, procedure: 2)
        let a = Call(from: from, to: to)
        let b = Call(from: Location(segment: 1, procedure: 1), to: Location(segment: 1, procedure: 2))
        XCTAssertEqual(a, b)
    }

    func testUnequalCallsByOrigin() {
        let a = Call(from: Location(segment: 1, procedure: 1), to: Location(segment: 1, procedure: 3))
        let b = Call(from: Location(segment: 1, procedure: 2), to: Location(segment: 1, procedure: 3))
        XCTAssertNotEqual(a, b)
    }

    func testUnequalCallsByTarget() {
        let a = Call(from: Location(segment: 1, procedure: 1), to: Location(segment: 1, procedure: 2))
        let b = Call(from: Location(segment: 1, procedure: 1), to: Location(segment: 1, procedure: 3))
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Hashing

    func testHashableInSet() {
        let a = Call(from: Location(segment: 1, procedure: 1), to: Location(segment: 1, procedure: 2))
        let b = Call(from: Location(segment: 1, procedure: 1), to: Location(segment: 1, procedure: 2))
        let set: Set<Call> = [a, b]
        XCTAssertEqual(set.count, 1)
    }

    // MARK: - Description

    func testDescription() {
        let call = Call(from: Location(segment: 0, procedure: 1, name: "CALLER"), to: Location(segment: 0, procedure: 2, name: "CALLEE"))
        let desc = call.description
        XCTAssertTrue(desc.contains("From"))
        XCTAssertTrue(desc.contains("to"))
        XCTAssertTrue(desc.contains("CALLER"))
        XCTAssertTrue(desc.contains("CALLEE"))
    }
}
