import Foundation

public struct InstructionReference: Hashable, Sendable, Codable {
    public let segment: Int
    public let procedure: Int?
    public let addr: Int

    public init(segment: Int, procedure: Int?, addr: Int) {
        self.segment = segment
        self.procedure = procedure
        self.addr = addr
    }
}

public struct DisassemblyComment: Hashable, Sendable, Codable {
    public let segment: Int
    public let procedure: Int?
    public let addr: Int
    public var comment: String

    public var reference: InstructionReference {
        InstructionReference(segment: segment, procedure: procedure, addr: addr)
    }

    public init(segment: Int, procedure: Int?, addr: Int, comment: String) {
        self.segment = segment
        self.procedure = procedure
        self.addr = addr
        self.comment = comment
    }

    public init(reference: InstructionReference, comment: String) {
        self.segment = reference.segment
        self.procedure = reference.procedure
        self.addr = reference.addr
        self.comment = comment
    }
}
