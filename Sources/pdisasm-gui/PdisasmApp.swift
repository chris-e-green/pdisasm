import AppKit
import SwiftUI
import pdisasm_gui_lib

@main
struct PdisasmApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @FocusedValue(\.openFileAction) private var openFileAction
    @Environment(\.openWindow) private var openWindow
    @State private var appState = GUIAppState()

    var body: some Scene {
        WindowGroup {
            ContentView(appState: appState)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") {
                    openFileAction?()
                }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(openFileAction == nil)

                Divider()

                Button("Metadata Editor") {
                    openWindow(id: "metadata-editor")
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            }
        }

        WindowGroup("Metadata Editor", id: "metadata-editor") {
            MetadataEditorView(relevantFilenames: appState.relevantMetadataFiles)
        }
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
