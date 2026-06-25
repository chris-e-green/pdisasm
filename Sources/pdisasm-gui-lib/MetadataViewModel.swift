import Foundation
import SwiftUI
import Observation

/// Represents a single row in a CSV file as an ordered dictionary of column→value.
struct CSVRow: Identifiable {
    let id = UUID()
    var values: [String: String]
}

enum MetadataFileKind {
    case csv
    case recordsJSON
    case pascalTypes
}

struct RecordMemberRow: Identifiable {
    let id = UUID()
    var offset: String
    var name: String
    var type: String
    var typeSource: String
}

struct RecordRow: Identifiable {
    let id = UUID()
    var name: String
    var isSystemRecord: Bool
    var members: [RecordMemberRow]
}

enum RecordMemberColumn {
    case offset
    case name
    case type
    case typeSource
}

enum MetadataEditorError: LocalizedError {
    case invalidRecordOffset(String)

    var errorDescription: String? {
        switch self {
        case .invalidRecordOffset(let offset):
            return "Record member offset must be an integer: \(offset)"
        }
    }
}

/// View model for loading, editing, and saving metadata files.
@MainActor
@Observable
final class MetadataViewModel {
    private enum MetadataColumn {
        static let type = "type"
        static let typeSource = "typeSource"
        static let returnType = "returnType"
        static let returnTypeSource = "returnTypeSource"
    }

    // MARK: - State

    private struct RecordFile: Codable {
        var name: String
        var isSystemRecord: Bool?
        var members: [String: RecordIdentifier]
    }

    private struct RecordIdentifier: Codable {
        var name: String
        var type: String
        var typeSource: String?
    }

    /// Available metadata files discovered in the metadata directory.
    var availableFiles: [URL] = []

    /// Currently selected file URL.
    var selectedFile: URL? {
        didSet { loadFile() }
    }

    var selectedFileKind: MetadataFileKind?

    /// Column headers from the CSV.
    var columns: [String] = []

    /// All rows loaded from the CSV.
    var rows: [CSVRow] = []

    /// All records loaded from a records JSON file.
    var records: [RecordRow] = []

    /// Raw Pascal type definitions loaded from a types Pascal file.
    var textContent: String = ""

    /// Whether there are unsaved edits.
    var isDirty: Bool = false
    var selectedCSVRowID: UUID?
    var selectedRecordID: UUID?

    /// Raw metadata filenames that are relevant to the current disassembly.
    var relevantFilenames: [String] = [] {
        didSet { discoverFiles() }
    }

    var errorMessage: String?

    var statusText: String {
        guard let selectedFile else { return "No metadata file selected" }
        let dirty = isDirty ? "Edited" : "Saved"
        switch selectedFileKind {
        case .csv:
            return "\(selectedFile.lastPathComponent)   \(rows.count) rows   \(columns.count) columns   \(dirty)"
        case .recordsJSON:
            let memberCount = records.reduce(0) { $0 + $1.members.count }
            return "\(selectedFile.lastPathComponent)   \(records.count) records   \(memberCount) members   \(dirty)"
        case .pascalTypes:
            return "\(selectedFile.lastPathComponent)   \(textContent.count) characters   \(dirty)"
        case nil:
            return selectedFile.lastPathComponent
        }
    }

    // MARK: - Init

    init() {}

    // MARK: - File Discovery

    func discoverFiles() {
        let appSupportDir = URL.pdisasmApplicationSupportDirectory
            .appendingPathComponent("pdisasm")

        let allFiles = (try? FileManager.default.contentsOfDirectory(
            at: appSupportDir,
            includingPropertiesForKeys: nil
        ).filter({ isEditableMetadataFile($0) })) ?? []

        if relevantFilenames.isEmpty {
            availableFiles = allFiles.sorted { $0.lastPathComponent < $1.lastPathComponent }
        } else {
            let relevant = Set(relevantFilenames)
            var files = allFiles
                .filter { relevant.contains($0.lastPathComponent) }
            for filename in relevant where filename.hasPrefix("types_") && filename.hasSuffix(".pas") {
                let url = appSupportDir.appendingPathComponent(filename)
                if !files.contains(url) {
                    files.append(url)
                }
            }
            availableFiles = files.sorted { $0.lastPathComponent < $1.lastPathComponent }
        }

        if let selectedFile, !availableFiles.contains(selectedFile) {
            self.selectedFile = nil
        }
    }

