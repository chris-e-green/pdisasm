import Foundation

public struct JSONDocumentExporter: Sendable {
  public init() {}

  public func data(for result: DisassemblyRunResult) throws -> Data {
    let export = JSONDisassemblyExport(result: result)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(export)
  }

  public func string(for result: DisassemblyRunResult) throws -> String {
    String(data: try data(for: result), encoding: .utf8) ?? "{}"
  }

  public func write(_ result: DisassemblyRunResult, to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data(for: result).write(to: url, options: .atomic)
  }
}

public struct CallGraphExporter: Sendable {
  public init() {}

  public func dot(for snapshot: ProgramSnapshot) -> String {
    var lines = ["digraph pdisasm_call_graph {"]
    for procedure in snapshot.procedures.values.sorted(by: { $0.id.description < $1.id.description }
    ) {
      lines.append(
        "  \"\(escape(procedure.id.description))\" [label=\"\(escape(procedure.name))\"];")
    }
    let edges = snapshot.callsByOrigin.values.flatMap { $0 }.sorted {
      $0.id.description < $1.id.description
    }
    for edge in edges {
      lines.append(
        "  \"\(escape(edge.origin.procedure.description))\" -> \"\(escape(edge.target.description))\";"
      )
    }
    lines.append("}")
    return lines.joined(separator: "\n") + "\n"
  }

  public func write(_ snapshot: ProgramSnapshot, to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try dot(for: snapshot).write(to: url, atomically: true, encoding: .utf8)
  }

  private func escape(_ value: String) -> String {
    value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
  }
}

public struct BatchDisassemblyResult: Sendable {
  public let results: [DisassemblyRunResult]

  public init(results: [DisassemblyRunResult]) {
    self.results = results
  }
}

public struct BatchDisassemblyService: Sendable {
  public let service: DisassemblyService
  public init(service: DisassemblyService = DisassemblyService()) { self.service = service }

  public func run(
    files: [URL], options: DisassemblyOptions = DisassemblyOptions(),
    workspace: MetadataWorkspace? = nil
  ) throws -> BatchDisassemblyResult {
    let results = try files.map { file in
      try service.run(
        DisassemblyRunRequest(source: .file(file), metadataWorkspace: workspace, options: options))
    }
    return BatchDisassemblyResult(results: results)
  }
}

private struct JSONDisassemblyExport: Encodable {
  let codeFileID: String
  let title: String
  let report: JSONRunReport
  let segments: [JSONSegment]
  let procedures: [JSONProcedure]
  let instructions: [JSONInstruction]
  let calls: [JSONCall]
  let locations: [JSONLocation]
  let document: [JSONDocumentNode]

  init(result: DisassemblyRunResult) {
    self.codeFileID = result.snapshot.codeFileID.value
    self.title = result.document.title
    self.report = JSONRunReport(report: result.report)
    self.segments = result.snapshot.segments.values.sorted { $0.id.description < $1.id.description }
      .map(JSONSegment.init)
    self.procedures = result.snapshot.procedures.values.sorted {
      $0.id.description < $1.id.description
    }.map(JSONProcedure.init)
    self.instructions = result.snapshot.instructions.values.sorted {
      $0.id.description < $1.id.description
    }.map(JSONInstruction.init)
    self.calls = result.snapshot.callsByOrigin.values.flatMap { $0 }.sorted {
      $0.id.description < $1.id.description
    }.map(JSONCall.init)
    self.locations = result.snapshot.locations.values.sorted {
      $0.id.description < $1.id.description
    }.map(JSONLocation.init)
    self.document = result.document.nodes.map(JSONDocumentNode.init)
  }
}

private struct JSONRunReport: Encodable {
  let isComplete: Bool
  let stages: [StageReport]
  init(report: RunReport) {
    isComplete = report.isComplete
    stages = report.stages
  }
}
private struct JSONSegment: Encodable {
  let id: String
  let name: String
  let procedures: [String]
  init(_ s: SegmentSnapshot) {
    id = s.id.description
    name = s.name
    procedures = s.procedureIDs.map(\.description)
  }
}
private struct JSONProcedure: Encodable {
  let id: String
  let name: String
  let isFunction: Bool
  let isAssembly: Bool
  let lexicalLevel: Int
  let dataSize: Int
  let parameterSize: Int
  let instructions: [String]
  init(_ p: ProcedureSnapshot) {
    id = p.id.description
    name = p.name
    isFunction = p.isFunction
    isAssembly = p.isAssembly
    lexicalLevel = p.lexicalLevel
    dataSize = p.dataSize
    parameterSize = p.parameterSize
    instructions = p.instructionIDs.map(\.description)
  }
}
private struct JSONInstruction: Encodable {
  let id: String
  let opcode: UInt8
  let mnemonic: String
  let parameters: [Int]
  let locationID: String?
  let destinationID: String?
  let comment: String?
  let userComment: String?
  init(_ i: InstructionSnapshot) {
    id = i.id.description
    opcode = i.opcode
    mnemonic = i.mnemonic
    parameters = i.parameters
    locationID = i.locationID?.description
    destinationID = i.destinationID?.description
    comment = i.comment
    userComment = i.userComment
  }
}
private struct JSONCall: Encodable {
  let id: String
  let origin: String
  let target: String
  init(_ c: CallEdge) {
    id = c.id.description
    origin = c.origin.description
    target = c.target.description
  }
}
private struct JSONLocation: Encodable {
  let id: String
  let name: String
  let type: String
  let typeSource: String
  let isParameter: Bool
  init(_ l: LocationFact) {
    id = l.id.description
    name = l.name
    type = l.type
    typeSource = l.typeSource.rawValue
    isParameter = l.isParameter
  }
}
private struct JSONDocumentNode: Encodable {
  let id: String
  let kind: String
  let text: String
  let anchor: String?
  init(_ n: DocumentNode) {
    id = n.id.description
    kind = String(describing: n.line.kind)
    text = n.line.text
    anchor = n.line.anchor
  }
}
