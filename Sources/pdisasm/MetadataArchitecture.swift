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

public struct MetadataTypeAlias: Hashable, Codable, Sendable {
    public let name: String
    public let type: String
    public init(name: String, type: String) {
        self.name = name
        self.type = type
    }
}

public struct MetadataConstant: Hashable, Codable, Sendable {
    public let name: String
    public let value: Int
    public init(name: String, value: Int) {
        self.name = name
        self.value = value
    }
}

public struct MetadataGlobal: Hashable, Codable, Sendable {
    public let address: Int
    public let identifier: Identifier
    public init(address: Int, identifier: Identifier) {
        self.address = address
        self.identifier = identifier
    }
}

public struct MetadataBundle: Hashable, Codable, @unchecked Sendable {
    public var labels: [ProvenancedMetadataFact<Location>]
    public var procedures: [ProvenancedMetadataFact<ProcedureIdentifier>]
    public var comments: [ProvenancedMetadataFact<DisassemblyComment>]
    public var records: [ProvenancedMetadataFact<PascalRecord>]
    public var typeAliases: [ProvenancedMetadataFact<MetadataTypeAlias>]
    public var scalarTypes: [ProvenancedMetadataFact<PascalScalarType>]
    public var constants: [ProvenancedMetadataFact<MetadataConstant>]
    public var subrangeTypes: [ProvenancedMetadataFact<PascalSubrangeType>]
    public var globals: [ProvenancedMetadataFact<MetadataGlobal>]

    public init(
        labels: [ProvenancedMetadataFact<Location>] = [],
        procedures: [ProvenancedMetadataFact<ProcedureIdentifier>] = [],
        comments: [ProvenancedMetadataFact<DisassemblyComment>] = [],
        records: [ProvenancedMetadataFact<PascalRecord>] = [],
        typeAliases: [ProvenancedMetadataFact<MetadataTypeAlias>] = [],
        scalarTypes: [ProvenancedMetadataFact<PascalScalarType>] = [],
        constants: [ProvenancedMetadataFact<MetadataConstant>] = [],
        subrangeTypes: [ProvenancedMetadataFact<PascalSubrangeType>] = [],
        globals: [ProvenancedMetadataFact<MetadataGlobal>] = []
    ) {
        self.labels = labels
        self.procedures = procedures
        self.comments = comments
        self.records = records
        self.typeAliases = typeAliases
        self.scalarTypes = scalarTypes
        self.constants = constants
        self.subrangeTypes = subrangeTypes
        self.globals = globals
    }
}

public struct MetadataSnapshot: Hashable, Codable, @unchecked Sendable {
    public var labels: [ProvenancedMetadataFact<Location>]
    public var procedures: [ProvenancedMetadataFact<ProcedureIdentifier>]
    public var comments: [ProvenancedMetadataFact<DisassemblyComment>]
    public var records: [ProvenancedMetadataFact<PascalRecord>]
    public var typeAliases: [ProvenancedMetadataFact<MetadataTypeAlias>]
    public var scalarTypes: [ProvenancedMetadataFact<PascalScalarType>]
    public var constants: [ProvenancedMetadataFact<MetadataConstant>]
    public var subrangeTypes: [ProvenancedMetadataFact<PascalSubrangeType>]
    public var globals: [ProvenancedMetadataFact<MetadataGlobal>]

    public init(
        labels: [ProvenancedMetadataFact<Location>] = [],
        procedures: [ProvenancedMetadataFact<ProcedureIdentifier>] = [],
        comments: [ProvenancedMetadataFact<DisassemblyComment>] = [],
        records: [ProvenancedMetadataFact<PascalRecord>] = [],
        typeAliases: [ProvenancedMetadataFact<MetadataTypeAlias>] = [],
        scalarTypes: [ProvenancedMetadataFact<PascalScalarType>] = [],
        constants: [ProvenancedMetadataFact<MetadataConstant>] = [],
        subrangeTypes: [ProvenancedMetadataFact<PascalSubrangeType>] = [],
        globals: [ProvenancedMetadataFact<MetadataGlobal>] = []
    ) {
        self.labels = labels
        self.procedures = procedures
        self.comments = comments
        self.records = records
        self.typeAliases = typeAliases
        self.scalarTypes = scalarTypes
        self.constants = constants
        self.subrangeTypes = subrangeTypes
        self.globals = globals
    }

