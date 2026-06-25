import Foundation

struct PascalSetElement: Equatable {
    var lower: String
    var upper: String?

    init(_ value: String) {
        self.lower = value
        self.upper = nil
    }

    init(lower: String, upper: String) {
        self.lower = lower
        self.upper = upper
    }

    var sourceText: String {
        if let upper {
            return "\(lower)..\(upper)"
        }
        return lower
    }
}

struct PascalSetWordFragment: Equatable {
    var baseText: String
    var wordIndex: Int?
    var text: String
}

struct PascalSetValue: Equatable {
    var wordCount: Int
    var elements: [PascalSetElement]
    var wordFragments: [PascalSetWordFragment]
    var expressionText: String?
    var malformedMessage: String?
    var legacyWrapsElements: Bool

    var isMalformed: Bool {
        malformedMessage != nil
    }

    var isLiteral: Bool {
        !isMalformed && expressionText == nil && wordFragments.isEmpty
    }

    var sourceText: String {
        if let malformedMessage {
            return malformedMessage
        }
        if let expressionText {
            return expressionText
        }
        if !elements.isEmpty {
            return "[" + elements.map(\.sourceText).joined(separator: ", ") + "]"
        }
        if wordFragments.isEmpty {
            return "[]"
        }
        return uniqueFragmentBases().joined(separator: ", ")
    }

    var legacyText: String {
        if let malformedMessage {
            return malformedMessage
        }
        if let expressionText {
            return expressionText
        }
        if !elements.isEmpty {
            let body = elements.map(\.sourceText).joined(separator: ", ")
            return legacyWrapsElements ? "[\(body)]" : body
        }
        if wordFragments.isEmpty {
            return "[]"
        }
        return uniqueFragmentBases().joined(separator: ", ")
    }

    static var empty: PascalSetValue {
        PascalSetValue(
            wordCount: 0,
            elements: [],
            wordFragments: [],
            expressionText: nil,
            malformedMessage: nil,
            legacyWrapsElements: true
        )
    }

    static func malformed(_ message: String) -> PascalSetValue {
        PascalSetValue(
            wordCount: 0,
            elements: [],
            wordFragments: [],
            expressionText: nil,
            malformedMessage: message,
            legacyWrapsElements: false
        )
    }

    static func literal(_ elements: [PascalSetElement], wordCount: Int = 1) -> PascalSetValue {
        PascalSetValue(
            wordCount: wordCount,
            elements: elements,
            wordFragments: [],
            expressionText: nil,
            malformedMessage: nil,
            legacyWrapsElements: true
        )
    }

    static func expression(_ text: String, wordCount: Int) -> PascalSetValue {
        PascalSetValue(
            wordCount: wordCount,
            elements: [],
            wordFragments: [],
            expressionText: text,
            malformedMessage: nil,
            legacyWrapsElements: false
        )
    }

    static func fromLegacyWords(wordCount: Int, words: [String]) -> PascalSetValue {
        guard wordCount > 0 else {
            return .empty
        }

        var symbolicElements: [PascalSetElement] = []
        var numericValues: [Int] = []
        var fragments: [PascalSetWordFragment] = []

        for (wordIndex, word) in words.enumerated() {
            if let fragment = parseLegacyWordFragment(word) {
                fragments.append(PascalSetWordFragment(
                    baseText: fragment.base,
                    wordIndex: fragment.index,
                    text: word
                ))
                continue
            }

            if let value = UInt64(word) {
                for bitIndex in 0..<16 where (value >> bitIndex) & 1 == 1 {
                    numericValues.append(wordIndex * 16 + bitIndex)
                }
                continue
            }

            symbolicElements.append(PascalSetElement(word))
        }

        let numericElements = ranges(for: numericValues)
        return PascalSetValue(
            wordCount: wordCount,
            elements: symbolicElements + numericElements,
            wordFragments: fragments,
            expressionText: nil,
            malformedMessage: nil,
            legacyWrapsElements: !numericElements.isEmpty
        )
    }

    func union(_ other: PascalSetValue) -> PascalSetValue {
        combine(other, operatorText: "+") { lhs, rhs in
            lhs.union(rhs)
        } literalFallback: { lhs, rhs in
            PascalSetValue.literal(
                PascalSetValue.deduplicated(lhs.elements + rhs.elements),
                wordCount: max(lhs.wordCount, rhs.wordCount)
            )
        }
    }

