import XCTest
@testable import pdisasm

final class DisassemblyServiceTests: XCTestCase {

    func testRunReportStatusSemanticsAndExitCodes() {
        let success = RunReport(stages: [StageReport(name: "analysis")])
        XCTAssertEqual(success.status, .success)
        XCTAssertEqual(success.status.processExitCode, 0)

        let degraded = RunReport(stages: [StageReport(name: "analysis", isComplete: false)], warnings: ["partial"])
        XCTAssertEqual(degraded.status, .degradedSuccess)
        XCTAssertEqual(degraded.status.processExitCode, 2)
        XCTAssertFalse(degraded.didConverge)

        let cancelled = RunReport(stages: [StageReport(name: "decode", status: .cancelled)])
        XCTAssertEqual(cancelled.status, .cancelled)
        XCTAssertEqual(cancelled.status.processExitCode, 130)

        let fatal = RunReport(fatalErrors: ["unreadable"])
        XCTAssertEqual(fatal.status, .fatalError)
        XCTAssertEqual(fatal.status.processExitCode, 1)
    }

    func testSnapshotAndDocumentExposeUserVisibleProvenance() throws {
        let fixture = try XCTUnwrap(Bundle.module.url(
            forResource: "SYSTEM.LIBRARY-02-00",
            withExtension: "bin",
            subdirectory: "Fixtures"
        ))
        let wrapped = try DisassemblyService().run(DisassemblyRunRequest(source: .file(fixture)))

        XCTAssertFalse(wrapped.snapshot.procedures.values.filter { !$0.provenance.source.isEmpty }.isEmpty)
        XCTAssertFalse(wrapped.snapshot.instructions.values.filter { $0.provenance == .decoded }.isEmpty)
        XCTAssertFalse(wrapped.snapshot.locations.values.filter { !$0.provenance.source.isEmpty }.isEmpty)
        XCTAssertFalse(wrapped.document.nodes.filter { $0.provenance == .rendered }.isEmpty)
    }

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
        XCTAssertGreaterThan(wrapped.document.sourceMapCoveragePercent, 0)
        XCTAssertGreaterThan(wrapped.document.sourceMap.count, wrapped.indexes.procedureNodes.count)
        XCTAssertEqual(
            Set(wrapped.indexes.procedureNodes.keys).subtracting(wrapped.snapshot.procedures.keys),
            []
        )
        XCTAssertEqual(
            Set(wrapped.indexes.instructionNodes.keys).subtracting(wrapped.snapshot.instructions.keys),
            []
        )
        let renderedDocument = renderDisassemblyDocument(
            wrapped.document,
            showMarkup: true,
            showPCode: true,
            showPseudoCode: true
        )
        XCTAssertTrue(renderedDocument.contains("#  SYSTEM.LIBRARY-02-00"))
        XCTAssertTrue(renderedDocument.contains("## Segment"))
        XCTAssertTrue(renderedDocument.contains("BEGIN"))
        XCTAssertTrue(renderedDocument.contains("END"))
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


    func testSnapshotDocumentSourceMapCoversProceduresAndInstructions() throws {
        let fixture = try XCTUnwrap(Bundle.module.url(
            forResource: "SYSTEM.LIBRARY-02-00",
            withExtension: "bin",
            subdirectory: "Fixtures"
        ))
        let wrapped = try DisassemblyService().run(DisassemblyRunRequest(source: .file(fixture)))

        XCTAssertEqual(Set(wrapped.indexes.procedureNodes.keys), Set(wrapped.snapshot.procedures.keys))
        XCTAssertEqual(Set(wrapped.indexes.instructionNodes.keys), Set(wrapped.snapshot.instructions.keys))
        XCTAssertGreaterThanOrEqual(wrapped.document.sourceMapCoveragePercent, 50)
        XCTAssertTrue(wrapped.document.sourceMap.values.contains { $0.locationID != nil })
    }

