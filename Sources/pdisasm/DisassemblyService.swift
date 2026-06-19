import Foundation

public enum CodeFileSource: Sendable {
    case file(URL)
    case bytes(Data, suggestedFilename: String)

    var filenameForLegacyRunner: String {
        get throws {
            switch self {
            case .file(let url):
                return url.path
            case .bytes(let data, let suggestedFilename):
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("pdisasm-")
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathComponent(suggestedFilename)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url)
                return url.path
            }
        }
    }
}

public struct DisassemblyOptions: Hashable, Codable, Sendable {
    public var verbose: Bool
    public var writeMetadata: Bool
    public var overwriteMetadata: Bool
    public var showMarkup: Bool
    public var showPCode: Bool
    public var showStackState: Bool
    public var showPseudoCode: Bool
    public var showDot: Bool

    public init(verbose: Bool = false, writeMetadata: Bool = false, overwriteMetadata: Bool = false, showMarkup: Bool = true, showPCode: Bool = true, showStackState: Bool = false, showPseudoCode: Bool = true, showDot: Bool = false) {
        self.verbose = verbose
        self.writeMetadata = writeMetadata
        self.overwriteMetadata = overwriteMetadata
        self.showMarkup = showMarkup
        self.showPCode = showPCode
        self.showStackState = showStackState
        self.showPseudoCode = showPseudoCode
        self.showDot = showDot
    }
}

public protocol CancellationToken: Sendable {
    var isCancellationRequested: Bool { get }
}

public struct DisassemblyCancelledError: Error, Sendable, CustomStringConvertible {
    public init() {}
    public var description: String { "Disassembly was cancelled" }
}

public struct DisassemblyRunRequest: Sendable {
    public let source: CodeFileSource
    public let metadata: MetadataSnapshot
    public let metadataWorkspace: MetadataWorkspace?
    public let options: DisassemblyOptions
    public let cancellation: CancellationToken?

    public init(
        source: CodeFileSource,
        metadata: MetadataSnapshot = MetadataSnapshot(),
        metadataWorkspace: MetadataWorkspace? = nil,
        options: DisassemblyOptions = DisassemblyOptions(),
        cancellation: CancellationToken? = nil
    ) {
        self.source = source
        self.metadata = metadata
        self.metadataWorkspace = metadataWorkspace
        self.options = options
        self.cancellation = cancellation
    }

    public func checkCancellation() throws {
        if cancellation?.isCancellationRequested == true {
            throw DisassemblyCancelledError()
        }
    }
}

public enum StageStatus: String, Hashable, Codable, Sendable {
    case complete
    case degraded
    case cancelled
    case fatal

    public var isComplete: Bool { self == .complete }
}

public enum RunStatus: String, Hashable, Codable, Sendable {
    case success
    case degradedSuccess
    case cancelled
    case fatalError

    public var isSuccess: Bool { self == .success || self == .degradedSuccess }
    public var processExitCode: Int32 {
        switch self {
        case .success: return 0
        case .degradedSuccess: return 2
        case .cancelled: return 130
        case .fatalError: return 1
        }
    }
}

public struct StageReport: Hashable, Codable, Sendable {
    public let name: String
    public let status: StageStatus
    public let metrics: [String: Int]
    public let diagnostics: [String]

    public var isComplete: Bool { status.isComplete }

    public init(name: String, status: StageStatus? = nil, isComplete: Bool = true, metrics: [String: Int] = [:], diagnostics: [String] = []) {
        self.name = name
        self.status = status ?? (isComplete ? .complete : .degraded)
        self.metrics = metrics
        self.diagnostics = diagnostics
    }
}

public struct RunReport: Hashable, Codable, Sendable {
    public let status: RunStatus
    public let stages: [StageReport]
    public let fatalErrors: [String]
    public let warnings: [String]
    public let metadataWarnings: [String]
    public let isComplete: Bool
    public let didConverge: Bool

    public init(
        status: RunStatus? = nil,
        stages: [StageReport] = [],
        fatalErrors: [String] = [],
        warnings: [String] = [],
        metadataWarnings: [String] = [],
        isComplete: Bool? = nil,
        didConverge: Bool? = nil
    ) {
        self.stages = stages
        self.fatalErrors = fatalErrors
        self.warnings = warnings
        self.metadataWarnings = metadataWarnings
        self.didConverge = didConverge ?? (stages.first { $0.name == "analysis" }?.isComplete ?? true)
        let complete = isComplete ?? (fatalErrors.isEmpty && stages.allSatisfy(\.isComplete))
        self.isComplete = complete
        self.status = status ?? RunReport.deriveStatus(stages: stages, fatalErrors: fatalErrors, warnings: warnings + metadataWarnings, isComplete: complete)
    }

    private static func deriveStatus(stages: [StageReport], fatalErrors: [String], warnings: [String], isComplete: Bool) -> RunStatus {
        if !fatalErrors.isEmpty || stages.contains(where: { $0.status == .fatal }) { return .fatalError }
        if stages.contains(where: { $0.status == .cancelled }) { return .cancelled }
        if !isComplete || !warnings.isEmpty || stages.contains(where: { $0.status == .degraded }) { return .degradedSuccess }
        return .success
    }
}

public struct FactProvenance: Hashable, Codable, Sendable {
    public let source: String
    public let detail: String

    public init(source: String, detail: String = "") {
        self.source = source
        self.detail = detail
    }

