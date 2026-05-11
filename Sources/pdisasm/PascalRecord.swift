//
//  KnownRecords.swift
//  pdisasm
//
//  Defines certain well-known structures from UCSD Pascal, like the FIB.
//
//  Created by Christopher Green on 29/4/2026.
//
public final class PascalRecord: CustomStringConvertible, Hashable, Sendable, Codable {
    
    public var description: String {
        return "\(name) { " + members.map { "\($0.key): \($0.value.name)" }.joined(separator: ", ") + " }"
    }
    
    public static func == (lhs: PascalRecord, rhs: PascalRecord) -> Bool {
        return lhs.name == rhs.name && lhs.members == rhs.members && lhs.isSystemRecord == rhs.isSystemRecord
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(isSystemRecord)
    }
    
    required public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.members = try container.decode([Int: Identifier].self, forKey: .members)
        self.isSystemRecord = try container.decodeIfPresent(Bool.self, forKey: .isSystemRecord) ?? false
    }
    
    init(name: String, members: [Int: Identifier], isSystemRecord: Bool = false) {
        self.name = name
        self.members = members
        self.isSystemRecord = isSystemRecord
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.name, forKey: CodingKeys.name)
        try container.encode(self.members, forKey: CodingKeys.members)
        try container.encode(self.isSystemRecord, forKey: CodingKeys.isSystemRecord)
    }
    
    enum CodingKeys: String, CodingKey {
        case name = "name"
        case members = "members"
        case isSystemRecord = "isSystemRecord"
    }
    public let name: String
    public let isSystemRecord: Bool
    public let members: [Int: Identifier]
}

//var knownRecords: [PascalRecord] = [   
//    PascalRecord(name: "FIB", members: [
//        0: Identifier(name:"FWINDOW", type: "WINDOWP"),
//        1: Identifier(name:"FEOLN", type: "BOOLEAN"),
//        2: Identifier(name:"FEOF", type: "BOOLEAN"),
//        3: Identifier(name:"FSTATE", type: "INTEGER"),
//        4: Identifier(name:"FRECSIZE", type: "INTEGER"),
//        5: Identifier(name:"FISOPEN", type: "BOOLEAN"),
//        6: Identifier(name:"FISBLKD", type: "BOOLEAN"),
//        7: Identifier(name:"FUNIT", type: "INTEGER"),
//        8: Identifier(name:"FVID", type: "ARRAY OF CHAR"),
//        12: Identifier(name:"FMAXBLK", type: "INTEGER"),
//        13: Identifier(name:"FNXTBLK", type: "INTEGER"),
//        14: Identifier(name:"FREPTCNT", type: "INTEGER"),
//        15: Identifier(name:"FMODIFIED", type: "BOOLEAN"),
//        16: Identifier(name:"DFIRSTBLK", type: "INTEGER"),
//        17: Identifier(name:"DLASTBLK", type: "INTEGER"),
//        18: Identifier(name:"DFKIND", type: "INTEGER"),
//        19: Identifier(name:"DTID", type: "ARRAY OF CHAR"),
//        27: Identifier(name:"DLASTBYTE", type: "INTEGER"),
//        28: Identifier(name:"DACCESS", type: "INTEGER"),
//        29: Identifier(name:"FSOFTBUF", type: "BOOLEAN"),
//        30: Identifier(name:"FMAXBYTE", type: "INTEGER"),
//        31: Identifier(name:"FNXTBYTE", type: "INTEGER"),
//        32: Identifier(name:"FBUFCHNGD", type: "BOOLEAN"),
//        33: Identifier(name:"FBUFFER", type: "ARRAY OF CHAR"),
//    ]),
//    PascalRecord(name: "DIRENTRY", members: [
//        0: Identifier(name:"DFIRSTBLK", type: "INTEGER"),
//        1: Identifier(name:"DLASTBLK", type: "INTEGER"),
//        2: Identifier(name:"DFKIND", type: "INTEGER"),
//        3: Identifier(name:"DTID", type: "ARRAY OF CHAR"),
//        7: Identifier(name:"DEOVBLK", type: "INTEGER"),
//        8: Identifier(name:"DNUMFILES", type: "INTEGER"),
//        9: Identifier(name:"DLOADTIME", type: "INTEGER"),
//        10: Identifier(name:"DLASTBOOT", type: "INTEGER"),
//        11: Identifier(name:"DLASTBYTE", type: "INTEGER"),
//        12: Identifier(name:"DACCESS", type: "INTEGER"),
//    ]),
//    PascalRecord(name: "SYSCOMREC", members: [
//        0: Identifier(name:"IORSLT", type: "INTEGER"),
//        1: Identifier(name:"XEQERR", type: "INTEGER"),
//        2: Identifier(name:"SYSUNIT", type: "INTEGER"),
//        3: Identifier(name:"BUGSTATE", type: "INTEGER"),
//        4: Identifier(name:"GDIRP", type: "INTEGER"),
//        5: Identifier(name:"BOMBP", type: "INTEGER"),
//        6: Identifier(name:"BASE", type: "INTEGER"),
//        7: Identifier(name:"MP", type: "INTEGER"),
//        8: Identifier(name:"JTAB", type: "INTEGER"),
//        9: Identifier(name:"SEGP", type: "INTEGER"),
//        10: Identifier(name:"MEMTOP", type: "INTEGER"),
//        11: Identifier(name:"BOMIPC", type: "INTEGER"),
//        12: Identifier(name:"HLTLINE", type: "INTEGER"),
//        13: Identifier(name:"BRKPTS1", type: "INTEGER"),
//        14: Identifier(name:"BRKPTS2", type: "INTEGER"),
//        15: Identifier(name:"BRKPTS3", type: "INTEGER"),
//        16: Identifier(name:"BRKPTS4", type: "INTEGER"),
//        17: Identifier(name:"RETRIES", type: "INTEGER"),
//        18: Identifier(name:"EXPANSION1", type: "INTEGER"),
//        19: Identifier(name:"EXPANSION2", type: "INTEGER"),
//        20: Identifier(name:"EXPANSION3", type: "INTEGER"),
//        21: Identifier(name:"EXPANSION4", type: "INTEGER"),
//        22: Identifier(name:"EXPANSION5", type: "INTEGER"),
//        23: Identifier(name:"EXPANSION6", type: "INTEGER"),
//        24: Identifier(name:"EXPANSION7", type: "INTEGER"),
//        25: Identifier(name:"EXPANSION8", type: "INTEGER"),
//        26: Identifier(name:"EXPANSION9", type: "INTEGER"),
//        27: Identifier(name:"LOWTIME", type: "INTEGER"),
//        28: Identifier(name:"HIGHTIME", type: "INTEGER"),
//        29: Identifier(name:"MISCINFO", type: "INTEGER"),
//        30: Identifier(name:"CRTTYPE", type: "INTEGER"),
//        31: Identifier(name:"CRTCTRL1", type: "INTEGER"),
//        32: Identifier(name:"CRTCTRL2", type: "INTEGER"),
//        33: Identifier(name:"CRTCTRL3", type: "INTEGER"),
//        34: Identifier(name:"CRTCTRL4", type: "INTEGER"),
//        35: Identifier(name:"CRTCTRL5", type: "INTEGER"),
//        36: Identifier(name:"CRTCTRL6", type: "INTEGER"),
//        37: Identifier(name:"CRTINFO.HEIGHT", type: "INTEGER"),
//        38: Identifier(name:"CRTINFO.WIDTH", type: "INTEGER"),
//        39: Identifier(name:"CRTINFO.CH1", type: "INTEGER"),
//        40: Identifier(name:"CRTINFO.CH2", type: "INTEGER"),
//        41: Identifier(name:"CRTINFO.CH3", type: "INTEGER"),
//        42: Identifier(name:"CRTINFO.CH4", type: "INTEGER"),
//        43: Identifier(name:"CRTINFO.CH5", type: "INTEGER"),
//        44: Identifier(name:"CRTINFO.CH6", type: "INTEGER"),
//        45: Identifier(name:"CRTINFO.CH7", type: "INTEGER"),
//        46: Identifier(name:"CRTINFO.CH8", type: "INTEGER"),
//        47: Identifier(name:"CRTINFO.PREFIXED", type: "INTEGER"),
//        48: Identifier(name:"SEGTABLE", type: "ARRAY OF SEG_ENTRY"),
//    ])
//]

