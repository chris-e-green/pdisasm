import Foundation

public enum FunctionResultRepresentation: String, Sendable {
    case unknown
    case scalar
    case real
    case aggregate
}

public struct FunctionResultStorage {
    public let baseAddress: Int
    public let reservedWordCount: Int
    public let valueWordCount: Int?
    public let representation: FunctionResultRepresentation
    public let baseLocation: Location?

    public var nextParameterAddress: Int {
        baseAddress + reservedWordCount
    }

    init(returnType: String?, baseLocation: Location?) {
        self.baseAddress = 1
        self.reservedWordCount = 2
        self.baseLocation = baseLocation

        let type = returnType?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased() ?? ""
        switch type {
        case "", "UNKNOWN":
            self.representation = .unknown
            self.valueWordCount = nil
        case "REAL":
            self.representation = .real
            self.valueWordCount = 2
        case "STRING", "TEXT":
            self.representation = .aggregate
            self.valueWordCount = nil
        case "BOOLEAN", "BYTE", "CHAR", "INTEGER", "LONGINT", "WORD":
            self.representation = .scalar
            self.valueWordCount = 1
        default:
            if type.hasPrefix("^") {
                self.representation = .scalar
                self.valueWordCount = 1
            } else if type.hasPrefix("ARRAY")
                || type.hasPrefix("PACKED ARRAY")
                || type.hasPrefix("SET OF ")
                || type.hasPrefix("FILE OF ")
            {
                self.representation = .aggregate
                self.valueWordCount = nil
            } else {
                self.representation = .unknown
                self.valueWordCount = nil
            }
        }
    }
}

enum ProcedureSignatureSlotKind {
    case returnValue
    case parameter(Int)

    var sortOrder: Int {
        switch self {
        case .returnValue:
            return -1
        case let .parameter(index):
            return index
        }
    }

    var parameterIndex: Int? {
        switch self {
        case .returnValue:
            return nil
        case let .parameter(index):
            return index
        }
    }

    var isParameter: Bool {
        parameterIndex != nil
    }
}

struct ProcedureSignatureSlot {
    var kind: ProcedureSignatureSlotKind
    var location: Location
}
