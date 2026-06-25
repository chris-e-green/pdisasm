import Foundation
import Observation

@MainActor
@Observable
final class DisassemblyDisplayPresentation {
    var showMarkup: Bool = true { didSet { onVisibilityChanged?() } }
    var showPCode: Bool = true { didSet { onVisibilityChanged?() } }
    var showStackState: Bool = false { didSet { onStructureChanged?() } }
    var showPseudoCode: Bool = true { didSet { onVisibilityChanged?() } }
    var showVariables: Bool = true { didSet { onVisibilityChanged?() } }
    var verbose: Bool = false

    @ObservationIgnored var onVisibilityChanged: (() -> Void)?
    @ObservationIgnored var onStructureChanged: (() -> Void)?

    var summary: String {
        var enabled: [String] = []
        if showMarkup { enabled.append("Markup") }
        if showPCode { enabled.append("P-Code") }
        if showPseudoCode { enabled.append("Pseudocode") }
        if showVariables { enabled.append("Variables") }
        if showStackState { enabled.append("Stack") }
        if verbose { enabled.append("Verbose") }
        return enabled.isEmpty ? "No optional sections" : enabled.joined(separator: ", ")
    }
}

struct SegmentPresentationItem: Identifiable {
    let id: Int
    let name: String
    let procedures: [ProcedurePresentationItem]
}

struct ProcedurePresentationItem: Identifiable {
    var id: String { "\(segmentNumber).\(number)" }
    let segmentNumber: Int
    let number: Int
    let name: String
}

enum SearchStatusWidthPreset: String, CaseIterable, Identifiable {
    case compact
    case medium
    case wide

    var id: String { rawValue }

    var width: Double {
        switch self {
        case .compact: return 200
        case .medium:  return 280
        case .wide:    return 360
        }
    }

    var title: String {
        switch self {
        case .compact: return "Status Width: Compact"
        case .medium:  return "Status Width: Medium"
        case .wide:    return "Status Width: Wide"
        }
    }
}
