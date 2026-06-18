import XCTest
@testable import pdisasm

final class DisassemblyServiceTests: XCTestCase {
    func testCanonicalIDAdaptersPreserveLegacyIdentityParts() {
        let codeFileID = CodeFileID("fixture")
        let legacyProcedure = ProcedureIdentifier(isFunction: false, segment: 2, procedure: 3)
        let procedureID = ProcedureID(codeFile: codeFileID, legacy: legacyProcedure)
        XCTAssertEqual(procedureID.segment.codeFile, codeFileID)
        XCTAssertEqual(procedureID.segment.number, 2)
        XCTAssertEqual(procedureID.number, 3)

        let instructionID = InstructionID(
            codeFile: codeFileID,
            legacy: InstructionReference(segment: 2, procedure: 3, addr: 42)
        )
        XCTAssertEqual(instructionID?.procedure, procedureID)
        XCTAssertEqual(instructionID?.offset, 42)

        let location = Location(segment: 2, procedure: 3, lexLevel: 1, addr: 4)
        let locationID = LocationID(codeFile: codeFileID, legacy: location)
        XCTAssertEqual(locationID.segment.number, 2)
        XCTAssertEqual(locationID.procedure, procedureID)
        XCTAssertEqual(locationID.lexicalLevel, 1)
        XCTAssertEqual(locationID.address, 4)
    }

    func testServiceWrapsLegacyDisassemblyWithoutChangingRenderedOutput() throws {
        let fixture = try XCTUnwrap(Bundle.module.url(
            forResource: "SYSTEM.LIBRARY-02-00",
            withExtension: "bin",
            subdirectory: "Fixtures"
        ))
        let legacy = try disassemble(filename: fixture.path, verbose: false)
        let wrapped = try DisassemblyService().run(DisassemblyRunRequest(
            source: .file(fixture),
            options: DisassemblyOptions(verbose: false)
        ))
        XCTAssertEqual(wrapped.legacyResult.sourceFilename, legacy.sourceFilename)
        XCTAssertEqual(wrapped.legacyResult.codeSegments.count, legacy.codeSegments.count)
        XCTAssertEqual(wrapped.legacyResult.allProcedures.count, legacy.allProcedures.count)
        XCTAssertEqual(
            renderDisassembly(wrapped.legacyResult, showMarkup: true, showPCode: true, showPseudoCode: true),
            renderDisassembly(legacy, showMarkup: true, showPCode: true, showPseudoCode: true)
        )
        XCTAssertEqual(wrapped.snapshot.codeFileID, CodeFileID(legacy.sourceFilename))
        XCTAssertEqual(wrapped.report.stages.first?.name, "codefileLoading")
        let stageNames = wrapped.report.stages.map(\.name)
        XCTAssertEqual(stageNames, [
            "codefileLoading",
            "metadataMerge",
            "decode",
            "referenceResolution",
            "analysis",
            "snapshotBuild",
            "documentBuild",
        ])
        let analysisReport = try XCTUnwrap(wrapped.report.stages.first { $0.name == "analysis" })
        XCTAssertGreaterThanOrEqual(analysisReport.metrics["iterations"] ?? 0, 1)
        XCTAssertEqual(analysisReport.metrics["maxIterations"], 4)
    }

    func testServiceBuildsImmutableSnapshotDocumentAndIndexes() throws {
        let fixture = try XCTUnwrap(Bundle.module.url(
            forResource: "SYSTEM.LIBRARY-02-00",
            withExtension: "bin",
            subdirectory: "Fixtures"
        ))
        let wrapped = try DisassemblyService().run(DisassemblyRunRequest(
            source: .file(fixture),
            options: DisassemblyOptions(verbose: false)
        ))

        XCTAssertEqual(wrapped.snapshot.segments.count, wrapped.legacyResult.codeSegments.count)
        XCTAssertFalse(wrapped.snapshot.procedures.isEmpty)
        XCTAssertFalse(wrapped.snapshot.instructions.isEmpty)
        XCTAssertFalse(wrapped.document.nodes.isEmpty)
        XCTAssertEqual(wrapped.document.nodes.count, wrapped.document.nodesByID.count)
        XCTAssertFalse(wrapped.indexes.procedureNodes.isEmpty)
        XCTAssertFalse(wrapped.indexes.symbolNodes.isEmpty)
        XCTAssertEqual(
            renderDisassemblyDocument(wrapped.document, showMarkup: true, showPCode: true, showPseudoCode: true),
            renderDisassembly(wrapped.legacyResult, showMarkup: true, showPCode: true, showPseudoCode: true)
        )
    }
}