    public static let decoded = FactProvenance(source: "decoded")
    public static let inferred = FactProvenance(source: "inferred")
    public static let rendered = FactProvenance(source: "rendered")
    public static func metadata(_ provenance: MetadataProvenance) -> FactProvenance {
        FactProvenance(source: provenance.source, detail: "metadata precedence \(provenance.precedence)")
    }
}

public struct CodeFileSummary: Sendable {
    public let id: CodeFileID
    public let sourceFilename: String
    public let segmentCount: Int
    public let dataSegmentNumbers: [Int]

    public init(id: CodeFileID, sourceFilename: String, segmentCount: Int, dataSegmentNumbers: [Int]) {
        self.id = id
        self.sourceFilename = sourceFilename
        self.segmentCount = segmentCount
        self.dataSegmentNumbers = dataSegmentNumbers
    }
}

public struct SegmentDictionaryEntrySnapshot: Sendable {
    public let slot: Int
    public let segmentID: SegmentID
    public let name: String
    public let codeAddress: Int
    public let codeLength: Int
    public let kind: String
    public let textAddress: Int
    public let machineType: Int
    public let version: Int

    public init(slot: Int, segmentID: SegmentID, name: String, codeAddress: Int, codeLength: Int, kind: String, textAddress: Int, machineType: Int, version: Int) {
        self.slot = slot
        self.segmentID = segmentID
        self.name = name
        self.codeAddress = codeAddress
        self.codeLength = codeLength
        self.kind = kind
        self.textAddress = textAddress
        self.machineType = machineType
        self.version = version
    }
}

public struct SegmentDictionarySnapshot: Sendable {
    public let entries: [SegmentDictionaryEntrySnapshot]
    public let intrinsicSegmentNumbers: [UInt8]
    public let comment: String

    public init(entries: [SegmentDictionaryEntrySnapshot], intrinsicSegmentNumbers: [UInt8], comment: String) {
        self.entries = entries
        self.intrinsicSegmentNumbers = intrinsicSegmentNumbers
        self.comment = comment
    }
}

public struct TypeEnvironmentSnapshot: Sendable {
    public let recordNames: [String]
    public let typeAliases: [String: String]
    public let scalarTypeNames: [String]
    public let constants: [String: Int]
    public let subrangeTypeNames: [String]

    public init(recordNames: [String], typeAliases: [String: String], scalarTypeNames: [String], constants: [String: Int], subrangeTypeNames: [String]) {
        self.recordNames = recordNames
        self.typeAliases = typeAliases
        self.scalarTypeNames = scalarTypeNames
        self.constants = constants
        self.subrangeTypeNames = subrangeTypeNames
    }
}

public struct SegmentSnapshot: Sendable {
    public let id: SegmentID
    public let name: String
    public let procedureIDs: [ProcedureID]
    public let provenance: FactProvenance

    public init(id: SegmentID, name: String, procedureIDs: [ProcedureID], provenance: FactProvenance = .decoded) {
        self.id = id
        self.name = name
        self.procedureIDs = procedureIDs
        self.provenance = provenance
    }
}

public struct ProcedureSnapshot: Sendable {
    public let id: ProcedureID
    public let name: String
    public let isFunction: Bool
    public let isAssembly: Bool
    public let lexicalLevel: Int
    public let dataSize: Int
    public let parameterSize: Int
    public let instructionIDs: [InstructionID]
    public let provenance: FactProvenance

    public init(id: ProcedureID, name: String, isFunction: Bool, isAssembly: Bool, lexicalLevel: Int, dataSize: Int, parameterSize: Int, instructionIDs: [InstructionID], provenance: FactProvenance = .decoded) {
        self.id = id
        self.name = name
        self.isFunction = isFunction
        self.isAssembly = isAssembly
        self.lexicalLevel = lexicalLevel
        self.dataSize = dataSize
        self.parameterSize = parameterSize
        self.instructionIDs = instructionIDs
        self.provenance = provenance
    }
}

public struct InstructionSnapshot: Sendable {
    public let id: InstructionID
    public let opcode: UInt8
    public let mnemonic: String
    public let parameters: [Int]
    public let locationID: LocationID?
    public let destinationID: LocationID?
    public let comment: String?
    public let userComment: String?
    public let provenance: FactProvenance
    public let commentProvenance: FactProvenance?

    public init(id: InstructionID, opcode: UInt8, mnemonic: String, parameters: [Int], locationID: LocationID?, destinationID: LocationID?, comment: String?, userComment: String?, provenance: FactProvenance = .decoded, commentProvenance: FactProvenance? = nil) {
        self.id = id
        self.opcode = opcode
        self.mnemonic = mnemonic
        self.parameters = parameters
        self.locationID = locationID
        self.destinationID = destinationID
        self.comment = comment
        self.userComment = userComment
        self.provenance = provenance
        self.commentProvenance = commentProvenance
    }
}

public struct LocationFact: Sendable {
    public let id: LocationID
    public let name: String
    public let type: String
    public let typeSource: TypeSource
    public let isParameter: Bool
    public let provenance: FactProvenance

    public init(id: LocationID, name: String, type: String, typeSource: TypeSource, isParameter: Bool, provenance: FactProvenance = .decoded) {
        self.id = id
        self.name = name
        self.type = type
        self.typeSource = typeSource
        self.isParameter = isParameter
        self.provenance = provenance
    }
}

