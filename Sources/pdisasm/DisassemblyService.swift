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

public struct StageReport: Hashable, Codable, Sendable {
    public let name: String
    public let isComplete: Bool
    public let metrics: [String: Int]
    public let diagnostics: [String]

    public init(name: String, isComplete: Bool = true, metrics: [String: Int] = [:], diagnostics: [String] = []) {
        self.name = name
        self.isComplete = isComplete
        self.metrics = metrics
        self.diagnostics = diagnostics
    }
}

public struct RunReport: Hashable, Codable, Sendable {
    public let stages: [StageReport]
    public let fatalErrors: [String]
    public let warnings: [String]
    public let isComplete: Bool

    public init(stages: [StageReport] = [], fatalErrors: [String] = [], warnings: [String] = [], isComplete: Bool = true) {
        self.stages = stages
        self.fatalErrors = fatalErrors
        self.warnings = warnings
        self.isComplete = isComplete
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
}

public struct LocationFact: Sendable {
    public let id: LocationID
    public let name: String
    public let type: String
    public let typeSource: TypeSource
    public let isParameter: Bool
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
        let filename = try request.source.filenameForLegacyRunner
        try request.checkCancellation()
        let injectedMetadata: MetadataSnapshot? = request.metadata.isEmpty ? nil : request.metadata
        let legacyResult = try disassemble(
            filename: filename,
            verbose: request.options.verbose,
            writeMetadata: request.options.writeMetadata,
            overwriteMetadata: request.options.overwriteMetadata,
            metadataWorkspace: request.metadataWorkspace,
            metadataSnapshot: injectedMetadata
        )
        try request.checkCancellation()
        let codeFileID = CodeFileID(legacyResult.sourceFilename)
        let snapshot = ProgramSnapshot.build(from: legacyResult, codeFileID: codeFileID)
        let structuredLines = renderStructuredLines(
            from: legacyResult,
            showStackState: request.options.showStackState,
            verbose: request.options.verbose
        )
        let document = DisassemblyDocument.build(from: structuredLines, id: DocumentID(codeFileID.value), title: legacyResult.sourceFilename, codeFileID: codeFileID)
        let indexes = DocumentIndexes.build(document: document, codeFileID: codeFileID)
        try request.checkCancellation()
        let report = RunReport(stages: legacyResult.runReport.stages + [
            StageReport(name: "snapshotBuild", metrics: [
                "segments": snapshot.segments.count,
                "procedures": snapshot.procedures.count,
                "instructions": snapshot.instructions.count,
                "locations": snapshot.locations.count,
            ]),
            StageReport(name: "documentBuild", metrics: [
                "documentNodes": document.nodes.count,
                "procedureNodes": indexes.procedureNodes.count,
                "instructionNodes": indexes.instructionNodes.count,
            ]),
        ], warnings: legacyResult.runReport.warnings, isComplete: legacyResult.runReport.isComplete)
        return DisassemblyRunResult(
            legacyResult: legacyResult,
            snapshot: snapshot,
            document: document,
            indexes: indexes,
            report: report
        )
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
            locations[id] = LocationFact(id: id, name: location.name, type: location.type, typeSource: location.typeSource, isParameter: location.isParam)
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
                    instructionIDs: instructionIDs
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
                        userComment: instruction.userComment
                    )
                }
            }

            segments[segmentID] = SegmentSnapshot(id: segmentID, name: segmentName, procedureIDs: procedureIDs)
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
}

