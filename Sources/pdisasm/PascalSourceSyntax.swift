import Foundation

private let pascalKeywords: Set<String> = [
    "AND", "ARRAY", "BEGIN", "CASE", "CONST", "DIV", "DO", "DOWNTO", "ELSE",
    "END", "FILE", "FOR", "FUNCTION", "GOTO", "IF", "IN", "LABEL", "MOD",
    "NIL", "NOT", "OF", "OR", "OTHERWISE", "PACKED", "PROCEDURE", "PROGRAM",
    "RECORD", "REPEAT", "SET", "THEN", "TO", "TYPE", "UNTIL", "VAR", "WHILE",
    "WITH", "UNIT", "INTERFACE", "IMPLEMENTATION", "USES"
]

func renderPascalCharLiteral(_ value: Int) -> String {
    guard value >= 0x20 && value <= 0x7E,
          let scalar = UnicodeScalar(value)
    else {
        return "CHR(\(value))"
    }

    let character = String(Character(scalar))
    return "'" + character.replacingOccurrences(of: "'", with: "''") + "'"
}

func renderPascalCharLiteral(_ value: String) -> String {
    let scalars = Array(value.unicodeScalars)
    guard scalars.count == 1 else {
        return renderPascalStringLiteral(value)
    }
    return renderPascalCharLiteral(Int(scalars[0].value))
}

func renderPascalStringLiteral(_ value: String) -> String {
    if value.isEmpty { return "''" }

    var parts: [String] = []
    var literalBuffer = ""

    func flushLiteralBuffer() {
        guard !literalBuffer.isEmpty else { return }
        parts.append("'" + literalBuffer.replacingOccurrences(of: "'", with: "''") + "'")
        literalBuffer = ""
    }

    for scalar in value.unicodeScalars {
        let code = Int(scalar.value)
        if code >= 0x20 && code <= 0x7E {
            literalBuffer.append(Character(scalar))
        } else {
            flushLiteralBuffer()
            parts.append("CHR(\(code))")
        }
    }
    flushLiteralBuffer()

    return parts.joined(separator: " + ")
}

func isValidPascalIdentifier(_ name: String) -> Bool {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    guard let first = trimmed.unicodeScalars.first,
          CharacterSet.letters.contains(first) || first.value == 0x5F
    else {
        return false
    }
    return trimmed.unicodeScalars.allSatisfy {
        CharacterSet.alphanumerics.contains($0) || $0.value == 0x5F
    }
}

func renderPascalIdentifier(_ name: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "_" }

    var rendered = ""
    for scalar in trimmed.unicodeScalars {
        if CharacterSet.alphanumerics.contains(scalar) || scalar.value == 0x5F {
            rendered.append(Character(scalar))
        } else {
            rendered.append("_")
        }
    }

    if let first = rendered.unicodeScalars.first,
       !(CharacterSet.letters.contains(first) || first.value == 0x5F) {
        rendered = "_" + rendered
    }

    if pascalKeywords.contains(rendered.uppercased()) {
        rendered += "_"
    }

    return rendered.isEmpty ? "_" : rendered
}

enum PascalBinaryOperator: String, Sendable {
    case multiply = "*"
    case realDivide = "/"
    case integerDivide = "DIV"
    case modulo = "MOD"
    case add = "+"
    case subtract = "-"
    case equals = "="
    case notEquals = "<>"
    case lessThan = "<"
    case lessThanOrEqual = "<="
    case greaterThan = ">"
    case greaterThanOrEqual = ">="
    case and = "AND"
    case or = "OR"
    case `in` = "IN"

    var precedence: Int {
        switch self {
        case .multiply, .realDivide, .integerDivide, .modulo, .and:
            return 40
        case .add, .subtract, .or:
            return 30
        case .equals, .notEquals, .lessThan, .lessThanOrEqual, .greaterThan, .greaterThanOrEqual, .in:
            return 20
        }
    }
}

enum PascalUnaryOperator: String, Sendable {
    case negate = "-"
    case not = "NOT"

    var precedence: Int { 50 }
}

