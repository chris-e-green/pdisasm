import AppKit
import SwiftUI
import pdisasm_gui_lib

@main
struct PdisasmApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @FocusedValue(\.openFileAction) private var openFileAction
    @FocusedValue(\.copyOutputSelectionAction) private var copyOutputSelectionAction
    @FocusedValue(\.hasOutputSelection) private var hasOutputSelection
    @FocusedValue(\.findDisassemblyAction) private var findDisassemblyAction
    @FocusedValue(\.findNextDisassemblyMatchAction) private var findNextDisassemblyMatchAction
    @FocusedValue(\.findPreviousDisassemblyMatchAction) private var findPreviousDisassemblyMatchAction
    @FocusedValue(\.hasDisassemblySearchMatches) private var hasDisassemblySearchMatches
    @FocusedValue(\.disassemblyDisplayOptions) private var displayOptions
    @Environment(\.openWindow) private var openWindow
    @State private var appState = GUIAppState()

    var body: some Scene {
        WindowGroup {
            ContentView(appState: appState)
        }
        .defaultSize(width: 1200, height: 820)
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

            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
                }
                .keyboardShortcut("z", modifiers: .command)

                Button("Redo") {
                    NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .pasteboard) {
                Button("Cut") {
                    NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("x", modifiers: .command)

                Button("Copy") {
                    if hasOutputSelection == true {
                        copyOutputSelectionAction?()
                    } else {
                        NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                    }
                }
                .keyboardShortcut("c", modifiers: .command)

                Button("Paste") {
                    NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("v", modifiers: .command)
            }

            CommandGroup(after: .textEditing) {
                Divider()

                Button("Find in Disassembly") {
                    findDisassemblyAction?()
                }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(findDisassemblyAction == nil)

                Button("Find Next") {
                    findNextDisassemblyMatchAction?()
                }
                .keyboardShortcut("g", modifiers: .command)
                .disabled(hasDisassemblySearchMatches != true)

                Button("Find Previous") {
                    findPreviousDisassemblyMatchAction?()
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(hasDisassemblySearchMatches != true)
            }

            CommandGroup(after: .toolbar) {
                Divider()

                if let displayOptions {
                    Toggle("Markup", isOn: displayOptions.showMarkup)
                    Toggle("P-Code", isOn: displayOptions.showPCode)
                    Toggle("Stack State", isOn: displayOptions.showStackState)
                    Toggle("Pseudocode", isOn: displayOptions.showPseudoCode)
                    Toggle("Variables", isOn: displayOptions.showVariables)

                    Divider()

                    Toggle("Verbose Output", isOn: displayOptions.verbose)
                } else {
                    Toggle("Markup", isOn: .constant(false)).disabled(true)
                    Toggle("P-Code", isOn: .constant(false)).disabled(true)
                    Toggle("Stack State", isOn: .constant(false)).disabled(true)
                    Toggle("Pseudocode", isOn: .constant(false)).disabled(true)
                    Toggle("Variables", isOn: .constant(false)).disabled(true)

                    Divider()

                    Toggle("Verbose Output", isOn: .constant(false)).disabled(true)
                }
            }
        }

        WindowGroup("Metadata Editor", id: "metadata-editor") {
            MetadataEditorView(relevantFilenames: appState.relevantMetadataFiles)
        }
        .defaultSize(width: 980, height: 700)

        Settings {
            Form {
                Text("pdisasm")
                    .font(.headline)
                Text("Metadata files are stored in Application Support/pdisasm.")
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(width: 420)
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
