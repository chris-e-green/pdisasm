import Foundation

public enum PascalBuiltinType: String, Hashable, Sendable {
    case boolean = "BOOLEAN"
    case byte = "BYTE"
    case char = "CHAR"
    case integer = "INTEGER"
    case longint = "LONGINT"
    case real = "REAL"
    case word = "WORD"
}

public struct PascalEnumeratedType: Hashable, Sendable {
    public var cases: [String]

    public init(cases: [String]) {
        self.cases = cases
    }
}

public struct PascalSubrangeTypeReference: Hashable, Sendable {
    public var lowerBound: String
    public var upperBound: String

    public init(lowerBound: String, upperBound: String) {
        self.lowerBound = lowerBound
        self.upperBound = upperBound
    }
}

public struct PascalPointerType: Hashable, Sendable {
    public var pointee: PascalType

    public init(pointee: PascalType) {
        self.pointee = pointee
    }
}

public struct PascalArrayType: Hashable, Sendable {
    public var isPacked: Bool
    public var indexTypes: [PascalType]
    public var elementType: PascalType

    public init(isPacked: Bool = false, indexTypes: [PascalType] = [], elementType: PascalType) {
        self.isPacked = isPacked
        self.indexTypes = indexTypes
        self.elementType = elementType
    }
}

public struct PascalSetType: Hashable, Sendable {
    public var elementType: PascalType

    public init(elementType: PascalType) {
        self.elementType = elementType
    }
}

public struct PascalFileType: Hashable, Sendable {
    public var elementType: PascalType?
    public var isText: Bool

    public init(elementType: PascalType? = nil, isText: Bool = false) {
        self.elementType = elementType
        self.isText = isText
    }
}

public struct PascalRecordField: Hashable, Sendable {
    public var names: [String]
    public var type: PascalType

    public init(names: [String], type: PascalType) {
        self.names = names
        self.type = type
    }
}

public struct PascalRecordType: Hashable, Sendable {
    public var isPacked: Bool
    public var fields: [PascalRecordField]
    public var rawBody: String?

    public init(isPacked: Bool = false, fields: [PascalRecordField] = [], rawBody: String? = nil) {
        self.isPacked = isPacked
        self.fields = fields
        self.rawBody = rawBody
    }
}

public struct PascalVariantRecordType: Hashable, Sendable {
    public var isPacked: Bool
    public var fixedFields: [PascalRecordField]
    public var variantBody: String

    public init(isPacked: Bool = false, fixedFields: [PascalRecordField] = [], variantBody: String) {
        self.isPacked = isPacked
        self.fixedFields = fixedFields
        self.variantBody = variantBody
    }
}

public struct PascalPackedFieldType: Hashable, Sendable {
    public var storageType: PascalType?
    public var width: Int?
    public var bitOffset: Int?
    public var rawText: String?

    public init(storageType: PascalType? = nil, width: Int? = nil, bitOffset: Int? = nil, rawText: String? = nil) {
        self.storageType = storageType
        self.width = width
        self.bitOffset = bitOffset
        self.rawText = rawText
    }
}

public indirect enum PascalType: Hashable, Sendable {
    case builtIn(PascalBuiltinType)
    case named(String)
    case enumerated(PascalEnumeratedType)
    case subrange(PascalSubrangeTypeReference)
    case pointer(PascalPointerType)
    case array(PascalArrayType)
    case record(PascalRecordType)
    case variantRecord(PascalVariantRecordType)
    case set(PascalSetType)
    case file(PascalFileType)
    case string
    case packedField(PascalPackedFieldType)
    case unknown
    case raw(String)

    public static func parse(_ typeText: String) -> PascalType {
        PascalTypeParser(typeText).parse()
    }

    public var renderedType: String {
        switch self {
        case .builtIn(let type):
            return type.rawValue
        case .named(let name):
            return renderPascalIdentifier(name)
        case .enumerated(let type):
            return "(" + type.cases.map(renderPascalIdentifier).joined(separator: ", ") + ")"
        case .subrange(let type):
            return "\(type.lowerBound)..\(type.upperBound)"
        case .pointer(let type):
            return "^\(type.pointee.renderedType)"
        case .array(let type):
            let prefix = type.isPacked ? "PACKED ARRAY" : "ARRAY"
            if type.indexTypes.isEmpty {
                return "\(prefix) OF \(type.elementType.renderedType)"
            }
            return "\(prefix)[\(type.indexTypes.map(\.renderedType).joined(separator: ", "))] OF \(type.elementType.renderedType)"
        case .record(let type):
            return renderRecordType(type)
        case .variantRecord(let type):
            return renderVariantRecordType(type)
        case .set(let type):
            return "SET OF \(type.elementType.renderedType)"
        case .file(let type):
            if type.isText {
                return "TEXT"
            }
            if let elementType = type.elementType {
                return "FILE OF \(elementType.renderedType)"
            }
            return "FILE"
        case .string:
            return "STRING"
        case .packedField(let type):
            if let rawText = type.rawText, !rawText.isEmpty {
                return rawText
            }
            var parts: [String] = []
            if let storageType = type.storageType {
                parts.append(storageType.renderedType)
            }
            if let width = type.width {
                parts.append("WIDTH \(width)")
            }
            if let bitOffset = type.bitOffset {
                parts.append("BIT \(bitOffset)")
            }
            return parts.isEmpty ? "PACKED FIELD" : "PACKED FIELD(\(parts.joined(separator: ", ")))"
        case .unknown:
            return "UNKNOWN"
        case .raw(let text):
            return text
        }
    }

    private func renderRecordType(_ type: PascalRecordType) -> String {
        let prefix = type.isPacked ? "PACKED RECORD" : "RECORD"
        if let rawBody = type.rawBody {
            return "\(prefix) \(rawBody) END"
        }
        guard !type.fields.isEmpty else {
            return "\(prefix) END"
        }
        let fields = type.fields.map { field in
            "\(field.names.map(renderPascalIdentifier).joined(separator: ", ")): \(field.type.renderedType)"
        }.joined(separator: "; ")
        return "\(prefix) \(fields); END"
    }

    private func renderVariantRecordType(_ type: PascalVariantRecordType) -> String {
        let prefix = type.isPacked ? "PACKED RECORD" : "RECORD"
        let fixedFields = type.fixedFields.map { field in
            "\(field.names.map(renderPascalIdentifier).joined(separator: ", ")): \(field.type.renderedType)"
        }.joined(separator: "; ")
        let separator = fixedFields.isEmpty ? "" : "; "
        return "\(prefix) \(fixedFields)\(separator)\(type.variantBody) END"
    }
}

