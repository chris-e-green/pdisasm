import Foundation

struct MetadataStore {
    let appSupportDirectory: URL
    var bundledDirectory: URL? = nil
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
            try writeLabelsCSV(labels, to: file, overwrite: overwrite)
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
            try writeProceduresCSV(procedures, to: file, overwrite: overwrite)
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

    func importDisassemblyComments(
        fromJson file: String,
        to comments: inout [InstructionReference: String]
    ) {
        if let loadedComments: [DisassemblyComment] = try? readJSON(file) {
            comments = Dictionary(uniqueKeysWithValues: loadedComments.map {
                ($0.reference, $0.comment)
            })
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

    func importTypeDefinitions(
        fromPascal file: String,
        to knownRecords: inout Set<PascalRecord>,
        aliases: inout [String: String],
        scalarTypes: inout [String: PascalScalarType],
        constants: inout [String: Int],
        constantValues: inout [String: PascalConstantValue],
        subrangeTypes: inout [String: PascalSubrangeType],
        isSystemRecord: Bool = false
    ) {
        do {
            guard let source = try readText(file, extension: "pas") else { return }
            let definitions = PascalTypeDefinitionParser.parse(
                source,
                isSystemRecord: isSystemRecord
            )
            knownRecords.formUnion(definitions.records)
            aliases.merge(definitions.aliases) { _, new in new }
            scalarTypes.merge(definitions.scalarTypes) { _, new in new }
            constants.merge(definitions.constants) { _, new in new }
            constantValues.merge(definitions.constantValues) { _, new in new }
            subrangeTypes.merge(definitions.subrangeTypes) { _, new in new }
            for diagnostic in definitions.diagnostics {
                switch diagnostic.severity {
                case .warning:
                    diagnostics?.warning(diagnostic.message)
                case .error:
                    diagnostics?.error(diagnostic.message)
                }
            }
        } catch {
            diagnostics?.error("Error reading \(file).pas: \(error)")
        }
    }

    private func fileURL(_ file: String, extension fileExtension: String) -> URL {
        appSupportDirectory
            .appendingPathComponent(file)
            .appendingPathExtension(fileExtension)
    }

    private func existingReadURL(_ file: String, extension fileExtension: String) -> URL? {
        let primary = fileURL(file, extension: fileExtension)
        if FileManager.default.fileExists(atPath: primary.path) { return primary }
        let bundledMetadata = (bundledDirectory ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("metadata", isDirectory: true))
            .appendingPathComponent(file)
            .appendingPathExtension(fileExtension)
        if FileManager.default.fileExists(atPath: bundledMetadata.path) { return bundledMetadata }
        return nil
    }

    private func readCSV<Value>(_ file: String) throws -> Value? {
        guard let url = existingReadURL(file, extension: "csv") else { return nil }
        let rows = try CSVTable(contentsOf: url)
        if Value.self == Set<Location>.self {
            return Set(rows.records.map(Location.init(csv:))) as? Value
        }
        if Value.self == [ProcedureIdentifier].self {
            return rows.records.map(ProcedureIdentifier.init(csv:)) as? Value
        }
        throw MetadataCSVError.unsupportedType(String(describing: Value.self))
    }

    func writeLabelsCSV(
        _ labels: [Location],
        to file: String,
        overwrite: Bool
    ) throws {
        let url = fileURL(file, extension: "csv")
        guard try prepareWrite(to: url, overwrite: overwrite) else { return }
        let headers = ["segment", "procedure", "lexLevel", "addr", "name", "type", "typeSource"]
        let rows = labels.map { label in
            [String(label.segment), label.procedure.csvString, label.lexLevel.csvString, label.addr.csvString, label.name, label.type, label.typeSource.rawValue]
        }
        try CSVTable.write(headers: headers, rows: rows, to: url)
    }

    func writeProceduresCSV(
        _ procedures: [ProcedureIdentifier],
        to file: String,
        overwrite: Bool
    ) throws {
        let url = fileURL(file, extension: "csv")
        guard try prepareWrite(to: url, overwrite: overwrite) else { return }
        let headers = ["segmentNumber", "segmentName", "procNumber", "procName", "isFunction", "isAssembly", "parameters", "parameterModes", "parameterModeSources", "returnType", "returnTypeSource"]
        let rows = procedures.map { proc in
            [
                String(proc.segment),
                proc.segmentName ?? "",
                String(proc.procedure),
                proc.procName ?? "",
                String(proc.isFunction),
                String(proc.isAssembly),
                proc.parameters.map(\.description).joined(separator: ";"),
                proc.parameters.map(\.parameterMode.rawValue).joined(separator: ";"),
                proc.parameters.map(\.parameterModeSource.rawValue).joined(separator: ";"),
                proc.returnType ?? "",
                proc.returnTypeSource.rawValue
            ]
        }
        try CSVTable.write(headers: headers, rows: rows, to: url)
    }

    private func readJSON<Value: Decodable>(_ file: String) throws -> Value? {
        guard let url = existingReadURL(file, extension: "json") else { return nil }
        let decoder = JSONDecoder()
        let data = try Data(contentsOf: url)
        return try decoder.decode(Value.self, from: data)
    }

    private func readText(_ file: String, extension fileExtension: String) throws -> String? {
        guard let url = existingReadURL(file, extension: fileExtension) else { return nil }
        return try String(contentsOf: url, encoding: .utf8)
    }

    func writeJSON<Value: Encodable>(
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

private enum MetadataCSVError: Error, CustomStringConvertible {
    case unsupportedType(String)
    var description: String {
        switch self { case .unsupportedType(let type): return "Unsupported CSV metadata type: \(type)" }
    }
}

struct CSVTable {
    let records: [[String: String]]

    init(contentsOf url: URL) throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        let rows = Self.parse(text)
        guard let headers = rows.first else { records = []; return }
        records = rows.dropFirst().filter { !$0.allSatisfy(\.isEmpty) }.map { row in
            Dictionary(uniqueKeysWithValues: headers.enumerated().map { index, header in
                (header, index < row.count ? row[index] : "")
            })
        }
    }

    static func write(headers: [String], rows: [[String]], to url: URL) throws {
        let lines = ([headers] + rows).map { $0.map(escape).joined(separator: ",") }
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private static func escape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    private static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.makeIterator()
        while let char = iterator.next() {
            if inQuotes {
                if char == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append(next) } else {
                            inQuotes = false
                            if next == "," { row.append(field); field = "" }
                            else if next == "\n" { row.append(field); rows.append(row); row = []; field = "" }
                            else if next != "\r" { field.append(next) }
                        }
                    } else { inQuotes = false }
                } else { field.append(char) }
            } else {
                if char == "\"" { inQuotes = true }
                else if char == "," { row.append(field); field = "" }
                else if char == "\n" { row.append(field); rows.append(row); row = []; field = "" }
                else if char != "\r" { field.append(char) }
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
}

private extension Optional where Wrapped == Int {
    var csvString: String { map(String.init) ?? "" }
}

extension Location {
    convenience init(csv record: [String: String]) {
        self.init(
            segment: Int(record["segment"] ?? "") ?? 0,
            procedure: Int(record["procedure"] ?? ""),
            lexLevel: Int(record["lexLevel"] ?? ""),
            addr: Int(record["addr"] ?? ""),
            name: record["name"] ?? "",
            type: record["type"] ?? "",
            typeSource: TypeSource(rawValue: record["typeSource"] ?? "")
        )
    }
}

extension ProcedureIdentifier {
    convenience init(csv record: [String: String]) {
        var parameters = (record["parameters"] ?? "").split(separator: ";").map { raw in
            let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
            return Identifier(name: parts.first ?? "", type: parts.count > 1 ? parts[1] : "")
        }
        let modes = (record["parameterModes"] ?? "").split(
            separator: ";",
            omittingEmptySubsequences: false
        )
        let modeSources = (record["parameterModeSources"] ?? "").split(
            separator: ";",
            omittingEmptySubsequences: false
        )
        for index in parameters.indices {
            guard modes.indices.contains(index),
                  let mode = ParameterMode(rawValue: String(modes[index]))
            else { continue }
            parameters[index].parameterMode = mode
            parameters[index].parameterModeSource = modeSources.indices.contains(index)
                ? ParameterModeSource(rawValue: String(modeSources[index]))
                    ?? (mode == .unknown ? .unknown : .metadata)
                : (mode == .unknown ? .unknown : .metadata)
        }
        self.init(
            isFunction: Bool(record["isFunction"] ?? "false") ?? false,
            isAssembly: Bool(record["isAssembly"] ?? "false") ?? false,
            segment: Int(record["segmentNumber"] ?? "") ?? 0,
            segmentName: record["segmentName"].flatMap { $0.isEmpty ? nil : $0 },
            procedure: Int(record["procNumber"] ?? "") ?? 0,
            procName: record["procName"].flatMap { $0.isEmpty ? nil : $0 },
            parameters: parameters,
            returnType: record["returnType"].flatMap { $0.isEmpty ? nil : $0 },
            returnTypeSource: TypeSource(rawValue: record["returnTypeSource"] ?? "")
        )
    }
}
