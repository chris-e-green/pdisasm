import XCTest
@testable import pdisasm

final class PascalTypeTests: XCTestCase {
    func testParsesAndRendersBuiltInTypes() {
        let type = PascalType.parse("integer")

        XCTAssertEqual(type, .builtIn(.integer))
        XCTAssertEqual(type.renderedType, "INTEGER")
    }

    func testParsesAndRendersNamedTypes() {
        let type = PascalType.parse("itemref")

        XCTAssertEqual(type, .named("ITEMREF"))
        XCTAssertEqual(type.renderedType, "ITEMREF")
    }

    func testParsesAndRendersEnumeratedTypes() {
        let type = PascalType.parse("(linked, hostseg, segproc)")

        XCTAssertEqual(type, .enumerated(PascalEnumeratedType(cases: ["LINKED", "HOSTSEG", "SEGPROC"])))
        XCTAssertEqual(type.renderedType, "(LINKED, HOSTSEG, SEGPROC)")
    }

    func testParsesAndRendersSubrangeTypes() {
        let type = PascalType.parse("1..MAXSEGS")

        XCTAssertEqual(type, .subrange(PascalSubrangeTypeReference(lowerBound: "1", upperBound: "MAXSEGS")))
        XCTAssertEqual(type.renderedType, "1..MAXSEGS")
    }

    func testParsesAndRendersPointerTypes() {
        let type = PascalType.parse("^item")

        XCTAssertEqual(type, .pointer(PascalPointerType(pointee: .named("ITEM"))))
        XCTAssertEqual(type.renderedType, "^ITEM")
    }

    func testParsesAndRendersArrayTypes() {
        let type = PascalType.parse("ARRAY[1..8, 0..3] OF WORD")

        XCTAssertEqual(type.renderedType, "ARRAY[1..8, 0..3] OF WORD")
        guard case .array(let arrayType) = type else {
            return XCTFail("Expected array type")
        }
        XCTAssertFalse(arrayType.isPacked)
        XCTAssertEqual(arrayType.indexTypes, [
            .subrange(PascalSubrangeTypeReference(lowerBound: "1", upperBound: "8")),
            .subrange(PascalSubrangeTypeReference(lowerBound: "0", upperBound: "3")),
        ])
        XCTAssertEqual(arrayType.elementType, .builtIn(.word))
    }

    func testParsesAndRendersPackedArrayTypes() {
        let type = PascalType.parse("PACKED ARRAY[1..C1] OF CHAR")

        XCTAssertEqual(type.renderedType, "PACKED ARRAY[1..C1] OF CHAR")
        guard case .array(let arrayType) = type else {
            return XCTFail("Expected array type")
        }
        XCTAssertTrue(arrayType.isPacked)
        XCTAssertEqual(arrayType.indexTypes, [
            .subrange(PascalSubrangeTypeReference(lowerBound: "1", upperBound: "C1")),
        ])
        XCTAssertEqual(arrayType.elementType, .builtIn(.char))
    }

    func testParsesArrayOfCompatibilityForm() {
        let type = PascalType.parse("ARRAY OF CHAR")

        XCTAssertEqual(type, .array(PascalArrayType(elementType: .builtIn(.char))))
        XCTAssertEqual(type.renderedType, "ARRAY OF CHAR")
    }

    func testParsesAndRendersRecordTypes() {
        let type = PascalType.parse("RECORD KEY: ALPHA; COUNT: INTEGER; LNO: 0..4; END")

        XCTAssertEqual(type.renderedType, "RECORD KEY: ALPHA; COUNT: INTEGER; LNO: 0..4; END")
        guard case .record(let recordType) = type else {
            return XCTFail("Expected record type")
        }
        XCTAssertFalse(recordType.isPacked)
        XCTAssertEqual(recordType.fields, [
            PascalRecordField(names: ["KEY"], type: .named("ALPHA")),
            PascalRecordField(names: ["COUNT"], type: .builtIn(.integer)),
            PascalRecordField(names: ["LNO"], type: .subrange(PascalSubrangeTypeReference(lowerBound: "0", upperBound: "4"))),
        ])
    }

    func testParsesAndRendersVariantRecordTypes() {
        let source = "PACKED RECORD KIND: INTEGER; CASE INTEGER OF 0: (IVALUE: INTEGER); 1: (RVALUE: REAL); END"
        let type = PascalType.parse(source)

        XCTAssertEqual(type.renderedType, source)
        guard case .variantRecord(let recordType) = type else {
            return XCTFail("Expected variant record type")
        }
        XCTAssertTrue(recordType.isPacked)
        XCTAssertEqual(recordType.fixedFields, [
            PascalRecordField(names: ["KIND"], type: .builtIn(.integer)),
        ])
    }

    func testParsesAndRendersSetTypes() {
        let type = PascalType.parse("SET OF SEGKINDS")

        XCTAssertEqual(type, .set(PascalSetType(elementType: .named("SEGKINDS"))))
        XCTAssertEqual(type.renderedType, "SET OF SEGKINDS")
    }

    func testParsesAndRendersFileTypes() {
        let fileType = PascalType.parse("FILE OF BYTE")
        let textType = PascalType.parse("TEXT")

        XCTAssertEqual(fileType, .file(PascalFileType(elementType: .builtIn(.byte))))
        XCTAssertEqual(fileType.renderedType, "FILE OF BYTE")
        XCTAssertEqual(textType, .file(PascalFileType(isText: true)))
        XCTAssertEqual(textType.renderedType, "TEXT")
    }

    func testParsesAndRendersStringUnknownAndRawFallbackTypes() {
        XCTAssertEqual(PascalType.parse("STRING"), .string)
        XCTAssertEqual(PascalType.parse("STRING").renderedType, "STRING")
        XCTAssertEqual(PascalType.parse("UNKNOWN"), .unknown)
        XCTAssertEqual(PascalType.parse("UNKNOWN").renderedType, "UNKNOWN")
        XCTAssertEqual(PascalType.parse("ARRAY[1..8 BYTE"), .raw("ARRAY[1..8 BYTE"))
        XCTAssertEqual(PascalType.parse("ARRAY[1..8 BYTE").renderedType, "ARRAY[1..8 BYTE")
    }

    func testRendersPackedFieldPseudoType() {
        let type = PascalType.packedField(PascalPackedFieldType(
            storageType: .builtIn(.word),
            width: 3,
            bitOffset: 5
        ))

        XCTAssertEqual(type.renderedType, "PACKED FIELD(WORD, WIDTH 3, BIT 5)")
    }
}
