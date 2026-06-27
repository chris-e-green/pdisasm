public class Instruction {
    public var opcode: UInt8
    public var mnemonic: String
    public var params: [Int] = []
    public var stringParameter: String?
    public var comparatorDataType: String
    public var memLocation: Location?
    public var destination: Location?
    public var comment: String?
    public var userComment: String?
    public var isPascal: Bool = true
    public var stackState: [String]?
    public var prePseudoCode: [String]  // pseudo-code to print before instruction
    public var forLoopEvidence: ForLoopEvidence?
    public var caseDispatchEvidence: CaseDispatchEvidence?
    var pseudoCodeStatement: PseudoCodeStatement?
    public var pseudoCode: String?  // pseudo-code to print after instruction

    public init(
        opcode: UInt8,
        mnemonic: String,
        params: [Int] = [],
        stringParameter: String? = nil,
        comparatorDataType: String = "",
        memLocation: Location? = nil,
        destination: Location? = nil,
        comment: String? = nil,
        userComment: String? = nil,
        isPascal: Bool = true,
        stackState: [String]? = nil,
        pseudoCode: String? = nil,
        prePseudoCode: [String] = [],
        forLoopEvidence: ForLoopEvidence? = nil,
        caseDispatchEvidence: CaseDispatchEvidence? = nil
    ) {
        self.opcode = opcode
        self.mnemonic = mnemonic
        self.params = params
        self.stringParameter = stringParameter
        self.comparatorDataType = comparatorDataType
        self.memLocation = memLocation
        self.destination = destination
        self.comment = comment
        self.userComment = userComment
        self.isPascal = isPascal
        self.stackState = stackState
        self.pseudoCodeStatement = pseudoCode.map {
            PseudoCodeStatement(renderedText: $0, locations: [])
        }
        self.pseudoCode = pseudoCode
        self.prePseudoCode = prePseudoCode
        self.forLoopEvidence = forLoopEvidence
        self.caseDispatchEvidence = caseDispatchEvidence
    }
}

public struct CaseDispatchEvidence: Hashable, Sendable {
    public let selectorExpression: String
    public let gatewayAddress: Int

    public init(selectorExpression: String, gatewayAddress: Int) {
        self.selectorExpression = selectorExpression
        self.gatewayAddress = gatewayAddress
    }
}

public struct ForLoopEvidence: Hashable, Sendable {
    public let direction: StructuredForDirection
    public let variable: StructuredForVariable
    public let startExpression: String
    public let limitExpression: String
    public let initializationStoreAddress: Int
    public let setupAddresses: Set<Int>
    public let updateStoreAddress: Int

    public init(
        direction: StructuredForDirection,
        variable: StructuredForVariable,
        startExpression: String,
        limitExpression: String,
        initializationStoreAddress: Int,
        setupAddresses: Set<Int>,
        updateStoreAddress: Int
    ) {
        self.direction = direction
        self.variable = variable
        self.startExpression = startExpression
        self.limitExpression = limitExpression
        self.initializationStoreAddress = initializationStoreAddress
        self.setupAddresses = setupAddresses
        self.updateStoreAddress = updateStoreAddress
    }
}