    func testSnapshotDocumentSourceMapReferencesExistingSnapshotFacts() throws {
        let codeFileID = CodeFileID("fixture")
        let segmentID = SegmentID(codeFile: codeFileID, number: 1)
        let procedureID = ProcedureID(segment: segmentID, number: 2)
        let instructionID = InstructionID(procedure: procedureID, offset: 16)
        let locationID = LocationID(segment: segmentID, procedure: procedureID, lexicalLevel: 0, address: 1)
        let snapshot = ProgramSnapshot(
            codeFileID: codeFileID,
            file: CodeFileSummary(id: codeFileID, sourceFilename: "fixture", segmentCount: 1, dataSegmentNumbers: []),
            segments: [segmentID: SegmentSnapshot(id: segmentID, name: "SEG", procedureIDs: [procedureID])],
            procedures: [procedureID: ProcedureSnapshot(id: procedureID, name: "PROC2", isFunction: false, isAssembly: false, lexicalLevel: 0, dataSize: 1, parameterSize: 0, instructionIDs: [instructionID])],
            instructions: [instructionID: InstructionSnapshot(id: instructionID, opcode: 0, mnemonic: "NOP", parameters: [], locationID: locationID, destinationID: nil, comment: "No operation", userComment: nil)],
            locations: [locationID: LocationFact(id: locationID, name: "LOCAL", type: "INTEGER", typeSource: .inferred, isParameter: false)]
        )

        let output = try DocumentBuildStage().run(DocumentBuildStageInput(
            result: DisassemblyResult(sourceFilename: "fixture", segDictionary: SegDictionary(segTable: [:], intrinsics: [], comment: ""), codeSegments: [:], dataSegments: [], allLocations: [], allProcedures: [], allCallers: [], knownRecords: [], typeAliases: [:], scalarTypes: [:], constants: [:], subrangeTypes: [:], typeConflicts: [], diagnostics: []),
            snapshot: snapshot,
            id: DocumentID("fixture"),
            title: "fixture",
            showStackState: false,
            verbose: false
        ))

        XCTAssertEqual(output.indexes.procedureNodes[procedureID].flatMap { output.document.sourceMap[$0]?.procedureID }, procedureID)
        XCTAssertEqual(output.indexes.instructionNodes[instructionID].flatMap { output.document.sourceMap[$0]?.instructionID }, instructionID)
        XCTAssertEqual(output.indexes.locationNodes[locationID]?.first.flatMap { output.document.sourceMap[$0]?.locationID }, locationID)
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


    func testTypedMetadataCommandsValidateAndSaveWithBackup() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdisasm-metadata-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = FileBackedMetadataRepository(workspace: MetadataWorkspace(writableDirectory: directory))
        let service = MetadataEditingService(repository: repository)
        let codeFileID = CodeFileID("fixture")
        let procedureID = ProcedureID(segment: SegmentID(codeFile: codeFileID, number: 1), number: 2)
        let instructionID = InstructionID(procedure: procedureID, offset: 3)
        let snapshot = ProgramSnapshot(
            codeFileID: codeFileID,
            procedures: [procedureID: ProcedureSnapshot(id: procedureID, name: "PROC2", isFunction: false, isAssembly: false, lexicalLevel: 1, dataSize: 0, parameterSize: 0, instructionIDs: [instructionID])],
            instructions: [instructionID: InstructionSnapshot(id: instructionID, opcode: 0, mnemonic: "NOP", parameters: [], locationID: nil, destinationID: nil, comment: nil, userComment: nil)]
        )
        let context = MetadataEditContext(codeFileID: codeFileID, snapshot: snapshot)

        let first = try service.apply(.upsertComment(instructionID, text: "old"), context: context)
        let second = try service.apply(.upsertComment(instructionID, text: "new"), context: context)

        XCTAssertEqual(first.invalidation, .documentOnly)
        XCTAssertEqual(second.diagnostics, [])
        XCTAssertEqual(second.invalidation, .documentOnly)
        let loaded = try repository.loadBundle(in: .fileComments(fileIdentifier: "fixture"), provenance: MetadataProvenance(source: "test", precedence: 0))
        XCTAssertEqual(loaded.comments.map(\.value.comment), ["new"])
        let backups = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("comments_fixture.json.bak.") }
        XCTAssertFalse(backups.isEmpty)
    }

    func testTypedProcedureCommandChoosesSystemMetadataScope() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdisasm-metadata-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = FileBackedMetadataRepository(workspace: MetadataWorkspace(writableDirectory: directory))
        let service = MetadataEditingService(repository: repository)
        let codeFileID = CodeFileID("fixture")
        let procedureID = ProcedureID(segment: SegmentID(codeFile: codeFileID, number: 2), number: 7)

        let result = try service.apply(
            .renameProcedure(procedureID, name: "RENAMED"),
            context: MetadataEditContext(codeFileID: codeFileID, systemMetadataVersion: 42, systemSegments: [2])
        )

        XCTAssertEqual(result.invalidation, .procedureSignature(segment: 2, procedure: 7))
        let loaded = try repository.loadBundle(in: .systemProcedures(version: 42), provenance: MetadataProvenance(source: "test", precedence: 0))
        XCTAssertEqual(loaded.procedures.first?.value.procName, "RENAMED")
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("procedures_fixture.csv").path))
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
    func loadBundle(in scope: MetadataScope, provenance: MetadataProvenance?) throws -> MetadataBundle {
        MetadataBundle()
    }

    func saveLabels(_ labels: [Location], in scope: MetadataScope) throws {}
    func saveProcedures(_ procedures: [ProcedureIdentifier], in scope: MetadataScope) throws {}
    func saveComments(_ comments: [DisassemblyComment], in scope: MetadataScope) throws {}
}

