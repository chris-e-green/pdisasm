import Foundation
import pdisasm

/// Observable view model that drives the GUI.
@MainActor
@Observable
final class DisassemblyViewModel {
    // MARK: - State

    var isLoading: Bool = false
    var errorMessage: String?
    var fileURL: URL?
    var showFileImporter: Bool = false

    // Display toggles – changing these only filters; no re-disassembly.
    var showMarkup: Bool = true
    var showPCode: Bool = true
    var showPseudoCode: Bool = true
    var showVariables: Bool = true
    var verbose: Bool = false

    // MARK: - Backing data (produced once per file open / reload)

    /// All lines produced by the last disassembly, always includes every kind.
    private var allLines: [OutputLine] = []

    // MARK: - Derived / filtered view

    /// Lines filtered by the current toggle state.
    var filteredLines: [OutputLine] {
        allLines.filter { line in
            switch line.kind {
            case .markup:      return showMarkup
            case .pcode:       return showPCode
            case .pseudocode:  return showPseudoCode
            case .variable:    return showVariables
            case .global:      return true       // always show globals
            case .header:      return true       // always show procedure headers
            }
        }
    }

    /// True when there is disassembly output to display.
    var hasOutput: Bool { !allLines.isEmpty }

    // MARK: - Segment sidebar data

    struct SegmentItem: Identifiable {
        let id: Int
        let name: String
        let procedures: [ProcedureItem]
    }

    struct ProcedureItem: Identifiable {
        var id: String { "\(segmentNumber).\(number)" }
        let segmentNumber: Int
        let number: Int
        let name: String
    }

    var segments: [SegmentItem] = []

    // MARK: - Actions

    func openFile(url: URL) {
        fileURL = url
        runDisassembly()
    }

    func runDisassembly() {
        guard let url = fileURL else { return }
        isLoading = true
        errorMessage = nil
        allLines = []
        segments = []

        let path = url.path
        let verb = verbose

        Task {
            do {
                let (lines, items) = try await Task.detached {
                    let result = try disassemble(
                        filename: path,
                        verbose: verb
                    )
                    let lines = renderStructuredLines(
                        from: result,
                        verbose: verb
                    )

                    // Build sidebar items
                    var items: [DisassemblyViewModel.SegmentItem] = []
                    for (segIdx, codeSeg) in result.codeSegments.sorted(by: { $0.key < $1.key }) {
                        let segName = result.segDictionary.segTable
                            .first(where: { $0.value.segNum == segIdx })?.value.name ?? "Segment \(segIdx)"
                        let procs = codeSeg.procedures.compactMap { proc -> DisassemblyViewModel.ProcedureItem? in
                            guard let ident = proc.identifier else { return nil }
                            let name = result.allProcedures
                                .first(where: { $0.segment == ident.segment && $0.procedure == ident.procedure })?
                                .shortDescription ?? ident.shortDescription
                            return DisassemblyViewModel.ProcedureItem(
                                segmentNumber: segIdx,
                                number: ident.procedure,
                                name: name
                            )
                        }
                        items.append(DisassemblyViewModel.SegmentItem(
                            id: segIdx,
                            name: segName,
                            procedures: procs
                        ))
                    }
                    return (lines, items)
                }.value

                self.allLines = lines
                self.segments = items
                self.isLoading = false
            } catch {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}
