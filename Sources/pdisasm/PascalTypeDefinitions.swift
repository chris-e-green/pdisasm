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
                let allMembers = parseRecordAllMembers(rhs, constants: definitions.constants)
                definitions.records.insert(PascalRecord(
                    name: declaration.name,
                    members: primaryMembers(from: allMembers),
                    allMembers: allMembers,
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

    private static func parseRecordAllMembers(
        _ typeText: String,
        constants: [String: Int]
    ) -> [PascalRecordMember] {
        guard let body = recordBody(typeText) else { return [] }
        let parsed = parseRecordMemberList(
            body,
            startOffset: 0,
            constants: constants,
            variantLabel: nil
        )
        return parsed.members
    }

    private static func primaryMembers(from allMembers: [PascalRecordMember]) -> [Int: Identifier] {
        var members: [Int: Identifier] = [:]
        for member in allMembers where members[member.offset] == nil {
            members[member.offset] = member.identifier
        }
        return members
    }

    private static func parseRecordMemberList(
        _ body: String,
        startOffset: Int,
        constants: [String: Int],
        variantLabel: String?
    ) -> (members: [PascalRecordMember], size: Int) {
        let chars = Array(body)
        var index = 0
        var offset = startOffset
        var members: [PascalRecordMember] = []

        while index < chars.count {
            skipSeparators(chars, &index)
            guard index < chars.count else { break }

            if startsWithWord("CASE", chars, index) {
                let parsedCase = parseVariantCase(
                    chars,
                    from: index,
                    startOffset: offset,
                    constants: constants
                )
                guard parsedCase.nextIndex > index else { break }
                members.append(contentsOf: parsedCase.members)
                offset += parsedCase.size
                index = parsedCase.nextIndex
                continue
            }

            let declarationStart = index
            guard let declarationEnd = nextTopLevelIndex(of: ";", in: chars, from: index) else {
                index = chars.count
                let declaration = String(chars[declarationStart..<index])
                let parsed = parseFieldDeclaration(
                    declaration,
                    startOffset: offset,
                    constants: constants,
                    variantLabel: variantLabel
                )
                members.append(contentsOf: parsed.members)
                offset += parsed.size
                break
            }

            index = declarationEnd + 1
            let declaration = String(chars[declarationStart..<declarationEnd])
            let parsed = parseFieldDeclaration(
                declaration,
                startOffset: offset,
                constants: constants,
                variantLabel: variantLabel
            )
            members.append(contentsOf: parsed.members)
            offset += parsed.size
        }

        return (members, max(offset - startOffset, 0))
    }

    private static func parseVariantCase(
        _ chars: [Character],
        from start: Int,
        startOffset: Int,
        constants: [String: Int]
    ) -> (members: [PascalRecordMember], size: Int, nextIndex: Int) {
        var index = start + 4
        guard let ofIndex = nextTopLevelWord("OF", in: chars, from: index) else {
            return ([], 0, start)
        }

        let header = String(chars[index..<ofIndex])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var members: [PascalRecordMember] = []
        var variantBaseOffset = startOffset

        if let colonIndex = topLevelColonIndex(in: Array(header)) {
            let headerChars = Array(header)
            let tagName = String(headerChars[..<colonIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            let tagType = String(headerChars[(colonIndex + 1)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !tagName.isEmpty {
                members.append(PascalRecordMember(
                    offset: startOffset,
                    identifier: Identifier(
                        name: tagName,
                        type: normalizeType(tagType, constants: constants)
                    )
                ))
                variantBaseOffset += 1
            }
        }

        index = ofIndex + 2
        var maxVariantSize = 0
        while index < chars.count {
            skipSeparators(chars, &index)
            guard index < chars.count else { break }

            guard let colonIndex = topLevelColonIndex(in: chars, from: index) else {
                break
            }
            let label = String(chars[index..<colonIndex])
                .split(whereSeparator: { $0.isWhitespace })
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            var valueIndex = colonIndex + 1
            skipWhitespace(chars, &valueIndex)
            guard valueIndex < chars.count, chars[valueIndex] == "(",
                  let closeIndex = matchingParenIndex(in: chars, from: valueIndex)
            else {
                break
            }

            let armBody = String(chars[(valueIndex + 1)..<closeIndex])
            let parsedArm = parseRecordMemberList(
                armBody,
                startOffset: variantBaseOffset,
                constants: constants,
                variantLabel: label.isEmpty ? nil : label
            )
            members.append(contentsOf: parsedArm.members)
            maxVariantSize = max(maxVariantSize, parsedArm.size)
            index = closeIndex + 1
            if index < chars.count, chars[index] == ";" {
                index += 1
            }
        }

        return (
            members,
            (variantBaseOffset - startOffset) + maxVariantSize,
            index
        )
    }

    private static func parseFieldDeclaration(
        _ declaration: String,
        startOffset: Int,
        constants: [String: Int],
        variantLabel: String?
    ) -> (members: [PascalRecordMember], size: Int) {
        let chars = Array(declaration)
        guard let colonIndex = topLevelColonIndex(in: chars) else { return ([], 0) }
        let names = String(chars[..<colonIndex]).split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }
        let type = normalizeType(String(chars[(colonIndex + 1)...]), constants: constants)
        var members: [PascalRecordMember] = []
        var offset = startOffset
        for name in names where !name.isEmpty {
            members.append(PascalRecordMember(
                offset: offset,
                identifier: Identifier(name: name, type: type),
                variantLabel: variantLabel
            ))
            offset += 1
        }
        return (members, offset - startOffset)
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
        if let arrayType = normalizeArrayType(upper, constants: constants) {
            return arrayType
        }
        if let bounds = parseSubrange(upper, constants: constants) {
            return "\(bounds.lower)..\(bounds.upper)"
        }
        return upper
    }

    private static func normalizeArrayType(_ typeText: String, constants: [String: Int]) -> String? {
        let prefix: String
        var rest: String
        if typeText.hasPrefix("PACKED ARRAY") {
            prefix = "PACKED ARRAY"
            rest = String(typeText.dropFirst("PACKED ARRAY".count))
        } else if typeText.hasPrefix("ARRAY") {
            prefix = "ARRAY"
            rest = String(typeText.dropFirst("ARRAY".count))
        } else {
            return nil
        }

        rest = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        if rest.hasPrefix("["),
           let closeBracket = matchingBracketIndex(in: Array(rest), from: 0) {
            let chars = Array(rest)
            let indexText = String(chars[1..<closeBracket])
            let afterBracket = String(chars[(closeBracket + 1)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard afterBracket.hasPrefix("OF ") else {
                return typeText
            }
            let elementText = String(afterBracket.dropFirst("OF ".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedIndexes = indexText.split(separator: ",").map {
                normalizeArrayIndexType(String($0), constants: constants)
            }.joined(separator: ", ")
            return "\(prefix)[\(normalizedIndexes)] OF \(normalizeType(elementText, constants: constants))"
        }

        guard rest.hasPrefix("OF ") else {
            return typeText
        }
        let elementText = String(rest.dropFirst("OF ".count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(prefix) OF \(normalizeType(elementText, constants: constants))"
    }

    private static func normalizeArrayIndexType(_ typeText: String, constants: [String: Int]) -> String {
        let upper = typeText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        if let bounds = parseSubrange(upper, constants: constants) {
            return "\(bounds.lower)..\(bounds.upper)"
        }
        return normalizeType(upper, constants: constants)
    }

    private static func matchingBracketIndex(in chars: [Character], from start: Int) -> Int? {
        guard start < chars.count, chars[start] == "[" else { return nil }
        var depth = 0
        var index = start
        while index < chars.count {
            if chars[index] == "[" {
                depth += 1
            } else if chars[index] == "]" {
                depth -= 1
                if depth == 0 {
                    return index
                }
            }
            index += 1
        }
        return nil
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

    private static func nextTopLevelIndex(
        of character: Character,
        in chars: [Character],
        from start: Int
    ) -> Int? {
        var index = start
        var parenDepth = 0
        while index < chars.count {
            if chars[index] == "(" {
                parenDepth += 1
            } else if chars[index] == ")" {
                parenDepth = max(parenDepth - 1, 0)
            } else if chars[index] == character && parenDepth == 0 {
                return index
            }
            index += 1
        }
        return nil
    }

    private static func nextTopLevelWord(
        _ word: String,
        in chars: [Character],
        from start: Int
    ) -> Int? {
        var index = start
        var parenDepth = 0
        while index < chars.count {
            if chars[index] == "(" {
                parenDepth += 1
            } else if chars[index] == ")" {
                parenDepth = max(parenDepth - 1, 0)
            } else if parenDepth == 0 && startsWithWord(word, chars, index) {
                return index
            }
            index += 1
        }
        return nil
    }

    private static func topLevelColonIndex(in chars: [Character], from start: Int = 0) -> Int? {
        nextTopLevelIndex(of: ":", in: chars, from: start)
    }

    private static func matchingParenIndex(in chars: [Character], from openIndex: Int) -> Int? {
        guard openIndex < chars.count, chars[openIndex] == "(" else { return nil }
        var index = openIndex
        var depth = 0
        while index < chars.count {
            if chars[index] == "(" {
                depth += 1
            } else if chars[index] == ")" {
                depth -= 1
                if depth == 0 {
                    return index
                }
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
