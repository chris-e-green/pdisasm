//
//  WDC6502.swift
//  PascalDisassembler
//
//  Created by Christopher Green on 27/9/2025.
//

import Foundation

private struct AssemblerFooterInfo {
    let footerBytes: Int
    let baseRelocs: Set<Int>
    let segRelocs: Set<Int>
    let procRelocs: Set<Int>
    let interpRelocs: Set<Int>
}

private func parseAssemblerFooter(
    codeData: CodeData,
    addr: Int,
//    segmentNumber: Int,
//    procedureNumber: Int
) throws -> AssemblerFooterInfo {
    // Bytes trailing code body before relocation tables: enterIC self-ref (2) + proc/lex header (2).
    var footerBytes = 4

    var baseRelocs: Set<Int> = []
    let baseCount = Int(try codeData.readWord(at: addr - footerBytes))
    footerBytes += 2
    for _ in 0..<baseCount {
        baseRelocs.insert(try codeData.getSelfRefPointer(at: addr - footerBytes))
        footerBytes += 2
    }

    var segRelocs: Set<Int> = []
    let segRelocCount = Int(try codeData.readWord(at: addr - footerBytes))
    footerBytes += 2
    for _ in 0..<segRelocCount {
        segRelocs.insert(try codeData.getSelfRefPointer(at: addr - footerBytes))
        footerBytes += 2
    }

    var procRelocs: Set<Int> = []
    let procRelocCount = Int(try codeData.readWord(at: addr - footerBytes))
    footerBytes += 2
    for _ in 0..<procRelocCount {
        procRelocs.insert(try codeData.getSelfRefPointer(at: addr - footerBytes))
        footerBytes += 2
    }

    var interpRelocs: Set<Int> = []
    let interpRelocCount = Int(try codeData.readWord(at: addr - footerBytes))
    footerBytes += 2
    for _ in 0..<interpRelocCount {
        interpRelocs.insert(try codeData.getSelfRefPointer(at: addr - footerBytes))
        footerBytes += 2
    }

    footerBytes -= 2 // The final count word is not followed by relocation entries, so subtract its bytes from the total.
    
    return AssemblerFooterInfo(
        footerBytes: footerBytes,
        baseRelocs: baseRelocs,
        segRelocs: segRelocs,
        procRelocs: procRelocs,
        interpRelocs: interpRelocs
    )
}

private func isWdc6502BranchOpcode(_ opcode: UInt8) -> Bool {
    // all 6502 branch opcodes have the form XXX10000, so we check that bits 0-3 are 0 and bit 4 is 1
    return (opcode & 0x1F) == 0x10
}

private func complementaryWdc6502BranchOpcode(for opcode: UInt8) -> UInt8 {
    // all 6502 branch opcodes have the form XXX10000, and complementary branches differ in bit 5, so we can flip bit 5 to get the complement
    return opcode ^ 0x20
}

