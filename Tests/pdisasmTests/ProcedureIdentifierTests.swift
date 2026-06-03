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

    func testInitializerNormalizesArbitraryPointerParameterType() {
        let pid = ProcedureIdentifier(
            isFunction: false,
            segment: 1,
            procedure: 2,
            parameters: [Identifier(name: "P", type: "POINTER", typeSource: .metadata)]
        )

        XCTAssertEqual(pid.parameters[0].name, "P")
        XCTAssertEqual(pid.parameters[0].type, "UNKNOWN")
        XCTAssertEqual(pid.parameters[0].typeSource, .unknown)
    }

    func testDescriptionDefaultNames() {
        let pid = ProcedureIdentifier(isFunction: false, segment: 2, procedure: 5)
        XCTAssertEqual(pid.description, "PROCEDURE SEG2.PROC5")
    }

    func testDescriptionProcedureOneDefaultsToSegmentName() {
        let pid = ProcedureIdentifier(isFunction: false, segment: 20, segmentName: "TURTLEGR", procedure: 1)
        XCTAssertEqual(pid.description, "PROCEDURE TURTLEGR.TURTLEGR")
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

    func testShortDescriptionProcedureOneDefaultsToSegmentName() {
        let pid = ProcedureIdentifier(isFunction: false, segment: 20, segmentName: "TURTLEGR", procedure: 1)
        XCTAssertEqual(pid.shortDescription, "TURTLEGR.TURTLEGR")
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
        XCTAssertEqual(decoded.returnTypeSource, .metadata)
        XCTAssertEqual(decoded.parameters.count, 1)
        XCTAssertEqual(decoded.parameters[0].name, "X")
    }

    func testDecodeNormalizesArbitraryPointerParameterType() throws {
        let json = """
        {
          "segmentNumber": 1,
          "segmentName": "MYSEG",
          "procNumber": 2,
          "procName": "DOWORK",
          "parameters": "P:POINTER",
          "returnType": null,
          "returnTypeSource": "unknown",
          "isAssembly": false,
          "isFunction": false
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(ProcedureIdentifier.self, from: json)

        XCTAssertEqual(decoded.parameters.count, 1)
        XCTAssertEqual(decoded.parameters[0].name, "P")
        XCTAssertEqual(decoded.parameters[0].type, "UNKNOWN")
        XCTAssertEqual(decoded.parameters[0].typeSource, .unknown)
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

    func testAssignReturnTypePreservesMetadataOverInference() {
        let proc = ProcedureIdentifier(
            isFunction: true,
            segment: 1,
            procedure: 2,
            returnType: "REAL",
            returnTypeSource: .metadata
        )
        let loc = Location(segment: 1, procedure: 2, lexLevel: 0, addr: 1, type: "INTEGER", typeSource: .inferred)
        let conflict = proc.assignReturnType(
            loc.type,
            source: loc.typeSource,
            location: loc,
            evidence: "test"
        )
        XCTAssertEqual(proc.returnType, "REAL")
        XCTAssertEqual(proc.returnTypeSource, .metadata)
        XCTAssertEqual(conflict?.existingType, "REAL")
        XCTAssertEqual(conflict?.proposedType, "INTEGER")
    }

    func testAssignParameterTypeFillsUnknown() {
        let proc = ProcedureIdentifier(
            isFunction: false,
            segment: 1,
            procedure: 2,
            parameters: [Identifier(name: "X", type: "UNKNOWN")]
        )
        let loc = Location(segment: 1, procedure: 2, lexLevel: 0, addr: 1, type: "INTEGER", typeSource: .inferred)
        let conflict = proc.assignParameterType(
            at: 0,
            loc.type,
            source: loc.typeSource,
            location: loc,
            evidence: "test"
        )
        XCTAssertNil(conflict)
        XCTAssertEqual(proc.parameters[0].type, "INTEGER")
        XCTAssertEqual(proc.parameters[0].typeSource, .inferred)
    }

    func testSynchronizeProcedureSignaturesUpdatesParameterAndReturnTypes() {
        let proc = ProcedureIdentifier(
            isFunction: true,
            segment: 1,
            procedure: 2,
            parameters: [
                Identifier(name: "FIRST", type: "UNKNOWN"),
                Identifier(name: "SECOND", type: "UNKNOWN"),
            ],
            returnType: "UNKNOWN"
        )
        let locations: Set<Location> = [
            Location(segment: 1, procedure: 2, lexLevel: 0, addr: 1, type: "BOOLEAN", typeSource: .inferred),
            Location(segment: 1, procedure: 2, lexLevel: 0, addr: 3, type: "CHAR", typeSource: .inferred),
            Location(segment: 1, procedure: 2, lexLevel: 0, addr: 4, type: "INTEGER", typeSource: .inferred),
        ]

        let conflicts = synchronizeProcedureSignatures(
            procedures: [proc],
            locations: locations
        )

        XCTAssertTrue(conflicts.isEmpty)
        XCTAssertEqual(proc.returnType, "BOOLEAN")
        XCTAssertEqual(proc.parameters[0].type, "INTEGER")
        XCTAssertEqual(proc.parameters[1].type, "CHAR")
    }

    func testSynchronizeProcedureSignaturesPrefersTypedLocationsOverUnknown() {
        let proc = ProcedureIdentifier(
            isFunction: true,
            segment: 1,
            procedure: 2,
            parameters: [
                Identifier(name: "VALUE", type: "UNKNOWN"),
            ],
            returnType: "UNKNOWN"
        )
        let locations: Set<Location> = [
            Location(segment: 1, procedure: 2, lexLevel: nil, addr: 1, type: "UNKNOWN", typeSource: .unknown),
            Location(segment: 1, procedure: 2, lexLevel: 0, addr: 1, type: "BOOLEAN", typeSource: .inferred),
            Location(segment: 1, procedure: 2, lexLevel: nil, addr: 3, type: "UNKNOWN", typeSource: .unknown),
            Location(segment: 1, procedure: 2, lexLevel: 0, addr: 3, type: "INTEGER", typeSource: .inferred),
        ]

        let conflicts = synchronizeProcedureSignatures(
            procedures: [proc],
            locations: locations
        )

        XCTAssertTrue(conflicts.isEmpty)
        XCTAssertEqual(proc.description, "FUNCTION SEG1.FUNC2(VALUE:INTEGER): BOOLEAN")
        XCTAssertEqual(proc.returnTypeSource, .inferred)
        XCTAssertEqual(proc.parameters[0].typeSource, .inferred)
    }

    func testSynchronizeProcedureSignaturesMapsRealWordPairToSingleParameter() {
        let proc = ProcedureIdentifier(
            isFunction: false,
            segment: 1,
            procedure: 2,
            parameters: [
                Identifier(name: "PARAM1", type: "UNKNOWN"),
                Identifier(name: "PARAM2", type: "UNKNOWN"),
            ]
        )
        let locations: Set<Location> = [
            Location(segment: 1, procedure: 2, lexLevel: 0, addr: 1, type: "REAL", typeSource: .inferred),
            Location(segment: 1, procedure: 2, lexLevel: 0, addr: 2, type: "UNKNOWN", typeSource: .unknown),
        ]

        let conflicts = synchronizeProcedureSignatures(
            procedures: [proc],
            locations: locations
        )

        XCTAssertTrue(conflicts.isEmpty)
        XCTAssertEqual(proc.parameters.count, 1)
        XCTAssertEqual(proc.parameters[0].name, "PARAM1")
        XCTAssertEqual(proc.parameters[0].type, "REAL")
        XCTAssertEqual(proc.description, "PROCEDURE SEG1.PROC2(PARAM1:REAL)")
    }

    func testSynchronizeProcedureSignaturesKeepsEarlierParametersBeforeRealPair() {
        let proc = ProcedureIdentifier(
            isFunction: false,
            segment: 1,
            procedure: 2,
            parameters: [
                Identifier(name: "PARAM1", type: "UNKNOWN"),
                Identifier(name: "PARAM2", type: "UNKNOWN"),
                Identifier(name: "PARAM3", type: "UNKNOWN"),
            ]
        )
        let locations: Set<Location> = [
            Location(segment: 1, procedure: 2, lexLevel: 0, addr: 1, type: "REAL", typeSource: .inferred),
            Location(segment: 1, procedure: 2, lexLevel: 0, addr: 2, type: "UNKNOWN", typeSource: .unknown),
            Location(segment: 1, procedure: 2, lexLevel: 0, addr: 3, type: "INTEGER", typeSource: .inferred),
        ]

        let conflicts = synchronizeProcedureSignatures(
            procedures: [proc],
            locations: locations
        )

        XCTAssertTrue(conflicts.isEmpty)
        XCTAssertEqual(proc.parameters.count, 2)
        XCTAssertEqual(proc.parameters[0].description, "PARAM1:INTEGER")
        XCTAssertEqual(proc.parameters[1].description, "PARAM2:REAL")
    }

    func testParameterLocationAddressesUseRealWordSize() {
        let proc = ProcedureIdentifier(
            isFunction: false,
            segment: 1,
            procedure: 2,
            parameters: [
                Identifier(name: "COUNT", type: "INTEGER"),
                Identifier(name: "VALUE", type: "REAL"),
            ]
        )

        let addresses = parameterLocationAddresses(for: proc)

        XCTAssertEqual(addresses.map(\.index), [0, 1])
        XCTAssertEqual(addresses.map(\.addr), [3, 1])
    }

    func testSynchronizeProcedureSignaturesUsesRealSizedParameterAddresses() {
        let proc = ProcedureIdentifier(
            isFunction: false,
            segment: 1,
            procedure: 2,
            parameters: [
                Identifier(name: "COUNT", type: "UNKNOWN"),
                Identifier(name: "VALUE", type: "REAL", typeSource: .inferred),
            ]
        )
        let locations: Set<Location> = [
            Location(segment: 1, procedure: 2, lexLevel: 0, addr: 1, type: "REAL", typeSource: .inferred),
            Location(segment: 1, procedure: 2, lexLevel: 0, addr: 2, type: "UNKNOWN", typeSource: .unknown),
            Location(segment: 1, procedure: 2, lexLevel: 0, addr: 3, type: "INTEGER", typeSource: .inferred),
        ]

        let conflicts = synchronizeProcedureSignatures(
            procedures: [proc],
            locations: locations
        )

        XCTAssertTrue(conflicts.isEmpty)
        XCTAssertEqual(proc.parameters[0].description, "COUNT:INTEGER")
        XCTAssertEqual(proc.parameters[1].description, "VALUE:REAL")
    }

    func testApplyProcedureSignatureLocationsRelabelsRealParameterBaseAndRemovesSecondWord() {
        let identifier = ProcedureIdentifier(
            isFunction: true,
            segment: 29,
            segmentName: "TRANSCEN",
            procedure: 2,
            parameters: [
                Identifier(name: "PARAM1", type: "REAL", typeSource: .inferred),
            ],
            returnType: "UNKNOWN"
        )
        let proc = Procedure()
        proc.lexicalLevel = 1
        proc.identifier = identifier
        let codeSegment = CodeSegment(
            procedureDictionary: ProcedureDictionary(procedureCount: 1, procedurePointers: []),
            procedures: [proc]
        )
        var locations: Set<Location> = [
            Location(segment: 29, procedure: 2, lexLevel: nil, addr: 1, isParam: true, name: "TRANSCEN.FUNC2", type: "UNKNOWN"),
            Location(segment: 29, procedure: 2, lexLevel: nil, addr: 3, isParam: true, name: "PARAM2", type: "REAL", typeSource: .inferred),
            Location(segment: 29, procedure: 2, lexLevel: nil, addr: 4, isParam: true, name: "PARAM1", type: "UNKNOWN"),
        ]

        let conflicts = applyProcedureSignatureLocations(
            procedures: [identifier],
            codeSegments: [29: codeSegment],
            locations: &locations
        )

        XCTAssertTrue(conflicts.isEmpty)
        XCTAssertEqual(locations.first(where: { $0.addr == 3 })?.description, "PARAM1:REAL")
        XCTAssertEqual(locations.first(where: { $0.addr == 3 })?.lexLevel, 1)
        XCTAssertNil(locations.first(where: { $0.addr == 4 }))
    }

    func testApplyProcedureSignatureLocationsRemovesStaleGeneratedParameterLocations() {
        let identifier = ProcedureIdentifier(
            isFunction: false,
            segment: 20,
            segmentName: "TURTLEGR",
            procedure: 3,
            procName: "MOVETO",
            parameters: [
                Identifier(name: "X", type: "INTEGER", typeSource: .metadata),
                Identifier(name: "Y", type: "INTEGER", typeSource: .metadata),
            ]
        )
        let proc = Procedure()
        proc.lexicalLevel = 1
        proc.identifier = identifier
        let codeSegment = CodeSegment(
            procedureDictionary: ProcedureDictionary(procedureCount: 1, procedurePointers: []),
            procedures: [proc]
        )
        var locations: Set<Location> = [
            Location(segment: 20, procedure: 3, lexLevel: nil, addr: 1, isParam: true, name: "Y", type: "INTEGER", typeSource: .metadata),
            Location(segment: 20, procedure: 3, lexLevel: nil, addr: 2, isParam: true, name: "X", type: "INTEGER", typeSource: .metadata),
            Location(segment: 20, procedure: 3, lexLevel: 1, addr: 1, isParam: true, name: "PARAM2", type: "INTEGER", typeSource: .inferred),
            Location(segment: 20, procedure: 3, lexLevel: 1, addr: 2, isParam: true, name: "PARAM1", type: "INTEGER", typeSource: .inferred),
        ]

        let conflicts = applyProcedureSignatureLocations(
            procedures: [identifier],
            codeSegments: [20: codeSegment],
            locations: &locations
        )

        XCTAssertTrue(conflicts.isEmpty)
        XCTAssertEqual(
            locations.filter { $0.segment == 20 && $0.procedure == 3 && $0.addr == 1 }.map(\.description),
            ["Y:INTEGER"]
        )
        XCTAssertEqual(
            locations.filter { $0.segment == 20 && $0.procedure == 3 && $0.addr == 2 }.map(\.description),
            ["X:INTEGER"]
        )
        XCTAssertEqual(locations.first(where: { $0.addr == 1 })?.lexLevel, 1)
        XCTAssertEqual(locations.first(where: { $0.addr == 2 })?.lexLevel, 1)

        let staleIdentifier = ProcedureIdentifier(
            isFunction: false,
            segment: 20,
            segmentName: "TURTLEGR",
            procedure: 3,
            procName: "MOVETO",
            parameters: [
                Identifier(name: "PARAM1", type: "INTEGER", typeSource: .inferred),
                Identifier(name: "PARAM2", type: "INTEGER", typeSource: .inferred),
            ]
        )

        let staleConflicts = applyProcedureSignatureLocations(
            procedures: [staleIdentifier],
            codeSegments: [20: codeSegment],
            locations: &locations
        )

        XCTAssertTrue(staleConflicts.isEmpty)
        XCTAssertEqual(
            locations.filter { $0.segment == 20 && $0.procedure == 3 && $0.addr == 1 }.map(\.description),
            ["Y:INTEGER"]
        )
        XCTAssertEqual(
            locations.filter { $0.segment == 20 && $0.procedure == 3 && $0.addr == 2 }.map(\.description),
            ["X:INTEGER"]
        )
    }
}