private extension DisassemblyDocument {
    static func build(from lines: [OutputLine], id: DocumentID, title: String, codeFileID: CodeFileID) -> DisassemblyDocument {
        let nodes = lines.map { line in
            DocumentNode(id: DocumentNodeID(document: id, value: "line-\(line.id)"), line: line)
        }
        let sections = buildSections(nodes: nodes, title: title)
        var sourceMap: [DocumentNodeID: SourceReference] = [:]
        for node in nodes {
            let locationID = node.line.locationReference.map { LocationID(codeFile: codeFileID, legacy: $0) }
            let instructionID = node.line.commentReference.flatMap { InstructionID(codeFile: codeFileID, legacy: $0) }
            let procedureID = instructionID?.procedure ?? locationID?.procedure
            if procedureID != nil || instructionID != nil || locationID != nil {
                sourceMap[node.id] = SourceReference(procedureID: procedureID, instructionID: instructionID, locationID: locationID)
            }
        }
        return DisassemblyDocument(id: id, title: title, nodes: nodes, sections: sections, sourceMap: sourceMap)
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
    static func build(document: DisassemblyDocument, codeFileID: CodeFileID) -> DocumentIndexes {
        var procedureNodes: [ProcedureID: DocumentNodeID] = [:]
        var locationNodes: [LocationID: [DocumentNodeID]] = [:]
        var instructionNodes: [InstructionID: DocumentNodeID] = [:]
        var symbolNodes: [String: [DocumentNodeID]] = [:]
        var searchIndex: [String: [DocumentNodeID]] = [:]

        for node in document.nodes {
            let line = node.line
            if let anchor = line.anchor {
                let parts = anchor.split(separator: ".").compactMap { Int($0) }
                if parts.count == 2 {
                    let procedureID = ProcedureID(segment: SegmentID(codeFile: codeFileID, number: parts[0]), number: parts[1])
                    procedureNodes[procedureID] = node.id
                }
            }
            if let location = line.locationReference {
                let id = LocationID(codeFile: codeFileID, legacy: location)
                locationNodes[id, default: []].append(node.id)
            }
            if let reference = line.commentReference,
               let id = InstructionID(codeFile: codeFileID, legacy: reference) {
                instructionNodes[id] = node.id
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

public struct CodefileLoadStage: Sendable {
    public init() {}
    public func run(source: CodeFileSource, cancellation: CancellationToken? = nil) throws -> CodefileLoadStageOutput {
        if cancellation?.isCancellationRequested == true { throw DisassemblyCancelledError() }
        let filename = try source.filenameForLegacyRunner
        let data = try Data(contentsOf: URL(fileURLWithPath: filename))
        return CodefileLoadStageOutput(filename: filename, data: data, report: StageReport(name: "codefileLoading", metrics: ["bytes": data.count]))
    }
}

public struct CodefileLoadStageOutput: Sendable {
    public let filename: String
    public let data: Data
    public let report: StageReport
}

public struct MetadataMergeStage: Sendable {
    public let resolver: MetadataScopeResolver?
    public init(resolver: MetadataScopeResolver? = nil) { self.resolver = resolver }
    public func run(fileIdentifier: String, version: Int, explicit: MetadataSnapshot = MetadataSnapshot()) throws -> MetadataMergeStageOutput {
        let snapshot = explicit.isEmpty ? (try resolver?.resolve(fileIdentifier: fileIdentifier, version: version) ?? MetadataSnapshot()) : explicit
        return MetadataMergeStageOutput(snapshot: snapshot, report: StageReport(name: "metadataMerge", metrics: [
            "labels": snapshot.labels.count,
            "procedures": snapshot.procedures.count,
            "comments": snapshot.comments.count,
        ]))
    }
}

public struct MetadataMergeStageOutput: Sendable {
    public let snapshot: MetadataSnapshot
    public let report: StageReport
}

public struct LegacyPipelineStages: Sendable {
    public init() {}
    public func run(filename: String, options: DisassemblyOptions, workspace: MetadataWorkspace?, metadata: MetadataSnapshot?) throws -> DisassemblyResult {
        try disassemble(filename: filename, verbose: options.verbose, writeMetadata: options.writeMetadata, overwriteMetadata: options.overwriteMetadata, metadataWorkspace: workspace, metadataSnapshot: metadata)
    }
}
