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

// MARK: - Structured Output Model

/// Classifies the kind of each output line so the GUI can filter and colour them.
public enum LineKind: Sendable, CaseIterable {
    case markup        // headings, code fences, segment table
    case pcode         // disassembled P-code instructions
    case pseudocode    // generated pseudocode
    case variable      // variable / location declarations
    case global        // global variable listings
    case header        // procedure/function header line, callers
}

/// A single line of disassembly output tagged with its kind.
public struct OutputLine: Identifiable, Sendable {
    public let id: Int           // sequential line number
    public let kind: LineKind
    public let text: String
    /// Optional anchor identifier (e.g. "2.3") used as a scroll target for procedure headers.
    public let anchor: String?

    public init(id: Int, kind: LineKind, text: String, anchor: String? = nil) {
        self.id = id
        self.kind = kind
        self.text = text
        self.anchor = anchor
    }
}

/// Produce an array of ``OutputLine`` from a ``DisassemblyResult``.
/// All line types are always generated; the GUI filters by toggling kinds on/off.
public func renderStructuredLines(
    from result: DisassemblyResult,
    verbose: Bool = false
) -> [OutputLine] {
    var lines: [OutputLine] = []
    var nextID = 0

    func addLine(_ kind: LineKind, _ text: String, anchor: String? = nil) {
        lines.append(OutputLine(id: nextID, kind: kind, text: text, anchor: anchor))
        nextID += 1
    }

    func prettyStack(_ s: [String]) -> String {
        "[" + s.joined(separator: ", ") + "]"
    }

    // File heading & segment table
    addLine(.markup, "#  \(result.sourceFilename) ")
    addLine(.markup, "")
    addLine(.markup, "\(result.segDictionary)")
    addLine(.markup, "## Globals")
    addLine(.markup, "")

    // Global variables
    result.allLocations.filter({ $0.lexLevel == -1 && $0.segment == 0 }).sorted()
        .forEach({ loc in
            addLine(.global, "G\(loc.addr ?? -1)=\(loc.description)")
        })
    addLine(.global, "")

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
                addLine(.header,
                    "### "
                        + (procDesc?.description ?? proc.identifier?.description
                            ?? "")
                        + " (* P=\(procNum), LL=\(proc.lexicalLevel), D=\(proc.dataSize) PAR=\(proc.parameterSize) *)",
                    anchor: anchor
                )

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
                    addLine(.variable, "L\(loc.addr ?? -1)=\(loc.description)")
                })

                addLine(.markup, "```")

                // Language-specific code fence
                if proc.identifier?.isAssembly == false {
                    addLine(.markup, "```pascal")
                    addLine(.pseudocode, "BEGIN")
                } else {
                    addLine(.markup, "```assembly")
                    addLine(.pcode, "; ASSEMBLER PROCEDURE")
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
                        addLine(.pseudocode, "\(indent)\(pseudo)")
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
                                pcLine += " \(n.name)"
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
                            pcLine += " " + prettyStack(inst.stackState ?? [])
                            addLine(.pcode, pcLine)
                            if paramStrings.count > 1 {
                                for i in 1..<paramStrings.count {
                                    addLine(.pcode,
                                        String(repeating: " ", count: 17)
                                            + paramStrings[i]
                                    )
                                }
                            }
                        } else {
                            pcLine += inst.mnemonic
                            if let comment = inst.comment {
                                pcLine += " ; \(comment)"
                            }
                            addLine(.pcode, pcLine)
                        }
                    }

                    // Post-pseudocode line
                    if let pseudo = inst.pseudoCode {
                        if pseudo.starts(with: "END")
                            || pseudo.starts(with: "UNTIL")
                        {
                            indentLevel -= 1
                        }
                        addLine(.pseudocode,
                            String(repeating: " ", count: indentLevel * 2)
                                + pseudo
                        )
                        if pseudo.hasSuffix("BEGIN")
                            || pseudo.starts(with: "REPEAT")
                            || pseudo.starts(with: "CASE")
                        {
                            indentLevel += 1
                        }
                    }
                }

                addLine(.pseudocode, "END")
                addLine(.markup, "```")
                addLine(.markup, "")
            }
        }
    }

    return lines
}
func outputResults(
    sourceFilename: String,
    segDictionary: SegDictionary,
    codeSegs: [Int: CodeSegment],
    allLocations: Set<Location>,
    allProcedures: [ProcedureIdentifier],
    allCallers: Set<Call>,
    verbose: Bool = false,
    showMarkup: Bool = true,
    showPCode: Bool = true,
    showPseudoCode: Bool = true,
    showDot: Bool = false
) {
    var stream = StdoutStream()
    outputResults(
        to: &stream,
        sourceFilename: sourceFilename,
        segDictionary: segDictionary,
        codeSegs: codeSegs,
        allLocations: allLocations,
        allProcedures: allProcedures,
        allCallers: allCallers,
        verbose: verbose,
        showMarkup: showMarkup,
        showPCode: showPCode,
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
    allLocations: Set<Location>,
    allProcedures: [ProcedureIdentifier],
    allCallers: Set<Call>,
    verbose: Bool = false,
    showMarkup: Bool = true,
    showPCode: Bool = true,
    showPseudoCode: Bool = true,
    showDot: Bool = false
) {
    func emit(_ items: Any..., terminator: String = "\n") {
        let line = items.map { "\($0)" }.joined(separator: " ")
        stream.write(line + terminator)
    }

    func prettyStack(_ s: [String]) -> String {
        "[" + s.joined(separator: ", ") + "]"
    }

    if showDot {
        emit("digraph {")
        allCallers.sorted(by: { $0.origin < $1.origin }).forEach {
            if $0.target.segment == $0.origin.segment
                && $0.target.lexLevel ?? -999 < $0.origin.lexLevel ?? -999
            {
                // ignore it
            } else {
                emit("\"\($0.origin)\" -> \"\($0.target)\"")
            }
        }
        emit("}")
    }
    if showMarkup {
        emit("#  \(sourceFilename) \n")
        emit(segDictionary)

        emit("## Globals\n")
    }

    allLocations.filter({ $0.lexLevel == -1 && $0.segment == 0 }).sorted()
        .forEach({ loc in
            emit("G\(loc.addr ?? -1)=\(loc.description)")
        })
    emit("")

    for (s, codeSeg) in codeSegs.sorted(by: { $0.key < $1.key }) {
        if verbose {
            segDictionary.segTable.first(where: { $0.value.segNum == s }).map {
                emit($0.value)
            }
        }
        if showMarkup {
            let segName =
                segDictionary.segTable.first(where: { $0.value.segNum == s })?
                .value.name ?? "Unknown"
            emit("## Segment \(segName) (\(s))\n")
        }

        if codeSeg.procedures.count > 0 {
            for proc in codeSeg.procedures {
                // emit proc/func header and procedure attributes
                let procDesc = allProcedures.first(where: {
                    $0.segment == s && $0.procedure == proc.identifier?.procedure
                })
                emit(
                    "### "
                        + (procDesc?.description ?? proc.identifier?.description
                            ?? "")
                        + " (* P=\(proc.identifier?.procedure ?? -99), LL=\(proc.lexicalLevel), D=\(proc.dataSize) PAR=\(proc.parameterSize) *)"
                )

                // emit callers
                var callerNames: [String] = []
                allCallers.filter(
                    {
                        $0.target.procedure == proc.identifier?.procedure
                            && $0.target.segment == s
                    }
                ).forEach(
                    { callerEntry in
                        if let callerName = allProcedures.first(where: {
                            $0.segment == callerEntry.origin.segment
                                && $0.procedure == callerEntry.origin.procedure
                        }) {
                            callerNames.append(callerName.shortDescription)
                        }
                    }
                )
                if !callerNames.isEmpty {
                    emit("Callers: \(callerNames.joined(separator: ", "))")
                }

                if showMarkup {
                    emit("```")
                }

                // emit variables declared in this procedure
                allLocations.filter({
                    $0.procedure == proc.identifier?.procedure && $0.segment == s
                        && $0.addr != nil
                }).sorted().forEach({ loc in
                    emit("L\(loc.addr ?? -1)=\(loc.description)")
                })

                if showMarkup {
                    emit("```")
                }

                // Variable listing is generated from `allLocations` and `allLabels`.
                if proc.identifier?.isAssembly == false {
                    if showMarkup {
                        emit("```pascal")
                    }
                    if showPseudoCode {
                        emit("BEGIN")
                    }
                } else {
                    if showMarkup {
                        emit("```assembly")
                    }
                    emit("; ASSEMBLER PROCEDURE")
                }

                var indentLevel: Int = 1

                for (address, inst) in proc.instructions.sorted(by: {
                    $0.key < $1.key
                }) {
                    if showPseudoCode {
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
                            emit("\(indent)\(pseudo)")
                            if pseudo.hasSuffix("BEGIN")
                                || pseudo.starts(with: "REPEAT")
                            {
                                indentLevel += 1
                            }
                        }
                    }

                    if showPCode || proc.identifier?.isAssembly == true {
                        if proc.entryPoints.contains(address) {
                            emit("->", terminator: " ")
                        } else {
                            emit("  ", terminator: " ")
                        }

                        emit(String(format: "%04x:", address), terminator: " ")
                        if inst.isPascal {
                            emit(
                                inst.mnemonic.padding(
                                    toLength: 8,
                                    withPad: " ",
                                    startingAt: 0
                                ),
                                terminator: ""
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

                            emit(
                                paramStrings[0].padding(
                                    toLength: 16,
                                    withPad: " ",
                                    startingAt: 0
                                ),
                                terminator: ""
                            )
                            if let c = inst.comment {
                                emit("; \(c)", terminator: "")
                            }
                            if let n = inst.memLocation {
                                emit(" \(n.name)", terminator: "")
                            }
                            if let d = inst.destination {
                                if let dest = allProcedures.first(where: {
                                    $0.segment == d.segment
                                        && $0.procedure == d.procedure
                                }) {
                                    emit(
                                        " \(dest.shortDescription)",
                                        terminator: ""
                                    )
                                } else {
                                    emit(" \(d.description)", terminator: "")
                                }
                            }
                            emit(" " + prettyStack(inst.stackState ?? []))
                            if paramStrings.count > 1 {
                                for i in 1..<paramStrings.count {
                                    emit(
                                        String(repeating: " ", count: 17)
                                            + paramStrings[i]
                                    )
                                }
                            }
                        } else {
                            emit(inst.mnemonic, terminator: "")
                            if inst.comment != nil {
                                emit(" ; \(inst.comment!)")
                            } else {
                                emit("")
                            }
                        }
                    }
                    if showPseudoCode {
                        if let pseudo = inst.pseudoCode {
                            if pseudo.starts(with: "END")
                                || pseudo.starts(with: "UNTIL")
                            {
                                indentLevel -= 1
                            }
                            emit(
                                String(repeating: " ", count: indentLevel * 2)
                                    + pseudo
                            )
                            if pseudo.hasSuffix("BEGIN")
                                || pseudo.starts(with: "REPEAT")
                                || pseudo.starts(with: "CASE")
                            {
                                indentLevel += 1
                            }
                        }
                    }
                }

                if showPseudoCode {
                    emit("END")
                }
                if showMarkup {
                    emit("```")
                    emit("")
                }
            }
        }
    }
}
