import XCTest
@testable import pdisasm

final class StackSimulatorTests: XCTestCase {

    // MARK: - Push / Pop basics

    func testPushAndPopWithType() {
        var sim = StackSimulator()
        sim.push(("42", "INTEGER"))
        let (val, typ) = sim.pop()
        XCTAssertEqual(val, "42")
        XCTAssertEqual(typ, "INTEGER")
    }

    func testPushNilTypeDefaultsToUNKNOWN() {
        var sim = StackSimulator()
        sim.push(("x", nil))
        let (val, typ) = sim.pop()
        XCTAssertEqual(val, "x")
        XCTAssertEqual(typ, "UNKNOWN")
    }

    func testPopFromEmptyStackReturnsUnderflow() {
        var sim = StackSimulator()
        let (val, _) = sim.pop()
        XCTAssertEqual(val, "underflow!")
    }

    // MARK: - Typed pop with UNKNOWN replacement

    func testTypedPopReplacesUNKNOWN() {
        var sim = StackSimulator()
        sim.push(("x", nil)) // stored as UNKNOWN
        let (_, typ) = sim.pop("BOOLEAN")
        XCTAssertEqual(typ, "BOOLEAN")
    }

    func testTypedPopKeepsExistingType() {
        var sim = StackSimulator()
        sim.push(("x", "CHAR"))
        let (_, typ) = sim.pop("INTEGER")
        XCTAssertEqual(typ, "CHAR") // should NOT be replaced
    }

    // MARK: - Parenthesization

    func testPopParenthesizesSpacedValues() {
        var sim = StackSimulator()
        sim.push(("a + b", "INTEGER"))
        let (val, _) = sim.pop()
        XCTAssertEqual(val, "(a + b)")
    }

    func testPopWithoutParenthesesFlag() {
        var sim = StackSimulator()
        sim.push(("a + b", "INTEGER"))
        let (val, _) = sim.pop(true)
        XCTAssertEqual(val, "a + b")
    }

    func testPopStringTypeNotParenthesized() {
        var sim = StackSimulator()
        sim.push(("hello world", "STRING"))
        let (val, _) = sim.pop()
        XCTAssertEqual(val, "hello world") // STRING type skips parens
    }

    // MARK: - Peek

    func testPeekDoesNotRemove() {
        var sim = StackSimulator()
        sim.push(("42", "INTEGER"))
        let (val, typ) = sim.peek()
        XCTAssertEqual(val, "42")
        XCTAssertEqual(typ, "INTEGER")
        XCTAssertEqual(sim.values.count, 1)
    }

    func testPushTracksValueKind() {
        var sim = StackSimulator()
        sim.push(("ADDR", "INTEGER"), kind: .address)
        XCTAssertEqual(sim.peekStackValue().kind, .address)
        let value = sim.popStackValue()
        XCTAssertEqual(value.text, "ADDR")
        XCTAssertEqual(value.kind, .address)
        XCTAssertTrue(sim.values.isEmpty)
    }

    func testAddressValuePopsAsPascalPointerToVariable() {
        var sim = StackSimulator()
        sim.push(("ADDR", "INTEGER"), kind: .address)

        let (value, type) = sim.pop()

        XCTAssertEqual(value, "^ADDR")
        XCTAssertEqual(type, "INTEGER")
    }

    func testAddressDestinationStillStoresIntoVariable() {
        let sim = StackSimulator()
        let target = StackValue(text: "ADDR", type: "INTEGER", kind: .address)

        XCTAssertEqual(sim.assignmentTargetText(target), "ADDR")
    }

    func testPointerDestinationDereferencesWithPascalSyntax() {
        let sim = StackSimulator()
        let target = StackValue(text: "PTR", type: "^INTEGER", kind: .pointer)

        XCTAssertEqual(sim.assignmentTargetText(target), "PTR^")
    }

    func testStackDescriptionIncludesStackValueFields() {
        let loc = Location(segment: 1, procedure: 2, lexLevel: 3, addr: 4)
        var sim = StackSimulator()
        sim.push(("ADDR", "INTEGER"), kind: .address, location: loc)

        XCTAssertEqual(
            sim.stackDescription,
            ["{V: ADDR, T: INTEGER, K: a, L: S1_P2_L3_A4}"]
        )
    }

