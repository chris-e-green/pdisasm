import Foundation
import pdisasm

struct PdisasmCLI {
  var filenames: [String] = ["Tests/pdisasmTests/Fixtures/SYSTEM.LIBRARY-02-00.bin"]
  var verbose = false
  var rewrite = false
  var showMarkup = false
  var showPcode = false
  var showStackState = false
  var showPseudocode = false
  var showDot = false
  var workspaceDirectory: String?
  var jsonOutput: String?
  var callGraphOutput: String?
  var batchMode = false

  init(arguments: [String]) throws {
    var positional: [String] = []
    var iterator = Array(arguments.dropFirst()).makeIterator()
    while let argument = iterator.next() {
      switch argument {
      case "--verbose": verbose = true
      case "--rewrite": rewrite = true
      case "--show-markup": showMarkup = true
      case "--show-pcode": showPcode = true
      case "--show-stack-state": showStackState = true
      case "--show-pseudocode": showPseudocode = true
      case "--show-dot": showDot = true
      case "--batch": batchMode = true
      case "--workspace":
        workspaceDirectory = try Self.requireValue(after: argument, from: &iterator)
      case "--json", "--export-json":
        jsonOutput = try Self.requireValue(after: argument, from: &iterator)
      case "--call-graph", "--export-call-graph":
        callGraphOutput = try Self.requireValue(after: argument, from: &iterator)
      case "--help", "-h":
        print(Self.helpText)
        Foundation.exit(0)
      default:
        if argument.hasPrefix("-") { throw CLIError.unknownOption(argument) }
        positional.append(argument)
      }
    }
    if !positional.isEmpty { filenames = positional }
    if filenames.count > 1 { batchMode = true }
    if filenames.count > 1 && jsonOutput != nil {
      throw CLIError.optionRequiresSingleFile("--json/--export-json")
    }
    if filenames.count > 1 && callGraphOutput != nil {
      throw CLIError.optionRequiresSingleFile("--call-graph/--export-call-graph")
    }
  }

  func run() throws {
    let workspace = workspaceDirectory.map { directory in
      MetadataWorkspace(
        writableDirectory: URL(fileURLWithPath: directory, isDirectory: true),
        bundledDirectory: URL(fileURLWithPath: directory, isDirectory: true)
      )
    }
    let options = DisassemblyOptions(
      verbose: verbose,
      writeMetadata: rewrite,
      overwriteMetadata: rewrite,
      showMarkup: showMarkup,
      showPCode: showPcode,
      showStackState: showStackState,
      showPseudoCode: showPseudocode,
      showDot: showDot
    )

    if batchMode {
      print(
        "pdisasm-cli: running batch decompiler on \(filenames.count) files (verbose=\(verbose))")
      let batch = try BatchDisassemblyService().run(
        files: filenames.map { URL(fileURLWithPath: $0) },
        options: options,
        workspace: workspace
      )
      let status = batch.results.map(\.report.status).reduce(RunStatus.success, Self.moreSevereStatus)
      Foundation.exit(status.processExitCode)
    }

    let filename = filenames[0]
    print("pdisasm-cli: running decompiler on \(filename) (verbose=\(verbose))")
    let result = try DisassemblyService().run(
      DisassemblyRunRequest(
        source: .file(URL(fileURLWithPath: filename)),
        metadataWorkspace: workspace,
        options: options
      ))

    if let jsonOutput {
      try JSONDocumentExporter().write(result, to: URL(fileURLWithPath: jsonOutput))
    } else if let callGraphOutput {
      try CallGraphExporter().write(result.snapshot, to: URL(fileURLWithPath: callGraphOutput))
    } else {
      print(
        renderDisassemblyDocument(
          result.document,
          showMarkup: showMarkup,
          showPCode: showPcode,
          showPseudoCode: showPseudocode
        ), terminator: "")
    }
    Foundation.exit(result.report.status.processExitCode)
  }

  private static func moreSevereStatus(_ lhs: RunStatus, _ rhs: RunStatus) -> RunStatus {
    let rank: [RunStatus: Int] = [.success: 0, .degradedSuccess: 1, .cancelled: 2, .fatalError: 3]
    return (rank[lhs] ?? 0) >= (rank[rhs] ?? 0) ? lhs : rhs
  }

  private static func requireValue(
    after option: String, from iterator: inout IndexingIterator<[String]>
  ) throws -> String {
    guard let value = iterator.next(), !value.hasPrefix("-") else {
      throw CLIError.missingValue(option)
    }
    return value
  }

  static let helpText = """
    USAGE: pdisasm-cli [file ...] [--batch] [--workspace dir] [--json file] [--call-graph file] [--verbose] [--rewrite] [--show-markup] [--show-pcode] [--show-stack-state] [--show-pseudocode] [--show-dot]
    """
}

enum CLIError: Error, CustomStringConvertible {
  case unknownOption(String)
  case missingValue(String)
  case optionRequiresSingleFile(String)
  var description: String {
    switch self {
    case .unknownOption(let option): return "Unknown option: \(option)"
    case .missingValue(let option): return "Missing value for option: \(option)"
    case .optionRequiresSingleFile(let option):
      return "\(option) can only be used with one input file"
    }
  }
}

do {
  try PdisasmCLI(arguments: CommandLine.arguments).run()
} catch {
  print("Error running pdisasm: \(error)")
  Foundation.exit(1)
}
