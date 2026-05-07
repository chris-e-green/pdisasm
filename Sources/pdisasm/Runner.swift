import Algorithms
import CodableCSV
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

func resolveAssemblerProcedureTargets(
    in codeSeg: CodeSegment,
    allProcedures: inout [ProcedureIdentifier],
    allCallers: inout Set<Call>
) {
    let assemblerProcedures = codeSeg.procedures
        .filter { $0.identifier?.isAssembly == true && $0.segmentEndAddress != nil }
        .sorted { ($0.segmentEndAddress ?? Int.max) < ($1.segmentEndAddress ?? Int.max) }

    guard !assemblerProcedures.isEmpty else { return }

    var lowerBound = 0
    for proc in assemblerProcedures {
        proc.segmentStartAddress = lowerBound
        lowerBound = proc.segmentEndAddress ?? lowerBound
        registerProcedureIdentifier(proc, in: &allProcedures)
    }

    func owningProcedure(for targetAddress: Int) -> Procedure? {
        assemblerProcedures.first(where: {
            guard let start = $0.segmentStartAddress,
                let end = $0.segmentEndAddress
            else {
                return false
            }
            return start <= targetAddress && targetAddress < end
        })
    }

    func appendComment(_ text: String, to instruction: Instruction) {
        if let existing = instruction.comment, !existing.isEmpty {
            if !existing.contains(text) {
                instruction.comment = existing + "; " + text
            }
        } else {
            instruction.comment = text
        }
    }

    // Process all procedures (not just assembler) to find cross-procedure calls
    // This includes Pascal procedures that may have inline assembler or that may call
    // into assembler routines
    for proc in codeSeg.procedures {
        guard let sourceIdentifier = proc.identifier else { continue }
        let origin = Location(
            segment: sourceIdentifier.segment,
            procedure: sourceIdentifier.procedure,
            lexLevel: proc.lexicalLevel
        )

        for instruction in proc.instructions.values where instruction.isPascal == false {
            guard [0x20, 0x4c].contains(instruction.opcode),
                let targetAddress = instruction.params.first,
                let targetProcedure = owningProcedure(for: targetAddress),
                let targetIdentifier = targetProcedure.identifier
            else {
                continue
            }

            instruction.destination = Location(
                segment: targetIdentifier.segment,
                procedure: targetIdentifier.procedure,
                lexLevel: targetProcedure.lexicalLevel,
                addr: targetAddress
            )

            let crossesProcedure = targetIdentifier.segment != sourceIdentifier.segment
                || targetIdentifier.procedure != sourceIdentifier.procedure

            if instruction.opcode == 0x4c, crossesProcedure
            {
                appendComment("tailcall", to: instruction)
            }

            if crossesProcedure && [0x20, 0x4c].contains(instruction.opcode)
            {
                // Mark the target address as an entry point in the target procedure
                targetProcedure.entryPoints.insert(targetAddress)
                
                allCallers.insert(
                    Call(
                        from: origin,
                        to: Location(
                            segment: targetIdentifier.segment,
                            procedure: targetIdentifier.procedure,
                            lexLevel: targetProcedure.lexicalLevel
                        )
                    )
                )
            }
        }
    }
}

/// Public entrypoint for the library to run the decompiler.
/// This mirrors the original CLI behaviour but is exposed as a callable function
/// so the `pdisasm-cli` executable can delegate to it.
// MARK: - Metadata I/O Helpers

func importLabels(
    fromCSV CSVFile: String,
    to labels: inout Set<Location>,
    appSupportDirectory: URL
) {
    do {
        let fileURL = appSupportDirectory.appendingPathComponent(CSVFile).appendingPathExtension("csv")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let dec = CSVDecoder()
            dec.headerStrategy = .firstLine
            if let labelsData = try? Data(
                contentsOf: URL(fileURLWithPath: fileURL.path)
            ) {
                labels = try dec.decode(
                    Set<Location>.self,
                    from: labelsData
                )
            }
        }
    } catch {
        print("Error reading \(CSVFile): \(error)")
    }
}