public struct CallEdge: Sendable {
    public let id: CallEdgeID
    public let origin: InstructionID
    public let target: ProcedureID
}

public struct ProgramSnapshot: Sendable {
    public let codeFileID: CodeFileID
    public let file: CodeFileSummary
    public let segmentDictionary: SegmentDictionarySnapshot
    public let typeEnvironment: TypeEnvironmentSnapshot
    public let segments: [SegmentID: SegmentSnapshot]
    public let procedures: [ProcedureID: ProcedureSnapshot]
    public let instructions: [InstructionID: InstructionSnapshot]
    public let locations: [LocationID: LocationFact]
    public let callsByOrigin: [ProcedureID: [CallEdge]]
    public let callsByTarget: [ProcedureID: [CallEdge]]
    public let diagnostics: [Diagnostic]

    public init(
        codeFileID: CodeFileID,
        file: CodeFileSummary? = nil,
        segmentDictionary: SegmentDictionarySnapshot = SegmentDictionarySnapshot(entries: [], intrinsicSegmentNumbers: [], comment: ""),
        typeEnvironment: TypeEnvironmentSnapshot = TypeEnvironmentSnapshot(recordNames: [], typeAliases: [:], scalarTypeNames: [], constants: [:], subrangeTypeNames: []),
        segments: [SegmentID: SegmentSnapshot] = [:],
        procedures: [ProcedureID: ProcedureSnapshot] = [:],
        instructions: [InstructionID: InstructionSnapshot] = [:],
        locations: [LocationID: LocationFact] = [:],
        callsByOrigin: [ProcedureID: [CallEdge]] = [:],
        callsByTarget: [ProcedureID: [CallEdge]] = [:],
        diagnostics: [Diagnostic] = []
    ) {
        self.codeFileID = codeFileID
        self.file = file ?? CodeFileSummary(id: codeFileID, sourceFilename: codeFileID.value, segmentCount: segments.count, dataSegmentNumbers: [])
        self.segmentDictionary = segmentDictionary
        self.typeEnvironment = typeEnvironment
        self.segments = segments
        self.procedures = procedures
        self.instructions = instructions
        self.locations = locations
        self.callsByOrigin = callsByOrigin
        self.callsByTarget = callsByTarget
        self.diagnostics = diagnostics
    }
}

public struct SourceReference: Hashable, Sendable {
    public let procedureID: ProcedureID?
    public let instructionID: InstructionID?
    public let locationID: LocationID?

    public init(procedureID: ProcedureID? = nil, instructionID: InstructionID? = nil, locationID: LocationID? = nil) {
        self.procedureID = procedureID
        self.instructionID = instructionID
        self.locationID = locationID
    }
}

public struct DocumentSection: Sendable {
    public let id: String
    public let title: String
    public let nodeIDs: [DocumentNodeID]

    public init(id: String, title: String, nodeIDs: [DocumentNodeID]) {
        self.id = id
        self.title = title
        self.nodeIDs = nodeIDs
    }
}

public struct DocumentNode: Sendable {
    public let id: DocumentNodeID
    public let line: OutputLine
    public let provenance: FactProvenance

    public init(id: DocumentNodeID, line: OutputLine, provenance: FactProvenance = .rendered) {
        self.id = id
        self.line = line
        self.provenance = provenance
    }
}

public struct DisassemblyDocument: Sendable {
    public let id: DocumentID
    public let title: String
    public let sections: [DocumentSection]
    public let nodes: [DocumentNode]
    public let nodesByID: [DocumentNodeID: DocumentNode]
    public let sourceMap: [DocumentNodeID: SourceReference]

    public init(
        id: DocumentID,
        title: String = "",
        nodes: [DocumentNode] = [],
        sections: [DocumentSection]? = nil,
        sourceMap: [DocumentNodeID: SourceReference] = [:]
    ) {
        self.id = id
        self.title = title
        self.nodes = nodes
        self.sections = sections ?? [DocumentSection(id: "main", title: title.isEmpty ? "Disassembly" : title, nodeIDs: nodes.map(\.id))]
        self.nodesByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        self.sourceMap = sourceMap
    }

    public func patchingComment(_ comment: DisassemblyComment) -> (document: DisassemblyDocument, patchedNodes: [DocumentNodeID]) {
        var patchedNodes: [DocumentNode] = []
        var patchedNodeIDs: [DocumentNodeID] = []

        for node in nodes {
            guard node.line.commentReference == comment.reference else {
                patchedNodes.append(node)
                continue
            }

            let patchedLine = node.line.patchingCommentText(comment.comment)
            patchedNodes.append(DocumentNode(id: node.id, line: patchedLine))
            patchedNodeIDs.append(node.id)
        }

        return (DisassemblyDocument(id: id, title: title, nodes: patchedNodes, sections: sections, sourceMap: sourceMap), patchedNodeIDs)
    }

    public var sourceMapCoveragePercent: Int {
        guard !nodes.isEmpty else { return 100 }
        return (sourceMap.count * 100) / nodes.count
    }
}

public struct DocumentIndexes: Sendable {
    public let procedureNodes: [ProcedureID: DocumentNodeID]
    public let locationNodes: [LocationID: [DocumentNodeID]]
    public let instructionNodes: [InstructionID: DocumentNodeID]
    public let symbolNodes: [String: [DocumentNodeID]]
    public let searchIndex: [String: [DocumentNodeID]]

