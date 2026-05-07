import Foundation
import SwiftUI

/// Represents a single row in a CSV file as an ordered dictionary of column→value.
struct CSVRow: Identifiable {
    let id = UUID()
    var values: [String: String]
}

/// View model for loading, editing, and saving CSV metadata files.
@MainActor
@Observable
final class MetadataViewModel {
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
            columns = header.components(separatedBy: ",")
            rows = lines.dropFirst().map { line in
                let fields = parseCSVLine(line)
                var dict: [String: String] = [:]
                for (i, col) in columns.enumerated() {
                    dict[col] = i < fields.count ? fields[i] : ""
                }
                return CSVRow(values: dict)
            }
            isDirty = false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Edit

    func updateValue(_ row: CSVRow, column: String, newValue: String) {
        guard let idx = rows.firstIndex(where: { $0.id == row.id }) else { return }
        rows[idx].values[column] = newValue
        isDirty = true
    }

    func addRow() {
        var dict: [String: String] = [:]
        for col in columns { dict[col] = "" }
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
        for ch in line {
            if ch == "\"" {
                inQuotes.toggle()
            } else if ch == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(ch)
            }
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
}