private func decodeAssemblerCodeInstruction(
    opcodeByte: UInt8,
    codeData: CodeData,
    codeEnd: Int,
    proc: Procedure,
    procRelocs: Set<Int>,
    assemblerEntryPoints: inout Set<Int>,
    instructionPointer: inout Int,
    inCode: inout Bool,
    procedureBounds: Range<Int>? = nil,
    isComplementaryBranch: Bool = false
) throws {
    if let opcode = wdc6502[opcodeByte] {
        func trackLocalEntryPointIfInBounds(_ address: Int) {
            guard address >= 0 && address < codeEnd else { return }
            if let bounds = procedureBounds {
                if bounds.contains(address) {
                    proc.entryPoints.insert(address)
                }
            } else {
                proc.entryPoints.insert(address)
            }
        }

        var shouldSwitchToDataMode = false

        func inferIndexedIndirectJumpTableTargets(
            instructionPointer: Int,
            zeroPagePointer: Int
        ) -> [Int] {
            guard zeroPagePointer >= 0 && zeroPagePointer <= 0xff else { return [] }
            let staHighOp = instructionPointer - 2
            let ldaHighOp = instructionPointer - 5
            let staLowOp = instructionPointer - 7
            let ldaLowOp = instructionPointer - 10
            guard ldaLowOp >= 0 else { return [] }

            guard
                let staHighOpcode = try? codeData.readByte(at: staHighOp),
                let staHighZp = try? codeData.readByte(at: staHighOp + 1),
                staHighOpcode == 0x85,
                Int(staHighZp) == zeroPagePointer + 1,
                let ldaHighOpcode = try? codeData.readByte(at: ldaHighOp),
                ldaHighOpcode == 0xbd,
                let rawTableHigh = try? codeData.readWord(at: ldaHighOp + 1),
                let staLowOpcode = try? codeData.readByte(at: staLowOp),
                let staLowZp = try? codeData.readByte(at: staLowOp + 1),
                staLowOpcode == 0x85,
                Int(staLowZp) == zeroPagePointer,
                let ldaLowOpcode = try? codeData.readByte(at: ldaLowOp),
                ldaLowOpcode == 0xbd,
                let rawTableLow = try? codeData.readWord(at: ldaLowOp + 1),
                let tableHigh = Optional(Int(rawTableHigh)
                    + (procRelocs.contains(ldaHighOp + 1) ? proc.enterIC : 0)),
                let tableLow = Optional(Int(rawTableLow)
                    + (procRelocs.contains(ldaLowOp + 1) ? proc.enterIC : 0)),
                tableHigh == tableLow + 1
            else {
                return []
            }

            var inferredTargets: [Int] = []
            var tableAddress = tableLow
            while tableAddress + 1 < codeEnd && procRelocs.contains(tableAddress) {
                if let tableWord = try? codeData.readWord(at: tableAddress) {
                    inferredTargets.append(Int(tableWord) + proc.enterIC)
                }
                tableAddress += 2
            }
            return inferredTargets
        }
        
        if isWdc6502BranchOpcode(opcodeByte) {
            // Check for complementary branch pair directly adjacent (e.g. BCS followed by BCC).
            // We'll decode both branches, then switch to data mode after the complementary instruction.
            let nextInstructionPointer = instructionPointer + 2
            if nextInstructionPointer < codeEnd,
               let nextOpcode = try? codeData.readByte(at: nextInstructionPointer),
               nextOpcode == complementaryWdc6502BranchOpcode(for: opcodeByte)
            {
                shouldSwitchToDataMode = true
            }
        } else if [0x4c, 0x6c, 0x60].contains(opcodeByte) {
            inCode = false
        }
        
        var param = 0
        var machCodeStr = String(format: "%02x", opcodeByte)
        if opcode.paramLength == 1 {
            if isWdc6502BranchOpcode(opcodeByte) {
                let rawOffset = Int(try codeData.readByte(at: instructionPointer + 1))
                var offset = rawOffset
                if offset > 127 { offset -= 256 }
                param = instructionPointer + 2 + offset
                assemblerEntryPoints.insert(param)
                trackLocalEntryPointIfInBounds(param)
                machCodeStr += String(format: " %02x   ", rawOffset)
            } else {
                param = Int(try codeData.readByte(at: instructionPointer + 1))
                machCodeStr += String(format: " %02x   ", param)
            }
        } else if opcode.paramLength == 2 {
            param = Int(try codeData.readWord(at: instructionPointer + 1))
            if procRelocs.contains(instructionPointer + 1) {
                param += proc.enterIC
            }
            if opcodeByte == 0x20 || opcodeByte == 0x4c {
                assemblerEntryPoints.insert(param)
                trackLocalEntryPointIfInBounds(param)
            } else if opcodeByte == 0x6c {
                // Recognize dispatch stubs that assemble a zero-page pointer from
                // a relocated table indexed by X and then jump via JMP (zp).
                let inferredTargets = inferIndexedIndirectJumpTableTargets(
                    instructionPointer: instructionPointer,
                    zeroPagePointer: param
                )
                for target in inferredTargets {
                    assemblerEntryPoints.insert(target)
                    trackLocalEntryPointIfInBounds(target)
                }
            }
            machCodeStr += String(format: " %04x ", param)
        } else {
            machCodeStr += "      "
        }
        let resolvedParams: [Int] = (opcodeByte == 0x20 || opcodeByte == 0x4c) ? [param] : []
        proc.instructions[instructionPointer] = Instruction(
            opcode: opcodeByte,
            mnemonic: machCodeStr + String(format: opcode.mnemonic, param),
            params: resolvedParams,
            comment: isComplementaryBranch ? "always taken" : nil,
            isPascal: false,
            stackState: []
        )
        instructionPointer += 1
        if procRelocs.contains(instructionPointer) && opcode.paramLength > 0 {
            proc.instructions[instructionPointer - 1]?.comment = " <- proc relocated"
        }
        instructionPointer += opcode.paramLength
        
        // If this is a branch that has a complementary branch following it,
        // decode the complementary branch instruction and then switch to data mode.
        if shouldSwitchToDataMode && instructionPointer < codeEnd {
            let complementaryOpcode = try codeData.readByte(at: instructionPointer)
            try decodeAssemblerCodeInstruction(
                opcodeByte: complementaryOpcode,
                codeData: codeData,
                codeEnd: codeEnd,
                proc: proc,
                procRelocs: procRelocs,
                assemblerEntryPoints: &assemblerEntryPoints,
                instructionPointer: &instructionPointer,
                inCode: &inCode,
                procedureBounds: procedureBounds,
                isComplementaryBranch: true
            )
            inCode = false
        }
    } else {
        proc.instructions[instructionPointer] = Instruction(
            opcode: opcodeByte,
            mnemonic: String(format: "???     %02x", opcodeByte),
            isPascal: false,
            stackState: []
        )
        instructionPointer += 1
    }
}