//let knownStructures:  [String: [Int: Identifier]] = [
//    "FIB": [
//        0: Identifier(name:"FWINDOW", type: "WINDOWP"),
//        1: Identifier(name:"FEOLN", type: "BOOLEAN"),
//        2: Identifier(name:"FEOF", type: "BOOLEAN"),
//        3: Identifier(name:"FSTATE", type: "INTEGER"),
//        4: Identifier(name:"FRECSIZE", type: "INTEGER"),
//        5: Identifier(name:"FISOPEN", type: "BOOLEAN"),
//        6: Identifier(name:"FISBLKD", type: "BOOLEAN"),
//        7: Identifier(name:"FUNIT", type: "INTEGER"),
//        8: Identifier(name:"FVID", type: "ARRAY OF CHAR"),
//        12: Identifier(name:"FMAXBLK", type: "INTEGER"),
//        13: Identifier(name:"FNXTBLK", type: "INTEGER"),
//        14: Identifier(name:"FREPTCNT", type: "INTEGER"),
//        15: Identifier(name:"FMODIFIED", type: "BOOLEAN"),
//        16: Identifier(name:"DFIRSTBLK", type: "INTEGER"),
//        17: Identifier(name:"DLASTBLK", type: "INTEGER"),
//        18: Identifier(name:"DFKIND", type: "INTEGER"),
//        19: Identifier(name:"DTID", type: "ARRAY OF CHAR"),
//        27: Identifier(name:"DLASTBYTE", type: "INTEGER"),
//        28: Identifier(name:"DACCESS", type: "INTEGER"),
//        29: Identifier(name:"FSOFTBUF", type: "BOOLEAN"),
//        30: Identifier(name:"FMAXBYTE", type: "INTEGER"),
//        31: Identifier(name:"FNXTBYTE", type: "INTEGER"),
//        32: Identifier(name:"FBUFCHNGD", type: "BOOLEAN"),
//        33: Identifier(name:"FBUFFER", type: "ARRAY OF CHAR"),
//        ],
//    "DIRENTRY": [
//        0: Identifier(name:"DFIRSTBLK", type: "INTEGER"),
//        1: Identifier(name:"DLASTBLK", type: "INTEGER"),
//        2: Identifier(name:"DFKIND", type: "INTEGER"),
//        3: Identifier(name:"DTID", type: "ARRAY OF CHAR"),
//        7: Identifier(name:"DEOVBLK", type: "INTEGER"),
//        8: Identifier(name:"DNUMFILES", type: "INTEGER"),
//        9: Identifier(name:"DLOADTIME", type: "INTEGER"),
//        10: Identifier(name:"DLASTBOOT", type: "INTEGER"),
//        11: Identifier(name:"DLASTBYTE", type: "INTEGER"),
//        12: Identifier(name:"DACCESS", type: "INTEGER"),
//    ],
//    "SYSCOMREC": [
//        0: Identifier(name:"IORSLT", type: "INTEGER"),
//        1: Identifier(name:"XEQERR", type: "INTEGER"),
//        2: Identifier(name:"SYSUNIT", type: "INTEGER"),
//        3: Identifier(name:"BUGSTATE", type: "INTEGER"),
//        4: Identifier(name:"GDIRP", type: "INTEGER"),
//        5: Identifier(name:"BOMBP", type: "INTEGER"),
//        6: Identifier(name:"BASE", type: "INTEGER"),
//        7: Identifier(name:"MP", type: "INTEGER"),
//        8: Identifier(name:"JTAB", type: "INTEGER"),
//        9: Identifier(name:"SEGP", type: "INTEGER"),
//        10: Identifier(name:"MEMTOP", type: "INTEGER"),
//        11: Identifier(name:"BOMIPC", type: "INTEGER"),
//        12: Identifier(name:"HLTLINE", type: "INTEGER"),
//        13: Identifier(name:"BRKPTS1", type: "INTEGER"),
//        14: Identifier(name:"BRKPTS2", type: "INTEGER"),
//        15: Identifier(name:"BRKPTS3", type: "INTEGER"),
//        16: Identifier(name:"BRKPTS4", type: "INTEGER"),
//        17: Identifier(name:"RETRIES", type: "INTEGER"),
//        18: Identifier(name:"EXPANSION1", type: "INTEGER"),
//        19: Identifier(name:"EXPANSION2", type: "INTEGER"),
//        20: Identifier(name:"EXPANSION3", type: "INTEGER"),
//        21: Identifier(name:"EXPANSION4", type: "INTEGER"),
//        22: Identifier(name:"EXPANSION5", type: "INTEGER"),
//        23: Identifier(name:"EXPANSION6", type: "INTEGER"),
//        24: Identifier(name:"EXPANSION7", type: "INTEGER"),
//        25: Identifier(name:"EXPANSION8", type: "INTEGER"),
//        26: Identifier(name:"EXPANSION9", type: "INTEGER"),
//        27: Identifier(name:"LOWTIME", type: "INTEGER"),
//        28: Identifier(name:"HIGHTIME", type: "INTEGER"),
//        29: Identifier(name:"MISCINFO", type: "INTEGER"),
//        30: Identifier(name:"CRTTYPE", type: "INTEGER"),
//        31: Identifier(name:"CRTCTRL1", type: "INTEGER"),
//        32: Identifier(name:"CRTCTRL2", type: "INTEGER"),
//        33: Identifier(name:"CRTCTRL3", type: "INTEGER"),
//        34: Identifier(name:"CRTCTRL4", type: "INTEGER"),
//        35: Identifier(name:"CRTCTRL5", type: "INTEGER"),
//        36: Identifier(name:"CRTCTRL6", type: "INTEGER"),
//        37: Identifier(name:"CRTINFO.HEIGHT", type: "INTEGER"),
//        38: Identifier(name:"CRTINFO.WIDTH", type: "INTEGER"),
//        39: Identifier(name:"CRTINFO.CH1", type: "INTEGER"),
//        40: Identifier(name:"CRTINFO.CH2", type: "INTEGER"),
//        41: Identifier(name:"CRTINFO.CH3", type: "INTEGER"),
//        42: Identifier(name:"CRTINFO.CH4", type: "INTEGER"),
//        43: Identifier(name:"CRTINFO.CH5", type: "INTEGER"),
//        44: Identifier(name:"CRTINFO.CH6", type: "INTEGER"),
//        45: Identifier(name:"CRTINFO.CH7", type: "INTEGER"),
//        46: Identifier(name:"CRTINFO.CH8", type: "INTEGER"),
//        47: Identifier(name:"CRTINFO.PREFIXED", type: "INTEGER"),
//        48: Identifier(name:"SEGTABLE", type: "ARRAY OF SEG_ENTRY"),
//
//    ]
//
//    ]