indirect enum PascalExpr: Sendable {
    case identifier(String)
    case integer(Int)
    case real(String)
    case character(String)
    case string(String)
    case boolean(Bool)
    case nilPointer
    case unary(PascalUnaryOperator, PascalExpr)
    case binary(PascalBinaryOperator, PascalExpr, PascalExpr)
    case call(name: String, arguments: [PascalExpr])
    case index(base: PascalExpr, index: PascalExpr)
    case field(base: PascalExpr, name: String)
    case dereference(PascalExpr)
    case addressOf(PascalExpr)
    case setLiteral([PascalExpr])
    case range(PascalExpr, PascalExpr)
    case raw(String)

    func rendered() -> String {
        render(parentPrecedence: 0, isRightChild: false)
    }

    private var precedence: Int {
        switch self {
        case .binary(let op, _, _): return op.precedence
        case .unary(let op, _): return op.precedence
        case .call, .index, .field, .dereference, .addressOf: return 60
        case .range: return 10
        case .identifier, .integer, .real, .character, .string, .boolean, .nilPointer, .setLiteral, .raw:
            return 100
        }
    }

    private func render(parentPrecedence: Int, isRightChild: Bool) -> String {
        let ownPrecedence = precedence
        let text: String
        switch self {
        case .identifier(let name):
            text = renderPascalIdentifier(name)
        case .integer(let value):
            text = String(value)
        case .real(let value):
            text = value
        case .character(let value):
            text = renderPascalCharLiteral(value)
        case .string(let value):
            text = renderPascalStringLiteral(value)
        case .boolean(let value):
            text = value ? "TRUE" : "FALSE"
        case .nilPointer:
            text = "NIL"
        case .unary(let op, let expr):
            let operand = expr.render(parentPrecedence: op.precedence, isRightChild: true)
            switch op {
            case .negate: text = "-\(operand)"
            case .not: text = "NOT \(operand)"
            }
        case .binary(let op, let lhs, let rhs):
            let left = lhs.render(parentPrecedence: op.precedence, isRightChild: false)
            let right = rhs.render(parentPrecedence: op.precedence, isRightChild: true)
            text = "\(left) \(op.rawValue) \(right)"
        case .call(let name, let arguments):
            text = "\(renderPascalIdentifier(name))(\(arguments.map { $0.rendered() }.joined(separator: ", ")))"
        case .index(let base, let index):
            text = "\(base.render(parentPrecedence: ownPrecedence, isRightChild: false))[\(index.rendered())]"
        case .field(let base, let name):
            text = "\(base.render(parentPrecedence: ownPrecedence, isRightChild: false)).\(renderPascalIdentifier(name))"
        case .dereference(let expr):
            text = "\(expr.render(parentPrecedence: ownPrecedence, isRightChild: false))^"
        case .addressOf(let expr):
            text = "@\(expr.render(parentPrecedence: ownPrecedence, isRightChild: false))"
        case .setLiteral(let elements):
            text = "[" + elements.map { $0.rendered() }.joined(separator: ", ") + "]"
        case .range(let lower, let upper):
            text = "\(lower.rendered())..\(upper.rendered())"
        case .raw(let rawText):
            text = rawText
        }

        let needsParens = ownPrecedence < parentPrecedence || (isRightChild && ownPrecedence == parentPrecedence)
        return needsParens ? "(\(text))" : text
    }
}

