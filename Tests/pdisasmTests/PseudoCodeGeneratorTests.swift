import XCTest
@testable import pdisasm

final class PseudoCodeGeneratorTests: XCTestCase {

    private func makeGenerator(
        procs: [ProcedureIdentifier] = [],
        labels: [Location] = []
    ) -> PseudoCodeGenerator {
        return PseudoCodeGenerator(
            allProcedures: procs,
            knownRecords: [],
            allLocations: Set(labels)
        )
    }

    // MARK: - STO generates assignment

    func testSTOAssignment() {
        var stack = StackSimulator()
        stack.push(("DEST", "POINTER"))
        stack.push(("42", "INTEGER"))
        let inst = Instruction(opcode: sto, mnemonic: "STO")
        var gen = makeGenerator()
        let result = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        XCTAssertEqual(result, "DEST := 42")
    }

    func testSTOUsesAddressDestinationKind() {
        var stack = StackSimulator()
        stack.push(("DEST", "INTEGER"), kind: .address)
        stack.push(("42", "INTEGER"), kind: .constant)
        let inst = Instruction(opcode: sto, mnemonic: "STO")
        var gen = makeGenerator()
        let result = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        XCTAssertEqual(result, "DEST := 42")
        XCTAssertTrue(stack.stack.isEmpty)
    }

    // MARK: - MOV generates assignment

    func testMOVAssignment() {
        var stack = StackSimulator()
        stack.push(("DST", "POINTER"))
        stack.push(("SRC", "POINTER"))
        let inst = Instruction(opcode: mov, mnemonic: "MOV", params: [1])
        var gen = makeGenerator()
        let result = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        XCTAssertEqual(result, "DST := SRC")
    }

    func testMOVUsesAddressDestinationAndValueSourceKinds() {
        var stack = StackSimulator()
        stack.push(("DST", "POINTER"), kind: .address)
        stack.push(("SRC", "INTEGER"), kind: .value)
        let inst = Instruction(opcode: mov, mnemonic: "MOV", params: [1])
        var gen = makeGenerator()
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
        var gen = makeGenerator()
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
        var gen = makeGenerator()
        let result = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        XCTAssertEqual(result, "ADDR[5] := X")
    }

    func testSTBUsesAddressDestinationKind() {
        var stack = StackSimulator()
        stack.push(("ADDR", "POINTER"), kind: .address)
        stack.push(("5", "INTEGER"), kind: .constant)
        stack.push(("88", "BYTE"), kind: .constant)
        let inst = Instruction(opcode: stb, mnemonic: "STB")
        var gen = makeGenerator()
        let result = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        XCTAssertEqual(result, "ADDR[5] := 88")
    }

    // MARK: - STL with memLocation

    func testSTLWithMemLocation() {
        var stack = StackSimulator()
        stack.push(("99", "INTEGER"))
        let loc = Location(segment: 1, procedure: 1, lexLevel: 1, addr: 5)
        let inst = Instruction(opcode: stl, mnemonic: "STL", memLocation: loc)
        var gen = makeGenerator()
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
        var gen = makeGenerator(labels: [loc])
        let result = gen.generateForInstruction(inst, stack: &stack, loc: loc)
        XCTAssertEqual(result, "CH := 'A'")
    }

    // MARK: - STL with BOOLEAN label converts 0/1

    func testSTLBooleanFalse() {
        var stack = StackSimulator()
        stack.push(("0", "INTEGER"))
        let loc = Location(segment: 1, procedure: 1, lexLevel: 1, addr: 5, name: "FLAG", type: "BOOLEAN")
        let inst = Instruction(opcode: stl, mnemonic: "STL", memLocation: loc)
        var gen = makeGenerator(labels: [loc])
        let result = gen.generateForInstruction(inst, stack: &stack, loc: loc)
        XCTAssertEqual(result, "FLAG := FALSE")
    }

    func testSTLBooleanTrue() {
        var stack = StackSimulator()
        stack.push(("1", "INTEGER"))
        let loc = Location(segment: 1, procedure: 1, lexLevel: 1, addr: 5, name: "FLAG", type: "BOOLEAN")
        let inst = Instruction(opcode: stl, mnemonic: "STL", memLocation: loc)
        var gen = makeGenerator(labels: [loc])
        let result = gen.generateForInstruction(inst, stack: &stack, loc: loc)
        XCTAssertEqual(result, "FLAG := TRUE")
    }

