import SwiftUI
import UniformTypeIdentifiers
import pdisasm

struct ContentView: View {
    @State private var viewModel = DisassemblyViewModel()

    var body: some View {
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
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    let viewModel: DisassemblyViewModel

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
                            Text(proc.name)
                                .font(.system(.body, design: .monospaced))
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
    let viewModel: DisassemblyViewModel

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
                    ScrollView([.horizontal, .vertical]) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(viewModel.filteredLines) { line in
                                Text(line.text)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 1)
                                    .background(backgroundColor(for: line.kind))
                            }
                        }
                        .textSelection(.enabled)
                        .padding(.vertical, 4)
                        .frame(minWidth: geo.size.width, alignment: .leading)
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
        }
    }
}

#Preview {
    ContentView()
}