    public init(
        procedureNodes: [ProcedureID: DocumentNodeID] = [:],
        locationNodes: [LocationID: [DocumentNodeID]] = [:],
        instructionNodes: [InstructionID: DocumentNodeID] = [:],
        symbolNodes: [String: [DocumentNodeID]] = [:],
        searchIndex: [String: [DocumentNodeID]]? = nil
    ) {
        self.procedureNodes = procedureNodes
        self.locationNodes = locationNodes
        self.instructionNodes = instructionNodes
        self.symbolNodes = symbolNodes
        self.searchIndex = searchIndex ?? symbolNodes
    }

    public func search(_ query: String) -> [DocumentNodeID] {
        let key = query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !key.isEmpty else { return [] }
        return searchIndex[key] ?? []
    }
}

public struct DisassemblyRunResult: @unchecked Sendable {
    public let legacyResult: DisassemblyResult
    public let snapshot: ProgramSnapshot
    public let document: DisassemblyDocument
    public let indexes: DocumentIndexes
    public let report: RunReport
}

public struct DisassemblyService: Sendable {
    public init() {}

    public func run(_ request: DisassemblyRunRequest) throws -> DisassemblyRunResult {
        try request.checkCancellation()
        let codefileLoad = try CodefileLoadStage().run(
            CodefileLoadStageInput(source: request.source, cancellation: request.cancellation)
        )
        try request.checkCancellation()
        let metadataWorkspaceResolver = request.metadataWorkspace.map { MetadataScopeResolver(repository: FileBackedMetadataRepository(workspace: $0)) }
        let metadataMerge = try MetadataMergeStage(resolver: metadataWorkspaceResolver).run(
            MetadataMergeStageInput(
                fileIdentifier: codefileLoad.fileIdentifier,
                version: codefileLoad.version,
                explicit: request.metadata
            )
        )
        try request.checkCancellation()
        let legacy = try LegacyPipelineStages().run(
            LegacyPipelineStageInput(
                codefile: codefileLoad,
                metadata: metadataMerge.snapshot,
                options: request.options,
                workspace: request.metadataWorkspace,
                cancellation: request.cancellation
            )
        )
        let legacyResult = legacy.result
        try request.checkCancellation()
        let codeFileID = CodeFileID(legacyResult.sourceFilename)
        let snapshotBuild = try SnapshotBuildStage().run(
            SnapshotBuildStageInput(result: legacyResult, codeFileID: codeFileID, cancellation: request.cancellation)
        )
        let snapshot = snapshotBuild.snapshot
        let documentBuild = try DocumentBuildStage().run(
            DocumentBuildStageInput(
                result: legacyResult,
                snapshot: snapshot,
                id: DocumentID(codeFileID.value),
                title: legacyResult.sourceFilename,
                showStackState: request.options.showStackState,
                verbose: request.options.verbose,
                cancellation: request.cancellation
            )
        )
        let document = documentBuild.document
        let indexes = documentBuild.indexes
        try request.checkCancellation()
        let stageReports = [codefileLoad.report, metadataMerge.report] + legacy.reports + [snapshotBuild.report, documentBuild.report]
        let metadataWarnings = metadataMerge.report.diagnostics
        let report = RunReport(
            stages: stageReports,
            fatalErrors: legacyResult.runReport.fatalErrors,
            warnings: legacyResult.runReport.warnings,
            metadataWarnings: metadataWarnings,
            isComplete: stageReports.allSatisfy(\.isComplete),
            didConverge: stageReports.first { $0.name == "analysis" }?.isComplete ?? true
        )
        return DisassemblyRunResult(
            legacyResult: legacyResult,
            snapshot: snapshot,
            document: document,
            indexes: indexes,
            report: report
        )
    }
}


public struct SnapshotBuildStageInput: @unchecked Sendable {
    public let result: DisassemblyResult
    public let codeFileID: CodeFileID
    public let cancellation: CancellationToken?

    public init(result: DisassemblyResult, codeFileID: CodeFileID, cancellation: CancellationToken? = nil) {
        self.result = result
        self.codeFileID = codeFileID
        self.cancellation = cancellation
    }
}

public struct SnapshotBuildStageOutput: Sendable {
    public let snapshot: ProgramSnapshot
    public let report: StageReport
}

public struct SnapshotBuildStage: Sendable {
    public init() {}

    public func run(_ input: SnapshotBuildStageInput) throws -> SnapshotBuildStageOutput {
        if input.cancellation?.isCancellationRequested == true { throw DisassemblyCancelledError() }
        let snapshot = ProgramSnapshot.build(from: input.result, codeFileID: input.codeFileID)
        let danglingCalls = input.result.allCallers.filter { call in
            guard let targetProcedure = call.target.procedure else { return true }
            let targetID = ProcedureID(segment: SegmentID(codeFile: input.codeFileID, number: call.target.segment), number: targetProcedure)
            return snapshot.procedures[targetID] == nil
        }.count
        let diagnostics = danglingCalls == 0 ? [] : ["Snapshot contains \(danglingCalls) call references without decoded target procedures"]
        return SnapshotBuildStageOutput(snapshot: snapshot, report: StageReport(name: "snapshotBuild", isComplete: diagnostics.isEmpty, metrics: [
            "segments": snapshot.segments.count,
            "procedures": snapshot.procedures.count,
            "instructions": snapshot.instructions.count,
            "locations": snapshot.locations.count,
            "callEdges": snapshot.callsByOrigin.values.reduce(0) { $0 + $1.count },
            "diagnostics": input.result.diagnostics.count,
            "danglingCalls": danglingCalls,
        ], diagnostics: diagnostics))
    }
}

