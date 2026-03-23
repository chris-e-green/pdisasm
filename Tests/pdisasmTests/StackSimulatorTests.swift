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
        XCTAssertEqual(sim.stack.count, 1)
    }

    func testPeekEmptyStackReturnsUnderflow() {
        let sim = StackSimulator()
        let (val, _) = sim.peek()
        XCTAssertEqual(val, "underflow!")
    }

    // MARK: - pushReal / popReal

    func testPushRealAndPopReal() {
        var sim = StackSimulator()
        sim.pushReal("3.14")
        let (val, typ) = sim.popReal()
        XCTAssertEqual(val, "3.14")
        XCTAssertEqual(typ, "REAL")
    }

    func testPopRealMergesTwoUntypedWords() {
        var sim = StackSimulator()
        // Push two raw untyped values (no separator)
        sim.stack.append("hello")
        sim.stack.append("world")
        let (val, typ) = sim.popReal()
        XCTAssertEqual(val, "world.hello")
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
        // bits 0,1,2 -> 0...2 and bit 4 -> 4
        XCTAssertTrue(str.contains("0...2"))
        XCTAssertTrue(str.contains("4"))
    }

    func testPopSetWithSymbolicElements() {
        var sim = StackSimulator()
        sim.push(("MYVAR", "SET"))
        sim.push(("1", "INTEGER")) // length
        let (len, str) = sim.popSet()
        XCTAssertEqual(len, 1)
        XCTAssertTrue(str.contains("MYVAR"))
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
        XCTAssertEqual(str, "[DATA]")
    }

    func testPopSetMalformed() {
        var sim = StackSimulator()
        sim.push(("notanumber", "STRING"))
        let (len, str) = sim.popSet()
        XCTAssertEqual(len, 0)
        XCTAssertEqual(str, "malformed set!")
    }
}