func exportLabels(
    toCSV CSVfile: String,
    from labels: [Location],
    overwrite: Bool = false,
    appSupportDirectory: URL
) {
    do {
        let fileURL = appSupportDirectory.appendingPathComponent(CSVfile).appendingPathExtension("csv")
        if !overwrite && FileManager.default.fileExists(atPath: fileURL.path) {
            return
        }
        let backupURL = fileURL.appendingPathExtension("bak")
        if FileManager.default.fileExists(atPath: backupURL.path) {
            try? FileManager.default.removeItem(at: backupURL)
        }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.copyItem(
                at: fileURL,
                to: backupURL
            )
        }
        let enc = CSVEncoder {
            $0.headers = [
                "segment", "procedure", "lexLevel", "addr", "name", "type",
            ]
            $0.bufferingStrategy = .sequential
        }
        try enc.encode(labels, into: fileURL)
    } catch {
        print("Error writing \(CSVfile): \(error)")
    }
}

func importProcedures(
    fromCSV CSVFile: String,
    to allProcedures: inout [ProcedureIdentifier],
    appSupportDirectory: URL
) {
    do {
        let fileURL = appSupportDirectory.appendingPathComponent(CSVFile).appendingPathExtension("csv")

        if FileManager.default.fileExists(atPath: fileURL.path) {
            let dec = CSVDecoder()
            dec.headerStrategy = .firstLine
            if let procData = try? Data(
                contentsOf: URL(fileURLWithPath: fileURL.path)
            ) {
                allProcedures = try dec.decode(
                    [ProcedureIdentifier].self,
                    from: procData
                )
            }
        }

    } catch {
        print("Error reading \(CSVFile): \(error)")
    }
}

func exportProcedures(
    toCSV CSVfile: String,
    from procedures: [ProcedureIdentifier],
    overwrite: Bool = false,
    appSupportDirectory: URL
) {
    do {
        let fileURL = appSupportDirectory.appendingPathComponent(CSVfile).appendingPathExtension("csv")

        // check if file exists and overwrite is false
        if !overwrite
            && FileManager.default.fileExists(atPath: fileURL.path)
        {
            return
        }

        let backupURL = fileURL.appendingPathExtension("bak")
        if FileManager.default.fileExists(atPath: backupURL.path) {
            try? FileManager.default.removeItem(at: backupURL)
        }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.copyItem(at: fileURL, to: backupURL)
        }
        let enc = CSVEncoder { configuration in
            configuration.headers = [
                "segmentNumber", "segmentName", "procNumber", "procName",
                "isFunction",
                "isAssembly", "parameters", "returnType",
            ]
        }
        try enc.encode(procedures, into: fileURL)

    } catch {
        print("Error writing \(CSVfile): \(error)")
    }
}

func importGlobalLabels(
    fromJson globalsFile: String,
    to globalNames: inout [Int: Identifier],
    appSupportDirectory: URL
) {
    let fileURL = appSupportDirectory.appendingPathComponent(globalsFile).appendingPathExtension("json")

    if FileManager.default.fileExists(atPath: fileURL.path) {

        let decoder = JSONDecoder()

        if let globalData = try? Data(contentsOf: fileURL) {
            globalNames =
                (try? decoder.decode(
                    [Int: Identifier].self,
                    from: globalData
                )) ?? [:]
        }
    }
}

func exportKnownRecords(
    toJson Jsonfile: String,
    from knownRecords: Set<PascalRecord>,
    overwrite: Bool = false,
    appSupportDirectory: URL
) {
    do {
        let fileURL = appSupportDirectory.appendingPathComponent(Jsonfile).appendingPathExtension("json")

        // check if file exists and overwrite is false
        if !overwrite
            && FileManager.default.fileExists(atPath: fileURL.path)
        {
            return
        }

        let backupURL = fileURL.appendingPathExtension("bak")
        if FileManager.default.fileExists(atPath: backupURL.path) {
            try? FileManager.default.removeItem(at: backupURL)
        }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.copyItem(at: fileURL, to: backupURL)
        }
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .prettyPrinted]
//        let enc = CSVEncoder { configuration in
//            configuration.headers = [
//                "segmentNumber", "segmentName", "procNumber", "procName",
//                "isFunction",
//                "isAssembly", "parameters", "returnType",
//            ]
//        }
        try enc.encode(knownRecords).write(to: fileURL, options: .atomic)

    } catch {
        print("Error writing \(Jsonfile): \(error)")
    }
}