public struct DocumentBuildStageInput: @unchecked Sendable {
    public let result: DisassemblyResult
    public let snapshot: ProgramSnapshot
    public let id: DocumentID
    public let title: String
    public let showStackState: Bool
    public let verbose: Bool
    public let cancellation: CancellationToken?

    public init(result: DisassemblyResult, snapshot: ProgramSnapshot, id: DocumentID, title: String, showStackState: Bool, verbose: Bool, cancellation: CancellationToken? = nil) {
        self.result = result
        self.snapshot = snapshot
        self.id = id
        self.title = title
        self.showStackState = showStackState
        self.verbose = verbose
        self.cancellation = cancellation
    }
}

public struct DocumentBuildStageOutput: Sendable {
    public let document: DisassemblyDocument
    public let indexes: DocumentIndexes
    public let report: StageReport
}

public struct DocumentBuildStage: Sendable {
    public init() {}

    public func run(_ input: DocumentBuildStageInput) throws -> DocumentBuildStageOutput {
        if input.cancellation?.isCancellationRequested == true { throw DisassemblyCancelledError() }
        let structuredLines = renderStructuredLines(from: input.result, showStackState: input.showStackState, verbose: input.verbose)
        let document = DisassemblyDocument.build(from: structuredLines, snapshot: input.snapshot, id: input.id, title: input.title)
        let indexes = DocumentIndexes.build(document: document)
        let unmappedNodes = document.nodes.count - document.sourceMap.count
        return DocumentBuildStageOutput(document: document, indexes: indexes, report: StageReport(name: "documentBuild", metrics: [
            "documentNodes": document.nodes.count,
            "sourceMappedNodes": document.sourceMap.count,
            "unmappedNodes": unmappedNodes,
            "sourceMapCoveragePercent": document.sourceMapCoveragePercent,
            "procedureNodes": indexes.procedureNodes.count,
            "instructionNodes": indexes.instructionNodes.count,
            "locationNodes": indexes.locationNodes.count,
            "searchTerms": indexes.searchIndex.count,
        ]))
    }
}

public extension ProgramSnapshot {
    func dependentProcedureScope(for procedureID: ProcedureID) -> Set<ProcedureID> {
        var scope: Set<ProcedureID> = [procedureID]
        var pending: [ProcedureID] = [procedureID]

        while let target = pending.popLast() {
            for edge in callsByTarget[target] ?? [] {
                let caller = edge.origin.procedure
                if scope.insert(caller).inserted {
                    pending.append(caller)
                }
            }
        }

        return scope
    }
}

public extension OutputLine {
    func patchingCommentText(_ comment: String) -> OutputLine {
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        let patchedText: String

        if let semicolon = text.range(of: " ; ") {
            let prefix = String(text[..<semicolon.lowerBound])
            patchedText = trimmed.isEmpty ? prefix : "\(prefix) ; \(trimmed)"
        } else {
            patchedText = trimmed.isEmpty ? text : "\(text) ; \(trimmed)"
        }

        return OutputLine(
            id: id,
            kind: kind,
            text: patchedText,
            anchor: anchor,
            locationReference: locationReference,
            commentReference: commentReference,
            headerEditTargets: headerEditTargets
        )
    }
}