extension DisassemblyServiceTests {
    func testMetadataSnapshotMergesByPrecedenceAndKeepsProvenance() {
        let bundled = MetadataBundle(labels: [
            ProvenancedMetadataFact(
                value: Location(segment: 1, procedure: 2, lexLevel: 0, addr: 3, name: "OLD", type: "INTEGER", typeSource: .metadata),
                provenance: MetadataProvenance(source: "bundled", precedence: 0)
            )
        ])
        let user = MetadataBundle(labels: [
            ProvenancedMetadataFact(
                value: Location(segment: 1, procedure: 2, lexLevel: 0, addr: 3, name: "NEW", type: "REAL", typeSource: .user),
                provenance: MetadataProvenance(source: "user", precedence: 10)
            )
        ])

        let snapshot = MetadataSnapshot(merging: [bundled, user])

        XCTAssertEqual(snapshot.labels.count, 1)
        XCTAssertEqual(snapshot.labels.first?.value.name, "NEW")
        XCTAssertEqual(snapshot.labels.first?.provenance.source, "user")
    }

    func testMetadataEditingServiceUpsertsCommentsThroughRepository() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdisasm-metadata-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = FileBackedMetadataRepository(workspace: MetadataWorkspace(writableDirectory: directory))
        let service = MetadataEditingService(repository: repository)

        let scope = try service.upsertComment(
            DisassemblyComment(reference: InstructionReference(segment: 1, procedure: 2, addr: 3), comment: "hello"),
            fileIdentifier: "fixture"
        )

        XCTAssertEqual(scope, .documentOnly)
        let loaded = try repository.loadBundle(
            named: "comments_fixture",
            kind: .commentsJSON,
            provenance: MetadataProvenance(source: "test", precedence: 0)
        )
        XCTAssertEqual(loaded.comments.map(\.value.comment), ["hello"])
        XCTAssertEqual(loaded.comments.first?.provenance.source, "comments_fixture.json")
    }

    func testCommentInvalidationCanPatchDocumentWithoutRerun() throws {
        let document = DisassemblyDocument(
            id: DocumentID("fixture"),
            nodes: [
                DocumentNode(
                    id: DocumentNodeID(document: DocumentID("fixture"), value: "line-1"),
                    line: OutputLine(
                        id: 1,
                        kind: .pcode,
                        text: "0003: NOP ; old",
                        commentReference: InstructionReference(segment: 1, procedure: 2, addr: 3)
                    )
                ),
                DocumentNode(
                    id: DocumentNodeID(document: DocumentID("fixture"), value: "line-2"),
                    line: OutputLine(id: 2, kind: .pcode, text: "0004: RTS")
                ),
            ]
        )

        let patched = document.patchingComment(
            DisassemblyComment(reference: InstructionReference(segment: 1, procedure: 2, addr: 3), comment: "new")
        )

        XCTAssertEqual(patched.patchedNodes, [DocumentNodeID(document: DocumentID("fixture"), value: "line-1")])
        XCTAssertEqual(patched.document.nodes.map(\.line.text), ["0003: NOP ; new", "0004: RTS"])
    }

    func testLabelInvalidationIsDocumentOnlyWhenTypeDoesNotAffectAnalysis() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdisasm-metadata-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let service = MetadataEditingService(repository: FileBackedMetadataRepository(workspace: MetadataWorkspace(writableDirectory: directory)))

        let scope = try service.upsertLabel(
            Location(segment: 1, procedure: 2, lexLevel: 0, addr: 3, name: "DISPLAY_ONLY", type: "", typeSource: .unknown),
            fileIdentifier: "fixture"
        )

        XCTAssertEqual(scope, .documentOnly)
    }

    func testProcedureSignatureInvalidationCanPropagateToCallers() throws {
        let codeFileID = CodeFileID("fixture")
        let callee = ProcedureID(segment: SegmentID(codeFile: codeFileID, number: 1), number: 2)
        let caller = ProcedureID(segment: SegmentID(codeFile: codeFileID, number: 1), number: 1)
        let callSite = InstructionID(procedure: caller, offset: 10)
        let snapshot = ProgramSnapshot(
            codeFileID: codeFileID,
            callsByTarget: [
                callee: [CallEdge(id: CallEdgeID(origin: callSite, target: callee), origin: callSite, target: callee)]
            ]
        )

        let procedure = ProcedureIdentifier(isFunction: false, isAssembly: false, segment: 1, segmentName: nil, procedure: 2)
        let scope = MetadataEditingService(repository: InMemoryMetadataRepository())
            .invalidationForProcedureEdit(procedure, in: snapshot)

        XCTAssertEqual(scope, .propagateCallGraph([callee, caller]))
    }
}

private struct InMemoryMetadataRepository: MetadataRepository {
    func loadBundle(named name: String, kind: MetadataFileKind, provenance: MetadataProvenance) throws -> MetadataBundle {
        MetadataBundle()
    }

