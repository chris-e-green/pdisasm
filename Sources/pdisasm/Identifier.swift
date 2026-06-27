public enum ParameterMode: String, Codable, Sendable {
    case unknown
    case value
    case variable
}

public enum ParameterModeSource: String, Codable, Sendable {
    case unknown
    case inferred
    case metadata
    case user

    var precedence: Int {
        switch self {
        case .unknown: return 0
        case .inferred: return 1
        case .metadata: return 2
        case .user: return 3
        }
    }
}

public struct Identifier: CustomStringConvertible, Hashable, Codable, Sendable {
    enum CodingKeys: String, CodingKey {
        case name, type, typeSource, parameterMode, parameterModeSource
    }

    public static func == (lhs: Identifier, rhs: Identifier) -> Bool {
        return lhs.name == rhs.name && lhs.type == rhs.type
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(type)
    }

    public var name: String
    public var type: String
    public var typeSource: TypeSource
    public var parameterMode: ParameterMode
    public var parameterModeSource: ParameterModeSource
    public var description: String {
        if type.isEmpty {
            return name
        } else {
            return "\(name):\(type)"
        }
    }

    public init(
        name: String,
        type: String,
        typeSource: TypeSource? = nil,
        parameterMode: ParameterMode = .unknown,
        parameterModeSource: ParameterModeSource? = nil
    ) {
        self.name = name
        self.type = type
        self.typeSource = typeSource ?? (type.isEmpty || type == "UNKNOWN" ? .unknown : .metadata)
        self.parameterMode = parameterMode
        self.parameterModeSource = parameterModeSource
            ?? (parameterMode == .unknown ? .unknown : .metadata)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.type = try container.decode(String.self, forKey: .type)
        if let rawTypeSource = try container.decodeIfPresent(String.self, forKey: .typeSource),
           !rawTypeSource.isEmpty {
            self.typeSource = TypeSource(rawValue: rawTypeSource) ?? .metadata
        } else {
            self.typeSource = self.type.isEmpty || self.type == "UNKNOWN" ? .unknown : .metadata
        }
        self.parameterMode = try container.decodeIfPresent(
            ParameterMode.self,
            forKey: .parameterMode
        ) ?? .unknown
        self.parameterModeSource = try container.decodeIfPresent(
            ParameterModeSource.self,
            forKey: .parameterModeSource
        ) ?? (self.parameterMode == .unknown ? .unknown : .metadata)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(type, forKey: .type)
        try container.encode(typeSource.rawValue, forKey: .typeSource)
        try container.encode(parameterMode, forKey: .parameterMode)
        try container.encode(parameterModeSource, forKey: .parameterModeSource)
    }

    @discardableResult
    public mutating func assignType(
        _ proposedType: String,
        source proposedSource: TypeSource
    ) -> (existingType: String, existingSource: TypeSource, proposedType: String, proposedSource: TypeSource)? {
        let newType = proposedType.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newType.isEmpty && newType != "UNKNOWN" else { return nil }

        let currentType = type.trimmingCharacters(in: .whitespacesAndNewlines)
        if currentType.isEmpty || currentType == "UNKNOWN" {
            type = newType
            typeSource = proposedSource
            return nil
        }

        if currentType == newType {
            if proposedSource.precedence > typeSource.precedence {
                typeSource = proposedSource
            }
            return nil
        }

        let conflict = (
            existingType: currentType,
            existingSource: typeSource,
            proposedType: newType,
            proposedSource: proposedSource
        )

        if proposedSource.precedence > typeSource.precedence {
            type = newType
            typeSource = proposedSource
        }

        return conflict
    }
}