func importKnownRecords(
    fromJson Jsonfile: String,
    to knownRecords: inout Set<PascalRecord>,
    appSupportDirectory: URL)
{
    let fileURL = appSupportDirectory.appendingPathComponent(Jsonfile).appendingPathExtension("json")

    if FileManager.default.fileExists(atPath: fileURL.path) {

        let decoder = JSONDecoder()

        if let newData = try? Data(contentsOf: fileURL) {
            if let newRecords =
                try? decoder.decode(
                    [PascalRecord].self,
                    from: newData
                ) {
                knownRecords.formUnion(newRecords)
            }
        }
    }
}
// MARK: - Code File Parsing

func readCodeFileStructure(codeData: CodeData) throws -> SegDictionary {
    // Read header pieces (first 512 bytes assumed)
    let diskInfo = CodeData(data: codeData.data.subdata(in: 0..<64))
    let segName = CodeData(data: codeData.data.subdata(in: 64..<192))
    let segKind = CodeData(data: codeData.data.subdata(in: 192..<224))
    let textAddr = CodeData(data: codeData.data.subdata(in: 224..<256))
    let segInfo = CodeData(data: codeData.data.subdata(in: 256..<288))
    let intrinsSegs = CodeData(data: codeData.data.subdata(in: 288..<296))
    let comment = CodeData(data: codeData.data.subdata(in: 433..<512))

    var segTable: [Int: Segment] = [:]

    // decode Segment Dictionary (per-segment parts)
    for segIdx in 0...15 {
        let codeAddress = Int(try diskInfo.readWord(at: segIdx * 4))
        let codeLength = Int(try diskInfo.readWord(at: segIdx * 4 + 2))
        var name = ""
        for j in 0...7 {
            name.append(
                String(
                    UnicodeScalar(
                        Int(try segName.readByte(at: segIdx * 8 + j))
                    )!
                )
            )
        }
        name = name.trimmingCharacters(in: [" "])
        let kind = SegmentKind(
            rawValue: Int(try segKind.readWord(at: segIdx * 2))
        )
        var segNum = Int(try segInfo.readByte(at: segIdx * 2))
        if segNum == 0 { segNum = segIdx }
        let machineType = Int(try segInfo.readByte(at: segIdx * 2 + 1) & 0x0F)
        let version = Int(
            (try segInfo.readByte(at: segIdx * 2 + 1) & 0xE0) >> 5
        )
        let text = try textAddr.readWord(at: segIdx * 2)
        if codeLength > 0 {
            segTable[segIdx] = Segment(
                codeAddress: codeAddress,
                codeLength: codeLength,
                name: name,
                segmentKind: kind ?? .dataseg,
                textAddress: Int(text),
                segNum: segNum,
                machineType: machineType,
                version: version
            )
        }
    }

    // intrinsic set
    var intrinsicSet = Set<UInt8>()
    for (i, value) in intrinsSegs.data.enumerated().reversed() {
        for j in 0..<8 {
            if (value >> j) & 1 == 1 {
                intrinsicSet.insert(UInt8(i * 8 + j))
            }
        }
    }

    let commentStr = comment.data.filter { $0 > 0 }.compactMap {
        UnicodeScalar($0)
    }.map(
        String.init
    ).joined()

    return SegDictionary(
        segTable: segTable,
        intrinsics: intrinsicSet,
        comment: commentStr
    )
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
                    if let p = allCallers.first(where: {
                        $0.origin.lexLevel == 0
                    }) {
                        inst.memLocation?.procedure = p.origin.procedure
                        inst.memLocation?.segment = p.origin.segment
                    } else {
                        print(
                            "\(proc.shortDescription): Memory location \(loc) doesn't match any caller"
                        )
                    }
                case proc.lexicalLevel:
                    print(
                        "\(proc.shortDescription): Memory location \(loc) has lex level \(lexLevel) and is local ",
                        terminator: " "
                    )
                    inst.memLocation?.procedure = proc.identifier?.procedure
                    print("Memory location is now \(loc).")
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
}