    func saveLabels(_ labels: [Location], named name: String) throws {}
    func saveProcedures(_ procedures: [ProcedureIdentifier], named name: String) throws {}
    func saveComments(_ comments: [DisassemblyComment], named name: String) throws {}
}


extension DisassemblyServiceTests {
    func testJSONDocumentExporterProducesStableExternalShape() throws {
        let fixture = try XCTUnwrap(Bundle.module.url(
            forResource: "SYSTEM.LIBRARY-02-00",
            withExtension: "bin",
            subdirectory: "Fixtures"
        ))
        let wrapped = try DisassemblyService().run(DisassemblyRunRequest(source: .file(fixture)))
        let json = try JSONDocumentExporter().string(for: wrapped)

        XCTAssertTrue(json.contains("\"codeFileID\" : \"SYSTEM.LIBRARY-02-00\""))
        XCTAssertTrue(json.contains("\"document\" : ["))
        XCTAssertTrue(json.contains("\"procedures\" : ["))
    }

    func testCallGraphExporterProducesDotGraph() throws {
        let codeFileID = CodeFileID("fixture")
        let caller = ProcedureID(segment: SegmentID(codeFile: codeFileID, number: 1), number: 1)
        let callee = ProcedureID(segment: SegmentID(codeFile: codeFileID, number: 1), number: 2)
        let callSite = InstructionID(procedure: caller, offset: 10)
        let snapshot = ProgramSnapshot(
            codeFileID: codeFileID,
            procedures: [
                caller: ProcedureSnapshot(id: caller, name: "CALLER", isFunction: false, isAssembly: false, lexicalLevel: 0, dataSize: 0, parameterSize: 0, instructionIDs: []),
                callee: ProcedureSnapshot(id: callee, name: "CALLEE", isFunction: false, isAssembly: false, lexicalLevel: 0, dataSize: 0, parameterSize: 0, instructionIDs: []),
            ],
            callsByOrigin: [
                caller: [CallEdge(id: CallEdgeID(origin: callSite, target: callee), origin: callSite, target: callee)]
            ]
        )

        let dot = CallGraphExporter().dot(for: snapshot)

        XCTAssertTrue(dot.contains("digraph pdisasm_call_graph"))
        XCTAssertTrue(dot.contains("\"fixture:1.1\" -> \"fixture:1.2\""))
    }

    func testBatchDisassemblyRunsMultipleFilesWithSharedWorkspace() throws {
        let fixture = try XCTUnwrap(Bundle.module.url(
            forResource: "SYSTEM.LIBRARY-02-00",
            withExtension: "bin",
            subdirectory: "Fixtures"
        ))
        let workspaceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdisasm-workspace-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

        let batch = try BatchDisassemblyService().run(
            files: [fixture, fixture],
            workspace: MetadataWorkspace(writableDirectory: workspaceURL, bundledDirectory: workspaceURL)
        )

        XCTAssertEqual(batch.results.count, 2)
        XCTAssertEqual(Set(batch.results.map(\.snapshot.codeFileID)), [CodeFileID("SYSTEM.LIBRARY-02-00")])
    }
}

extension DisassemblyServiceTests {
    func testSnapshotExposesArchitectureSummaries() throws {
        let fixture = try XCTUnwrap(Bundle.module.url(
            forResource: "SYSTEM.LIBRARY-02-00",
            withExtension: "bin",
            subdirectory: "Fixtures"
        ))
        let wrapped = try DisassemblyService().run(DisassemblyRunRequest(source: .file(fixture)))

        XCTAssertEqual(wrapped.snapshot.file.id, wrapped.snapshot.codeFileID)
        XCTAssertEqual(wrapped.snapshot.file.sourceFilename, "SYSTEM.LIBRARY-02-00")
        XCTAssertEqual(wrapped.snapshot.file.segmentCount, wrapped.legacyResult.codeSegments.count)
        XCTAssertEqual(wrapped.snapshot.segmentDictionary.entries.count, wrapped.legacyResult.segDictionary.segTable.count)
        XCTAssertFalse(wrapped.snapshot.typeEnvironment.recordNames.isEmpty)
        XCTAssertFalse(wrapped.document.sections.isEmpty)
        XCTAssertFalse(wrapped.indexes.search("SEGMENT").isEmpty)
    }

    func testCancellationTokenStopsRunBeforeLegacyWork() throws {
        struct CancelledToken: CancellationToken { let isCancellationRequested = true }
        let fixture = try XCTUnwrap(Bundle.module.url(
            forResource: "SYSTEM.LIBRARY-02-00",
            withExtension: "bin",
            subdirectory: "Fixtures"
        ))

        XCTAssertThrowsError(try DisassemblyService().run(DisassemblyRunRequest(
            source: .file(fixture),
            cancellation: CancelledToken()
        ))) { error in
            XCTAssertTrue(error is DisassemblyCancelledError)
        }
    }
}
