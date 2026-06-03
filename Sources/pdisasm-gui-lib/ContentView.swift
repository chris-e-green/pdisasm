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
    @State private var outputScrollView: NSScrollView?
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

                    ScrollView([.horizontal, .vertical]) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(lines.indices, id: \.self) { index in
                                let line = lines[index]
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
                            }
                        }
                        .padding(.vertical, outputContentVerticalPadding)
                        .frame(minWidth: geo.size.width, alignment: .leading)
                        .contentShape(Rectangle())
                        .highPriorityGesture(outputDragSelectionGesture())
                        .background(ScrollViewAccessor { scrollView in
                            if outputScrollView !== scrollView {
                                outputScrollView = scrollView
                            }
                        })
                    }
                    .onChange(of: viewModel.procedureScrollRequest) { _, _ in
                        if let index = viewModel.selectedProcedureFilteredIndex {
                            scrollOutput(to: index, anchor: .top)
                        }
                    }
                    .onChange(of: viewModel.outputRestoreScrollRequest) { _, _ in
                        if let index = viewModel.outputRestoreFilteredIndex {
                            scrollOutput(to: index, anchor: .top)
                            DispatchQueue.main.async {
                                scrollOutput(to: index, anchor: .top)
                            }
                        }
                    }
                    .onChange(of: viewModel.currentMatchScrollIndex) { _, newValue in
                        if let index = newValue {
                            scrollOutput(to: index, anchor: .center)
                        }
                    }
                }
            }
        }
        .sheet(item: $viewModel.locationEditDraft) { _ in
            LocationEditSheet(viewModel: viewModel)
        }
        .sheet(item: $viewModel.procedureSignatureEditDraft) { _ in
            ProcedureSignatureEditSheet(viewModel: viewModel)
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

                guard !isClick(value) else {
                    return
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
                        if NSApp.currentEvent?.clickCount == 2 {
                            viewModel.beginEditingOutputLine(
                                on: line,
                                filteredIndex: index,
                                atCharacterOffset: outputCharacterOffset(at: value.location)
                            )
                            dragSelectionAnchorIndex = nil
                            dragSelectionDidStart = false
                            return
                        }
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

    private enum ScrollAnchor {
        case top
        case center
    }

    private func scrollOutput(to index: Int, anchor: ScrollAnchor) {
        guard let scrollView = outputScrollView else { return }
        guard viewModel.filteredLines.indices.contains(index) else { return }

        let clipView = scrollView.contentView
        let currentX = clipView.bounds.origin.x
        let documentHeight = CGFloat(viewModel.filteredLines.count) * outputRowHeight
            + (outputContentVerticalPadding * 2)
        let visibleHeight = clipView.bounds.height
        var y = outputContentVerticalPadding + CGFloat(index) * outputRowHeight
        if anchor == .center {
            y -= max((visibleHeight - outputRowHeight) / 2, 0)
        }
        let maxY = max(documentHeight - visibleHeight, 0)
        y = min(max(y, 0), maxY)

        if let documentView = scrollView.documentView, !documentView.isFlipped {
            y = maxY - y
        }

        clipView.scroll(to: NSPoint(x: currentX, y: y))
        scrollView.reflectScrolledClipView(clipView)
    }

    private func outputCharacterOffset(at location: CGPoint) -> Int {
        let horizontalPadding: CGFloat = 8
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let characterWidth = max(font.advancement(forGlyph: font.glyph(withName: "0")).width, 1)
        return max(Int((location.x - horizontalPadding) / characterWidth), 0)
    }

    private struct LocationEditSheet: View {
        @Bindable var viewModel: DisassemblyViewModel
        @Environment(\.dismiss) private var dismiss

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
                    Button("Save") {
                        viewModel.saveLocationEdit()
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(minWidth: 420)
        }
    }

    private struct ProcedureSignatureEditSheet: View {
        @Bindable var viewModel: DisassemblyViewModel
        @Environment(\.dismiss) private var dismiss

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
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button("Cancel") {
                        viewModel.procedureSignatureEditDraft = nil
                        dismiss()
                    }
                    Button("Save") {
                        viewModel.saveProcedureSignatureEdit()
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(minWidth: 420)
        }
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

private struct ScrollViewAccessor: NSViewRepresentable {
    let onResolve: (NSScrollView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        resolveScrollView(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        resolveScrollView(from: nsView)
    }

    private func resolveScrollView(from view: NSView) {
        DispatchQueue.main.async {
            if let scrollView = view.enclosingScrollView {
                onResolve(scrollView)
            }
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
