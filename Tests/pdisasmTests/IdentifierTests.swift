import XCTest
@testable import pdisasm

final class IdentifierTests: XCTestCase {

    // MARK: - description

    func testDescriptionWithType() {
        let id = Identifier(name: "FOO", type: "INTEGER")
        XCTAssertEqual(id.description, "FOO:INTEGER")
    }

    func testDescriptionWithEmptyType() {
        let id = Identifier(name: "BAR", type: "")
        XCTAssertEqual(id.description, "BAR")
    }

    // MARK: - Equality

    func testEqualityByNameAndType() {
        let a = Identifier(name: "X", type: "INT")
        let b = Identifier(name: "X", type: "INT")
        XCTAssertEqual(a, b)
    }

    func testInequalityByType() {
        let a = Identifier(name: "X", type: "INT")
        let b = Identifier(name: "X", type: "CHAR")
        XCTAssertNotEqual(a, b)
    }

    func testInequalityByName() {
        let a = Identifier(name: "X", type: "INT")
        let b = Identifier(name: "Y", type: "INT")
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Hashing

    func testHashableInSet() {
        let a = Identifier(name: "X", type: "INT")
        let b = Identifier(name: "X", type: "INT")
        let set: Set<Identifier> = [a, b]
        XCTAssertEqual(set.count, 1)
    }

    func testDifferentIdentifiersInSet() {
        let a = Identifier(name: "X", type: "INT")
        let b = Identifier(name: "Y", type: "INT")
        let set: Set<Identifier> = [a, b]
        XCTAssertEqual(set.count, 2)
    }
}