/// Disassemble a binary file and return structured results without printing.
public func disassemble(
    filename: String,
    verbose: Bool = false,
    rewrite: Bool = false
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

    var allCodeSegs: [Int: CodeSegment] = [:]
    var allLocations: Set<Location> = []
    var sysLocations: Set<Location> = []
    var allProcedures: [ProcedureIdentifier] = []
    var sysProcedures: [ProcedureIdentifier] = []
    var allCallers: Set<Call> = []
    var dataSegments: [Int] = []
    
    var knownRecords: Set<PascalRecord> = [
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

    // Try loading name maps (optional files in repo)
    var globalNames: [Int: Identifier] = [:]
    let version = segDict.segTable[1]?.version ?? segDict.segTable[0]?.version ?? 0
    let fileIdentifier = fileURL.deletingPathExtension().lastPathComponent
    let allLabelsCSVFile = "labels_\(fileIdentifier)"
    let sysLabelsCSVFile = "labels_ver_\(version)"
    let allProceduresCSVFile = "procedures_\(fileIdentifier)"
    let sysProceduresCSVFile = "procedures_ver_\(version)"
    let sysRecordsFile = "records_ver_\(version)"
    let allRecordsFile = "records_\(fileIdentifier)"
    let globalsFile = "globals_ver_\(version)"
    let appSupportDirectory = URL.applicationSupportDirectory
        .appendingPathComponent("pdisasm")
    try FileManager.default.createDirectory(
        at: appSupportDirectory,
        withIntermediateDirectories: true,
        attributes: nil
    )

    importKnownRecords(
        fromJson: sysRecordsFile,
        to: &knownRecords,
        appSupportDirectory: appSupportDirectory
    )
    importKnownRecords(
        fromJson: allRecordsFile,
        to: &knownRecords,
        appSupportDirectory: appSupportDirectory
    )
    importLabels(
        fromCSV: allLabelsCSVFile,
        to: &allLocations,
        appSupportDirectory: appSupportDirectory
    )
    importLabels(
        fromCSV: sysLabelsCSVFile,
        to: &sysLocations,
        appSupportDirectory: appSupportDirectory
    )

    allLocations.formUnion(sysLocations)

    importGlobalLabels(
        fromJson: globalsFile,
        to: &globalNames,
        appSupportDirectory: appSupportDirectory
    )

    importProcedures(
        fromCSV: allProceduresCSVFile,
        to: &allProcedures,
        appSupportDirectory: appSupportDirectory
    )
    importProcedures(
        fromCSV: sysProceduresCSVFile,
        to: &sysProcedures,
        appSupportDirectory: appSupportDirectory
    )

    allProcedures.append(contentsOf: sysProcedures)

    // For each segment, extract code blocks and decode procedures
    for segment in segDict.segTable.sorted(by: { $0.key < $1.key }) {
        let seg = segment.value
        var extraCodeOffset = 0
        let code = binaryData.getCodeBlock(
            at: seg.codeAddress,
            length: seg.codeLength
        )

        // If the extracted code block is missing or too small to contain the
        // expected trailer bytes, skip this segment to avoid out-of-bounds
        // subscripting on `Data` (which can crash at runtime on some platforms).
        if code.count < 2 {
            if verbose {
                print(
                    "Skipping segment \(seg.name) (segNum=\(seg.segNum)): code block too small (len=\(code.count))"
                )
            }
            continue
        }
        
        if seg.segmentKind == .dataseg  {
            dataSegments.append(Int(seg.segNum))
            // data segments don't have content within the file - the runtime just reserves memory
            // for them, so we don't need to try to read anything for them. There are no procedures,
            // so we can skip to the next segment.
            if verbose {
                print("Segment \(seg.name) (segNum=\(seg.segNum)): segment kind is .dataseg")
            }
            continue
        }
        
        // count of procedures in this segment
        let procCount = Int(code[code.endIndex - 1])
        
        // wrap the code in a CodeData to make it easier to read from it.
        let codeData = CodeData(data: code, instructionPointer: 0, header: 0)
        
        // This applies to the core pascal operating system file (SYSTEM.PASCAL).
        // Segment 0 (the PASCALSYSTEM segment) is actually split between
        // slots 0 and 15 in the segment table. The part that's in slot 15
        // has a name that is eight spaces - so more or less hidden.
        // The runtime loads these parts into memory locations that vary
        // from version to version.
        // The procedure table in slot 0's part contains references to
        // procedures contained in slot 15, stored as negative addresses.
        // (On a 6502, the negative addresses just wrap around to where
        // the runtime has loaded the second part.)
        // We deal with this in our code by determining an offset that we can
        // add to any negative address in the procedure table to turn it
        // into a positive address within the slot 15 part.

        var extraCode: Data = Data()
        // slots 0 and 15 may need to be handled differently - IF they are
        // part of the PASCALSY segment.
        if seg.segNum == 0 && seg.name == "PASCALSY" {
            if let extraSeg = segDict.segTable[15] {
                extraCode = binaryData.getCodeBlock(
                    at: extraSeg.codeAddress,
                    length: extraSeg.codeLength
                )
                let lastProcHdrLoc = code.endIndex - procCount * 2 - 2
                let lastProcRelativeAddr = Int(
                    try codeData.readWord(at: lastProcHdrLoc)
                )
                let lastProcAbsAddr = lastProcRelativeAddr - lastProcHdrLoc
                extraCodeOffset = lastProcAbsAddr + extraCode.endIndex - 2
            }
        }
        if seg.segNum == 15 && seg.name == "" {
            // if we are processing the 'hidden' part of PASCALSY from
            // slot 15, skip it, because we will have processed all of
            // its procedures when we dealt with slot 0.
            continue
        }

        let codeSeg: CodeSegment = CodeSegment(
            procedureDictionary: ProcedureDictionary(
                procedureCount: procCount,
                procedurePointers: []
            ),
            procedures: []
        )

        for i in 1...codeSeg.procedureDictionary.procedureCount {
            let procPtrOffset = code.endIndex - i * 2 - 2
            if let procPtr = try? codeData.getSelfRefPointer(at: procPtrOffset) {
                codeSeg.procedureDictionary.procedurePointers.append(procPtr)
            } else {
                codeSeg.procedureDictionary.procedurePointers.append(0)
            }
        }

        var assemblerProcedureBoundsByIndex: [Int: Range<Int>] = [:]
        if seg.machineType == 7 {
            let sortedEnds = codeSeg.procedureDictionary.procedurePointers.enumerated()
                .map { ($0.offset, $0.element + 2) }
                .filter { $0.1 >= 0 }
                .sorted { $0.1 < $1.1 }

            var lowerBound = 0
            for (index, endAddress) in sortedEnds {
                let upperBound = max(endAddress, lowerBound)
                assemblerProcedureBoundsByIndex[index] = lowerBound..<upperBound
                lowerBound = upperBound
            }
        }

        var tempCallers: Set<Call> = []
        // track assembly entry points across procedures within a segment because they can call
        // each other directly by absolute address, without going through the procedure table. This means we won't be able to assign them to a procedure based on calls from other procedures, so we need to track them separately and assign them to a pseudo-procedure for the assembler code at the end.
        var asmEntryPoints: Set<Int> = []

        for (procIdx, procPtr) in codeSeg.procedureDictionary.procedurePointers
            .enumerated()
        {
            var proc = Procedure()
            var segCodeBlock: Data
            var procStartOffset = procPtr
            // if the procStartOffset is negative, this is a reference to the 'extra' part of the PASCALSY
            // segment stored in slot 15, so we need to add the extraCodeOffset to it and read from the
            // extraCode block instead of the main code block.
            if procStartOffset < 0 {
                segCodeBlock = extraCode
                procStartOffset = procStartOffset + extraCodeOffset
            } else {
                segCodeBlock = code
            }

            // Basic validation
            let minNeededIndex = procStartOffset - 8
            let maxNeededIndex = procStartOffset + 1
            if minNeededIndex < 0 || maxNeededIndex >= segCodeBlock.count {
                if verbose {
                    print(
                        "Skipping procedure at index \(procIdx + 1): pointer out of range (addr=\(procStartOffset), code.len=\(segCodeBlock.count))"
                    )
                }
                continue
            }

            var procNumber = 0
            var isAssembler = false
            if procStartOffset >= 0 && procStartOffset < segCodeBlock.count {
                procNumber = Int(segCodeBlock[procStartOffset])
            }

            // if it's assembler, proc# is based on the index alone.
            if procNumber == 0 && seg.machineType == 7 {
                procNumber = procIdx + 1
                isAssembler = true
            }

            // set proc headers for any procedures we already know about
            // this will make it easier to assign their memory locations.
            if let predefinedProc = allProcedures.first(where: {
                $0.segment == seg.segNum && $0.procedure == procNumber
            }) {
                proc.identifier = predefinedProc
            }

            if isAssembler && seg.machineType == 7 {
                let procedureBounds = assemblerProcedureBoundsByIndex[procIdx]
                if let bounds = procedureBounds {
                    proc.segmentStartAddress = bounds.lowerBound
                    proc.segmentEndAddress = bounds.upperBound
                }
                try? decodeAssemblerProcedure(
                    segmentNumber: seg.segNum,
                    procedureNumber: procNumber,
                    proc: &proc,
                    code: segCodeBlock,
                    addr: procStartOffset,
                    assemblerEntryPoints: &asmEntryPoints,
                    procedureBounds: procedureBounds
                )
                if proc.segmentEndAddress == nil {
                    proc.segmentEndAddress = procStartOffset + 2
                }
            } else {
                decodePascalProcedure(
                    currSeg: seg,
                    procedureNumber: procNumber,
                    proc: &proc,
                    code: segCodeBlock,
                    addr: procStartOffset,
                    callers: &tempCallers,
                    allLocations: &allLocations,
                    allProcedures: &allProcedures
                )
            }

            registerProcedureIdentifier(proc, in: &allProcedures)

            codeSeg.procedures.append(proc)
            allCallers.formUnion(tempCallers)
        }

        if seg.machineType == 7 {
            resolveAssemblerProcedureTargets(
                in: codeSeg,
                allProcedures: &allProcedures,
                allCallers: &allCallers
            )
        }

        allCodeSegs[Int(seg.segNum)] = codeSeg
    }

    // Amend relative memory locations in instructions by lex level (which we
    // can't do until all procedures are decoded and we know the procedure calling hierarchy)
    for (_, codeSeg) in allCodeSegs {
        for proc in codeSeg.procedures {
            if let pt = proc.identifier {
                allCallers.forEach { call in
                    if call.target.segment == pt.segment
                        && call.target.procedure == pt.procedure
                        && call.target.lexLevel == nil
                    {
                        allCallers.remove(call)
                        call.target.lexLevel = proc.lexicalLevel
                        allCallers.insert(call)
                    }
                    if call.origin.segment == pt.segment
                        && call.origin.procedure == pt.procedure
                        && call.origin.lexLevel == nil
                    {
                        allCallers.remove(call)
                        call.origin.lexLevel = proc.lexicalLevel
                        allCallers.insert(call)
                    }
                }
            }
        }
    }

    // And now we can resolve any missing procedure values.
    for (_, codeSeg) in allCodeSegs {
        for proc in codeSeg.procedures {
            normaliseMemoryLocations(proc, allCallers)
            let missingLex = allLocations.filter({ $0.isParam == false &&
                $0.lexLevel == nil && $0.segment == proc.identifier?.segment
                    && $0.procedure == proc.identifier?.procedure
            })
            missingLex.forEach { loc in
                allLocations.remove(loc)
                let updatedLoc = loc
                updatedLoc.lexLevel = proc.lexicalLevel
                allLocations.insert(updatedLoc)
            }
        }
    }

    // Now we can update memory locations that correspond to procedure/function parameters and returns.
    for (_, codeSeg) in allCodeSegs {
        for proc in codeSeg.procedures {
            if let pt = proc.identifier {
                var paramAddr = 1

                // if it's a function, set locations 1 (and 2 for reals) to retval

                if pt.isFunction == true {
                    if let ret = allLocations.first(where: {
                        $0.segment == pt.segment && $0.procedure == pt.procedure
                            && $0.addr == 1
                    }) {
                        ret.name = pt.procName ?? pt.shortDescription
                        ret.type = pt.returnType ?? "UNKNOWN"
                        ret.isParam = true
                        allLocations.update(with: ret)
                    } else {
                        allLocations.insert(
                            Location(
                                segment: pt.segment,
                                procedure: pt.procedure,
                                lexLevel: proc.lexicalLevel,
                                addr: 1,
                                isParam: true,
                                name: pt.procName ?? pt.shortDescription,
                                type: pt.returnType ?? "UNKNOWN"
                            )
                        )
                    }
                    if proc.identifier?.returnType == "REAL" {
                        if let ret = allLocations.first(where: {
                            $0.segment == pt.segment
                                && $0.procedure == pt.procedure
                                && $0.addr == 2
                        }) {
                            ret.name = pt.procName ?? pt.shortDescription
                            ret.type = pt.returnType ?? "REAL"
                            ret.isParam = true
                            allLocations.update(with: ret)
                        } else {
                            allLocations.insert(
                                Location(
                                    segment: pt.segment,
                                    procedure: pt.procedure,
                                    lexLevel: proc.lexicalLevel,
                                    addr: 2,
                                    isParam: true,
                                    name: pt.procName ?? pt.shortDescription,
                                    type: pt.returnType ?? "REAL"
                                )
                            )
                        }
                    }
                    paramAddr = 3
                }
                for param in pt.parameters.reversed() {
                    if let par = allLocations.first(where: {
                        $0.segment == pt.segment && $0.procedure == pt.procedure
                            && $0.addr == paramAddr
                    }) {
                        par.name = param.name
                        par.type = param.type
                        par.isParam = true
                        allLocations.update(with: par)
                    } else {
                        allLocations.insert(
                            Location(
                                segment: pt.segment,
                                procedure: pt.procedure,
                                lexLevel: proc.lexicalLevel,
                                addr: paramAddr,
                                isParam: true,
                                name: param.name,
                                type: param.type
                            )
                        )
                    }
                    paramAddr += 1
                }
            }
        }
    }

    // Do stack simulation and pseudocode generation
    // once we have all procedures decoded.
    // As the stack plays a role in control flow, we need to handle them at the same time.
    for (_, codeSeg) in allCodeSegs {
        for proc in codeSeg.procedures {
            if proc.identifier?.isAssembly == true {
                // skip assembly procedures
                continue
            }
            simulateStackAndGeneratePseudocode(
                proc: proc,
                knownRecords: knownRecords,
                allProcedures: &allProcedures,
                allLocations: &allLocations
            )
        }
    }

    let result = DisassemblyResult(
        sourceFilename: fileIdentifier,
        segDictionary: segDict,
        codeSegments: allCodeSegs,
        dataSegments: dataSegments,
        allLocations: allLocations,
        allProcedures: allProcedures,
        allCallers: allCallers
    )

    exportKnownRecords(
        toJson: sysRecordsFile,
        from: knownRecords.filter { $0.isSystemRecord == true },
        appSupportDirectory: appSupportDirectory
    )

    exportKnownRecords(
        toJson: allRecordsFile,
        from: knownRecords.filter { $0.isSystemRecord == false },
        appSupportDirectory: appSupportDirectory
    )

    exportLabels(
        toCSV: allLabelsCSVFile,
        from: allLocations.filter { $0.segment != 0 && $0.addr != nil && $0.isParam == false }.sorted { $0 < $1 },
        overwrite: rewrite,
        appSupportDirectory: appSupportDirectory
    )
    exportLabels(
        toCSV: sysLabelsCSVFile,
        from: allLocations.filter { $0.segment == 0 && $0.addr != nil && $0.isParam == false }.sorted { $0 < $1 },
        overwrite: rewrite,
        appSupportDirectory: appSupportDirectory
    )

    exportProcedures(
        toCSV: allProceduresCSVFile,
        from: allProcedures.filter { $0.segment != 0 },
        overwrite: rewrite,
        appSupportDirectory: appSupportDirectory
    )
    exportProcedures(
        toCSV: sysProceduresCSVFile,
        from: allProcedures.filter { $0.segment == 0 },
        overwrite: rewrite,
        appSupportDirectory: appSupportDirectory
    )

    return result
}

/// Render a ``DisassemblyResult`` to a String using the shared output logic.
public func renderDisassembly(
    _ result: DisassemblyResult,
    showMarkup: Bool = true,
    showPCode: Bool = true,
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
        verbose: verbose,
        showMarkup: showMarkup,
        showPCode: showPCode,
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
    showPseudoCode: Bool = false,
    showDot: Bool = false
) throws {
    let result = try disassemble(
        filename: filename,
        verbose: verbose,
        rewrite: rewrite
    )

    outputResults(
        sourceFilename: result.sourceFilename,
        segDictionary: result.segDictionary,
        codeSegs: result.codeSegments,
        dataSegs: result.dataSegments,
        allLocations: result.allLocations,
        allProcedures: result.allProcedures,
        allCallers: result.allCallers,
        verbose: verbose,
        showMarkup: showMarkup,
        showPCode: showPCode,
        showPseudoCode: showPseudoCode,
        showDot: showDot
    )
}