    public init(merging bundles: [MetadataBundle]) {
        var labels: [LocationReference: ProvenancedMetadataFact<Location>] = [:]
        var procedures: [ProcedureKey: ProvenancedMetadataFact<ProcedureIdentifier>] = [:]
        var comments: [InstructionReference: ProvenancedMetadataFact<DisassemblyComment>] = [:]
        var records: [String: ProvenancedMetadataFact<PascalRecord>] = [:]
        var typeAliases: [String: ProvenancedMetadataFact<MetadataTypeAlias>] = [:]
        var scalarTypes: [String: ProvenancedMetadataFact<PascalScalarType>] = [:]
        var constants: [String: ProvenancedMetadataFact<MetadataConstant>] = [:]
        var subrangeTypes: [String: ProvenancedMetadataFact<PascalSubrangeType>] = [:]
        var globals: [Int: ProvenancedMetadataFact<MetadataGlobal>] = [:]
        for bundle in bundles {
            for fact in bundle.labels { labels.mergeKeepingHighestPrecedence(fact, key: LocationReference(fact.value)) }
            for fact in bundle.procedures { procedures.mergeKeepingHighestPrecedence(fact, key: ProcedureKey(fact.value)) }
            for fact in bundle.comments { comments.mergeKeepingHighestPrecedence(fact, key: fact.value.reference) }
            for fact in bundle.records { records.mergeKeepingHighestPrecedence(fact, key: fact.value.name) }
            for fact in bundle.typeAliases { typeAliases.mergeKeepingHighestPrecedence(fact, key: fact.value.name) }
            for fact in bundle.scalarTypes { scalarTypes.mergeKeepingHighestPrecedence(fact, key: fact.value.name) }
            for fact in bundle.constants { constants.mergeKeepingHighestPrecedence(fact, key: fact.value.name) }
            for fact in bundle.subrangeTypes { subrangeTypes.mergeKeepingHighestPrecedence(fact, key: fact.value.name) }
            for fact in bundle.globals { globals.mergeKeepingHighestPrecedence(fact, key: fact.value.address) }
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
        self.records = records.values.sorted { $0.value.name < $1.value.name }
        self.typeAliases = typeAliases.values.sorted { $0.value.name < $1.value.name }
        self.scalarTypes = scalarTypes.values.sorted { $0.value.name < $1.value.name }
        self.constants = constants.values.sorted { $0.value.name < $1.value.name }
        self.subrangeTypes = subrangeTypes.values.sorted { $0.value.name < $1.value.name }
        self.globals = globals.values.sorted { $0.value.address < $1.value.address }
    }

    public var bundle: MetadataBundle {
        MetadataBundle(
            labels: labels,
            procedures: procedures,
            comments: comments,
            records: records,
            typeAliases: typeAliases,
            scalarTypes: scalarTypes,
            constants: constants,
            subrangeTypes: subrangeTypes,
            globals: globals
        )
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

public enum MetadataFileKind: Hashable, Sendable {
    case labelsCSV, proceduresCSV, commentsJSON, recordsJSON, typesPascal, globalsJSON
}

public enum MetadataEditCommand: Hashable, Sendable {
    case upsertLabel(LocationID, name: String, type: String?)
    case renameProcedure(ProcedureID, name: String)
    case upsertParameter(ProcedureID, index: Int, name: String, type: String?)
    case upsertReturnType(ProcedureID, type: String?)
    case upsertComment(InstructionID, text: String?)
}

public struct MetadataEditContext: @unchecked Sendable {
    public let codeFileID: CodeFileID
    public let fileIdentifier: String
    public let systemMetadataVersion: Int?
    public let systemSegments: Set<Int>
    public let snapshot: ProgramSnapshot?
    public let proceduresByID: [ProcedureID: ProcedureIdentifier]

    public init(
        codeFileID: CodeFileID,
        fileIdentifier: String? = nil,
        systemMetadataVersion: Int? = nil,
        systemSegments: Set<Int> = [0, 2, 3, 4, 5, 6, 20, 21, 22, 28, 29, 30, 31],
        snapshot: ProgramSnapshot? = nil,
        procedures: [ProcedureIdentifier] = []
    ) {
        self.codeFileID = codeFileID
        self.fileIdentifier = fileIdentifier ?? codeFileID.value
        self.systemMetadataVersion = systemMetadataVersion
        self.systemSegments = systemSegments
        self.snapshot = snapshot
        self.proceduresByID = Dictionary(uniqueKeysWithValues: procedures.map { (ProcedureID(codeFile: codeFileID, legacy: $0), $0) })
    }
}

public struct MetadataEditResult: Hashable, Sendable {
    public let diagnostics: [Diagnostic]
    public let invalidation: MetadataInvalidationScope

    public init(diagnostics: [Diagnostic] = [], invalidation: MetadataInvalidationScope) {
        self.diagnostics = diagnostics
        self.invalidation = invalidation
    }
}

public enum MetadataInvalidationScope: Hashable, Sendable {
    case none
    case documentOnly
    case patchDocument([DocumentNodeID])
    case procedureSignature(segment: Int, procedure: Int)
    case propagateCallGraph(Set<ProcedureID>)
    case fullDisassembly
}

public enum ProcedureSignatureEditField: Hashable, Sendable { case procedureName, parameter(Int), returnType }

public struct MetadataEditingService: Sendable {
    public let repository: MetadataRepository
    public init(repository: MetadataRepository) { self.repository = repository }

    @discardableResult
    public func apply(_ command: MetadataEditCommand, context: MetadataEditContext) throws -> MetadataEditResult {
        let diagnostics = validate(command, context: context)
        let hasErrors = diagnostics.contains { $0.severity == .error }
        guard !hasErrors else { return MetadataEditResult(diagnostics: diagnostics, invalidation: .none) }

        switch command {
        case let .upsertLabel(id, name, type):
            let trimmedType = type?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let location = Location(
                segment: id.segment.number,
                procedure: id.procedure?.number,
                lexLevel: id.lexicalLevel,
                addr: id.address,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                type: trimmedType,
                typeSource: trimmedType.isEmpty ? .unknown : .user
            )
            let invalidation = try upsertLabel(location, fileIdentifier: context.fileIdentifier)
            return MetadataEditResult(diagnostics: diagnostics, invalidation: invalidation)
        case let .upsertComment(id, text):
            let comment = DisassemblyComment(
                reference: InstructionReference(segment: id.procedure.segment.number, procedure: id.procedure.number, addr: id.offset),
                comment: text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            )
            let invalidation = try upsertComment(comment, fileIdentifier: context.fileIdentifier)
            return MetadataEditResult(diagnostics: diagnostics, invalidation: invalidation)
        case let .renameProcedure(id, name):
            let procedure = try editableProcedure(for: id, context: context)
            procedure.procName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return try saveProcedure(procedure, id: id, context: context, diagnostics: diagnostics)
        case let .upsertParameter(id, index, name, type):
            let procedure = try editableProcedure(for: id, context: context)
            guard procedure.parameters.indices.contains(index) else {
                return MetadataEditResult(diagnostics: diagnostics + [Diagnostic(severity: .error, message: "Parameter index \(index) does not exist on procedure \(id).")], invalidation: .none)
            }
            let trimmedType = type?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            procedure.parameters[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            procedure.parameters[index].type = trimmedType == "POINTER" ? "" : trimmedType
            procedure.parameters[index].typeSource = procedure.parameters[index].type.isEmpty ? .unknown : .user
            return try saveProcedure(procedure, id: id, context: context, diagnostics: diagnostics)
        case let .upsertReturnType(id, type):
            let procedure = try editableProcedure(for: id, context: context)
            guard procedure.isFunction else {
                return MetadataEditResult(diagnostics: diagnostics + [Diagnostic(severity: .error, message: "Procedure \(id) is not a function.")], invalidation: .none)
            }
            let trimmedType = type?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            procedure.returnType = trimmedType
            procedure.returnTypeSource = trimmedType.isEmpty ? .unknown : .user
            return try saveProcedure(procedure, id: id, context: context, diagnostics: diagnostics)
        }
    }

    @discardableResult
    public func upsertLabel(_ location: Location, fileIdentifier: String) throws -> MetadataInvalidationScope {
        let name = "labels_\(fileIdentifier)"
        var labels = try repository.loadBundle(named: name, kind: .labelsCSV, provenance: MetadataProvenance(source: name, precedence: 0)).labels.map(\.value)
        if let index = labels.firstIndex(where: { LocationReference($0) == LocationReference(location) }) { labels[index] = location } else { labels.append(location) }
        try repository.saveLabels(labels.sorted { $0 < $1 }, named: name)
        return location.type.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || location.typeSource == .unknown
            ? .documentOnly
            : .fullDisassembly
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

    public func invalidationForProcedureEdit(_ procedure: ProcedureIdentifier, in snapshot: ProgramSnapshot?) -> MetadataInvalidationScope {
        let changedProcedure = ProcedureID(
            segment: SegmentID(codeFile: snapshot?.codeFileID ?? CodeFileID("metadata"), number: procedure.segment),
            number: procedure.procedure
        )
        guard let snapshot else { return .procedureSignature(segment: procedure.segment, procedure: procedure.procedure) }
        let dependents = snapshot.dependentProcedureScope(for: changedProcedure)
        return dependents.isEmpty ? .procedureSignature(segment: procedure.segment, procedure: procedure.procedure) : .propagateCallGraph(dependents)
    }

    private func validate(_ command: MetadataEditCommand, context: MetadataEditContext) -> [Diagnostic] {
        guard let snapshot = context.snapshot else { return [] }
        switch command {
        case let .upsertLabel(id, name, _):
            var diagnostics: [Diagnostic] = []
            if snapshot.locations[id] == nil {
                diagnostics.append(Diagnostic(severity: .warning, message: "Location \(id) is not present in the current snapshot; metadata will be saved for the next run."))
            }
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                diagnostics.append(Diagnostic(severity: .error, message: "Label name cannot be empty."))
            }
            return diagnostics
        case let .upsertComment(id, _):
            return snapshot.instructions[id] == nil
                ? [Diagnostic(severity: .warning, message: "Instruction \(id) is not present in the current snapshot; metadata will be saved for the next run.")]
                : []
        case let .renameProcedure(id, name):
            var diagnostics = snapshot.procedures[id] == nil
                ? [Diagnostic(severity: .warning, message: "Procedure \(id) is not present in the current snapshot; metadata will be saved for the next run.")]
                : []
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                diagnostics.append(Diagnostic(severity: .error, message: "Procedure name cannot be empty."))
            }
            return diagnostics
        case let .upsertParameter(id, _, name, _):
            var diagnostics = snapshot.procedures[id] == nil
                ? [Diagnostic(severity: .warning, message: "Procedure \(id) is not present in the current snapshot; metadata will be saved for the next run.")]
                : []
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                diagnostics.append(Diagnostic(severity: .error, message: "Parameter name cannot be empty."))
            }
            return diagnostics
        case let .upsertReturnType(id, _):
            return snapshot.procedures[id] == nil
                ? [Diagnostic(severity: .warning, message: "Procedure \(id) is not present in the current snapshot; metadata will be saved for the next run.")]
                : []
        }
    }

    private func editableProcedure(for id: ProcedureID, context: MetadataEditContext) throws -> ProcedureIdentifier {
        let metadataName = procedureMetadataName(for: id, context: context)
        let procedures = try repository.loadBundle(named: metadataName, kind: .proceduresCSV, provenance: MetadataProvenance(source: metadataName, precedence: 0)).procedures.map(\.value)
        if let existing = procedures.first(where: { $0.segment == id.segment.number && $0.procedure == id.number }) {
            return ProcedureIdentifier(isFunction: existing.isFunction, isAssembly: existing.isAssembly, segment: existing.segment, segmentName: existing.segmentName, procedure: existing.procedure, procName: existing.procName, parameters: existing.parameters, returnType: existing.returnType, returnTypeSource: existing.returnTypeSource)
        }
        if let current = context.proceduresByID[id] {
            return ProcedureIdentifier(isFunction: current.isFunction, isAssembly: current.isAssembly, segment: current.segment, segmentName: current.segmentName, procedure: current.procedure, procName: current.procName, parameters: current.parameters, returnType: current.returnType, returnTypeSource: current.returnTypeSource)
        }
        let snapshotProcedure = context.snapshot?.procedures[id]
        return ProcedureIdentifier(isFunction: snapshotProcedure?.isFunction ?? false, isAssembly: snapshotProcedure?.isAssembly ?? false, segment: id.segment.number, procedure: id.number, procName: snapshotProcedure?.name)
    }

    private func saveProcedure(_ procedure: ProcedureIdentifier, id: ProcedureID, context: MetadataEditContext, diagnostics: [Diagnostic]) throws -> MetadataEditResult {
        let invalidation = try upsertProcedure(procedure, metadataFileName: procedureMetadataName(for: id, context: context))
        let scopedInvalidation = invalidationForProcedureEdit(procedure, in: context.snapshot)
        return MetadataEditResult(diagnostics: diagnostics, invalidation: scopedInvalidation == .procedureSignature(segment: procedure.segment, procedure: procedure.procedure) ? invalidation : scopedInvalidation)
    }

    private func procedureMetadataName(for id: ProcedureID, context: MetadataEditContext) -> String {
        if context.systemSegments.contains(id.segment.number), let version = context.systemMetadataVersion {
            return "procedures_ver_\(version)"
        }
        return "procedures_\(context.fileIdentifier)"
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
        case .recordsJSON:
            let rows = try JSONDecoder().decode([PascalRecord].self, from: Data(contentsOf: url))
            return MetadataBundle(records: rows.map { ProvenancedMetadataFact(value: $0, provenance: source) })
        case .typesPascal:
            let definitions = PascalTypeDefinitionParser.parse(try String(contentsOf: url, encoding: .utf8), isSystemRecord: name.hasPrefix("types_ver_"))
            return MetadataBundle(
                records: definitions.records.map { ProvenancedMetadataFact(value: $0, provenance: source) },
                typeAliases: definitions.aliases.map { ProvenancedMetadataFact(value: MetadataTypeAlias(name: $0.key, type: $0.value), provenance: source) },
                scalarTypes: definitions.scalarTypes.map { ProvenancedMetadataFact(value: $0.value, provenance: source) },
                constants: definitions.constants.map { ProvenancedMetadataFact(value: MetadataConstant(name: $0.key, value: $0.value), provenance: source) },
                subrangeTypes: definitions.subrangeTypes.map { ProvenancedMetadataFact(value: $0.value, provenance: source) }
            )
        case .globalsJSON:
            let rows = try JSONDecoder().decode([Int: Identifier].self, from: Data(contentsOf: url))
            return MetadataBundle(globals: rows.map { ProvenancedMetadataFact(value: MetadataGlobal(address: $0.key, identifier: $0.value), provenance: source) })
        }
    }

    public func saveLabels(_ labels: [Location], named name: String) throws { try MetadataStore(appSupportDirectory: workspace.writableDirectory).writeLabelsCSV(labels, to: name, overwrite: true) }
    public func saveProcedures(_ procedures: [ProcedureIdentifier], named name: String) throws { try MetadataStore(appSupportDirectory: workspace.writableDirectory).writeProceduresCSV(procedures, to: name, overwrite: true) }
    public func saveComments(_ comments: [DisassemblyComment], named name: String) throws { try MetadataStore(appSupportDirectory: workspace.writableDirectory).writeJSON(comments, to: name, overwrite: true) }

    private func readURL(named name: String, kind: MetadataFileKind) -> URL? {
        let ext: String
        switch kind {
        case .commentsJSON, .recordsJSON, .globalsJSON: ext = "json"
        case .typesPascal: ext = "pas"
        case .labelsCSV, .proceduresCSV: ext = "csv"
        }
        let writable = workspace.writableDirectory.appendingPathComponent(name).appendingPathExtension(ext)
        if FileManager.default.fileExists(atPath: writable.path) { return writable }
        if let bundled = workspace.bundledDirectory?.appendingPathComponent(name).appendingPathExtension(ext), FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        return nil
    }
}

public struct InMemoryMetadataRepository: MetadataRepository, @unchecked Sendable {
    public var bundles: [MetadataRepositoryKey: MetadataBundle]
    public init(bundles: [MetadataRepositoryKey: MetadataBundle] = [:]) {
        self.bundles = bundles
    }

