import Foundation

public struct MetadataWorkspace: Hashable, Sendable {
    public let writableDirectory: URL
    public let bundledDirectory: URL?

    public init(writableDirectory: URL, bundledDirectory: URL? = nil) {
        self.writableDirectory = writableDirectory
        self.bundledDirectory = bundledDirectory
    }

    public static func applicationSupport(fileManager: FileManager = .default) -> MetadataWorkspace {
        let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        return MetadataWorkspace(
            writableDirectory: URL.applicationSupportDirectory.appendingPathComponent("pdisasm", isDirectory: true),
            bundledDirectory: cwd.appendingPathComponent("metadata", isDirectory: true)
        )
    }
}

public struct MetadataProvenance: Hashable, Codable, Sendable {
    public let source: String
    public let precedence: Int
    public init(source: String, precedence: Int) {
        self.source = source
        self.precedence = precedence
    }
}

public struct ProvenancedMetadataFact<Value: Hashable & Codable>: Hashable, Codable, @unchecked Sendable {
    public let value: Value
    public let provenance: MetadataProvenance
    public init(value: Value, provenance: MetadataProvenance) {
        self.value = value
        self.provenance = provenance
    }
}

public struct MetadataBundle: Hashable, Codable, @unchecked Sendable {
    public var labels: [ProvenancedMetadataFact<Location>]
    public var procedures: [ProvenancedMetadataFact<ProcedureIdentifier>]
    public var comments: [ProvenancedMetadataFact<DisassemblyComment>]

    public init(
        labels: [ProvenancedMetadataFact<Location>] = [],
        procedures: [ProvenancedMetadataFact<ProcedureIdentifier>] = [],
        comments: [ProvenancedMetadataFact<DisassemblyComment>] = []
    ) {
        self.labels = labels
        self.procedures = procedures
        self.comments = comments
    }
}

public struct MetadataSnapshot: Hashable, Codable, @unchecked Sendable {
    public var labels: [ProvenancedMetadataFact<Location>]
    public var procedures: [ProvenancedMetadataFact<ProcedureIdentifier>]
    public var comments: [ProvenancedMetadataFact<DisassemblyComment>]

    public init(
        labels: [ProvenancedMetadataFact<Location>] = [],
        procedures: [ProvenancedMetadataFact<ProcedureIdentifier>] = [],
        comments: [ProvenancedMetadataFact<DisassemblyComment>] = []
    ) {
        self.labels = labels
        self.procedures = procedures
        self.comments = comments
    }

    public init(merging bundles: [MetadataBundle]) {
        var labels: [LocationReference: ProvenancedMetadataFact<Location>] = [:]
        var procedures: [ProcedureKey: ProvenancedMetadataFact<ProcedureIdentifier>] = [:]
        var comments: [InstructionReference: ProvenancedMetadataFact<DisassemblyComment>] = [:]
        for bundle in bundles {
            for fact in bundle.labels { labels.mergeKeepingHighestPrecedence(fact, key: LocationReference(fact.value)) }
            for fact in bundle.procedures { procedures.mergeKeepingHighestPrecedence(fact, key: ProcedureKey(fact.value)) }
            for fact in bundle.comments { comments.mergeKeepingHighestPrecedence(fact, key: fact.value.reference) }
        }
        self.labels = labels.values.sorted { $0.value < $1.value }
        self.procedures = procedures.values.sorted { lhs, rhs in
            if lhs.value.segment != rhs.value.segment { return lhs.value.segment < rhs.value.segment }
            return lhs.value.procedure < rhs.value.procedure
        }
        self.comments = comments.values.sorted { lhs, rhs in
            if lhs.value.segment != rhs.value.segment { return lhs.value.segment < rhs.value.segment }
            if lhs.value.procedure != rhs.value.procedure { return (lhs.value.procedure ?? -1) < (rhs.value.procedure ?? -1) }
            return lhs.value.addr < rhs.value.addr
        }
    }
}

private extension Dictionary {
    mutating func mergeKeepingHighestPrecedence<ValueType>(_ fact: ProvenancedMetadataFact<ValueType>, key: Key) where Value == ProvenancedMetadataFact<ValueType> {
        if self[key]?.provenance.precedence ?? Int.min <= fact.provenance.precedence { self[key] = fact }
    }
}

private struct ProcedureKey: Hashable, Codable, Sendable {
    let segment: Int
    let procedure: Int
    init(_ procedure: ProcedureIdentifier) { self.segment = procedure.segment; self.procedure = procedure.procedure }
}

public protocol MetadataRepository: Sendable {
    func loadBundle(named name: String, kind: MetadataFileKind, provenance: MetadataProvenance) throws -> MetadataBundle
    func saveLabels(_ labels: [Location], named name: String) throws
    func saveProcedures(_ procedures: [ProcedureIdentifier], named name: String) throws
    func saveComments(_ comments: [DisassemblyComment], named name: String) throws
}