    func testInferredTypeDoesNotOverrideMetadataType() {
        let loc = Location(segment: 1, procedure: 1, lexLevel: 1, addr: 5, name: "VALUE", type: "REAL", typeSource: .metadata)
        var gen = makeGenerator(labels: [loc])
        gen.setLocType("S1_P1_L1_A5", "INTEGER", evidence: "test inference")
        XCTAssertEqual(loc.type, "REAL")
        XCTAssertEqual(loc.typeSource, .metadata)
        XCTAssertEqual(gen.typeConflicts.count, 1)
        XCTAssertEqual(gen.typeConflicts.first?.existingType, "REAL")
        XCTAssertEqual(gen.typeConflicts.first?.proposedType, "INTEGER")
    }

    func testInferredTypeFillsUnknownType() {
        let loc = Location(segment: 1, procedure: 1, lexLevel: 1, addr: 5, name: "VALUE")
        var gen = makeGenerator(labels: [loc])
        gen.setLocType("S1_P1_L1_A5", "INTEGER", evidence: "test inference")
        XCTAssertEqual(loc.type, "INTEGER")
        XCTAssertEqual(loc.typeSource, .inferred)
        XCTAssertTrue(gen.typeConflicts.isEmpty)
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
        var gen = makeGenerator(procs: [calledProc])
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
        var gen = makeGenerator(procs: [calledFunc])
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
        var gen = makeGenerator()
        let result = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        XCTAssertEqual(result, "missing destination!")
    }

    // MARK: - Unhandled opcode returns nil

    func testUnhandledOpcodeReturnsNil() {
        var stack = StackSimulator()
        let inst = Instruction(opcode: nop, mnemonic: "NOP")
        var gen = makeGenerator()
        let result = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        XCTAssertNil(result)
    }

    // MARK: - Arithmetic opcodes

    func testADI() {
        var stack = StackSimulator()
        stack.push(("3", "INTEGER"))
        stack.push(("5", "INTEGER"))
        let inst = Instruction(opcode: adi, mnemonic: "ADI")
        var gen = makeGenerator()
        let result = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        XCTAssertNil(result)  // pushes to stack, no pseudo-code
        let (val, _) = stack.pop()
        XCTAssertEqual(val, "(3 + 5)")
    }

    func testSBI() {
        var stack = StackSimulator()
        stack.push(("10", "INTEGER"))
        stack.push(("4", "INTEGER"))
        let inst = Instruction(opcode: sbi, mnemonic: "SBI")
        var gen = makeGenerator()
        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        let (val, _) = stack.pop()
        XCTAssertEqual(val, "(10 - 4)")
    }

    func testMPI() {
        var stack = StackSimulator()
        stack.push(("6", "INTEGER"))
        stack.push(("7", "INTEGER"))
        let inst = Instruction(opcode: mpi, mnemonic: "MPI")
        var gen = makeGenerator()
        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        let (val, _) = stack.pop()
        XCTAssertEqual(val, "(6 * 7)")
    }

    func testDVI() {
        var stack = StackSimulator()
        stack.push(("20", "INTEGER"))
        stack.push(("5", "INTEGER"))
        let inst = Instruction(opcode: dvi, mnemonic: "DVI")
        var gen = makeGenerator()
        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        let (val, _) = stack.pop()
        XCTAssertEqual(val, "(20 DIV 5)")
    }

    func testMODI() {
        var stack = StackSimulator()
        stack.push(("10", "INTEGER"))
        stack.push(("3", "INTEGER"))
        let inst = Instruction(opcode: modi, mnemonic: "MODI")
        var gen = makeGenerator()
        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        let (val, _) = stack.pop()
        XCTAssertEqual(val, "(10 MOD 3)")
    }

    func testABI() {
        var stack = StackSimulator()
        stack.push(("-5", "INTEGER"))
        let inst = Instruction(opcode: abi, mnemonic: "ABI")
        var gen = makeGenerator()
        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        let (val, _) = stack.pop()
        XCTAssertEqual(val, "ABI(-5)")
    }

    func testNGI() {
        var stack = StackSimulator()
        stack.push(("42", "INTEGER"))
        let inst = Instruction(opcode: ngi, mnemonic: "NGI")
        var gen = makeGenerator()
        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        let (val, _) = stack.pop()
        XCTAssertEqual(val, "-42")
    }