indirect enum PascalStmt: Sendable {
    case assignment(target: PascalExpr, source: PascalExpr)
    case call(name: String, arguments: [PascalExpr])
    case block([PascalStmt])
    case ifThen(condition: PascalExpr, thenBlock: PascalStmt)
    case ifElse(condition: PascalExpr, thenBlock: PascalStmt, elseBlock: PascalStmt)
    case whileDo(condition: PascalExpr, body: PascalStmt)
    case repeatUntil(body: [PascalStmt], condition: PascalExpr)
    case forLoop(variable: String, start: PascalExpr, limit: PascalExpr, direction: PascalForDirection, body: PascalStmt)
    case caseStatement(expression: PascalExpr, arms: [PascalCaseArm], defaultBody: [PascalStmt]?)
    case goto(label: String)
    case label(String, PascalStmt?)
    case raw(String)

    func rendered(indentation: Int = 0) -> [String] {
        let indent = String(repeating: " ", count: indentation)
        switch self {
        case .assignment(let target, let source):
            return ["\(indent)\(target.rendered()) := \(source.rendered());"]
        case .call(let name, let arguments):
            return ["\(indent)\(renderPascalIdentifier(name))(\(arguments.map { $0.rendered() }.joined(separator: ", ")));"]
        case .block(let statements):
            var lines = ["\(indent)BEGIN"]
            lines.append(contentsOf: statements.flatMap { $0.rendered(indentation: indentation + 2) })
            lines.append("\(indent)END")
            return lines
        case .ifThen(let condition, let thenBlock):
            return ["\(indent)IF \(condition.rendered()) THEN"] + thenBlock.rendered(indentation: indentation + 2)
        case .ifElse(let condition, let thenBlock, let elseBlock):
            return ["\(indent)IF \(condition.rendered()) THEN"] + thenBlock.rendered(indentation: indentation + 2) + ["\(indent)ELSE"] + elseBlock.rendered(indentation: indentation + 2)
        case .whileDo(let condition, let body):
            return ["\(indent)WHILE \(condition.rendered()) DO"] + body.rendered(indentation: indentation + 2)
        case .repeatUntil(let body, let condition):
            return ["\(indent)REPEAT"] + body.flatMap { $0.rendered(indentation: indentation + 2) } + ["\(indent)UNTIL \(condition.rendered());"]
        case .forLoop(let variable, let start, let limit, let direction, let body):
            return ["\(indent)FOR \(renderPascalIdentifier(variable)) := \(start.rendered()) \(direction.rawValue) \(limit.rendered()) DO"] + body.rendered(indentation: indentation + 2)
        case .caseStatement(let expression, let arms, let defaultBody):
            var lines = ["\(indent)CASE \(expression.rendered()) OF"]
            for arm in arms {
                lines.append("\(indent)  \(arm.labels.map { $0.rendered() }.joined(separator: ", ")):")
                lines.append(contentsOf: arm.body.flatMap { $0.rendered(indentation: indentation + 4) })
            }
            if let defaultBody {
                lines.append("\(indent)  OTHERWISE")
                lines.append(contentsOf: defaultBody.flatMap { $0.rendered(indentation: indentation + 4) })
            }
            lines.append("\(indent)END")
            return lines
        case .goto(let label):
            return ["\(indent)GOTO \(renderPascalIdentifier(label));"]
        case .label(let label, let statement):
            if let statement {
                return ["\(indent)\(renderPascalIdentifier(label)):"] + statement.rendered(indentation: indentation + 2)
            }
            return ["\(indent)\(renderPascalIdentifier(label)):"]
        case .raw(let text):
            return ["\(indent)\(PascalStmt.renderRaw(text))"]
        }
    }

    private static func renderRaw(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasSuffix(":") || trimmed.hasSuffix(";") || trimmed == "BEGIN" || trimmed == "END" || trimmed.starts(with: "END") || trimmed.starts(with: "ELSE") || trimmed.starts(with: "UNTIL") || trimmed.starts(with: "CASE") || trimmed.hasSuffix("BEGIN") {
            return trimmed
        }
        return "\(trimmed);"
    }
}

enum PascalForDirection: String, Sendable {
    case to = "TO"
    case downto = "DOWNTO"
}

struct PascalCaseArm: Sendable {
    var labels: [PascalExpr]
    var body: [PascalStmt]
}

struct PascalBlock: Sendable {
    var statements: [PascalStmt]

    func rendered(indentation: Int = 0) -> [String] {
        PascalStmt.block(statements).rendered(indentation: indentation)
    }
}

extension PseudoCodeStatement {
    var pascalSourceStatement: PascalStmt {
        pascalSourceStatement(functionResultStorage: nil, functionName: nil)
    }

    func pascalSourceStatement(
        functionResultStorage: FunctionResultStorage?,
        functionName: String?
    ) -> PascalStmt {
        switch self {
        case .rendered(let text):
            return .raw(text)
        case .assignment(let targetLocation, let targetText, let source):
            let isFunctionResult = targetLocation != nil
                && targetLocation == functionResultStorage?.baseLocation
            let target = if isFunctionResult, let functionName {
                functionName
            } else if targetLocation?.displayName.isEmpty == false {
                targetLocation?.displayName ?? targetText
            } else {
                targetText
            }
            return .assignment(target: .raw(target), source: .raw(source))
        }
    }
}
