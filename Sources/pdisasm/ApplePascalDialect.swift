public enum ApplePascalDialect: String, CaseIterable, Codable, Sendable {
    case applePascal = "apple-pascal"
    case ucsdPSystem = "ucsd-p-system"
}

struct ApplePascalDialectPolicy {
    let keywords: Set<String>
    let caseDefaultKeyword: String
    let supportsUnitSyntax: Bool
    let textFileTypeName: String
    let standardProcedures: [Int: (String, [Identifier], String)]
}

extension ApplePascalDialect {
    var policy: ApplePascalDialectPolicy {
        switch self {
        case .applePascal:
            return ApplePascalDialectPolicy(
                keywords: applePascalKeywords,
                caseDefaultKeyword: "OTHERWISE",
                supportsUnitSyntax: true,
                textFileTypeName: "TEXT",
                standardProcedures: cspProcs
            )
        case .ucsdPSystem:
            // Unverified version differences deliberately retain compatibility
            // behavior until a version-specific table is documented.
            return ApplePascalDialectPolicy(
                keywords: ucsdPSystemKeywords,
                caseDefaultKeyword: "OTHERWISE",
                supportsUnitSyntax: true,
                textFileTypeName: "TEXT",
                standardProcedures: cspProcs
            )
        }
    }
}

private let commonPascalKeywords: Set<String> = [
    "AND", "ARRAY", "BEGIN", "CASE", "CONST", "DIV", "DO", "DOWNTO",
    "ELSE", "END", "FILE", "FOR", "FUNCTION", "GOTO", "IF", "IN",
    "LABEL", "MOD", "NIL", "NOT", "OF", "OR", "OTHERWISE", "PACKED",
    "PROCEDURE", "PROGRAM", "RECORD", "REPEAT", "SET", "THEN", "TO",
    "TYPE", "UNTIL", "VAR", "WHILE", "WITH",
]

private let applePascalKeywords = commonPascalKeywords.union([
    "IMPLEMENTATION", "INTERFACE", "SEGMENT", "UNIT", "USES",
])

private let ucsdPSystemKeywords = commonPascalKeywords.union([
    "IMPLEMENTATION", "INTERFACE", "UNIT", "USES",
])

func standardProcedures(
    for dialect: ApplePascalDialect
) -> [Int: (String, [Identifier], String)] {
    dialect.policy.standardProcedures
}