    func testSQI() {
        var stack = StackSimulator()
        stack.push(("7", "INTEGER"))
        let inst = Instruction(opcode: sqi, mnemonic: "SQI")
        var gen = makeGenerator()
        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        let (val, _) = stack.pop()
        XCTAssertEqual(val, "(7 * 7)")
    }

    func testLAND() {
        var stack = StackSimulator()
        stack.push(("A", "BOOLEAN"))
        stack.push(("B", "BOOLEAN"))
        let inst = Instruction(opcode: land, mnemonic: "LAND")
        var gen = makeGenerator()
        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        let (val, _) = stack.pop()
        XCTAssertEqual(val, "(A AND B)")
    }

    func testLOR() {
        var stack = StackSimulator()
        stack.push(("X", "BOOLEAN"))
        stack.push(("Y", "BOOLEAN"))
        let inst = Instruction(opcode: lor, mnemonic: "LOR")
        var gen = makeGenerator()
        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        let (val, _) = stack.pop()
        XCTAssertEqual(val, "(X OR Y)")
    }

    func testLNOT() {
        var stack = StackSimulator()
        stack.push(("TRUE", "BOOLEAN"))
        let inst = Instruction(opcode: lnot, mnemonic: "LNOT")
        var gen = makeGenerator()
        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        let (val, _) = stack.pop()
        XCTAssertEqual(val, "(NOT TRUE)")
    }

    func testFLT() {
        var stack = StackSimulator()
        stack.push(("42", "INTEGER"))
        let inst = Instruction(opcode: flt, mnemonic: "FLT")
        var gen = makeGenerator()
        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        let (val, type) = stack.pop()
        XCTAssertEqual(val, "42")
        XCTAssertEqual(type, "REAL")
    }

    func testADR() {
        var stack = StackSimulator()
        stack.push(("1.5", "REAL"))
        stack.push(("2.5", "REAL"))
        let inst = Instruction(opcode: adr, mnemonic: "ADR")
        var gen = makeGenerator()
        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        let (val, type) = stack.pop()
        XCTAssertTrue(val.contains("1.5"))
        XCTAssertTrue(val.contains("2.5"))
        XCTAssertEqual(type, "REAL")
    }

    // MARK: - Comparison opcodes

    func testEQLInteger() {
        var stack = StackSimulator()
        stack.push(("A", "INTEGER"))
        stack.push(("B", "INTEGER"))
        let inst = Instruction(opcode: eql, mnemonic: "EQL", comparatorDataType: "INTEGER")
        var gen = makeGenerator()
        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        let (val, type) = stack.pop()
        XCTAssertEqual(val, "(A = B)")
        XCTAssertEqual(type, "BOOLEAN")
    }

    func testNEQInteger() {
        var stack = StackSimulator()
        stack.push(("X", "INTEGER"))
        stack.push(("Y", "INTEGER"))
        let inst = Instruction(opcode: neq, mnemonic: "NEQ", comparatorDataType: "INTEGER")
        var gen = makeGenerator()
        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        let (val, _) = stack.pop()
        XCTAssertEqual(val, "(X <> Y)")
    }

    func testGRTInteger() {
        var stack = StackSimulator()
        stack.push(("A", "INTEGER"))
        stack.push(("B", "INTEGER"))
        let inst = Instruction(opcode: grt, mnemonic: "GRT", comparatorDataType: "INTEGER")
        var gen = makeGenerator()
        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        let (val, _) = stack.pop()
        XCTAssertEqual(val, "(A > B)")
    }

    func testLEQInteger() {
        var stack = StackSimulator()
        stack.push(("A", "INTEGER"))
        stack.push(("B", "INTEGER"))
        let inst = Instruction(opcode: leq, mnemonic: "LEQ", comparatorDataType: "INTEGER")
        var gen = makeGenerator()
        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        let (val, _) = stack.pop()
        XCTAssertEqual(val, "(A <= B)")
    }

    func testEQUI() {
        var stack = StackSimulator()
        stack.push(("X", "INTEGER"))
        stack.push(("Y", "INTEGER"))
        let inst = Instruction(opcode: equi, mnemonic: "EQUI")
        var gen = makeGenerator()
        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        let (val, type) = stack.pop()
        XCTAssertEqual(val, "(X = Y)")
        XCTAssertEqual(type, "BOOLEAN")
    }

