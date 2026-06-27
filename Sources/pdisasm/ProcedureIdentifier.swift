public class ProcedureIdentifier: CustomStringConvertible, Hashable, Codable {
    private static func normalizedParameter(_ parameter: Identifier) -> Identifier {
        let type = parameter.type.trimmingCharacters(in: .whitespacesAndNewlines)
        guard type == "POINTER" else { return parameter }
        return Identifier(
            name: parameter.name,
            type: "UNKNOWN",
            typeSource: .unknown,
            parameterMode: parameter.parameterMode,
            parameterModeSource: parameter.parameterModeSource
        )
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(segment)
        hasher.combine(procedure)
    }

    public static func == (lhs: ProcedureIdentifier, rhs: ProcedureIdentifier) -> Bool {
        return lhs.segment == rhs.segment && lhs.procedure == rhs.procedure
    }

    public init(
        isFunction: Bool,
        isAssembly: Bool = false,
        segment: Int,
        segmentName: String? = nil,
        procedure: Int,
        procName: String? = nil,
        parameters: [Identifier] = [],
        returnType: String? = nil,
        returnTypeSource: TypeSource? = nil
    ) {
        self.isFunction = isFunction
        self.isAssembly = isAssembly
        self.segment = segment
        self.segmentName = segmentName
        self.procedure = procedure
        self.procName = procName
        self.parameters = parameters.map(Self.normalizedParameter)
        self.returnTypeSource = .unknown
        if isFunction {
            self.returnType = returnType ?? "UNKNOWN"
            self.returnTypeSource = returnTypeSource ?? (self.returnType == "UNKNOWN" ? .unknown : .metadata)
        }
    }

    public var description: String {
        var s =
            (isFunction
                ? "FUNCTION "
                : "PROCEDURE ") + (segmentName ?? "SEG" + String(segment)) + "."
            + defaultedProcedureName
        let parameterDescriptions = signatureParameterDescriptions
        if !parameterDescriptions.isEmpty {
            s +=
                "(" + parameterDescriptions.joined(separator: "; ")
                + ")"
        }
        if isFunction {
            s += ": " + (returnType ?? "UNKNOWN")
        }
        return s
    }

    private var signatureParameterDescriptions: [String] {
        if parameterLocations.count == parameters.count {
            return parameterLocations.map(\.description)
        }
        return parameters.map(\.description)
    }
    public var shortDescription: String {
        var result = ""
        if segmentName == nil || segmentName!.isEmpty {
            result += "SEG" + String(segment)
        } else {
            result += segmentName!
        }
        result += "."
        result += defaultedProcedureName
        return result
    }

    private var defaultedProcedureName: String {
        if let procName, !procName.isEmpty {
            return procName
        }
        if procedure == 1, let segmentName, !segmentName.isEmpty {
            return segmentName
        }
        return (isFunction ? "FUNC" : "PROC") + String(procedure)
    }

    required public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.segment = try container.decode(
            Int.self,
            forKey: CodingKeys.segmentNumber
        )
        self.procedure = try container.decode(
            Int.self,
            forKey: CodingKeys.procNumber
        )
        self.segmentName = try container.decodeIfPresent(
            String.self,
            forKey: CodingKeys.segmentName
        )
        self.procName = try container.decodeIfPresent(
            String.self,
            forKey: CodingKeys.procName
        )
        let paramStr = try container.decode(
            String.self,
            forKey: CodingKeys.parameters
        )
        self.parameters = paramStr.split(separator: ";").map {
            let parts = $0.split(separator: ":", maxSplits: 1).map {
                String($0)
            }
            if parts.count == 2 {
                return Identifier(name: parts[0], type: parts[1])
            } else {
                return Identifier(name: parts[0], type: "")
            }
        }.map(Self.normalizedParameter)
        let modes = try container.decodeIfPresent(
            [ParameterMode].self,
            forKey: .parameterModes
        ) ?? []
        let modeSources = try container.decodeIfPresent(
            [ParameterModeSource].self,
            forKey: .parameterModeSources
        ) ?? []
        for index in self.parameters.indices {
            guard modes.indices.contains(index) else { continue }
            self.parameters[index].parameterMode = modes[index]
            self.parameters[index].parameterModeSource = modeSources.indices.contains(index)
                ? modeSources[index]
                : (modes[index] == .unknown ? .unknown : .metadata)
        }
        self.returnType = try container.decodeIfPresent(
            String.self,
            forKey: CodingKeys.returnType
        )
        if let rawReturnTypeSource = try container.decodeIfPresent(
            String.self,
            forKey: CodingKeys.returnTypeSource
        ), !rawReturnTypeSource.isEmpty {
            self.returnTypeSource = TypeSource(rawValue: rawReturnTypeSource) ?? .metadata
        } else {
            self.returnTypeSource = (self.returnType ?? "").isEmpty || self.returnType == "UNKNOWN" ? .unknown : .metadata
        }
        self.isAssembly = try container.decode(
            Bool.self,
            forKey: CodingKeys.isAssembly
        )
        self.isFunction = try container.decode(
            Bool.self,
            forKey: CodingKeys.isFunction
        )
        if !self.isFunction {
            self.returnType = nil
            self.returnTypeSource = .unknown
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.segment, forKey: CodingKeys.segmentNumber)
        try container.encode(self.procedure, forKey: CodingKeys.procNumber)
        try container.encode(self.segmentName, forKey: CodingKeys.segmentName)
        try container.encode(self.procName, forKey: CodingKeys.procName)
        try container.encode(
            self.signatureParameterDescriptions.joined(separator: ";"),
            forKey: CodingKeys.parameters
        )
        try container.encode(parameters.map(\.parameterMode), forKey: .parameterModes)
        try container.encode(parameters.map(\.parameterModeSource), forKey: .parameterModeSources)
        try container.encode(self.returnType, forKey: CodingKeys.returnType)
        try container.encode(self.returnTypeSource.rawValue, forKey: CodingKeys.returnTypeSource)
        try container.encode(self.isAssembly, forKey: CodingKeys.isAssembly)
        try container.encode(self.isFunction, forKey: CodingKeys.isFunction)
    }
    enum CodingKeys: String, CodingKey {
        case segmentNumber = "segmentNumber"
        case procNumber = "procNumber"
        case segmentName = "segmentName"
        case procName = "procName"
        case parameters = "parameters"
        case parameterModes
        case parameterModeSources
        case returnType = "returnType"
        case returnTypeSource = "returnTypeSource"
        case isAssembly = "isAssembly"
        case isFunction = "isFunction"

    }
    public var isFunction: Bool
    public var isAssembly: Bool = false
    public var segment: Int
    public var segmentName: String?
    public var procedure: Int
    public var procName: String?
    public var parameters: [Identifier] = []
    var signatureSlots: [ProcedureSignatureSlot] = []
    public var functionResultStorage: FunctionResultStorage? {
        guard isFunction else { return nil }
        return FunctionResultStorage(
            returnType: returnType,
            baseLocation: returnLocation
        )
    }
    public var returnLocation: Location? {
        get {
            signatureSlots.first {
                if case .returnValue = $0.kind {
                    return true
                }
                return false
            }?.location
        }
        set {
            signatureSlots.removeAll {
                if case .returnValue = $0.kind {
                    return true
                }
                return false
            }
            if let newValue {
                signatureSlots.append(ProcedureSignatureSlot(
                    kind: .returnValue,
                    location: newValue
                ))
                sortSignatureSlots()
            }
        }
    }
    public var parameterLocations: [Location] {
        get {
            signatureSlots.compactMap { slot -> (Int, Location)? in
                guard let index = slot.kind.parameterIndex else { return nil }
                return (index, slot.location)
            }
            .sorted { $0.0 < $1.0 }
            .map(\.1)
        }
        set {
            signatureSlots.removeAll { $0.kind.isParameter }
            signatureSlots.append(contentsOf: newValue.enumerated().map {
                ProcedureSignatureSlot(kind: .parameter($0.offset), location: $0.element)
            })
            sortSignatureSlots()
        }
    }
    public var returnType: String?
    public var returnTypeSource: TypeSource = .unknown

    private func sortSignatureSlots() {
        signatureSlots.sort { $0.kind.sortOrder < $1.kind.sortOrder }
    }

    @discardableResult
    public func assignReturnType(
        _ proposedType: String,
        source proposedSource: TypeSource,
        location: Location,
        evidence: String
    ) -> TypeConflict? {
        guard isFunction else { return nil }
        let newType = proposedType.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newType.isEmpty && newType != "UNKNOWN" else { return nil }

        let currentType = (returnType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if currentType.isEmpty || currentType == "UNKNOWN" {
            returnType = newType
            returnTypeSource = proposedSource
            return nil
        }

        if currentType == newType {
            if proposedSource.precedence > returnTypeSource.precedence {
                returnTypeSource = proposedSource
            }
            return nil
        }

        let conflict = TypeConflict(
            location: location,
            existingType: currentType,
            existingSource: returnTypeSource,
            proposedType: newType,
            proposedSource: proposedSource,
            evidence: evidence
        )

        if proposedSource.precedence > returnTypeSource.precedence {
            returnType = newType
            returnTypeSource = proposedSource
        }

        return conflict
    }

    @discardableResult
    public func assignParameterType(
        at index: Int,
        _ proposedType: String,
        source proposedSource: TypeSource,
        location: Location,
        evidence: String
    ) -> TypeConflict? {
        guard parameters.indices.contains(index) else { return nil }
        guard proposedType.trimmingCharacters(in: .whitespacesAndNewlines) != "POINTER" else {
            return nil
        }
        if let conflict = parameters[index].assignType(proposedType, source: proposedSource) {
            return TypeConflict(
                location: location,
                existingType: conflict.existingType,
                existingSource: conflict.existingSource,
                proposedType: conflict.proposedType,
                proposedSource: conflict.proposedSource,
                evidence: evidence
            )
        }
        return nil
    }
}