private final class RecordingMetadataRepository: MetadataRepository, @unchecked Sendable {
    var loadedScopes: [MetadataScope] = []
    var savedProcedureScopes: [MetadataScope] = []

    func loadBundle(in scope: MetadataScope, provenance: MetadataProvenance?) throws -> MetadataBundle {
        loadedScopes.append(scope)
        return MetadataBundle()
    }

    func saveLabels(_ labels: [Location], in scope: MetadataScope) throws {}
    func saveProcedures(_ procedures: [ProcedureIdentifier], in scope: MetadataScope) throws {
        savedProcedureScopes.append(scope)
    }
    func saveComments(_ comments: [DisassemblyComment], in scope: MetadataScope) throws {}
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
        let documentBuild = try XCTUnwrap(wrapped.report.stages.first { $0.name == "documentBuild" })
        XCTAssertEqual(documentBuild.metrics["sourceMappedNodes"], wrapped.document.sourceMap.count)
        XCTAssertEqual(documentBuild.metrics["sourceMapCoveragePercent"], wrapped.document.sourceMapCoveragePercent)
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

extension DisassemblyServiceTests {

    func testMetadataEditingUsesTypedMetadataScopes() throws {
        let repository = RecordingMetadataRepository()
        let service = MetadataEditingService(repository: repository)
        let codeFileID = CodeFileID("fixture")
        let procedureID = ProcedureID(segment: SegmentID(codeFile: codeFileID, number: 2), number: 7)

        _ = try service.apply(
            .renameProcedure(procedureID, name: "RENAMED"),
            context: MetadataEditContext(codeFileID: codeFileID, systemMetadataVersion: 42, systemSegments: [2])
        )

        XCTAssertEqual(Set(repository.loadedScopes), [.systemProcedures(version: 42)])
        XCTAssertEqual(repository.savedProcedureScopes, [.systemProcedures(version: 42)])
    }

