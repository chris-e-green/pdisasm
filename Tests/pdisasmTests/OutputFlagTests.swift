import XCTest
@testable import pdisasm
import Foundation

final class OutputFlagTests: XCTestCase {

    /// Captures stdout output from a closure.
    private func captureOutput(_ block: () -> Void) -> String {
        let originalStdout = dup(STDOUT_FILENO)
        let pipefds = UnsafeMutablePointer<Int32>.allocate(capacity: 2)
        defer { pipefds.deallocate() }
        pipe(pipefds)
        fflush(stdout)
        dup2(pipefds[1], STDOUT_FILENO)

        block()

        fflush(stdout)
        dup2(originalStdout, STDOUT_FILENO)
        close(originalStdout)
        close(pipefds[1])
        let readFD = pipefds[0]
        var outData = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(readFD, &buffer, 4096)
            if n <= 0 { break }
            outData.append(buffer, count: n)
        }
        close(readFD)
        return String(data: outData, encoding: .utf8) ?? ""
    }

    private func makeMinimalInputs() -> (SegDictionary, [Int: CodeSegment], Set<Location>, [ProcedureIdentifier], Set<Call>) {
        let seg = Segment(codeAddress: 0, codeLength: 0, name: "TEST", segmentKind: .dataseg, textAddress: 0, segNum: 0, machineType: 0, version: 0)
        let dict = SegDictionary(segTable: [0: seg], intrinsics: [], comment: "")

        let proc = Procedure()
        proc.identifier = ProcedureIdentifier(isFunction: false, segment: 0, segmentName: "TEST", procedure: 1, procName: "MYPROC")
        proc.instructions[0] = Instruction(opcode: 0xAD, mnemonic: "RNP", params: [0], comment: "Return", stackState: [])
        proc.entryPoints = [0]

        let codeSeg = CodeSegment(procedureDictionary: ProcedureDictionary(procedureCount: 1, procedurePointers: [0]), procedures: [proc])
        let codeSegs: [Int: CodeSegment] = [0: codeSeg]
        let allProcedures: [ProcedureIdentifier] = [proc.identifier!]

        return (dict, codeSegs, [], allProcedures, [])
    }

    // MARK: - showDot

    func testShowDotProducesDigraph() {
        let (dict, codeSegs, locs, procs, callers) = makeMinimalInputs()
        let out = captureOutput {
            outputResults(sourceFilename: "test", segDictionary: dict, codeSegs: codeSegs, allLocations: locs, allProcedures: procs, allCallers: callers, showDot: true)
        }
        XCTAssertTrue(out.contains("digraph {"))
        XCTAssertTrue(out.contains("}"))
    }

    // MARK: - showMarkup

    func testShowMarkupTrue() {
        let (dict, codeSegs, locs, procs, callers) = makeMinimalInputs()
        let out = captureOutput {
            outputResults(sourceFilename: "test", segDictionary: dict, codeSegs: codeSegs, allLocations: locs, allProcedures: procs, allCallers: callers, showMarkup: true, showPCode: true)
        }
        XCTAssertTrue(out.contains("#  test"))
        XCTAssertTrue(out.contains("## Segment"))
        XCTAssertTrue(out.contains("```"))
    }

    func testShowMarkupFalseSuppressesMarkdown() {
        let (dict, codeSegs, locs, procs, callers) = makeMinimalInputs()
        let out = captureOutput {
            outputResults(sourceFilename: "test", segDictionary: dict, codeSegs: codeSegs, allLocations: locs, allProcedures: procs, allCallers: callers, showMarkup: false, showPCode: true)
        }
        XCTAssertFalse(out.contains("#  test"))
        XCTAssertFalse(out.contains("## Segment"))
    }

    // MARK: - showPCode

    func testShowPCodeTrueIncludesInstructions() {
        let (dict, codeSegs, locs, procs, callers) = makeMinimalInputs()
        let out = captureOutput {
            outputResults(sourceFilename: "test", segDictionary: dict, codeSegs: codeSegs, allLocations: locs, allProcedures: procs, allCallers: callers, showPCode: true)
        }
        XCTAssertTrue(out.contains("RNP"))
    }

    func testShowPCodeFalseSuppressesInstructions() {
        let (dict, codeSegs, locs, procs, callers) = makeMinimalInputs()
        let out = captureOutput {
            outputResults(sourceFilename: "test", segDictionary: dict, codeSegs: codeSegs, allLocations: locs, allProcedures: procs, allCallers: callers, showPCode: false)
        }
        XCTAssertFalse(out.contains("0000:"))
    }

    // MARK: - showPseudoCode

    func testShowPseudoCodeTrueIncludesBEGINEND() {
        let (dict, codeSegs, locs, procs, callers) = makeMinimalInputs()
        let out = captureOutput {
            outputResults(sourceFilename: "test", segDictionary: dict, codeSegs: codeSegs, allLocations: locs, allProcedures: procs, allCallers: callers, showPseudoCode: true)
        }
        XCTAssertTrue(out.contains("BEGIN"))
        XCTAssertTrue(out.contains("END"))
    }

    func testShowPseudoCodeFalseSuppressesBEGINEND() {
        let (dict, codeSegs, locs, procs, callers) = makeMinimalInputs()
        let out = captureOutput {
            outputResults(sourceFilename: "test", segDictionary: dict, codeSegs: codeSegs, allLocations: locs, allProcedures: procs, allCallers: callers, showPseudoCode: false)
        }
        XCTAssertFalse(out.contains("BEGIN"))
    }
}