private extension ProgramSnapshot {
    static func build(from result: DisassemblyResult, codeFileID: CodeFileID) -> ProgramSnapshot {
        var segments: [SegmentID: SegmentSnapshot] = [:]
        var procedures: [ProcedureID: ProcedureSnapshot] = [:]
        var instructions: [InstructionID: InstructionSnapshot] = [:]
        var locations: [LocationID: LocationFact] = [:]

        for location in result.allLocations {
            let id = LocationID(codeFile: codeFileID, legacy: location)
            locations[id] = LocationFact(id: id, name: location.name, type: location.type, typeSource: location.typeSource, isParameter: location.isParam, provenance: provenance(for: location))
        }

        for (segmentNumber, codeSegment) in result.codeSegments {
            let segmentID = SegmentID(codeFile: codeFileID, number: segmentNumber)
            let segmentName = result.segDictionary.segTable.first { $0.value.segNum == segmentNumber }?.value.name ?? "Unknown"
            var procedureIDs: [ProcedureID] = []

            for procedure in codeSegment.procedures {
                guard let legacyID = procedure.identifier else { continue }
                let procedureID = ProcedureID(codeFile: codeFileID, legacy: legacyID)
                procedureIDs.append(procedureID)
                let instructionIDs = procedure.instructions.keys.sorted().map {
                    InstructionID(procedure: procedureID, offset: $0)
                }
                procedures[procedureID] = ProcedureSnapshot(
                    id: procedureID,
                    name: legacyID.procName ?? legacyID.shortDescription,
                    isFunction: legacyID.isFunction,
                    isAssembly: legacyID.isAssembly,
                    lexicalLevel: procedure.lexicalLevel,
                    dataSize: procedure.dataSize,
                    parameterSize: procedure.parameterSize,
                    instructionIDs: instructionIDs,
                    provenance: provenance(for: legacyID)
                )

                for offset in procedure.instructions.keys.sorted() {
                    guard let instruction = procedure.instructions[offset] else { continue }
                    let instructionID = InstructionID(procedure: procedureID, offset: offset)
                    instructions[instructionID] = InstructionSnapshot(
                        id: instructionID,
                        opcode: instruction.opcode,
                        mnemonic: instruction.mnemonic,
                        parameters: instruction.params,
                        locationID: instruction.memLocation.map { LocationID(codeFile: codeFileID, legacy: $0) },
                        destinationID: instruction.destination.map { LocationID(codeFile: codeFileID, legacy: $0) },
                        comment: instruction.comment,
                        userComment: instruction.userComment,
                        commentProvenance: instruction.userComment == nil ? nil : .metadata(MetadataProvenance(source: "metadata-comment", precedence: 0))
                    )
                }
            }

            segments[segmentID] = SegmentSnapshot(id: segmentID, name: segmentName, procedureIDs: procedureIDs, provenance: .decoded)
        }

        var callsByOrigin: [ProcedureID: [CallEdge]] = [:]
        var callsByTarget: [ProcedureID: [CallEdge]] = [:]
        for call in result.allCallers {
            guard let originProcedureNumber = call.origin.procedure,
                  let originAddress = call.origin.addr,
                  let targetProcedureNumber = call.target.procedure
            else { continue }
            let originProcedure = ProcedureID(
                segment: SegmentID(codeFile: codeFileID, number: call.origin.segment),
                number: originProcedureNumber
            )
            let targetProcedure = ProcedureID(
                segment: SegmentID(codeFile: codeFileID, number: call.target.segment),
                number: targetProcedureNumber
            )
            let originInstruction = InstructionID(procedure: originProcedure, offset: originAddress)
            let edge = CallEdge(id: CallEdgeID(origin: originInstruction, target: targetProcedure), origin: originInstruction, target: targetProcedure)
            callsByOrigin[originProcedure, default: []].append(edge)
            callsByTarget[targetProcedure, default: []].append(edge)
        }

        let file = CodeFileSummary(
            id: codeFileID,
            sourceFilename: result.sourceFilename,
            segmentCount: result.codeSegments.count,
            dataSegmentNumbers: result.dataSegments.sorted()
        )
        let segmentDictionary = SegmentDictionarySnapshot(
            entries: result.segDictionary.segTable.map { slot, segment in
                SegmentDictionaryEntrySnapshot(
                    slot: slot,
                    segmentID: SegmentID(codeFile: codeFileID, number: segment.segNum),
                    name: segment.name,
                    codeAddress: segment.codeAddress,
                    codeLength: segment.codeLength,
                    kind: String(describing: segment.segmentKind),
                    textAddress: segment.textAddress,
                    machineType: segment.machineType,
                    version: segment.version
                )
            }.sorted { $0.slot < $1.slot },
            intrinsicSegmentNumbers: result.segDictionary.intrinsics.sorted(),
            comment: result.segDictionary.comment
        )
        let typeEnvironment = TypeEnvironmentSnapshot(
            recordNames: result.knownRecords.map(\.name).sorted(),
            typeAliases: result.typeAliases,
            scalarTypeNames: result.scalarTypes.keys.sorted(),
            constants: result.constants,
            subrangeTypeNames: result.subrangeTypes.keys.sorted()
        )

        return ProgramSnapshot(
            codeFileID: codeFileID,
            file: file,
            segmentDictionary: segmentDictionary,
            typeEnvironment: typeEnvironment,
            segments: segments,
            procedures: procedures,
            instructions: instructions,
            locations: locations,
            callsByOrigin: callsByOrigin.mapValues { $0.sorted { $0.id.description < $1.id.description } },
            callsByTarget: callsByTarget.mapValues { $0.sorted { $0.id.description < $1.id.description } },
            diagnostics: result.diagnostics
        )
    }

    static func provenance(for location: Location) -> FactProvenance {
        switch location.typeSource {
        case .user: return FactProvenance(source: "user-metadata")
        case .metadata: return FactProvenance(source: "metadata")
        case .inferred: return .inferred
        default: return .decoded
        }
    }

    static func provenance(for procedure: ProcedureIdentifier) -> FactProvenance {
        procedure.procName == nil ? .decoded : FactProvenance(source: "procedure-metadata")
    }
}

private extension DisassemblyDocument {
    static func build(from lines: [OutputLine], snapshot: ProgramSnapshot, id: DocumentID, title: String) -> DisassemblyDocument {
        let nodes = lines.map { line in
            DocumentNode(id: nodeID(for: line, in: id, snapshot: snapshot), line: line)
        }
        let sections = buildSections(nodes: nodes, title: title)
        var sourceMap: [DocumentNodeID: SourceReference] = [:]
        for node in nodes {
            let reference = sourceReference(for: node.line, snapshot: snapshot)
            let procedureID = reference.procedureID
            let instructionID = reference.instructionID
            let locationID = reference.locationID
            if procedureID != nil || instructionID != nil || locationID != nil {
                sourceMap[node.id] = reference
            }
        }
        return DisassemblyDocument(id: id, title: title, nodes: nodes, sections: sections, sourceMap: sourceMap)
    }