    public func loadBundle(named name: String, kind: MetadataFileKind, provenance: MetadataProvenance) throws -> MetadataBundle {
        bundles[MetadataRepositoryKey(name: name, kind: kind)] ?? MetadataBundle()
    }

    public func saveLabels(_ labels: [Location], named name: String) throws {}
    public func saveProcedures(_ procedures: [ProcedureIdentifier], named name: String) throws {}
    public func saveComments(_ comments: [DisassemblyComment], named name: String) throws {}
}

public struct MetadataRepositoryKey: Hashable, Sendable {
    public let name: String
    public let kind: MetadataFileKind
    public init(name: String, kind: MetadataFileKind) {
        self.name = name
        self.kind = kind
    }
}

public struct MetadataScopeResolver: Sendable {
    public let repository: MetadataRepository
    public init(repository: MetadataRepository) { self.repository = repository }

    public func resolve(fileIdentifier: String, version: Int) throws -> MetadataSnapshot {
        let scopes: [(String, MetadataFileKind, Int)] = [
            ("records_ver_\(version)", .recordsJSON, 0),
            ("types_ver_\(version)", .typesPascal, 0),
            ("globals_ver_\(version)", .globalsJSON, 0),
            ("labels_ver_\(version)", .labelsCSV, 0),
            ("procedures_ver_\(version)", .proceduresCSV, 0),
            ("records_\(fileIdentifier)", .recordsJSON, 10),
            ("types_\(fileIdentifier)", .typesPascal, 10),
            ("labels_\(fileIdentifier)", .labelsCSV, 10),
            ("procedures_\(fileIdentifier)", .proceduresCSV, 10),
            ("comments_\(fileIdentifier)", .commentsJSON, 10),
        ]
        let bundles = try scopes.map { name, kind, precedence in
            try repository.loadBundle(named: name, kind: kind, provenance: MetadataProvenance(source: name, precedence: precedence))
        }
        return MetadataSnapshot(merging: bundles)
    }
}
