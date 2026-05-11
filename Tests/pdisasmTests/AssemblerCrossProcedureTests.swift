import XCTest
@testable import pdisasm
import Foundation

final class AssemblerCrossProcedureTests: XCTestCase {
    private func makeAssemblerProcedure(
        segment: Int,
        procedure: Int,
        segmentName: String = "TEST",
        procName: String,
        segmentEndAddress: Int,
        instructions: [Int: Instruction] = [:]
    ) -> Procedure {
        let proc = Procedure()
        proc.identifier = ProcedureIdentifier(
            isFunction: false,
            isAssembly: true,
            segment: segment,
            segmentName: segmentName,
            procedure: procedure,
            procName: procName
        )
        proc.segmentEndAddress = segmentEndAddress
        proc.instructions = instructions
        return proc
    }

    func testResolveAssemblerCrossProcedureJSRUsesOwningProcedureRange() {
        let prefix = makeAssemblerProcedure(
            segment: 1,
            procedure: 1,
            procName: "PREFIX",
            segmentEndAddress: 0x0d00
        )
        let procA = makeAssemblerProcedure(
            segment: 1,
            procedure: 2,
            procName: "A",
            segmentEndAddress: 0x0e00
        )
        let callInstruction = Instruction(
            opcode: 0x20,
            mnemonic: "20 100d JSR $0d10",
            params: [0x0d10],
            isPascal: false,
            stackState: []
        )
        let procB = makeAssemblerProcedure(
            segment: 1,
            procedure: 3,
            procName: "B",
            segmentEndAddress: 0x0f00,
            instructions: [0x0e20: callInstruction]
        )

        let codeSeg = CodeSegment(
            procedureDictionary: ProcedureDictionary(procedureCount: 3, procedurePointers: []),
            procedures: [prefix, procA, procB]
        )
        var allProcedures: [ProcedureIdentifier] = []
        var allCallers: Set<Call> = []

        resolveAssemblerProcedureTargets(
            in: codeSeg,
            allProcedures: &allProcedures,
            allCallers: &allCallers
        )

        XCTAssertEqual(prefix.segmentStartAddress, 0x0000)
        XCTAssertEqual(procA.segmentStartAddress, 0x0d00)
        XCTAssertEqual(procB.segmentStartAddress, 0x0e00)

        XCTAssertEqual(procB.instructions[0x0e20]?.destination?.procedure, 2)
        XCTAssertEqual(procB.instructions[0x0e20]?.destination?.addr, 0x0d10)

        XCTAssertTrue(
            allCallers.contains(
                Call(
                    from: Location(segment: 1, procedure: 3, lexLevel: 0),
                    to: Location(segment: 1, procedure: 2, lexLevel: 0)
                )
            )
        )
        XCTAssertEqual(allProcedures.count, 3)
    }

    func testOutputShowsResolvedAssemblerProcedureAndCaller() {
        let prefix = makeAssemblerProcedure(
            segment: 1,
            procedure: 1,
            procName: "PREFIX",
            segmentEndAddress: 0x0d00
        )
        let callInstruction = Instruction(
            opcode: 0x20,
            mnemonic: "20 100d JSR $0d10",
            params: [0x0d10],
            isPascal: false,
            stackState: []
        )
        let procA = makeAssemblerProcedure(
            segment: 1,
            procedure: 2,
            procName: "A",
            segmentEndAddress: 0x0e00
        )
        let procB = makeAssemblerProcedure(
            segment: 1,
            procedure: 3,
            procName: "B",
            segmentEndAddress: 0x0f00,
            instructions: [0x0e20: callInstruction]
        )
        let codeSeg = CodeSegment(
            procedureDictionary: ProcedureDictionary(procedureCount: 3, procedurePointers: []),
            procedures: [prefix, procA, procB]
        )
        var allProcedures: [ProcedureIdentifier] = []
        var allCallers: Set<Call> = []
        resolveAssemblerProcedureTargets(
            in: codeSeg,
            allProcedures: &allProcedures,
            allCallers: &allCallers
        )

        let seg = Segment(
            codeAddress: 0,
            codeLength: 0,
            name: "TEST",
            segmentKind: .dataseg,
            textAddress: 0,
            segNum: 1,
            machineType: 7,
            version: 0
        )
        let segDict = SegDictionary(segTable: [1: seg], intrinsics: [], comment: "")
        let codeSegs: [Int: CodeSegment] = [1: codeSeg]
        var stream = StringStream()

        outputResults(
            to: &stream,
            sourceFilename: "test.bin",
            segDictionary: segDict,
            codeSegs: codeSegs,
            dataSegs: [],
            allLocations: [],
            allProcedures: allProcedures,
            allCallers: allCallers,
            verbose: false,
            showMarkup: true,
            showPCode: true,
            showPseudoCode: false,
            showDot: false
        )

        XCTAssertTrue(stream.text.contains("Callers: TEST.B"))
        XCTAssertTrue(stream.text.contains("JSR $0d10 -> TEST.A @ $0d10"))
    }

