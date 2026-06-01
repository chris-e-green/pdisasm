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