    func testPeekEmptyStackReturnsUnderflow() {
        let sim = StackSimulator()
        let (val, _) = sim.peek()
        XCTAssertEqual(val, "underflow!")
    }

    // MARK: - push real / popReal

    func testPushRealAndPopReal() {
        var sim = StackSimulator()
        sim.push(("3.14", "REAL"))
        let (val, typ) = sim.popReal()
        XCTAssertEqual(val, "3.14")
        XCTAssertEqual(typ, "REAL")
    }

    func testPopRealMergesTwoUntypedWords() {
        var sim = StackSimulator()
        sim.push(StackValue(text: "hello", type: nil, kind: .value))
        sim.push(StackValue(text: "world", type: nil, kind: .value))
        let (val, typ) = sim.popReal()
        XCTAssertEqual(val, "world.hello")
        XCTAssertEqual(typ, "REAL")
    }

    func testPopRealMergesRealWordRepresentationAccesses() {
        var sim = StackSimulator()
        sim.push(StackValue(text: "REAL_WORD(X, 0)", type: "INTEGER", kind: .value))
        sim.push(StackValue(text: "REAL_WORD(X, 1)", type: "INTEGER", kind: .value))

        let (val, typ) = sim.popReal()

        XCTAssertEqual(val, "X")
        XCTAssertEqual(typ, "REAL")
    }

    func testPopRealMergesSameBaseRealWordLocationAccesses() {
        var sim = StackSimulator()
        sim.push(StackValue(text: "REAL_WORD(S29_P4_L1_A6, 0)", type: "INTEGER", kind: .value))
        sim.push(StackValue(text: "REAL_WORD(S29_P4_L1_A6, 1)", type: "INTEGER", kind: .value))

        let (val, typ) = sim.popReal()

        XCTAssertEqual(val, "S29_P4_L1_A6")
        XCTAssertEqual(typ, "REAL")
    }

    func testPopRealMergesRealWordAdjacentLocationAccesses() {
        var sim = StackSimulator()
        sim.push(StackValue(text: "REAL_WORD(S29_P4_L1_A8, 0)", type: "INTEGER", kind: .value))
        sim.push(StackValue(text: "REAL_WORD(S29_P4_L1_A9, 1)", type: "INTEGER", kind: .value))

        let (val, typ) = sim.popReal()

        XCTAssertEqual(val, "S29_P4_L1_A8")
        XCTAssertEqual(typ, "REAL")
    }

    func testPopRealMergesStructuredRealWordPayloads() {
        let base = Location(segment: 29, procedure: 4, lexLevel: 1, addr: 8)
        let secondWord = Location(segment: 29, procedure: 4, lexLevel: 1, addr: 9)
        var sim = StackSimulator()
        sim.push(StackValue(
            text: "opaque-low",
            type: "INTEGER",
            kind: .value,
            location: base,
            payload: .realWord(
                baseText: "X",
                wordIndex: 0,
                baseLocation: base,
                physicalLocation: base
            )
        ))
        sim.push(StackValue(
            text: "opaque-high",
            type: "INTEGER",
            kind: .value,
            location: secondWord,
            payload: .realWord(
                baseText: "X",
                wordIndex: 1,
                baseLocation: base,
                physicalLocation: secondWord
            )
        ))

        let (val, typ) = sim.popReal()

        XCTAssertEqual(val, "S29_P4_L1_A8")
        XCTAssertEqual(typ, "REAL")
    }

    // MARK: - popSet

    func testPopSetNumericWithRanges() {
        var sim = StackSimulator()
        // Push a set: element word with bits 0,1,2,4 set = 0b10111 = 23
        // Then length = 1
        sim.push(("23", "INTEGER")) // element word
        sim.push(("1", "INTEGER"))  // set length
        let (len, str) = sim.popSet()
        XCTAssertEqual(len, 1)
        // bits 0,1,2 -> 0..2 and bit 4 -> 4
        XCTAssertTrue(str.contains("0..2"))
        XCTAssertTrue(str.contains("4"))
    }

