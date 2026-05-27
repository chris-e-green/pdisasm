public struct Identifier: CustomStringConvertible, Hashable, Codable, Sendable {
    enum CodingKeys: String, CodingKey {
        case name, type, typeSource
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
    public var description: String {
        if type.isEmpty {
            return name
        } else {
            return "\(name):\(type)"
        }
    }

    public init(name: String, type: String, typeSource: TypeSource? = nil) {
        self.name = name
        self.type = type
        self.typeSource = typeSource ?? (type.isEmpty || type == "UNKNOWN" ? .unknown : .metadata)
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
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(type, forKey: .type)
        try container.encode(typeSource.rawValue, forKey: .typeSource)
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
