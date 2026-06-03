import Foundation

public struct PascalScalarType: Hashable, Sendable, Codable {
    public let name: String
    public let cases: [String]

    public var valuesByName: [String: Int] {
        Dictionary(uniqueKeysWithValues: cases.enumerated().map { ($0.element, $0.offset) })
    }

    public var namesByValue: [Int: String] {
        Dictionary(uniqueKeysWithValues: cases.enumerated().map { ($0.offset, $0.element) })
    }

    init(name: String, cases: [String]) {
        self.name = name
        self.cases = cases
    }
}

public struct PascalSubrangeType: Hashable, Sendable, Codable {
    public let name: String
    public let lowerBound: Int
    public let upperBound: Int

    public var renderedType: String {
        "\(lowerBound)..\(upperBound)"
    }

    init(name: String, lowerBound: Int, upperBound: Int) {
        self.name = name
        self.lowerBound = lowerBound
        self.upperBound = upperBound
    }
}

struct PascalTypeDefinitions: Sendable {
    var aliases: [String: String] = [:]
    var records: Set<PascalRecord> = []
    var scalarTypes: [String: PascalScalarType] = [:]
    var constants: [String: Int] = [:]
    var subrangeTypes: [String: PascalSubrangeType] = [:]
}

enum PascalTypeDefinitionParser {
    static func parse(_ source: String, isSystemRecord: Bool = false) -> PascalTypeDefinitions {
        let declarations = parseDeclarations(source)
        var definitions = PascalTypeDefinitions()

        for declaration in declarations {
            let rhs = declaration.typeText.trimmingCharacters(in: .whitespacesAndNewlines)
            if let value = parseIntegerConstant(rhs) {
                definitions.constants[declaration.name] = value
            }
        }

        for declaration in declarations {
            let rhs = declaration.typeText.trimmingCharacters(in: .whitespacesAndNewlines)
            if definitions.constants[declaration.name] != nil {
                continue
            }
            if isRecordType(rhs) {
                definitions.records.insert(PascalRecord(
                    name: declaration.name,
                    members: parseRecordMembers(rhs, constants: definitions.constants),
                    isSystemRecord: isSystemRecord
                ))
            } else if let cases = parseScalarCases(rhs) {
                definitions.scalarTypes[declaration.name] = PascalScalarType(
                    name: declaration.name,
                    cases: cases
                )
            } else if let bounds = parseSubrange(rhs, constants: definitions.constants) {
                definitions.subrangeTypes[declaration.name] = PascalSubrangeType(
                    name: declaration.name,
                    lowerBound: bounds.lower,
                    upperBound: bounds.upper
                )
                definitions.aliases[declaration.name] = "INTEGER"
            } else {
                definitions.aliases[declaration.name] = normalizeType(
                    rhs,
                    constants: definitions.constants
                )
            }
        }

        return definitions
    }

    private struct Declaration {
        let name: String
        let typeText: String
    }