    func testPopSetValueTracksNumericLiteralRanges() {
        var sim = StackSimulator()
        sim.push(("23", "INTEGER"))
        sim.push(("1", "INTEGER"))

        let set = sim.popSetValue()

        XCTAssertEqual(set.wordCount, 1)
        XCTAssertTrue(set.isLiteral)
        XCTAssertEqual(set.sourceText, "[0..2, 4]")
        XCTAssertEqual(set.legacyText, "[0..2, 4]")
        XCTAssertEqual(set.elements, [
            PascalSetElement(lower: "0", upper: "2"),
            PascalSetElement("4")
        ])
        XCTAssertTrue(set.wordFragments.isEmpty)
    }

    func testPopSetWithSymbolicElements() {
        var sim = StackSimulator()
        sim.push(("MYVAR", "SET"))
        sim.push(("1", "INTEGER")) // length
        let (len, str) = sim.popSet()
        XCTAssertEqual(len, 1)
        XCTAssertTrue(str.contains("MYVAR"))
    }

    func testPopSetValueTracksSymbolicLiteralSeparatelyFromLegacyText() {
        var sim = StackSimulator()
        sim.push(("MYVAR", "SET"))
        sim.push(("1", "INTEGER"))

        let set = sim.popSetValue()

        XCTAssertEqual(set.wordCount, 1)
        XCTAssertTrue(set.isLiteral)
        XCTAssertEqual(set.sourceText, "[MYVAR]")
        XCTAssertEqual(set.legacyText, "MYVAR")
        XCTAssertEqual(set.elements, [PascalSetElement("MYVAR")])
        XCTAssertTrue(set.wordFragments.isEmpty)
    }

    func testPopSetArrayElements() {
        var sim = StackSimulator()
        // Two elements from same array
        sim.push(("DATA{0}", "SET"))
        sim.push(("DATA{1}", "SET"))
        sim.push(("2", "INTEGER")) // length
        let (len, str) = sim.popSet()
        XCTAssertEqual(len, 2)
        // Should only contain the array name once
        XCTAssertEqual(str, "DATA")
    }

    func testPopSetValueTracksWordFragmentsSeparatelyFromLiterals() {
        var sim = StackSimulator()
        sim.push(("DATA{0}", "SET"))
        sim.push(("DATA{1}", "SET"))
        sim.push(("2", "INTEGER"))

        let set = sim.popSetValue()

        XCTAssertEqual(set.wordCount, 2)
        XCTAssertFalse(set.isLiteral)
        XCTAssertEqual(set.sourceText, "DATA")
        XCTAssertEqual(set.legacyText, "DATA")
        XCTAssertTrue(set.elements.isEmpty)
        XCTAssertEqual(set.wordFragments, [
            PascalSetWordFragment(baseText: "DATA", wordIndex: 1, text: "DATA{1}"),
            PascalSetWordFragment(baseText: "DATA", wordIndex: 0, text: "DATA{0}")
        ])
    }

    func testPopSetMalformed() {
        var sim = StackSimulator()
        sim.push(("notanumber", "STRING"))
        let (len, str) = sim.popSet()
        XCTAssertEqual(len, 0)
        XCTAssertEqual(str, "Set has no length!")
    }

    func testPopSetValueMalformed() {
        var sim = StackSimulator()
        sim.push(("notanumber", "STRING"))

        let set = sim.popSetValue()

        XCTAssertEqual(set.wordCount, 0)
        XCTAssertTrue(set.isMalformed)
        XCTAssertEqual(set.sourceText, "Set has no length!")
        XCTAssertEqual(set.legacyText, "Set has no length!")
    }

    func testPushSetValueRoundTripsStructuredPayload() {
        let original = PascalSetValue.literal([
            PascalSetElement("1"),
            PascalSetElement(lower: "3", upper: "5")
        ])
        var sim = StackSimulator()
        sim.pushSetValue(original)

        let set = sim.popSetValue()

        XCTAssertEqual(set, original)
        XCTAssertEqual(set.sourceText, "[1, 3..5]")
    }
}
