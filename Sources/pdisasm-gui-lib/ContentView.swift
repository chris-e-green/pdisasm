import AppKit
import SwiftUI
import UniformTypeIdentifiers
import pdisasm

public struct ContentView: View {
    @State private var viewModel = DisassemblyViewModel()
    @Bindable var appState: GUIAppState
    @FocusState private var isSearchFieldFocused: Bool

    public init(appState: GUIAppState) {
        self.appState = appState
    }

    public var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            DetailView(viewModel: viewModel)
        }
        .navigationTitle(viewModel.fileURL?.lastPathComponent ?? "pdisasm")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    viewModel.showFileImporter = true
                } label: {
                    Label("Open File", systemImage: "doc.badge.plus")
                }

                if viewModel.fileURL != nil {
                    Button {
                        viewModel.runDisassembly()
                    } label: {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                }
            }

            ToolbarItemGroup(placement: .secondaryAction) {
                let matchCount = viewModel.searchMatchIndices.count
                let scanned = viewModel.searchScannedLineCount
                let total = viewModel.searchTotalLineCount
                let progressPercent = total > 0 ? (scanned * 100) / total : 0
                let statusWidth = viewModel.searchStatusWidthPreset.width

                TextField("Search disassembly", text: $viewModel.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 200)
                    .focused($isSearchFieldFocused)
                    .onSubmit { viewModel.commitSearch() }

                if matchCount > 0 {
                    Text("\(viewModel.currentMatchIndex + 1)/\(matchCount)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Button {
                        viewModel.previousMatch()
                    } label: {
                        Label("Previous", systemImage: "chevron.up")
                    }
                    Button {
                        viewModel.nextMatch()
                    } label: {
                        Label("Next", systemImage: "chevron.down")
                    }
                }

                ZStack(alignment: .leading) {
                    if viewModel.isSearching {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            ViewThatFits(in: .horizontal) {
                                Text("Searching... \(viewModel.liveSearchMatchCount) matches (\(scanned)/\(total), \(progressPercent)%)")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                Text("\(viewModel.liveSearchMatchCount) matches, \(progressPercent)%")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                Text("\(progressPercent)%")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(width: statusWidth, alignment: .leading)

                Menu {
                    Picker("Search Status Width", selection: $viewModel.searchStatusWidthPreset) {
                        ForEach(DisassemblyViewModel.SearchStatusWidthPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                } label: {
                    Image(systemName: "textformat.size")
                }
                .help("Choose search status width")

                Button {
                    viewModel.copySelectedOutputLines()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .disabled(viewModel.selectedOutputLineCount == 0)

                Menu {
                    Toggle("Markup", isOn: $viewModel.showMarkup)
                    Toggle("P-Code", isOn: $viewModel.showPCode)
                    Toggle("Stack State", isOn: $viewModel.showStackState)
                    Toggle("Pseudocode", isOn: $viewModel.showPseudoCode)
                    Toggle("Variables", isOn: $viewModel.showVariables)

                    Divider()

                    Toggle("Verbose Output", isOn: $viewModel.verbose)
                } label: {
                    Label("Display", systemImage: "line.3.horizontal.decrease.circle")
                }
                .help(viewModel.displaySummary)
            }
        }
        .fileImporter(
            isPresented: $viewModel.showFileImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    viewModel.openFile(url: url)
                }
            case .failure(let error):
                viewModel.errorMessage = error.localizedDescription
            }
        }
        .focusedSceneValue(\.openFileAction) {
            viewModel.showFileImporter = true
        }
        .focusedSceneValue(\.copyOutputSelectionAction) {
            viewModel.copySelectedOutputLines()
        }
        .focusedSceneValue(\.hasOutputSelection, viewModel.selectedOutputLineCount > 0)
        .focusedSceneValue(\.findDisassemblyAction) {
            isSearchFieldFocused = true
        }
        .focusedSceneValue(\.findNextDisassemblyMatchAction) {
            viewModel.nextMatch()
        }
        .focusedSceneValue(\.findPreviousDisassemblyMatchAction) {
            viewModel.previousMatch()
        }
        .focusedSceneValue(\.hasDisassemblySearchMatches, !viewModel.searchMatchIndices.isEmpty)
        .focusedSceneValue(\.disassemblyDisplayOptions, DisassemblyDisplayOptions(
            showMarkup: $viewModel.showMarkup,
            showPCode: $viewModel.showPCode,
            showStackState: $viewModel.showStackState,
            showPseudoCode: $viewModel.showPseudoCode,
            showVariables: $viewModel.showVariables,
            verbose: $viewModel.verbose
        ))
        .onAppear {
            viewModel.restoreLastFile()
            appState.relevantMetadataFiles = viewModel.relevantMetadataFiles
        }
        .onChange(of: viewModel.relevantMetadataFiles) { _, newValue in
            appState.relevantMetadataFiles = newValue
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Bindable var viewModel: DisassemblyViewModel

    var body: some View {
        if viewModel.segments.isEmpty {
            ContentUnavailableView(
                "No File Open",
                systemImage: "doc",
                description: Text("Open a .bin file to see its segments and procedures.")
            )
        } else {
            List(selection: Binding(
                get: { viewModel.selectedProcedure },
                set: { viewModel.selectProcedure($0) }
            )) {
                ForEach(viewModel.segments) { segment in
                    Section(segment.name) {
                        ForEach(segment.procedures) { proc in
                            Text(proc.name)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)
                                .tag(proc.id)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }
}

// MARK: - Detail

struct DetailView: View {
    @Bindable var viewModel: DisassemblyViewModel

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Disassembling…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.errorMessage {
                ContentUnavailableView(
                    "Error",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if !viewModel.hasOutput {
                ContentUnavailableView(
                    "No Disassembly",
                    systemImage: "cpu",
                    description: Text("Open a Pascal P-code binary (.bin) to get started.")
                )
            } else {
                VStack(spacing: 0) {
                    outputHeader
                    Divider()
                    DisassemblyTableView(
                        viewModel: viewModel,
                        lines: viewModel.filteredLines,
                        selectedLineIDs: viewModel.selectedOutputLineIDs,
                        procedureScrollRequest: viewModel.procedureScrollRequest,
                        selectedProcedureFilteredIndex: viewModel.selectedProcedureFilteredIndex,
                        restoreScrollRequest: viewModel.outputRestoreScrollRequest,
                        restoreFilteredIndex: viewModel.outputRestoreFilteredIndex,
                        currentMatchScrollIndex: viewModel.currentMatchScrollIndex,
                        searchMatchIndices: viewModel.searchMatchIndices,
                        searchMatchIndexSet: Set(viewModel.searchMatchIndices)
                    )
                    Divider()
                    statusBar
                }
            }
        }
        .sheet(item: $viewModel.locationEditDraft) { _ in
            LocationEditSheet(viewModel: viewModel)
        }
        .sheet(item: $viewModel.procedureSignatureEditDraft) { _ in
            ProcedureSignatureEditSheet(viewModel: viewModel)
        }
        .sheet(item: $viewModel.commentEditDraft) { _ in
            CommentEditSheet(viewModel: viewModel)
        }
    }

    private var outputHeader: some View {
        HStack(spacing: 10) {
            Text(viewModel.fileURL?.lastPathComponent ?? "Disassembly")
                .font(.headline)
                .lineLimit(1)
            Text(viewModel.displaySummary)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if viewModel.isSearching {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            Text(viewModel.statusText)
                .lineLimit(1)
            Spacer()
            if let selectedProcedure = viewModel.selectedProcedure {
                Text("Procedure \(selectedProcedure)")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private struct LocationEditSheet: View {
        @Bindable var viewModel: DisassemblyViewModel
        @Environment(\.dismiss) private var dismiss
        @FocusState private var isNameFocused: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                Text(viewModel.locationEditDraft?.title ?? "Location")
                    .font(.headline)
                    .monospaced()

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text("Name")
                        TextField("Name", text: Binding(
                            get: { viewModel.locationEditDraft?.name ?? "" },
                            set: { viewModel.locationEditDraft?.name = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(minWidth: 280)
                        .focused($isNameFocused)
                    }

                    GridRow {
                        Text("Type")
                        TextField("Type", text: Binding(
                            get: { viewModel.locationEditDraft?.type ?? "" },
                            set: { viewModel.locationEditDraft?.type = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    }
                }

                HStack {
                    Spacer()
                    Button("Cancel") {
                        viewModel.locationEditDraft = nil
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                    Button("Save") {
                        viewModel.saveLocationEdit()
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(minWidth: 420)
            .onAppear { isNameFocused = true }
        }
    }

    private struct ProcedureSignatureEditSheet: View {
        @Bindable var viewModel: DisassemblyViewModel
        @Environment(\.dismiss) private var dismiss
        @FocusState private var isFirstFieldFocused: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                Text(viewModel.procedureSignatureEditDraft?.title ?? "Signature")
                    .font(.headline)
                    .monospaced()

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    if viewModel.procedureSignatureEditDraft?.editsName == true {
                        GridRow {
                            Text("Name")
                            TextField("Name", text: Binding(
                                get: { viewModel.procedureSignatureEditDraft?.name ?? "" },
                                set: { viewModel.procedureSignatureEditDraft?.name = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .frame(minWidth: 280)
                            .focused($isFirstFieldFocused)
                        }
                    }

                    if viewModel.procedureSignatureEditDraft?.editsType == true {
                        GridRow {
                            Text("Type")
                            TextField("Type", text: Binding(
                                get: { viewModel.procedureSignatureEditDraft?.type ?? "" },
                                set: { viewModel.procedureSignatureEditDraft?.type = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .frame(minWidth: 280)
                            .focused($isFirstFieldFocused)
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button("Cancel") {
                        viewModel.procedureSignatureEditDraft = nil
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                    Button("Save") {
                        viewModel.saveProcedureSignatureEdit()
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(minWidth: 420)
            .onAppear { isFirstFieldFocused = true }
        }
    }

    private struct CommentEditSheet: View {
        @Bindable var viewModel: DisassemblyViewModel
        @Environment(\.dismiss) private var dismiss
        @FocusState private var isCommentFocused: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                Text(viewModel.commentEditDraft?.title ?? "Comment")
                    .font(.headline)
                    .monospaced()

                TextField("Comment", text: Binding(
                    get: { viewModel.commentEditDraft?.comment ?? "" },
                    set: { viewModel.commentEditDraft?.comment = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 420)
                .focused($isCommentFocused)

                HStack {
                    Spacer()
                    Button("Cancel") {
                        viewModel.commentEditDraft = nil
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                    Button("Save") {
                        viewModel.saveCommentEdit()
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(minWidth: 500)
            .onAppear { isCommentFocused = true }
        }
    }

}

#Preview {
    ContentView(appState: GUIAppState())
}

// MARK: - Focused Value for Open File action

public struct OpenFileActionKey: FocusedValueKey {
    public typealias Value = () -> Void
}

public struct CopyOutputSelectionActionKey: FocusedValueKey {
    public typealias Value = () -> Void
}

public struct HasOutputSelectionKey: FocusedValueKey {
    public typealias Value = Bool
}

public struct FindDisassemblyActionKey: FocusedValueKey {
    public typealias Value = () -> Void
}

public struct FindNextDisassemblyMatchActionKey: FocusedValueKey {
    public typealias Value = () -> Void
}

public struct FindPreviousDisassemblyMatchActionKey: FocusedValueKey {
    public typealias Value = () -> Void
}

public struct HasDisassemblySearchMatchesKey: FocusedValueKey {
    public typealias Value = Bool
}

public struct DisassemblyDisplayOptions {
    public var showMarkup: Binding<Bool>
    public var showPCode: Binding<Bool>
    public var showStackState: Binding<Bool>
    public var showPseudoCode: Binding<Bool>
    public var showVariables: Binding<Bool>
    public var verbose: Binding<Bool>
}

public struct DisassemblyDisplayOptionsKey: FocusedValueKey {
    public typealias Value = DisassemblyDisplayOptions
}

public extension FocusedValues {
    var openFileAction: (() -> Void)? {
        get { self[OpenFileActionKey.self] }
        set { self[OpenFileActionKey.self] = newValue }
    }

    var copyOutputSelectionAction: (() -> Void)? {
        get { self[CopyOutputSelectionActionKey.self] }
        set { self[CopyOutputSelectionActionKey.self] = newValue }
    }

    var hasOutputSelection: Bool? {
        get { self[HasOutputSelectionKey.self] }
        set { self[HasOutputSelectionKey.self] = newValue }
    }

    var findDisassemblyAction: (() -> Void)? {
        get { self[FindDisassemblyActionKey.self] }
        set { self[FindDisassemblyActionKey.self] = newValue }
    }

    var findNextDisassemblyMatchAction: (() -> Void)? {
        get { self[FindNextDisassemblyMatchActionKey.self] }
        set { self[FindNextDisassemblyMatchActionKey.self] = newValue }
    }

    var findPreviousDisassemblyMatchAction: (() -> Void)? {
        get { self[FindPreviousDisassemblyMatchActionKey.self] }
        set { self[FindPreviousDisassemblyMatchActionKey.self] = newValue }
    }

    var hasDisassemblySearchMatches: Bool? {
        get { self[HasDisassemblySearchMatchesKey.self] }
        set { self[HasDisassemblySearchMatchesKey.self] = newValue }
    }

    var disassemblyDisplayOptions: DisassemblyDisplayOptions? {
        get { self[DisassemblyDisplayOptionsKey.self] }
        set { self[DisassemblyDisplayOptionsKey.self] = newValue }
    }
}
