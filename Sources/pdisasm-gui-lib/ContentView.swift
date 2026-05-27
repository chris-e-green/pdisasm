import SwiftUI
import UniformTypeIdentifiers
import pdisasm

public struct ContentView: View {
    @State private var viewModel = DisassemblyViewModel()
    @Bindable var appState: GUIAppState

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

                Toggle("Markup", isOn: $viewModel.showMarkup)
                Toggle("P-Code", isOn: $viewModel.showPCode)
                Toggle("Pseudocode", isOn: $viewModel.showPseudoCode)
                Toggle("Variables", isOn: $viewModel.showVariables)
                Toggle("Verbose", isOn: $viewModel.verbose)
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
            List {
                ForEach(viewModel.segments) { segment in
                    Section(segment.name) {
                        ForEach(segment.procedures) { proc in
                            Button {
                                viewModel.selectedProcedure = proc.id
                            } label: {
                                Text(proc.name)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
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
                GeometryReader { geo in
                    let lines = viewModel.filteredLines

                    ScrollViewReader { scrollProxy in
                        ScrollView([.horizontal, .vertical]) {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                                    let lineID = line.anchor ?? "line-\(line.id)"
                                    let isMatch = viewModel.lineMatchesCommittedSearch(atFilteredIndex: index)
                                    let isCurrentMatch = viewModel.isCurrentMatch(atFilteredIndex: index)
                                    Text(line.text)
                                        .font(.system(.body, design: .monospaced))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 1)
                                        .background(isCurrentMatch ? Color.yellow.opacity(0.4) : isMatch ? Color.yellow.opacity(0.2) : backgroundColor(for: line.kind))
                                        .id(lineID)
                                }
                            }
                            .textSelection(.enabled)
                            .padding(.vertical, 4)
                            .frame(minWidth: geo.size.width, alignment: .leading)
                        }
                        .onChange(of: viewModel.selectedProcedure) { _, newValue in
                            if let anchor = newValue {
                                withAnimation {
                                    scrollProxy.scrollTo(anchor, anchor: .top)
                                }
                            }
                        }
                        .onChange(of: viewModel.currentMatchAnchor) { _, newValue in
                            if let anchor = newValue {
                                withAnimation {
                                    scrollProxy.scrollTo(anchor, anchor: .center)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func backgroundColor(for kind: LineKind) -> Color {
        switch kind {
        case .markup:      return Color.gray.opacity(0.08)
        case .pcode:       return Color.blue.opacity(0.06)
        case .pseudocode:  return Color.green.opacity(0.08)
        case .variable:    return Color.orange.opacity(0.08)
        case .global:      return Color.purple.opacity(0.06)
        case .header:      return Color.yellow.opacity(0.10)
        case .diagnostic:  return Color.red.opacity(0.08)
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

public extension FocusedValues {
    var openFileAction: (() -> Void)? {
        get { self[OpenFileActionKey.self] }
        set { self[OpenFileActionKey.self] = newValue }
    }
}