    // MARK: - Load

    func loadFile() {
        guard let url = selectedFile else {
            columns = []
            rows = []
            records = []
            textContent = ""
            selectedFileKind = nil
            selectedCSVRowID = nil
            selectedRecordID = nil
            return
        }
        guard let kind = fileKind(for: url) else {
            columns = []
            rows = []
            records = []
            textContent = ""
            selectedFileKind = nil
            selectedCSVRowID = nil
            selectedRecordID = nil
            return
        }
        selectedFileKind = kind
        switch kind {
        case .csv:
            loadCSVFile(url)
        case .recordsJSON:
            loadRecordsFile(url)
        case .pascalTypes:
            loadTextFile(url)
        }
    }

    private func loadCSVFile(_ url: URL) {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
            guard let header = lines.first else {
                columns = []
                rows = []
                records = []
                return
            }
            let loadedColumns = header.components(separatedBy: ",")
            columns = loadedColumns
            rows = lines.dropFirst().map { line in
                let fields = parseCSVLine(line)
                var dict: [String: String] = [:]
                for (i, col) in loadedColumns.enumerated() {
                    dict[col] = i < fields.count ? fields[i] : ""
                }
                return CSVRow(values: dict)
            }
            ensureSourceColumn(for: MetadataColumn.type, sourceColumn: MetadataColumn.typeSource)
            ensureSourceColumn(for: MetadataColumn.returnType, sourceColumn: MetadataColumn.returnTypeSource)
            fillMissingSourceValues(typeColumn: MetadataColumn.type, sourceColumn: MetadataColumn.typeSource)
            fillMissingSourceValues(typeColumn: MetadataColumn.returnType, sourceColumn: MetadataColumn.returnTypeSource)
            records = []
            textContent = ""
            selectedCSVRowID = nil
            selectedRecordID = nil
            isDirty = false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadRecordsFile(_ url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([RecordFile].self, from: data)
            records = decoded.map { record in
                RecordRow(
                    name: record.name,
                    isSystemRecord: record.isSystemRecord ?? false,
                    members: record.members
                        .map { offset, identifier in
                            RecordMemberRow(
                                offset: offset,
                                name: identifier.name,
                                type: identifier.type,
                                typeSource: identifier.typeSource ?? ""
                            )
                        }
                        .sorted { lhs, rhs in
                            (Int(lhs.offset) ?? Int.max, lhs.offset) < (Int(rhs.offset) ?? Int.max, rhs.offset)
                        }
                )
            }
            columns = []
            rows = []
            textContent = ""
            selectedCSVRowID = nil
            selectedRecordID = nil
            isDirty = false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadTextFile(_ url: URL) {
        do {
            textContent = FileManager.default.fileExists(atPath: url.path)
                ? try String(contentsOf: url, encoding: .utf8)
                : ""
            columns = []
            rows = []
            records = []
            selectedCSVRowID = nil
            selectedRecordID = nil
            isDirty = false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Edit

    func updateValue(_ row: CSVRow, column: String, newValue: String) {
        guard let idx = rows.firstIndex(where: { $0.id == row.id }) else { return }
        guard rows[idx].values[column] != newValue else { return }
        rows[idx].values[column] = newValue
        markUserTypeSourceIfNeeded(rowIndex: idx, editedColumn: column, newValue: newValue)
        isDirty = true
    }

    func addRow() {
        var dict: [String: String] = [:]
        for col in columns { dict[col] = "" }
        if columns.contains(MetadataColumn.typeSource) {
            dict[MetadataColumn.typeSource] = "unknown"
        }
        if columns.contains(MetadataColumn.returnTypeSource) {
            dict[MetadataColumn.returnTypeSource] = "unknown"
        }
        rows.append(CSVRow(values: dict))
        isDirty = true
    }

    func deleteRows(at offsets: IndexSet) {
        rows.remove(atOffsets: offsets)
        if let selectedCSVRowID, !rows.contains(where: { $0.id == selectedCSVRowID }) {
            self.selectedCSVRowID = nil
        }
        isDirty = true
    }

    func deleteSelectedRows() {
        guard let selectedCSVRowID,
              let index = rows.firstIndex(where: { $0.id == selectedCSVRowID })
        else { return }
        deleteRows(at: IndexSet(integer: index))
    }

    func addRecord() {
        records.append(RecordRow(name: "NEW_RECORD", isSystemRecord: false, members: []))
        isDirty = true
    }

    func deleteRecord(_ record: RecordRow) {
        records.removeAll { $0.id == record.id }
        if selectedRecordID == record.id {
            selectedRecordID = nil
        }
        isDirty = true
    }

    func deleteSelectedRecord() {
        guard let selectedRecordID,
              let record = records.first(where: { $0.id == selectedRecordID })
        else { return }
        deleteRecord(record)
    }

    func updateRecordName(_ record: RecordRow, newValue: String) {
        guard let index = records.firstIndex(where: { $0.id == record.id }),
              records[index].name != newValue else { return }
        records[index].name = newValue
        isDirty = true
    }

    func updateRecordIsSystem(_ record: RecordRow, newValue: Bool) {
        guard let index = records.firstIndex(where: { $0.id == record.id }),
              records[index].isSystemRecord != newValue else { return }
        records[index].isSystemRecord = newValue
        isDirty = true
    }

    func addMember(to record: RecordRow) {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        let nextOffset = (records[index].members.compactMap { Int($0.offset) }.max() ?? -1) + 1
        records[index].members.append(RecordMemberRow(
            offset: "\(nextOffset)",
            name: "FIELD",
            type: "UNKNOWN",
            typeSource: "unknown"
        ))
        isDirty = true
    }

    func deleteMember(_ member: RecordMemberRow, from record: RecordRow) {
        guard let recordIndex = records.firstIndex(where: { $0.id == record.id }) else { return }
        records[recordIndex].members.removeAll { $0.id == member.id }
        isDirty = true
    }

    func updateMember(_ member: RecordMemberRow, in record: RecordRow, column: RecordMemberColumn, newValue: String) {
        guard let recordIndex = records.firstIndex(where: { $0.id == record.id }),
              let memberIndex = records[recordIndex].members.firstIndex(where: { $0.id == member.id }) else { return }

        switch column {
        case .offset:
            guard records[recordIndex].members[memberIndex].offset != newValue else { return }
            records[recordIndex].members[memberIndex].offset = newValue
        case .name:
            guard records[recordIndex].members[memberIndex].name != newValue else { return }
            records[recordIndex].members[memberIndex].name = newValue
        case .type:
            guard records[recordIndex].members[memberIndex].type != newValue else { return }
            records[recordIndex].members[memberIndex].type = newValue
            if records[recordIndex].members[memberIndex].typeSource.isEmpty ||
                records[recordIndex].members[memberIndex].typeSource == "unknown" {
                records[recordIndex].members[memberIndex].typeSource =
                    newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newValue == "UNKNOWN"
                    ? "unknown"
                    : "user"
            }
        case .typeSource:
            guard records[recordIndex].members[memberIndex].typeSource != newValue else { return }
            records[recordIndex].members[memberIndex].typeSource = newValue
        }
        isDirty = true
    }

    func updateTextContent(_ newValue: String) {
        guard textContent != newValue else { return }
        textContent = newValue
        isDirty = true
    }

    // MARK: - Save

    func save() {
        guard let url = selectedFile else { return }
        switch selectedFileKind {
        case .csv:
            saveCSVFile(url)
        case .recordsJSON:
            saveRecordsFile(url)
        case .pascalTypes:
            saveTextFile(url)
        case nil:
            return
        }
    }

    private func saveCSVFile(_ url: URL) {
        var lines: [String] = [columns.joined(separator: ",")]
        for row in rows {
            let fields = columns.map { escapeCSVField(row.values[$0] ?? "") }
            lines.append(fields.joined(separator: ","))
        }
        let content = lines.joined(separator: "\n") + "\n"
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            isDirty = false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveRecordsFile(_ url: URL) {
        do {
            let encoded = try records.map { record in
                var members: [String: RecordIdentifier] = [:]
                for member in record.members {
                    let offset = member.offset.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard Int(offset) != nil else {
                        throw MetadataEditorError.invalidRecordOffset(offset)
                    }
                    let source = member.typeSource.trimmingCharacters(in: .whitespacesAndNewlines)
                    members[offset] = RecordIdentifier(
                        name: member.name,
                        type: member.type,
                        typeSource: source.isEmpty ? nil : source
                    )
                }
                return RecordFile(
                    name: record.name,
                    isSystemRecord: record.isSystemRecord,
                    members: members
                )
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(encoded)
            try data.write(to: url, options: .atomic)
            isDirty = false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveTextFile(_ url: URL) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try textContent.write(to: url, atomically: true, encoding: .utf8)
            isDirty = false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - CSV Helpers

    private func isEditableMetadataFile(_ url: URL) -> Bool {
        if url.pathExtension == "csv" { return true }
        return fileKind(for: url) == .recordsJSON
            || fileKind(for: url) == .pascalTypes
    }

    private func fileKind(for url: URL) -> MetadataFileKind? {
        if url.pathExtension == "csv" { return .csv }
        if url.pathExtension == "json",
           url.deletingPathExtension().lastPathComponent.hasPrefix("records") {
            return .recordsJSON
        }
        if url.pathExtension == "pas",
           url.deletingPathExtension().lastPathComponent.hasPrefix("types") {
            return .pascalTypes
        }
        return nil
    }

    private func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var index = line.startIndex
        while index < line.endIndex {
            let ch = line[index]
            if ch == "\"" {
                if inQuotes {
                    let nextIndex = line.index(after: index)
                    if nextIndex < line.endIndex && line[nextIndex] == "\"" {
                        current.append("\"")
                        index = line.index(after: nextIndex)
                        continue
                    } else {
                        inQuotes = false
                    }
                } else {
                    inQuotes = true
                }
            } else if ch == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(ch)
            }
            index = line.index(after: index)
        }
        fields.append(current)
        return fields
    }

    private func escapeCSVField(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    private func ensureSourceColumn(for typeColumn: String, sourceColumn: String) {
        guard columns.contains(typeColumn), !columns.contains(sourceColumn) else { return }
        if let typeIndex = columns.firstIndex(of: typeColumn) {
            columns.insert(sourceColumn, at: columns.index(after: typeIndex))
        } else {
            columns.append(sourceColumn)
        }
    }

    private func markUserTypeSourceIfNeeded(rowIndex: Int, editedColumn: String, newValue: String) {
        switch editedColumn {
        case MetadataColumn.type:
            markTypeSource(
                rowIndex: rowIndex,
                sourceColumn: MetadataColumn.typeSource,
                typeValue: newValue
            )
        case MetadataColumn.returnType:
            markTypeSource(
                rowIndex: rowIndex,
                sourceColumn: MetadataColumn.returnTypeSource,
                typeValue: newValue
            )
        default:
            return
        }
    }

    private func markTypeSource(rowIndex: Int, sourceColumn: String, typeValue: String) {
        guard columns.contains(sourceColumn) else { return }
        let trimmed = typeValue.trimmingCharacters(in: .whitespacesAndNewlines)
        rows[rowIndex].values[sourceColumn] =
            trimmed.isEmpty || trimmed == "UNKNOWN" ? "unknown" : "user"
    }

    private func fillMissingSourceValues(typeColumn: String, sourceColumn: String) {
        guard columns.contains(typeColumn), columns.contains(sourceColumn) else { return }
        for index in rows.indices where rows[index].values[sourceColumn] == nil {
            let typeValue = rows[index].values[typeColumn] ?? ""
            let trimmed = typeValue.trimmingCharacters(in: .whitespacesAndNewlines)
            rows[index].values[sourceColumn] =
                trimmed.isEmpty || trimmed == "UNKNOWN" ? "unknown" : "metadata"
        }
    }
}
