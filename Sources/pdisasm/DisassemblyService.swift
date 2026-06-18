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

public struct DisassemblyRunRequest: Sendable {
    public let source: CodeFileSource
    public let metadata: MetadataSnapshot
    public let options: DisassemblyOptions

    public init(source: CodeFileSource, metadata: MetadataSnapshot = MetadataSnapshot(), options: DisassemblyOptions = DisassemblyOptions()) {
        self.source = source
        self.metadata = metadata
        self.options = options
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
    public let segments: [SegmentID: SegmentSnapshot]
    public let procedures: [ProcedureID: ProcedureSnapshot]
    public let instructions: [InstructionID: InstructionSnapshot]
    public let locations: [LocationID: LocationFact]
    public let callsByOrigin: [ProcedureID: [CallEdge]]
    public let callsByTarget: [ProcedureID: [CallEdge]]
    public let diagnostics: [Diagnostic]

    public init(
        codeFileID: CodeFileID,
        segments: [SegmentID: SegmentSnapshot] = [:],
        procedures: [ProcedureID: ProcedureSnapshot] = [:],
        instructions: [InstructionID: InstructionSnapshot] = [:],
        locations: [LocationID: LocationFact] = [:],
        callsByOrigin: [ProcedureID: [CallEdge]] = [:],
        callsByTarget: [ProcedureID: [CallEdge]] = [:],
        diagnostics: [Diagnostic] = []
    ) {
        self.codeFileID = codeFileID
        self.segments = segments
        self.procedures = procedures
        self.instructions = instructions
        self.locations = locations
        self.callsByOrigin = callsByOrigin
        self.callsByTarget = callsByTarget
        self.diagnostics = diagnostics
    }
}

public struct DocumentNode: Sendable {
    public let id: DocumentNodeID
    public let line: OutputLine
}

public struct DisassemblyDocument: Sendable {
    public let id: DocumentID
    public let title: String
    public let nodes: [DocumentNode]
    public let nodesByID: [DocumentNodeID: DocumentNode]

    public init(id: DocumentID, title: String = "", nodes: [DocumentNode] = []) {
        self.id = id
        self.title = title
        self.nodes = nodes
        self.nodesByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
    }
}

public struct DocumentIndexes: Sendable {
    public let procedureNodes: [ProcedureID: DocumentNodeID]
    public let locationNodes: [LocationID: [DocumentNodeID]]
    public let instructionNodes: [InstructionID: DocumentNodeID]
    public let symbolNodes: [String: [DocumentNodeID]]

    public init(
        procedureNodes: [ProcedureID: DocumentNodeID] = [:],
        locationNodes: [LocationID: [DocumentNodeID]] = [:],
        instructionNodes: [InstructionID: DocumentNodeID] = [:],
        symbolNodes: [String: [DocumentNodeID]] = [:]
    ) {
        self.procedureNodes = procedureNodes
        self.locationNodes = locationNodes
        self.instructionNodes = instructionNodes
        self.symbolNodes = symbolNodes
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
        let filename = try request.source.filenameForLegacyRunner
        let legacyResult = try disassemble(
            filename: filename,
            verbose: request.options.verbose,
            writeMetadata: request.options.writeMetadata,
            overwriteMetadata: request.options.overwriteMetadata
        )
        let codeFileID = CodeFileID(legacyResult.sourceFilename)
        let snapshot = ProgramSnapshot.build(from: legacyResult, codeFileID: codeFileID)
        let structuredLines = renderStructuredLines(
            from: legacyResult,
            showStackState: request.options.showStackState,
            verbose: request.options.verbose
        )
        let document = DisassemblyDocument.build(from: structuredLines, id: DocumentID(codeFileID.value), title: legacyResult.sourceFilename)
        let indexes = DocumentIndexes.build(document: document, codeFileID: codeFileID)
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

        return ProgramSnapshot(
            codeFileID: codeFileID,
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
    static func build(from lines: [OutputLine], id: DocumentID, title: String) -> DisassemblyDocument {
        let nodes = lines.map { line in
            DocumentNode(id: DocumentNodeID(document: id, value: "line-\(line.id)"), line: line)
        }
        return DisassemblyDocument(id: id, title: title, nodes: nodes)
    }
}

private extension DocumentIndexes {
    static func build(document: DisassemblyDocument, codeFileID: CodeFileID) -> DocumentIndexes {
        var procedureNodes: [ProcedureID: DocumentNodeID] = [:]
        var locationNodes: [LocationID: [DocumentNodeID]] = [:]
        var instructionNodes: [InstructionID: DocumentNodeID] = [:]
        var symbolNodes: [String: [DocumentNodeID]] = [:]

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
                symbolNodes[String(token).uppercased(), default: []].append(node.id)
            }
        }

        return DocumentIndexes(
            procedureNodes: procedureNodes,
            locationNodes: locationNodes,
            instructionNodes: instructionNodes,
            symbolNodes: symbolNodes
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
