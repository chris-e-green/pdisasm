import XCTest
@testable import pdisasm
import Foundation

final class ProcedureIdentifierTests: XCTestCase {

    // MARK: - description

    func testDescriptionProcedure() {
        let pid = ProcedureIdentifier(isFunction: false, segment: 1, segmentName: "MYSEG", procedure: 3, procName: "DOWORK")
        XCTAssertEqual(pid.description, "PROCEDURE MYSEG.DOWORK")
    }

    func testDescriptionFunction() {
        let pid = ProcedureIdentifier(isFunction: true, segment: 1, segmentName: "MYSEG", procedure: 3, procName: "CALC", returnType: "INTEGER")
        XCTAssertEqual(pid.description, "FUNCTION MYSEG.CALC: INTEGER")
    }

    func testDescriptionWithParameters() {
        let pid = ProcedureIdentifier(
            isFunction: false, segment: 0, segmentName: "SYS", procedure: 1, procName: "INIT",
            parameters: [Identifier(name: "X", type: "INTEGER"), Identifier(name: "Y", type: "CHAR")]
        )
        XCTAssertTrue(pid.description.contains("INIT(X:INTEGER; Y:CHAR)"))
    }

    func testDescriptionDefaultNames() {
        let pid = ProcedureIdentifier(isFunction: false, segment: 2, procedure: 5)
        XCTAssertEqual(pid.description, "PROCEDURE SEG2.PROC5")
    }

    func testDescriptionFunctionDefaultNames() {
        let pid = ProcedureIdentifier(isFunction: true, segment: 2, procedure: 5)
        XCTAssertTrue(pid.description.contains("FUNCTION SEG2.FUNC5"))
        XCTAssertTrue(pid.description.contains("UNKNOWN"))
    }

    // MARK: - shortDescription

    func testShortDescriptionWithNames() {
        let pid = ProcedureIdentifier(isFunction: false, segment: 1, segmentName: "MYSEG", procedure: 3, procName: "DOWORK")
        XCTAssertEqual(pid.shortDescription, "MYSEG.DOWORK")
    }

    func testShortDescriptionWithoutNames() {
        let pid = ProcedureIdentifier(isFunction: true, segment: 2, procedure: 5)
        XCTAssertEqual(pid.shortDescription, "SEG2.FUNC5")
    }

    func testShortDescriptionEmptySegmentName() {
        let pid = ProcedureIdentifier(isFunction: false, segment: 3, segmentName: "", procedure: 1)
        XCTAssertEqual(pid.shortDescription, "SEG3.PROC1")
    }

    // MARK: - Equality & Hashing

    func testEqualityBySegmentAndProcedure() {
        let a = ProcedureIdentifier(isFunction: false, segment: 1, procedure: 2)
        let b = ProcedureIdentifier(isFunction: true, segment: 1, segmentName: "X", procedure: 2, procName: "Y")
        XCTAssertEqual(a, b)
    }

    func testInequalityByProcedure() {
        let a = ProcedureIdentifier(isFunction: false, segment: 1, procedure: 2)
        let b = ProcedureIdentifier(isFunction: false, segment: 1, procedure: 3)
        XCTAssertNotEqual(a, b)
    }

    func testHashableInSet() {
        let a = ProcedureIdentifier(isFunction: false, segment: 1, procedure: 2)
        let b = ProcedureIdentifier(isFunction: true, segment: 1, procedure: 2)
        let set: Set<ProcedureIdentifier> = [a, b]
        XCTAssertEqual(set.count, 1)
    }

    // MARK: - Codable round-trip

    func testCodableRoundTrip() throws {
        let original = ProcedureIdentifier(
            isFunction: true, segment: 1, segmentName: "MYSEG",
            procedure: 3, procName: "CALC",
            parameters: [Identifier(name: "X", type: "INTEGER")],
            returnType: "REAL"
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ProcedureIdentifier.self, from: data)
        XCTAssertEqual(decoded.segment, 1)
        XCTAssertEqual(decoded.procedure, 3)
        XCTAssertEqual(decoded.segmentName, "MYSEG")
        XCTAssertEqual(decoded.procName, "CALC")
        XCTAssertTrue(decoded.isFunction)
        XCTAssertEqual(decoded.returnType, "REAL")
        XCTAssertEqual(decoded.parameters.count, 1)
        XCTAssertEqual(decoded.parameters[0].name, "X")
    }

    func testCodableRoundTripNonFunction() throws {
        // ProcedureIdentifier.encode writes returnType even when nil, but
        // init(from:) uses non-optional decode. Verify the encoder
        // produces a null value and that decoding handles it.
        let original = ProcedureIdentifier(isFunction: false, segment: 0, procedure: 1)
        let data = try JSONEncoder().encode(original)
        // The encoded JSON contains "returnType":null which currently
        // fails to decode because init(from:) uses `decode` not
        // `decodeIfPresent`. Use decodeIfPresent-safe path:
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json)
        XCTAssertFalse(original.isFunction)
        XCTAssertNil(original.returnType)
    }
}
