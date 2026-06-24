import Foundation

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
            text = name
        case .integer(let value):
            text = String(value)
        case .real(let value):
            text = value
        case .character(let value):
            text = "'\(value.replacingOccurrences(of: "'", with: "''"))'"
        case .string(let value):
            text = "'\(value.replacingOccurrences(of: "'", with: "''"))'"
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
            text = "\(name)(\(arguments.map { $0.rendered() }.joined(separator: ", ")))"
        case .index(let base, let index):
            text = "\(base.render(parentPrecedence: ownPrecedence, isRightChild: false))[\(index.rendered())]"
        case .field(let base, let name):
            text = "\(base.render(parentPrecedence: ownPrecedence, isRightChild: false)).\(name)"
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
            return ["\(indent)\(name)(\(arguments.map { $0.rendered() }.joined(separator: ", ")));"]
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
            return ["\(indent)FOR \(variable) := \(start.rendered()) \(direction.rawValue) \(limit.rendered()) DO"] + body.rendered(indentation: indentation + 2)
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
            return ["\(indent)GOTO \(label);"]
        case .label(let label, let statement):
            if let statement {
                return ["\(indent)\(label):"] + statement.rendered(indentation: indentation + 2)
            }
            return ["\(indent)\(label):"]
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
        switch self {
        case .rendered(let text):
            return .raw(text)
        case .assignment(let targetLocation, let targetText, let source):
            let target = targetLocation?.displayName.isEmpty == false
                ? targetLocation?.displayName ?? targetText
                : targetText
            return .assignment(target: .raw(target), source: .raw(source))
        }
    }
}
