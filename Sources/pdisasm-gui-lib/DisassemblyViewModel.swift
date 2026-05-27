import Foundation
import Observation
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
    var showMarkup: Bool = true { didSet { rebuildFilteredLinesAndSearchMatches() } }
    var showPCode: Bool = true { didSet { rebuildFilteredLinesAndSearchMatches() } }
    var showPseudoCode: Bool = true { didSet { rebuildFilteredLinesAndSearchMatches() } }
    var showVariables: Bool = true { didSet { rebuildFilteredLinesAndSearchMatches() } }
    var verbose: Bool = false

    /// The anchor ID of the procedure to scroll to (e.g. "2.3"). Set by sidebar selection.
    var selectedProcedure: String?

    // MARK: - Search

    var searchText: String = "" { didSet { scheduleDebouncedSearchCommit() } }
    /// Query currently active for matching; updated only when the user submits.
    var committedSearchText: String = ""
    var currentMatchIndex: Int = 0
    var isSearching: Bool = false
    var liveSearchMatchCount: Int = 0
    var searchScannedLineCount: Int = 0
    var searchTotalLineCount: Int = 0

    /// Indices into `filteredLines` that match the committed search query.
    var searchMatchIndices: [Int] = []

    enum SearchStatusWidthPreset: String, CaseIterable, Identifiable {
        case compact
        case medium
        case wide

        var id: String { rawValue }

        var width: Double {
            switch self {
            case .compact: return 200
            case .medium:  return 280
            case .wide:    return 360
            }
        }

        var title: String {
            switch self {
            case .compact: return "Status Width: Compact"
            case .medium:  return "Status Width: Medium"
            case .wide:    return "Status Width: Wide"
            }
        }
    }

    var searchStatusWidthPreset: SearchStatusWidthPreset = .medium {
        didSet {
            UserDefaults.standard.set(searchStatusWidthPreset.rawValue, forKey: Self.searchStatusWidthPresetKey)
        }
    }

    /// The anchor string for the current search match, if any.
    var currentMatchAnchor: String? {
        guard !searchMatchIndices.isEmpty else { return nil }
        let idx = searchMatchIndices[min(currentMatchIndex, searchMatchIndices.count - 1)]
        let line = filteredLines[idx]
        return line.anchor ?? "line-\(line.id)"
    }

    func nextMatch() {
        let count = searchMatchIndices.count
        guard count > 0 else { return }
        currentMatchIndex = (currentMatchIndex + 1) % count
    }

    func previousMatch() {
        let count = searchMatchIndices.count
        guard count > 0 else { return }
        currentMatchIndex = (currentMatchIndex - 1 + count) % count
    }

    func commitSearch() {
        searchDebounceTask?.cancel()
        committedSearchText = searchText
        rebuildSearchMatches(resetCurrentIndex: true)
    }

    func lineMatchesCommittedSearch(atFilteredIndex index: Int) -> Bool {
        searchMatchIndexSet.contains(index)
    }

    func isCurrentMatch(atFilteredIndex index: Int) -> Bool {
        guard searchMatchIndices.indices.contains(currentMatchIndex) else { return false }
        return index == searchMatchIndices[currentMatchIndex]
    }

    private func makeWholeWordWildcardRegex(from query: String) -> String {
        var escaped = NSRegularExpression.escapedPattern(for: query)
        escaped = escaped.replacingOccurrences(of: #"\\\*"#, with: #"[A-Za-z0-9_]*"#, options: .regularExpression)
        escaped = escaped.replacingOccurrences(of: #"\\\?"#, with: #"[A-Za-z0-9_]"#, options: .regularExpression)
        return #"\b"# + escaped + #"\b"#
    }

    // MARK: - Backing data (produced once per file open / reload)

    /// All lines produced by the last disassembly, always includes every kind.
    private var allLines: [OutputLine] = []
    private var searchMatchIndexSet: Set<Int> = []
    private var searchDebounceTask: Task<Void, Never>?
    private var searchRebuildTask: Task<Void, Never>?
    private var searchRevision: Int = 0

    private static let searchDebounceDelayNanoseconds: UInt64 = 250_000_000
    private static let asyncSearchThreshold = 3000
    private static let asyncSearchChunkSize = 750
    private static let searchStatusWidthPresetKey = "searchStatusWidthPreset"

    // MARK: - Derived / filtered view

    /// Lines filtered by the current toggle state.
    var filteredLines: [OutputLine] = []

    private func filterLines() -> [OutputLine] {
        allLines.filter { line in
            switch line.kind {
            case .markup:      return showMarkup
            case .pcode:       return showPCode
            case .pseudocode:  return showPseudoCode
            case .variable:    return showVariables
            case .global:      return true       // always show globals
            case .header:      return true       // always show procedure headers
            case .diagnostic:  return true       // always show diagnostics
            }
        }
    }

    private func rebuildFilteredLinesAndSearchMatches() {
        filteredLines = filterLines()
        rebuildSearchMatches(resetCurrentIndex: false)
    }

    private func scheduleDebouncedSearchCommit() {
        searchDebounceTask?.cancel()
        let pendingQuery = searchText
        searchDebounceTask = Task {
            try? await Task.sleep(nanoseconds: Self.searchDebounceDelayNanoseconds)
            guard !Task.isCancelled else { return }
            guard pendingQuery == self.searchText else { return }
            self.committedSearchText = pendingQuery
            self.rebuildSearchMatches(resetCurrentIndex: true)
        }
    }

    nonisolated private static func computeMatchIndices(lines: [OutputLine], pattern: String, indexOffset: Int = 0) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        var matches: [Int] = []
        matches.reserveCapacity(min(lines.count, 256))
        for (idx, line) in lines.enumerated() {
            let range = NSRange(line.text.startIndex..<line.text.endIndex, in: line.text)
            if regex.firstMatch(in: line.text, options: [], range: range) != nil {
                matches.append(indexOffset + idx)
            }
        }
        return matches
    }

    private func applySearchMatches(_ matches: [Int], resetCurrentIndex: Bool) {
        searchMatchIndices = matches
        searchMatchIndexSet = Set(matches)

        if matches.isEmpty {
            currentMatchIndex = 0
        } else if resetCurrentIndex {
            currentMatchIndex = 0
        } else if currentMatchIndex >= matches.count {
            currentMatchIndex = matches.count - 1
        }
    }

    private func rebuildSearchMatches(resetCurrentIndex: Bool) {
        searchRebuildTask?.cancel()
        isSearching = false
        liveSearchMatchCount = 0
        searchScannedLineCount = 0
        searchTotalLineCount = 0
        let query = committedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            applySearchMatches([], resetCurrentIndex: true)
            return
        }

        let pattern = makeWholeWordWildcardRegex(from: query)
        let linesSnapshot = filteredLines
        let nextRevision = searchRevision &+ 1
        searchRevision = nextRevision

        if linesSnapshot.count < Self.asyncSearchThreshold {
            let matches = Self.computeMatchIndices(lines: linesSnapshot, pattern: pattern)
            applySearchMatches(matches, resetCurrentIndex: resetCurrentIndex)
            return
        }

        isSearching = true
        searchTotalLineCount = linesSnapshot.count
        if resetCurrentIndex {
            currentMatchIndex = 0
        }
        searchMatchIndices = []
        searchMatchIndexSet = []

        searchRebuildTask = Task { [linesSnapshot, pattern, resetCurrentIndex, nextRevision] in
            var allMatches: [Int] = []
            allMatches.reserveCapacity(min(linesSnapshot.count, 512))

            for start in stride(from: 0, to: linesSnapshot.count, by: Self.asyncSearchChunkSize) {
                let end = min(start + Self.asyncSearchChunkSize, linesSnapshot.count)
                let chunk = Array(linesSnapshot[start..<end])
                let chunkMatches = await Task.detached(priority: .userInitiated) {
                    Self.computeMatchIndices(lines: chunk, pattern: pattern, indexOffset: start)
                }.value

                guard !Task.isCancelled else { return }
                guard self.searchRevision == nextRevision else { return }

                allMatches.append(contentsOf: chunkMatches)
                self.searchScannedLineCount = end
                self.liveSearchMatchCount = allMatches.count
            }

            guard !Task.isCancelled else { return }
            guard self.searchRevision == nextRevision else { return }
            self.applySearchMatches(allMatches, resetCurrentIndex: resetCurrentIndex)
            self.isSearching = false
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

    /// CSV filenames relevant to the currently loaded file.
    var relevantMetadataFiles: [String] = []

    // MARK: - Actions

    private static let lastFileBookmarkKey = "lastOpenedFileBookmark"

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.searchStatusWidthPresetKey),
           let preset = SearchStatusWidthPreset(rawValue: raw)
        {
            searchStatusWidthPreset = preset
        }
    }

    func openFile(url: URL) {
        fileURL = url
        persistURL(url)
        runDisassembly()
    }

    /// Call once at launch to reopen the last file.
    func restoreLastFile() {
        guard let data = UserDefaults.standard.data(forKey: Self.lastFileBookmarkKey) else { return }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return }
        if isStale { persistURL(url) }
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        fileURL = url
        runDisassembly()
    }

    private func persistURL(_ url: URL) {
        let data = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(data, forKey: Self.lastFileBookmarkKey)
    }

    func runDisassembly() {
        guard let url = fileURL else { return }
        searchDebounceTask?.cancel()
        searchRebuildTask?.cancel()
        isSearching = false
        liveSearchMatchCount = 0
        searchScannedLineCount = 0
        searchTotalLineCount = 0
        isLoading = true
        errorMessage = nil
        allLines = []
        filteredLines = []
        searchMatchIndices = []
        searchMatchIndexSet = []
        currentMatchIndex = 0
        segments = []

        let path = url.path
        let verb = verbose

        Task {
            do {
                let (lines, items, relevantFiles) = try await Task.detached {
                    let result = try disassemble(
                        filename: path,
                        verbose: verb
                    )
                    let lines = renderStructuredLines(
                        from: result,
                        verbose: verb
                    )

                    // Determine relevant metadata CSV filenames
                    let fileIdentifier = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                    let version = result.segDictionary.segTable[1]?.version ?? result.segDictionary.segTable[0]?.version ?? 0
                    let relevantFiles = [
                        "labels_\(fileIdentifier).csv",
                        "labels_ver_\(version).csv",
                        "procedures_\(fileIdentifier).csv",
                        "procedures_ver_\(version).csv"
                    ]

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
                    return (lines, items, relevantFiles)
                }.value

                self.allLines = lines
                self.rebuildFilteredLinesAndSearchMatches()
                self.segments = items
                self.relevantMetadataFiles = relevantFiles
                self.isLoading = false
            } catch {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}
