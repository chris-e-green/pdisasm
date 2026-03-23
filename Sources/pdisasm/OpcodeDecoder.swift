import Foundation

// MARK: - Opcode Decoder

/// Handles decoding of P-code opcodes and extracting instruction parameters
struct OpcodeDecoder {
    let codeData: CodeData

    // MARK: - Trivial single-byte opcode table
    // Opcodes that decode to just a mnemonic and comment with bytesConsumed=1, no params/locations.
    private static let trivialOpcodes: [UInt8: (mnemonic: String, comment: String)] = [
        abi:  ("ABI",  "Absolute value of integer (TOS)"),
        abr:  ("ABR",  "Absolute value of real (TOS)"),
        adi:  ("ADI",  "Add integers (TOS + TOS-1)"),
        adr:  ("ADR",  "Add reals (TOS + TOS-1)"),
        land: ("LAND", "Logical AND (TOS & TOS-1)"),
        dif:  ("DIF",  "Set difference (TOS-1 AND NOT TOS)"),
        dvi:  ("DVI",  "Divide integers (TOS-1 / TOS)"),
        dvr:  ("DVR",  "Divide reals (TOS-1 / TOS)"),
        chk:  ("CHK",  "Check subrange (TOS-1 <= TOS-2 <= TOS)"),
        flo:  ("FLO",  "Float next to TOS (int TOS-1 to real TOS)"),
        flt:  ("FLT",  "Float TOS (int TOS to real TOS)"),
        inn:  ("INN",  "Set membership (TOS-1 in set TOS)"),
        int:  ("INT",  "Set intersection (TOS AND TOS-1)"),
        lor:  ("LOR",  "Logical OR (TOS | TOS-1)"),
        modi: ("MODI", "Modulo integers (TOS-1 % TOS)"),
        mpi:  ("MPI",  "Multiply integers (TOS * TOS-1)"),
        mpr:  ("MPR",  "Multiply reals (TOS * TOS-1)"),
        ngi:  ("NGI",  "Negate integer"),
        ngr:  ("NGR",  "Negate real"),
        lnot: ("LNOT", "Logical NOT (~TOS)"),
        srs:  ("SRS",  "Subrange set [TOS-1..TOS]"),
        sbi:  ("SBI",  "Subtract integers (TOS-1 - TOS)"),
        sbr:  ("SBR",  "Subtract reals (TOS-1 - TOS)"),
        sgs:  ("SGS",  "Build singleton set [TOS]"),
        sqi:  ("SQI",  "Square integer (TOS * TOS)"),
        sqr:  ("SQR",  "Square real (TOS * TOS)"),
        sto:  ("STO",  "Store indirect word (TOS into TOS-1)"),
        ixs:  ("IXS",  "Index string array (check 1<=TOS<=len of str TOS-1)"),
        uni:  ("UNI",  "Set union (TOS OR TOS-1)"),
        ldcn: ("LDCN", "Load constant NIL"),
        ldp:  ("LDP",  "Load packed field (TOS)"),
        stp:  ("STP",  "Store packed field (TOS into TOS-1)"),
        ldb:  ("LDB",  "Load byte at byte ptr TOS-1 + TOS"),
        stb:  ("STB",  "Store byte at TOS to byte ptr TOS-2 + TOS-1"),
        nop:  ("NOP",  "No operation"),
        xit:  ("XIT",  "Exit the operating system"),
        nop2: ("NOP",  "No operation"),
        equi: ("EQUI", "Integer TOS-1 = TOS"),
        geqi: ("GEQI", "Integer TOS-1 >= TOS"),
        grti: ("GRTI", "Integer TOS-1 > TOS"),
        leqi: ("LEQI", "Integer TOS-1 <= TOS"),
        lesi: ("LESI", "Integer TOS-1 < TOS"),
        neqi: ("NEQI", "Integer TOS-1 <> TOS"),
    ]

    struct DecodedInstruction {
        let opcode: UInt8
        let mnemonic: String
        let params: [Int]
        let stringParameter: String?
        let bytesConsumed: Int
        let comment: String?
        let memLocation: Location?
        let destination: Location?
        let requiresComparator: Bool
        let comparatorOffset: Int

