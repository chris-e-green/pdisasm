//
//  WDC6502.swift
//  PascalDisassembler
//
//  Created by Christopher Green on 27/9/2025.
//

import Foundation

struct WDC6502OpInfo {
    var mnemonic: String
    var paramLength: Int
}

let wdc6502: [UInt8: WDC6502OpInfo] = [
    0x00: WDC6502OpInfo(mnemonic: "BRK", paramLength: 0),
    0x01: WDC6502OpInfo(mnemonic: "ORA ($%02x,X)", paramLength: 1),
    0x05: WDC6502OpInfo(mnemonic: "ORA $%02x", paramLength: 1),
    0x06: WDC6502OpInfo(mnemonic: "ASL $%02x", paramLength: 1),
    0x08: WDC6502OpInfo(mnemonic: "PHP", paramLength: 0),
    0x09: WDC6502OpInfo(mnemonic: "ORA #$%02x", paramLength: 1),
    0x0a: WDC6502OpInfo(mnemonic: "ASL A", paramLength: 0),
    0x0d: WDC6502OpInfo(mnemonic: "ORA $%04x", paramLength: 2),
    0x0e: WDC6502OpInfo(mnemonic: "ASL $%04x", paramLength: 2),

    0x10: WDC6502OpInfo(mnemonic: "BPL $%04x", paramLength: 1),
    0x11: WDC6502OpInfo(mnemonic: "ORA ($%02x),Y", paramLength: 1),
    0x15: WDC6502OpInfo(mnemonic: "ORA $%02x,X", paramLength: 1),
    0x16: WDC6502OpInfo(mnemonic: "ASL $%02x,X", paramLength: 1),
    0x18: WDC6502OpInfo(mnemonic: "CLC", paramLength: 0),
    0x19: WDC6502OpInfo(mnemonic: "ORA $%04x,Y", paramLength: 2),
    0x1d: WDC6502OpInfo(mnemonic: "ORA $%04x,X", paramLength: 2),
    0x1e: WDC6502OpInfo(mnemonic: "ASL $%04x,X", paramLength: 2),

    0x20: WDC6502OpInfo(mnemonic: "JSR $%04x", paramLength: 2),
    0x21: WDC6502OpInfo(mnemonic: "AND ($%02x,X)", paramLength: 1),
    0x24: WDC6502OpInfo(mnemonic: "BIT $%02x", paramLength: 1),
    0x25: WDC6502OpInfo(mnemonic: "AND $%02x", paramLength: 1),
    0x26: WDC6502OpInfo(mnemonic: "ROL $%02x", paramLength: 1),
    0x28: WDC6502OpInfo(mnemonic: "PLP", paramLength: 0),
    0x29: WDC6502OpInfo(mnemonic: "AND #$%02x", paramLength: 1),
    0x2a: WDC6502OpInfo(mnemonic: "ROL A", paramLength: 0),
    0x2c: WDC6502OpInfo(mnemonic: "BIT $%04x", paramLength: 2),
    0x2d: WDC6502OpInfo(mnemonic: "AND $%04x", paramLength: 2),
    0x2e: WDC6502OpInfo(mnemonic: "ROL $%04x", paramLength: 2),

    0x30: WDC6502OpInfo(mnemonic: "BMI $%04x", paramLength: 1),
    0x31: WDC6502OpInfo(mnemonic: "AND ($%02x),Y", paramLength: 1),
    0x35: WDC6502OpInfo(mnemonic: "AND $%02x,X", paramLength: 1),
    0x36: WDC6502OpInfo(mnemonic: "ROL $%02x,X", paramLength: 1),
    0x38: WDC6502OpInfo(mnemonic: "SEC", paramLength: 0),
    0x39: WDC6502OpInfo(mnemonic: "AND $%04x,Y", paramLength: 2),
    0x3d: WDC6502OpInfo(mnemonic: "AND $%04x,X", paramLength: 2),
    0x3e: WDC6502OpInfo(mnemonic: "ROL $%04x,X", paramLength: 2),

    0x40: WDC6502OpInfo(mnemonic: "RTI", paramLength: 0),
    0x41: WDC6502OpInfo(mnemonic: "EOR ($%02x,X)", paramLength: 1),
    0x45: WDC6502OpInfo(mnemonic: "EOR $%02x", paramLength: 1),
    0x46: WDC6502OpInfo(mnemonic: "LSR $%02x", paramLength: 1),
    0x48: WDC6502OpInfo(mnemonic: "PHA", paramLength: 0),
    0x49: WDC6502OpInfo(mnemonic: "EOR #$%02x", paramLength: 1),
    0x4a: WDC6502OpInfo(mnemonic: "LSR A", paramLength: 0),
    0x4c: WDC6502OpInfo(mnemonic: "JMP $%04x", paramLength: 2),
    0x4d: WDC6502OpInfo(mnemonic: "EOR $%04x", paramLength: 2),
    0x4e: WDC6502OpInfo(mnemonic: "LSR $%04x", paramLength: 2),

    0x50: WDC6502OpInfo(mnemonic: "BVC $%04x", paramLength: 1),
    0x51: WDC6502OpInfo(mnemonic: "EOR ($%02x),Y", paramLength: 1),
    0x55: WDC6502OpInfo(mnemonic: "EOR $%02x,X", paramLength: 1),
    0x56: WDC6502OpInfo(mnemonic: "LSR $%02x,X", paramLength: 1),
    0x58: WDC6502OpInfo(mnemonic: "CLI", paramLength: 0),
    0x59: WDC6502OpInfo(mnemonic: "EOR $%04x,Y", paramLength: 2),
    0x5d: WDC6502OpInfo(mnemonic: "EOR $%04x,X", paramLength: 2),
    0x5e: WDC6502OpInfo(mnemonic: "LSR $%04x,X", paramLength: 2),

    0x60: WDC6502OpInfo(mnemonic: "RTS", paramLength: 0),
    0x61: WDC6502OpInfo(mnemonic: "ADC ($%02x,X)", paramLength: 1),
    0x65: WDC6502OpInfo(mnemonic: "ADC $%02x", paramLength: 1),
    0x66: WDC6502OpInfo(mnemonic: "ROR $%02x", paramLength: 1),
    0x68: WDC6502OpInfo(mnemonic: "PLA", paramLength: 0),
    0x69: WDC6502OpInfo(mnemonic: "ADC #$%02x", paramLength: 1),
    0x6a: WDC6502OpInfo(mnemonic: "ROR A", paramLength: 0),
    0x6c: WDC6502OpInfo(mnemonic: "JMP ($%04x)", paramLength: 2),
    0x6d: WDC6502OpInfo(mnemonic: "ADC $%04x", paramLength: 2),
    0x6e: WDC6502OpInfo(mnemonic: "ROR $%04x", paramLength: 2),

    0x70: WDC6502OpInfo(mnemonic: "BVS $%04x", paramLength: 1),
    0x71: WDC6502OpInfo(mnemonic: "ADC ($%02x),Y", paramLength: 1),
    0x75: WDC6502OpInfo(mnemonic: "ADC $%02x,X", paramLength: 1),
    0x76: WDC6502OpInfo(mnemonic: "ROR $%02x,X", paramLength: 1),
    0x78: WDC6502OpInfo(mnemonic: "SEI", paramLength: 0),
    0x79: WDC6502OpInfo(mnemonic: "ADC $%02x,Y", paramLength: 1),
    0x7d: WDC6502OpInfo(mnemonic: "ADC $%04x,X", paramLength: 2),
    0x7e: WDC6502OpInfo(mnemonic: "ROR $%04x,X", paramLength: 2),

    0x81: WDC6502OpInfo(mnemonic: "STA ($%02x,X)", paramLength: 1),
    0x84: WDC6502OpInfo(mnemonic: "STY $%02x", paramLength: 1),
    0x85: WDC6502OpInfo(mnemonic: "STA $%02x", paramLength: 1),
    0x86: WDC6502OpInfo(mnemonic: "STX $%02x", paramLength: 1),
    0x88: WDC6502OpInfo(mnemonic: "DEY", paramLength: 0),
    0x8a: WDC6502OpInfo(mnemonic: "TXA", paramLength: 0),
    0x8c: WDC6502OpInfo(mnemonic: "STY $%04x", paramLength: 2),
    0x8d: WDC6502OpInfo(mnemonic: "STA $%04x", paramLength: 2),
    0x8e: WDC6502OpInfo(mnemonic: "STX $%04x", paramLength: 2),

    0x90: WDC6502OpInfo(mnemonic: "BCC $%04x", paramLength: 1),
    0x91: WDC6502OpInfo(mnemonic: "STA ($%02x),Y", paramLength: 1),
    0x94: WDC6502OpInfo(mnemonic: "STY $%02x,X", paramLength: 1),
    0x95: WDC6502OpInfo(mnemonic: "STA $%02x,X", paramLength: 1),
    0x96: WDC6502OpInfo(mnemonic: "STX $%02x,Y", paramLength: 1),
    0x98: WDC6502OpInfo(mnemonic: "TYA", paramLength: 0),
    0x99: WDC6502OpInfo(mnemonic: "STA $%04x,Y", paramLength: 2),
    0x9a: WDC6502OpInfo(mnemonic: "TXS", paramLength: 0),
    0x9d: WDC6502OpInfo(mnemonic: "STA $%04x,X", paramLength: 2),

    0xa0: WDC6502OpInfo(mnemonic: "LDY #$%02x", paramLength: 1),
    0xa1: WDC6502OpInfo(mnemonic: "LDA ($%02x,X)", paramLength: 1),
    0xa2: WDC6502OpInfo(mnemonic: "LDX #$%02x", paramLength: 1),
    0xa4: WDC6502OpInfo(mnemonic: "LDY $%02x", paramLength: 1),
    0xa5: WDC6502OpInfo(mnemonic: "LDA $%02x", paramLength: 1),
    0xa6: WDC6502OpInfo(mnemonic: "LDX $%02x", paramLength: 1),
    0xa8: WDC6502OpInfo(mnemonic: "TAY", paramLength: 0),
    0xa9: WDC6502OpInfo(mnemonic: "LDA #$%02x", paramLength: 1),
    0xaa: WDC6502OpInfo(mnemonic: "TAX", paramLength: 0),
    0xac: WDC6502OpInfo(mnemonic: "LDY $%04x", paramLength: 2),
    0xad: WDC6502OpInfo(mnemonic: "LDA $%04x", paramLength: 2),
    0xae: WDC6502OpInfo(mnemonic: "LDX $%04x", paramLength: 2),

    0xb0: WDC6502OpInfo(mnemonic: "BCS $%04x", paramLength: 1),
    0xb1: WDC6502OpInfo(mnemonic: "LDA ($%02x),Y", paramLength: 1),
    0xb4: WDC6502OpInfo(mnemonic: "LDY $%02x,X", paramLength: 1),
    0xb5: WDC6502OpInfo(mnemonic: "LDA $%02x,X", paramLength: 1),
    0xb6: WDC6502OpInfo(mnemonic: "LDX $%02x,Y", paramLength: 1),
    0xb8: WDC6502OpInfo(mnemonic: "CLV", paramLength: 0),
    0xb9: WDC6502OpInfo(mnemonic: "LDA $%04x,Y", paramLength: 2),
    0xba: WDC6502OpInfo(mnemonic: "TSX", paramLength: 0),
    0xbc: WDC6502OpInfo(mnemonic: "LDY $%04x,X", paramLength: 2),
    0xbd: WDC6502OpInfo(mnemonic: "LDA $%04x,X", paramLength: 2),
    0xbe: WDC6502OpInfo(mnemonic: "LDX $%04x,Y", paramLength: 2),

    0xc0: WDC6502OpInfo(mnemonic: "CPY #$%02x", paramLength: 1),
    0xc1: WDC6502OpInfo(mnemonic: "CMP ($%02x,X)", paramLength: 1),
    0xc4: WDC6502OpInfo(mnemonic: "CPY $%02x", paramLength: 1),
    0xc5: WDC6502OpInfo(mnemonic: "CMP $%02x", paramLength: 1),
    0xc6: WDC6502OpInfo(mnemonic: "DEC $%02x", paramLength: 1),
    0xc8: WDC6502OpInfo(mnemonic: "INY", paramLength: 0),
    0xc9: WDC6502OpInfo(mnemonic: "CMP #$%02x", paramLength: 1),
    0xca: WDC6502OpInfo(mnemonic: "DEX", paramLength: 0),
    0xcc: WDC6502OpInfo(mnemonic: "CPY $%04x", paramLength: 2),
    0xcd: WDC6502OpInfo(mnemonic: "CMP $%04x", paramLength: 2),
    0xce: WDC6502OpInfo(mnemonic: "DEC $%04x", paramLength: 2),

    0xd0: WDC6502OpInfo(mnemonic: "BNE $%04x", paramLength: 1),
    0xd1: WDC6502OpInfo(mnemonic: "CMP ($%02x),Y", paramLength: 1),
    0xd5: WDC6502OpInfo(mnemonic: "CMP $%02x,X", paramLength: 1),
    0xd6: WDC6502OpInfo(mnemonic: "DEC $%02x,X", paramLength: 1),
    0xd8: WDC6502OpInfo(mnemonic: "CLD", paramLength: 0),
    0xd9: WDC6502OpInfo(mnemonic: "CMP $%04x,Y", paramLength: 2),
    0xdd: WDC6502OpInfo(mnemonic: "CMP $%04x,X", paramLength: 2),
    0xde: WDC6502OpInfo(mnemonic: "DEC $%04x,X", paramLength: 2),

    0xe0: WDC6502OpInfo(mnemonic: "CPX #$%02x", paramLength: 1),
    0xe1: WDC6502OpInfo(mnemonic: "SBC ($%02x,X)", paramLength: 1),
    0xe4: WDC6502OpInfo(mnemonic: "CPX $%02x", paramLength: 1),
    0xe5: WDC6502OpInfo(mnemonic: "SBC $%02x", paramLength: 1),
    0xe6: WDC6502OpInfo(mnemonic: "INC $%02x", paramLength: 1),
    0xe8: WDC6502OpInfo(mnemonic: "INX", paramLength: 0),
    0xe9: WDC6502OpInfo(mnemonic: "SBC #$%02x", paramLength: 1),
    0xea: WDC6502OpInfo(mnemonic: "NOP", paramLength: 0),
    0xec: WDC6502OpInfo(mnemonic: "CPX $%04x", paramLength: 2),
    0xed: WDC6502OpInfo(mnemonic: "SBC $%04x", paramLength: 2),
    0xee: WDC6502OpInfo(mnemonic: "INC $%04x", paramLength: 2),

    0xf0: WDC6502OpInfo(mnemonic: "BEQ $%04x", paramLength: 1),
    0xf1: WDC6502OpInfo(mnemonic: "SBC ($%02x),Y", paramLength: 1),
    0xf5: WDC6502OpInfo(mnemonic: "SBC $%02x,X", paramLength: 1),
    0xf6: WDC6502OpInfo(mnemonic: "INC $%02x,X", paramLength: 1),
    0xf8: WDC6502OpInfo(mnemonic: "SED", paramLength: 0),
    0xf9: WDC6502OpInfo(mnemonic: "SBC $%04x,Y", paramLength: 2),
    0xfd: WDC6502OpInfo(mnemonic: "SBC $%04x,X", paramLength: 2),
    0xfe: WDC6502OpInfo(mnemonic: "INC $%04x,X", paramLength: 2),
]

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
    segmentNumber: Int,
    procedureNumber: Int
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

