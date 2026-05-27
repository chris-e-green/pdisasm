public enum TypeSource: String, Codable, Sendable {
    case unknown
    case inferred
    case procedureSignature
    case metadata
    case user

    var precedence: Int {
        switch self {
        case .unknown: return 0
        case .inferred: return 1
        case .procedureSignature: return 2
        case .metadata: return 3
        case .user: return 4
        }
    }
}

public struct TypeConflict: Hashable, Sendable {
    public let segment: Int
    public let procedure: Int?
    public let lexLevel: Int?
    public let addr: Int?
    public let existingType: String
    public let existingSource: TypeSource
    public let proposedType: String
    public let proposedSource: TypeSource
    public let evidence: String

    init(
        location: Location,
        existingType: String,
        existingSource: TypeSource,
        proposedType: String,
        proposedSource: TypeSource,
        evidence: String
    ) {
        self.segment = location.segment
        self.procedure = location.procedure
        self.lexLevel = location.lexLevel
        self.addr = location.addr
        self.existingType = existingType
        self.existingSource = existingSource
        self.proposedType = proposedType
        self.proposedSource = proposedSource
        self.evidence = evidence
    }
}

public final class Location: Hashable, CustomStringConvertible, Comparable,
    Codable
{
    public var segment: Int
    public var procedure: Int?
    public var lexLevel: Int?
    public var addr: Int?
    public var isParam: Bool
    public var name: String
    public var type: String
    public var typeSource: TypeSource

    enum CodingKeys: String, CodingKey {
        case segment, procedure, lexLevel, addr, name, type, typeSource
    }

    public static func < (lhs: Location, rhs: Location) -> Bool {
        if lhs.segment != rhs.segment {
            return lhs.segment < rhs.segment
        }
        if lhs.procedure != rhs.procedure {
            return (lhs.procedure ?? -1) < (rhs.procedure ?? -1)
        }
        if lhs.lexLevel != rhs.lexLevel {
            return (lhs.lexLevel ?? -1) < (rhs.lexLevel ?? -1)
        }
        return (lhs.addr ?? -1) < (rhs.addr ?? -1)
    }

    required public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.segment = try container.decode(
            Int.self,
            forKey: CodingKeys.segment
        )
        self.procedure = try container.decodeIfPresent(
            Int.self,
            forKey: CodingKeys.procedure
        )
        self.lexLevel = try container.decodeIfPresent(
            Int.self,
            forKey: CodingKeys.lexLevel
        )
        self.addr = try container.decodeIfPresent(
            Int.self,
            forKey: CodingKeys.addr
        )
        self.isParam = false
        self.name = try container.decode(String.self, forKey: CodingKeys.name)
        self.type = try container.decode(String.self, forKey: CodingKeys.type)
        if let rawTypeSource = try container.decodeIfPresent(
            String.self,
            forKey: CodingKeys.typeSource
        ), !rawTypeSource.isEmpty {
            self.typeSource = TypeSource(rawValue: rawTypeSource) ?? .metadata
        } else {
            self.typeSource = self.type.isEmpty || self.type == "UNKNOWN" ? .unknown : .metadata
        }
    }

    public init(
        segment: Int,
        procedure: Int? = nil,
        lexLevel: Int? = nil,
        addr: Int? = nil,
        isParam: Bool = false,
        name: String = "",
        type: String = "",
        typeSource: TypeSource? = nil
    ) {
        self.segment = segment
        self.procedure = procedure
        self.lexLevel = lexLevel
        self.addr = addr
        self.isParam = isParam
        self.name = name
        self.type = type
        self.typeSource = typeSource ?? (type.isEmpty || type == "UNKNOWN" ? .unknown : .metadata)
    }

    public init(from str: String) {
        self.procedure = nil
        self.lexLevel = nil
        self.addr = nil
        self.segment = 0
        self.name = ""
        self.type = ""
        self.typeSource = .unknown
        if str.contains("_") {
            let sa = str.split(separator: "_")
            for sai in sa {
                if sai.starts(with: "P") {
                    self.procedure = Int(sai.dropFirst())
                } else if sai.starts(with: "L") {
                    self.lexLevel = Int(sai.dropFirst())
                } else if sai.starts(with: "S") {
                    self.segment = Int(sai.dropFirst()) ?? -1
                } else if sai.starts(with: "A") {
                    self.addr = Int(sai.dropFirst())
                }
            }
        }
        self.isParam = false
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.segment, forKey: CodingKeys.segment)
        try container.encode(self.procedure, forKey: CodingKeys.procedure)
        try container.encode(self.lexLevel, forKey: CodingKeys.lexLevel)
        try container.encode(self.addr, forKey: CodingKeys.addr)
        try container.encode(self.name, forKey: CodingKeys.name)
        try container.encode(self.type, forKey: CodingKeys.type)
        try container.encode(self.typeSource.rawValue, forKey: CodingKeys.typeSource)
    }

    public static func == (lhs: Location, rhs: Location) -> Bool {
        return lhs.segment == rhs.segment && lhs.procedure == rhs.procedure
            && lhs.lexLevel == rhs.lexLevel && lhs.addr == rhs.addr
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(segment)
        hasher.combine(procedure)
        hasher.combine(lexLevel)
        hasher.combine(addr)
    }

    public var displayName: String {
        if !name.isEmpty {
            return name
        }
        var locationString = "S\(segment)"
        if let procedure = procedure {
            locationString += "_P\(procedure)"
        }
        if let lexLevel = lexLevel {
            locationString += "_L\(lexLevel)"
        }
        if let addr = addr {
            locationString += "_A\(addr)"
        }
        return locationString
    }

    public var displayType: String {
        return type.isEmpty ? "UNKNOWN" : type
    }

    public var description: String {
        type.isEmpty ? displayName : "\(displayName):\(type)"
    }

    @discardableResult
    public func assignType(
        _ proposedType: String,
        source proposedSource: TypeSource,
        evidence: String = ""
    ) -> TypeConflict? {
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

        let conflict = TypeConflict(
            location: self,
            existingType: currentType,
            existingSource: typeSource,
            proposedType: newType,
            proposedSource: proposedSource,
            evidence: evidence
        )

        if proposedSource.precedence > typeSource.precedence {
            type = newType
            typeSource = proposedSource
        }

        return conflict
    }
}
