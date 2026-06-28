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

    private func pascalSourceLines(
        for identifier: ProcedureIdentifier,
        sourceMetadata: PascalSourceMetadata? = nil,
        configureProcedure: ((Procedure) -> Void)? = nil
    ) -> [String] {
        let (dict, codeSegments, locations, _, callers) = makeMinimalInputs()
        if let procedure = codeSegments[0]?.procedures[0] {
            procedure.identifier = identifier
            configureProcedure?(procedure)
        }
        let result = DisassemblyResult(
            sourceFilename: "test",
            segDictionary: dict,
            codeSegments: codeSegments,
            dataSegments: [],
            allLocations: locations,
            allProcedures: [identifier],
            allCallers: callers,
            knownRecords: [],
            typeAliases: [:],
            scalarTypes: [:],
            constants: [:],
            subrangeTypes: [:],
            typeConflicts: [],
            diagnostics: [],
            sourceMetadata: sourceMetadata
        )
        return renderPascalSourceLines(from: result, showMarkup: false)
    }

    // MARK: - Pascal declaration sections

    func testPascalDeclarationSectionsRenderLabelsConstantsTypesAndVariables() {
        let record = PascalRecord(
            name: "NODE",
            members: [
                0: Identifier(name: "KIND", type: "SEGKINDS"),
                1: Identifier(name: "COUNT", type: "SEGNO")
            ]
        )
        let lines = renderPascalDeclarationSectionLines(
            labels: ["LAB20", "LAB10", "LAB20"],
            records: [record],
            aliases: [
                "ALPHA": "PACKED ARRAY[1..8] OF CHAR",
                "NODE": "INTEGER",
                "SEGNO": "INTEGER"
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
            variables: [
                Location(segment: 1, procedure: 2, lexLevel: 0, addr: 4, name: "LOCAL_B", type: "CHAR"),
                Location(segment: 0, procedure: nil, lexLevel: -1, addr: 1, name: "GLOBAL_A", type: "INTEGER")
            ]
        )

        XCTAssertEqual(lines, [
            "LABEL",
            "  LAB10, LAB20;",
            "",
            "CONST",
            "  MAXSEGS = 15;",
            "",
            "TYPE",
            "  SEGKINDS = (LINKED, HOSTSEG, SEGPROC);",
            "  SEGNO = 1..15;",
            "  ALPHA = PACKED ARRAY[1..8] OF CHAR;",
            "  NODE = RECORD",
            "    KIND: SEGKINDS; (* offset 0 *)",
            "    COUNT: SEGNO; (* offset 1 *)",
            "  END;",
            "",
            "VAR",
            "  GLOBAL_A: INTEGER;",
            "  LOCAL_B: CHAR;"
        ])
    }

    func testPascalDeclarationSectionsRenderRichConstants() {
        let lines = renderPascalDeclarationSectionLines(
            constantValues: [
                "ENABLED": .boolean(true),
                "GREETING": .string("'HELLO'"),
                "RATIO": .real("3.125")
            ]
        )

        XCTAssertEqual(lines, [
            "CONST",
            "  ENABLED = TRUE;",
            "  GREETING = 'HELLO';",
            "  RATIO = 3.125;"
        ])
    }

    func testPascalDeclarationSectionsSkipParameterLocationsAndDeduplicateVariables() {
        let param = Location(
            segment: 1,
            procedure: 2,
            lexLevel: 0,
            addr: 1,
            isParam: true,
            name: "ARG",
            type: "INTEGER"
        )
        let first = Location(segment: 1, procedure: 2, lexLevel: 0, addr: 2, name: "TEMP", type: "INTEGER")
        let duplicate = Location(segment: 1, procedure: 2, lexLevel: 0, addr: 3, name: "TEMP", type: "INTEGER")

        let lines = renderPascalDeclarationSectionLines(variables: [param, duplicate, first])

        XCTAssertEqual(lines, [
            "VAR",
            "  TEMP: INTEGER;"
        ])
    }

    func testPascalDeclarationSectionsReturnEmptyWhenNothingIsKnown() {
        XCTAssertTrue(renderPascalDeclarationSectionLines().isEmpty)
    }

    func testOutputResultsEmitsRunLevelPascalDeclarations() {
        let (dict, codeSegs, _, procs, callers) = makeMinimalInputs()
        let accessedGlobal = Location(
            segment: 0,
            procedure: nil,
            lexLevel: -1,
            addr: 7,
            name: "GLOBAL_VALUE",
            type: "SEGNO"
        )
        let unaccessedGlobal = Location(
            segment: 0,
            procedure: nil,
            lexLevel: -1,
            addr: 8,
            name: "UNUSED_GLOBAL",
            type: "INTEGER"
        )
        let dataSegmentGlobal = Location(
            segment: 3,
            procedure: nil,
            lexLevel: nil,
            addr: 2,
            name: "DATA_VALUE",
            type: "CHAR"
        )
        codeSegs[0]?.procedures.first?.instructions[1] = Instruction(
            opcode: lao,
            mnemonic: "LAO",
            memLocation: accessedGlobal
        )

        let out = captureOutput {
            outputResults(
                sourceFilename: "test",
                segDictionary: dict,
                codeSegs: codeSegs,
                dataSegs: [3],
                allLocations: [accessedGlobal, unaccessedGlobal, dataSegmentGlobal],
                allProcedures: procs,
                allCallers: callers,
                typeAliases: ["SEGNO": "INTEGER"],
                constants: ["MAXSEGS": 15],
                subrangeTypes: [
                    "SEGNO": PascalSubrangeType(name: "SEGNO", lowerBound: 1, upperBound: 15)
                ],
                showMarkup: true
            )
        }

        XCTAssertTrue(out.contains("## Declarations"))
        XCTAssertTrue(out.contains("CONST\n  MAXSEGS = 15;"))
        XCTAssertTrue(out.contains("TYPE\n  SEGNO = 1..15;"))
        XCTAssertTrue(out.contains("VAR\n  DATA_VALUE: CHAR;"))
        XCTAssertTrue(out.contains("  GLOBAL_VALUE: SEGNO;"))
        XCTAssertFalse(out.contains("UNUSED_GLOBAL: INTEGER;"))
    }

    func testPascalSourceEmitsRunLevelDeclarationsAndDataSegmentGlobals() {
        let (dict, codeSegs, _, procs, callers) = makeMinimalInputs()
        let dataSegmentGlobal = Location(
            segment: 3,
            procedure: nil,
            addr: 2,
            name: "DATA_VALUE",
            type: "SEGNO"
        )
        let result = DisassemblyResult(
            sourceFilename: "test",
            segDictionary: dict,
            codeSegments: codeSegs,
            dataSegments: [3],
            allLocations: [dataSegmentGlobal],
            allProcedures: procs,
            allCallers: callers,
            knownRecords: [],
            typeAliases: ["SEGNO": "INTEGER"],
            scalarTypes: [:],
            constants: ["MAXSEGS": 15],
            subrangeTypes: [
                "SEGNO": PascalSubrangeType(name: "SEGNO", lowerBound: 1, upperBound: 15)
            ],
            typeConflicts: [],
            diagnostics: []
        )

        let lines = renderPascalSourceLines(from: result, showMarkup: false)

        XCTAssertTrue(lines.contains("CONST"))
        XCTAssertTrue(lines.contains("  MAXSEGS = 15;"))
        XCTAssertTrue(lines.contains("TYPE"))
        XCTAssertTrue(lines.contains("  SEGNO = 1..15;"))
        XCTAssertTrue(lines.contains("VAR"))
        XCTAssertTrue(lines.contains("  DATA_VALUE: SEGNO;"))
        XCTAssertLessThan(lines.firstIndex(of: "VAR")!, lines.firstIndex(of: "PROCEDURE MYPROC;")!)
    }

    func testPascalSourceEmitsProcedureLabelsAndLocalVariables() {
        let (dict, codeSegs, _, procs, callers) = makeMinimalInputs()
        let procedure = codeSegs[0]!.procedures[0]
        procedure.instructions[1] = Instruction(opcode: ujp, mnemonic: "UJP")
        procedure.instructions[1]?.pseudoCode = "GOTO LAB20"
        procedure.instructions[2] = Instruction(opcode: ujp, mnemonic: "UJP")
        procedure.instructions[2]?.pseudoCode = "GOTO LAB20"
        procedure.instructions[20] = Instruction(opcode: rnp, mnemonic: "RNP")
        procedure.instructions[20]?.prePseudoCode = ["LAB20:"]

        let local = Location(
            segment: 0,
            procedure: 1,
            lexLevel: 0,
            addr: 2,
            name: "LOCAL_VALUE",
            type: "INTEGER"
        )
        let temporary = Location(
            segment: 0,
            procedure: 1,
            lexLevel: 0,
            addr: 3,
            name: "TEMP1",
            type: "BOOLEAN",
            typeSource: .inferred
        )
        let parameter = Location(
            segment: 0,
            procedure: 1,
            lexLevel: 0,
            addr: 1,
            isParam: true,
            name: "ARG",
            type: "INTEGER"
        )
        let otherProcedureLocal = Location(
            segment: 0,
            procedure: 2,
            lexLevel: 0,
            addr: 1,
            name: "OTHER_LOCAL",
            type: "CHAR"
        )
        let procedureIdentity = Location(
            segment: 0,
            procedure: 1,
            lexLevel: 0
        )
        let result = DisassemblyResult(
            sourceFilename: "test",
            segDictionary: dict,
            codeSegments: codeSegs,
            dataSegments: [],
            allLocations: [
                local,
                temporary,
                parameter,
                otherProcedureLocal,
                procedureIdentity,
            ],
            allProcedures: procs,
            allCallers: callers,
            knownRecords: [],
            typeAliases: [:],
            scalarTypes: [:],
            constants: [:],
            subrangeTypes: [:],
            typeConflicts: [],
            diagnostics: []
        )

        let lines = renderPascalSourceLines(from: result, showMarkup: false)

        XCTAssertEqual(lines.filter { $0 == "  LAB20;" }.count, 1)
        XCTAssertTrue(lines.contains("LABEL"))
        XCTAssertTrue(lines.contains("VAR"))
        XCTAssertTrue(lines.contains("  LOCAL_VALUE: INTEGER;"))
        XCTAssertTrue(lines.contains("  TEMP1: BOOLEAN;"))
        XCTAssertFalse(lines.contains("  ARG: INTEGER;"))
        XCTAssertFalse(lines.contains("  OTHER_LOCAL: CHAR;"))
        XCTAssertFalse(lines.contains("  S0_P1_L0: UNKNOWN;"))
        XCTAssertLessThan(lines.firstIndex(of: "LABEL")!, lines.firstIndex(of: "BEGIN")!)
        XCTAssertLessThan(lines.firstIndex(of: "VAR")!, lines.firstIndex(of: "BEGIN")!)
    }

    func testPascalSourceUsesStructuredCFGRegions() {
        let identifier = ProcedureIdentifier(
            isFunction: false,
            segment: 0,
            segmentName: "TEST",
            procedure: 1,
            procName: "CHOOSE"
        )
        let lines = pascalSourceLines(
            for: identifier,
            configureProcedure: { procedure in
                procedure.instructions = [
                    0: Instruction(
                        opcode: fjp,
                        mnemonic: "FJP",
                        params: [4],
                        pseudoCode: "IF READY THEN BEGIN"
                    ),
                    2: Instruction(
                        opcode: nop,
                        mnemonic: "NOP",
                        pseudoCode: "SELECT_A()"
                    ),
                    3: Instruction(
                        opcode: ujp,
                        mnemonic: "UJP",
                        params: [6],
                        pseudoCode: "END ELSE BEGIN"
                    ),
                    4: Instruction(
                        opcode: nop,
                        mnemonic: "NOP",
                        pseudoCode: "SELECT_B()"
                    ),
                    5: Instruction(
                        opcode: ujp,
                        mnemonic: "UJP",
                        params: [6]
                    ),
                    6: Instruction(
                        opcode: rnp,
                        mnemonic: "RNP",
                        prePseudoCode: ["END (* IF READY *)"]
                    ),
                ]
            }
        )

        XCTAssertTrue(lines.contains("  IF READY THEN"))
        XCTAssertTrue(lines.contains("    SELECT_A();"))
        XCTAssertTrue(lines.contains("  ELSE"))
        XCTAssertTrue(lines.contains("    SELECT_B();"))
        XCTAssertFalse(lines.contains("  IF READY THEN BEGIN"))
        XCTAssertFalse(lines.contains("  END ELSE BEGIN"))
        XCTAssertFalse(lines.contains("  END (* IF READY *)"))
    }

    func testPascalSourceDeclaresOnlyCFGGeneratedGotoLabels() {
        let identifier = ProcedureIdentifier(
            isFunction: false,
            segment: 0,
            segmentName: "TEST",
            procedure: 1,
            procName: "TRANSFER"
        )
        let lines = pascalSourceLines(
            for: identifier,
            configureProcedure: { procedure in
                procedure.instructions = [
                    0: Instruction(
                        opcode: ujp,
                        mnemonic: "UJP",
                        params: [4],
                        pseudoCode: "GOTO LAB999"
                    ),
                    2: Instruction(
                        opcode: ujp,
                        mnemonic: "UJP",
                        params: [4]
                    ),
                    4: Instruction(
                        opcode: nop,
                        mnemonic: "NOP",
                        pseudoCode: "TARGET()",
                        prePseudoCode: ["LAB999:"]
                    ),
                    5: Instruction(opcode: rnp, mnemonic: "RNP"),
                ]
            }
        )

        XCTAssertEqual(lines.filter { $0 == "  LAB4;" }.count, 1)
        XCTAssertEqual(lines.filter { $0 == "  GOTO LAB4;" }.count, 2)
        XCTAssertEqual(lines.filter { $0 == "  LAB4:" }.count, 1)
        XCTAssertFalse(lines.contains("  LAB999;"))
        XCTAssertFalse(lines.contains("  LAB999:"))
    }

    func testPascalSourceRendersGroupedProcedureParameters() {
        let identifier = ProcedureIdentifier(
            isFunction: false,
            segment: 0,
            procedure: 2,
            procName: "UPDATE",
            parameters: [
                Identifier(name: "X", type: "INTEGER", parameterMode: .value),
                Identifier(name: "Y", type: "INTEGER", parameterMode: .value),
                Identifier(name: "FLAG", type: "BOOLEAN", parameterMode: .value)
            ]
        )

        XCTAssertTrue(
            pascalSourceLines(for: identifier).contains(
                "PROCEDURE UPDATE(X, Y: INTEGER; FLAG: BOOLEAN);"
            )
        )
    }

    func testPascalSourceRendersFunctionReturnType() {
        let identifier = ProcedureIdentifier(
            isFunction: true,
            segment: 0,
            procedure: 3,
            procName: "LOOKUP",
            parameters: [
                Identifier(name: "INDEX", type: "INTEGER", parameterMode: .value)
            ],
            returnType: "CHAR"
        )

        XCTAssertTrue(
            pascalSourceLines(for: identifier).contains(
                "FUNCTION LOOKUP(INDEX: INTEGER): CHAR;"
            )
        )
    }

    func testPascalSourceRendersEmptyProcedureParameterListWithoutParentheses() {
        let identifier = ProcedureIdentifier(
            isFunction: false,
            segment: 0,
            procedure: 4,
            procName: "RESET"
        )

        XCTAssertTrue(pascalSourceLines(for: identifier).contains("PROCEDURE RESET;"))
    }

    func testPascalSourceAnnotatesUncertainSignatureParts() {
        let identifier = ProcedureIdentifier(
            isFunction: true,
            segment: 0,
            procedure: 5,
            parameters: [
                Identifier(name: "VALUE", type: "UNKNOWN"),
                Identifier(
                    name: "COUNT",
                    type: "INTEGER",
                    typeSource: .inferred,
                    parameterMode: .value,
                    parameterModeSource: .inferred
                )
            ],
            returnType: "REAL",
            returnTypeSource: .inferred
        )

        XCTAssertTrue(
            pascalSourceLines(for: identifier).contains(
                "FUNCTION FUNC5(VALUE: UNKNOWN; COUNT: INTEGER): REAL;"
                    + " (* uncertain signature: name generated; VALUE type unknown;"
                    + " VALUE mode unknown; COUNT type inferred;"
                    + " COUNT mode inferred as value; return type inferred *)"
            )
        )
    }

    func testPascalSourceRendersExplicitAndInferredVariableModes() {
        let identifier = ProcedureIdentifier(
            isFunction: false,
            segment: 0,
            procedure: 6,
            procName: "SWAP",
            parameters: [
                Identifier(name: "LEFT", type: "INTEGER", parameterMode: .variable),
                Identifier(name: "RIGHT", type: "INTEGER", parameterMode: .variable),
                Identifier(
                    name: "COUNT",
                    type: "INTEGER",
                    parameterMode: .value,
                    parameterModeSource: .inferred
                )
            ]
        )

        XCTAssertTrue(
            pascalSourceLines(for: identifier).contains(
                "PROCEDURE SWAP(VAR LEFT, RIGHT: INTEGER; COUNT: INTEGER);"
                    + " (* uncertain signature: COUNT mode inferred as value *)"
            )
        )
    }

    func testPascalSourceCanonicalizesFunctionResultAssignment() {
        let resultLocation = Location(
            segment: 0,
            procedure: 7,
            lexLevel: 1,
            addr: 1,
            isParam: true,
            name: "TEST.CALCULATE",
            type: "INTEGER"
        )
        let identifier = ProcedureIdentifier(
            isFunction: true,
            segment: 0,
            procedure: 7,
            procName: "CALCULATE",
            returnType: "INTEGER"
        )
        identifier.returnLocation = resultLocation

        let lines = pascalSourceLines(for: identifier) { procedure in
            procedure.instructions[0]?.pseudoCodeStatement = .assignment(
                targetValue: StackValue(
                    text: resultLocation.displayName,
                    type: "INTEGER",
                    kind: .address,
                    location: resultLocation
                ),
                targetText: resultLocation.displayName,
                source: "42"
            )
        }

        XCTAssertTrue(lines.contains("FUNCTION CALCULATE: INTEGER;"))
        XCTAssertTrue(lines.contains("  CALCULATE := 42;"))
        XCTAssertFalse(lines.contains("  TEST.CALCULATE := 42;"))
    }

    func testPascalSourceWrapsStandaloneBinaryInProgram() {
        let identifier = ProcedureIdentifier(
            isFunction: false,
            segment: 0,
            procedure: 1,
            procName: "MAIN"
        )

        let lines = pascalSourceLines(for: identifier)

        XCTAssertEqual(lines.first, "PROGRAM test;")
        XCTAssertEqual(Array(lines.suffix(2)), ["BEGIN", "END."])
        XCTAssertTrue(lines.contains("(* Segment TEST [0] *)"))
    }

    func testPascalSourceRendersMetadataDrivenUnitAndUses() {
        let identifier = ProcedureIdentifier(
            isFunction: false,
            segment: 0,
            procedure: 1,
            procName: "INITIALIZE"
        )
        let metadata = PascalSourceMetadata(
            kind: .unit,
            name: "TOOLS",
            uses: ["SYSTEM", "IO"],
            interfaceSegments: [0],
            implementationSegments: [0]
        )

        let lines = pascalSourceLines(
            for: identifier,
            sourceMetadata: metadata
        )

        XCTAssertEqual(lines.first, "UNIT TOOLS;")
        XCTAssertTrue(lines.contains("INTERFACE"))
        XCTAssertTrue(lines.contains("  IO, SYSTEM;"))
        XCTAssertTrue(lines.contains("IMPLEMENTATION"))
        XCTAssertEqual(lines.last, "END.")
        XCTAssertEqual(
            lines.filter { $0 == "PROCEDURE INITIALIZE;" }.count,
            2
        )
    }

    func testPascalSourceUnitWithoutBoundariesDocumentsLimitation() {
        let identifier = ProcedureIdentifier(
            isFunction: false,
            segment: 0,
            procedure: 1,
            procName: "INITIALIZE"
        )

        let lines = pascalSourceLines(
            for: identifier,
            sourceMetadata: PascalSourceMetadata(kind: .unit, name: "TOOLS")
        )

        XCTAssertTrue(lines.contains {
            $0.contains("INTERFACE declarations are not recoverable")
        })
    }

    func testPascalSourceGroupsAndAnnotatesSegmentsDeterministically() {
        let first = Segment(
            codeAddress: 0,
            codeLength: 0,
            name: "FIRST",
            segmentKind: .linked,
            textAddress: 0,
            segNum: 1,
            machineType: 0,
            version: 0
        )
        let second = Segment(
            codeAddress: 0,
            codeLength: 0,
            name: "HELPER",
            segmentKind: .segproc,
            textAddress: 0,
            segNum: 2,
            machineType: 0,
            version: 0
        )
        let result = DisassemblyResult(
            sourceFilename: "GROUPED",
            segDictionary: SegDictionary(
                segTable: [2: second, 1: first],
                intrinsics: [],
                comment: ""
            ),
            codeSegments: [
                2: CodeSegment(
                    procedureDictionary: ProcedureDictionary(
                        procedureCount: 0,
                        procedurePointers: []
                    ),
                    procedures: []
                ),
                1: CodeSegment(
                    procedureDictionary: ProcedureDictionary(
                        procedureCount: 0,
                        procedurePointers: []
                    ),
                    procedures: []
                )
            ],
            dataSegments: [],
            allLocations: [],
            allProcedures: [],
            allCallers: [],
            knownRecords: [],
            typeAliases: [:],
            scalarTypes: [:],
            constants: [:],
            subrangeTypes: [:],
            typeConflicts: [],
            diagnostics: []
        )

        let lines = renderPascalSourceLines(from: result, showMarkup: false)

        XCTAssertLessThan(
            lines.firstIndex(of: "(* Segment FIRST [1] *)")!,
            lines.firstIndex(of: "(* SEGMENT PROCEDURE HELPER [2] *)")!
        )
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

extension OutputFlagTests {
    func testShowPascalSourceEmitsSourceLikeBlockWithoutChangingPseudocodeToggle() {
        let (dict, codeSegs, locs, procs, callers) = makeMinimalInputs()
        var stream = StringStream()
        outputResults(
            to: &stream,
            sourceFilename: "test",
            segDictionary: dict,
            codeSegs: codeSegs,
            dataSegs: [],
            allLocations: locs,
            allProcedures: procs,
            allCallers: callers,
            showMarkup: false,
            showPCode: false,
            showPseudoCode: false,
            showPascalSource: true
        )

        XCTAssertFalse(stream.text.contains("  MYPROC := 5\n"))
        XCTAssertTrue(stream.text.contains("PROCEDURE MYPROC;"))
        XCTAssertTrue(stream.text.contains("BEGIN"))
        XCTAssertTrue(stream.text.contains("  MYPROC := 5;"))
        XCTAssertTrue(stream.text.contains("END"))
    }
}
