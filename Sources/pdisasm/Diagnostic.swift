public enum DiagnosticSeverity: String, Codable, Sendable {
    case warning
    case error
}

public struct Diagnostic: Codable, Hashable, Sendable {
    public var severity: DiagnosticSeverity
    public var message: String

    public init(severity: DiagnosticSeverity, message: String) {
        self.severity = severity
        self.message = message
    }
}

final class DiagnosticCollector {
    private(set) var diagnostics: [Diagnostic] = []

    func warning(_ message: String) {
        diagnostics.append(Diagnostic(severity: .warning, message: message))
    }

    func error(_ message: String) {
        diagnostics.append(Diagnostic(severity: .error, message: message))
    }
}
