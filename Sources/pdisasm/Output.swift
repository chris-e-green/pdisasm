import Foundation

/// A simple wrapper around stdout that conforms to TextOutputStream.
struct StdoutStream: TextOutputStream {
    mutating func write(_ string: String) {
        Swift.print(string, terminator: "")
    }
}

/// A stream that accumulates output into a String.
public class StringStream: TextOutputStream {
    public var text: String = ""
    public init() {}
    public func write(_ string: String) {
        text += string
    }
}

private func assemblerDestinationText(
    for instruction: Instruction,
    destination: Location,
    allProcedures: [ProcedureIdentifier]
) -> String {
    let procedureLabel: String
    if let procedure = destination.procedure,
        let dest = allProcedures.first(where: {
            $0.segment == destination.segment && $0.procedure == procedure
        })
    {
        procedureLabel = dest.shortDescription
    } else {
        procedureLabel = destination.displayName
    }

    let arrow = instruction.opcode == 0x4c ? " => " : " -> "

    if let addr = destination.addr {
        return "\(arrow)\(procedureLabel) @ $\(String(format: "%04x", addr))"
    }

    return "\(arrow)\(procedureLabel)"
}

private func sortedTypeConflicts(_ conflicts: [TypeConflict]) -> [TypeConflict] {
    Array(Set(conflicts)).sorted {
        if $0.segment != $1.segment {
            return $0.segment < $1.segment
        }
        if $0.procedure != $1.procedure {
            return ($0.procedure ?? -1) < ($1.procedure ?? -1)
        }
        if $0.lexLevel != $1.lexLevel {
            return ($0.lexLevel ?? -1) < ($1.lexLevel ?? -1)
        }
        if $0.addr != $1.addr {
            return ($0.addr ?? -1) < ($1.addr ?? -1)
        }
        if $0.existingType != $1.existingType {
            return $0.existingType < $1.existingType
        }
        return $0.proposedType < $1.proposedType
    }
}

private func typeConflictText(_ conflict: TypeConflict) -> String {
    var location = "S\(conflict.segment)"
    if let procedure = conflict.procedure {
        location += " P\(procedure)"
    }
    if let lexLevel = conflict.lexLevel {
        location += " L\(lexLevel)"
    }
    if let addr = conflict.addr {
        location += " A\(addr)"
    }

    var text =
        "TYPE CONFLICT \(location): kept \(conflict.existingType) (\(conflict.existingSource.rawValue)); rejected \(conflict.proposedType) (\(conflict.proposedSource.rawValue))"
    if !conflict.evidence.isEmpty {
        text += "; evidence: \(conflict.evidence)"
    }
    return text
}

private func typeConflictDiagnostics(_ conflicts: [TypeConflict]) -> [Diagnostic] {
    sortedTypeConflicts(conflicts).map {
        Diagnostic(severity: .warning, message: typeConflictText($0))
    }
}

private func accessedSystemGlobalAddresses(in codeSegments: [Int: CodeSegment]) -> Set<Int> {
    var addresses: Set<Int> = []
    for codeSegment in codeSegments.values {
        for proc in codeSegment.procedures {
            for instruction in proc.instructions.values {
                guard let location = instruction.memLocation,
                    location.segment == 0,
                    location.lexLevel == -1,
                    let addr = location.addr
                else {
                    continue
                }
                addresses.insert(addr)
            }
        }
    }
    return addresses
}

// MARK: - Structured Output Model

/// Classifies the kind of each output line so the GUI can filter and colour them.
public enum LineKind: Sendable, CaseIterable {
    case markup        // headings, code fences, segment table
    case pcode         // disassembled P-code / assembly instructions
    case pseudocode    // generated pseudocode
    case variable      // variable / location declarations
    case global        // global variable listings
    case header        // procedure/function header line, callers
    case diagnostic    // warnings and diagnostics from analysis
}

/// A single line of disassembly output tagged with its kind.
public struct LocationReference: Hashable, Sendable, Codable {
    public let segment: Int
    public let procedure: Int?
    public let lexLevel: Int?
    public let addr: Int?

    public init(segment: Int, procedure: Int?, lexLevel: Int?, addr: Int?) {
        self.segment = segment
        self.procedure = procedure
        self.lexLevel = lexLevel
        self.addr = addr
    }

