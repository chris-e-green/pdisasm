import Foundation

enum SearchStatusWidthPreset: String, CaseIterable, Identifiable, Sendable {
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
