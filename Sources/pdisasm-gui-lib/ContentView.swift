import AppKit
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

                Button {
                    viewModel.copySelectedOutputLines()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .disabled(viewModel.selectedOutputLineCount == 0)
                .keyboardShortcut("c", modifiers: .command)

                Toggle("Markup", isOn: $viewModel.showMarkup)
                Toggle("P-Code", isOn: $viewModel.showPCode)
                Toggle("Stack", isOn: $viewModel.showStackState)
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
                                viewModel.scrollToProcedure(proc.id)
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
    @State private var dragSelectionAnchorIndex: Int?
    @State private var dragSelectionDidStart = false
    private let outputRowHeight: CGFloat = 20
    private let outputContentVerticalPadding: CGFloat = 4

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
                                    let isSelected = viewModel.selectedOutputLineIDs.contains(line.id)
                                    Text(line.text)
                                        .font(.system(.body, design: .monospaced))
                                        .fixedSize(horizontal: true, vertical: false)
                                        .frame(minWidth: geo.size.width, alignment: .leading)
                                        .frame(height: outputRowHeight, alignment: .center)
                                        .padding(.horizontal, 8)
                                        .background(rowBackgroundColor(
                                            for: line.kind,
                                            isSelected: isSelected,
                                            isMatch: isMatch,
                                            isCurrentMatch: isCurrentMatch
                                        ))
                                        .contentShape(Rectangle())
                                        .contextMenu {
                                            Button("Copy Selected Lines") {
                                                if !isSelected {
                                                    viewModel.selectOutputLine(
                                                        lineID: line.id,
                                                        at: index,
                                                        extending: false,
                                                        toggling: false
                                                    )
                                                }
                                                viewModel.copySelectedOutputLines()
                                            }

                                            Button("Clear Selection") {
                                                viewModel.clearOutputSelection()
                                            }
                                            .disabled(viewModel.selectedOutputLineCount == 0)
                                        }
                                        .id(lineID)
                                }
                            }
                            .padding(.vertical, outputContentVerticalPadding)
                            .frame(minWidth: geo.size.width, alignment: .leading)
                            .contentShape(Rectangle())
                            .highPriorityGesture(outputDragSelectionGesture())
                        }
                        .onChange(of: viewModel.procedureScrollRequest) { _, _ in
                            if let anchor = viewModel.selectedProcedure {
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

    private func outputDragSelectionGesture() -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let currentIndex = outputRowIndex(at: value.location) else {
                    return
                }

                if !dragSelectionDidStart {
                    dragSelectionDidStart = true
                    dragSelectionAnchorIndex = outputRowIndex(at: value.startLocation) ?? currentIndex
                }

                let anchorIndex = dragSelectionAnchorIndex ?? currentIndex
                viewModel.selectOutputLineRange(from: anchorIndex, to: currentIndex)
            }
            .onEnded { value in
                if isClick(value) {
                    let index = outputRowIndex(at: value.location)
                        ?? outputRowIndex(at: value.startLocation)
                    if let index, viewModel.filteredLines.indices.contains(index) {
                        let line = viewModel.filteredLines[index]
                        let modifiers = NSEvent.modifierFlags
                        viewModel.selectOutputLine(
                            lineID: line.id,
                            at: index,
                            extending: modifiers.contains(.shift),
                            toggling: modifiers.contains(.command)
                        )
                    }
                }

                dragSelectionAnchorIndex = nil
                dragSelectionDidStart = false
            }
    }

    private func isClick(_ value: DragGesture.Value) -> Bool {
        abs(value.translation.width) < 3 && abs(value.translation.height) < 3
    }

    private func outputRowIndex(at location: CGPoint) -> Int? {
        guard !viewModel.filteredLines.isEmpty else { return nil }

        let rowIndex = Int((location.y - outputContentVerticalPadding) / outputRowHeight)
        return min(max(rowIndex, 0), viewModel.filteredLines.count - 1)
    }

    private func rowBackgroundColor(
        for kind: LineKind,
        isSelected: Bool,
        isMatch: Bool,
        isCurrentMatch: Bool
    ) -> Color {
        if isSelected {
            return Color.accentColor.opacity(0.25)
        }
        if isCurrentMatch {
            return Color.yellow.opacity(0.4)
        }
        if isMatch {
            return Color.yellow.opacity(0.2)
        }
        return backgroundColor(for: kind)
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