private struct PascalTypeParser {
    let original: String
    let collapsed: String
    let upper: String

    init(_ typeText: String) {
        self.original = typeText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.collapsed = PascalTypeParser.collapseWhitespace(typeText)
        self.upper = collapsed.uppercased()
    }

    func parse() -> PascalType {
        guard !collapsed.isEmpty else { return .unknown }
        if upper == "UNKNOWN" { return .unknown }
        if upper == "STRING" { return .string }
        if upper == "TEXT" { return .file(PascalFileType(isText: true)) }
        if let builtin = PascalBuiltinType(rawValue: upper) {
            return .builtIn(builtin)
        }
        if upper == "POINTER" {
            return .pointer(PascalPointerType(pointee: .unknown))
        }
        if collapsed.hasPrefix("^") {
            let pointeeText = String(collapsed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            return .pointer(PascalPointerType(pointee: PascalType.parse(pointeeText)))
        }
        if let parsed = parseArray() { return parsed }
        if let parsed = parseSet() { return parsed }
        if let parsed = parseFile() { return parsed }
        if let parsed = parseRecord() { return parsed }
        if let parsed = parseEnumerated() { return parsed }
        if let parsed = parseSubrange() { return parsed }
        if isIdentifier(collapsed) {
            return .named(upper)
        }
        return .raw(collapsed)
    }

    private func parseArray() -> PascalType? {
        let isPacked: Bool
        let rest: String
        if startsWithWords(["PACKED", "ARRAY"]) {
            isPacked = true
            rest = collapsed.dropLeadingWords(["PACKED", "ARRAY"])
        } else if startsWithWords(["ARRAY"]) {
            isPacked = false
            rest = collapsed.dropLeadingWords(["ARRAY"])
        } else {
            return nil
        }

        let trimmedRest = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedRest.uppercased().hasPrefix("OF ") {
            let elementText = String(trimmedRest.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
            return .array(PascalArrayType(isPacked: isPacked, elementType: PascalType.parse(elementText)))
        }

        guard trimmedRest.hasPrefix("["),
              let closeBracket = matchingBracket(in: trimmedRest),
              closeBracket + 1 < trimmedRest.count
        else {
            return .raw(collapsed)
        }
        let body = String(Array(trimmedRest)[1..<closeBracket])
        let afterBracket = String(Array(trimmedRest)[(closeBracket + 1)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard afterBracket.uppercased().hasPrefix("OF ") else {
            return .raw(collapsed)
        }
        let elementText = String(afterBracket.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        let indexTypes = splitTopLevel(body, separator: ",").map { PascalType.parse($0) }
        return .array(PascalArrayType(
            isPacked: isPacked,
            indexTypes: indexTypes,
            elementType: PascalType.parse(elementText)
        ))
    }

    private func parseSet() -> PascalType? {
        guard upper.hasPrefix("SET OF ") else { return nil }
        let elementText = String(collapsed.dropFirst("SET OF ".count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return .set(PascalSetType(elementType: PascalType.parse(elementText)))
    }

    private func parseFile() -> PascalType? {
        guard upper.hasPrefix("FILE OF ") else { return nil }
        let elementText = String(collapsed.dropFirst("FILE OF ".count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return .file(PascalFileType(elementType: PascalType.parse(elementText)))
    }

    private func parseEnumerated() -> PascalType? {
        guard collapsed.hasPrefix("("), collapsed.hasSuffix(")") else { return nil }
        let body = String(collapsed.dropFirst().dropLast())
        let cases = splitTopLevel(body, separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }
        guard !cases.isEmpty, cases.allSatisfy(isIdentifier) else {
            return .raw(collapsed)
        }
        return .enumerated(PascalEnumeratedType(cases: cases))
    }

    private func parseSubrange() -> PascalType? {
        let parts = splitTopLevel(collapsed, separator: "..")
        guard parts.count == 2 else { return nil }
        let lower = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let upper = parts[1].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !lower.isEmpty, !upper.isEmpty else { return .raw(collapsed) }
        return .subrange(PascalSubrangeTypeReference(lowerBound: lower, upperBound: upper))
    }

    private func parseRecord() -> PascalType? {
        let isPacked: Bool
        let rest: String
        if startsWithWords(["PACKED", "RECORD"]) {
            isPacked = true
            rest = collapsed.dropLeadingWords(["PACKED", "RECORD"])
        } else if startsWithWords(["RECORD"]) {
            isPacked = false
            rest = collapsed.dropLeadingWords(["RECORD"])
        } else {
            return nil
        }

        let trimmedRest = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedRest.uppercased().hasSuffix("END") else {
            return .raw(collapsed)
        }
        let bodyEnd = trimmedRest.index(trimmedRest.endIndex, offsetBy: -3)
        let body = String(trimmedRest[..<bodyEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else {
            return .record(PascalRecordType(isPacked: isPacked))
        }
        if body.uppercased().contains("CASE ") {
            let fixedText = String(body.prefixBeforeTopLevelWord("CASE"))
            let variantText = String(body.dropFirst(fixedText.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let fixed = parseRecordFields(fixedText)
            return .variantRecord(PascalVariantRecordType(
                isPacked: isPacked,
                fixedFields: fixed,
                variantBody: variantText
            ))
        }
        let fields = parseRecordFields(body)
        if fields.isEmpty {
            return .record(PascalRecordType(isPacked: isPacked, rawBody: body))
        }
        return .record(PascalRecordType(isPacked: isPacked, fields: fields))
    }

    private func parseRecordFields(_ body: String) -> [PascalRecordField] {
        splitTopLevel(body, separator: ";").compactMap { declaration in
            let pieces = splitTopLevel(declaration, separator: ":")
            guard pieces.count == 2 else { return nil }
            let names = splitTopLevel(pieces[0], separator: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            }
            guard !names.isEmpty, names.allSatisfy(isIdentifier) else { return nil }
            return PascalRecordField(names: names, type: PascalType.parse(pieces[1]))
        }
    }

    private func startsWithWords(_ words: [String]) -> Bool {
        upper.startsWithWords(words)
    }

    private func matchingBracket(in text: String) -> Int? {
        var depth = 0
        for (offset, ch) in text.enumerated() {
            if ch == "[" {
                depth += 1
            } else if ch == "]" {
                depth -= 1
                if depth == 0 {
                    return offset
                }
            }
        }
        return nil
    }

    private func splitTopLevel(_ text: String, separator: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var parenDepth = 0
        var bracketDepth = 0
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "(" {
                parenDepth += 1
            } else if text[index] == ")" {
                parenDepth -= 1
            } else if text[index] == "[" {
                bracketDepth += 1
            } else if text[index] == "]" {
                bracketDepth -= 1
            }

            if parenDepth == 0,
               bracketDepth == 0,
               text[index...].hasPrefix(separator)
            {
                parts.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
                index = text.index(index, offsetBy: separator.count)
                continue
            }

            current.append(text[index])
            index = text.index(after: index)
        }
        parts.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        return parts.filter { !$0.isEmpty }
    }

    private func isIdentifier(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        guard let first = text.unicodeScalars.first,
              CharacterSet.letters.contains(first) || first.value == 0x5F
        else {
            return false
        }
        return text.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0.value == 0x5F
        }
    }

    static func collapseWhitespace(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    func startsWithWords(_ words: [String]) -> Bool {
        var remainder = self[...]
        for word in words {
            remainder = remainder.drop(while: { $0.isWhitespace })
            guard remainder.uppercased().hasPrefix(word) else { return false }
            let afterWord = remainder.index(remainder.startIndex, offsetBy: word.count)
            if afterWord < remainder.endIndex,
               let scalar = remainder[afterWord].unicodeScalars.first,
               CharacterSet.alphanumerics.contains(scalar) || scalar.value == 0x5F
            {
                return false
            }
            remainder = remainder[afterWord...]
        }
        return true
    }

    func dropLeadingWords(_ words: [String]) -> String {
        var remainder = self[...]
        for word in words {
            remainder = remainder.drop(while: { $0.isWhitespace })
            guard remainder.uppercased().hasPrefix(word) else { break }
            let afterWord = remainder.index(remainder.startIndex, offsetBy: word.count)
            remainder = remainder[afterWord...]
        }
        return String(remainder)
    }

    func prefixBeforeTopLevelWord(_ word: String) -> Substring {
        let upper = self.uppercased()
        guard let range = upper.range(of: word) else { return self[...] }
        let distance = upper.distance(from: upper.startIndex, to: range.lowerBound)
        let end = self.index(self.startIndex, offsetBy: distance)
        return self[..<end]
    }
}
