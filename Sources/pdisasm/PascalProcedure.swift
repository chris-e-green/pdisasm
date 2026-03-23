import Foundation

func decodePascalProcedure(
    currSeg: Segment,
    procedureNumber: Int,
    proc: inout Procedure,
    code: Data,
    addr: Int,
    callers: inout Set<Call>,
    allLocations: inout Set<Location>,
    allProcedures: inout [ProcedureIdentifier],
    verbose: Bool = false
) {
    // Early validation: ensure addr and the procedure header bytes are present
    // Many subsequent reads assume bytes at addr+1 and at addr-2..addr-8. If
    // the buffer is too small or addr is invalid, bail out silently to avoid
    // crashing on malformed data.
    if addr < 0 { return }
    if addr + 1 >= code.count { return }
    if addr - 8 < 0 { return }

    // Create a CodeData view for bounds-checked reads.
    let cd = CodeData(data: code, instructionPointer: 0, header: 0)

    // Read header fields with bounds-checked reads.
    do {
        let lexical = try cd.readByte(at: addr + 1)
        proc.lexicalLevel = Int(lexical)
        if proc.lexicalLevel > 127 { proc.lexicalLevel -= 256 }

        proc.enterIC = try cd.getSelfRefPointer(at: addr - 2)
        proc.exitIC = try cd.getSelfRefPointer(at: addr - 4)
        proc.parameterSize = Int(try cd.readWord(at: addr - 6)) >> 1
        proc.dataSize = Int(try cd.readWord(at: addr - 8)) >> 1
    } catch {
        return
    }

    // Validate computed entry/exit ICs
    if proc.enterIC < 0 || proc.exitIC < 0 || proc.enterIC >= addr
        || proc.exitIC >= addr
        || proc.enterIC >= code.count || proc.exitIC >= code.count
    {
        return
    }

    let segment = currSeg.segNum
    let procedure = procedureNumber
    var isFunction = false

    // by using strings, we can store and manipulate symbolic data rather than just locations/ints
    var ic = proc.enterIC

    var done: Bool = false
    proc.entryPoints.insert(proc.enterIC)
    proc.entryPoints.insert(proc.exitIC)
    let myLoc = Location(
        segment: segment,
        procedure: procedure,
        lexLevel: proc.lexicalLevel
    )

    // Initialize components for clean separation of concerns
    let decoder = OpcodeDecoder(codeData: cd)

    // Decode loop: uses new architecture for clean separation of decoding, simulation, and generation
    while ic < addr && !done {
        do {
            let opcode = try cd.readByte(at: ic)

            // Decode the instruction using the new architecture
            var decoded: OpcodeDecoder.DecodedInstruction
            if let cachedDecoded = try? decoder.decode(
                opcode: opcode,
                at: ic,
                currSeg: currSeg,
                segment: segment,
                procedure: procedure,
                proc: proc,
                addr: addr
            ) {
                decoded = cachedDecoded
            } else {
                // Fallback for any decode errors
                if verbose {
                    print(
                        "Decode error at IC \(String(format: "%04x", ic)) in segment \(segment) proc \(procedure)"
                    )
                }
                return
            }

            // Handle comparator opcodes specially
            var finalMnemonic = decoded.mnemonic
            var finalComment = decoded.comment
            var bytesConsumed = decoded.bytesConsumed
            let params = decoded.params
            var comparatorDataType: String = ""

            if decoded.requiresComparator {
                let (suffix, prefix, inc, dataType) = decoder.decodeComparator(
                    at: decoded.comparatorOffset
                )
                finalMnemonic += suffix
                comparatorDataType = dataType
                finalComment =
                    prefix
                    + " TOS-1 \(decoded.mnemonic == "EQL" ? "=" : decoded.mnemonic == "GEQ" ? ">=" : decoded.mnemonic == "GRT" ? ">" : decoded.mnemonic == "LEQ" ? "<=" : decoded.mnemonic == "LES" ? "<" : "<>") TOS"
                bytesConsumed = inc + 1
            }

            let memLoc = decoded.memLocation
            let dest = decoded.destination

            // Helper: track a procedure call (find-or-create Location, record caller relationship)
            func trackCall(targetSegment: Int, targetProcedure: Int) {
                let loc =
                    allLocations.first(where: {
                        $0.segment == targetSegment && $0.procedure == targetProcedure
                            && $0.addr == nil
                    })
                    ?? Location(segment: targetSegment, procedure: targetProcedure, addr: nil)
                allLocations.insert(loc)
                if targetProcedure != procedure || targetSegment != segment {
                    callers.insert(Call(from: myLoc, to: loc))
                }
            }

            switch opcode {
            case rnp:
                // Return from non-base procedure
                isFunction = (decoded.params[0] > 0)
                done = true
            case rbp:
                // Return from base procedure
                isFunction = (decoded.params[0] > 0)
                done = true
            case xit:
                // Exit interpreter — only PASCALSYSTEM.PASCALSYSTEM calls this
                isFunction = false
                done = true
            case cip:
                trackCall(targetSegment: segment, targetProcedure: Int(decoded.params[0]))
            case cbp:
                trackCall(targetSegment: segment, targetProcedure: Int(params[0]))
            case clp:
                trackCall(targetSegment: segment, targetProcedure: Int(params[0]))
            case cgp:
                trackCall(targetSegment: segment, targetProcedure: Int(params[0]))
            case cxp:
                trackCall(targetSegment: Int(params[0]), targetProcedure: Int(params[1]))
            case ldc:
                // LDC is special: recalculate bytesConsumed for variable-length word-aligned data
                let count = decoded.params[0]
                bytesConsumed = 2 + (ic % 2 == 0 ? 0 : 1) + count * 2
            default:
                // All other opcodes (including unknown ones) just advance ic.
                // Unknown opcodes with no mnemonic indicate unrecognised data — stop decoding.
                if decoded.mnemonic.isEmpty {
                    return
                }
            }
            ic += bytesConsumed

            // Build instruction from decoded data (after switch, before applying markers)
            if proc.instructions[ic - bytesConsumed] == nil {
                proc.instructions[ic - bytesConsumed] = Instruction(
                    opcode: opcode,
                    mnemonic: finalMnemonic,
                    params: decoded.params,
                    stringParameter: decoded.stringParameter,
                    comparatorDataType: comparatorDataType,
                    memLocation: memLoc,
                    destination: dest,
                    comment: finalComment
                )
            }
        } catch {
            // Any read error (out of range, EOF) aborts decoding this procedure.
            return
        }
    }

    if proc.identifier == nil {
        proc.identifier = ProcedureIdentifier(
            isFunction: isFunction,
            isAssembly: false,
            segment: segment,
            segmentName: currSeg.name,
            procedure: procedure
        )
        if proc.parameterSize > 0 {
            var paramCount = proc.parameterSize
            if proc.identifier?.isFunction == true {
                // functions have an extra two words for the return value
                paramCount -= 2
            }
            if paramCount > 0 {
                for parmnum in 1...paramCount {
                    proc.identifier?.parameters.append(
                        Identifier(name: "PARAM\(parmnum)", type: "UNKNOWN")
                    )
                }
            }
        }
    }

    if let p = proc.identifier {
        if !allProcedures.contains(where: {
            $0.procedure == p.procedure && $0.segment == p.segment
        }) {
            allProcedures.append(p)
        }
    }
}
