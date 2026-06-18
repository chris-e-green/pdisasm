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
}
