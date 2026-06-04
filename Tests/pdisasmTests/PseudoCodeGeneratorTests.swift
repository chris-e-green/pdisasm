import XCTest
@testable import pdisasm

final class PseudoCodeGeneratorTests: XCTestCase {

    private func makeGenerator(
        procs: [ProcedureIdentifier] = [],
        labels: [Location] = [],
        typeAliases: [String: String] = [:],
        scalarTypes: [String: PascalScalarType] = [:],
        records: Set<PascalRecord> = []
    ) -> PseudoCodeGenerator {
        return PseudoCodeGenerator(
            allProcedures: procs,
            knownRecords: records,
            typeAliases: typeAliases,
            scalarTypes: scalarTypes,
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
        XCTAssertTrue(stack.values.isEmpty)
    }

    func testSTOToRecordWithoutFieldPointerUsesOffsetZeroMember() {
        let record = PascalRecord(
            name: "DISPSTATE",
            members: [
                0: Identifier(name: "LEFT", type: "INTEGER"),
                1: Identifier(name: "RIGHT", type: "INTEGER"),
                2: Identifier(name: "BOTTOM", type: "INTEGER")
            ]
        )
        var stack = StackSimulator()
        stack.push(("DISPSTATE_COPY", "DISPSTATE"), kind: .value)
        stack.push(("0", "INTEGER"), kind: .constant)
        let inst = Instruction(opcode: sto, mnemonic: "STO")
        var gen = makeGenerator(records: [record])
        let result = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        XCTAssertEqual(result, "DISPSTATE_COPY.LEFT := 0")
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

    func testSTPUsesRealRepresentationTarget() {
        let loc = Location(
            segment: 1,
            procedure: 1,
            lexLevel: 1,
            addr: 5,
            name: "RVALUE",
            type: "REAL",
            typeSource: .metadata
        )
        var stack = StackSimulator()
        stack.push(("RVALUE", "REAL"), kind: .address, location: loc)
        stack.push(("4", "INTEGER"), kind: .constant)
        stack.push(("2", "INTEGER"), kind: .constant)
        stack.push(("VALUE", "INTEGER"), kind: .value)
        let inst = Instruction(opcode: stp, mnemonic: "STP")
        var gen = makeGenerator(labels: [loc])
        let result = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        XCTAssertEqual(result, "REAL_BITS(RVALUE, 4, 2) := VALUE")
        XCTAssertEqual(loc.type, "REAL")
        XCTAssertTrue(gen.typeConflicts.isEmpty)
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

    func testSTBUsesRealRepresentationTarget() {
        let loc = Location(
            segment: 1,
            procedure: 1,
            lexLevel: 1,
            addr: 5,
            name: "RVALUE",
            type: "REAL",
            typeSource: .metadata
        )
        var stack = StackSimulator()
        stack.push(("RVALUE", "REAL"), kind: .address, location: loc)
        stack.push(("1", "INTEGER"), kind: .constant)
        stack.push(("88", "BYTE"), kind: .constant)
        let inst = Instruction(opcode: stb, mnemonic: "STB")
        var gen = makeGenerator(labels: [loc])
        let result = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        XCTAssertEqual(result, "REAL_BYTE(RVALUE, 1) := 88")
        XCTAssertEqual(loc.type, "REAL")
        XCTAssertTrue(gen.typeConflicts.isEmpty)
    }

    // MARK: - STM (store multiple words)

    func testSTMRecombinesRealWordRepresentationSource() {
        let dst = Location(
            segment: 31,
            procedure: 4,
            lexLevel: 1,
            addr: 9,
            type: "REAL",
            typeSource: .metadata
        )
        var stack = StackSimulator()
        stack.push(StackValue(
            text: dst.displayName,
            type: "REAL",
            kind: .address,
            location: dst
        ))
        stack.push(StackValue(text: "REAL_WORD(X, 0)", type: "INTEGER", kind: .value))
        stack.push(StackValue(text: "REAL_WORD(X, 1)", type: "INTEGER", kind: .value))
        let inst = Instruction(opcode: stm, mnemonic: "STM", params: [2])
        var gen = makeGenerator(labels: [dst])

        let result = gen.generateForInstruction(inst, stack: &stack, loc: nil)

        XCTAssertEqual(result, "S31_P4_L1_A9 := X")
        XCTAssertEqual(dst.type, "REAL")
        XCTAssertTrue(gen.typeConflicts.isEmpty)
    }

    func testSTMRecombinesRealWordRepresentationSourceWithPhysicalWordLocation() {
        let dst = Location(
            segment: 29,
            procedure: 6,
            lexLevel: 1,
            addr: 5,
            type: "REAL",
            typeSource: .metadata
        )
        let src = Location(
            segment: 29,
            procedure: 6,
            lexLevel: 1,
            addr: 3,
            name: "X",
            type: "REAL",
            typeSource: .metadata
        )
        let srcSecondWord = Location(
            segment: 29,
            procedure: 6,
            lexLevel: 1,
            addr: 4
        )
        var stack = StackSimulator()
        stack.push(StackValue(
            text: dst.displayName,
            type: "UNKNOWN",
            kind: .address,
            location: dst
        ))
        stack.push(StackValue(
            text: "REAL_WORD(X, 0)",
            type: "INTEGER",
            kind: .value,
            location: src
        ))
        stack.push(StackValue(
            text: "REAL_WORD(X, 1)",
            type: "INTEGER",
            kind: .value,
            location: srcSecondWord
        ))
        let inst = Instruction(opcode: stm, mnemonic: "STM", params: [2])
        var gen = makeGenerator(labels: [dst, src])

        let result = gen.generateForInstruction(inst, stack: &stack, loc: nil)

        XCTAssertEqual(result, "S29_P6_L1_A5 := X")
        XCTAssertTrue(stack.values.isEmpty)
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

    func testSTLScalarTypeConvertsIntegerToCaseName() {
        var stack = StackSimulator()
        stack.push(("2", "INTEGER"))
        let loc = Location(segment: 1, procedure: 1, lexLevel: 1, addr: 5, name: "SK", type: "SEGKINDS")
        let inst = Instruction(opcode: stl, mnemonic: "STL", memLocation: loc)
        var gen = makeGenerator(
            labels: [loc],
            scalarTypes: [
                "SEGKINDS": PascalScalarType(
                    name: "SEGKINDS",
                    cases: ["LINKED", "HOSTSEG", "SEGPROC", "UNITSEG", "SEPRTSEG"]
                )
            ]
        )

        let result = gen.generateForInstruction(inst, stack: &stack, loc: loc)

        XCTAssertEqual(result, "SK := SEGPROC")
    }

    func testSTOScalarTypeConvertsIntegerToCaseName() {
        var stack = StackSimulator()
        stack.push(("SK", "SEGKINDS"), kind: .address)
        stack.push(("1", "INTEGER"), kind: .constant)
        let inst = Instruction(opcode: sto, mnemonic: "STO")
        var gen = makeGenerator(
            scalarTypes: [
                "SEGKINDS": PascalScalarType(
                    name: "SEGKINDS",
                    cases: ["LINKED", "HOSTSEG", "SEGPROC"]
                )
            ]
        )

        let result = gen.generateForInstruction(inst, stack: &stack, loc: nil)

        XCTAssertEqual(result, "SK := HOSTSEG")
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

    func testCallProcedureInfersArgumentTypeFromKnownParameterType() {
        let arg = Location(
            segment: 1,
            procedure: 2,
            lexLevel: 0,
            addr: 5,
            name: "ARG",
            type: "UNKNOWN"
        )
        var stack = StackSimulator()
        stack.push(StackValue(text: "ARG", type: "UNKNOWN", kind: .value, location: arg))
        let calledProc = ProcedureIdentifier(
            isFunction: false,
            segment: 1,
            segmentName: "MYSEG",
            procedure: 5,
            procName: "DOWORK",
            parameters: [Identifier(name: "X", type: "INTEGER", typeSource: .inferred)]
        )
        let dest = Location(segment: 1, procedure: 5)
        let inst = Instruction(opcode: cip, mnemonic: "CIP", destination: dest)
        var gen = makeGenerator(procs: [calledProc], labels: [arg])

        let result = gen.generateForInstruction(inst, stack: &stack, loc: nil)

        XCTAssertEqual(result, "MYSEG.DOWORK(ARG)")
        XCTAssertEqual(gen.allLocations.first(where: { $0 == arg })?.type, "INTEGER")
        XCTAssertEqual(gen.allLocations.first(where: { $0 == arg })?.typeSource, .inferred)
    }

    func testCallProcedureDoesNotInferArbitraryPointerParameterType() {
        let arg = Location(
            segment: 1,
            procedure: 2,
            lexLevel: 0,
            addr: 5,
            name: "ARG",
            type: "UNKNOWN"
        )
        var stack = StackSimulator()
        stack.push(StackValue(text: "ARG", type: "POINTER", kind: .address, location: arg))
        let calledProc = ProcedureIdentifier(
            isFunction: false,
            segment: 1,
            segmentName: "MYSEG",
            procedure: 5,
            procName: "DOWORK",
            parameters: [Identifier(name: "X", type: "UNKNOWN")]
        )
        let dest = Location(segment: 1, procedure: 5)
        let inst = Instruction(opcode: cip, mnemonic: "CIP", destination: dest)
        var gen = makeGenerator(procs: [calledProc], labels: [arg])

        let result = gen.generateForInstruction(inst, stack: &stack, loc: nil)

        XCTAssertEqual(result, "MYSEG.DOWORK(ARG)")
        XCTAssertEqual(calledProc.parameters[0].type, "UNKNOWN")
        XCTAssertEqual(gen.allLocations.first(where: { $0 == arg })?.type, "UNKNOWN")
    }

    func testCallProcedureConsumesTwoWordRealArgument() {
        let intArg = Location(
            segment: 1,
            procedure: 2,
            lexLevel: 0,
            addr: 3,
            name: "COUNT",
            type: "INTEGER"
        )
        let realArg = Location(
            segment: 1,
            procedure: 2,
            lexLevel: 0,
            addr: 1,
            name: "VALUE",
            type: "REAL"
        )
        var stack = StackSimulator()
        stack.push(StackValue(text: "COUNT", type: "INTEGER", kind: .value, location: intArg))
        stack.push(stack.realWordValue(
            base: StackValue(text: "VALUE", type: "REAL", kind: .address, location: realArg),
            wordIndex: 0,
            physicalLocation: realArg
        ))
        stack.push(stack.realWordValue(
            base: StackValue(text: "VALUE", type: "REAL", kind: .address, location: realArg),
            wordIndex: 1,
            physicalLocation: Location(segment: 1, procedure: 2, lexLevel: 0, addr: 2)
        ))
        let calledProc = ProcedureIdentifier(
            isFunction: false,
            segment: 1,
            segmentName: "MYSEG",
            procedure: 5,
            procName: "DOWORK",
            parameters: [
                Identifier(name: "COUNT", type: "INTEGER"),
                Identifier(name: "VALUE", type: "REAL"),
            ]
        )
        let inst = Instruction(
            opcode: cip,
            mnemonic: "CIP",
            destination: Location(segment: 1, procedure: 5)
        )
        var gen = makeGenerator(procs: [calledProc], labels: [intArg, realArg])

        let result = gen.generateForInstruction(inst, stack: &stack, loc: nil)

        XCTAssertEqual(result, "MYSEG.DOWORK(COUNT, VALUE)")
        XCTAssertTrue(stack.values.isEmpty)
    }

    func testUnknownFunctionCallInfersRealArgumentAndRealReturnStore() {
        let returnLocation = Location(
            segment: 29,
            procedure: 2,
            lexLevel: 1,
            addr: 1,
            name: "TRANSCEN.FUNC2",
            type: "UNKNOWN"
        )
        let param = Location(
            segment: 29,
            procedure: 2,
            lexLevel: 1,
            addr: 3,
            name: "PARAM1",
            type: "REAL",
            typeSource: .inferred
        )
        let func9Return = Location(
            segment: 29,
            procedure: 9,
            addr: 1,
            type: "UNKNOWN"
        )
        let func9 = ProcedureIdentifier(
            isFunction: true,
            segment: 29,
            segmentName: "TRANSCEN",
            procedure: 9,
            parameters: [
                Identifier(name: "PARAM1", type: "UNKNOWN"),
                Identifier(name: "PARAM2", type: "UNKNOWN"),
                Identifier(name: "PARAM3", type: "UNKNOWN"),
            ],
            returnType: "UNKNOWN"
        )
        var gen = makeGenerator(
            procs: [func9],
            labels: [returnLocation, param, func9Return]
        )
        var stack = StackSimulator()

        _ = gen.generateForInstruction(Instruction(opcode: lla, mnemonic: "LLA", memLocation: returnLocation), stack: &stack, loc: nil)
        _ = gen.generateForInstruction(Instruction(opcode: lla, mnemonic: "LLA", memLocation: param), stack: &stack, loc: nil)
        _ = gen.generateForInstruction(Instruction(opcode: ldm, mnemonic: "LDM", params: [2]), stack: &stack, loc: nil)
        _ = gen.generateForInstruction(Instruction(opcode: ngr, mnemonic: "NGR"), stack: &stack, loc: nil)
        _ = gen.generateForInstruction(Instruction(opcode: 1, mnemonic: "SLDC 01"), stack: &stack, loc: nil)
        _ = gen.generateForInstruction(Instruction(opcode: ngi, mnemonic: "NGI"), stack: &stack, loc: nil)
        _ = gen.generateForInstruction(Instruction(opcode: sldc0, mnemonic: "SLDC 00"), stack: &stack, loc: nil)
        _ = gen.generateForInstruction(Instruction(opcode: sldc0, mnemonic: "SLDC 00"), stack: &stack, loc: nil)
        _ = gen.generateForInstruction(
            Instruction(
                opcode: cgp,
                mnemonic: "CGP",
                destination: Location(segment: 29, procedure: 9)
            ),
            stack: &stack,
            loc: nil
        )
        let store = gen.generateForInstruction(
            Instruction(opcode: stm, mnemonic: "STM", params: [2]),
            stack: &stack,
            loc: nil
        )

        XCTAssertEqual(store, "TRANSCEN.FUNC2 := TRANSCEN.FUNC9(-PARAM1, -1)")
        XCTAssertTrue(stack.values.isEmpty)
        XCTAssertEqual(func9.parameters.map(\.description), ["PARAM1:REAL", "PARAM3:INTEGER"])
        XCTAssertEqual(gen.allLocations.first(where: { $0 == func9Return })?.type, "REAL")
    }

    func testUnknownFunctionCallInfersAggregateRealArgumentAndRealReturnBeforeMultiply() {
        let returnLocation = Location(
            segment: 29,
            procedure: 7,
            lexLevel: 1,
            addr: 1,
            name: "TRANSCEN.FUNC7",
            type: "UNKNOWN"
        )
        let param = Location(
            segment: 29,
            procedure: 7,
            lexLevel: 1,
            addr: 3,
            name: "PARAM1",
            type: "UNKNOWN"
        )
        let func6Return = Location(
            segment: 29,
            procedure: 6,
            addr: 1,
            type: "UNKNOWN"
        )
        let func6 = ProcedureIdentifier(
            isFunction: true,
            segment: 29,
            segmentName: "TRANSCEN",
            procedure: 6,
            parameters: [
                Identifier(name: "PARAM1", type: "UNKNOWN"),
                Identifier(name: "PARAM2", type: "UNKNOWN"),
            ],
            returnType: "UNKNOWN"
        )
        var gen = makeGenerator(
            procs: [func6],
            labels: [returnLocation, param, func6Return]
        )
        var stack = StackSimulator()

        _ = gen.generateForInstruction(Instruction(opcode: lla, mnemonic: "LLA", memLocation: returnLocation), stack: &stack, loc: nil)
        _ = gen.generateForInstruction(Instruction(opcode: lla, mnemonic: "LLA", memLocation: param), stack: &stack, loc: nil)
        _ = gen.generateForInstruction(Instruction(opcode: ldm, mnemonic: "LDM", params: [2]), stack: &stack, loc: nil)
        _ = gen.generateForInstruction(Instruction(opcode: sldc0, mnemonic: "SLDC 00"), stack: &stack, loc: nil)
        _ = gen.generateForInstruction(Instruction(opcode: sldc0, mnemonic: "SLDC 00"), stack: &stack, loc: nil)
        _ = gen.generateForInstruction(
            Instruction(
                opcode: cgp,
                mnemonic: "CGP",
                destination: Location(segment: 29, procedure: 6)
            ),
            stack: &stack,
            loc: nil
        )
        _ = gen.generateForInstruction(
            Instruction(opcode: ldc, mnemonic: "LDC", params: [2, 0, 0]),
            stack: &stack,
            loc: nil
        )
        _ = gen.generateForInstruction(Instruction(opcode: mpr, mnemonic: "MPR"), stack: &stack, loc: nil)
        let store = gen.generateForInstruction(
            Instruction(opcode: stm, mnemonic: "STM", params: [2]),
            stack: &stack,
            loc: nil
        )

        XCTAssertEqual(store, "TRANSCEN.FUNC7 := TRANSCEN.FUNC6(PARAM1) * 0.0")
        XCTAssertTrue(stack.values.isEmpty)
        XCTAssertEqual(func6.parameters.map(\.description), ["PARAM1:REAL"])
        XCTAssertEqual(gen.allLocations.first(where: { $0 == returnLocation })?.type, "REAL")
        XCTAssertEqual(gen.allLocations.first(where: { $0 == param })?.type, "REAL")
        XCTAssertEqual(gen.allLocations.first(where: { $0 == func6Return })?.type, "REAL")

        let func7 = ProcedureIdentifier(
            isFunction: true,
            segment: 29,
            segmentName: "TRANSCEN",
            procedure: 7,
            procName: "FUNC7",
            parameters: [Identifier(name: "PARAM1", type: "REAL")],
            returnType: "UNKNOWN"
        )
        let conflicts = synchronizeProcedureSignatures(
            procedures: [func7],
            locations: gen.allLocations
        )
        XCTAssertTrue(conflicts.isEmpty)
        XCTAssertEqual(func7.returnType, "REAL")
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
        XCTAssertEqual(stack.values.count, 1)
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

    func testMPRCollapsesSameBaseRealWordRepresentationAccesses() {
        var stack = StackSimulator()
        stack.push(StackValue(text: "Y", type: "REAL", kind: .value))
        stack.push(StackValue(text: "REAL_WORD(S29_P4_L1_A6, 0)", type: "INTEGER", kind: .value))
        stack.push(StackValue(text: "REAL_WORD(S29_P4_L1_A6, 1)", type: "INTEGER", kind: .value))
        let inst = Instruction(opcode: mpr, mnemonic: "MPR")
        var gen = makeGenerator()

        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)

        let (val, type) = stack.pop()
        XCTAssertEqual(val, "(Y * S29_P4_L1_A6)")
        XCTAssertEqual(type, "REAL")
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

    func testIntegerArithmeticInfersParameterOperandTypes() {
        assertIntegerArithmeticInfersParameterOperandTypes(opcode: adi, mnemonic: "ADI")
        assertIntegerArithmeticInfersParameterOperandTypes(opcode: dvi, mnemonic: "DVI")
        assertIntegerArithmeticInfersParameterOperandTypes(opcode: modi, mnemonic: "MODI")
    }

    private func assertIntegerArithmeticInfersParameterOperandTypes(opcode: UInt8, mnemonic: String) {
        let lhs = Location(
            segment: 1,
            procedure: 2,
            lexLevel: nil,
            addr: 3,
            isParam: true,
            name: "LHS",
            type: "UNKNOWN"
        )
        let rhs = Location(
            segment: 1,
            procedure: 2,
            lexLevel: nil,
            addr: 4,
            isParam: true,
            name: "RHS",
            type: "UNKNOWN"
        )
        var stack = StackSimulator()
        stack.push(StackValue(text: "LHS", type: "UNKNOWN", kind: .value, location: lhs))
        stack.push(StackValue(text: "RHS", type: "UNKNOWN", kind: .value, location: rhs))
        let inst = Instruction(opcode: opcode, mnemonic: mnemonic)
        var gen = makeGenerator(labels: [lhs, rhs])

        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)

        XCTAssertEqual(gen.allLocations.first(where: { $0 == lhs })?.type, "INTEGER")
        XCTAssertEqual(gen.allLocations.first(where: { $0 == rhs })?.type, "INTEGER")
        XCTAssertEqual(gen.allLocations.first(where: { $0 == lhs })?.typeSource, .inferred)
        XCTAssertEqual(gen.allLocations.first(where: { $0 == rhs })?.typeSource, .inferred)
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

    func testADRRecombinesRealWordRepresentationAccesses() {
        let loc = Location(
            segment: 1,
            procedure: 1,
            lexLevel: 1,
            addr: 5,
            name: "X",
            type: "REAL",
            typeSource: .metadata
        )
        var stack = StackSimulator()
        stack.push(("1.5", "REAL"))
        stack.push(("X", "REAL"), kind: .address, location: loc)
        var gen = makeGenerator(labels: [loc])

        _ = gen.generateForInstruction(
            Instruction(opcode: ldm, mnemonic: "LDM", params: [2]),
            stack: &stack,
            loc: nil
        )
        _ = gen.generateForInstruction(
            Instruction(opcode: adr, mnemonic: "ADR"),
            stack: &stack,
            loc: nil
        )

        let (val, type) = stack.pop()
        XCTAssertEqual(val, "(X + 1.5)")
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

    func testREALComparisonInfersRepresentationOperandTypes() {
        let left = Location(
            segment: 1,
            procedure: 1,
            lexLevel: 1,
            addr: 5,
            name: "LEFT",
            type: "UNKNOWN"
        )
        let right = Location(
            segment: 1,
            procedure: 1,
            lexLevel: 1,
            addr: 7,
            name: "RIGHT",
            type: "UNKNOWN"
        )
        var stack = StackSimulator()
        stack.push(stack.realWordValue(
            base: StackValue(text: "LEFT", type: "UNKNOWN", kind: .address, location: left),
            wordIndex: 0,
            physicalLocation: left
        ))
        stack.push(stack.realWordValue(
            base: StackValue(text: "LEFT", type: "UNKNOWN", kind: .address, location: left),
            wordIndex: 1,
            physicalLocation: Location(segment: 1, procedure: 1, lexLevel: 1, addr: 6)
        ))
        stack.push(stack.realWordValue(
            base: StackValue(text: "RIGHT", type: "UNKNOWN", kind: .address, location: right),
            wordIndex: 0,
            physicalLocation: right
        ))
        stack.push(stack.realWordValue(
            base: StackValue(text: "RIGHT", type: "UNKNOWN", kind: .address, location: right),
            wordIndex: 1,
            physicalLocation: Location(segment: 1, procedure: 1, lexLevel: 1, addr: 8)
        ))

        let inst = Instruction(opcode: les, mnemonic: "LES", comparatorDataType: "REAL")
        var gen = makeGenerator(labels: [left, right])
        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)

        let (val, type) = stack.pop()
        XCTAssertEqual(val, "(LEFT < RIGHT)")
        XCTAssertEqual(type, "BOOLEAN")
        XCTAssertEqual(left.type, "REAL")
        XCTAssertEqual(right.type, "REAL")
        XCTAssertTrue(gen.typeConflicts.isEmpty)
    }

    func testREALComparisonInfersUnknownLDMOperandAsReal() {
        let param = Location(
            segment: 29,
            procedure: 2,
            lexLevel: 1,
            addr: 3,
            isParam: true,
            name: "PARAM2",
            type: "UNKNOWN"
        )
        var stack = StackSimulator()
        var gen = makeGenerator(labels: [param])

        _ = gen.generateForInstruction(
            Instruction(opcode: lla, mnemonic: "LLA", memLocation: param),
            stack: &stack,
            loc: nil
        )
        _ = gen.generateForInstruction(
            Instruction(opcode: ldm, mnemonic: "LDM", params: [2]),
            stack: &stack,
            loc: nil
        )
        _ = gen.generateForInstruction(
            Instruction(opcode: ldc, mnemonic: "LDC", params: [2, 0, 0]),
            stack: &stack,
            loc: nil
        )
        _ = gen.generateForInstruction(
            Instruction(opcode: les, mnemonic: "LES", comparatorDataType: "REAL"),
            stack: &stack,
            loc: nil
        )

        let (val, type) = stack.pop()
        XCTAssertEqual(val, "(PARAM2 < 0.0)")
        XCTAssertEqual(type, "BOOLEAN")
        XCTAssertEqual(gen.allLocations.first(where: { $0 == param })?.type, "REAL")
        XCTAssertEqual(gen.allLocations.first(where: { $0 == param })?.typeSource, .inferred)
        XCTAssertTrue(gen.typeConflicts.isEmpty)
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

    func testINNWithCharValueFormatsNumericSetAsCharacterRanges() {
        var stack = StackSimulator()
        stack.push(("CH", "CHAR"))
        stack.push(("2047", "INTEGER"))   // word 7: 112...122
        stack.push(("65534", "INTEGER"))  // word 6: 97...111
        stack.push(("2047", "INTEGER"))   // word 5: 80...90
        stack.push(("65534", "INTEGER"))  // word 4: 65...79
        stack.push(("0", "INTEGER"))
        stack.push(("0", "INTEGER"))
        stack.push(("0", "INTEGER"))
        stack.push(("0", "INTEGER"))
        stack.push(("8", "INTEGER"))
        let inst = Instruction(opcode: inn, mnemonic: "INN")
        var gen = makeGenerator()
        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)

        let (val, type) = stack.pop("BOOLEAN", true)
        XCTAssertEqual(val, "CH IN ['A'..'Z', 'a'..'z']")
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
        XCTAssertEqual(val, "^GVAR")
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
        XCTAssertEqual(val, "^(PTR + 4)")
    }

    func testIND() {
        var stack = StackSimulator()
        stack.push(("BASE", "POINTER"), kind: .address)
        let inst = Instruction(opcode: ind, mnemonic: "IND", params: [2])
        var gen = makeGenerator()
        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        XCTAssertEqual(stack.peekStackValue().kind, .value)
        let (val, type) = stack.pop()
        XCTAssertEqual(val, "(BASE + 2)^")
        XCTAssertEqual(type, "INTEGER")
    }

    func testINDZeroOnAddressLoadsVariable() {
        var stack = StackSimulator()
        stack.push(("BASE", "INTEGER"), kind: .address)
        let inst = Instruction(opcode: ind, mnemonic: "IND", params: [0])
        var gen = makeGenerator()

        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)

        let (val, type) = stack.pop()
        XCTAssertEqual(val, "BASE")
        XCTAssertEqual(type, "INTEGER")
    }

    func testINDZeroOnPointerValueDereferencesWithPascalSyntax() {
        var stack = StackSimulator()
        stack.push(("PTR", "^NODE"), kind: .value)
        let inst = Instruction(opcode: ind, mnemonic: "IND", params: [0])
        var gen = makeGenerator()

        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)

        let (val, type) = stack.pop()
        XCTAssertEqual(val, "PTR^")
        XCTAssertEqual(type, "NODE")
    }

    func testINDZeroResolvesPointerAlias() {
        var stack = StackSimulator()
        stack.push(("PTR", "ITEMREF"), kind: .value)
        let inst = Instruction(opcode: ind, mnemonic: "IND", params: [0])
        var gen = makeGenerator(typeAliases: ["ITEMREF": "^ITEM"])

        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)

        let (val, type) = stack.pop()
        XCTAssertEqual(val, "PTR^")
        XCTAssertEqual(type, "ITEM")
    }

    func testRecordFieldAccessResolvesParsedPascalTypeDefinitions() {
        let definitions = PascalTypeDefinitionParser.parse("""
            CONST
            C1=8;
            C4=4;
            MAXSEGS=15;
            TYPE
            ALPHA=PACKED ARRAY[1..C1] OF CHAR;
            SEGNO=1..MAXSEGS;
            SEGKINDS=(LINKED,HOSTSEG,SEGPROC,UNITSEG,SEPRTSEG);
            WORDREF=^WORD;
            ITEMREF=^ITEM;
            WORD=RECORD
              KEY: ALPHA;
              KIND: SEGKINDS;
              FIRST,LAST: ITEMREF;
              LEFT,RIGHT: WORDREF;
            END;
            ITEM=PACKED RECORD
              LNO: 0..C4;
              NEXT: ITEMREF;
            END;
            """)
        let word = definitions.records.first { $0.name == "WORD" }
        let item = definitions.records.first { $0.name == "ITEM" }
        XCTAssertEqual(definitions.constants["MAXSEGS"], 15)
        XCTAssertEqual(definitions.subrangeTypes["SEGNO"]?.lowerBound, 1)
        XCTAssertEqual(definitions.subrangeTypes["SEGNO"]?.upperBound, 15)
        XCTAssertEqual(definitions.aliases["SEGNO"], "INTEGER")
        XCTAssertEqual(definitions.aliases["WORDREF"], "^WORD")
        XCTAssertEqual(definitions.aliases["ITEMREF"], "^ITEM")
        XCTAssertEqual(definitions.aliases["ALPHA"], "ARRAY OF CHAR")
        XCTAssertNil(definitions.aliases["SEGKINDS"])
        XCTAssertEqual(definitions.scalarTypes["SEGKINDS"]?.namesByValue[0], "LINKED")
        XCTAssertEqual(definitions.scalarTypes["SEGKINDS"]?.namesByValue[2], "SEGPROC")
        XCTAssertEqual(definitions.scalarTypes["SEGKINDS"]?.valuesByName["SEPRTSEG"], 4)
        XCTAssertEqual(word?.members[0]?.name, "KEY")
        XCTAssertEqual(word?.members[1]?.name, "KIND")
        XCTAssertEqual(word?.members[1]?.type, "SEGKINDS")
        XCTAssertEqual(word?.members[2]?.name, "FIRST")
        XCTAssertEqual(word?.members[2]?.type, "ITEMREF")
        XCTAssertEqual(item?.members[0]?.name, "LNO")
        XCTAssertEqual(item?.members[0]?.type, "0..4")

        var stack = StackSimulator()
        stack.push(("W", "WORDREF"), kind: .value)
        var gen = makeGenerator(
            typeAliases: definitions.aliases,
            scalarTypes: definitions.scalarTypes,
            records: definitions.records
        )

        _ = gen.generateForInstruction(Instruction(opcode: ind, mnemonic: "IND", params: [0]), stack: &stack, loc: nil)
        _ = gen.generateForInstruction(Instruction(opcode: ind, mnemonic: "IND", params: [2]), stack: &stack, loc: nil)

        let value = stack.popStackValue()
        XCTAssertEqual(value.text, "W^.FIRST")
        XCTAssertEqual(value.type, "ITEMREF")
    }

    func testVariantRecordFieldsShareOffsets() {
        let definitions = PascalTypeDefinitionParser.parse("""
            TYPE
            NODE=RECORD
              NEXT: ^NODE;
              CASE KIND: INTEGER OF
                0: (IVALUE: INTEGER);
                1: (RVALUE: REAL);
                2: (CH: CHAR; COUNT: INTEGER)
            END;
            UNTYPED=RECORD
              PREFIX: INTEGER;
              CASE INTEGER OF
                0: (LEFT: INTEGER);
                1: (RIGHT: CHAR)
            END;
            """)

        let node = definitions.records.first { $0.name == "NODE" }
        XCTAssertEqual(node?.members[0]?.name, "NEXT")
        XCTAssertEqual(node?.members[1]?.name, "KIND")
        XCTAssertEqual(node?.members[2]?.name, "IVALUE")
        XCTAssertEqual(node?.allMembers.first { $0.identifier.name == "IVALUE" }?.offset, 2)
        XCTAssertEqual(node?.allMembers.first { $0.identifier.name == "RVALUE" }?.offset, 2)
        XCTAssertEqual(node?.allMembers.first { $0.identifier.name == "CH" }?.offset, 2)
        XCTAssertEqual(node?.allMembers.first { $0.identifier.name == "COUNT" }?.offset, 3)
        XCTAssertEqual(node?.allMembers.first { $0.identifier.name == "RVALUE" }?.variantLabel, "1")

        let untyped = definitions.records.first { $0.name == "UNTYPED" }
        XCTAssertEqual(untyped?.members[0]?.name, "PREFIX")
        XCTAssertEqual(untyped?.members[1]?.name, "LEFT")
        XCTAssertEqual(untyped?.allMembers.first { $0.identifier.name == "LEFT" }?.offset, 1)
        XCTAssertEqual(untyped?.allMembers.first { $0.identifier.name == "RIGHT" }?.offset, 1)
    }

    func testINDUsesRealRepresentationAccess() {
        let loc = Location(
            segment: 1,
            procedure: 1,
            lexLevel: 1,
            addr: 5,
            name: "RVALUE",
            type: "REAL",
            typeSource: .metadata
        )
        var stack = StackSimulator()
        stack.push(("RVALUE", "REAL"), kind: .address, location: loc)
        let inst = Instruction(opcode: ind, mnemonic: "IND", params: [1])
        var gen = makeGenerator(labels: [loc])
        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        let value = stack.popStackValue()
        XCTAssertEqual(value.text, "REAL_WORD(RVALUE, 1)")
        XCTAssertEqual(value.type, "INTEGER")
        XCTAssertEqual(value.location?.displayName, "S1_P1_L1_A6")
        XCTAssertEqual(loc.type, "REAL")
        XCTAssertTrue(gen.typeConflicts.isEmpty)
    }

    func testINDUsesSecondRealWordMemoryLocation() {
        let loc = Location(
            segment: 29,
            procedure: 4,
            lexLevel: 1,
            addr: 8,
            type: "REAL",
            typeSource: .metadata
        )
        var stack = StackSimulator()
        stack.push((loc.displayName, "REAL"), kind: .address, location: loc)
        let inst = Instruction(opcode: ind, mnemonic: "IND", params: [1])
        var gen = makeGenerator(labels: [loc])
        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)

        let value = stack.popStackValue()

        XCTAssertEqual(value.text, "REAL_WORD(S29_P4_L1_A8, 1)")
        XCTAssertEqual(value.type, "INTEGER")
        XCTAssertEqual(value.location?.displayName, "S29_P4_L1_A9")
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
        XCTAssertEqual(val, "^ARR[3]")
    }

    func testIXAStringIndexZeroRendersLength() {
        var stack = StackSimulator()
        stack.push(("S", "STRING"))
        stack.push(("0", "INTEGER"))
        let inst = Instruction(opcode: ixa, mnemonic: "IXA", params: [1])
        var gen = makeGenerator()
        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)

        let value = stack.popStackValue()
        XCTAssertEqual(value.text, "LENGTH(S)")
        XCTAssertEqual(value.type, "INTEGER")
    }

    func testIXAStringPositiveIndexInfersChar() {
        var stack = StackSimulator()
        stack.push(("S", "STRING"))
        stack.push(("1", "INTEGER"))
        let inst = Instruction(opcode: ixa, mnemonic: "IXA", params: [1])
        var gen = makeGenerator()
        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)

        let value = stack.popStackValue()
        XCTAssertEqual(value.text, "S[1]")
        XCTAssertEqual(value.type, "CHAR")
    }

