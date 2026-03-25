import AppKit
import SwiftUI

@main
struct PdisasmApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @FocusedValue(\.openFileAction) private var openFileAction

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") {
                    openFileAction?()
                }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(openFileAction == nil)
            }
        }
    }
}

// MARK: - Focused Value for Open File action

struct OpenFileActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var openFileAction: (() -> Void)? {
        get { self[OpenFileActionKey.self] }
        set { self[OpenFileActionKey.self] = newValue }
    }
}

/// Ensures the process is promoted to a regular macOS app with a menu bar,
/// Dock icon, and ⌘Q support even when launched from `swift run`.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
