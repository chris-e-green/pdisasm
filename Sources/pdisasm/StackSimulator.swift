import Foundation

// MARK: - Stack Simulator

enum StackValueKind: String {
    case value
    case address
    case pointer
    case constant
    case expression

    var displayCode: String {
        switch self {
        case .value: return "v"
        case .address: return "a"
        case .pointer: return "p"
        case .constant: return "c"
        case .expression: return "e"
        }
    }
}

enum StackValuePayload {
    case none
    case realWord(
        baseText: String,
        wordIndex: Int,
        baseLocation: Location?,
        physicalLocation: Location?
    )

    var realWord: (
        baseText: String,
        wordIndex: Int,
        baseLocation: Location?,
        physicalLocation: Location?
    )? {
        switch self {
        case .none:
            return nil
        case let .realWord(baseText, wordIndex, baseLocation, physicalLocation):
            return (baseText, wordIndex, baseLocation, physicalLocation)
        }
    }
}

struct StackValue {
    var text: String
    var type: String?
    var kind: StackValueKind
    var location: Location?
    var payload: StackValuePayload = .none

    var encodedType: String {
        type ?? "UNKNOWN"
    }

    var isAddressLike: Bool {
        kind == .address || kind == .pointer
    }

//    var isValueLike: Bool {
//        kind == .value || kind == .constant || kind == .expression
//    }

    var stackDescription: String {
        var fields = ["V: \(text)"]
        if let type, !type.isEmpty {
            fields.append("T: \(type)")
        }
        fields.append("K: \(kind.displayCode)")
        if let location {
            fields.append("L: \(location.displayName)")
        }
        if let realWord = payload.realWord {
            fields.append("R: \(realWord.baseText)#\(realWord.wordIndex)")
        }
        return "{" + fields.joined(separator: ", ") + "}"
    }
}

/// Manages the symbolic execution stack during P-code decoding
struct StackSimulator {
    let sep = "~"
    let ptr = "@"
    var values: [StackValue] = []

    var stack: [String] {
        get {
            values.map(encodeStackValue)
        }
        set {
            values = newValue.map(decodeStackValue)
        }
    }

    var stackDescription: [String] {
        values.map(\.stackDescription)
    }

//    func prettyStack() -> String {
//        "[" + stackDescription.joined(separator: ", ") + "]"
//    }

    private func encodeStackValue(_ value: StackValue) -> String {
        "\(value.text)\(sep)\(value.encodedType)"
    }

    private func decodeStackValue(_ encoded: String) -> StackValue {
        if encoded.contains(sep) {
            var parts = encoded.split(separator: sep, maxSplits: 1)
            if parts.count < 2 {
                parts.append("UNKNOWN")
            }
            let encodedType = String(parts[1])
            return StackValue(
                text: String(parts[0]),
                type: encodedType.hasPrefix(ptr)
                    ? String(encodedType.dropFirst())
                    : encodedType,
                kind: encodedType.hasPrefix(ptr) ? .pointer : .value
            )
        }

        return StackValue(text: encoded, type: nil, kind: .value)
    }

    mutating func push(
        _ value: (val: String, type: String?),
        isPointer: Bool = false,
        kind: StackValueKind? = nil,
        location: Location? = nil
    ) {
        let valueKind = kind ?? (isPointer ? .address : .value)
        values.append(StackValue(
            text: value.val,
            type: value.type ?? "UNKNOWN",
            kind: valueKind,
            location: location
        ))
    }

    mutating func push(_ value: StackValue) {
        values.append(value)
    }

    mutating func popStackValue() -> StackValue {
        values.popLast() ?? StackValue(text: "underflow!", type: nil, kind: .value)
    }

    func peekStackValue(_ at: Int = 0) -> StackValue {
        let pos = values.endIndex - at - 1
        if pos < values.startIndex || pos >= values.endIndex {
            return StackValue(text: "underflow!", type: nil, kind: .value)
        }
        return values[pos]
    }

    func parenthesizedText(_ value: StackValue, withoutParentheses: Bool = false) -> String {
        if withoutParentheses {
            return value.text
        }
        if value.text.hasPrefix("*(") {
            return value.text
        }
        return value.text.contains(" ") && value.type != "STRING" ? "(\(value.text))" : value.text
    }

    func assignmentTargetText(_ value: StackValue) -> String {
        if value.kind == .pointer {
            return "*(\(parenthesizedText(value)))"
        }
        return parenthesizedText(value)
    }

    func assignmentSourceText(_ value: StackValue, withoutParentheses: Bool = false) -> String {
        parenthesizedText(value, withoutParentheses: withoutParentheses)
    }

