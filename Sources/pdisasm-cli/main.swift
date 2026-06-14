import Foundation
import pdisasm

struct PdisasmCLI {
    var filename: String = "Tests/pdisasmTests/Fixtures/SYSTEM.LIBRARY-02-00.bin"
    var verbose = false
    var rewrite = false
    var showMarkup = false
    var showPcode = false
    var showStackState = false
    var showPseudocode = false
    var showDot = false

    init(arguments: [String]) throws {
        var positional: [String] = []
        for argument in arguments.dropFirst() {
            switch argument {
            case "--verbose": verbose = true
            case "--rewrite": rewrite = true
            case "--show-markup": showMarkup = true
            case "--show-pcode": showPcode = true
            case "--show-stack-state": showStackState = true
            case "--show-pseudocode": showPseudocode = true
            case "--show-dot": showDot = true
            case "--help", "-h":
                print(Self.helpText)
                Foundation.exit(0)
            default:
                if argument.hasPrefix("-") { throw CLIError.unknownOption(argument) }
                positional.append(argument)
            }
        }
        if let first = positional.first { filename = first }
        if positional.count > 1 { throw CLIError.tooManyArguments(positional.dropFirst().joined(separator: " ")) }
    }

    func run() throws {
        print("pdisasm-cli: running decompiler on \(filename) (verbose=\(verbose))")
        try runPdisasm(filename: filename, verbose: verbose, rewrite: rewrite, showMarkup: showMarkup, showPCode: showPcode, showStackState: showStackState, showPseudoCode: showPseudocode, showDot: showDot)
    }

    static let helpText = """
    USAGE: pdisasm-cli [file] [--verbose] [--rewrite] [--show-markup] [--show-pcode] [--show-stack-state] [--show-pseudocode] [--show-dot]
    """
}

enum CLIError: Error, CustomStringConvertible {
    case unknownOption(String)
    case tooManyArguments(String)
    var description: String {
        switch self {
        case .unknownOption(let option): return "Unknown option: \(option)"
        case .tooManyArguments(let args): return "Too many positional arguments: \(args)"
        }
    }
}

do {
    try PdisasmCLI(arguments: CommandLine.arguments).run()
} catch {
    print("Error running pdisasm: \(error)")
    Foundation.exit(1)
}
