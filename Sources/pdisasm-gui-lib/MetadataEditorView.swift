import SwiftUI

/// A view for browsing and editing metadata files used by the disassembler.
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
            if viewModel.selectedFileKind == nil {
                ContentUnavailableView(
                    "No File Selected",
                    systemImage: "tablecells",
                    description: Text("Select a metadata file from the sidebar to view and edit its contents.")
                )
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Filter", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor))
                    Divider()
                    switch viewModel.selectedFileKind {
                    case .csv:
                        tableView
                    case .recordsJSON:
                        recordsView
                    case .pascalTypes:
                        typeDefinitionsView
                    case nil:
                        EmptyView()
                    }
                }
                .navigationTitle(viewModel.selectedFile?.lastPathComponent ?? "")
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        switch viewModel.selectedFileKind {
                        case .csv:
                            Button {
                                viewModel.addRow()
                            } label: {
                                Label("Add Row", systemImage: "plus")
                            }
                        case .recordsJSON:
                            Button {
                                viewModel.addRecord()
                            } label: {
                                Label("Add Record", systemImage: "plus")
                            }
                        case .pascalTypes:
                            EmptyView()
                        case nil:
                            EmptyView()
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
        .alert("Error", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { _ in viewModel.errorMessage = nil })) {
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

    // MARK: - Records

    private var recordsView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(filteredRecords) { record in
                    recordEditor(record)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func recordEditor(_ record: RecordRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                EditableCell(
                    text: record.name,
                    onCommit: { newValue in
                        viewModel.updateRecordName(record, newValue: newValue)
                    }
                )
                .font(.system(.headline, design: .monospaced))
                .frame(minWidth: 220, maxWidth: 360, alignment: .leading)

                Toggle(
                    "System",
                    isOn: Binding(
                        get: { record.isSystemRecord },
                        set: { viewModel.updateRecordIsSystem(record, newValue: $0) }
                    )
                )
                .toggleStyle(.checkbox)

                Spacer()

                Button {
                    viewModel.addMember(to: record)
                } label: {
                    Label("Add Member", systemImage: "plus")
                }

                Button(role: .destructive) {
                    viewModel.deleteRecord(record)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    recordsHeader("offset", width: 80)
                    recordsHeader("name", width: 180)
                    recordsHeader("type", width: 180)
                    recordsHeader("typeSource", width: 120)
                    Color.clear.frame(width: 32)
                }

                ForEach(record.members) { member in
                    GridRow {
                        recordMemberCell(member.offset, width: 80) {
                            viewModel.updateMember(member, in: record, column: .offset, newValue: $0)
                        }
                        recordMemberCell(member.name, width: 180) {
                            viewModel.updateMember(member, in: record, column: .name, newValue: $0)
                        }
                        recordMemberCell(member.type, width: 180) {
                            viewModel.updateMember(member, in: record, column: .type, newValue: $0)
                        }
                        recordMemberCell(member.typeSource, width: 120) {
                            viewModel.updateMember(member, in: record, column: .typeSource, newValue: $0)
                        }
                        Button(role: .destructive) {
                            viewModel.deleteMember(member, from: record)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .frame(width: 32)
                    }
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func recordsHeader(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .bold()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(width: width, alignment: .leading)
            .background(Color.gray.opacity(0.15))
    }

    private func recordMemberCell(_ text: String, width: CGFloat, onCommit: @escaping (String) -> Void) -> some View {
        EditableCell(text: text, onCommit: onCommit)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .frame(width: width, alignment: .leading)
    }

    // MARK: - Pascal Type Definitions

    private var typeDefinitionsView: some View {
        TextEditor(text: Binding(
            get: { viewModel.textContent },
            set: { viewModel.updateTextContent($0) }
        ))
        .font(.system(.body, design: .monospaced))
        .padding(8)
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

    private var filteredRecords: [RecordRow] {
        guard !searchText.isEmpty else { return viewModel.records }
        let query = searchText.lowercased()
        return viewModel.records.filter { record in
            record.name.lowercased().contains(query) ||
                record.members.contains { member in
                    member.offset.lowercased().contains(query) ||
                        member.name.lowercased().contains(query) ||
                        member.type.lowercased().contains(query) ||
                        member.typeSource.lowercased().contains(query)
                }
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