    func testEQUIWithChar() {
        var stack = StackSimulator()
        stack.push(("65", "CHAR"))   // 'A'
        stack.push(("66", "CHAR"))   // 'B'
        let inst = Instruction(opcode: equi, mnemonic: "EQUI")
        var gen = makeGenerator()
        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        let (val, type) = stack.pop()
        XCTAssertTrue(val.contains("'A'"))
        XCTAssertTrue(val.contains("'B'"))
        XCTAssertEqual(type, "BOOLEAN")
    }

    func testNEQI() {
        var stack = StackSimulator()
        stack.push(("A", "INTEGER"))
        stack.push(("B", "INTEGER"))
        let inst = Instruction(opcode: neqi, mnemonic: "NEQI")
        var gen = makeGenerator()
        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        let (val, _) = stack.pop()
        XCTAssertEqual(val, "(A <> B)")
    }

    func testGEQI() {
        var stack = StackSimulator()
        stack.push(("A", "INTEGER"))
        stack.push(("B", "INTEGER"))
        let inst = Instruction(opcode: geqi, mnemonic: "GEQI")
        var gen = makeGenerator()
        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        let (val, _) = stack.pop()
        XCTAssertEqual(val, "(A >= B)")
    }

    // MARK: - Load / push opcodes

    func testSLDC() {
        var stack = StackSimulator()
        let inst = Instruction(opcode: 42, mnemonic: "SLDC 42")  // sldc42
        var gen = makeGenerator()
        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        let (val, type) = stack.pop()
        XCTAssertEqual(val, "42")
        XCTAssertEqual(type, "INTEGER")
    }

    func testLDCI() {
        var stack = StackSimulator()
        let inst = Instruction(opcode: ldci, mnemonic: "LDCI", params: [999])
        var gen = makeGenerator()
        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        let (val, type) = stack.pop()
        XCTAssertEqual(val, "999")
        XCTAssertEqual(type, "INTEGER")
    }

    func testLDCN() {
        var stack = StackSimulator()
        let inst = Instruction(opcode: ldcn, mnemonic: "LDCN")
        var gen = makeGenerator()
        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        let (val, type) = stack.pop()
        XCTAssertEqual(val, "NIL")
        XCTAssertEqual(type, "POINTER")
    }

    func testLSA() {
        var stack = StackSimulator()
        let inst = Instruction(opcode: lsa, mnemonic: "LSA", stringParameter: "HELLO")
        var gen = makeGenerator()
        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        let (val, type) = stack.pop()
        XCTAssertEqual(val, "'HELLO'")
        XCTAssertEqual(type, "STRING")
    }

    func testLPA() {
        var stack = StackSimulator()
        let inst = Instruction(opcode: lpa, mnemonic: "LPA", stringParameter: "ABC")
        var gen = makeGenerator()
        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        let (val, type) = stack.pop()
        XCTAssertEqual(val, "'ABC'")
        XCTAssertEqual(type, "PACKED ARRAY")
    }

    func testLAOWithMemLocation() {
        var stack = StackSimulator()
        let loc = Location(segment: 1, procedure: 1, lexLevel: 0, addr: 10, name: "GVAR")
        let inst = Instruction(opcode: lao, mnemonic: "LAO", memLocation: loc)
        var gen = makeGenerator(labels: [loc])
        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        XCTAssertEqual(stack.peekStackValue().kind, .address)
        let (val, _) = stack.pop()
        XCTAssertEqual(val, "GVAR")
        XCTAssertTrue(gen.allLocations.contains(loc))
    }

    func testLDC() {
        var stack = StackSimulator()
        let inst = Instruction(opcode: ldc, mnemonic: "LDC", params: [3, 100, 200, 300])
        var gen = makeGenerator()
        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        // 3 words pushed in reverse order, so first pop gets first word
        let (val1, _) = stack.pop()
        let (val2, _) = stack.pop()
        let (val3, _) = stack.pop()
        XCTAssertEqual(val1, "100")
        XCTAssertEqual(val2, "200")
        XCTAssertEqual(val3, "300")
    }

    func testINC() {
        var stack = StackSimulator()
        stack.push(("PTR", "POINTER"))
        let inst = Instruction(opcode: inc, mnemonic: "INC", params: [4])
        var gen = makeGenerator()
        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        let (val, _) = stack.pop()
        XCTAssertEqual(val, "(PTR + 4)")
    }