private func processAssemblerDataRegion(
    opcodeByte: UInt8,
    codeData: CodeData,
    code: Data,
    codeEnd: Int,
    proc: Procedure,
    procRelocs: Set<Int>,
    assemblerEntryPoints: Set<Int>,
    instructionPointer: inout Int,
    inCode: inout Bool
) throws {
    func emitDataInstruction(start: Int, end: Int, bytes: String, ascii: String) {
        proc.instructions[start] = Instruction(
            opcode: opcodeByte,
            mnemonic: bytes + String(repeating: " ", count: max(0, 50 - bytes.count)) + " | " + ascii,
            params: [start, end],
            isPascal: false,
            stackState: []
        )
    }

    var dataChunkStart = instructionPointer

    // Pre-pad the first (possibly partial) row so that byte columns align on
    // the 16-byte grid regardless of where the data block starts.
    let startOffset = dataChunkStart % 16
    let slotsBeforeSep = min(startOffset, 8)
    let slotsAfterSep  = startOffset > 8 ? startOffset - 8 : 0
    var bytesString = String(repeating: "   ", count: slotsBeforeSep)
        + (startOffset >= 8 ? " -" : "")
        + String(repeating: "   ", count: slotsAfterSep)
    var asciiString = String(repeating: " ", count: slotsBeforeSep)
        + (startOffset >= 8 ? " " : "")
        + String(repeating: " ", count: slotsAfterSep)

    while instructionPointer < codeEnd && !inCode {
        if instructionPointer.isMultiple(of: 16) && !bytesString.isEmpty {
            emitDataInstruction(
                start: dataChunkStart,
                end: instructionPointer,
                bytes: bytesString,
                ascii: asciiString
            )
            bytesString = ""
            asciiString = ""
            dataChunkStart = instructionPointer
        } else if instructionPointer.isMultiple(of: 8) && !bytesString.isEmpty
                    && instructionPointer != dataChunkStart {
            // Add mid-row separator when transitioning from the lower to upper
            // half of a 16-byte row. Guard against the first byte of a chunk
            // that starts exactly at column 8, which was already pre-padded.
            bytesString += " -"
            asciiString += " "
        }

        if procRelocs.contains(instructionPointer) {
            bytesString += String(
                format: " *%04x",
                Int(try codeData.readWord(at: instructionPointer)) + proc.enterIC
            )
            asciiString += "  "
            instructionPointer += 2
        } else {
            bytesString += String(format: " %02x", code[instructionPointer])
            if code[instructionPointer] >= 0x20 && code[instructionPointer] <= 0x7e {
                asciiString.append(Character(UnicodeScalar(code[instructionPointer])))
            } else {
                asciiString.append(Character("."))
            }
            instructionPointer += 1
        }

        if assemblerEntryPoints.contains(instructionPointer) {
            inCode = true
        }
    }

    if !bytesString.isEmpty {
        emitDataInstruction(
            start: dataChunkStart,
            end: instructionPointer,
            bytes: bytesString,
            ascii: asciiString
        )
    }
}

