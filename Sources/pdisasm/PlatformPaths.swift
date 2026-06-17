import Foundation

extension URL {
    static var applicationSupportDirectory: URL {
        #if os(macOS)
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        #else
        if let xdgDataHome = ProcessInfo.processInfo.environment["XDG_DATA_HOME"], !xdgDataHome.isEmpty {
            return URL(fileURLWithPath: xdgDataHome, isDirectory: true)
        }
        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSTemporaryDirectory()
        return URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("share", isDirectory: true)
        #endif
    }
}
