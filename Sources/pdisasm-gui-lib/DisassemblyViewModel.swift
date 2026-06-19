import AppKit
import Foundation
import Observation
import pdisasm

/// Observable view model that drives the GUI.
@MainActor
@Observable
final class DisassemblyViewModel {
    struct LocationEditDraft: Identifiable {
        let id = UUID()
        let reference: LocationReference
        let originalDisplayName: String
        let sourceFilteredIndex: Int?
        var name: String
        var type: String

        var title: String {
            originalDisplayName
        }
    }

    struct ProcedureSignatureEditDraft: Identifiable {
        enum Field {
            case procedureName
            case parameter(Int)
            case returnType
        }

        let id = UUID()
        let segment: Int
        let procedure: Int
        let field: Field
        let title: String
        var name: String
        var type: String

        var editsName: Bool {
            switch field {
            case .procedureName, .parameter:
                return true
            case .returnType:
                return false
            }
        }

        var editsType: Bool {
            switch field {
            case .parameter, .returnType:
                return true
            case .procedureName:
                return false
            }
        }
    }

    struct CommentEditDraft: Identifiable {
        let id = UUID()
        let reference: InstructionReference
        let title: String
        let sourceFilteredIndex: Int?
        var comment: String
    }

    // MARK: - State

    var isLoading: Bool = false
    var errorMessage: String?
    var fileURL: URL?
    var showFileImporter: Bool = false

    // Display toggles; structural rendering options rerun through the session controller.
    var showMarkup: Bool = true { didSet { rebuildFilteredLinesAndSearchMatches() } }
    var showPCode: Bool = true { didSet { rebuildFilteredLinesAndSearchMatches() } }
    var showStackState: Bool = false { didSet { runDisassembly() } }
    var showPseudoCode: Bool = true { didSet { rebuildFilteredLinesAndSearchMatches() } }
    var showVariables: Bool = true { didSet { rebuildFilteredLinesAndSearchMatches() } }
    var verbose: Bool = false

    /// The anchor ID of the procedure to scroll to (e.g. "2.3"). Set by sidebar selection.
    var selectedProcedure: String?
    var selectedProcedureFilteredIndex: Int?
    var procedureScrollRequest: Int = 0
    var outputRestoreFilteredIndex: Int?
    var outputRestoreScrollRequest: Int = 0

