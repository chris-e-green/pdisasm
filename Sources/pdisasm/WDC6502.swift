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
    0x0A: WDC6502OpInfo(mnemonic: "ASL A", paramLength: 0),
    0x0d: WDC6502OpInfo(mnemonic: "ORA $%04x", paramLength: 2),
    0x0e: WDC6502OpInfo(mnemonic: "ASL $%04x", paramLength: 2),

    0x10: WDC6502OpInfo(mnemonic: "BPL $%02x", paramLength: 1),
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

    0x30: WDC6502OpInfo(mnemonic: "BMI $%02x", paramLength: 1),
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

    0x50: WDC6502OpInfo(mnemonic: "BVC $%02x", paramLength: 1),
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

    0x70: WDC6502OpInfo(mnemonic: "BVS $%02x", paramLength: 1),
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

    0x90: WDC6502OpInfo(mnemonic: "BCC $%02x", paramLength: 1),
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

    0xb0: WDC6502OpInfo(mnemonic: "BCS $%02x", paramLength: 1),
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

    0xd0: WDC6502OpInfo(mnemonic: "BNE $%02x", paramLength: 1),
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

    0xf0: WDC6502OpInfo(mnemonic: "BEQ $%02x", paramLength: 1),
    0xf1: WDC6502OpInfo(mnemonic: "SBC ($%02x),Y", paramLength: 1),
    0xf5: WDC6502OpInfo(mnemonic: "SBC $%02x,X", paramLength: 1),
    0xf6: WDC6502OpInfo(mnemonic: "INC $%02x,X", paramLength: 1),
    0xf8: WDC6502OpInfo(mnemonic: "SED", paramLength: 0),
    0xf9: WDC6502OpInfo(mnemonic: "SBC $%04x,Y", paramLength: 2),
    0xfd: WDC6502OpInfo(mnemonic: "SBC $%04x,X", paramLength: 2),
    0xfe: WDC6502OpInfo(mnemonic: "INC $%04x,X", paramLength: 2),
]

func decodeAssemblerProcedure(
    segmentNumber: Int,
    procedureNumber: Int,
    proc: inout Procedure,
    code: Data,
    addr: Int
) throws {

    proc.identifier = ProcedureIdentifier(
        isFunction: false,
        isAssembly: true,
        segment: segmentNumber,
        procedure: procedureNumber
    )

    let cd = CodeData(data: code, instructionPointer: 0, header: 0)
    proc.enterIC = try cd.getSelfRefPointer(at: addr - 2)
    proc.entryPoints.insert(proc.enterIC)
    var pos = 4

    var baseRelocs: Set<Int> = []
    let baseCount = Int(try cd.readWord(at: addr - pos))
    pos += 2
    for _ in 0..<baseCount {
        baseRelocs.insert(try cd.getSelfRefPointer(at: addr - pos))
        pos += 2
    }
    var segRelocs: Set<Int> = []
    let segRelocCount = Int(try cd.readWord(at: addr - pos))
    pos += 2
    for _ in 0..<segRelocCount {
        segRelocs.insert(try cd.getSelfRefPointer(at: addr - pos))
        pos += 2
    }
    var procRelocs: Set<Int> = []
    let procRelocCount = Int(try cd.readWord(at: addr - pos))
    pos += 2
    for _ in 0..<procRelocCount {
        procRelocs.insert(try cd.getSelfRefPointer(at: addr - pos))
        pos += 2
    }
    var interpRelocs: Set<Int> = []
    let interpRelocCount = Int(try cd.readWord(at: addr - pos))
    for _ in 0..<interpRelocCount {
        interpRelocs.insert(try cd.getSelfRefPointer(at: addr - pos))
        pos += 2
    }
    var instructionPointer = proc.enterIC
    var op = try cd.readByte(at: instructionPointer)
    var done = false
    repeat {
        if let opcode = wdc6502[op] {
            if op == 0x60 || instructionPointer > code.count { done = true }  // RTS is the only guaranteed end of code. If we are past the end of the code, just stop disassembling.
            var param = 0
            var machCodeStr = String(format: "%02x", op)
            if opcode.paramLength == 1 {
                let isBranch = [0x10, 0x30, 0x50, 0x70, 0x90, 0xB0, 0xD0, 0xF0]
                    .contains(op & 0x1F)

                if isBranch {
                    // it's a relative branch of some sort
                    let rawOffset = Int(try cd.readByte(at: instructionPointer + 1))
                    var offset = rawOffset
                    if offset > 127 {
                        offset -= 256
                    }
                    param = instructionPointer + 2 + offset
                    proc.entryPoints.insert(param)
                    machCodeStr += String(format: " %02x   ", rawOffset)
                } else {
                    param = Int(try cd.readByte(at: instructionPointer + 1))
                    machCodeStr += String(format: " %02x   ", param)
                }
            } else if opcode.paramLength == 2 {
                param = Int(try cd.readWord(at: instructionPointer + 1))
                if procRelocs.contains(instructionPointer + 1) {  // adjust for relocation
                    param += proc.enterIC
                }
                if op == 0x20 || op == 0x4c { proc.entryPoints.insert(param) }
                machCodeStr += String(format: " %04x ", param)
            } else {
                machCodeStr += "      "
            }
            proc.instructions[instructionPointer] = Instruction(
                opcode: op,
                mnemonic: machCodeStr + String(format: opcode.mnemonic, param),
                isPascal: false,
                stackState: []
            )
            instructionPointer += 1
            if procRelocs.contains(instructionPointer) && opcode.paramLength > 0 {
                proc.instructions[instructionPointer - 1]?.comment = " <- proc relocated"
            }
            instructionPointer += opcode.paramLength
            if instructionPointer < code.count {
                op = try cd.readByte(at: instructionPointer)
            } else {
                break
            }
        } else {
            proc.instructions[instructionPointer] = Instruction(
                opcode: op,
                mnemonic: String(format: "???     %02x", op),
                isPascal: false,
                stackState: []
            )
            instructionPointer += 1
            if instructionPointer < code.count {
                op = try cd.readByte(at: instructionPointer)
            } else {
                break
            }

        }
        op = code[instructionPointer]
    } while !done

    var s = ""
    var sh = ""
    var i = instructionPointer
    while i < (addr - pos) {
        if i.isMultiple(of: 16) && !s.isEmpty {
            proc.instructions[((i - 1) / 16) * 16] = Instruction(
                opcode: op,
                mnemonic: s + " | " + sh,
                isPascal: false,
                stackState: []
            )
            s = ""
            sh = ""
        } else if i.isMultiple(of: 8) && !s.isEmpty {
            s += " -"
            sh += " "
        }
        if procRelocs.contains(i) {  // adjust for relocation
            s += String(
                format: " *%04x",
                Int(try cd.readWord(at: i)) + proc.enterIC
            )
            sh += "  "
            i += 2
        } else {
            s += String(format: " %02x", code[i])
            if code[i] >= 0x20 && code[i] <= 0x7e {
                sh.append(Character(UnicodeScalar(code[i])))
            } else {
                sh.append(Character("."))
            }
            i += 1
        }
    }
    if !s.isEmpty {
        proc.instructions[((addr - pos - 1) / 16) * 16] = Instruction(
            opcode: op,
            mnemonic: s + String(repeating: " ", count: (48 - s.count)) + " | "
                + sh,
            isPascal: false,
            stackState: []
        )
    }
}
