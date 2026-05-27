import ArgumentParser
import Foundation
import pdisasm

struct PdisasmCLI: @preconcurrency ParsableCommand {
    @Argument(help: "The file to decompile.")
    var filename: String = "Tests/pdisasmTests/Fixtures/SYSTEM.LIBRARY-02-00.bin"
    @Flag(help: "Run with verbose output.")
    var verbose: Bool = false
    @Flag(help: "Write and overwrite metadata files.")
    var rewrite: Bool = false
    @Flag(help: "Show markup in output.")
    var showMarkup: Bool = false
    @Flag(help: "Show pcode in output.")
    var showPcode: Bool = false
    @Flag(help: "Show pseudocode in output.")
    var showPseudocode: Bool = false
    @Flag(help: "Show graphviz DOT file for call tree in output.")
    var showDot: Bool = false
    @MainActor mutating func run() throws {
        print(
            "pdisasm-cli: running decompiler on \(filename) (verbose=\(verbose))"
        )
        do {
            try runPdisasm(
                filename: filename,
                verbose: verbose,
                rewrite: rewrite,
                showMarkup: showMarkup,
                showPCode: showPcode,
                showPseudoCode: showPseudocode,
                showDot: showDot
            )
        } catch {
            print("Error running pdisasm: \(error)")
            throw error
        }
    }
}

struct Main {
    static func main() throws {
        PdisasmCLI.main()
    }
}
try Main.main()