    public init(_ location: Location) {
        self.segment = location.segment
        self.procedure = location.procedure
        self.lexLevel = location.lexLevel
        self.addr = location.addr
    }
}

public enum HeaderEditTargetKind: Hashable, Sendable {
    case procedureName
    case parameter(Int)
    case returnType
}

public struct HeaderEditTarget: Hashable, Sendable {
    public let kind: HeaderEditTargetKind
    public let segment: Int
    public let procedure: Int
    public let range: Range<Int>

    public init(
        kind: HeaderEditTargetKind,
        segment: Int,
        procedure: Int,
        range: Range<Int>
    ) {
        self.kind = kind
        self.segment = segment
        self.procedure = procedure
        self.range = range
    }

    public func contains(characterOffset: Int) -> Bool {
        range.contains(characterOffset)
    }
}

public struct OutputLine: Identifiable, Sendable {
    public let id: Int           // sequential line number
    public let kind: LineKind
    public let text: String
    /// Optional anchor identifier (e.g. "2.3") used as a scroll target for procedure headers.
    public let anchor: String?
    public let locationReference: LocationReference?
    public let commentReference: InstructionReference?
    public let headerEditTargets: [HeaderEditTarget]

    public init(
        id: Int,
        kind: LineKind,
        text: String,
        anchor: String? = nil,
        locationReference: LocationReference? = nil,
        commentReference: InstructionReference? = nil,
        headerEditTargets: [HeaderEditTarget] = []
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.anchor = anchor
        self.locationReference = locationReference
        self.commentReference = commentReference
        self.headerEditTargets = headerEditTargets
    }
}

private func assemblerCommentText(for instruction: Instruction) -> String? {
    let comments = [instruction.comment, instruction.userComment]
        .compactMap { comment -> String? in
            let trimmed = comment?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }
    guard !comments.isEmpty else { return nil }
    return comments.joined(separator: "; ")
}

private func defaultProcedureName(for procedure: ProcedureIdentifier) -> String {
    if let procName = procedure.procName, !procName.isEmpty {
        return procName
    }
    if procedure.procedure == 1, let segmentName = procedure.segmentName, !segmentName.isEmpty {
        return segmentName
    }
    return (procedure.isFunction ? "FUNC" : "PROC") + String(procedure.procedure)
}

private func signatureParameterDescriptions(for procedure: ProcedureIdentifier) -> [String] {
    if procedure.parameterLocations.count == procedure.parameters.count {
        return procedure.parameterLocations.map(\.description)
    }
    return procedure.parameters.map(\.description)
}

private func procedureHeaderTextAndTargets(
    for procedure: ProcedureIdentifier,
    dataSize: Int,
    parameterSize: Int,
    lexicalLevel: Int
) -> (text: String, targets: [HeaderEditTarget]) {
    var text = procedure.isFunction ? "FUNCTION " : "PROCEDURE "
    text += (procedure.segmentName ?? "SEG" + String(procedure.segment)) + "."

    var targets: [HeaderEditTarget] = []
    let procedureNameStart = text.count
    let procedureName = defaultProcedureName(for: procedure)
    text += procedureName
    targets.append(HeaderEditTarget(
        kind: .procedureName,
        segment: procedure.segment,
        procedure: procedure.procedure,
        range: procedureNameStart..<text.count
    ))

    let parameters = signatureParameterDescriptions(for: procedure)
    if !parameters.isEmpty {
        text += "("
        for (index, parameter) in parameters.enumerated() {
            if index > 0 {
                text += "; "
            }
            let start = text.count
            text += parameter
            targets.append(HeaderEditTarget(
                kind: .parameter(index),
                segment: procedure.segment,
                procedure: procedure.procedure,
                range: start..<text.count
            ))
        }
        text += ")"
    }

    if procedure.isFunction {
        text += ": "
        let start = text.count
        text += procedure.returnType ?? "UNKNOWN"
        targets.append(HeaderEditTarget(
            kind: .returnType,
            segment: procedure.segment,
            procedure: procedure.procedure,
            range: start..<text.count
        ))
    }

    text += " (* S=\(procedure.segment), P=\(procedure.procedure), LL=\(lexicalLevel), D=\(dataSize) PAR=\(parameterSize) *)"
    return (text, targets)
}

