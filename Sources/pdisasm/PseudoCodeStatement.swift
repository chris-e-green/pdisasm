enum PseudoCodeStatement {
    case rendered(String)
    case assignment(targetLocation: Location?, targetText: String, source: String)

    init(renderedText: String, locations: Set<Location>) {
        guard let separator = renderedText.range(of: " := ") else {
            self = .rendered(renderedText)
            return
        }

        let targetText = String(renderedText[..<separator.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceText = String(renderedText[separator.upperBound...])
        self = .assignment(
            targetLocation: locations.first(where: { $0.displayName == targetText }),
            targetText: targetText,
            source: sourceText
        )
    }

    static func assignment(
        targetValue: StackValue,
        targetText: String,
        source: String
    ) -> PseudoCodeStatement {
        let targetLocation: Location? = targetValue.location?.displayName == targetText
            ? targetValue.location
            : nil
        return .assignment(
            targetLocation: targetLocation,
            targetText: targetText,
            source: source
        )
    }

    var renderedText: String {
        switch self {
        case let .rendered(text):
            return text
        case let .assignment(targetLocation, targetText, source):
            let renderedTarget = targetLocation?.displayName.isEmpty == false
                ? targetLocation?.displayName ?? targetText
                : targetText
            return "\(renderedTarget) := \(source)"
        }
    }
}
