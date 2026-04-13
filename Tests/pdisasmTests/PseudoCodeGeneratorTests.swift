import XCTest
@testable import pdisasm

final class PseudoCodeGeneratorTests: XCTestCase {

    private func makeGenerator(
        procs: [ProcedureIdentifier] = [],
        labels: [Location] = []
    ) -> PseudoCodeGenerator {
        return PseudoCodeGenerator(
            allProcedures: procs,
            allLocations: Set(labels)
        )
    }

    // MARK: - STO generates assignment

    func testSTOAssignment() {
        var stack = StackSimulator()
        stack.push(("DEST", "POINTER"))
        stack.push(("42", "INTEGER"))
        let inst = Instruction(opcode: sto, mnemonic: "STO")
        let gen = makeGenerator()
        let result = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        XCTAssertEqual(result, "DEST := 42")
    }

    // MARK: - MOV generates assignment

    func testMOVAssignment() {
        var stack = StackSimulator()
        stack.push(("DST", "POINTER"))
        stack.push(("SRC", "POINTER"))
        let inst = Instruction(opcode: mov, mnemonic: "MOV", params: [1])
        let gen = makeGenerator()
        let result = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        XCTAssertEqual(result, "DST := SRC")
    }

    // MARK: - STP (store packed field)

    func testSTPAssignment() {
        var stack = StackSimulator()
        stack.push(("BASE", "POINTER"))
        stack.push(("4", "INTEGER"))    // width
        stack.push(("2", "INTEGER"))    // bit
        stack.push(("VALUE", "INTEGER"))
        let inst = Instruction(opcode: stp, mnemonic: "STP")
        let gen = makeGenerator()
        let result = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        XCTAssertEqual(result, "BASE:4:2 := VALUE")
    }

    // MARK: - STB (store byte)

    func testSTBAssignment() {
        var stack = StackSimulator()
        stack.push(("ADDR", "POINTER"))
        stack.push(("5", "INTEGER"))    // offset
        stack.push(("X", "BYTE"))       // source
        let inst = Instruction(opcode: stb, mnemonic: "STB")
        let gen = makeGenerator()
        let result = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        XCTAssertEqual(result, "ADDR[5] := X")
    }

    // MARK: - STL with memLocation

    func testSTLWithMemLocation() {
        var stack = StackSimulator()
        stack.push(("99", "INTEGER"))
        let loc = Location(segment: 1, procedure: 1, lexLevel: 1, addr: 5)
        let inst = Instruction(opcode: stl, mnemonic: "STL", memLocation: loc)
        let gen = makeGenerator()
        let result = gen.generateForInstruction(inst, stack: &stack, loc: loc)
        XCTAssertTrue(result?.contains(":=") == true)
        XCTAssertTrue(result?.contains("99") == true)
    }

    // MARK: - STL with CHAR label converts to character literal

    func testSTLCharConversion() {
        var stack = StackSimulator()
        stack.push(("65", "INTEGER"))  // 'A'
        let loc = Location(segment: 1, procedure: 1, lexLevel: 1, addr: 5, name: "CH", type: "CHAR")
        let inst = Instruction(opcode: stl, mnemonic: "STL", memLocation: loc)
        let gen = makeGenerator(labels: [loc])
        let result = gen.generateForInstruction(inst, stack: &stack, loc: loc)
        XCTAssertEqual(result, "CH := 'A'")
    }

    // MARK: - STL with BOOLEAN label converts 0/1

    func testSTLBooleanFalse() {
        var stack = StackSimulator()
        stack.push(("0", "INTEGER"))
        let loc = Location(segment: 1, procedure: 1, lexLevel: 1, addr: 5, name: "FLAG", type: "BOOLEAN")
        let inst = Instruction(opcode: stl, mnemonic: "STL", memLocation: loc)
        let gen = makeGenerator(labels: [loc])
        let result = gen.generateForInstruction(inst, stack: &stack, loc: loc)
        XCTAssertEqual(result, "FLAG := FALSE")
    }

    func testSTLBooleanTrue() {
        var stack = StackSimulator()
        stack.push(("1", "INTEGER"))
        let loc = Location(segment: 1, procedure: 1, lexLevel: 1, addr: 5, name: "FLAG", type: "BOOLEAN")
        let inst = Instruction(opcode: stl, mnemonic: "STL", memLocation: loc)
        let gen = makeGenerator(labels: [loc])
        let result = gen.generateForInstruction(inst, stack: &stack, loc: loc)
        XCTAssertEqual(result, "FLAG := TRUE")
    }

    // MARK: - Call procedure

    func testCallProcedureGeneratesCallString() {
        var stack = StackSimulator()
        stack.push(("42", "INTEGER"))  // one argument
        let calledProc = ProcedureIdentifier(
            isFunction: false, segment: 1, segmentName: "MYSEG",
            procedure: 5, procName: "DOWORK",
            parameters: [Identifier(name: "X", type: "INTEGER")]
        )
        let dest = Location(segment: 1, procedure: 5)
        let inst = Instruction(opcode: cip, mnemonic: "CIP", destination: dest)
        let gen = makeGenerator(procs: [calledProc])
        let result = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        XCTAssertEqual(result, "MYSEG.DOWORK(42)")
    }

    func testCallFunctionPushesResult() {
        var stack = StackSimulator()
        // Function calls expect return space + something on stack
        stack.push(("retspace", "INTEGER"))  // return space
        stack.push(("retspace2", "INTEGER")) // second return word
        stack.push(("10", "INTEGER"))        // argument
        let calledFunc = ProcedureIdentifier(
            isFunction: true, segment: 1, segmentName: "MYSEG",
            procedure: 3, procName: "CALC",
            parameters: [Identifier(name: "N", type: "INTEGER")],
            returnType: "INTEGER"
        )
        let dest = Location(segment: 1, procedure: 3)
        let inst = Instruction(opcode: cip, mnemonic: "CIP", destination: dest)
        let gen = makeGenerator(procs: [calledFunc])
        let result = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        // Function calls return nil (push result to stack instead)
        XCTAssertNil(result)
        // Stack should have the function call expression
        XCTAssertEqual(stack.stack.count, 1)
        let (val, _) = stack.pop()
        XCTAssertTrue(val.contains("MYSEG.CALC"))
    }

    func testCallWithMissingDestination() {
        var stack = StackSimulator()
        let inst = Instruction(opcode: cip, mnemonic: "CIP")
        // No destination set
        let gen = makeGenerator()
        let result = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        XCTAssertEqual(result, "missing destination!")
    }

    // MARK: - Unhandled opcode returns nil

    func testUnhandledOpcodeReturnsNil() {
        var stack = StackSimulator()
        let inst = Instruction(opcode: 0x82, mnemonic: "ADI") // ADI is not in the generator
        let gen = makeGenerator()
        let result = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        XCTAssertNil(result)
    }
}