    var selectedOutputLineIDs: Set<Int> = []
    private var selectionAnchorIndex: Int?
    var locationEditDraft: LocationEditDraft?
    var procedureSignatureEditDraft: ProcedureSignatureEditDraft?
    var commentEditDraft: CommentEditDraft?

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
    var currentMatchScrollIndex: Int? {
        guard !searchMatchIndices.isEmpty else { return nil }
        return searchMatchIndices[min(currentMatchIndex, searchMatchIndices.count - 1)]
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

    func scrollToProcedure(_ procedureID: String) {
        selectedProcedure = procedureID
        selectedProcedureFilteredIndex = procedureFilteredIndices[procedureID]
        procedureScrollRequest += 1
    }

    func selectProcedure(_ procedureID: String?) {
        guard let procedureID else {
            selectedProcedure = nil
            selectedProcedureFilteredIndex = nil
            return
        }
        scrollToProcedure(procedureID)
    }

    var selectedOutputLineCount: Int {
        filteredLines.filter { selectedOutputLineIDs.contains($0.id) }.count
    }

    var procedureCount: Int {
        segments.reduce(0) { $0 + $1.procedures.count }
    }

    var statusText: String {
        guard fileURL != nil else { return "No file open" }
        if isLoading { return "Disassembling..." }
        if let errorMessage { return errorMessage }

        var parts: [String] = []
        parts.append("\(segments.count) segments")
        parts.append("\(procedureCount) procedures")
        parts.append("\(filteredLines.count) lines")
        if selectedOutputLineCount > 0 {
            parts.append("\(selectedOutputLineCount) selected")
        }
        if !searchMatchIndices.isEmpty {
            parts.append("\(searchMatchIndices.count) matches")
        }
        return parts.joined(separator: "   ")
    }

    var displaySummary: String {
        var enabled: [String] = []
        if showMarkup { enabled.append("Markup") }
        if showPCode { enabled.append("P-Code") }
        if showPseudoCode { enabled.append("Pseudocode") }
        if showVariables { enabled.append("Variables") }
        if showStackState { enabled.append("Stack") }
        if verbose { enabled.append("Verbose") }
        return enabled.isEmpty ? "No optional sections" : enabled.joined(separator: ", ")
    }

    var selectedOutputText: String {
        filteredLines
            .filter { selectedOutputLineIDs.contains($0.id) }
            .map(\.text)
            .joined(separator: "\n")
    }

    func selectOutputLine(lineID: Int, at index: Int, extending: Bool, toggling: Bool) {
        if extending {
            let anchor = selectionAnchorIndex ?? firstSelectedOutputLineIndex() ?? index
            selectOutputLineRange(from: anchor, to: index)
            return
        }

        if toggling {
            if selectedOutputLineIDs.contains(lineID) {
                selectedOutputLineIDs.remove(lineID)
            } else {
                selectedOutputLineIDs.insert(lineID)
            }
            selectionAnchorIndex = index
            return
        }

        selectedOutputLineIDs = [lineID]
        selectionAnchorIndex = index
    }

    func selectOutputLineRange(from anchor: Int, to index: Int) {
        guard filteredLines.indices.contains(anchor),
            filteredLines.indices.contains(index)
        else {
            return
        }

        let bounds = min(anchor, index)...max(anchor, index)
        selectedOutputLineIDs = Set(bounds.map { filteredLines[$0].id })
        selectionAnchorIndex = anchor
    }

    func selectOutputRows(_ rows: IndexSet) {
        let validRows = rows.filter { filteredLines.indices.contains($0) }
        selectedOutputLineIDs = Set(validRows.map { filteredLines[$0].id })
        selectionAnchorIndex = validRows.first
    }

    func clearOutputSelection() {
        selectedOutputLineIDs.removeAll()
        selectionAnchorIndex = nil
    }

    func copySelectedOutputLines() {
        let text = selectedOutputText
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func beginEditingOutputLine(on line: OutputLine, filteredIndex: Int? = nil, atCharacterOffset characterOffset: Int? = nil) {
        if let characterOffset, beginEditingProcedureSignature(on: line, atCharacterOffset: characterOffset) {
            return
        }
        if beginEditingComment(on: line, filteredIndex: filteredIndex) {
            return
        }
        beginEditingLocation(on: line, filteredIndex: filteredIndex)
    }

    @discardableResult
    func beginEditingComment(on line: OutputLine, filteredIndex: Int? = nil) -> Bool {
        guard let reference = line.commentReference else { return false }
        let existingComment = instruction(matching: reference)?.userComment ?? ""
        commentEditDraft = CommentEditDraft(
            reference: reference,
            title: "S\(reference.segment) P\(reference.procedure ?? -1) \(String(format: "$%04x", reference.addr))",
            sourceFilteredIndex: filteredIndex,
            comment: existingComment
        )
        return true
    }

    private func beginEditingLocation(on line: OutputLine, filteredIndex: Int?) {
        guard let location = editableLocation(for: line) else { return }
        locationEditDraft = LocationEditDraft(
            reference: LocationReference(location),
            originalDisplayName: location.displayName,
            sourceFilteredIndex: filteredIndex,
            name: location.name,
            type: location.displayType == "UNKNOWN" ? "" : location.displayType
        )
    }

    @discardableResult
    private func beginEditingProcedureSignature(on line: OutputLine, atCharacterOffset characterOffset: Int) -> Bool {
        guard let target = line.headerEditTargets.first(where: { $0.contains(characterOffset: characterOffset) }),
              let procedure = procedure(matching: target)
        else {
            return false
        }

        switch target.kind {
        case .procedureName:
            procedureSignatureEditDraft = ProcedureSignatureEditDraft(
                segment: target.segment,
                procedure: target.procedure,
                field: .procedureName,
                title: procedure.shortDescription,
                name: procedure.procName ?? procedure.shortDescription.split(separator: ".").last.map(String.init) ?? "",
                type: ""
            )
        case let .parameter(index):
            guard procedure.parameters.indices.contains(index) else { return false }
            let parameter = procedure.parameters[index]
            procedureSignatureEditDraft = ProcedureSignatureEditDraft(
                segment: target.segment,
                procedure: target.procedure,
                field: .parameter(index),
                title: "\(procedure.shortDescription) parameter \(index + 1)",
                name: parameter.name,
                type: parameter.type == "UNKNOWN" ? "" : parameter.type
            )
        case .returnType:
            guard procedure.isFunction else { return false }
            procedureSignatureEditDraft = ProcedureSignatureEditDraft(
                segment: target.segment,
                procedure: target.procedure,
                field: .returnType,
                title: "\(procedure.shortDescription) return type",
                name: "",
                type: (procedure.returnType ?? "UNKNOWN") == "UNKNOWN" ? "" : (procedure.returnType ?? "")
            )
        }
        return true
    }

    func saveLocationEdit() {
        guard let draft = locationEditDraft else { return }
        do {
            let invalidation = try upsertUserLabel(draft)
            locationEditDraft = nil
            applyMetadataInvalidation(invalidation, restoringFilteredIndex: draft.sourceFilteredIndex)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveProcedureSignatureEdit() {
        guard let draft = procedureSignatureEditDraft else { return }
        do {
            let invalidation = try upsertProcedureSignature(draft)
            procedureSignatureEditDraft = nil
            applyMetadataInvalidation(invalidation)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveCommentEdit() {
        guard let draft = commentEditDraft else { return }
        do {
            let invalidation = try upsertUserComment(draft)
            commentEditDraft = nil
            applyMetadataInvalidation(invalidation, restoringFilteredIndex: draft.sourceFilteredIndex)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func firstSelectedOutputLineIndex() -> Int? {
        filteredLines.firstIndex { selectedOutputLineIDs.contains($0.id) }
    }

    private func editableLocation(for line: OutputLine) -> Location? {
        if let reference = line.locationReference,
           let location = editableLocationsByReference[reference] {
            return location
        }

        for displayName in editableLocationDisplayNames {
            if containsWholeToken(displayName, in: line.text),
               let location = editableLocationsByDisplayName[displayName] {
                return location
            }
        }
        return nil
    }

    private func procedure(matching target: HeaderEditTarget) -> ProcedureIdentifier? {
        disassemblyResult?.allProcedures.first {
            $0.segment == target.segment && $0.procedure == target.procedure
        }
    }

    private func instruction(matching reference: InstructionReference) -> Instruction? {
        guard let codeSegment = disassemblyResult?.codeSegments[reference.segment] else {
            return nil
        }
        return codeSegment.procedures
            .first { $0.identifier?.procedure == reference.procedure }?
            .instructions[reference.addr]
    }

    private func location(matching reference: LocationReference, in locations: Set<Location>) -> Location? {
        locations.first {
            $0.segment == reference.segment &&
                $0.procedure == reference.procedure &&
                $0.lexLevel == reference.lexLevel &&
                $0.addr == reference.addr
        }
    }

    private func containsWholeToken(_ token: String, in text: String) -> Bool {
        guard !token.isEmpty else { return false }
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: token, options: [], range: searchRange) {
            let hasTokenPrefix: Bool
            if range.lowerBound == text.startIndex {
                hasTokenPrefix = false
            } else {
                hasTokenPrefix = isIdentifierCharacter(text[text.index(before: range.lowerBound)])
            }

            let hasTokenSuffix: Bool
            if range.upperBound == text.endIndex {
                hasTokenSuffix = false
            } else {
                hasTokenSuffix = isIdentifierCharacter(text[range.upperBound])
            }

            if !hasTokenPrefix && !hasTokenSuffix {
                return true
            }

            guard range.upperBound < text.endIndex else { return false }
            searchRange = text.index(after: range.lowerBound)..<text.endIndex
        }
        return false
    }

    private func isIdentifierCharacter(_ character: Character) -> Bool {
        character == "_" || character.isLetter || character.isNumber
    }

    private func upsertUserLabel(_ draft: LocationEditDraft) throws -> MetadataInvalidationScope {
        guard let fileURL else { throw LocationEditError.noOpenFile }
        let reference = draft.reference
        let type = draft.type.trimmingCharacters(in: .whitespacesAndNewlines)
        let location = Location(
            segment: reference.segment,
            procedure: reference.procedure,
            lexLevel: reference.lexLevel,
            addr: reference.addr,
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            type: type,
            typeSource: type.isEmpty ? .unknown : .user
        )
        let service = MetadataEditingService(repository: FileBackedMetadataRepository())
        let codeFileID = CodeFileID(fileURL: fileURL)
        return try service.apply(
            .upsertLabel(LocationID(codeFile: codeFileID, legacy: location), name: location.name, type: location.type),
            context: MetadataEditContext(codeFileID: codeFileID)
        ).invalidation
    }

    private func upsertProcedureSignature(_ draft: ProcedureSignatureEditDraft) throws -> MetadataInvalidationScope {
        guard let fileURL else { throw SignatureEditError.noOpenFile }
        guard let disassemblyResult else { throw SignatureEditError.noDisassembly }
        guard let procedure = disassemblyResult.allProcedures.first(where: {
            $0.segment == draft.segment && $0.procedure == draft.procedure
        }) else {
            throw SignatureEditError.procedureNotFound
        }

        let edited = ProcedureIdentifier(
            isFunction: procedure.isFunction,
            isAssembly: procedure.isAssembly,
            segment: procedure.segment,
            segmentName: procedure.segmentName,
            procedure: procedure.procedure,
            procName: procedure.procName,
            parameters: procedure.parameters,
            returnType: procedure.returnType,
            returnTypeSource: procedure.returnTypeSource
        )

        switch draft.field {
        case .procedureName:
            edited.procName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        case let .parameter(index):
            var parameters = edited.parameters
            guard parameters.indices.contains(index) else { throw SignatureEditError.parameterNotFound }
            parameters[index].name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let editedType = draft.type.trimmingCharacters(in: .whitespacesAndNewlines)
            let type = editedType == "POINTER" ? "" : editedType
            parameters[index].type = type
            parameters[index].typeSource = type.isEmpty ? .unknown : .user
            edited.parameters = parameters
        case .returnType:
            guard edited.isFunction else { throw SignatureEditError.notFunction }
            let type = draft.type.trimmingCharacters(in: .whitespacesAndNewlines)
            edited.returnType = type
            edited.returnTypeSource = type.isEmpty ? .unknown : .user
        }

        let service = MetadataEditingService(repository: FileBackedMetadataRepository())
        let codeFileID = CodeFileID(fileURL: fileURL)
        let procedureID = ProcedureID(codeFile: codeFileID, legacy: edited)
        let context = MetadataEditContext(
            codeFileID: codeFileID,
            systemMetadataVersion: metadataVersion(from: disassemblyResult),
            systemSegments: Self.systemSegments,
            procedures: disassemblyResult.allProcedures
        )
        switch draft.field {
        case .procedureName:
            return try service.apply(.renameProcedure(procedureID, name: edited.procName ?? ""), context: context).invalidation
        case let .parameter(index):
            return try service.apply(.upsertParameter(procedureID, index: index, name: edited.parameters[index].name, type: edited.parameters[index].type), context: context).invalidation
        case .returnType:
            return try service.apply(.upsertReturnType(procedureID, type: edited.returnType), context: context).invalidation
        }
    }

    private func upsertUserComment(_ draft: CommentEditDraft) throws -> MetadataInvalidationScope {
        guard let fileURL else { throw CommentEditError.noOpenFile }
        let comment = DisassemblyComment(
            reference: draft.reference,
            comment: draft.comment.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let service = MetadataEditingService(repository: FileBackedMetadataRepository())
        let codeFileID = CodeFileID(fileURL: fileURL)
        if let instructionID = InstructionID(codeFile: codeFileID, legacy: comment.reference) {
            return try service.apply(.upsertComment(instructionID, text: comment.comment), context: MetadataEditContext(codeFileID: codeFileID)).invalidation
        }
        return .none
    }


    private func applyMetadataInvalidation(_ invalidation: MetadataInvalidationScope, restoringFilteredIndex restoreIndex: Int? = nil) {
        isLoading = true
        let verb = verbose
        let stackState = showStackState
        sessionGeneration &+= 1
        let generation = sessionGeneration
        Task {
            do {
                if let model = try await sessionController.applyEdit(invalidation: invalidation, verbose: verb, showStackState: stackState) {
                    guard generation == self.sessionGeneration else { return }
                    applyPresentationModel(model, restoringFilteredIndex: restoreIndex)
                } else if generation == self.sessionGeneration {
                    isLoading = false
                }
            } catch {
                guard generation == self.sessionGeneration else { return }
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func metadataVersion(from disassemblyResult: DisassemblyResult) -> Int? {
        disassemblyResult.segDictionary.segTable[1]?.version
            ?? disassemblyResult.segDictionary.segTable[0]?.version
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
    private var disassemblyResult: DisassemblyResult?
    private var procedureFilteredIndices: [String: Int] = [:]
    private var editableLocationsByReference: [LocationReference: Location] = [:]
    private var editableLocationsByDisplayName: [String: Location] = [:]
    private var editableLocationDisplayNames: [String] = []
    private var searchMatchIndexSet: Set<Int> = []
    private var searchDebounceTask: Task<Void, Never>?
    private var searchRebuildTask: Task<Void, Never>?
    private var searchRevision: Int = 0
    private let sessionController = DocumentSessionController()
    private var sessionGeneration: Int = 0

    private static let searchDebounceDelayNanoseconds: UInt64 = 250_000_000
    private static let asyncSearchThreshold = 3000
    private static let asyncSearchChunkSize = 750
    private static let searchStatusWidthPresetKey = "searchStatusWidthPreset"
    private static let systemSegments: Set<Int> = [0, 2, 3, 4, 5, 6, 20, 21, 22, 28, 29, 30, 31]

    private enum LocationEditError: LocalizedError {
        case noOpenFile

        var errorDescription: String? {
            switch self {
            case .noOpenFile:
                return "No disassembly file is open."
            }
        }
    }

    private enum SignatureEditError: LocalizedError {
        case noOpenFile
        case noDisassembly
        case procedureNotFound
        case parameterNotFound
        case notFunction

        var errorDescription: String? {
            switch self {
            case .noOpenFile:
                return "No disassembly file is open."
            case .noDisassembly:
                return "No disassembly result is available."
            case .procedureNotFound:
                return "The selected procedure was not found."
            case .parameterNotFound:
                return "The selected parameter was not found."
            case .notFunction:
                return "Only functions have return types."
            }
        }
    }

    private enum CommentEditError: LocalizedError {
        case noOpenFile

        var errorDescription: String? {
            switch self {
            case .noOpenFile:
                return "No disassembly file is open."
            }
        }
    }

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
        rebuildFilteredLineIndexes()
        let visibleLineIDs = Set(filteredLines.map(\.id))
        selectedOutputLineIDs.formIntersection(visibleLineIDs)
        if let selectionAnchorIndex, !filteredLines.indices.contains(selectionAnchorIndex) {
            self.selectionAnchorIndex = nil
        }
        if let selectedProcedure {
            selectedProcedureFilteredIndex = procedureFilteredIndices[selectedProcedure]
        }
        rebuildSearchMatches(resetCurrentIndex: false)
    }

    private func rerenderStructuredLines() {
        guard let disassemblyResult else { return }
        allLines = renderStructuredLines(
            from: disassemblyResult,
            showStackState: showStackState,
            verbose: verbose
        )
        rebuildFilteredLinesAndSearchMatches()
    }

    private func rebuildFilteredLineIndexes() {
        procedureFilteredIndices = Dictionary(uniqueKeysWithValues: filteredLines.enumerated().compactMap { index, line in
            guard let anchor = line.anchor else { return nil }
            return (anchor, index)
        })
    }

    private func rebuildLocationIndexes(from result: DisassemblyResult) {
        let editableLocations = result.allLocations.filter { $0.addr != nil }
        let sortedEditableLocations = editableLocations.sorted {
            typeSourceRank($0.typeSource) > typeSourceRank($1.typeSource)
        }
        var byReference: [LocationReference: Location] = [:]
        for location in sortedEditableLocations {
            let reference = LocationReference(location)
            if byReference[reference] == nil {
                byReference[reference] = location
            }
        }
        editableLocationsByReference = byReference

        var byDisplayName: [String: Location] = [:]
        for location in sortedEditableLocations {
            if byDisplayName[location.displayName] == nil {
                byDisplayName[location.displayName] = location
            }
        }
        editableLocationsByDisplayName = byDisplayName
        editableLocationDisplayNames = byDisplayName.keys.sorted {
            if $0.count != $1.count {
                return $0.count > $1.count
            }
            return $0 < $1
        }
    }

    private func typeSourceRank(_ source: TypeSource) -> Int {
        switch source {
        case .unknown: return 0
        case .inferred: return 1
        case .procedureSignature: return 2
        case .metadata: return 3
        case .user: return 4
        }
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


    private func indexedSearchMatches(for query: String, visibleLineIDs: [Int: Int]) -> [Int]? {
        let nodeIDs = sessionController.indexedSearchNodeIDs(for: query)
        guard !nodeIDs.isEmpty, let document = sessionController.runResult?.document else { return nil }
        let matches = nodeIDs.compactMap { nodeID -> Int? in
            guard let lineID = document.nodesByID[nodeID]?.line.id else { return nil }
            return visibleLineIDs[lineID]
        }
        let uniqueMatches = Array(Set(matches)).sorted()
        return uniqueMatches.isEmpty ? nil : uniqueMatches
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

        let visibleLineIDs = Dictionary(uniqueKeysWithValues: filteredLines.enumerated().map { ($0.element.id, $0.offset) })
        if let matches = indexedSearchMatches(for: query, visibleLineIDs: visibleLineIDs) {
            applySearchMatches(matches, resetCurrentIndex: resetCurrentIndex)
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

    /// Metadata filenames relevant to the currently loaded file.
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
        sessionController.open(url: url)
        fileURL = url
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
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
        sessionController.open(url: url)
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

    func runDisassembly(restoringFilteredIndex restoreIndex: Int? = nil) {
        guard fileURL != nil else { return }
        searchDebounceTask?.cancel()
        searchRebuildTask?.cancel()
        isSearching = false
        liveSearchMatchCount = 0
        searchScannedLineCount = 0
        searchTotalLineCount = 0
        isLoading = true
        errorMessage = nil
        disassemblyResult = nil
        allLines = []
        filteredLines = []
        procedureFilteredIndices = [:]
        editableLocationsByReference = [:]
        editableLocationsByDisplayName = [:]
        editableLocationDisplayNames = []
        searchMatchIndices = []
        searchMatchIndexSet = []
        clearOutputSelection()
        currentMatchIndex = 0
        segments = []

        let verb = verbose
        let stackState = showStackState
        sessionGeneration &+= 1
        let generation = sessionGeneration

        Task {
            do {
                let model = try await sessionController.rerun(verbose: verb, showStackState: stackState)
                guard generation == self.sessionGeneration else { return }
                applyPresentationModel(model, restoringFilteredIndex: restoreIndex)
            } catch is CancellationError {
                guard generation == self.sessionGeneration else { return }
                self.isLoading = false
            } catch is DisassemblyCancelledError {
                guard generation == self.sessionGeneration else { return }
                self.isLoading = false
            } catch {
                guard generation == self.sessionGeneration else { return }
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    private func applyPresentationModel(_ model: DocumentSessionController.PresentationModel, restoringFilteredIndex restoreIndex: Int? = nil) {
        self.disassemblyResult = model.result
        self.allLines = model.lines
        self.rebuildLocationIndexes(from: model.result)
        self.rebuildFilteredLinesAndSearchMatches()
        self.segments = model.segments
        self.relevantMetadataFiles = model.relevantMetadataFiles
        self.isLoading = false
        if let restoreIndex, !self.filteredLines.isEmpty {
            let clampedRestoreIndex = min(max(restoreIndex, 0), self.filteredLines.count - 1)
            Task { @MainActor in
                await Task.yield()
                self.outputRestoreFilteredIndex = clampedRestoreIndex
                self.outputRestoreScrollRequest += 1
            }
        }
    }
}
