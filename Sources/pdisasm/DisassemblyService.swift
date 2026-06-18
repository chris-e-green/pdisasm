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

public struct ProgramSnapshot: Sendable {
    public let codeFileID: CodeFileID
    public init(codeFileID: CodeFileID) { self.codeFileID = codeFileID }
}

public struct DisassemblyDocument: Sendable {
    public let id: DocumentID
    public init(id: DocumentID) { self.id = id }
}

public struct DocumentIndexes: Sendable {
    public init() {}
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
        let report = RunReport(stages: [
            StageReport(name: "legacyDisassembly", metrics: [
                "segments": legacyResult.codeSegments.count,
                "procedures": legacyResult.allProcedures.count,
                "diagnostics": legacyResult.diagnostics.count,
            ])
        ])
        return DisassemblyRunResult(
            legacyResult: legacyResult,
            snapshot: ProgramSnapshot(codeFileID: codeFileID),
            document: DisassemblyDocument(id: DocumentID(codeFileID.value)),
            indexes: DocumentIndexes(),
            report: report
        )
    }
}