        init(
            opcode: UInt8,
            mnemonic: String,
            params: [Int] = [],
            stringParameter: String? = nil,
            bytesConsumed: Int,
            comment: String? = nil,
            memLocation: Location? = nil,
            destination: Location? = nil,
            requiresComparator: Bool = false,
            comparatorOffset: Int = 0
        ) {
            self.opcode = opcode
            self.mnemonic = mnemonic
            self.params = params
            self.stringParameter = stringParameter
            self.bytesConsumed = bytesConsumed
            self.comment = comment
            self.memLocation = memLocation
            self.destination = destination
            self.requiresComparator = requiresComparator
            self.comparatorOffset = comparatorOffset
        }
    }

    func decode(
        opcode: UInt8,
        at ic: Int,
        currSeg: Segment,
        segment: Int,
        procedure: Int,
        proc: Procedure,
        addr: Int
    ) throws
        -> DecodedInstruction
    {
        // Fast path: trivial single-byte opcodes (no params, no locations)
        if let entry = Self.trivialOpcodes[opcode] {
            return DecodedInstruction(
                opcode: opcode,
                mnemonic: entry.mnemonic,
                bytesConsumed: 1,
                comment: entry.comment
            )
        }

        switch opcode {
        case sldc0...sldc127:
            return DecodedInstruction(
                opcode: opcode,
                mnemonic: "SLDC",
                params: [Int(opcode)],
                bytesConsumed: 1,
                comment: "Short load one-word constant \(opcode)"
            )
        case lde:
            let seg = Int(try codeData.readByte(at: ic + 1))
            let (val, inc) = try codeData.readBig(at: ic + 2)
            let loc = Location(
                segment: seg,
                procedure: 0,
                lexLevel: 0,
                addr: val
                )
            return DecodedInstruction(
                opcode: opcode,
                mnemonic: "LDE",
                params: [seg, val],
                bytesConsumed: 2 + inc,
                comment:
                    "Load extended word (word offset \(val) in data seg \(seg))",
                memLocation: loc
            )
        case csp:
            let procNum = Int(try codeData.readByte(at: ic + 1))
            return DecodedInstruction(
                opcode: opcode,
                mnemonic: "CSP",
                params: [procNum],
                bytesConsumed: 2,
                comment:
                    "Call standard procedure \(cspProcs[procNum]?.0 ?? String(procNum))"
            )
        case adj:
            let count = Int(try codeData.readByte(at: ic + 1))
            return DecodedInstruction(
                opcode: opcode,
                mnemonic: "ADJ",
                params: [count],
                bytesConsumed: 2,
                comment: "Adjust set to \(count) words"
            )
        case fjp:
            let offset = Int(try codeData.readByte(at: ic + 1))
            var dest: Int = 0
            if offset > 0x7f {
                let jte = addr + offset - 256
                dest = jte - Int(try codeData.readWord(at: jte))
            } else {
                dest = ic + offset + 2
            }
            return DecodedInstruction(
                opcode: opcode,
                mnemonic: "FJP",
                params: [dest],
                bytesConsumed: 2,
                comment: "Jump if TOS false to \(String(format: "%04x", dest))"
            )
        case inc:
            let (val, inc) = try codeData.readBig(at: ic + 1)
            return DecodedInstruction(
                opcode: opcode,
                mnemonic: "INC",
                params: [val],
                bytesConsumed: 1 + inc,
                comment: "Inc field ptr (TOS+\(val))"
            )
        case ind:
            let (val, inc) = try codeData.readBig(at: ic + 1)
            return DecodedInstruction(
                opcode: opcode,
                mnemonic: "IND",
                params: [val],
                bytesConsumed: 1 + inc,
                comment: "Static index and load word (TOS+\(val))"
            )
        case ixa:
            let (val, inc) = try codeData.readBig(at: ic + 1)
            return DecodedInstruction(
                opcode: opcode,
                mnemonic: "IXA",
                params: [val],
                bytesConsumed: 1 + inc,
                comment: "Index array (TOS-1 + TOS * \(val))"
            )
        case lao:
            let (val, inc) = try codeData.readBig(at: ic + 1)
            let loc = Location(segment: segment, lexLevel: 0, addr: val)
            return DecodedInstruction(
                opcode: opcode,
                mnemonic: "LAO",
                params: [val],
                bytesConsumed: 1 + inc,
                comment: "Load global address",
                memLocation: loc
            )
        case lsa:
            let strLen = Int(try codeData.readByte(at: ic + 1))
            var s: String = ""
            if strLen > 0 {
                for i in 1...strLen {
                    let ch = try codeData.readByte(at: ic + 1 + Int(i))
                    s += String(format: "%c", ch)
                }
            }
            return DecodedInstruction(
                opcode: opcode,
                mnemonic: "LSA",
                params: [strLen],
                stringParameter: s,
                bytesConsumed: 2 + strLen,
                comment: "Load string address: '" + s + "'"
            )
        case lae:
            let seg = Int(try codeData.readByte(at: ic + 1))
            let (val, inc) = try codeData.readBig(at: ic + 2)
            let loc = Location(
                segment: seg,
                procedure: 0,
                lexLevel: 0,
                addr: val
            )
            return DecodedInstruction(
                opcode: opcode,
                mnemonic: "LAE",
                params: [seg, val],
                bytesConsumed: 2 + inc,
                comment: "Load extended address",
                memLocation: loc
            )
        case mov:
            // MOV
            let (val, inc) = try codeData.readBig(at: ic + 1)
            return DecodedInstruction(
                opcode: opcode,
                mnemonic: "MOV",
                params: [val],
                bytesConsumed: 1 + inc,
                comment: "Move \(val) words (TOS to TOS-1)"
            )
        case ldo:
            // LDO
            let (val, inc) = try codeData.readBig(at: ic + 1)
            let loc = Location(segment: segment, lexLevel: 0, addr: val)
            return DecodedInstruction(
                opcode: opcode,
                mnemonic: "LDO",
                params: [val],
                bytesConsumed: 1 + inc,
                comment: "Load global word",
                memLocation: loc
            )
        case sas:
            // SAS
            let sasCount = Int(try codeData.readByte(at: ic + 1))
            return DecodedInstruction(
                opcode: opcode,
                mnemonic: "SAS",
                params: [sasCount],
                bytesConsumed: 2,
                comment: "String assign (TOS to TOS-1, \(sasCount) chars)"
            )
        case sro:
            // SRO
            let (val, inc) = try codeData.readBig(at: ic + 1)
            let loc = Location(segment: segment, lexLevel: 0, addr: val)
            return DecodedInstruction(
                opcode: opcode,
                mnemonic: "SRO",
                params: [val],
                bytesConsumed: 1 + inc,
                comment: "Store global word",
                memLocation: loc
            )
        case xjp:
            // Case jump
            var tempIC = ic + 1
            var tempParams: [Int] = []
            if tempIC % 2 != 0 { tempIC += 1 }
            let first = Int(try codeData.readInt(at: tempIC))
            tempParams.append(first)
            tempIC += 2
            let last = Int(try codeData.readInt(at: tempIC))
            tempParams.append(last)
            tempIC += 2
            tempParams.append(tempIC)

            var dest: Int = 0
            let offset = Int(try codeData.readByte(at: tempIC + 1))
            if offset > 0x7f {
                let jte = addr + offset - 256
                dest = jte - Int(try codeData.readWord(at: jte))
            } else {
                dest = tempIC + offset + 2
            }
            tempParams.append(dest)
            tempIC += 2
            if first > last {
                print(
                    "Warning: XJP first (\(first)) is greater than last (\(last))"
                )
                exit(1)
            }
            for _ in first...last {
                let caseDest = try codeData.getSelfRefPointer(at: tempIC)
                tempParams.append(caseDest)
                tempIC += 2
            }
            return DecodedInstruction(
                opcode: opcode,
                mnemonic: "XJP",
                params: tempParams,
                bytesConsumed: tempIC - ic,
                comment: "Case jump"
            )
        case rnp:
            // RNP
            let retCount = Int(try codeData.readByte(at: ic + 1))
            return DecodedInstruction(
                opcode: opcode,
                mnemonic: "RNP",
                params: [retCount],
                bytesConsumed: 2,
                comment: "Return from nonbase procedure"
            )
        case cip:
            // CIP
            let procNum = Int(try codeData.readByte(at: ic + 1))
            let loc = Location(segment: currSeg.segNum, procedure: procNum)
            return DecodedInstruction(
                opcode: opcode,
                mnemonic: "CIP",
                params: [procNum],
                bytesConsumed: 2,
                comment: "Call intermediate procedure",
                destination: loc
            )
        case eql:
            // EQL
            return DecodedInstruction(
                opcode: opcode,
                mnemonic: "EQL",
                bytesConsumed: 0,
                requiresComparator: true,
                comparatorOffset: ic + 1
            )
        case geq:
            // GEQ
            return DecodedInstruction(
                opcode: opcode,
                mnemonic: "GEQ",
                bytesConsumed: 0,
                requiresComparator: true,
                comparatorOffset: ic + 1
            )
        case grt:
            // GRT
            return DecodedInstruction(
                opcode: opcode,
                mnemonic: "GRT",
                bytesConsumed: 0,
                requiresComparator: true,
                comparatorOffset: ic + 1
            )
        case lda:
            // LDA
            let (val, inc) = try codeData.readBig(at: ic + 2)
            let byte1 = try codeData.readByte(at: ic + 1)
            let refLexLevel = proc.lexicalLevel - Int(byte1)
            let loc = Location(
                segment: refLexLevel < 0 ? 0 : currSeg.segNum,
                lexLevel: refLexLevel,
                addr: val
            )
            return DecodedInstruction(
                opcode: opcode,
                mnemonic: "LDA",
                params: [Int(byte1), val],
                bytesConsumed: 2 + inc,
                comment: "Load intermediate address",
                memLocation: loc
            )
        case ldc:
            // LDC has variable-length data - just return count, actual size calculated in switch
            let count = Int(try codeData.readByte(at: ic + 1))
            var params: [Int] = [count]
            var tempIC = ic + 2
            if tempIC % 2 != 0 { tempIC += 1 }  // word aligned data
            for i in (0..<count).reversed() {  // words are in reverse order
                let val = Int(try codeData.readWord(at: tempIC + i * 2))
                params.append(val)
            }
            return DecodedInstruction(
                opcode: opcode,
                mnemonic: "LDC",
                params: params,
                bytesConsumed: 2 + (ic % 2 == 0 ? 0 : 1) + count * 2,
                comment: "Load multiple-word constant"
            )
        case leq:
            // LEQ
            return DecodedInstruction(
                opcode: opcode,
                mnemonic: "LEQ",
                bytesConsumed: 0,
                requiresComparator: true,
                comparatorOffset: ic + 1
            )
        case les:
            // LES
            return DecodedInstruction(
                opcode: opcode,
                mnemonic: "LES",
                bytesConsumed: 0,
                requiresComparator: true,
                comparatorOffset: ic + 1
            )
        case lod:
            // LOD
            let (val, inc) = try codeData.readBig(at: ic + 2)
            let byte1 = try codeData.readByte(at: ic + 1)
            let refLexLevel = proc.lexicalLevel - Int(byte1)
            let loc = Location(
                segment: refLexLevel < 0 ? 0 : currSeg.segNum,
                lexLevel: refLexLevel,
                addr: val
            )
            return DecodedInstruction(
                opcode: opcode,
                mnemonic: "LOD",
                params: [Int(byte1), val],
                bytesConsumed: 2 + inc,
                comment: "Load intermediate word",
                memLocation: loc
            )
        case neq:
            // NEQ
            return DecodedInstruction(
                opcode: opcode,
                mnemonic: "NEQ",
                bytesConsumed: 0,
                requiresComparator: true,
                comparatorOffset: ic + 1
            )
        case str:
            // STR
            let (val, inc) = try codeData.readBig(at: ic + 2)
            let byte1 = try codeData.readByte(at: ic + 1)
            let refLexLevel = proc.lexicalLevel - Int(byte1)
            let loc = Location(
                segment: refLexLevel < 0 ? 0 : currSeg.segNum,
                lexLevel: refLexLevel,
                addr: val
            )
            return DecodedInstruction(
                opcode: opcode,
                mnemonic: "STR",
                params: [Int(byte1), val],
                bytesConsumed: 2 + inc,
                comment: "Store intermediate word",
                memLocation: loc
            )
        case ujp:
            let offset = Int(try codeData.readByte(at: ic + 1))
            var dest: Int = 0
            if offset > 0x7f {
                let jte = addr + offset - 256
                dest = jte - Int(try codeData.readWord(at: jte))
            } else {
                dest = ic + offset + 2
            }
            return DecodedInstruction(
                opcode: opcode,
                mnemonic: "UJP",
                params: [dest],
                bytesConsumed: 2,
                comment: "Unconditional jump to \(String(format: "%04x", dest))"
            )
        case ldm:
            let ldmCount = Int(try codeData.readByte(at: ic + 1))
            return DecodedInstruction(
                opcode: opcode,
                mnemonic: "LDM",
                params: [ldmCount],
                bytesConsumed: 2,
                comment: "Load \(ldmCount) words from (TOS)"
            )
        case stm:
            let stmCount = Int(try codeData.readByte(at: ic + 1))
            return DecodedInstruction(
                opcode: opcode,
                mnemonic: "STM",
                params: [stmCount],
                bytesConsumed: 2,
                comment: "Store \(stmCount) words at TOS to TOS-1"
            )
        case ixp:
            let elementsPerWord = Int(try codeData.readByte(at: ic + 1))
            let fieldWidth = Int(try codeData.readByte(at: ic + 2))
            return DecodedInstruction(
                opcode: opcode,
                mnemonic: "IXP",
                params: [elementsPerWord, fieldWidth],
                bytesConsumed: 3,
                comment:
                    "Index packed array TOS-1[TOS], \(elementsPerWord) elts/word, \(fieldWidth) field width"
            )
        case rbp:
            let retCount = Int(try codeData.readByte(at: ic + 1))
            return DecodedInstruction(
                opcode: opcode,
                mnemonic: "RBP",
                params: [retCount],
                bytesConsumed: 2,
                comment: "Return from base procedure"
            )
        case cbp:
            let procNum = Int(try codeData.readByte(at: ic + 1))
            let loc = Location(segment: currSeg.segNum, procedure: procNum)
            return DecodedInstruction(
                opcode: opcode,
                mnemonic: "CBP",
                params: [procNum],
                bytesConsumed: 2,
                comment: "Call base procedure",
                destination: loc
            )
        case lla:
            let (val, inc) = try codeData.readBig(at: ic + 1)
            let loc = Location(
                segment: currSeg.segNum,
                procedure: procedure,
                lexLevel: proc.lexicalLevel,
                addr: val
            )
            return DecodedInstruction(
                opcode: opcode,
                mnemonic: "LLA",
                params: [val],
                bytesConsumed: 1 + inc,
                comment: "Load local address",
                memLocation: loc
            )
        case ldci:
            let val = Int(try codeData.readWord(at: ic + 1))
            return DecodedInstruction(
                opcode: opcode,
                mnemonic: "LDCI",
                params: [val],
                bytesConsumed: 3,
                comment: "Load one-word constant \(val)"
            )
        case ldl:
            let (val, inc) = try codeData.readBig(at: ic + 1)
            let loc = Location(
                segment: segment,
                procedure: procedure,
                lexLevel: proc.lexicalLevel,
                addr: val
            )
            return DecodedInstruction(
                opcode: opcode,
                mnemonic: "LDL",
                params: [val],
                bytesConsumed: 1 + inc,
                comment: "Load local word",
                memLocation: loc
            )
        case stl:
            let (val, inc) = try codeData.readBig(at: ic + 1)
            let loc = Location(
                segment: segment,
                procedure: procedure,
                lexLevel: proc.lexicalLevel,
                addr: val
            )
            return DecodedInstruction(
                opcode: opcode,
                mnemonic: "STL",
                params: [val],
                bytesConsumed: 1 + inc,
                comment: "Store local word",
                memLocation: loc
            )
        case cxp:
            let seg = Int(try codeData.readByte(at: ic + 1))
            let procNum = Int(try codeData.readByte(at: ic + 2))
            let loc = Location(segment: seg, procedure: procNum)
            return DecodedInstruction(
                opcode: opcode,
                mnemonic: "CXP",
                params: [seg, procNum],
                bytesConsumed: 3,
                comment: "Call external procedure",
                destination: loc
            )
        case clp:
            let procNum = Int(try codeData.readByte(at: ic + 1))
            let loc = Location(segment: currSeg.segNum, procedure: procNum)
            return DecodedInstruction(
                opcode: opcode,
                mnemonic: "CLP",
                params: [procNum],
                bytesConsumed: 2,
                comment: "Call local procedure",
                destination: loc
            )
        case cgp:
            let procNum = Int(try codeData.readByte(at: ic + 1))
            let loc = Location(segment: currSeg.segNum, procedure: procNum)
            return DecodedInstruction(
                opcode: opcode,
                mnemonic: "CGP",
                params: [procNum],
                bytesConsumed: 2,
                comment: "Call global procedure",
                destination: loc
            )
        case lpa:
            let count = Int(try codeData.readByte(at: ic + 1))
            var txtRep = ""
            for i in 1...count {
                if let c = try? codeData.readByte(at: ic + 1 + i) {
                    if c >= 0x20 && c <= 0x7e {
                        txtRep.append(Character(UnicodeScalar(Int(c))!))
                    } else {
                        txtRep.append(".")
                    }
                }
            }
            return DecodedInstruction(
                opcode: opcode,
                mnemonic: "LPA",
                params: [count],
                stringParameter: txtRep,
                bytesConsumed: 2 + count,
                comment: "Load packed array"
            )
        case ste:
            let seg = Int(try codeData.readByte(at: ic + 1))
            let (val, inc) = try codeData.readBig(at: ic + 2)
            let loc = Location(
                segment: seg,
                procedure: 0,
                lexLevel: 0,
                addr: val
            )
            return DecodedInstruction(
                opcode: opcode,
                mnemonic: "STE",
                params: [seg, val],
                bytesConsumed: 2 + inc,
                comment: "Store extended word TOS into",
                memLocation: loc
            )
        case bpt:
            let (val, inc) = try codeData.readBig(at: ic + 1)
            return DecodedInstruction(
                opcode: opcode,
                mnemonic: "BPT",
                params: [val],
                bytesConsumed: 1 + inc,
                comment: "Breakpoint"
            )
        case sldl1...sldl16:
            let b = Int(opcode)
            let val = b - Int(sldl1) + 1
            let loc = Location(
                segment: segment,
                procedure: procedure,
                lexLevel: proc.lexicalLevel,
                addr: val
            )
            return DecodedInstruction(
                opcode: opcode,
                mnemonic: "SLDL",
                params: [val],
                bytesConsumed: 1,
                comment: "Short load local word",
                memLocation: loc
            )
        case sldo1...sldo16:
            let b2 = Int(opcode)
            let val = b2 - Int(sldo1) + 1
            let loc = Location(segment: segment, lexLevel: 0, addr: val)
            return DecodedInstruction(
                opcode: opcode,
                mnemonic: "SLDO",
                params: [val],
                bytesConsumed: 1,
                comment: "Short load global word",
                memLocation: loc
            )
        case sind0...sind7:
            let b3 = Int(opcode)
            let offs = b3 - Int(sind0)
            return DecodedInstruction(
                opcode: opcode,
                mnemonic: "SIND",
                params: [offs],
                bytesConsumed: 1,
                comment: "Short index and load word *TOS+\(offs)"
            )
        default:
            throw CodeDataError.unexpectedEndOfData
        }
    }

    func decodeComparator(at index: Int) -> (
        suffix: String, prefix: String, increment: Int, dataType: String
    ) {
        guard let b = try? codeData.readByte(at: index) else {
            return ("", "", 1, "")
        }
        switch b {
        case 2: return ("REAL", "Real", 1, "REAL")
        case 4: return ("STR", "String", 1, "STRING")
        case 6: return ("BOOL", "Boolean", 1, "BOOLEAN")
        case 8: return ("SET", "Set", 1, "SET")
        case 10:
            if let (val, inc) = try? codeData.readBig(at: index + 1) {
                return (
                    "BYTE", "Byte array (\(val) long)", inc + 1,
                    "ARRAY[1..\(val)] OF BYTE"
                )
            }
            return ("BYTE", "Byte array (0 long)", 1, "ARRAY OF BYTE")
        case 12:
            if let (val, inc) = try? codeData.readBig(at: index + 1) {
                return (
                    "WORD", "Word array (\(val) long)", inc + 1,
                    "ARRAY[1..\(val)] OF WORD"
                )
            }
            return ("WORD", "Word array (0 long)", 1, "ARRAY OF WORD")
        default:
            return ("", "", 1, "")
        }
    }
}
