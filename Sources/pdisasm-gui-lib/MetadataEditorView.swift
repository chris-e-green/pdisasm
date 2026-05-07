import SwiftUI

/// A view for browsing and editing CSV metadata files used by the disassembler.
public struct MetadataEditorView: View {
    var relevantFilenames: [String] = []
    @State private var viewModel = MetadataViewModel()
    @State private var searchText = ""

    public init(relevantFilenames: [String] = []) {
        self.relevantFilenames = relevantFilenames
    }

    public var body: some View {
        NavigationSplitView {
            List(viewModel.availableFiles, id: \.self, selection: $viewModel.selectedFile) { file in
                Text(file.lastPathComponent)
                    .font(.system(.body, design: .monospaced))
            }
            .listStyle(.sidebar)
            .navigationTitle("Metadata Files")
            .frame(minWidth: 200)
        } detail: {
            if viewModel.columns.isEmpty {
                ContentUnavailableView(
                    "No File Selected",
                    systemImage: "tablecells",
                    description: Text("Select a CSV file from the sidebar to view and edit its contents.")
                )
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Filter rows", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor))
                    Divider()
                    tableView
                }
                .navigationTitle(viewModel.selectedFile?.lastPathComponent ?? "")
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            viewModel.addRow()
                        } label: {
                            Label("Add Row", systemImage: "plus")
                        }

                        Button {
                            viewModel.save()
                        } label: {
                            Label("Save", systemImage: "square.and.arrow.down")
                        }
                        .disabled(!viewModel.isDirty)
                        .keyboardShortcut("s", modifiers: .command)
                    }
                }
            }
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .onAppear {
            viewModel.relevantFilenames = relevantFilenames
        }
        .onChange(of: relevantFilenames) { _, newValue in
            viewModel.relevantFilenames = newValue
        }
    }

    // MARK: - Table

    @ViewBuilder
    private var tableView: some View {
        let filtered = filteredRows
        ScrollView([.horizontal, .vertical]) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                // Header row
                GridRow {
                    ForEach(viewModel.columns, id: \.self) { column in
                        Text(column)
                            .font(.system(.caption, design: .monospaced))
                            .bold()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .frame(minWidth: 100, alignment: .leading)
                            .background(Color.gray.opacity(0.15))
                    }
                }
                Divider()
                // Data rows
                ForEach(filtered) { row in
                    GridRow {
                        ForEach(viewModel.columns, id: \.self) { column in
                            EditableCell(
                                text: row.values[column] ?? "",
                                onCommit: { newValue in
                                    viewModel.updateValue(row, column: column, newValue: newValue)
                                }
                            )
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .frame(minWidth: 100, alignment: .leading)
                        }
                    }
                    .contextMenu {
                        Button("Delete Row", role: .destructive) {
                            if let idx = viewModel.rows.firstIndex(where: { $0.id == row.id }) {
                                viewModel.deleteRows(at: IndexSet(integer: idx))
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }
    private var filteredRows: [CSVRow] {
        guard !searchText.isEmpty else { return viewModel.rows }
        let query = searchText.lowercased()
        return viewModel.rows.filter { row in
            row.values.values.contains { $0.lowercased().contains(query) }
        }
    }
}

// MARK: - Editable Cell

struct EditableCell: View {
    @State private var text: String
    let onCommit: (String) -> Void

    init(text: String, onCommit: @escaping (String) -> Void) {
        _text = State(initialValue: text)
        self.onCommit = onCommit
    }

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .font(.system(.body, design: .monospaced))
            .onSubmit {
                onCommit(text)
            }
            .onChange(of: text) { _, newValue in
                onCommit(newValue)
            }
    }
}

#Preview {
    MetadataEditorView(relevantFilenames: [])
}