    private static func sourceReference(for line: OutputLine, snapshot: ProgramSnapshot) -> SourceReference {
        let locationID = line.locationReference.map { LocationID(codeFile: snapshot.codeFileID, legacy: $0) }
        let instructionID = line.commentReference.flatMap { InstructionID(codeFile: snapshot.codeFileID, legacy: $0) }
        let procedureID = instructionID?.procedure ?? locationID?.procedure ?? procedureID(for: line.anchor, snapshot: snapshot)
        return SourceReference(procedureID: procedureID, instructionID: instructionID, locationID: locationID)
    }

    private static func nodeID(for line: OutputLine, in documentID: DocumentID, snapshot: ProgramSnapshot) -> DocumentNodeID {
        let reference = sourceReference(for: line, snapshot: snapshot)
        if let instructionID = reference.instructionID {
            return DocumentNodeID(document: documentID, value: "instruction-\(instructionID.procedure.segment.number)-\(instructionID.procedure.number)-\(instructionID.offset)-line-\(line.id)")
        }
        if let locationID = reference.locationID {
            let procedure = locationID.procedure.map { "\($0.number)" } ?? "global"
            let lexicalLevel = locationID.lexicalLevel.map(String.init) ?? "none"
            let address = locationID.address.map(String.init) ?? "none"
            return DocumentNodeID(document: documentID, value: "location-\(locationID.segment.number)-\(procedure)-\(lexicalLevel)-\(address)-line-\(line.id)")
        }
        if let procedureID = reference.procedureID {
            return DocumentNodeID(document: documentID, value: "procedure-\(procedureID.segment.number)-\(procedureID.number)")
        }
        return DocumentNodeID(document: documentID, value: "line-\(line.id)")
    }

    private static func procedureID(for anchor: String?, snapshot: ProgramSnapshot) -> ProcedureID? {
        guard let anchor else { return nil }
        let parts = anchor.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        let procedureID = ProcedureID(segment: SegmentID(codeFile: snapshot.codeFileID, number: parts[0]), number: parts[1])
        return snapshot.procedures[procedureID] == nil ? nil : procedureID
    }
}

private func buildSections(nodes: [DocumentNode], title: String) -> [DocumentSection] {
    var sections: [DocumentSection] = []
    var currentTitle = title.isEmpty ? "Preamble" : title
    var currentIDs: [DocumentNodeID] = []
    var currentID = "section-0"

    func flush() {
        if !currentIDs.isEmpty {
            sections.append(DocumentSection(id: currentID, title: currentTitle, nodeIDs: currentIDs))
        }
    }

    for node in nodes {
        if let anchor = node.line.anchor {
            flush()
            currentID = "procedure-\(anchor.replacingOccurrences(of: ".", with: "-"))"
            currentTitle = node.line.text
            currentIDs = []
        }
        currentIDs.append(node.id)
    }
    flush()
    return sections.isEmpty ? [DocumentSection(id: "main", title: title.isEmpty ? "Disassembly" : title, nodeIDs: nodes.map(\.id))] : sections
}

private extension DocumentIndexes {
    static func build(document: DisassemblyDocument) -> DocumentIndexes {
        var procedureNodes: [ProcedureID: DocumentNodeID] = [:]
        var locationNodes: [LocationID: [DocumentNodeID]] = [:]
        var instructionNodes: [InstructionID: DocumentNodeID] = [:]
        var symbolNodes: [String: [DocumentNodeID]] = [:]
        var searchIndex: [String: [DocumentNodeID]] = [:]

        for node in document.nodes {
            let line = node.line
            if let reference = document.sourceMap[node.id] {
                if let procedureID = reference.procedureID, line.anchor != nil {
                    procedureNodes[procedureID] = node.id
                }
                if let locationID = reference.locationID {
                    locationNodes[locationID, default: []].append(node.id)
                }
                if let instructionID = reference.instructionID {
                    instructionNodes[instructionID] = instructionNodes[instructionID] ?? node.id
                }
            }
            for token in line.text.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" }) {
                let key = String(token).uppercased()
                symbolNodes[key, default: []].append(node.id)
                searchIndex[key, default: []].append(node.id)
            }
            for word in line.text.split(whereSeparator: { $0.isWhitespace }) {
                searchIndex[String(word).uppercased(), default: []].append(node.id)
            }
        }

        return DocumentIndexes(
            procedureNodes: procedureNodes,
            locationNodes: locationNodes,
            instructionNodes: instructionNodes,
            symbolNodes: symbolNodes,
            searchIndex: searchIndex.mapValues { Array(Set($0)).sorted { $0.description < $1.description } }
        )
    }
}

public func renderDisassemblyDocument(
    _ document: DisassemblyDocument,
    showMarkup: Bool = true,
    showPCode: Bool = true,
    showPseudoCode: Bool = true
) -> String {
    document.nodes
        .map(\.line)
        .filter {
            shouldEmitLine($0, showMarkup: showMarkup, showPCode: showPCode, showPseudoCode: showPseudoCode)
        }
        .map(\.text)
        .joined(separator: "\n") + "\n"
}


public extension MetadataSnapshot {
    var isEmpty: Bool { labels.isEmpty && procedures.isEmpty && comments.isEmpty }
}

public struct CodefileLoadStageInput: Sendable {
    public let source: CodeFileSource
    public let cancellation: CancellationToken?

    public init(source: CodeFileSource, cancellation: CancellationToken? = nil) {
        self.source = source
        self.cancellation = cancellation
    }
}