    func derivedAddressKind(from value: StackValue) -> StackValueKind {
        value.isAddressLike || value.type == "POINTER" ? .address : value.kind
    }

    func realWordValue(
        base: StackValue,
        wordIndex: Int,
        physicalLocation: Location?
    ) -> StackValue {
        let baseText = parenthesizedText(base)
        return StackValue(
            text: "REAL_WORD(\(baseText), \(wordIndex))",
            type: "INTEGER",
            kind: .value,
            location: physicalLocation,
            payload: .realWord(
                baseText: baseText,
                wordIndex: wordIndex,
                baseLocation: base.location,
                physicalLocation: physicalLocation
            )
        )
    }

    func realRepresentationBaseName(_ text: String) -> String? {
        realRepresentationWord(text)?.base
    }

    func realRepresentationBaseName(_ value: StackValue) -> String? {
        if let realWord = value.payload.realWord {
            return realWord.baseLocation?.displayName ?? realWord.baseText
        }
        return realRepresentationBaseName(value.text)
    }

    func realRepresentationWord(_ text: String) -> (base: String, offset: Int)? {
        guard text.hasPrefix("REAL_WORD("), text.hasSuffix(")") else {
            return nil
        }
        let bodyStart = text.index(text.startIndex, offsetBy: "REAL_WORD(".count)
        let bodyEnd = text.index(before: text.endIndex)
        let body = text[bodyStart..<bodyEnd]
        guard let comma = body.lastIndex(of: ",") else {
            return nil
        }
        let base = String(body[..<comma]).trimmingCharacters(in: .whitespacesAndNewlines)
        let offsetText = body[body.index(after: comma)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let offset = Int(offsetText) else {
            return nil
        }
        return (base, offset)
    }

    func realRepresentationWord(_ value: StackValue) -> (base: String, offset: Int)? {
        if let realWord = value.payload.realWord {
            return (
                realWord.baseLocation?.displayName ?? realWord.baseText,
                realWord.wordIndex
            )
        }
        return realRepresentationWord(value.text)
    }

    func realRepresentationStorageBaseName(_ text: String) -> String? {
        guard let word = realRepresentationWord(text) else {
            return nil
        }
        guard word.offset != 0 else {
            return word.base
        }
        let location = Location(from: word.base)
        guard let address = location.addr else {
            return word.base
        }
        location.addr = address - word.offset
        return location.displayName
    }

    func realRepresentationStorageBaseName(_ value: StackValue) -> String? {
        if let realWord = value.payload.realWord {
            return realWord.baseLocation?.displayName ?? realWord.baseText
        }
        if let baseName = realRepresentationStorageBaseName(value.text) {
            return baseName
        }
        return nil
    }

    func realRepresentationPairBaseName(_ a: StackValue, _ b: StackValue) -> String? {
        guard let aWord = realRepresentationWord(a),
            let bWord = realRepresentationWord(b)
        else {
            return nil
        }

        let offsets = Set([aWord.offset, bWord.offset])
        guard offsets == Set([0, 1]) else {
            return nil
        }

        if aWord.base == bWord.base {
            return aWord.base
        }

        let aBase = realRepresentationStorageBaseName(a)
        let bBase = realRepresentationStorageBaseName(b)
        return aBase == bBase ? aBase : nil
    }

//    mutating func pushReal(_ value: String, isPointer: Bool = false) {
//        stack.append("\(value)\(sep)REAL")
//    }

    @discardableResult
    /// Pops the top of the stack and any datatype. If the type
    /// of the popped value is not defined, it uses the provided type
    /// and (if it refers to a memory location) corrects the type of
    /// the variable at that location.
    /// - Parameters:
    ///   - type: the type to use if the popped value is UNKNOWN
    ///   - withoutParentheses: whether to return the value without parentheses
    /// - Returns: a tuple of the popped value and its type (if any)
    mutating func pop(_ type: String, _ withoutParentheses: Bool = false) -> (
        val: String, type: String?
    ) {
        let value = popStackValue()
        var locType = value.type ?? type
        if locType == "UNKNOWN" {
            locType = type
        }
        return (parenthesizedText(
            StackValue(text: value.text, type: locType, kind: value.kind, location: value.location),
            withoutParentheses: withoutParentheses
        ), locType)
    }

    @discardableResult
    /// Pops the top of the stack and any datatype
    ///
    /// - Parameter withoutParentheses: whether to return the value without parentheses
    /// - Returns: a tuple of the popped value and its type (if any)
    mutating func pop(_ withoutParentheses: Bool = false) -> (val: String, type: String?) {
        let value = popStackValue()
        return (parenthesizedText(value, withoutParentheses: withoutParentheses), value.type)
    }

    @discardableResult
    /// Gets the top of the stack and any datatype without changing the stack
    ///
    /// - Parameter at: the index from the top of the stack to peek at (0 for top, 1 for second, etc.)
    /// - Parameter withoutParentheses: whether to return the value without parentheses
    /// - Returns: a tuple of the value at the top of the stack and its type (if any)
    func peek(_ at: Int = 0, _ withoutParentheses: Bool = false) -> (val: String, type: String?) {
        let value = peekStackValue(at)
        if value.text == "underflow!" {
            return ("underflow!", nil)
        }
        return (parenthesizedText(value, withoutParentheses: withoutParentheses), value.type)
    }

    @discardableResult
    /// Pops the top of the stack as a REAL value.
    /// - Returns: a tuple with the REAL value and the 'REAL' type
    mutating func popReal() -> (val: String, type: String?) {
        let a = popStackValue()
        if a.type == "REAL" {
            return (a.text, "REAL")
        }

        let b = popStackValue()
        if let val1 = UInt16(a.text), let val2 = UInt16(b.text) {
            let rv = Float(bitPattern: UInt32(val1) | UInt32(val2) << 16)
            return ("\(rv)", "REAL")
        }

        if a.type != nil || b.type != nil {
            if let pairName = realRepresentationPairBaseName(a, b) {
                return (pairName, "REAL")
            }
            let name = realRepresentationStorageBaseName(a) ?? String(a.text.split(separator: "{", maxSplits: 1)[0])
            let bName = realRepresentationStorageBaseName(b) ?? String(b.text.split(separator: "{", maxSplits: 1)[0])
            if name != bName {
                print(
                    "Warning: expected matching names for REAL parts, got '\(name)' and '\(bName)'"
                )
                return ("\(a.text).\(b.text)", "REAL")
            } else {
                return ("\(name)", "REAL")
            }
        } else {
            return ("\(a.text).\(b.text)", "REAL")
        }
    }

    @discardableResult
    /// Pops the top of the stack as a SET value.
    /// - Returns: a tuple with the length of the set and its string representation
    mutating func popSet() -> (len: Int, val: String) {
        let (setLen, _) = self.pop()
        var isNumeric = false // flag to track if we have numeric values in the set
        // to hold string set values
        var setData: [String] = []
        // to hold numeric set values
        var setVals: [Int] = []
        var prevElement: String = ""
        // if the set length is an integer, it's valid
        if let len = Int(setLen) {
            if len == 0 { // special case for empty set
                return (0, "[]")
            }
            // for each element in the set
            for i in 0..<len {
                // pop the element
                let (element, _) = self.pop(true)
                // we use '{' to indicate words within an array of elements
                // eg. SETDATA{0}, SETDATA{1}, ... so that counting the words
                // on the stack still works
                if !element.contains("{") {
                    // if the element is an integer, we extract the bits set
                    // and add the corresponding values to the numeric set values
                    if let value = UInt64(element) {
                        for j in 0..<16 {
                            if (value >> j) & 1 == 1 {
                                setVals.append(i * 16 + j)
                            }
                        }
                    } else {
                        // otherwise, we just add the element
                        setData.append(element)
                    }
                } else {
                    // if the element is part of an array, we only add the array name
                    let elementParts = element.split(separator: "{")
                    if String(elementParts[0]) != prevElement {
                        prevElement = String(elementParts[0])
                        setData.append(String(elementParts[0]))
                    }
                }
            }
            if !setVals.isEmpty {
                isNumeric = true
            }

            // if we have numeric set values, we convert them to ranges
            while !setVals.isEmpty {
                let first = setVals.first!  // we can force unwrap as we checked above
                // group consecutive values
                let group = setVals.prefix(while: {
                    $0 == setVals.first! + (setVals.firstIndex(of: $0)!)
                        - (setVals.firstIndex(of: first)!)
                })
                // if the group has only one value, add it as is
                if group.count == 1 {
                    setData.append("\(group[0])")
                } else {
                    // otherwise, add it as a range
                    setData.append("\(group.first!)...\(group.last!)")
                }
                // remove the processed values from the setVals
                setVals = Array(setVals.dropFirst(group.count))
            }

            if isNumeric {
                return (len, "[" + setData.joined(separator: ", ") + "]")
            } else {
                return (len, setData.joined(separator: ", "))
            }
        }
        return (0, "Set has no length!")
    }
}
