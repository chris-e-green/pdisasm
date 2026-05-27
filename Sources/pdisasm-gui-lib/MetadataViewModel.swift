import Foundation
import SwiftUI
import Observation

/// Represents a single row in a CSV file as an ordered dictionary of column→value.
struct CSVRow: Identifiable {
    let id = UUID()
    var values: [String: String]
}

/// View model for loading, editing, and saving CSV metadata files.
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

    /// Available CSV files discovered in the metadata directory.
    var availableFiles: [URL] = []

    /// Currently selected file URL.
    var selectedFile: URL? {
        didSet { loadFile() }
    }

    /// Column headers from the CSV.
    var columns: [String] = []

    /// All rows loaded from the CSV.
    var rows: [CSVRow] = []

    /// Whether there are unsaved edits.
    var isDirty: Bool = false

    /// CSV filenames that are relevant to the current disassembly.
    var relevantFilenames: [String] = [] {
        didSet { discoverFiles() }
    }

    var errorMessage: String?

    // MARK: - Init

    init() {}

    // MARK: - File Discovery

    func discoverFiles() {
        let appSupportDir = URL.applicationSupportDirectory
            .appendingPathComponent("pdisasm")

        guard let allFiles = try? FileManager.default.contentsOfDirectory(at: appSupportDir, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension == "csv" }) else {
            availableFiles = []
            return
        }

        if relevantFilenames.isEmpty {
            availableFiles = allFiles.sorted { $0.lastPathComponent < $1.lastPathComponent }
        } else {
            let relevant = Set(relevantFilenames)
            availableFiles = allFiles
                .filter { relevant.contains($0.lastPathComponent) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
    }

    // MARK: - Load

    func loadFile() {
        guard let url = selectedFile else {
            columns = []
            rows = []
            return
        }
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
            guard let header = lines.first else {
                columns = []
                rows = []
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
        isDirty = true
    }

    // MARK: - Save

    func save() {
        guard let url = selectedFile else { return }
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

    // MARK: - CSV Helpers

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
