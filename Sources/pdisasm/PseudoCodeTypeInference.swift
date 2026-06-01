import Foundation

extension PseudoCodeGenerator {
    mutating func setLocType(_ location: Location?, _ type: String, evidence: String = "") {
        guard let location else { return }
        let found = allLocations.first(where: { $0 == location }) ?? location
        if let conflict = found.assignType(type, source: .inferred, evidence: evidence) {
            typeConflicts.append(conflict)
        }
        allLocations.update(with: found)
    }

    mutating func setLocType(_ locStr: String, _ type: String, evidence: String = "") {
        if locStr.contains(/^S[0-9]+_P[0-9]+(_L[0-9]+)?_A[0-9]+$/) {
            let location = Location(from: locStr)
            setLocType(location, type, evidence: evidence)
        }
    }

    mutating func inferStackValueType(_ value: StackValue, _ type: String, evidence: String = "") {
        if let location = value.location {
            setLocType(location, type, evidence: evidence)
        } else {
            setLocType(value.text, type, evidence: evidence)
        }
    }

    func typedOperandText(_ value: StackValue, _ type: String, stack: StackSimulator) -> String {
        var operandType = value.type ?? type
        if operandType == "UNKNOWN" {
            operandType = type
        }
        return stack.parenthesizedText(StackValue(
            text: value.text,
            type: operandType,
            kind: value.kind,
            location: value.location
        ))
    }

    mutating func inferRealOperand(_ stack: StackSimulator, evidence: String = "") {
        let value = stack.peekStackValue()
        if value.type == "REAL" {
            inferStackValueType(value, "REAL", evidence: evidence)
            return
        }

        let nextValue = stack.peekStackValue(1)
        inferRealRepresentationType(value, evidence: evidence)
        inferRealRepresentationType(nextValue, evidence: evidence)
        inferRealAggregatePairType(value, nextValue, evidence: evidence)
    }

    mutating func inferRealRepresentationType(_ value: StackValue, evidence: String = "") {
        if let realWord = value.payload.realWord {
            if let baseLocation = realWord.baseLocation {
                setLocType(baseLocation, "REAL", evidence: evidence)
            } else {
                setLocType(realWord.baseText, "REAL", evidence: evidence)
            }
            return
        }

        if let baseName = StackSimulator().realRepresentationStorageBaseName(value) {
            setLocType(baseName, "REAL", evidence: evidence)
        }
    }

    func aggregateWord(_ value: StackValue) -> (base: String, offset: Int)? {
        guard value.text.hasSuffix("}") else {
            return nil
        }
        guard let openBrace = value.text.lastIndex(of: "{") else {
            return nil
        }
        let base = String(value.text[..<openBrace])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let offsetStart = value.text.index(after: openBrace)
        let offsetEnd = value.text.index(before: value.text.endIndex)
        let offsetText = value.text[offsetStart..<offsetEnd]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, let offset = Int(offsetText) else {
            return nil
        }
        return (base, offset)
    }

    mutating func inferRealAggregatePairType(
        _ value: StackValue,
        _ nextValue: StackValue,
        evidence: String = ""
    ) {
        guard let word = aggregateWord(value),
            let nextWord = aggregateWord(nextValue),
            word.base == nextWord.base,
            Set([word.offset, nextWord.offset]) == Set([0, 1])
        else {
            return
        }

        if let location = value.location ?? nextValue.location {
            setLocType(location, "REAL", evidence: evidence)
            return
        }

        if let location = allLocations.first(where: { $0.displayName == word.base }) {
            setLocType(location, "REAL", evidence: evidence)
        } else {
            setLocType(word.base, "REAL", evidence: evidence)
        }
    }

    func isRealAggregatePair(_ value: StackValue, _ nextValue: StackValue) -> Bool {
        guard let word = aggregateWord(value),
            let nextWord = aggregateWord(nextValue),
            word.base == nextWord.base,
            Set([word.offset, nextWord.offset]) == Set([0, 1])
        else {
            return false
        }
        return true
    }

    mutating func popRealOperand(
        _ stack: inout StackSimulator,
        evidence: String
    ) -> (val: String, type: String?) {
        let value = stack.peekStackValue()
        if value.kind == .expression
            && (value.type == nil || value.type == "UNKNOWN")
        {
            let popped = stack.popStackValue()
            inferStackValueType(popped, "REAL", evidence: evidence)
            return (
                stack.assignmentSourceText(StackValue(
                    text: popped.text,
                    type: "REAL",
                    kind: popped.kind,
                    location: popped.location,
                    payload: popped.payload
                ), withoutParentheses: true),
                "REAL"
            )
        }

        let result = stack.popReal()
        setLocType(result.val, "REAL", evidence: evidence)
        return result
    }

    func representationWordText(
        _ base: StackValue,
        offset: String,
        stack: StackSimulator
    ) -> String {
        if base.type == "REAL" {
            return "REAL_WORD(\(stack.parenthesizedText(base)), \(offset))"
        }
        return "*(\(stack.parenthesizedText(base)) + \(offset))"
    }

    func representationWordLocation(
        _ base: StackValue,
        offset: String
    ) -> Location? {
        let trimmedOffset = offset.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let offsetValue = Int(trimmedOffset),
            offsetValue != 0,
            let location = base.location,
            let address = location.addr
        else {
            return base.location
        }

        return Location(
            segment: location.segment,
            procedure: location.procedure,
            lexLevel: location.lexLevel,
            addr: address + offsetValue
        )
    }

    func representationWordValue(
        _ base: StackValue,
        offset: Int,
        stack: StackSimulator
    ) -> StackValue {
        stack.realWordValue(
            base: base,
            wordIndex: offset,
            physicalLocation: representationWordLocation(base, offset: "\(offset)")
        )
    }

    func representationByteText(
        _ base: StackValue,
        offset: String,
        stack: StackSimulator
    ) -> String {
        if base.type == "REAL" {
            return "REAL_BYTE(\(stack.parenthesizedText(base)), \(offset))"
        }
        return "\(stack.parenthesizedText(base))[\(offset)]"
    }

    func representationBitsText(
        _ base: StackValue,
        width: String,
        bit: String,
        stack: StackSimulator
    ) -> String {
        if base.type == "REAL" {
            return "REAL_BITS(\(stack.parenthesizedText(base)), \(width), \(bit))"
        }
        return "\(stack.parenthesizedText(base)):\(width):\(bit)"
    }
}