    func testMetadataScopeResolverMergesInMemoryScopesByPrecedence() throws {
        let systemLocation = Location(segment: 1, procedure: 1, lexLevel: 0, addr: 10, name: "SYSTEM", type: "INTEGER", typeSource: .metadata)
        let fileLocation = Location(segment: 1, procedure: 1, lexLevel: 0, addr: 10, name: "FILE", type: "BOOLEAN", typeSource: .user)
        let systemRecord = PascalRecord(name: "REC", members: [0: Identifier(name: "OLD", type: "INTEGER")], isSystemRecord: true)
        let fileRecord = PascalRecord(name: "REC", members: [0: Identifier(name: "NEW", type: "BOOLEAN")])
        let repository = pdisasm.InMemoryMetadataRepository(bundles: [
            MetadataRepositoryKey(name: "labels_ver_1", kind: .labelsCSV): MetadataBundle(labels: [
                ProvenancedMetadataFact(value: systemLocation, provenance: MetadataProvenance(source: "labels_ver_1", precedence: 0))
            ]),
            MetadataRepositoryKey(name: "records_ver_1", kind: .recordsJSON): MetadataBundle(records: [
                ProvenancedMetadataFact(value: systemRecord, provenance: MetadataProvenance(source: "records_ver_1", precedence: 0))
            ]),
            MetadataRepositoryKey(name: "types_ver_1", kind: .typesPascal): MetadataBundle(
                typeAliases: [ProvenancedMetadataFact(value: MetadataTypeAlias(name: "ALIAS", type: "INTEGER"), provenance: MetadataProvenance(source: "types_ver_1", precedence: 0))],
                scalarTypes: [ProvenancedMetadataFact(value: PascalScalarType(name: "CHOICE", cases: ["A"]), provenance: MetadataProvenance(source: "types_ver_1", precedence: 0))],
                constants: [ProvenancedMetadataFact(value: MetadataConstant(name: "MAX", value: 1), provenance: MetadataProvenance(source: "types_ver_1", precedence: 0))],
                subrangeTypes: [ProvenancedMetadataFact(value: PascalSubrangeType(name: "RANGE", lowerBound: 1, upperBound: 1), provenance: MetadataProvenance(source: "types_ver_1", precedence: 0))]
            ),
            MetadataRepositoryKey(name: "globals_ver_1", kind: .globalsJSON): MetadataBundle(globals: [
                ProvenancedMetadataFact(value: MetadataGlobal(address: 7, identifier: Identifier(name: "GLOBAL", type: "INTEGER")), provenance: MetadataProvenance(source: "globals_ver_1", precedence: 0))
            ]),
            MetadataRepositoryKey(name: "labels_SAMPLE", kind: .labelsCSV): MetadataBundle(labels: [
                ProvenancedMetadataFact(value: fileLocation, provenance: MetadataProvenance(source: "labels_SAMPLE", precedence: 10))
            ]),
            MetadataRepositoryKey(name: "records_SAMPLE", kind: .recordsJSON): MetadataBundle(records: [
                ProvenancedMetadataFact(value: fileRecord, provenance: MetadataProvenance(source: "records_SAMPLE", precedence: 10))
            ]),
        ])

        let snapshot = try MetadataScopeResolver(repository: repository).resolve(fileIdentifier: "SAMPLE", version: 1)

        XCTAssertEqual(snapshot.labels.count, 1)
        XCTAssertEqual(snapshot.labels.first?.value.name, "FILE")
        XCTAssertEqual(snapshot.records.count, 1)
        XCTAssertEqual(snapshot.records.first?.value.members[0]?.name, "NEW")
        XCTAssertEqual(snapshot.typeAliases.first?.value.type, "INTEGER")
        XCTAssertEqual(snapshot.scalarTypes.first?.value.cases, ["A"])
        XCTAssertEqual(snapshot.constants.first?.value.value, 1)
        XCTAssertEqual(snapshot.subrangeTypes.first?.value.upperBound, 1)
        XCTAssertEqual(snapshot.globals.first?.value.identifier.name, "GLOBAL")
    }

    func testFileBackedResolverLoadsCompleteMetadataSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdisasm-metadata-complete-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "segment,procedure,lexLevel,addr,name,type,typeSource\n1,1,0,4,FILE_LABEL,INTEGER,user\n"
            .write(to: directory.appendingPathComponent("labels_SAMPLE.csv"), atomically: true, encoding: .utf8)
        try "segmentNumber,segmentName,procNumber,procName,isFunction,isAssembly,parameters,returnType,returnTypeSource\n1,,1,FILE_PROC,false,false,,,unknown\n"
            .write(to: directory.appendingPathComponent("procedures_SAMPLE.csv"), atomically: true, encoding: .utf8)
        try JSONEncoder().encode([DisassemblyComment(reference: InstructionReference(segment: 1, procedure: 1, addr: 4), comment: "hello")])
            .write(to: directory.appendingPathComponent("comments_SAMPLE.json"))
        try JSONEncoder().encode([PascalRecord(name: "REC", members: [0: Identifier(name: "FIELD", type: "INTEGER")])])
            .write(to: directory.appendingPathComponent("records_SAMPLE.json"))
        try "MAX = 3;\nCHOICE = (A, B);\nRANGE = 1..MAX;\nALIAS = INTEGER;\n"
            .write(to: directory.appendingPathComponent("types_SAMPLE.pas"), atomically: true, encoding: .utf8)
        try JSONEncoder().encode([9: Identifier(name: "GLOBAL", type: "INTEGER")])
            .write(to: directory.appendingPathComponent("globals_ver_1.json"))

