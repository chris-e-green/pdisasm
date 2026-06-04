import XCTest
@testable import pdisasm
import Foundation

final class OutputFlagTests: XCTestCase {

    /// Captures stdout output from a closure.
    private func captureOutput(_ block: () -> Void) -> String {
        let originalStdout = dup(STDOUT_FILENO)
        let pipefds = UnsafeMutablePointer<Int32>.allocate(capacity: 2)
        defer { pipefds.deallocate() }
        pipe(pipefds)
        fflush(stdout)
        dup2(pipefds[1], STDOUT_FILENO)

        block()

        fflush(stdout)
        dup2(originalStdout, STDOUT_FILENO)
        close(originalStdout)
        close(pipefds[1])
        let readFD = pipefds[0]
        var outData = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(readFD, &buffer, 4096)
            if n <= 0 { break }
            outData.append(buffer, count: n)
        }
        close(readFD)
        return String(data: outData, encoding: .utf8) ?? ""
    }

    private func makeMinimalInputs() -> (SegDictionary, [Int: CodeSegment], Set<Location>, [ProcedureIdentifier], Set<Call>) {
        let seg = Segment(codeAddress: 0, codeLength: 0, name: "TEST", segmentKind: .dataseg, textAddress: 0, segNum: 0, machineType: 0, version: 0)
        let dict = SegDictionary(segTable: [0: seg], intrinsics: [], comment: "")

        let proc = Procedure()
        proc.identifier = ProcedureIdentifier(isFunction: false, segment: 0, segmentName: "TEST", procedure: 1, procName: "MYPROC")
        proc.instructions[0] = Instruction(opcode: 0xAD, mnemonic: "RNP", params: [0], comment: "Return", stackState: ["{V: 5, T: INTEGER, K: c}"])
        proc.instructions[0]?.pseudoCode = "MYPROC := 5"
        proc.entryPoints = [0]

        let codeSeg = CodeSegment(procedureDictionary: ProcedureDictionary(procedureCount: 1, procedurePointers: [0]), procedures: [proc])
        let codeSegs: [Int: CodeSegment] = [0: codeSeg]
        let allProcedures: [ProcedureIdentifier] = [proc.identifier!]

        return (dict, codeSegs, [], allProcedures, [])
    }

    // MARK: - showDot

    func testShowDotProducesDigraph() {
        let (dict, codeSegs, locs, procs, callers) = makeMinimalInputs()
        let out = captureOutput {
            outputResults(sourceFilename: "test", segDictionary: dict, codeSegs: codeSegs, dataSegs: [], allLocations: locs, allProcedures: procs, allCallers: callers, showDot: true)
        }
        XCTAssertTrue(out.contains("digraph {"))
        XCTAssertTrue(out.contains("}"))
    }

    // MARK: - showMarkup

    func testShowMarkupTrue() {
        let (dict, codeSegs, locs, procs, callers) = makeMinimalInputs()
        let out = captureOutput {
            outputResults(sourceFilename: "test", segDictionary: dict, codeSegs: codeSegs, dataSegs: [], allLocations: locs, allProcedures: procs, allCallers: callers, showMarkup: true, showPCode: true)
        }
        XCTAssertTrue(out.contains("#  test"))
        XCTAssertTrue(out.contains("## Segment"))
        XCTAssertTrue(out.contains("```"))
    }

    func testShowMarkupFalseSuppressesMarkdown() {
        let (dict, codeSegs, locs, procs, callers) = makeMinimalInputs()
        let out = captureOutput {
            outputResults(sourceFilename: "test", segDictionary: dict, codeSegs: codeSegs, dataSegs: [], allLocations: locs, allProcedures: procs, allCallers: callers, showMarkup: false, showPCode: true)
        }
        XCTAssertFalse(out.contains("#  test"))
        XCTAssertFalse(out.contains("## Segment"))
        XCTAssertFalse(out.contains("```"))
    }

    func testShowMarkupFalseLeavesPseudocodeIntact() {
        let (dict, codeSegs, locs, procs, callers) = makeMinimalInputs()
        var markupStream = StringStream()
        outputResults(
            to: &markupStream,
            sourceFilename: "test",
            segDictionary: dict,
            codeSegs: codeSegs,
            dataSegs: [],
            allLocations: locs,
            allProcedures: procs,
            allCallers: callers,
            showMarkup: true,
            showPCode: false,
            showPseudoCode: true
        )

        var plainStream = StringStream()
        outputResults(
            to: &plainStream,
            sourceFilename: "test",
            segDictionary: dict,
            codeSegs: codeSegs,
            dataSegs: [],
            allLocations: locs,
            allProcedures: procs,
            allCallers: callers,
            showMarkup: false,
            showPCode: false,
            showPseudoCode: true
        )

        let expectedPseudocode = ["BEGIN", "  MYPROC := 5", "END"]
        for line in expectedPseudocode {
            XCTAssertTrue(markupStream.text.contains(line))
            XCTAssertTrue(plainStream.text.contains(line))
        }

        XCTAssertFalse(plainStream.text.contains("#  test"))
        XCTAssertFalse(plainStream.text.contains("## Segment"))
        XCTAssertFalse(plainStream.text.contains("```"))
    }

    // MARK: - showPCode

    func testShowPCodeTrueIncludesInstructions() {
        let (dict, codeSegs, locs, procs, callers) = makeMinimalInputs()
        let out = captureOutput {
            outputResults(sourceFilename: "test", segDictionary: dict, codeSegs: codeSegs, dataSegs: [], allLocations: locs, allProcedures: procs, allCallers: callers, showPCode: true)
        }
        XCTAssertTrue(out.contains("RNP"))
    }

    func testShowPCodeFalseSuppressesInstructions() {
        let (dict, codeSegs, locs, procs, callers) = makeMinimalInputs()
        let out = captureOutput {
            outputResults(sourceFilename: "test", segDictionary: dict, codeSegs: codeSegs, dataSegs: [], allLocations: locs, allProcedures: procs, allCallers: callers, showPCode: false)
        }
        XCTAssertFalse(out.contains("0000:"))
    }

    func testAssemblerUserCommentsRenderAndExposeEditableReference() {
        let seg = Segment(
            codeAddress: 0,
            codeLength: 0,
            name: "ASM",
            segmentKind: .unitseg,
            textAddress: 0,
            segNum: 1,
            machineType: 7,
            version: 0
        )
        let dict = SegDictionary(segTable: [1: seg], intrinsics: [], comment: "")
        let proc = Procedure()
        proc.identifier = ProcedureIdentifier(
            isFunction: false,
            isAssembly: true,
            segment: 1,
            segmentName: "ASM",
            procedure: 2,
            procName: "DOIT"
        )
        proc.instructions[0x443] = Instruction(
            opcode: 0xa4,
            mnemonic: "a4 80   LDY $80",
            comment: "decoded",
            userComment: "user note",
            isPascal: false
        )
        proc.entryPoints = [0x443]
        let codeSeg = CodeSegment(
            procedureDictionary: ProcedureDictionary(procedureCount: 1, procedurePointers: [0]),
            procedures: [proc]
        )
        let result = DisassemblyResult(
            sourceFilename: "test",
            segDictionary: dict,
            codeSegments: [1: codeSeg],
            dataSegments: [],
            allLocations: [],
            allProcedures: [proc.identifier!],
            allCallers: [],
            knownRecords: [],
            typeAliases: [:],
            scalarTypes: [:],
            constants: [:],
            subrangeTypes: [:],
            typeConflicts: [],
            diagnostics: []
        )

        let lines = renderStructuredLines(from: result)
        let assemblerLine = lines.first { $0.text.contains("LDY $80") }

        XCTAssertTrue(assemblerLine?.text.contains("; decoded; user note") == true)
        XCTAssertEqual(assemblerLine?.commentReference, InstructionReference(
            segment: 1,
            procedure: 2,
            addr: 0x443
        ))
    }

    // MARK: - showStackState

    func testShowStackStateTrueIncludesStackState() {
        let (dict, codeSegs, locs, procs, callers) = makeMinimalInputs()
        let out = captureOutput {
            outputResults(sourceFilename: "test", segDictionary: dict, codeSegs: codeSegs, dataSegs: [], allLocations: locs, allProcedures: procs, allCallers: callers, showPCode: true, showStackState: true)
        }
        XCTAssertTrue(out.contains("[{V: 5, T: INTEGER, K: c}]"))
    }

    func testShowStackStateFalseSuppressesStackState() {
        let (dict, codeSegs, locs, procs, callers) = makeMinimalInputs()
        let out = captureOutput {
            outputResults(sourceFilename: "test", segDictionary: dict, codeSegs: codeSegs, dataSegs: [], allLocations: locs, allProcedures: procs, allCallers: callers, showPCode: true, showStackState: false)
        }
        XCTAssertFalse(out.contains("[{V: 5, T: INTEGER, K: c}]"))
    }

    // MARK: - showPseudoCode

    func testShowPseudoCodeTrueIncludesBEGINEND() {
        let (dict, codeSegs, locs, procs, callers) = makeMinimalInputs()
        let out = captureOutput {
            outputResults(sourceFilename: "test", segDictionary: dict, codeSegs: codeSegs, dataSegs: [], allLocations: locs, allProcedures: procs, allCallers: callers, showPseudoCode: true)
        }
        XCTAssertTrue(out.contains("BEGIN"))
        XCTAssertTrue(out.contains("END"))
    }

    func testShowPseudoCodeFalseSuppressesBEGINEND() {
        let (dict, codeSegs, locs, procs, callers) = makeMinimalInputs()
        let out = captureOutput {
            outputResults(sourceFilename: "test", segDictionary: dict, codeSegs: codeSegs, dataSegs: [], allLocations: locs, allProcedures: procs, allCallers: callers, showPseudoCode: false)
        }
        XCTAssertFalse(out.contains("BEGIN"))
    }

    func testGlobalOutputOnlyIncludesAccessedGlobals() {
        let (dict, _, _, procs, callers) = makeMinimalInputs()
        let accessedGlobal = Location(
            segment: 0,
            procedure: 1,
            lexLevel: -1,
            addr: 2,
            name: "ACCESSED",
            type: "INTEGER"
        )
        let unaccessedGlobal = Location(
            segment: 0,
            procedure: 1,
            lexLevel: -1,
            addr: 3,
            name: "UNACCESSED",
            type: "INTEGER"
        )

        let proc = Procedure()
        proc.identifier = ProcedureIdentifier(isFunction: false, segment: 1, segmentName: "TEST", procedure: 1, procName: "MYPROC")
        proc.instructions[0] = Instruction(
            opcode: 0xC6,
            mnemonic: "LDO",
            params: [2],
            memLocation: Location(segment: 0, procedure: 1, lexLevel: -1, addr: 2)
        )
        let codeSegs = [
            1: CodeSegment(
                procedureDictionary: ProcedureDictionary(procedureCount: 1, procedurePointers: [0]),
                procedures: [proc]
            )
        ]

        let out = captureOutput {
            outputResults(
                sourceFilename: "test",
                segDictionary: dict,
                codeSegs: codeSegs,
                dataSegs: [],
                allLocations: [accessedGlobal, unaccessedGlobal],
                allProcedures: procs,
                allCallers: callers,
                showPCode: false,
                showPseudoCode: false
            )
        }

        XCTAssertTrue(out.contains("G2=ACCESSED:INTEGER"))
        XCTAssertFalse(out.contains("UNACCESSED"))
    }

    func testOutputReportsTypeConflictsOnce() {
        let (dict, codeSegs, locs, procs, callers) = makeMinimalInputs()
        let loc = Location(
            segment: 2,
            procedure: 3,
            lexLevel: 1,
            addr: 4,
            type: "REAL",
            typeSource: .metadata
        )
        let conflict = loc.assignType(
            "INTEGER",
            source: .inferred,
            evidence: "ADI"
        )!

        let out = captureOutput {
            outputResults(
                sourceFilename: "test",
                segDictionary: dict,
                codeSegs: codeSegs,
                dataSegs: [],
                allLocations: locs,
                allProcedures: procs,
                allCallers: callers,
                typeConflicts: [conflict, conflict],
                showMarkup: true
            )
        }

        XCTAssertFalse(out.contains("## Type Conflicts"))
        XCTAssertTrue(out.contains("## Diagnostics"))
        XCTAssertTrue(out.contains("WARNING: TYPE CONFLICT S2 P3 L1 A4"))
        XCTAssertTrue(out.contains("kept REAL (metadata)"))
        XCTAssertTrue(out.contains("rejected INTEGER (inferred)"))
        XCTAssertEqual(out.components(separatedBy: "TYPE CONFLICT").count - 1, 1)
    }

    func testKnownTypesOutputShowsAliasesRecordsAndOffsets() {
        let (dict, codeSegs, locs, procs, callers) = makeMinimalInputs()
        let record = PascalRecord(
            name: "WORD",
            members: [
                0: Identifier(name: "KEY", type: "ALPHA"),
                1: Identifier(name: "FIRST", type: "ITEMREF"),
                3: Identifier(name: "RIGHT", type: "WORDREF")
            ]
        )

        let out = captureOutput {
            outputResults(
                sourceFilename: "test",
                segDictionary: dict,
                codeSegs: codeSegs,
                dataSegs: [],
                allLocations: locs,
                allProcedures: procs,
                allCallers: callers,
                knownRecords: [record],
                typeAliases: [
                    "ALPHA": "ARRAY OF CHAR",
                    "ITEMREF": "^ITEM",
                    "SEGNO": "INTEGER",
                    "WORDREF": "^WORD"
                ],
                scalarTypes: [
                    "SEGKINDS": PascalScalarType(
                        name: "SEGKINDS",
                        cases: ["LINKED", "HOSTSEG", "SEGPROC"]
                    )
                ],
                constants: ["MAXSEGS": 15],
                subrangeTypes: [
                    "SEGNO": PascalSubrangeType(name: "SEGNO", lowerBound: 1, upperBound: 15)
                ],
                showMarkup: true
            )
        }

        XCTAssertTrue(out.contains("## Known Types"))
        XCTAssertTrue(out.contains("CONST"))
        XCTAssertTrue(out.contains("  MAXSEGS = 15;"))
        XCTAssertTrue(out.contains("TYPE"))
        XCTAssertTrue(out.contains("  SEGKINDS = (LINKED, HOSTSEG, SEGPROC);"))
        XCTAssertTrue(out.contains("  SEGNO = 1..15;"))
        XCTAssertTrue(out.contains("  ALPHA = ARRAY OF CHAR;"))
        XCTAssertFalse(out.contains("  SEGNO = INTEGER;"))
        XCTAssertTrue(out.contains("  WORDREF = ^WORD;"))
        XCTAssertTrue(out.contains("  WORD = RECORD"))
        XCTAssertTrue(out.contains("    KEY: ALPHA; (* offset 0 *)"))
        XCTAssertTrue(out.contains("    FIRST: ITEMREF; (* offset 1 *)"))
        XCTAssertTrue(out.contains("    RIGHT: WORDREF; (* offset 3 *)"))
        XCTAssertTrue(out.contains("  END;"))
    }

    func testKnownTypesOutputShowsVariantRecordMembers() {
        let (dict, codeSegs, locs, procs, callers) = makeMinimalInputs()
        let record = PascalRecord(
            name: "NODE",
            members: [
                0: Identifier(name: "KIND", type: "INTEGER"),
                1: Identifier(name: "IVALUE", type: "INTEGER")
            ],
            allMembers: [
                PascalRecordMember(offset: 0, identifier: Identifier(name: "KIND", type: "INTEGER")),
                PascalRecordMember(offset: 1, identifier: Identifier(name: "IVALUE", type: "INTEGER"), variantLabel: "0"),
                PascalRecordMember(offset: 1, identifier: Identifier(name: "RVALUE", type: "REAL"), variantLabel: "1")
            ]
        )

        let out = captureOutput {
            outputResults(
                sourceFilename: "test",
                segDictionary: dict,
                codeSegs: codeSegs,
                dataSegs: [],
                allLocations: locs,
                allProcedures: procs,
                allCallers: callers,
                knownRecords: [record],
                showMarkup: true
            )
        }

        XCTAssertTrue(out.contains("  NODE = RECORD"))
        XCTAssertTrue(out.contains("    KIND: INTEGER; (* offset 0 *)"))
        XCTAssertTrue(out.contains("    IVALUE: INTEGER; (* variant 0, offset 1 *)"))
        XCTAssertTrue(out.contains("    RVALUE: REAL; (* variant 1, offset 1 *)"))
    }

    func testKnownTypesOutputFlagsUnknownFinalTypes() {
        let (dict, codeSegs, locs, procs, callers) = makeMinimalInputs()
        let record = PascalRecord(
            name: "WORD",
            members: [
                0: Identifier(name: "KEY", type: "ALPHA"),
                1: Identifier(name: "NEXT", type: "ITEMREF")
            ]
        )

        let out = captureOutput {
            outputResults(
                sourceFilename: "test",
                segDictionary: dict,
                codeSegs: codeSegs,
                dataSegs: [],
                allLocations: locs,
                allProcedures: procs,
                allCallers: callers,
                knownRecords: [record],
                typeAliases: [
                    "ALPHA": "ARRAY OF GLYPH",
                    "ITEMREF": "^ITEM"
                ],
                showMarkup: true
            )
        }

        XCTAssertTrue(out.contains("## Diagnostics"))
        XCTAssertTrue(out.contains("WARNING: TYPE ALPHA resolves to unknown final type GLYPH"))
        XCTAssertTrue(out.contains("WARNING: TYPE ITEMREF resolves to unknown final type ITEM"))
        XCTAssertTrue(out.contains("WARNING: RECORD WORD.KEY at offset 0 resolves to unknown final type GLYPH"))
        XCTAssertTrue(out.contains("WARNING: RECORD WORD.NEXT at offset 1 resolves to unknown final type ITEM"))
    }

    func testOutputFlagsUndefinedTypesUsedByCode() {
        let (dict, codeSegs, _, _, callers) = makeMinimalInputs()
        let location = Location(
            segment: 1,
            procedure: 2,
            lexLevel: 1,
            addr: 4,
            name: "CURRENT",
            type: "ITEMREF",
            typeSource: .metadata
        )
        let procedure = ProcedureIdentifier(
            isFunction: true,
            segment: 1,
            segmentName: "TEST",
            procedure: 2,
            procName: "LOOKUP",
            parameters: [
                Identifier(name: "KEY", type: "ALPHA"),
                Identifier(name: "NEXT", type: "^NODE"),
                Identifier(name: "COUNT", type: "INTEGER")
            ],
            returnType: "ITEMREF"
        )

        let out = captureOutput {
            outputResults(
                sourceFilename: "test",
                segDictionary: dict,
                codeSegs: codeSegs,
                dataSegs: [],
                allLocations: [location],
                allProcedures: [procedure],
                allCallers: callers,
                typeAliases: [
                    "ALPHA": "PACKED ARRAY[1..8] OF CHAR"
                ],
                showMarkup: true
            )
        }

        XCTAssertTrue(out.contains("## Diagnostics"))
        XCTAssertTrue(out.contains("WARNING: LOCATION CURRENT uses undefined type ITEMREF"))
        XCTAssertTrue(out.contains("WARNING: PROCEDURE TEST.LOOKUP parameter NEXT uses undefined type NODE"))
        XCTAssertTrue(out.contains("WARNING: FUNCTION TEST.LOOKUP return type uses undefined type ITEMREF"))
        XCTAssertFalse(out.contains("parameter KEY uses undefined type"))
        XCTAssertFalse(out.contains("undefined type CHAR"))
    }
}
