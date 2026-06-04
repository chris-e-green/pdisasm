//
//  KnownRecords.swift
//  pdisasm
//
//  Defines certain well-known structures from UCSD Pascal, like the FIB.
//
//  Created by Christopher Green on 29/4/2026.
//
public struct PascalRecordMember: Hashable, Sendable, Codable {
    public let offset: Int
    public let identifier: Identifier
    public let variantLabel: String?

    public init(offset: Int, identifier: Identifier, variantLabel: String? = nil) {
        self.offset = offset
        self.identifier = identifier
        self.variantLabel = variantLabel
    }
}

public final class PascalRecord: CustomStringConvertible, Hashable, Sendable, Codable {

    public var description: String {
        return "\(name) { " + members.map { "\($0.key): \($0.value.name)" }.joined(separator: ", ") + " }"
    }

    public static func == (lhs: PascalRecord, rhs: PascalRecord) -> Bool {
        return lhs.name == rhs.name
            && lhs.members == rhs.members
            && lhs.allMembers == rhs.allMembers
            && lhs.isSystemRecord == rhs.isSystemRecord
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(isSystemRecord)
    }

    required public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        let decodedMembers = try container.decode([Int: Identifier].self, forKey: .members)
        self.members = decodedMembers
        self.allMembers = try container.decodeIfPresent([PascalRecordMember].self, forKey: .allMembers)
            ?? decodedMembers.keys.sorted().compactMap { offset in
                decodedMembers[offset].map {
                    PascalRecordMember(offset: offset, identifier: $0)
                }
            }
        self.isSystemRecord = try container.decodeIfPresent(Bool.self, forKey: .isSystemRecord) ?? false
    }

    init(
        name: String,
        members: [Int: Identifier],
        allMembers: [PascalRecordMember]? = nil,
        isSystemRecord: Bool = false
    ) {
        self.name = name
        self.members = members
        self.allMembers = allMembers ?? members.keys.sorted().compactMap { offset in
            members[offset].map {
                PascalRecordMember(offset: offset, identifier: $0)
            }
        }
        self.isSystemRecord = isSystemRecord
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.name, forKey: CodingKeys.name)
        try container.encode(self.members, forKey: CodingKeys.members)
        try container.encode(self.allMembers, forKey: CodingKeys.allMembers)
        try container.encode(self.isSystemRecord, forKey: CodingKeys.isSystemRecord)
    }

    enum CodingKeys: String, CodingKey {
        case name = "name"
        case members = "members"
        case allMembers = "allMembers"
        case isSystemRecord = "isSystemRecord"
    }
    public let name: String
    public let isSystemRecord: Bool
    public let members: [Int: Identifier]
    public let allMembers: [PascalRecordMember]
}