        let snapshot = try MetadataScopeResolver(repository: FileBackedMetadataRepository(workspace: MetadataWorkspace(writableDirectory: directory))).resolve(fileIdentifier: "SAMPLE", version: 1)

        XCTAssertEqual(snapshot.labels.first?.value.name, "FILE_LABEL")
        XCTAssertEqual(snapshot.procedures.first?.value.procName, "FILE_PROC")
        XCTAssertEqual(snapshot.comments.first?.value.comment, "hello")
        XCTAssertEqual(snapshot.records.first?.value.name, "REC")
        XCTAssertEqual(snapshot.constants.first?.value.value, 3)
        XCTAssertEqual(snapshot.scalarTypes.first?.value.cases, ["A", "B"])
        XCTAssertEqual(snapshot.subrangeTypes.first?.value.upperBound, 3)
        XCTAssertEqual(snapshot.typeAliases.first?.value.type, "INTEGER")
        XCTAssertEqual(snapshot.globals.first?.value.identifier.name, "GLOBAL")
    }

    func testStageFacadesAcceptInMemoryInputs() throws {
        let bytes = Data([0, 1, 2, 3])
        let load = try CodefileLoadStage().run(source: .bytes(bytes, suggestedFilename: "sample.bin"))
        XCTAssertEqual(load.data, bytes)
        XCTAssertEqual(load.report.name, "codefileLoading")
        XCTAssertEqual(load.report.metrics["bytes"], bytes.count)

        let snapshot = MetadataSnapshot(labels: [
            ProvenancedMetadataFact(
                value: Location(segment: 1, procedure: 1, lexLevel: 0, addr: 4, name: "L", type: "", typeSource: .unknown),
                provenance: MetadataProvenance(source: "test", precedence: 1)
            )
        ])
        let merge = try MetadataMergeStage().run(fileIdentifier: "sample", version: 1, explicit: snapshot)
        XCTAssertEqual(merge.snapshot.labels.count, 1)
        XCTAssertEqual(merge.report.metrics["labels"], 1)
    }

    func testBytesSourceWithInMemoryMetadataDoesNotReadApplicationSupport() throws {
        let fixture = try XCTUnwrap(Bundle.module.url(
            forResource: "SYSTEM.LIBRARY-02-00",
            withExtension: "bin",
            subdirectory: "Fixtures"
        ))
        let appSupport = URL.pdisasmApplicationSupportDirectory.appendingPathComponent("pdisasm", isDirectory: true)
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        let sentinel = appSupport.appendingPathComponent("procedures_MEMORY.csv")
        try "segmentNumber,segmentName,procNumber,procName,isFunction,isAssembly,parameters,returnType,returnTypeSource\n1,,1,SHOULD_NOT_BE_READ,false,false,,,unknown\n"
            .write(to: sentinel, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: sentinel) }

        let bytes = try Data(contentsOf: fixture)
        let snapshot = MetadataSnapshot(labels: [
            ProvenancedMetadataFact(
                value: Location(segment: 1, procedure: nil, lexLevel: nil, addr: nil, name: "IN_MEMORY_ONLY", type: "", typeSource: .user),
                provenance: MetadataProvenance(source: "in-memory", precedence: 100)
            )
        ])
        let wrapped = try DisassemblyService().run(DisassemblyRunRequest(
            source: .bytes(bytes, suggestedFilename: "MEMORY.bin"),
            metadata: snapshot
        ))

        XCTAssertTrue(wrapped.legacyResult.allLocations.contains { $0.name == "IN_MEMORY_ONLY" })
        XCTAssertFalse(wrapped.legacyResult.allProcedures.contains { $0.procName == "SHOULD_NOT_BE_READ" })
    }
}
