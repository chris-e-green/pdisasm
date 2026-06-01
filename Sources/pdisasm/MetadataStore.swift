import CodableCSV
import Foundation

struct MetadataStore {
    let appSupportDirectory: URL
    var diagnostics: DiagnosticCollector? = nil

    func createDirectory() throws {
        try FileManager.default.createDirectory(
            at: appSupportDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    func importLabels(fromCSV file: String, to labels: inout Set<Location>) {
        do {
            if let loadedLabels: Set<Location> = try readCSV(file) {
                labels = loadedLabels
            }
        } catch {
            diagnostics?.error("Error reading \(file): \(error)")
        }
    }

    func exportLabels(
        toCSV file: String,
        from labels: [Location],
        overwrite: Bool = false
    ) {
        do {
            let encoder = CSVEncoder {
                $0.headers = [
                    "segment", "procedure", "lexLevel", "addr", "name", "type",
                    "typeSource",
                ]
                $0.bufferingStrategy = .sequential
            }
            try writeCSV(labels, to: file, overwrite: overwrite, encoder: encoder)
        } catch {
            diagnostics?.error("Error writing \(file): \(error)")
        }
    }

    func importProcedures(
        fromCSV file: String,
        to allProcedures: inout [ProcedureIdentifier]
    ) {
        do {
            if let loadedProcedures: [ProcedureIdentifier] = try readCSV(file) {
                allProcedures = loadedProcedures
            }
        } catch {
            diagnostics?.error("Error reading \(file): \(error)")
        }
    }

    func exportProcedures(
        toCSV file: String,
        from procedures: [ProcedureIdentifier],
        overwrite: Bool = false
    ) {
        do {
            let encoder = CSVEncoder { configuration in
                configuration.headers = [
                    "segmentNumber", "segmentName", "procNumber", "procName",
                    "isFunction",
                    "isAssembly", "parameters", "returnType", "returnTypeSource",
                ]
            }
            try writeCSV(procedures, to: file, overwrite: overwrite, encoder: encoder)
        } catch {
            diagnostics?.error("Error writing \(file): \(error)")
        }
    }

    func importGlobalLabels(
        fromJson file: String,
        to globalNames: inout [Int: Identifier]
    ) {
        if let loadedNames: [Int: Identifier] = try? readJSON(file) {
            globalNames = loadedNames
        }
    }

    func exportKnownRecords(
        toJson file: String,
        from knownRecords: Set<PascalRecord>,
        overwrite: Bool = false
    ) {
        do {
            try writeJSON(knownRecords, to: file, overwrite: overwrite)
        } catch {
            diagnostics?.error("Error writing \(file): \(error)")
        }
    }

    func importKnownRecords(
        fromJson file: String,
        to knownRecords: inout Set<PascalRecord>
    ) {
        if let newRecords: [PascalRecord] = try? readJSON(file) {
            knownRecords.formUnion(newRecords)
        }
    }

    private func fileURL(_ file: String, extension fileExtension: String) -> URL {
        appSupportDirectory
            .appendingPathComponent(file)
            .appendingPathExtension(fileExtension)
    }

    private func readCSV<Value: Decodable>(_ file: String) throws -> Value? {
        let url = fileURL(file, extension: "csv")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let decoder = CSVDecoder()
        decoder.headerStrategy = .firstLine
        let data = try Data(contentsOf: url)
        return try decoder.decode(Value.self, from: data)
    }

    private func writeCSV<Value: Encodable>(
        _ value: Value,
        to file: String,
        overwrite: Bool,
        encoder: CSVEncoder
    ) throws {
        let url = fileURL(file, extension: "csv")
        guard try prepareWrite(to: url, overwrite: overwrite) else { return }
        try encoder.encode(value, into: url)
    }

    private func readJSON<Value: Decodable>(_ file: String) throws -> Value? {
        let url = fileURL(file, extension: "json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let decoder = JSONDecoder()
        let data = try Data(contentsOf: url)
        return try decoder.decode(Value.self, from: data)
    }

    private func writeJSON<Value: Encodable>(
        _ value: Value,
        to file: String,
        overwrite: Bool
    ) throws {
        let url = fileURL(file, extension: "json")
        guard try prepareWrite(to: url, overwrite: overwrite) else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private func prepareWrite(to url: URL, overwrite: Bool) throws -> Bool {
        if !overwrite && FileManager.default.fileExists(atPath: url.path) {
            return false
        }

        let backupURL = url
            .appendingPathExtension("bak")
            .appendingPathExtension(Date().ISO8601Format())
        if FileManager.default.fileExists(atPath: backupURL.path) {
            try? FileManager.default.removeItem(at: backupURL)
        }
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.copyItem(at: url, to: backupURL)
        }
        return true
    }
}
