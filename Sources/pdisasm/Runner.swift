import Foundation

func registerProcedureIdentifier(
    _ proc: Procedure,
    in allProcedures: inout [ProcedureIdentifier]
) {
    guard let identifier = proc.identifier else { return }
    if !allProcedures.contains(where: {
        $0.segment == identifier.segment && $0.procedure == identifier.procedure
    }) {
        allProcedures.append(identifier)
    }
}

// MARK: - Memory Location Resolution

/// Resolve any memory locations where the procedure number has not been determined and update.
/// If the memory location is in the same segment as the code using it, finding the relevant procedure
/// will depend on the lex level. If the lex level is the same as the current procedure, it'll be a local variable.
/// If the lex level is -1, it'll be a system global in segment 0, procedure 1. If it's lex level 0, it'll be a
/// program global (i.e. in the main procedure of segment 1). Otherwise, it'll be somewhere up the call
/// chain, so we'll have to follow it up until we find a matching lex level.
func normaliseMemoryLocations(
    _ proc: Procedure,
    _ allCallers: Set<Call>
) {
    let missingDetail = proc.instructions.filter {
        $0.value.memLocation != nil && $0.value.memLocation?.procedure == nil
    }
    if !missingDetail.isEmpty {
        missingDetail.forEach { (_, inst) in

            if let loc = inst.memLocation, let lexLevel = loc.lexLevel {
                switch lexLevel {
                case -1:
                    inst.memLocation?.segment = 0
                    inst.memLocation?.procedure = 1
                case 0:
                    if loc.segment == proc.identifier?.segment,
                       let p = allCallers.first(where: {
                           $0.origin.lexLevel == 0
                       }) {
                        inst.memLocation?.procedure = p.origin.procedure
                        inst.memLocation?.segment = p.origin.segment
                    }
                case proc.lexicalLevel:
                    inst.memLocation?.procedure = proc.identifier?.procedure
                default:
                    var parents = allCallers.filter {
                        $0.target.segment == proc.identifier?.segment
                            && $0.target.procedure
                                == proc.identifier?.procedure
                    }.map(\.origin)
                    var foundMatch = false
                    while !parents.isEmpty && !foundMatch {
                        for parent in parents {
                            if parent.lexLevel == lexLevel {
                                inst.memLocation?.procedure =
                                    parent.procedure
                                inst.memLocation?.segment = parent.segment
                                foundMatch = true
                                break
                            }
                            parents = allCallers.filter {
                                $0.target.segment == parent.segment
                                    && $0.target.procedure
                                        == parent.procedure
                            }.map(\.origin)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Public Entry Point

/// Holds the structured results of a disassembly run.
public struct DisassemblyResult: @unchecked Sendable {
    public let sourceFilename: String
    public let segDictionary: SegDictionary
    public let codeSegments: [Int: CodeSegment]
    public let dataSegments: [Int]
    public let allLocations: Set<Location>
    public let allProcedures: [ProcedureIdentifier]
    public let allCallers: Set<Call>
    public let knownRecords: Set<PascalRecord>
    public let typeAliases: [String: String]
    public let scalarTypes: [String: PascalScalarType]
    public let constants: [String: Int]
    public let subrangeTypes: [String: PascalSubrangeType]
    public let typeConflicts: [TypeConflict]
    public let diagnostics: [Diagnostic]
    public let runReport: RunReport

    public init(
        sourceFilename: String,
        segDictionary: SegDictionary,
        codeSegments: [Int: CodeSegment],
        dataSegments: [Int],
        allLocations: Set<Location>,
        allProcedures: [ProcedureIdentifier],
        allCallers: Set<Call>,
        knownRecords: Set<PascalRecord>,
        typeAliases: [String: String],
        scalarTypes: [String: PascalScalarType],
        constants: [String: Int],
        subrangeTypes: [String: PascalSubrangeType],
        typeConflicts: [TypeConflict],
        diagnostics: [Diagnostic],
        runReport: RunReport = RunReport()
    ) {
        self.sourceFilename = sourceFilename
        self.segDictionary = segDictionary
        self.codeSegments = codeSegments
        self.dataSegments = dataSegments
        self.allLocations = allLocations
        self.allProcedures = allProcedures
        self.allCallers = allCallers
        self.knownRecords = knownRecords
        self.typeAliases = typeAliases
        self.scalarTypes = scalarTypes
        self.constants = constants
        self.subrangeTypes = subrangeTypes
        self.typeConflicts = typeConflicts
        self.diagnostics = diagnostics
        self.runReport = runReport
    }
}

private func defaultKnownRecords() -> Set<PascalRecord> {
    [
        PascalRecord(name: "FIB", members: [
            0: Identifier(name:"FWINDOW", type: "WINDOWP"),
            1: Identifier(name:"FEOLN", type: "BOOLEAN"),
            2: Identifier(name:"FEOF", type: "BOOLEAN"),
            3: Identifier(name:"FSTATE", type: "INTEGER"),
            4: Identifier(name:"FRECSIZE", type: "INTEGER"),
            5: Identifier(name:"FISOPEN", type: "BOOLEAN"),
            6: Identifier(name:"FISBLKD", type: "BOOLEAN"),
            7: Identifier(name:"FUNIT", type: "INTEGER"),
            8: Identifier(name:"FVID", type: "ARRAY OF CHAR"),
            12: Identifier(name:"FMAXBLK", type: "INTEGER"),
            13: Identifier(name:"FNXTBLK", type: "INTEGER"),
            14: Identifier(name:"FREPTCNT", type: "INTEGER"),
            15: Identifier(name:"FMODIFIED", type: "BOOLEAN"),
            16: Identifier(name:"DFIRSTBLK", type: "INTEGER"),
            17: Identifier(name:"DLASTBLK", type: "INTEGER"),
            18: Identifier(name:"DFKIND", type: "INTEGER"),
            19: Identifier(name:"DTID", type: "ARRAY OF CHAR"),
            27: Identifier(name:"DLASTBYTE", type: "INTEGER"),
            28: Identifier(name:"DACCESS", type: "INTEGER"),
            29: Identifier(name:"FSOFTBUF", type: "BOOLEAN"),
            30: Identifier(name:"FMAXBYTE", type: "INTEGER"),
            31: Identifier(name:"FNXTBYTE", type: "INTEGER"),
            32: Identifier(name:"FBUFCHNGD", type: "BOOLEAN"),
            33: Identifier(name:"FBUFFER", type: "ARRAY OF CHAR"),
        ], isSystemRecord: true),
        PascalRecord(name: "DIRENTRY", members: [
            0: Identifier(name:"DFIRSTBLK", type: "INTEGER"),
            1: Identifier(name:"DLASTBLK", type: "INTEGER"),
            2: Identifier(name:"DFKIND", type: "INTEGER"),
            3: Identifier(name:"DTID", type: "ARRAY OF CHAR"),
            7: Identifier(name:"DEOVBLK", type: "INTEGER"),
            8: Identifier(name:"DNUMFILES", type: "INTEGER"),
            9: Identifier(name:"DLOADTIME", type: "INTEGER"),
            10: Identifier(name:"DLASTBOOT", type: "INTEGER"),
            11: Identifier(name:"DLASTBYTE", type: "INTEGER"),
            12: Identifier(name:"DACCESS", type: "INTEGER"),
        ]),
        PascalRecord(name: "SYSCOMREC", members: [
            0: Identifier(name:"IORSLT", type: "INTEGER"),
            1: Identifier(name:"XEQERR", type: "INTEGER"),
            2: Identifier(name:"SYSUNIT", type: "INTEGER"),
            3: Identifier(name:"BUGSTATE", type: "INTEGER"),
            4: Identifier(name:"GDIRP", type: "INTEGER"),
            5: Identifier(name:"BOMBP", type: "INTEGER"),
            6: Identifier(name:"BASE", type: "INTEGER"),
            7: Identifier(name:"MP", type: "INTEGER"),
            8: Identifier(name:"JTAB", type: "INTEGER"),
            9: Identifier(name:"SEGP", type: "INTEGER"),
            10: Identifier(name:"MEMTOP", type: "INTEGER"),
            11: Identifier(name:"BOMIPC", type: "INTEGER"),
            12: Identifier(name:"HLTLINE", type: "INTEGER"),
            13: Identifier(name:"BRKPTS1", type: "INTEGER"),
            14: Identifier(name:"BRKPTS2", type: "INTEGER"),
            15: Identifier(name:"BRKPTS3", type: "INTEGER"),
            16: Identifier(name:"BRKPTS4", type: "INTEGER"),
            17: Identifier(name:"RETRIES", type: "INTEGER"),
            18: Identifier(name:"EXPANSION1", type: "INTEGER"),
            19: Identifier(name:"EXPANSION2", type: "INTEGER"),
            20: Identifier(name:"EXPANSION3", type: "INTEGER"),
            21: Identifier(name:"EXPANSION4", type: "INTEGER"),
            22: Identifier(name:"EXPANSION5", type: "INTEGER"),
            23: Identifier(name:"EXPANSION6", type: "INTEGER"),
            24: Identifier(name:"EXPANSION7", type: "INTEGER"),
            25: Identifier(name:"EXPANSION8", type: "INTEGER"),
            26: Identifier(name:"EXPANSION9", type: "INTEGER"),
            27: Identifier(name:"LOWTIME", type: "INTEGER"),
            28: Identifier(name:"HIGHTIME", type: "INTEGER"),
            29: Identifier(name:"MISCINFO", type: "INTEGER"),
            30: Identifier(name:"CRTTYPE", type: "INTEGER"),
            31: Identifier(name:"CRTCTRL1", type: "INTEGER"),
            32: Identifier(name:"CRTCTRL2", type: "INTEGER"),
            33: Identifier(name:"CRTCTRL3", type: "INTEGER"),
            34: Identifier(name:"CRTCTRL4", type: "INTEGER"),
            35: Identifier(name:"CRTCTRL5", type: "INTEGER"),
            36: Identifier(name:"CRTCTRL6", type: "INTEGER"),
            37: Identifier(name:"CRTINFO.HEIGHT", type: "INTEGER"),
            38: Identifier(name:"CRTINFO.WIDTH", type: "INTEGER"),
            39: Identifier(name:"CRTINFO.CH1", type: "INTEGER"),
            40: Identifier(name:"CRTINFO.CH2", type: "INTEGER"),
            41: Identifier(name:"CRTINFO.CH3", type: "INTEGER"),
            42: Identifier(name:"CRTINFO.CH4", type: "INTEGER"),
            43: Identifier(name:"CRTINFO.CH5", type: "INTEGER"),
            44: Identifier(name:"CRTINFO.CH6", type: "INTEGER"),
            45: Identifier(name:"CRTINFO.CH7", type: "INTEGER"),
            46: Identifier(name:"CRTINFO.CH8", type: "INTEGER"),
            47: Identifier(name:"CRTINFO.PREFIXED", type: "INTEGER"),
            48: Identifier(name:"SEGTABLE", type: "ARRAY OF SEG_ENTRY"),
        ])
    ]
}

private struct MetadataContext {
    let systemSegments = [0, 2, 3, 4, 5, 6, 20, 21, 22, 28, 29, 30, 31]
    let fileIdentifier: String
    let allLabelsCSVFile: String
    let sysLabelsCSVFile: String
    let allProceduresCSVFile: String
    let sysProceduresCSVFile: String
    let sysRecordsFile: String
    let allRecordsFile: String
    let sysTypesFile: String
    let allTypesFile: String
    let commentsFile: String
    let globalsFile: String
    let appSupportDirectory: URL
    let workspace: MetadataWorkspace?
    let store: MetadataStore

    init(fileURL: URL, segDict: SegDictionary, workspace: MetadataWorkspace? = nil, diagnostics: DiagnosticCollector? = nil) {
        let version = segDict.segTable[1]?.version ?? segDict.segTable[0]?.version ?? 0
        let fileIdentifier = fileURL.deletingPathExtension().lastPathComponent
        self.fileIdentifier = fileIdentifier
        allLabelsCSVFile = "labels_\(fileIdentifier)"
        sysLabelsCSVFile = "labels_ver_\(version)"
        allProceduresCSVFile = "procedures_\(fileIdentifier)"
        sysProceduresCSVFile = "procedures_ver_\(version)"
        sysRecordsFile = "records_ver_\(version)"
        allRecordsFile = "records_\(fileIdentifier)"
        sysTypesFile = "types_ver_\(version)"
        allTypesFile = "types_\(fileIdentifier)"
        commentsFile = "comments_\(fileIdentifier)"
        globalsFile = "globals_ver_\(version)"
        self.workspace = workspace
        appSupportDirectory = workspace?.writableDirectory ?? URL.applicationSupportDirectory
            .appendingPathComponent("pdisasm")
        store = MetadataStore(
            appSupportDirectory: appSupportDirectory,
            bundledDirectory: workspace?.bundledDirectory,
            diagnostics: diagnostics
        )
    }

    func load(
        knownRecords: inout Set<PascalRecord>,
        typeAliases: inout [String: String],
        scalarTypes: inout [String: PascalScalarType],
        constants: inout [String: Int],
        subrangeTypes: inout [String: PascalSubrangeType],
        allLocations: inout Set<Location>,
        allProcedures: inout [ProcedureIdentifier],
        lineComments: inout [InstructionReference: String],
        globalNames: inout [Int: Identifier]
    ) {
        var sysLocations: Set<Location> = []
        var sysProcedures: [ProcedureIdentifier] = []

        store.importKnownRecords(fromJson: sysRecordsFile, to: &knownRecords)
        store.importKnownRecords(fromJson: allRecordsFile, to: &knownRecords)
        store.importTypeDefinitions(
            fromPascal: sysTypesFile,
            to: &knownRecords,
            aliases: &typeAliases,
            scalarTypes: &scalarTypes,
            constants: &constants,
            subrangeTypes: &subrangeTypes,
            isSystemRecord: true
        )
        store.importTypeDefinitions(
            fromPascal: allTypesFile,
            to: &knownRecords,
            aliases: &typeAliases,
            scalarTypes: &scalarTypes,
            constants: &constants,
            subrangeTypes: &subrangeTypes
        )
        store.importLabels(fromCSV: allLabelsCSVFile, to: &allLocations)
        store.importLabels(fromCSV: sysLabelsCSVFile, to: &sysLocations)
        allLocations.formUnion(sysLocations)

        store.importGlobalLabels(fromJson: globalsFile, to: &globalNames)
        store.importDisassemblyComments(fromJson: commentsFile, to: &lineComments)

        store.importProcedures(fromCSV: allProceduresCSVFile, to: &allProcedures)
        store.importProcedures(fromCSV: sysProceduresCSVFile, to: &sysProcedures)
        allProcedures.append(contentsOf: sysProcedures)
    }

    func write(
        knownRecords: Set<PascalRecord>,
        allLocations: Set<Location>,
        allProcedures: [ProcedureIdentifier],
        overwriteMetadata: Bool
    ) throws {
        try store.createDirectory()

        store.exportKnownRecords(
            toJson: sysRecordsFile,
            from: knownRecords.filter { $0.isSystemRecord == true },
            overwrite: overwriteMetadata
        )

        store.exportKnownRecords(
            toJson: allRecordsFile,
            from: knownRecords.filter { $0.isSystemRecord == false },
            overwrite: overwriteMetadata
        )

        store.exportLabels(
            toCSV: allLabelsCSVFile,
            from: allLocations.filter {
                !systemSegments.contains($0.segment)
                    && $0.addr != nil
                    && $0.isParam == false
            }.sorted { $0 < $1 },
            overwrite: overwriteMetadata
        )
        store.exportLabels(
            toCSV: sysLabelsCSVFile,
            from: allLocations.filter {
                systemSegments.contains($0.segment)
                    && $0.addr != nil
                    && $0.isParam == false
            }.sorted { $0 < $1 },
            overwrite: overwriteMetadata
        )

        store.exportProcedures(
            toCSV: allProceduresCSVFile,
            from: allProcedures.filter { !systemSegments.contains($0.segment) },
            overwrite: overwriteMetadata
        )
        store.exportProcedures(
            toCSV: sysProceduresCSVFile,
            from: allProcedures.filter { systemSegments.contains($0.segment) },
            overwrite: overwriteMetadata
        )
    }
}

private func applyCallerLexLevels(
    codeSegments: [Int: CodeSegment],
    allCallers: inout Set<Call>
) {
    for (_, codeSeg) in codeSegments {
        for proc in codeSeg.procedures {
            guard let pt = proc.identifier else { continue }
            allCallers = Set(allCallers.map { call in
                if call.target.segment == pt.segment
                    && call.target.procedure == pt.procedure
                    && call.target.lexLevel == nil
                {
                    call.target.lexLevel = proc.lexicalLevel
                }
                if call.origin.segment == pt.segment
                    && call.origin.procedure == pt.procedure
                    && call.origin.lexLevel == nil
                {
                    call.origin.lexLevel = proc.lexicalLevel
                }
                return call
            })
        }
    }
}

private func normaliseDecodedLocations(
    codeSegments: [Int: CodeSegment],
    allCallers: Set<Call>,
    allLocations: inout Set<Location>
) {
    for (_, codeSeg) in codeSegments {
        for proc in codeSeg.procedures {
            normaliseMemoryLocations(proc, allCallers)
            let missingLexLevelLocations = allLocations.filter({
                $0.isParam == false
                    && $0.lexLevel == nil
                    && $0.segment == proc.identifier?.segment
                    && $0.procedure == proc.identifier?.procedure
            })
            for loc in missingLexLevelLocations {
                allLocations.remove(loc)
                loc.lexLevel = proc.lexicalLevel
                allLocations.insert(loc)
            }
        }
    }
}

private func simulatePascalProcedures(
    codeSegments: [Int: CodeSegment],
    knownRecords: Set<PascalRecord>,
    typeAliases: [String: String],
    scalarTypes: [String: PascalScalarType],
    allProcedures: inout [ProcedureIdentifier],
    allLocations: inout Set<Location>,
    diagnostics: DiagnosticCollector
) -> [TypeConflict] {
    var typeConflicts: [TypeConflict] = []

    for (_, codeSeg) in codeSegments {
        for proc in codeSeg.procedures {
            if proc.identifier?.isAssembly == true {
                continue
            }
            typeConflicts.append(contentsOf: simulateStackAndGeneratePseudocode(
                proc: proc,
                knownRecords: knownRecords,
                typeAliases: typeAliases,
                scalarTypes: scalarTypes,
                allProcedures: &allProcedures,
                allLocations: &allLocations,
                diagnostics: diagnostics
            ))
        }
    }

    return typeConflicts
}

private func decodeCodeSegments(
    segDict: SegDictionary,
    binaryData: CodeData,
    verbose: Bool,
    allLocations: inout Set<Location>,
    allProcedures: inout [ProcedureIdentifier],
    allCallers: inout Set<Call>,
    dataSegments: inout [Int],
    diagnostics: DiagnosticCollector
) throws -> [Int: CodeSegment] {
    try CodeSegmentDecoder(
        segDict: segDict,
        binaryData: binaryData,
        verbose: verbose,
        diagnostics: diagnostics
    ).decode(
        allLocations: &allLocations,
        allProcedures: &allProcedures,
        allCallers: &allCallers,
        dataSegments: &dataSegments
    )
}

private func applyDisassemblyComments(
    _ comments: [InstructionReference: String],
    to codeSegments: [Int: CodeSegment]
) {
    guard !comments.isEmpty else { return }
    for (segment, codeSegment) in codeSegments {
        for proc in codeSegment.procedures {
            let procedure = proc.identifier?.procedure
            for (addr, instruction) in proc.instructions {
                let reference = InstructionReference(
                    segment: segment,
                    procedure: procedure,
                    addr: addr
                )
                guard let comment = comments[reference] else { continue }
                let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
                instruction.userComment = trimmed.isEmpty ? nil : trimmed
            }
        }
    }
}

private func prepareDecodedProgram(
    codeSegments: [Int: CodeSegment],
    allCallers: inout Set<Call>,
    allLocations: inout Set<Location>
) -> [TypeConflict] {
    applyCallerLexLevels(codeSegments: codeSegments, allCallers: &allCallers)
    normaliseDecodedLocations(
        codeSegments: codeSegments,
        allCallers: allCallers,
        allLocations: &allLocations
    )
    return applyInitialProcedureSignatureLocations(
        codeSegments: codeSegments,
        allLocations: &allLocations
    )
}

private func runPascalAnalysisPass(
    codeSegments: [Int: CodeSegment],
    knownRecords: Set<PascalRecord>,
    typeAliases: [String: String],
    scalarTypes: [String: PascalScalarType],
    allProcedures: inout [ProcedureIdentifier],
    allLocations: inout Set<Location>,
    diagnostics: DiagnosticCollector
) -> [TypeConflict] {
    var typeConflicts = simulatePascalProcedures(
        codeSegments: codeSegments,
        knownRecords: knownRecords,
        typeAliases: typeAliases,
        scalarTypes: scalarTypes,
        allProcedures: &allProcedures,
        allLocations: &allLocations,
        diagnostics: diagnostics
    )
    typeConflicts.append(contentsOf: synchronizeSignaturesAndLocations(
        allProcedures: allProcedures,
        codeSegments: codeSegments,
        allLocations: &allLocations
    ))
    return typeConflicts
}


private struct SegmentDecodeStageOutput {
    var codeSegments: [Int: CodeSegment]
    var dataSegments: [Int]
    var report: StageReport
}

private struct SegmentDecodeStageFacade {
    func run(
        segDict: SegDictionary,
        binaryData: CodeData,
        verbose: Bool,
        allLocations: inout Set<Location>,
        allProcedures: inout [ProcedureIdentifier],
        allCallers: inout Set<Call>,
        diagnostics: DiagnosticCollector
    ) throws -> SegmentDecodeStageOutput {
        let diagnosticsBefore = diagnostics.diagnostics.count
        let locationsBefore = allLocations.count
        let proceduresBefore = allProcedures.count
        let callersBefore = allCallers.count
        var dataSegments: [Int] = []
        let codeSegments = try decodeCodeSegments(
            segDict: segDict,
            binaryData: binaryData,
            verbose: verbose,
            allLocations: &allLocations,
            allProcedures: &allProcedures,
            allCallers: &allCallers,
            dataSegments: &dataSegments,
            diagnostics: diagnostics
        )
        let procedureCount = codeSegments.values.reduce(0) { $0 + $1.procedures.count }
        let instructionCount = codeSegments.values.reduce(0) { total, segment in
            total + segment.procedures.reduce(0) { $0 + $1.instructions.count }
        }
        let diagnosticsAdded = diagnostics.diagnostics.count - diagnosticsBefore
        return SegmentDecodeStageOutput(
            codeSegments: codeSegments,
            dataSegments: dataSegments,
            report: StageReport(name: "decode", metrics: [
                "segments": codeSegments.count,
                "procedures": procedureCount,
                "instructions": instructionCount,
                "dataSegments": dataSegments.count,
                "locationsAdded": allLocations.count - locationsBefore,
                "proceduresAdded": allProcedures.count - proceduresBefore,
                "callersAdded": allCallers.count - callersBefore,
                "diagnosticsAdded": diagnosticsAdded,
            ], diagnostics: diagnostics.diagnostics.suffix(diagnosticsAdded).map(\.message))
        )
    }
}

private struct ReferenceResolutionStageOutput {
    var typeConflicts: [TypeConflict]
    var report: StageReport
}

private struct ReferenceResolutionStageFacade {
    func run(
        codeSegments: [Int: CodeSegment],
        lineComments: [InstructionReference: String],
        allCallers: inout Set<Call>,
        allLocations: inout Set<Location>,
        diagnostics: DiagnosticCollector
    ) -> ReferenceResolutionStageOutput {
        let diagnosticsBefore = diagnostics.diagnostics.count
        let locationsBefore = allLocations.count
        applyDisassemblyComments(lineComments, to: codeSegments)
        let conflicts = prepareDecodedProgram(
            codeSegments: codeSegments,
            allCallers: &allCallers,
            allLocations: &allLocations
        )
        let diagnosticsAdded = diagnostics.diagnostics.count - diagnosticsBefore
        return ReferenceResolutionStageOutput(
            typeConflicts: conflicts,
            report: StageReport(name: "referenceResolution", metrics: [
                "callers": allCallers.count,
                "locations": allLocations.count,
                "locationsAdded": allLocations.count - locationsBefore,
                "commentsApplied": lineComments.count,
                "typeConflicts": conflicts.count,
                "diagnosticsAdded": diagnosticsAdded,
            ], diagnostics: diagnostics.diagnostics.suffix(diagnosticsAdded).map(\.message))
        )
    }
}

private struct AnalysisSignatureStageOutput {
    var typeConflicts: [TypeConflict]
    var converged: Bool
    var iterations: Int
    var report: StageReport
}

private struct AnalysisSignatureStageFacade {
    let maxSignatureIterations = 4

    func run(
        codeSegments: [Int: CodeSegment],
        knownRecords: Set<PascalRecord>,
        typeAliases: [String: String],
        scalarTypes: [String: PascalScalarType],
        allProcedures: inout [ProcedureIdentifier],
        allLocations: inout Set<Location>,
        diagnostics: DiagnosticCollector
    ) -> AnalysisSignatureStageOutput {
        let diagnosticsBefore = diagnostics.diagnostics.count
        var typeConflicts: [TypeConflict] = []
        var iterations = 0
        var previousFingerprint: String?
        var converged = false
        while iterations < maxSignatureIterations {
            iterations += 1
            typeConflicts.append(contentsOf: runPascalAnalysisPass(
                codeSegments: codeSegments,
                knownRecords: knownRecords,
                typeAliases: typeAliases,
                scalarTypes: scalarTypes,
                allProcedures: &allProcedures,
                allLocations: &allLocations,
                diagnostics: diagnostics
            ))
            let fingerprint = analysisFingerprint(allProcedures: allProcedures, allLocations: allLocations)
            if fingerprint == previousFingerprint {
                converged = true
                break
            }
            previousFingerprint = fingerprint
        }
        if !converged {
            diagnostics.warning("Signature/type analysis did not converge after \(maxSignatureIterations) iterations")
        }
        let diagnosticsAdded = diagnostics.diagnostics.count - diagnosticsBefore
        let stageDiagnostics = diagnostics.diagnostics.suffix(diagnosticsAdded).map(\.message)
        return AnalysisSignatureStageOutput(
            typeConflicts: typeConflicts,
            converged: converged,
            iterations: iterations,
            report: StageReport(name: "analysis", isComplete: converged, metrics: [
                "iterations": iterations,
                "maxIterations": maxSignatureIterations,
                "procedures": allProcedures.count,
                "locations": allLocations.count,
                "typeConflicts": typeConflicts.count,
                "diagnosticsAdded": diagnosticsAdded,
            ], diagnostics: stageDiagnostics)
        )
    }
}

/// Disassemble a binary file and return structured results without printing.
public func disassemble(
    filename: String,
    verbose: Bool = false,
    writeMetadata: Bool = false,
    overwriteMetadata: Bool = false,
    metadataWorkspace: MetadataWorkspace? = nil,
    metadataSnapshot: MetadataSnapshot? = nil
) throws -> DisassemblyResult {
    var fileURL: URL
    var binaryData: CodeData
    do {
        fileURL = URL(fileURLWithPath: filename)
        binaryData = try CodeData(data: Data(contentsOf: fileURL))
    } catch {
        throw error
    }

    let segDict = try readCodeFileStructure(codeData: binaryData)
    let diagnostics = DiagnosticCollector()
    let metadata = MetadataContext(fileURL: fileURL, segDict: segDict, workspace: metadataWorkspace, diagnostics: diagnostics)

    var allLocations: Set<Location> = []
    var allProcedures: [ProcedureIdentifier] = []
    var allCallers: Set<Call> = []
    var typeConflicts: [TypeConflict] = []
    var dataSegments: [Int] = []
    var knownRecords = defaultKnownRecords()
    var typeAliases: [String: String] = [:]
    var scalarTypes: [String: PascalScalarType] = [:]
    var constants: [String: Int] = [:]
    var subrangeTypes: [String: PascalSubrangeType] = [:]
    var lineComments: [InstructionReference: String] = [:]

    // Try loading name maps from the resolved metadata snapshot or workspace.
    // Missing metadata is fine; writeback is controlled separately by the caller.
    var globalNames: [Int: Identifier] = [:]
    if let metadataSnapshot {
        allLocations.formUnion(metadataSnapshot.labels.map(\.value))
        allProcedures.append(contentsOf: metadataSnapshot.procedures.map(\.value))
        for comment in metadataSnapshot.comments {
            lineComments[comment.value.reference] = comment.value.comment
        }
    } else {
        metadata.load(
            knownRecords: &knownRecords,
            typeAliases: &typeAliases,
            scalarTypes: &scalarTypes,
            constants: &constants,
            subrangeTypes: &subrangeTypes,
            allLocations: &allLocations,
            allProcedures: &allProcedures,
            lineComments: &lineComments,
            globalNames: &globalNames
        )
    }

    let decode = try SegmentDecodeStageFacade().run(
        segDict: segDict,
        binaryData: binaryData,
        verbose: verbose,
        allLocations: &allLocations,
        allProcedures: &allProcedures,
        allCallers: &allCallers,
        diagnostics: diagnostics
    )
    let allCodeSegs = decode.codeSegments
    dataSegments = decode.dataSegments

    let references = ReferenceResolutionStageFacade().run(
        codeSegments: allCodeSegs,
        lineComments: lineComments,
        allCallers: &allCallers,
        allLocations: &allLocations,
        diagnostics: diagnostics
    )
    typeConflicts.append(contentsOf: references.typeConflicts)

    let analysis = AnalysisSignatureStageFacade().run(
        codeSegments: allCodeSegs,
        knownRecords: knownRecords,
        typeAliases: typeAliases,
        scalarTypes: scalarTypes,
        allProcedures: &allProcedures,
        allLocations: &allLocations,
        diagnostics: diagnostics
    )
    typeConflicts.append(contentsOf: analysis.typeConflicts)
    let analysisConverged = analysis.converged

    let baseStages = [
        StageReport(name: "codefileLoading", metrics: ["bytes": binaryData.data.count]),
        StageReport(name: "metadataMerge", metrics: [
            "labels": allLocations.count,
            "procedures": allProcedures.count,
            "comments": lineComments.count,
            "records": knownRecords.count,
            "typeAliases": typeAliases.count,
            "scalarTypes": scalarTypes.count,
        ]),
        decode.report,
        references.report,
        analysis.report,
    ]
    let result = DisassemblyResult(
        sourceFilename: metadata.fileIdentifier,
        segDictionary: segDict,
        codeSegments: allCodeSegs,
        dataSegments: dataSegments,
        allLocations: allLocations,
        allProcedures: allProcedures,
        allCallers: allCallers,
        knownRecords: knownRecords,
        typeAliases: typeAliases,
        scalarTypes: scalarTypes,
        constants: constants,
        subrangeTypes: subrangeTypes,
        typeConflicts: typeConflicts,
        diagnostics: diagnostics.diagnostics,
        runReport: RunReport(stages: baseStages, isComplete: analysisConverged)
    )

    if writeMetadata {
        try metadata.write(
            knownRecords: knownRecords,
            allLocations: allLocations,
            allProcedures: allProcedures,
            overwriteMetadata: overwriteMetadata
        )
    }

    return result
}

//@available(*, deprecated, renamed: "disassemble(filename:verbose:writeMetadata:overwriteMetadata:)")
//public func disassemble(
//    filename: String,
//    verbose: Bool = false,
//    rewrite: Bool
//) throws -> DisassemblyResult {
//    try disassemble(
//        filename: filename,
//        verbose: verbose,
//        writeMetadata: rewrite,
//        overwriteMetadata: rewrite
//    )
//}

/// Render a ``DisassemblyResult`` to a String using the shared output logic.
public func renderDisassembly(
    _ result: DisassemblyResult,
    showMarkup: Bool = true,
    showPCode: Bool = true,
    showStackState: Bool = false,
    showPseudoCode: Bool = true,
    showDot: Bool = false,
    verbose: Bool = false
) -> String {
    let stream = StringStream()
    var s: TextOutputStream = stream
    outputResults(
        to: &s,
        sourceFilename: result.sourceFilename,
        segDictionary: result.segDictionary,
        codeSegs: result.codeSegments,
        dataSegs: result.dataSegments,
        allLocations: result.allLocations,
        allProcedures: result.allProcedures,
        allCallers: result.allCallers,
        knownRecords: result.knownRecords,
        typeAliases: result.typeAliases,
        scalarTypes: result.scalarTypes,
        constants: result.constants,
        subrangeTypes: result.subrangeTypes,
        typeConflicts: result.typeConflicts,
        diagnostics: result.diagnostics,
        verbose: verbose,
        showMarkup: showMarkup,
        showPCode: showPCode,
        showStackState: showStackState,
        showPseudoCode: showPseudoCode,
        showDot: showDot
    )
    return stream.text
}

/// Public entrypoint for the library to run the decompiler.
/// This mirrors the original CLI behaviour but is exposed as a callable function
/// so the `pdisasm-cli` executable can delegate to it.
public func runPdisasm(
    filename: String,
    verbose: Bool = false,
    rewrite: Bool = false,
    showMarkup: Bool = false,
    showPCode: Bool = false,
    showStackState: Bool = false,
    showPseudoCode: Bool = false,
    showDot: Bool = false
) throws {
    let runResult = try DisassemblyService().run(DisassemblyRunRequest(
        source: .file(URL(fileURLWithPath: filename)),
        options: DisassemblyOptions(
            verbose: verbose,
            writeMetadata: rewrite,
            overwriteMetadata: rewrite,
            showMarkup: showMarkup,
            showPCode: showPCode,
            showStackState: showStackState,
            showPseudoCode: showPseudoCode,
            showDot: showDot
        )
    ))
    let result = runResult.legacyResult

    outputResults(
        sourceFilename: result.sourceFilename,
        segDictionary: result.segDictionary,
        codeSegs: result.codeSegments,
        dataSegs: result.dataSegments,
        allLocations: result.allLocations,
        allProcedures: result.allProcedures,
        allCallers: result.allCallers,
        knownRecords: result.knownRecords,
        typeAliases: result.typeAliases,
        scalarTypes: result.scalarTypes,
        constants: result.constants,
        subrangeTypes: result.subrangeTypes,
        typeConflicts: result.typeConflicts,
        diagnostics: result.diagnostics,
        verbose: verbose,
        showMarkup: showMarkup,
        showPCode: showPCode,
        showStackState: showStackState,
        showPseudoCode: showPseudoCode,
        showDot: showDot
    )
}

private func analysisFingerprint(
    allProcedures: [ProcedureIdentifier],
    allLocations: Set<Location>
) -> String {
    let procedureFacts = allProcedures
        .sorted { lhs, rhs in
            if lhs.segment != rhs.segment { return lhs.segment < rhs.segment }
            return lhs.procedure < rhs.procedure
        }
        .map { procedure in
            [
                String(procedure.segment),
                String(procedure.procedure),
                procedure.procName ?? "",
                procedure.returnType ?? "",
                procedure.parameters.map { "\($0.name):\($0.type):\($0.typeSource.rawValue)" }.joined(separator: ","),
                procedure.parameterLocations.map { "\($0.name):\($0.type):\($0.typeSource.rawValue)" }.joined(separator: ","),
            ].joined(separator: "|")
        }
    let locationFacts = allLocations
        .sorted()
        .map { location in
            [
                String(location.segment),
                location.procedure.map(String.init) ?? "",
                location.lexLevel.map(String.init) ?? "",
                location.addr.map(String.init) ?? "",
                location.name,
                location.type,
                location.typeSource.rawValue,
                String(location.isParam),
            ].joined(separator: "|")
        }
    return (procedureFacts + locationFacts).joined(separator: "\n")
}