    func testIXAStringSymbolicIndexInfersChar() {
        var stack = StackSimulator()
        stack.push(("S", "STRING"))
        stack.push(("I", "INTEGER"))
        let inst = Instruction(opcode: ixa, mnemonic: "IXA", params: [1])
        var gen = makeGenerator()
        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)

        let value = stack.popStackValue()
        XCTAssertEqual(value.text, "S[I]")
        XCTAssertEqual(value.type, "CHAR")
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

    func testLDBStringOffsetZeroRendersLength() {
        var stack = StackSimulator()
        stack.push(("S", "STRING"))
        stack.push(("0", "INTEGER"))
        let inst = Instruction(opcode: ldb, mnemonic: "LDB")
        var gen = makeGenerator()
        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)

        let value = stack.popStackValue()
        XCTAssertEqual(value.text, "LENGTH(S)")
        XCTAssertEqual(value.type, "INTEGER")
    }

    func testLDBStringPositiveOffsetInfersChar() {
        var stack = StackSimulator()
        stack.push(("S", "STRING"))
        stack.push(("1", "INTEGER"))
        let inst = Instruction(opcode: ldb, mnemonic: "LDB")
        var gen = makeGenerator()
        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)

        let value = stack.popStackValue()
        XCTAssertEqual(value.text, "S[1]")
        XCTAssertEqual(value.type, "CHAR")
    }

    func testLDBUsesRealRepresentationAccess() {
        let loc = Location(
            segment: 1,
            procedure: 1,
            lexLevel: 1,
            addr: 5,
            name: "RVALUE",
            type: "REAL",
            typeSource: .metadata
        )
        var stack = StackSimulator()
        stack.push(("RVALUE", "REAL"), kind: .address, location: loc)
        stack.push(("1", "INTEGER"), kind: .constant)
        let inst = Instruction(opcode: ldb, mnemonic: "LDB")
        var gen = makeGenerator(labels: [loc])
        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        let value = stack.popStackValue()
        XCTAssertEqual(value.text, "REAL_BYTE(RVALUE, 1)")
        XCTAssertEqual(value.type, "BYTE")
        XCTAssertNil(value.location)
        XCTAssertEqual(loc.type, "REAL")
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

    func testLDPUsesRealRepresentationAccess() {
        let loc = Location(
            segment: 1,
            procedure: 1,
            lexLevel: 1,
            addr: 5,
            name: "RVALUE",
            type: "REAL",
            typeSource: .metadata
        )
        var stack = StackSimulator()
        stack.push(("RVALUE", "REAL"), kind: .address, location: loc)
        stack.push(("4", "INTEGER"), kind: .constant)
        stack.push(("2", "INTEGER"), kind: .constant)
        let inst = Instruction(opcode: ldp, mnemonic: "LDP")
        var gen = makeGenerator(labels: [loc])
        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        let value = stack.popStackValue()
        XCTAssertEqual(value.text, "REAL_BITS(RVALUE, 4, 2)")
        XCTAssertEqual(value.type, "INTEGER")
        XCTAssertNil(value.location)
        XCTAssertEqual(loc.type, "REAL")
        XCTAssertTrue(gen.typeConflicts.isEmpty)
    }

    func testLDM() {
        var stack = StackSimulator()
        stack.push(("ORIGIN", "POINTER"))
        let inst = Instruction(opcode: ldm, mnemonic: "LDM", params: [3])
        var gen = makeGenerator()
        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        XCTAssertEqual(stack.values.count, 3)
    }

    func testLDMUsesRealRepresentationAccess() {
        let loc = Location(
            segment: 1,
            procedure: 1,
            lexLevel: 1,
            addr: 5,
            name: "RVALUE",
            type: "REAL",
            typeSource: .metadata
        )
        var stack = StackSimulator()
        stack.push(("RVALUE", "REAL"), kind: .address, location: loc)
        let inst = Instruction(opcode: ldm, mnemonic: "LDM", params: [2])
        var gen = makeGenerator(labels: [loc])
        _ = gen.generateForInstruction(inst, stack: &stack, loc: nil)
        XCTAssertEqual(stack.peekStackValue(1).text, "REAL_WORD(RVALUE, 0)")
        XCTAssertEqual(stack.peekStackValue(0).text, "REAL_WORD(RVALUE, 1)")
        XCTAssertEqual(stack.peekStackValue(0).location?.displayName, "S1_P1_L1_A6")
        if case let .realWord(baseText, wordIndex, baseLocation, physicalLocation) = stack.peekStackValue(0).payload {
            XCTAssertEqual(baseText, "RVALUE")
            XCTAssertEqual(wordIndex, 1)
            XCTAssertEqual(baseLocation?.displayName, "RVALUE")
            XCTAssertEqual(physicalLocation?.displayName, "S1_P1_L1_A6")
        } else {
            XCTFail("Expected structured REAL word payload")
        }
        XCTAssertEqual(loc.type, "REAL")
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
