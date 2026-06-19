import XCTest
@testable import pdisasm

final class DisassemblyRunResultPatchTests: XCTestCase {
    func testRunResultCommentPatchRefreshesDocumentIndexesAndLegacyComment() throws {
        let documentID = DocumentID("fixture")
        let lineID = DocumentNodeID(document: documentID, value: "line-1")
        let procedure = Procedure()
        procedure.identifier = ProcedureIdentifier(isFunction: false, segment: 1, procedure: 2)
        procedure.instructions[3] = Instruction(opcode: 0, mnemonic: "NOP", userComment: "old")
        let codeSegment = CodeSegment(
            procedureDictionary: ProcedureDictionary(procedureCount: 1, procedurePointers: [0]),
            procedures: [procedure]
        )
        let document = DisassemblyDocument(
            id: documentID,
            nodes: [
                DocumentNode(
                    id: lineID,
                    line: OutputLine(
                        id: 1,
                        kind: .pcode,
                        text: "0003: NOP ; old",
                        commentReference: InstructionReference(segment: 1, procedure: 2, addr: 3)
                    )
                ),
            ]
        )
        let runResult = DisassemblyRunResult(
            legacyResult: DisassemblyResult(
                sourceFilename: "fixture.bin",
                segDictionary: SegDictionary(segTable: [:], intrinsics: [], comment: ""),
                codeSegments: [1: codeSegment],
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
            ),
            snapshot: ProgramSnapshot(codeFileID: CodeFileID("fixture")),
            document: document,
            indexes: DocumentIndexes.buildPatched(document: document),
            report: RunReport()
        )

        let patched = runResult.patchingComment(
            DisassemblyComment(reference: InstructionReference(segment: 1, procedure: 2, addr: 3), comment: "newtoken")
        )

        XCTAssertEqual(patched.patchedNodes, [lineID])
        XCTAssertEqual(patched.result.document.nodes.map { $0.line.text }, ["0003: NOP ; newtoken"])
        XCTAssertEqual(patched.result.indexes.search("newtoken"), [lineID])
        XCTAssertTrue(patched.result.indexes.search("old").isEmpty)
        XCTAssertEqual(patched.result.legacyResult.codeSegments[1]?.procedures.first?.instructions[3]?.userComment, "newtoken")
    }
}