private func renderKnownTypeDefinitionLines(
    records: Set<PascalRecord>,
    aliases: [String: String],
    scalarTypes: [String: PascalScalarType],
    constants: [String: Int],
    subrangeTypes: [String: PascalSubrangeType]
) -> [String] {
    guard !records.isEmpty || !aliases.isEmpty || !scalarTypes.isEmpty || !constants.isEmpty || !subrangeTypes.isEmpty else {
        return []
    }

    var lines: [String] = ["## Known Types", ""]

    if !constants.isEmpty {
        lines.append("CONST")
        for constant in constants.keys.sorted() {
            if let value = constants[constant] {
                lines.append("  \(constant) = \(value);")
            }
        }
        lines.append("")
    }

    lines.append("TYPE")

    for scalarName in scalarTypes.keys.sorted() {
        if let scalarType = scalarTypes[scalarName] {
            lines.append("  \(scalarName) = (\(scalarType.cases.joined(separator: ", ")));")
        }
    }

    for subrangeName in subrangeTypes.keys.sorted() {
        if let subrangeType = subrangeTypes[subrangeName] {
            lines.append("  \(subrangeName) = \(subrangeType.renderedType);")
        }
    }

    for alias in aliases.keys.sorted() {
        if subrangeTypes[alias] == nil, let type = aliases[alias] {
            lines.append("  \(alias) = \(type);")
        }
    }

    for record in records.sorted(by: { $0.name < $1.name }) {
        lines.append("  \(record.name) = RECORD")
        let renderedMembers = record.allMembers.isEmpty
            ? record.members.keys.sorted().compactMap { offset in
                record.members[offset].map {
                    PascalRecordMember(offset: offset, identifier: $0)
                }
            }
            : record.allMembers.sorted {
                if $0.offset != $1.offset {
                    return $0.offset < $1.offset
                }
                return $0.identifier.name < $1.identifier.name
            }
        for member in renderedMembers {
            let identifier = member.identifier
            let type = identifier.type.isEmpty ? "UNKNOWN" : identifier.type
            let variant = member.variantLabel.map { " variant \($0)," } ?? ""
            lines.append("    \(identifier.name): \(type); (*\(variant) offset \(member.offset) *)")
        }
        lines.append("  END;")
    }

    lines.append("")
    return lines
}