public struct CodefileLoadStage: Sendable {
    public init() {}

    public func run(_ input: CodefileLoadStageInput) throws -> CodefileLoadStageOutput {
        if input.cancellation?.isCancellationRequested == true { throw DisassemblyCancelledError() }
        let filename = try input.source.filenameForLegacyRunner
        let data = try Data(contentsOf: URL(fileURLWithPath: filename))
        let codeData = CodeData(data: data)
        let fileIdentifier = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        var version = 0
        var segmentCount = 0
        var diagnostics: [String] = []
        if data.count >= 80 {
            do {
                let segDictionary = try readCodeFileStructure(codeData: codeData)
                version = segDictionary.segTable[1]?.version ?? segDictionary.segTable[0]?.version ?? 0
                segmentCount = segDictionary.segTable.count
            } catch {
                diagnostics.append("Codefile dictionary preflight failed: \(error)")
            }
        } else {
            diagnostics.append("Codefile is too small for segment dictionary preflight")
        }
        return CodefileLoadStageOutput(
            filename: filename,
            fileIdentifier: fileIdentifier,
            data: data,
            version: version,
            segmentCount: segmentCount,
            report: StageReport(name: "codefileLoading", isComplete: diagnostics.isEmpty, metrics: [
                "bytes": data.count,
                "segments": segmentCount,
                "version": version,
            ], diagnostics: diagnostics)
        )
    }

    public func run(source: CodeFileSource, cancellation: CancellationToken? = nil) throws -> CodefileLoadStageOutput {
        try run(CodefileLoadStageInput(source: source, cancellation: cancellation))
    }
}

public struct CodefileLoadStageOutput: Sendable {
    public let filename: String
    public let fileIdentifier: String
    public let data: Data
    public let version: Int
    public let segmentCount: Int
    public let report: StageReport
}

public struct MetadataMergeStageInput: Sendable {
    public let fileIdentifier: String
    public let version: Int
    public let explicit: MetadataSnapshot

    public init(fileIdentifier: String, version: Int, explicit: MetadataSnapshot = MetadataSnapshot()) {
        self.fileIdentifier = fileIdentifier
        self.version = version
        self.explicit = explicit
    }
}

public struct MetadataMergeStage: Sendable {
    public let resolver: MetadataScopeResolver?
    public init(resolver: MetadataScopeResolver? = nil) { self.resolver = resolver }

    public func run(_ input: MetadataMergeStageInput) throws -> MetadataMergeStageOutput {
        let snapshot = input.explicit.isEmpty ? (try resolver?.resolve(fileIdentifier: input.fileIdentifier, version: input.version) ?? MetadataSnapshot()) : input.explicit
        return MetadataMergeStageOutput(snapshot: snapshot, report: StageReport(name: "metadataMerge", metrics: [
            "labels": snapshot.labels.count,
            "procedures": snapshot.procedures.count,
            "comments": snapshot.comments.count,
        ]))
    }

    public func run(fileIdentifier: String, version: Int, explicit: MetadataSnapshot = MetadataSnapshot()) throws -> MetadataMergeStageOutput {
        try run(MetadataMergeStageInput(fileIdentifier: fileIdentifier, version: version, explicit: explicit))
    }
}

public struct MetadataMergeStageOutput: Sendable {
    public let snapshot: MetadataSnapshot
    public let report: StageReport
}

public struct LegacyPipelineStageInput: Sendable {
    public let codefile: CodefileLoadStageOutput
    public let metadata: MetadataSnapshot
    public let options: DisassemblyOptions
    public let workspace: MetadataWorkspace?
    public let cancellation: CancellationToken?

    public init(codefile: CodefileLoadStageOutput, metadata: MetadataSnapshot, options: DisassemblyOptions, workspace: MetadataWorkspace? = nil, cancellation: CancellationToken? = nil) {
        self.codefile = codefile
        self.metadata = metadata
        self.options = options
        self.workspace = workspace
        self.cancellation = cancellation
    }
}

public struct LegacyPipelineStageOutput: @unchecked Sendable {
    public let result: DisassemblyResult
    public let reports: [StageReport]
}

public struct LegacyPipelineStages: Sendable {
    public init() {}

    public func run(_ input: LegacyPipelineStageInput) throws -> LegacyPipelineStageOutput {
        if input.cancellation?.isCancellationRequested == true { throw DisassemblyCancelledError() }
        let metadata = input.metadata.isEmpty ? nil : input.metadata
        let result = try disassemble(
            filename: input.codefile.filename,
            verbose: input.options.verbose,
            writeMetadata: input.options.writeMetadata,
            overwriteMetadata: input.options.overwriteMetadata,
            metadataWorkspace: input.workspace,
            metadataSnapshot: metadata
        )
        if input.cancellation?.isCancellationRequested == true { throw DisassemblyCancelledError() }
        let reports = result.runReport.stages.filter { !["codefileLoading", "metadataMerge"].contains($0.name) }
        return LegacyPipelineStageOutput(result: result, reports: reports)
    }

    public func run(filename: String, options: DisassemblyOptions, workspace: MetadataWorkspace?, metadata: MetadataSnapshot?) throws -> DisassemblyResult {
        try disassemble(filename: filename, verbose: options.verbose, writeMetadata: options.writeMetadata, overwriteMetadata: options.overwriteMetadata, metadataWorkspace: workspace, metadataSnapshot: metadata)
    }
}