    private static func parseDeclarations(_ source: String) -> [Declaration] {
        let cleaned = stripComments(source)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let scanner = Array(cleaned)
        var index = 0
        var declarations: [Declaration] = []

        while index < scanner.count {
            skipSeparators(scanner, &index)
            if startsWithWord("TYPE", scanner, index) {
                index += 4
                continue
            }
            if startsWithWord("CONST", scanner, index) {
                index += 5
                continue
            }

            guard let equalsIndex = nextIndex(of: "=", in: scanner, from: index) else {
                break
            }
            let name = String(scanner[index..<equalsIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            index = equalsIndex + 1
            skipWhitespace(scanner, &index)

            let typeStart = index
            if startsWithRecord(scanner, index) {
                if let endRange = findRecordEnd(in: scanner, from: index) {
                    index = endRange.upperBound
                } else {
                    index = scanner.count
                }
            } else if let semicolon = nextIndex(of: ";", in: scanner, from: index) {
                index = semicolon
            } else {
                index = scanner.count
            }

            let typeText = String(scanner[typeStart..<index])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty, !typeText.isEmpty {
                declarations.append(Declaration(name: name, typeText: typeText))
            }
            if index < scanner.count, scanner[index] == ";" {
                index += 1
            }
        }

        return declarations
    }

    private static func stripComments(_ source: String) -> String {
        var result = ""
        var index = source.startIndex
        while index < source.endIndex {
            if source[index] == "{" {
                if let end = source[index...].firstIndex(of: "}") {
                    index = source.index(after: end)
                } else {
                    break
                }
            } else {
                result.append(source[index])
                index = source.index(after: index)
            }
        }
        return result
    }

    private static func parseRecordMembers(_ typeText: String, constants: [String: Int]) -> [Int: Identifier] {
        guard let body = recordBody(typeText) else { return [:] }
        var members: [Int: Identifier] = [:]
        var offset = 0
        for declaration in body.split(separator: ";") {
            let parts = declaration.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let names = parts[0].split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            }
            let type = normalizeType(String(parts[1]), constants: constants)
            for name in names where !name.isEmpty {
                members[offset] = Identifier(name: name, type: type)
                offset += 1
            }
        }
        return members
    }

    private static func recordBody(_ typeText: String) -> String? {
        let upper = typeText.uppercased()
        guard let recordRange = upper.range(of: "RECORD"),
              let endRange = upper.range(of: "END", options: .backwards) else {
            return nil
        }
        return String(typeText[recordRange.upperBound..<endRange.lowerBound])
    }

    private static func normalizeType(_ typeText: String, constants: [String: Int]) -> String {
        let collapsed = typeText
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = collapsed.uppercased()
        if upper.contains("ARRAY"), let ofRange = upper.range(of: " OF ") {
            let elementType = upper[ofRange.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return "ARRAY OF \(normalizeType(String(elementType), constants: constants))"
        }
        if let bounds = parseSubrange(upper, constants: constants) {
            return "\(bounds.lower)..\(bounds.upper)"
        }
        return upper
    }

    private static func parseIntegerConstant(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: #"^[+-]?[0-9]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        return Int(trimmed)
    }

    private static func parseSubrange(
        _ text: String,
        constants: [String: Int]
    ) -> (lower: Int, upper: Int)? {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let parts = collapsed.components(separatedBy: "..")
        guard parts.count == 2,
              let lower = resolveInteger(parts[0], constants: constants),
              let upper = resolveInteger(parts[1], constants: constants)
        else {
            return nil
        }
        return (lower, upper)
    }

    private static func resolveInteger(_ text: String, constants: [String: Int]) -> Int? {
        if let value = parseIntegerConstant(text) {
            return value
        }
        return constants[text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()]
    }

    private static func parseScalarCases(_ typeText: String) -> [String]? {
        let trimmed = typeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("("), trimmed.hasSuffix(")") else { return nil }
        let body = trimmed.dropFirst().dropLast()
        let cases = body.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }
        guard !cases.isEmpty, cases.allSatisfy({ !$0.isEmpty && isIdentifierText($0) }) else {
            return nil
        }
        return cases
    }

    private static func isRecordType(_ typeText: String) -> Bool {
        typeText.uppercased().contains("RECORD")
    }

    private static func startsWithRecord(_ chars: [Character], _ index: Int) -> Bool {
        startsWithWord("RECORD", chars, index) || startsWithWords(["PACKED", "RECORD"], chars, index)
    }

    private static func startsWithWords(_ words: [String], _ chars: [Character], _ start: Int) -> Bool {
        var index = start
        for word in words {
            skipWhitespace(chars, &index)
            guard startsWithWord(word, chars, index) else { return false }
            index += word.count
        }
        return true
    }

    private static func startsWithWord(_ word: String, _ chars: [Character], _ index: Int) -> Bool {
        guard index + word.count <= chars.count else { return false }
        let text = String(chars[index..<(index + word.count)]).uppercased()
        guard text == word else { return false }
        if index > chars.startIndex, isIdentifier(chars[index - 1]) { return false }
        if index + word.count < chars.count, isIdentifier(chars[index + word.count]) { return false }
        return true
    }

    private static func findRecordEnd(in chars: [Character], from start: Int) -> Range<Int>? {
        var index = start
        while index < chars.count {
            if startsWithWord("END", chars, index) {
                return index..<(index + 3)
            }
            index += 1
        }
        return nil
    }

    private static func nextIndex(of character: Character, in chars: [Character], from start: Int) -> Int? {
        var index = start
        while index < chars.count {
            if chars[index] == character {
                return index
            }
            index += 1
        }
        return nil
    }

    private static func skipSeparators(_ chars: [Character], _ index: inout Int) {
        while index < chars.count, chars[index].isWhitespace || chars[index] == ";" {
            index += 1
        }
    }

    private static func skipWhitespace(_ chars: [Character], _ index: inout Int) {
        while index < chars.count, chars[index].isWhitespace {
            index += 1
        }
    }

    private static func isIdentifier(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    private static func isIdentifierText(_ text: String) -> Bool {
        guard let first = text.first, first.isLetter || first == "_" else { return false }
        return text.allSatisfy(isIdentifier)
    }
}