public enum MetadataFileKind: Sendable { case labelsCSV, proceduresCSV, commentsJSON }

public enum MetadataInvalidationScope: Hashable, Sendable { case documentOnly, procedureSignature(segment: Int, procedure: Int), fullDisassembly }

public enum ProcedureSignatureEditField: Hashable, Sendable { case procedureName, parameter(Int), returnType }

public struct MetadataEditingService: Sendable {
    public let repository: MetadataRepository
    public init(repository: MetadataRepository) { self.repository = repository }

    @discardableResult
    public func upsertLabel(_ location: Location, fileIdentifier: String) throws -> MetadataInvalidationScope {
        let name = "labels_\(fileIdentifier)"
        var labels = try repository.loadBundle(named: name, kind: .labelsCSV, provenance: MetadataProvenance(source: name, precedence: 0)).labels.map(\.value)
        if let index = labels.firstIndex(where: { LocationReference($0) == LocationReference(location) }) { labels[index] = location } else { labels.append(location) }
        try repository.saveLabels(labels.sorted { $0 < $1 }, named: name)
        return .fullDisassembly
    }

    @discardableResult
    public func upsertComment(_ comment: DisassemblyComment, fileIdentifier: String) throws -> MetadataInvalidationScope {
        let name = "comments_\(fileIdentifier)"
        var comments = try repository.loadBundle(named: name, kind: .commentsJSON, provenance: MetadataProvenance(source: name, precedence: 0)).comments.map(\.value)
        comments.removeAll { $0.reference == comment.reference }
        if !comment.comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { comments.append(comment) }
        try repository.saveComments(comments.sorted { ($0.segment, $0.procedure ?? -1, $0.addr) < ($1.segment, $1.procedure ?? -1, $1.addr) }, named: name)
        return .documentOnly
    }

    @discardableResult
    public func upsertProcedure(_ procedure: ProcedureIdentifier, metadataFileName: String) throws -> MetadataInvalidationScope {
        var procedures = try repository.loadBundle(named: metadataFileName, kind: .proceduresCSV, provenance: MetadataProvenance(source: metadataFileName, precedence: 0)).procedures.map(\.value)
        if let index = procedures.firstIndex(where: { $0.segment == procedure.segment && $0.procedure == procedure.procedure }) { procedures[index] = procedure } else { procedures.append(procedure) }
        try repository.saveProcedures(procedures, named: metadataFileName)
        return .procedureSignature(segment: procedure.segment, procedure: procedure.procedure)
    }
}

public struct FileBackedMetadataRepository: MetadataRepository {
    public let workspace: MetadataWorkspace
    public init(workspace: MetadataWorkspace = .applicationSupport()) { self.workspace = workspace }

    public func loadBundle(named name: String, kind: MetadataFileKind, provenance: MetadataProvenance) throws -> MetadataBundle {
        guard let url = readURL(named: name, kind: kind) else { return MetadataBundle() }
        let source = MetadataProvenance(source: url.lastPathComponent, precedence: provenance.precedence)
        switch kind {
        case .labelsCSV:
            let rows = try CSVTable(contentsOf: url).records.map(Location.init(csv:))
            return MetadataBundle(labels: rows.map { ProvenancedMetadataFact(value: $0, provenance: source) })
        case .proceduresCSV:
            let rows = try CSVTable(contentsOf: url).records.map(ProcedureIdentifier.init(csv:))
            return MetadataBundle(procedures: rows.map { ProvenancedMetadataFact(value: $0, provenance: source) })
        case .commentsJSON:
            let rows = try JSONDecoder().decode([DisassemblyComment].self, from: Data(contentsOf: url))
            return MetadataBundle(comments: rows.map { ProvenancedMetadataFact(value: $0, provenance: source) })
        }
    }

    public func saveLabels(_ labels: [Location], named name: String) throws { try MetadataStore(appSupportDirectory: workspace.writableDirectory).writeLabelsCSV(labels, to: name, overwrite: true) }
    public func saveProcedures(_ procedures: [ProcedureIdentifier], named name: String) throws { try MetadataStore(appSupportDirectory: workspace.writableDirectory).writeProceduresCSV(procedures, to: name, overwrite: true) }
    public func saveComments(_ comments: [DisassemblyComment], named name: String) throws { try MetadataStore(appSupportDirectory: workspace.writableDirectory).writeJSON(comments, to: name, overwrite: true) }

    private func readURL(named name: String, kind: MetadataFileKind) -> URL? {
        let ext = kind == .commentsJSON ? "json" : "csv"
        let writable = workspace.writableDirectory.appendingPathComponent(name).appendingPathExtension(ext)
        if FileManager.default.fileExists(atPath: writable.path) { return writable }
        if let bundled = workspace.bundledDirectory?.appendingPathComponent(name).appendingPathExtension(ext), FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        return nil
    }
}