private let wdc6502BranchOpcodes: [UInt8] = [0x10, 0x30, 0x50, 0x70, 0x90, 0xB0, 0xD0, 0xF0]

private func isWdc6502BranchOpcode(_ opcode: UInt8) -> Bool {
    wdc6502BranchOpcodes.contains(opcode & 0x1F)
}

private func complementaryWdc6502BranchOpcode(for opcode: UInt8) -> UInt8? {
    switch opcode {
    case 0x90: return 0xB0 // BCC <-> BCS
    case 0xB0: return 0x90
    case 0xD0: return 0xF0 // BNE <-> BEQ
    case 0xF0: return 0xD0
    case 0x10: return 0x30 // BPL <-> BMI
    case 0x30: return 0x10
    case 0x50: return 0x70 // BVC <-> BVS
    case 0x70: return 0x50
    default: return nil
    }
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
               let complement = complementaryWdc6502BranchOpcode(for: opcodeByte),
               let nextOpcode = try? codeData.readByte(at: nextInstructionPointer),
               nextOpcode == complement
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
    func emitDataInstruction(start: Int, bytes: String, ascii: String) {
        proc.instructions[start] = Instruction(
            opcode: opcodeByte,
            mnemonic: bytes + String(repeating: " ", count: max(0, 50 - bytes.count)) + " | " + ascii,
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
            emitDataInstruction(start: dataChunkStart, bytes: bytesString, ascii: asciiString)
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
        emitDataInstruction(start: dataChunkStart, bytes: bytesString, ascii: asciiString)
    }
}

func decodeAssemblerProcedure(
    segmentNumber: Int,
    procedureNumber: Int,
    proc: inout Procedure,
    code: Data,
    addr: Int,
    assemblerEntryPoints: inout Set<Int>,
    procedureBounds: Range<Int>? = nil
) throws {

    func isAssemblerDataInstruction(_ instruction: Instruction) -> Bool {
        instruction.mnemonic.contains(" | ")
    }

    if let existingIdentifier = proc.identifier {
        // Preserve metadata-provided function/procedure classification.
        existingIdentifier.isAssembly = true
        existingIdentifier.segment = segmentNumber
        existingIdentifier.procedure = procedureNumber
        proc.identifier = existingIdentifier
    } else {
        proc.identifier = ProcedureIdentifier(
            isFunction: false,
            isAssembly: true,
            segment: segmentNumber,
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
        segmentNumber: segmentNumber,
        procedureNumber: procedureNumber
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
        pendingBackwardEntryPoints.remove(entryPoint)
        if decodedBackwardEntryPoints.contains(entryPoint) { continue }
        decodedBackwardEntryPoints.insert(entryPoint)

        // If this entry point lands inside an emitted data line, drop overlapping
        // data starts so code decode can proceed from the actual entry point.
        for (offset, instruction) in proc.instructions
        where isAssemblerDataInstruction(instruction)
            && offset <= entryPoint && offset + 16 > entryPoint
        {
            proc.instructions.removeValue(forKey: offset)
        }

        var backwardInstructionPointer = entryPoint
        var backwardInCode = true
        while backwardInstructionPointer < codeEnd && backwardInCode {
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
}