    func intersection(_ other: PascalSetValue) -> PascalSetValue {
        combine(other, operatorText: "*") { lhs, rhs in
            lhs.intersection(rhs)
        } literalFallback: { lhs, rhs in
            PascalSetValue.expression(
                "\(lhs.sourceText) * \(rhs.sourceText)",
                wordCount: max(lhs.wordCount, rhs.wordCount)
            )
        }
    }

    func difference(_ other: PascalSetValue) -> PascalSetValue {
        combine(other, operatorText: "-") { lhs, rhs in
            lhs.subtracting(rhs)
        } literalFallback: { lhs, rhs in
            PascalSetValue.expression(
                "\(lhs.sourceText) - \(rhs.sourceText)",
                wordCount: max(lhs.wordCount, rhs.wordCount)
            )
        }
    }

    private func combine(
        _ other: PascalSetValue,
        operatorText: String,
        numericOperation: (Set<Int>, Set<Int>) -> Set<Int>,
        literalFallback: (PascalSetValue, PascalSetValue) -> PascalSetValue
    ) -> PascalSetValue {
        if isMalformed {
            return self
        }
        if other.isMalformed {
            return other
        }

        let wordCount = max(self.wordCount, other.wordCount)
        if let lhs = integerElements(), let rhs = other.integerElements() {
            return PascalSetValue.fromIntegerElements(numericOperation(lhs, rhs), wordCount: wordCount)
        }

        if self.isLiteral && other.isLiteral {
            return literalFallback(self, other)
        }

        return PascalSetValue.expression(
            "\(sourceText) \(operatorText) \(other.sourceText) (* raw set word operation *)",
            wordCount: wordCount
        )
    }

    private func integerElements() -> Set<Int>? {
        guard isLiteral else {
            return nil
        }

        var values = Set<Int>()
        for element in elements {
            guard let lower = Int(element.lower) else {
                return nil
            }
            if let upperText = element.upper {
                guard let upper = Int(upperText) else {
                    return nil
                }
                guard lower <= upper else {
                    return nil
                }
                for value in lower...upper {
                    values.insert(value)
                }
            } else {
                values.insert(lower)
            }
        }
        return values
    }

    private static func fromIntegerElements(_ values: Set<Int>, wordCount: Int) -> PascalSetValue {
        PascalSetValue.literal(ranges(for: Array(values)), wordCount: wordCount)
    }

    private static func deduplicated(_ elements: [PascalSetElement]) -> [PascalSetElement] {
        var seen: Set<String> = []
        var result: [PascalSetElement] = []
        for element in elements {
            let key = element.sourceText
            guard !seen.contains(key) else {
                continue
            }
            seen.insert(key)
            result.append(element)
        }
        return result
    }

    private func uniqueFragmentBases() -> [String] {
        var seen: Set<String> = []
        var bases: [String] = []
        for fragment in wordFragments where !seen.contains(fragment.baseText) {
            seen.insert(fragment.baseText)
            bases.append(fragment.baseText)
        }
        return bases
    }

    private static func ranges(for values: [Int]) -> [PascalSetElement] {
        let sortedValues = Array(Set(values)).sorted()
        var result: [PascalSetElement] = []
        var index = sortedValues.startIndex

        while index < sortedValues.endIndex {
            let start = sortedValues[index]
            var end = start
            var next = sortedValues.index(after: index)
            while next < sortedValues.endIndex && sortedValues[next] == end + 1 {
                end = sortedValues[next]
                next = sortedValues.index(after: next)
            }

            if start == end {
                result.append(PascalSetElement("\(start)"))
            } else {
                result.append(PascalSetElement(lower: "\(start)", upper: "\(end)"))
            }
            index = next
        }

        return result
    }

    private static func parseLegacyWordFragment(_ word: String) -> (base: String, index: Int?)? {
        guard let openBrace = word.lastIndex(of: "{"),
              word.hasSuffix("}")
        else {
            return nil
        }

        let base = String(word[..<openBrace])
        let indexStart = word.index(after: openBrace)
        let indexEnd = word.index(before: word.endIndex)
        let indexText = word[indexStart..<indexEnd]
        return (base, Int(indexText))
    }
}