func decodeAssemblerProcedure(
    segmentNumber: Int,
    segmentName: String? = nil,
    procedureNumber: Int,
    proc: inout Procedure,
    code: Data,
    addr: Int,
    assemblerEntryPoints: inout Set<Int>,
    procedureBounds: Range<Int>? = nil,
    cancellation: CancellationToken? = nil
) throws {

    func isAssemblerDataInstruction(_ instruction: Instruction) -> Bool {
        instruction.mnemonic.contains(" | ")
    }

    func assemblerDataRange(_ instruction: Instruction, at offset: Int) -> Range<Int>? {
        guard isAssemblerDataInstruction(instruction) else { return nil }
        if instruction.params.count == 2, instruction.params[0] < instruction.params[1] {
            return instruction.params[0]..<instruction.params[1]
        }
        return offset..<min(offset + 16, code.count)
    }

    func assemblerCodeRange(_ instruction: Instruction, at offset: Int) -> Range<Int>? {
        guard instruction.isPascal == false, !isAssemblerDataInstruction(instruction) else {
            return nil
        }
        let length = (wdc6502[instruction.opcode]?.paramLength ?? 0) + 1
        return offset..<min(offset + length, code.count)
    }

    func rangesOverlap(_ lhs: Range<Int>, _ rhs: Range<Int>) -> Bool {
        lhs.lowerBound < rhs.upperBound && rhs.lowerBound < lhs.upperBound
    }

    func removeAssemblerDataOverlappingCode() {
        let codeRanges = proc.instructions.compactMap { offset, instruction in
            assemblerCodeRange(instruction, at: offset)
        }
        guard !codeRanges.isEmpty else { return }

        for (offset, instruction) in proc.instructions {
            guard let dataRange = assemblerDataRange(instruction, at: offset),
                  codeRanges.contains(where: { rangesOverlap(dataRange, $0) })
            else {
                continue
            }
            proc.instructions.removeValue(forKey: offset)
        }
    }

    if let existingIdentifier = proc.identifier {
        // Preserve metadata-provided function/procedure classification.
        existingIdentifier.isAssembly = true
        existingIdentifier.segment = segmentNumber
        if existingIdentifier.segmentName?.isEmpty != false {
            existingIdentifier.segmentName = segmentName
        }
        existingIdentifier.procedure = procedureNumber
        proc.identifier = existingIdentifier
    } else {
        proc.identifier = ProcedureIdentifier(
            isFunction: false,
            isAssembly: true,
            segment: segmentNumber,
            segmentName: segmentName,
            procedure: procedureNumber
        )
    }

    let cd = CodeData(data: code, instructionPointer: 0, header: 0)
    proc.enterIC = try cd.getSelfRefPointer(at: addr - 2)
    // the enterIC is always an entry point.
    assemblerEntryPoints.insert(proc.enterIC)
    proc.entryPoints.insert(proc.enterIC)

    let footerInfo = try parseAssemblerFooter(
        codeData: cd,
        addr: addr,
//        segmentNumber: segmentNumber,
//        procedureNumber: procedureNumber
    )

    func codeEndIndex(footerBytes: Int) -> Int {
        // `addr` points at procNumber; subtracting footer bytes yields the first byte after code.
        addr - footerBytes
    }

    let procRelocs = footerInfo.procRelocs
    let codeEnd = codeEndIndex(footerBytes: footerInfo.footerBytes)
    let localProcedureBounds = procedureBounds ?? (0..<codeEnd)
    proc.segmentStartAddress = localProcedureBounds.lowerBound
    proc.segmentEndAddress = localProcedureBounds.upperBound

    var instructionPointer = proc.enterIC
    guard instructionPointer >= 0 && instructionPointer < codeEnd else { return }
    var op = try cd.readByte(at: instructionPointer)

    // start out being 'in-code'
    var inCode = true
    repeat {
        try cancellation?.checkCancellation()
        if instructionPointer >= codeEnd { break }
        try decodeAssemblerCodeInstruction(
            opcodeByte: op,
            codeData: cd,
            codeEnd: codeEnd,
            proc: proc,
            procRelocs: procRelocs,
            assemblerEntryPoints: &assemblerEntryPoints,
            instructionPointer: &instructionPointer,
            inCode: &inCode,
            procedureBounds: localProcedureBounds
        )
        if !inCode && assemblerEntryPoints.contains(instructionPointer) {
            inCode = true
        }
        if !inCode {
            try processAssemblerDataRegion(
                opcodeByte: op,
                codeData: cd,
                code: code,
                codeEnd: codeEnd,
                proc: proc,
                procRelocs: procRelocs,
                assemblerEntryPoints: assemblerEntryPoints,
                instructionPointer: &instructionPointer,
                inCode: &inCode
            )
        }
        if instructionPointer >= codeEnd { break }
        op = code[instructionPointer]
    } while instructionPointer < codeEnd

    // Backward-entry fix: revisit unresolved entry points anywhere inside this
    // procedure's own address bounds.
    func isUnresolvedEntryPoint(_ address: Int) -> Bool {
        guard localProcedureBounds.contains(address) else { return false }
        guard let existing = proc.instructions[address] else { return true }
        return isAssemblerDataInstruction(existing)
    }

    var pendingBackwardEntryPoints = Set(proc.entryPoints.filter { isUnresolvedEntryPoint($0) })
    var decodedBackwardEntryPoints: Set<Int> = []

    while let entryPoint = pendingBackwardEntryPoints.sorted().first {
        try cancellation?.checkCancellation()
        pendingBackwardEntryPoints.remove(entryPoint)
        if decodedBackwardEntryPoints.contains(entryPoint) { continue }
        decodedBackwardEntryPoints.insert(entryPoint)

        // If this entry point lands inside an emitted data line, drop overlapping
        // data starts so code decode can proceed from the actual entry point.
        for (offset, instruction) in proc.instructions
        where assemblerDataRange(instruction, at: offset)?.contains(entryPoint) == true
        {
            proc.instructions.removeValue(forKey: offset)
        }

        var backwardInstructionPointer = entryPoint
        var backwardInCode = true
        while backwardInstructionPointer < codeEnd && backwardInCode {
            try cancellation?.checkCancellation()
            if let existing = proc.instructions[backwardInstructionPointer] {
                if isAssemblerDataInstruction(existing) {
                    proc.instructions.removeValue(forKey: backwardInstructionPointer)
                } else {
                    break
                }
            }
            let backwardOp = try cd.readByte(at: backwardInstructionPointer)
            try decodeAssemblerCodeInstruction(
                opcodeByte: backwardOp,
                codeData: cd,
                codeEnd: codeEnd,
                proc: proc,
                procRelocs: procRelocs,
                assemblerEntryPoints: &assemblerEntryPoints,
                instructionPointer: &backwardInstructionPointer,
                inCode: &backwardInCode,
                procedureBounds: localProcedureBounds
            )

            for discoveredEntryPoint in proc.entryPoints where isUnresolvedEntryPoint(discoveredEntryPoint)
                && !decodedBackwardEntryPoints.contains(discoveredEntryPoint)
            {
                pendingBackwardEntryPoints.insert(discoveredEntryPoint)
            }
        }
    }

    removeAssemblerDataOverlappingCode()
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

    // Process all procedures (not just assembler) to find cross-procedure calls.
    // Pascal procedures can have inline assembler or call into assembler routines.
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
                targetProcedure.entryPoints.insert(targetAddress)
                targetProcedure.externalEntryPoints.insert(targetAddress)

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