private func unknownKnownTypeDiagnostics(
    records: Set<PascalRecord>,
    aliases: [String: String],
    scalarTypes: [String: PascalScalarType],
    subrangeTypes: [String: PascalSubrangeType]
) -> [Diagnostic] {
    let builtinTypes: Set<String> = [
        "BOOLEAN", "BYTE", "CHAR", "INTEGER", "POINTER", "REAL", "STRING"
    ]
    let recordNames = Set(records.map(\.name))
    let scalarNames = Set(scalarTypes.keys)
    let subrangeNames = Set(subrangeTypes.keys)

    func finalType(_ type: String) -> String {
        var current = type.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        var seen: Set<String> = []
        while let resolved = aliases[current], !seen.contains(current) {
            seen.insert(current)
            current = resolved.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }
        return current
    }

    func unresolvedFinalType(_ type: String) -> String? {
        let resolved = finalType(type)
        if resolved.isEmpty || resolved == "UNKNOWN" {
            return resolved.isEmpty ? "UNKNOWN" : resolved
        }
        if resolved.hasPrefix("^") {
            let pointee = String(resolved.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            return unresolvedFinalType(pointee)
        }
        if resolved.hasPrefix("ARRAY OF ") {
            let elementType = String(resolved.dropFirst("ARRAY OF ".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return unresolvedFinalType(elementType)
        }
        if resolved.range(of: #"^[+-]?[0-9]+\.\.[+-]?[0-9]+$"#, options: .regularExpression) != nil {
            return nil
        }
        if builtinTypes.contains(resolved)
            || recordNames.contains(resolved)
            || scalarNames.contains(resolved)
            || subrangeNames.contains(resolved)
        {
            return nil
        }
        return resolved
    }

    var diagnostics: [Diagnostic] = []
    for alias in aliases.keys.sorted() {
        guard let type = aliases[alias],
              let unknownType = unresolvedFinalType(type)
        else { continue }
        diagnostics.append(Diagnostic(
            severity: .warning,
            message: "TYPE \(alias) resolves to unknown final type \(unknownType)"
        ))
    }

    for record in records.sorted(by: { $0.name < $1.name }) {
        let diagnosticMembers = record.allMembers.isEmpty
            ? record.members.keys.sorted().compactMap { offset in
                record.members[offset].map {
                    PascalRecordMember(offset: offset, identifier: $0)
                }
            }
            : record.allMembers
        for member in diagnosticMembers.sorted(by: { $0.offset < $1.offset }) {
            guard let unknownType = unresolvedFinalType(member.identifier.type)
            else { continue }
            diagnostics.append(Diagnostic(
                severity: .warning,
                message: "RECORD \(record.name).\(member.identifier.name) at offset \(member.offset) resolves to unknown final type \(unknownType)"
            ))
        }
    }
    return diagnostics
}

/// Produce an array of ``OutputLine`` from a ``DisassemblyResult``.
/// All line types are always generated; the GUI filters by toggling kinds on/off.
public func renderStructuredLines(
    from result: DisassemblyResult,
    showStackState: Bool = false,
    verbose: Bool = false
) -> [OutputLine] {
    var lines: [OutputLine] = []
    var nextID = 0

    func addLine(
        _ kind: LineKind,
        _ text: String,
        anchor: String? = nil,
        location: Location? = nil,
        commentReference: InstructionReference? = nil,
        headerEditTargets: [HeaderEditTarget] = []
    ) {
        if text.contains("\n") {
            let parts = text.split(separator: "\n", omittingEmptySubsequences: false)
            for (index, part) in parts.enumerated() {
                addLine(
                    kind,
                    String(part),
                    anchor: index == 0 ? anchor : nil,
                    location: index == 0 ? location : nil,
                    commentReference: index == 0 ? commentReference : nil,
                    headerEditTargets: index == 0 ? headerEditTargets : []
                )
            }
            return
        }

        lines.append(OutputLine(
            id: nextID,
            kind: kind,
            text: text,
            anchor: anchor,
            locationReference: location.map(LocationReference.init),
            commentReference: commentReference,
            headerEditTargets: headerEditTargets
        ))
        nextID += 1
    }

    func prettyStack(_ s: [String]) -> String {
        "[" + s.joined(separator: ", ") + "]"
    }

    // File heading & segment table
    addLine(.markup, "#  \(result.sourceFilename) ")
    addLine(.markup, "")
    addLine(.markup, "\(result.segDictionary)")

    let diagnostics = typeConflictDiagnostics(result.typeConflicts)
        + result.diagnostics
        + unknownKnownTypeDiagnostics(
            records: result.knownRecords,
            aliases: result.typeAliases,
            scalarTypes: result.scalarTypes,
            subrangeTypes: result.subrangeTypes
        )
    if !diagnostics.isEmpty {
        addLine(.markup, "## Diagnostics")
        for diagnostic in diagnostics {
            addLine(.diagnostic, "\(diagnostic.severity.rawValue.uppercased()): \(diagnostic.message)")
        }
        addLine(.diagnostic, "")
    }

    for line in renderKnownTypeDefinitionLines(
        records: result.knownRecords,
        aliases: result.typeAliases,
        scalarTypes: result.scalarTypes,
        constants: result.constants,
        subrangeTypes: result.subrangeTypes
    ) {
        addLine(line.hasPrefix("##") ? .markup : .variable, line)
    }

    addLine(.markup, "## Globals")
    addLine(.markup, "")

    // Global variables
    let accessedGlobalAddresses = accessedSystemGlobalAddresses(in: result.codeSegments)
    result.allLocations.filter({
        $0.lexLevel == -1
            && $0.segment == 0
            && $0.addr.map(accessedGlobalAddresses.contains) == true
    }).sorted()
        .forEach({ loc in
            addLine(.global, "G\(loc.addr ?? -1)=\(loc.description)", location: loc)
        })
    addLine(.global, "")
    
    for ds in result.dataSegments.sorted(by: { $0 < $1 }) {
        addLine(.variable, "## Data Segment \(ds)\n")
        result.allLocations.filter({ $0.segment == ds }).sorted().forEach( { loc in
            addLine(.variable, "D\(loc.addr ?? -1)=\(loc.description)", location: loc)
        })
    }
    addLine(.variable, "")

    for (s, codeSeg) in result.codeSegments.sorted(by: { $0.key < $1.key }) {
        if verbose {
            result.segDictionary.segTable.first(where: { $0.value.segNum == s }).map {
                addLine(.markup, "\($0.value)")
            }
        }

        let segName =
            result.segDictionary.segTable.first(where: { $0.value.segNum == s })?
            .value.name ?? "Unknown"
        addLine(.markup, "## Segment \(segName) (\(s))")
        addLine(.markup, "")

        if codeSeg.procedures.count > 0 {
            for proc in codeSeg.procedures {
                let procDesc = result.allProcedures.first(where: {
                    $0.segment == s && $0.procedure == proc.identifier?.procedure
                })
                let procNum = proc.identifier?.procedure ?? -99
                let anchor = "\(s).\(procNum)"
                let headerProcedure = procDesc ?? proc.identifier
                if let headerProcedure {
                    let header = procedureHeaderTextAndTargets(
                        for: headerProcedure,
                        dataSize: proc.dataSize,
                        parameterSize: proc.parameterSize,
                        lexicalLevel: proc.lexicalLevel
                    )
                    addLine(.header, header.text, anchor: anchor, headerEditTargets: header.targets)
                } else {
                    addLine(
                        .header,
                        " (* S=\(s), P=\(procNum), LL=\(proc.lexicalLevel), D=\(proc.dataSize) PAR=\(proc.parameterSize) *)",
                        anchor: anchor
                    )
                }

                // Callers
                var callerNames: [String] = []
                result.allCallers.filter(
                    {
                        $0.target.procedure == proc.identifier?.procedure
                            && $0.target.segment == s
                    }
                ).forEach(
                    { callerEntry in
                        if let callerName = result.allProcedures.first(where: {
                            $0.segment == callerEntry.origin.segment
                                && $0.procedure == callerEntry.origin.procedure
                        }) {
                            callerNames.append(callerName.shortDescription)
                        }
                    }
                )
                if !callerNames.isEmpty {
                    addLine(.header, "Callers: \(callerNames.joined(separator: ", "))")
                }

                addLine(.markup, "```")

                // Variables declared in this procedure
                result.allLocations.filter({
                    $0.procedure == proc.identifier?.procedure && $0.segment == s
                        && $0.addr != nil
                }).sorted().forEach({ loc in
                    addLine(.variable, "L\(loc.addr ?? -1)=\(loc.description)", location: loc)
                })

                addLine(.markup, "```")

                // Language-specific code fence
                if proc.identifier?.isAssembly == false {
                    addLine(.markup, "```pascal")
                    addLine(.pseudocode, "BEGIN")
                } else {
                    addLine(.markup, "```assembly")
                    addLine(.pseudocode, "; ASSEMBLER PROCEDURE")
                    addLine(.pseudocode, ".\(proc.identifier?.isFunction == true ? "FUNC" : "PROC") \(proc.identifier?.procName ?? "P\(proc.identifier?.procedure ?? -99)")")
                }

                var indentLevel: Int = 1

                for (address, inst) in proc.instructions.sorted(by: {
                    $0.key < $1.key
                }) {
                    // Pre-pseudocode lines
                    for pseudo in inst.prePseudoCode.reversed() {
                        if pseudo.starts(with: "END")
                            || pseudo.starts(with: "UNTIL")
                        {
                            indentLevel -= 1
                        }
                        let indent = String(
                            repeating: " ",
                            count: indentLevel * 2
                        )
                        addLine(.pseudocode, "\(indent)\(pseudo)", location: inst.memLocation)
                        if pseudo.hasSuffix("BEGIN")
                            || pseudo.starts(with: "REPEAT")
                        {
                            indentLevel += 1
                        }
                    }

                    // P-code / assembly line
                    if true /* always generate */ {
                        var pcLine = ""
                        if proc.entryPoints.contains(address) {
                            pcLine += "-> "
                        } else {
                            pcLine += "   "
                        }

                        pcLine += String(format: "%04x: ", address)
                        if inst.isPascal {
                            pcLine += inst.mnemonic.padding(
                                toLength: 8,
                                withPad: " ",
                                startingAt: 0
                            )
                            var paramStrings: [String] = [""]
                            var paramStrIndex = 0
                            for p in inst.params {
                                if p > 0xff {
                                    if paramStrings[paramStrIndex].count > 12 {
                                        paramStrings.append("")
                                        paramStrIndex += 1
                                    }
                                    paramStrings[paramStrIndex] += String(
                                        format: "%04x ",
                                        p
                                    )
                                } else {
                                    if paramStrings[paramStrIndex].count > 14 {
                                        paramStrings.append("")
                                        paramStrIndex += 1
                                    }
                                    paramStrings[paramStrIndex] += String(
                                        format: "%02x ",
                                        p
                                    )
                                }
                            }

                            pcLine += paramStrings[0].padding(
                                toLength: 16,
                                withPad: " ",
                                startingAt: 0
                            )
                            if let c = inst.comment {
                                pcLine += "; \(c)"
                            }
                            if let n = inst.memLocation {
                                pcLine += " \(n.displayName)"
                            }
                            if let d = inst.destination {
                                if let dest = result.allProcedures.first(where: {
                                    $0.segment == d.segment
                                        && $0.procedure == d.procedure
                                }) {
                                    pcLine += " \(dest.shortDescription)"
                                } else {
                                    pcLine += " \(d.description)"
                                }
                            }
                            if showStackState {
                                pcLine += " " + prettyStack(inst.stackState ?? [])
                            }
                            addLine(.pcode, pcLine, location: inst.memLocation)
                            if paramStrings.count > 1 {
                                for i in 1..<paramStrings.count {
                                    addLine(.pcode,
                                        String(repeating: " ", count: 17)
                                            + paramStrings[i]
                                    )
                                }
                            }
                        } else { // not pascal
                            pcLine += inst.mnemonic
                            if let comment = assemblerCommentText(for: inst) {
                                pcLine += " ; \(comment)"
                            }
                            if let destination = inst.destination {
                                pcLine += assemblerDestinationText(
                                    for: inst,
                                    destination: destination,
                                    allProcedures: result.allProcedures
                                )
                            }
                            addLine(
                                .pcode,
                                pcLine,
                                commentReference: InstructionReference(
                                    segment: s,
                                    procedure: proc.identifier?.procedure,
                                    addr: address
                                )
                            )
                        }
                    }

                    // Post-pseudocode line
                    if let pseudo = inst.pseudoCodeStatement?.renderedText ?? inst.pseudoCode {
                        if pseudo.starts(with: "END")
                            || pseudo.starts(with: "UNTIL")
                        {
                            indentLevel -= 1
                        }
                            addLine(.pseudocode,
                                String(repeating: " ", count: indentLevel * 2)
                                    + pseudo,
                                location: inst.memLocation
                            )
                        if pseudo.hasSuffix("BEGIN")
                            || pseudo.starts(with: "REPEAT")
                            || pseudo.starts(with: "CASE")
                        {
                            indentLevel += 1
                        }
                    }
                }
                if proc.identifier?.isAssembly == false {
                    addLine(.pseudocode, "END")
                } else {
                    addLine(.pseudocode, ".END")
                }
                addLine(.markup, "```")
                addLine(.markup, "")
            }
        }
    }

    return lines
}

private func makeDisassemblyResult(
    sourceFilename: String,
    segDictionary: SegDictionary,
    codeSegs: [Int: CodeSegment],
    dataSegs: [Int],
    allLocations: Set<Location>,
    allProcedures: [ProcedureIdentifier],
    allCallers: Set<Call>,
    knownRecords: Set<PascalRecord> = [],
    typeAliases: [String: String] = [:],
    scalarTypes: [String: PascalScalarType] = [:],
    constants: [String: Int] = [:],
    subrangeTypes: [String: PascalSubrangeType] = [:],
    typeConflicts: [TypeConflict],
    diagnostics: [Diagnostic] = []
) -> DisassemblyResult {
    DisassemblyResult(
        sourceFilename: sourceFilename,
        segDictionary: segDictionary,
        codeSegments: codeSegs,
        dataSegments: dataSegs,
        allLocations: allLocations,
        allProcedures: allProcedures,
        allCallers: allCallers,
        knownRecords: knownRecords,
        typeAliases: typeAliases,
        scalarTypes: scalarTypes,
        constants: constants,
        subrangeTypes: subrangeTypes,
        typeConflicts: typeConflicts,
        diagnostics: diagnostics
    )
}

private func shouldEmitLine(
    _ line: OutputLine,
    showMarkup: Bool,
    showPCode: Bool,
    showPseudoCode: Bool
) -> Bool {
    switch line.kind {
    case .markup:     return showMarkup
    case .pcode:      return showPCode
    case .pseudocode: return showPseudoCode
    case .variable:   return true
    case .global:     return true
    case .header:     return true
    case .diagnostic: return true
    }
}

private func renderDotLines(allCallers: Set<Call>) -> [String] {
    var lines = ["digraph {"]
    allCallers.sorted(by: { $0.origin < $1.origin }).forEach {
        if $0.target.segment == $0.origin.segment
            && $0.target.lexLevel ?? -999 < $0.origin.lexLevel ?? -999
        {
            return
        }
        lines.append("\"\($0.origin)\" -> \"\($0.target)\"")
    }
    lines.append("}")
    return lines
}

private func writeLines<Target: TextOutputStream>(
    _ lines: [String],
    to stream: inout Target
) {
    for line in lines {
        stream.write(line)
        stream.write("\n")
    }
}

func outputResults(
    sourceFilename: String,
    segDictionary: SegDictionary,
    codeSegs: [Int: CodeSegment],
    dataSegs: [Int],
    allLocations: Set<Location>,
    allProcedures: [ProcedureIdentifier],
    allCallers: Set<Call>,
    knownRecords: Set<PascalRecord> = [],
    typeAliases: [String: String] = [:],
    scalarTypes: [String: PascalScalarType] = [:],
    constants: [String: Int] = [:],
    subrangeTypes: [String: PascalSubrangeType] = [:],
    typeConflicts: [TypeConflict] = [],
    diagnostics: [Diagnostic] = [],
    verbose: Bool = false,
    showMarkup: Bool = true,
    showPCode: Bool = true,
    showStackState: Bool = false,
    showPseudoCode: Bool = true,
    showDot: Bool = false
) {
    var stream = StdoutStream()
    outputResults(
        to: &stream,
        sourceFilename: sourceFilename,
        segDictionary: segDictionary,
        codeSegs: codeSegs,
        dataSegs: dataSegs,
        allLocations: allLocations,
        allProcedures: allProcedures,
        allCallers: allCallers,
        knownRecords: knownRecords,
        typeAliases: typeAliases,
        scalarTypes: scalarTypes,
        constants: constants,
        subrangeTypes: subrangeTypes,
        typeConflicts: typeConflicts,
        diagnostics: diagnostics,
        verbose: verbose,
        showMarkup: showMarkup,
        showPCode: showPCode,
        showStackState: showStackState,
        showPseudoCode: showPseudoCode,
        showDot: showDot
    )
}

/// Core output rendering that writes to any TextOutputStream.
func outputResults<Target: TextOutputStream>(
    to stream: inout Target,
    sourceFilename: String,
    segDictionary: SegDictionary,
    codeSegs: [Int: CodeSegment],
    dataSegs: [Int],
    allLocations: Set<Location>,
    allProcedures: [ProcedureIdentifier],
    allCallers: Set<Call>,
    knownRecords: Set<PascalRecord> = [],
    typeAliases: [String: String] = [:],
    scalarTypes: [String: PascalScalarType] = [:],
    constants: [String: Int] = [:],
    subrangeTypes: [String: PascalSubrangeType] = [:],
    typeConflicts: [TypeConflict] = [],
    diagnostics: [Diagnostic] = [],
    verbose: Bool = false,
    showMarkup: Bool = true,
    showPCode: Bool = true,
    showStackState: Bool = false,
    showPseudoCode: Bool = true,
    showDot: Bool = false
) {
    if showDot {
        writeLines(renderDotLines(allCallers: allCallers), to: &stream)
    }

    let result = makeDisassemblyResult(
        sourceFilename: sourceFilename,
        segDictionary: segDictionary,
        codeSegs: codeSegs,
        dataSegs: dataSegs,
        allLocations: allLocations,
        allProcedures: allProcedures,
        allCallers: allCallers,
        knownRecords: knownRecords,
        typeAliases: typeAliases,
        scalarTypes: scalarTypes,
        constants: constants,
        subrangeTypes: subrangeTypes,
        typeConflicts: typeConflicts,
        diagnostics: diagnostics
    )

    let lines = renderStructuredLines(
        from: result,
        showStackState: showStackState,
        verbose: verbose
    )
    let filteredLines = lines
        .filter {
            shouldEmitLine(
                $0,
                showMarkup: showMarkup,
                showPCode: showPCode,
                showPseudoCode: showPseudoCode
            )
        }
        .map(\.text)
    writeLines(filteredLines, to: &stream)
}
