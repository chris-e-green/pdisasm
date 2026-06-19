import Foundation
import pdisasm

/// Owns the GUI document session lifecycle and keeps rerun/cancellation policy out of the view model.
@MainActor
final class DocumentSessionController {
    struct PresentationModel {
        let result: DisassemblyResult
        let runResult: DisassemblyRunResult
        let lines: [OutputLine]
        let segments: [DisassemblyViewModel.SegmentItem]
        let relevantMetadataFiles: [String]
    }

    private final class SessionCancellationToken: CancellationToken, @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false

        var isCancellationRequested: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }

        func cancel() {
            lock.lock()
            cancelled = true
            lock.unlock()
        }
    }

    private var currentTask: Task<PresentationModel, Error>?
    private var currentCancellation: SessionCancellationToken?
    private var runGeneration = 0
    private let service: DisassemblyService

    private(set) var sourceURL: URL?
    private(set) var runResult: DisassemblyRunResult?

    init(service: DisassemblyService = DisassemblyService()) {
        self.service = service
    }

    func open(url: URL) {
        cancelRun()
        sourceURL = url
        runResult = nil
    }

    func cancelRun() {
        currentCancellation?.cancel()
        currentTask?.cancel()
        currentCancellation = nil
        currentTask = nil
    }

    func rerun(verbose: Bool, showStackState: Bool) async throws -> PresentationModel {
        guard let sourceURL else { throw SessionError.noOpenFile }
        cancelRun()
        runGeneration &+= 1
        let generation = runGeneration

        let token = SessionCancellationToken()
        currentCancellation = token
        let service = service
        let path = sourceURL.path
        let task = Task.detached(priority: .userInitiated) { () throws -> PresentationModel in
            let runResult = try service.run(DisassemblyRunRequest(
                source: .file(URL(fileURLWithPath: path)),
                options: DisassemblyOptions(verbose: verbose, showStackState: showStackState),
                cancellation: token
            ))
            try Task.checkCancellation()
            let result = runResult.legacyResult
            let lines = renderStructuredLines(
                from: result,
                showStackState: showStackState,
                verbose: verbose
            )
            let items = Self.buildSegmentItems(from: result)
            let relevantFiles = Self.relevantMetadataFiles(for: URL(fileURLWithPath: path), result: result)
            return PresentationModel(
                result: result,
                runResult: runResult,
                lines: lines,
                segments: items,
                relevantMetadataFiles: relevantFiles
            )
        }
        currentTask = task

        do {
            let model = try await task.value
            if runGeneration == generation {
                runResult = model.runResult
                currentTask = nil
                currentCancellation = nil
            }
            return model
        } catch {
            if runGeneration == generation {
                currentTask = nil
                currentCancellation = nil
            }
            throw error
        }
    }

    func applyEdit(invalidation: MetadataInvalidationScope, verbose: Bool, showStackState: Bool) async throws -> PresentationModel? {
        switch invalidation {
        case .none:
            return nil
        case .documentOnly, .patchDocument:
            // Existing renderers still derive location/signature/comment display from the legacy result.
            // Keep the policy centralized here and conservatively rerun until document patches cover all edit types.
            return try await rerun(verbose: verbose, showStackState: showStackState)
        case .procedureSignature, .propagateCallGraph, .fullDisassembly:
            return try await rerun(verbose: verbose, showStackState: showStackState)
        }
    }

    func indexedSearchNodeIDs(for query: String) -> [DocumentNodeID] {
        guard !query.contains("*") && !query.contains("?") else { return [] }
        return runResult?.indexes.search(query) ?? []
    }

    private static func buildSegmentItems(from result: DisassemblyResult) -> [DisassemblyViewModel.SegmentItem] {
        var items: [DisassemblyViewModel.SegmentItem] = []
        for (segIdx, codeSeg) in result.codeSegments.sorted(by: { $0.key < $1.key }) {
            let segName = result.segDictionary.segTable
                .first(where: { $0.value.segNum == segIdx })?.value.name ?? "Segment \(segIdx)"
            let procs = codeSeg.procedures.compactMap { proc -> DisassemblyViewModel.ProcedureItem? in
                guard let ident = proc.identifier else { return nil }
                let name = result.allProcedures
                    .first(where: { $0.segment == ident.segment && $0.procedure == ident.procedure })?
                    .shortDescription ?? ident.shortDescription
                return DisassemblyViewModel.ProcedureItem(segmentNumber: segIdx, number: ident.procedure, name: name)
            }
            items.append(DisassemblyViewModel.SegmentItem(id: segIdx, name: segName, procedures: procs))
        }
        return items
    }

    private static func relevantMetadataFiles(for url: URL, result: DisassemblyResult) -> [String] {
        let fileIdentifier = url.deletingPathExtension().lastPathComponent
        let version = result.segDictionary.segTable[1]?.version ?? result.segDictionary.segTable[0]?.version ?? 0
        return [
            "labels_\(fileIdentifier).csv",
            "labels_ver_\(version).csv",
            "procedures_\(fileIdentifier).csv",
            "procedures_ver_\(version).csv",
            "records_\(fileIdentifier).json",
            "records_ver_\(version).json",
            "types_\(fileIdentifier).pas",
            "types_ver_\(version).pas",
            "comments_\(fileIdentifier).json"
        ]
    }

    enum SessionError: LocalizedError {
        case noOpenFile

        var errorDescription: String? {
            switch self {
            case .noOpenFile:
                return "No disassembly file is open."
            }
        }
    }
}