    func testIND() {
        var stack = StackSimulator()
        stack.push(("BASE", "POINTER"), kind: .address)
        let inst = Instruction(opcode: ind, mnemonic: "IND", params: [2])
        var gen = makeGenerator()
        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        XCTAssertEqual(stack.peekStackValue().kind, .value)
        let (val, type) = stack.pop()
        XCTAssertEqual(val, "*(BASE + 2)")
        XCTAssertEqual(type, "INTEGER")
    }

    func testIXA() {
        var stack = StackSimulator()
        stack.push(("ARR", "POINTER"))
        stack.push(("3", "INTEGER"))
        let inst = Instruction(opcode: ixa, mnemonic: "IXA", params: [2])
        var gen = makeGenerator()
        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        XCTAssertEqual(stack.peekStackValue().kind, .address)
        let (val, _) = stack.pop()
        XCTAssertEqual(val, "ARR[3]")
    }

    func testIXPPreservesBaseAddressKind() {
        var stack = StackSimulator()
        stack.push(("BASE", "POINTER"), kind: .address)
        stack.push(("4", "INTEGER"), kind: .constant)
        let inst = Instruction(opcode: ixp, mnemonic: "IXP", params: [2, 8])
        var gen = makeGenerator()
        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        XCTAssertEqual(stack.peekStackValue(2).kind, .address)
        XCTAssertEqual(stack.peekStackValue(1).kind, .constant)
        XCTAssertEqual(stack.peekStackValue(0).kind, .expression)
    }

    func testLDB() {
        var stack = StackSimulator()
        stack.push(("BUF", "POINTER"))
        stack.push(("5", "INTEGER"))
        let inst = Instruction(opcode: ldb, mnemonic: "LDB")
        var gen = makeGenerator()
        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        let (val, type) = stack.pop()
        XCTAssertEqual(val, "BUF[5]")
        XCTAssertEqual(type, "BYTE")
    }

    func testLDP() {
        var stack = StackSimulator()
        stack.push(("BASE", "POINTER"))
        stack.push(("4", "INTEGER"))   // width
        stack.push(("2", "INTEGER"))   // bit
        let inst = Instruction(opcode: ldp, mnemonic: "LDP")
        var gen = makeGenerator()
        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        let (val, type) = stack.pop()
        XCTAssertEqual(val, "BASE:4:2")
        XCTAssertEqual(type, "INTEGER")
    }

    func testLDM() {
        var stack = StackSimulator()
        stack.push(("ORIGIN", "POINTER"))
        let inst = Instruction(opcode: ldm, mnemonic: "LDM", params: [3])
        var gen = makeGenerator()
        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        XCTAssertEqual(stack.stack.count, 3)
    }

    // MARK: - CSP (call standard procedure)

    func testCSPWithReturnValue() {
        var stack = StackSimulator()
        // MEMAVAIL (proc 40) takes no params, returns INTEGER
        let inst = Instruction(opcode: csp, mnemonic: "CSP", params: [40])
        var gen = makeGenerator()
        let result = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        XCTAssertNil(result)  // return value pushed to stack
        let (val, type) = stack.pop()
        XCTAssertEqual(val, "MEMAVAIL()")
        XCTAssertEqual(type, "INTEGER")
    }

    func testCSPWithNoReturnValue() {
        var stack = StackSimulator()
        // HALT (proc 39) takes no params, returns nothing
        let inst = Instruction(opcode: csp, mnemonic: "CSP", params: [39])
        var gen = makeGenerator()
        let result = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        XCTAssertEqual(result, "HALT()")
    }

    func testCSPWithParameters() {
        var stack = StackSimulator()
        stack.push(("5", "INTEGER"))
        // LOADSEGMENT (proc 21) takes one INTEGER param, returns nothing
        let inst = Instruction(opcode: csp, mnemonic: "CSP", params: [21])
        var gen = makeGenerator()
        let result = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("LOADSEGMENT"))
        XCTAssertTrue(result!.contains("5"))
    }

    func testCSPUnknownProcReturnsNil() {
        var stack = StackSimulator()
        let inst = Instruction(opcode: csp, mnemonic: "CSP", params: [255])  // nonexistent
        var gen = makeGenerator()
        let result = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        XCTAssertNil(result)
    }
}
