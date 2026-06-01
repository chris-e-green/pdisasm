import Foundation

struct CodeSegmentDecoder {
    let segDict: SegDictionary
    let binaryData: CodeData
    let verbose: Bool
    let diagnostics: DiagnosticCollector?

    func decode(
        allLocations: inout Set<Location>,
        allProcedures: inout [ProcedureIdentifier],
        allCallers: inout Set<Call>,
        dataSegments: inout [Int]
    ) throws -> [Int: CodeSegment] {
        var allCodeSegs: [Int: CodeSegment] = [:]

        for segment in segDict.segTable.sorted(by: { $0.key < $1.key }) {
            let seg = segment.value
            var extraCodeOffset = 0
            let code = binaryData.getCodeBlock(
                at: seg.codeAddress,
                length: seg.codeLength
            )

            if code.count < 2 {
                diagnostics?.warning(
                    "Skipping segment \(seg.name) (segNum=\(seg.segNum)): code block too small (len=\(code.count))"
                )
                continue
            }

            if seg.segmentKind == .dataseg  {
                dataSegments.append(Int(seg.segNum))
                diagnostics?.warning(
                    "Segment \(seg.name) (segNum=\(seg.segNum)): segment kind is .dataseg"
                )
                continue
            }

            let procCount = Int(code[code.endIndex - 1])
            let codeData = CodeData(data: code, instructionPointer: 0, header: 0)

            var extraCode: Data = Data()
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
                continue
            }

            let codeSeg = CodeSegment(
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

            var asmEntryPoints: Set<Int> = []

            for (procIdx, procPtr) in codeSeg.procedureDictionary.procedurePointers
                .enumerated()
            {
                var tempCallers: Set<Call> = []
                var proc = Procedure()
                var segCodeBlock: Data
                var procStartOffset = procPtr
                if procStartOffset < 0 {
                    segCodeBlock = extraCode
                    procStartOffset = procStartOffset + extraCodeOffset
                } else {
                    segCodeBlock = code
                }

                let minNeededIndex = procStartOffset - 8
                let maxNeededIndex = procStartOffset + 1
                if minNeededIndex < 0 || maxNeededIndex >= segCodeBlock.count {
                    diagnostics?.warning(
                        "Skipping procedure at index \(procIdx + 1): pointer out of range (addr=\(procStartOffset), code.len=\(segCodeBlock.count))"
                    )
                    continue
                }

                var procNumber = 0
                var isAssembler = false
                if procStartOffset >= 0 && procStartOffset < segCodeBlock.count {
                    procNumber = Int(segCodeBlock[procStartOffset])
                }

                if procNumber == 0 && seg.machineType == 7 {
                    procNumber = procIdx + 1
                    isAssembler = true
                }

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
                        segmentName: seg.name,
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
                        allProcedures: &allProcedures,
                        verbose: verbose,
                        diagnostics: diagnostics
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

        return allCodeSegs
    }
}
