import Foundation
import Observation

@MainActor
@Observable
public final class GUIAppState {
    public var relevantMetadataFiles: [String] = []

    public init() {}
}
