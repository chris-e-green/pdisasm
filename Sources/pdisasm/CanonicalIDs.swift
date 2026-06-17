import Foundation

public struct CodeFileID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let value: String
    public init(_ value: String) { self.value = value }
    public var description: String { value }
}

public struct SegmentID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let codeFile: CodeFileID
    public let number: Int
    public init(codeFile: CodeFileID, number: Int) {
        self.codeFile = codeFile
        self.number = number
    }
    public var description: String { "\(codeFile):\(number)" }
}

public struct ProcedureID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let segment: SegmentID
    public let number: Int
    public init(segment: SegmentID, number: Int) {
        self.segment = segment
        self.number = number
    }
    public var description: String { "\(segment).\(number)" }
}

public struct InstructionID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let procedure: ProcedureID
    public let offset: Int
    public init(procedure: ProcedureID, offset: Int) {
        self.procedure = procedure
        self.offset = offset
    }
    public var description: String { "\(procedure)@\(offset)" }
}

public struct LocationID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let segment: SegmentID
    public let procedure: ProcedureID?
    public let lexicalLevel: Int?
    public let address: Int?
    public init(segment: SegmentID, procedure: ProcedureID? = nil, lexicalLevel: Int? = nil, address: Int? = nil) {
        self.segment = segment
        self.procedure = procedure
        self.lexicalLevel = lexicalLevel
        self.address = address
    }
    public var description: String {
        ["segment=\(segment)", procedure.map { "procedure=\($0)" }, lexicalLevel.map { "lexicalLevel=\($0)" }, address.map { "address=\($0)" }]
            .compactMap { $0 }
            .joined(separator: ",")
    }
}

public struct CallEdgeID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let origin: InstructionID
    public let target: ProcedureID
    public init(origin: InstructionID, target: ProcedureID) {
        self.origin = origin
        self.target = target
    }
    public var description: String { "\(origin)->\(target)" }
}

public struct MetadataFactID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let value: String
    public init(_ value: String) { self.value = value }
    public var description: String { value }
}

public struct DocumentID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let value: String
    public init(_ value: String) { self.value = value }
    public var description: String { value }
}

public struct DocumentNodeID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let document: DocumentID
    public let value: String
    public init(document: DocumentID, value: String) {
        self.document = document
        self.value = value
    }
    public var description: String { "\(document)#\(value)" }
}

public extension CodeFileID {
    init(fileURL: URL) {
        self.init(fileURL.deletingPathExtension().lastPathComponent)
    }
}

public extension SegmentID {
    init(codeFile: CodeFileID, legacySegmentNumber: Int) {
        self.init(codeFile: codeFile, number: legacySegmentNumber)
    }
}

public extension ProcedureID {
    init(codeFile: CodeFileID, legacy identifier: ProcedureIdentifier) {
        self.init(segment: SegmentID(codeFile: codeFile, number: identifier.segment), number: identifier.procedure)
    }
}

public extension InstructionID {
    init?(codeFile: CodeFileID, legacy reference: InstructionReference) {
        guard let procedureNumber = reference.procedure else { return nil }
        self.init(
            procedure: ProcedureID(segment: SegmentID(codeFile: codeFile, number: reference.segment), number: procedureNumber),
            offset: reference.addr
        )
    }
}

public extension LocationID {
    init(codeFile: CodeFileID, legacy location: Location) {
        let segmentID = SegmentID(codeFile: codeFile, number: location.segment)
        let procedureID = location.procedure.map { ProcedureID(segment: segmentID, number: $0) }
        self.init(segment: segmentID, procedure: procedureID, lexicalLevel: location.lexLevel, address: location.addr)
    }

    init(codeFile: CodeFileID, legacy reference: LocationReference) {
        let segmentID = SegmentID(codeFile: codeFile, number: reference.segment)
        let procedureID = reference.procedure.map { ProcedureID(segment: segmentID, number: $0) }
        self.init(segment: segmentID, procedure: procedureID, lexicalLevel: reference.lexLevel, address: reference.addr)
    }
}
