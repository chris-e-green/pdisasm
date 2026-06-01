enum PseudoCodeStatement {
    case rendered(String)
    case assignment(target: Location, source: String, fallbackTarget: String)

    init(renderedText: String, locations: Set<Location>) {
        guard let separator = renderedText.range(of: " := ") else {
            self = .rendered(renderedText)
            return
        }

        let targetText = String(renderedText[..<separator.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceText = String(renderedText[separator.upperBound...])
        if let target = locations.first(where: { $0.displayName == targetText }) {
            self = .assignment(
                target: target,
                source: sourceText,
                fallbackTarget: targetText
            )
        } else {
            self = .rendered(renderedText)
        }
    }

    var renderedText: String {
        switch self {
        case let .rendered(text):
            return text
        case let .assignment(target, source, fallbackTarget):
            let targetText = target.displayName.isEmpty
                ? fallbackTarget
                : target.displayName
            return "\(targetText) := \(source)"
        }
    }
}