    func testResolveAssemblerCrossProcedureJMPUsesTransferSemantics() {
        let prefix = makeAssemblerProcedure(
            segment: 1,
            procedure: 1,
            procName: "PREFIX",
            segmentEndAddress: 0x0d00
        )
        let procA = makeAssemblerProcedure(
            segment: 1,
            procedure: 2,
            procName: "A",
            segmentEndAddress: 0x0e00
        )
        let jumpInstruction = Instruction(
            opcode: 0x4c,
            mnemonic: "4c 100d JMP $0d10",
            params: [0x0d10],
            isPascal: false,
            stackState: []
        )
        let procB = makeAssemblerProcedure(
            segment: 1,
            procedure: 3,
            procName: "B",
            segmentEndAddress: 0x0f00,
            instructions: [0x0e20: jumpInstruction]
        )

        let codeSeg = CodeSegment(
            procedureDictionary: ProcedureDictionary(procedureCount: 3, procedurePointers: []),
            procedures: [prefix, procA, procB]
        )
        var allProcedures: [ProcedureIdentifier] = []
        var allCallers: Set<Call> = []

        resolveAssemblerProcedureTargets(
            in: codeSeg,
            allProcedures: &allProcedures,
            allCallers: &allCallers
        )

        XCTAssertEqual(procB.instructions[0x0e20]?.destination?.procedure, 2)
        XCTAssertEqual(procB.instructions[0x0e20]?.destination?.addr, 0x0d10)
        XCTAssertEqual(procB.instructions[0x0e20]?.comment, "tailcall")
        XCTAssertTrue(
            allCallers.contains(
                Call(
                    from: Location(segment: 1, procedure: 3, lexLevel: 0),
                    to: Location(segment: 1, procedure: 2, lexLevel: 0)
                )
            )
        )
    }

    func testOutputShowsResolvedAssemblerTransferForJMP() {
        let prefix = makeAssemblerProcedure(
            segment: 1,
            procedure: 1,
            procName: "PREFIX",
            segmentEndAddress: 0x0d00
        )
        let jumpInstruction = Instruction(
            opcode: 0x4c,
            mnemonic: "4c 100d JMP $0d10",
            params: [0x0d10],
            isPascal: false,
            stackState: []
        )
        let procA = makeAssemblerProcedure(
            segment: 1,
            procedure: 2,
            procName: "A",
            segmentEndAddress: 0x0e00
        )
        let procB = makeAssemblerProcedure(
            segment: 1,
            procedure: 3,
            procName: "B",
            segmentEndAddress: 0x0f00,
            instructions: [0x0e20: jumpInstruction]
        )
        let codeSeg = CodeSegment(
            procedureDictionary: ProcedureDictionary(procedureCount: 3, procedurePointers: []),
            procedures: [prefix, procA, procB]
        )
        var allProcedures: [ProcedureIdentifier] = []
        var allCallers: Set<Call> = []
        resolveAssemblerProcedureTargets(
            in: codeSeg,
            allProcedures: &allProcedures,
            allCallers: &allCallers
        )

        let seg = Segment(
            codeAddress: 0,
            codeLength: 0,
            name: "TEST",
            segmentKind: .dataseg,
            textAddress: 0,
            segNum: 1,
            machineType: 7,
            version: 0
        )
        let segDict = SegDictionary(segTable: [1: seg], intrinsics: [], comment: "")
        let codeSegs: [Int: CodeSegment] = [1: codeSeg]
        var stream = StringStream()

        outputResults(
            to: &stream,
            sourceFilename: "test.bin",
            segDictionary: segDict,
            codeSegs: codeSegs,
            dataSegs: [],
            allLocations: [],
            allProcedures: allProcedures,
            allCallers: allCallers,
            verbose: false,
            showMarkup: true,
            showPCode: true,
            showPseudoCode: false,
            showDot: false
        )

        XCTAssertTrue(stream.text.contains("Callers: TEST.B"))
        XCTAssertTrue(stream.text.contains("JMP $0d10 ; tailcall => TEST.A @ $0d10"))
    }

    func testDecodedAssemblerJSRMarksCalleeEntryPoint() throws {
        func decodeProcedureFromBytes(
            _ bytes: [UInt8],
            segment: Int,
            procedure: Int,
            procName: String,
            segmentEndAddress: Int
        ) throws -> Procedure {
            let code = Data(bytes)
            var proc = Procedure()
            proc.segmentEndAddress = segmentEndAddress
            proc.identifier = ProcedureIdentifier(
                isFunction: false,
                isAssembly: true,
                segment: segment,
                segmentName: "TEST",
                procedure: procedure,
                procName: procName
            )
            var assemblerEntryPoints: Set<Int> = []
            try decodeAssemblerProcedure(
                segmentNumber: segment,
                procedureNumber: procedure,
                proc: &proc,
                code: code,
                addr: code.count - 2,
                assemblerEntryPoints: &assemblerEntryPoints
            )
            return proc
        }

        // Callee procedure includes an RTS at $0087.
        var calleeBytes: [UInt8] = []
        calleeBytes += Array(repeating: 0xEA, count: 0x87)
        calleeBytes += [0x60]
        calleeBytes += [0x00, 0x00]  // interp
        calleeBytes += [0x00, 0x00]  // proc
        calleeBytes += [0x00, 0x00]  // seg
        calleeBytes += [0x00, 0x00]  // base
        let calleeEnterPos = calleeBytes.count
        calleeBytes += [UInt8(calleeEnterPos), 0x00]
        calleeBytes += [0x01, 0x00]

        // Caller JSRs to $0087.
        var callerBytes: [UInt8] = []
        callerBytes += [0x20, 0x87, 0x00]
        callerBytes += [0x60]
        callerBytes += [0x00, 0x00]  // interp
        callerBytes += [0x00, 0x00]  // proc
        callerBytes += [0x00, 0x00]  // seg
        callerBytes += [0x00, 0x00]  // base
        let callerEnterPos = callerBytes.count
        callerBytes += [UInt8(callerEnterPos), 0x00]
        callerBytes += [0x02, 0x00]

        let callee = try decodeProcedureFromBytes(
            calleeBytes,
            segment: 1,
            procedure: 1,
            procName: "CALLEE",
            segmentEndAddress: 0x0100
        )
        let caller = try decodeProcedureFromBytes(
            callerBytes,
            segment: 1,
            procedure: 2,
            procName: "CALLER",
            segmentEndAddress: 0x0200
        )

        let codeSeg = CodeSegment(
            procedureDictionary: ProcedureDictionary(procedureCount: 2, procedurePointers: []),
            procedures: [callee, caller]
        )
        var allProcedures: [ProcedureIdentifier] = []
        var allCallers: Set<Call> = []

        resolveAssemblerProcedureTargets(
            in: codeSeg,
            allProcedures: &allProcedures,
            allCallers: &allCallers
        )

        XCTAssertEqual(caller.instructions[0]?.params, [0x0087])
        XCTAssertTrue(callee.entryPoints.contains(0x0087))
    }
}
