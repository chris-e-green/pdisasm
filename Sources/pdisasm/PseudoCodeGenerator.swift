import Foundation

// MARK: - Pseudo-code Generator

/// Generates high-level pseudo-code from decoded instructions and stack states
struct PseudoCodeGenerator {
    let allProcedures: [ProcedureIdentifier]
    let knownRecords: Set<PascalRecord>
    var allLocations: Set<Location>
    var labelLookup: [String: Location]
    var typeConflicts: [TypeConflict] = []

    init(allProcedures: [ProcedureIdentifier], knownRecords: Set<PascalRecord>, allLocations: Set<Location>, labelLookup: [String: Location]) {
        self.allProcedures = allProcedures
        self.knownRecords = knownRecords
        self.allLocations = allLocations
        self.labelLookup = labelLookup
    }

    init(allProcedures: [ProcedureIdentifier], knownRecords: Set<PascalRecord>, allLocations: Set<Location>) {
        self.allProcedures = allProcedures
        self.knownRecords = knownRecords
        self.allLocations = allLocations
        var lookup: [String: Location] = [:]
        for label in allLocations {
            let key = "\(label.segment):\(label.procedure ?? -1):\(label.addr ?? -1)"
            lookup[key] = label
        }
        self.labelLookup = lookup
    }

    func findStackLabel(_ loc: Location) -> (String, String?) {
        let key = "\(loc.segment):\(loc.procedure ?? -1):\(loc.addr ?? -1)"
        if let ll = labelLookup[key] {
            return (ll.displayName, ll.displayType)
        } else {
            return (loc.displayName, loc.displayType)
        }
    }
    
    mutating func setLocType(_ locStr: String, _ type: String, evidence: String = "") {
        // if the location is a memory reference, set the type.
        if locStr.contains(/^S[0-9]*_P[0-9]*_L[0-9]*_A[0-9]*$/) {
            // convert string location to Location
            let l = Location(from: locStr)
            // find in allLocations and set type
            let found = allLocations.first(where: { $0 == l })
            if let conflict = found?.assignType(type, source: .inferred, evidence: evidence) {
                typeConflicts.append(conflict)
            }
        }
    }

    mutating func generateForInstruction(
        _ inst: Instruction,
        stack: inout StackSimulator,
        loc: Location?
    ) -> String? {
        switch inst.opcode {
        case sto:
            let (src, srcType) = stack.pop()
            var (destName, destType) = stack.pop()
            switch destType {
            case "CHAR":
                if let ch = Int(src), ch >= 0x20 && ch <= 0x7E {
                    return
                      "\(destName) := '\(String(format: "%c", ch))'"
                } else {
                    return "\(destName) := \(src)"
                }
            case "BOOLEAN":
                if src == "0" {
                    return "\(destName) := FALSE"
                } else if src == "1" {
                    return "\(destName) := TRUE"
                } else {
                    return "\(destName) := \(src)"
                }
                
            default:
                if let type = destType, !type.isEmpty && type != "UNKNOWN"  {
                    setLocType(src, type)
                }
                if let type = srcType, !type.isEmpty && type != "UNKNOWN" {
                    setLocType(destName, type)
                }
                break
            }
            if let type = destType, type.starts(with:"ARRAY") {
                destName = "\(destName)[0]"  // for now just show the first element being assigned
            }
            return "\(destName) := \(src)"
        case sas:
            let (src, _) = stack.pop()
            let (dest, _) = stack.pop()
            setLocType(src, "STRING")
            setLocType(dest, "STRING")
            return "\(dest) := \(src)"
        case mov:
            let (src, _) = stack.pop()
            let (dst, _) = stack.pop()
            return "\(dst) := \(src)"
        case stp:
            let (a, _) = stack.pop()
            let (bbit, _) = stack.pop()
            let (bwid, _) = stack.pop()
            let (b, _) = stack.pop()
            return "\(b):\(bwid):\(bbit) := \(a)"
        case stb:
            let (src, _) = stack.pop(true)
            let (dstoffs, dstoffstype) = stack.pop()
            let (dstaddr, dstaddrtype) = stack.pop()
            if dstaddrtype == "STRING" && dstoffstype == "INTEGER" {
                if let offset = Int(dstoffs), offset > 0 {
                    if let ch = Int(src), ch >= 0x20 && ch <= 0x7E {
                        return "\(dstaddr)[\(dstoffs)] := '\(String(format: "%c", ch))'"
                    }
                }
            }
            return "\(dstaddr)[\(dstoffs)] := \(src)"
        case stm:
            let stmCount = inst.params[0]
            var src: String = ""
            var prevElement: String = ""
            var srcdata: [String] = []
            let (_, t1) = stack.peek()
            if stmCount == 2 && t1 == "REAL" {
                (src, _) = stack.popReal()
            } else {
                for _ in 0..<stmCount {
                    let (element, _) = stack.pop(true)
                    let elementParts = element.split(separator: "{")
                    if String(elementParts[0]) != prevElement {
                        prevElement = String(elementParts[0])
                        srcdata.append(String(elementParts[0]))
                    }
                }
                src = srcdata.joined(separator: ", ")
            }
            let (dst, t) = stack.pop()  // destination address
            if stmCount == 2 && srcdata.count == 2 && t == "REAL" {
                // need to see if the elements parse as a real number
                if let val1 = UInt16(srcdata[0]), let val2 = UInt16(srcdata[1]) {
                    let rv = Float(bitPattern: UInt32(val1) | UInt32(val2) << 16)
                    setLocType(dst, "REAL")
                    return "\(dst) := \(String(format:"%f", rv))"
                } else {
                    setLocType(src, "REAL")
                }
            }
            return "\(dst) := \(src)"
            
        case sro, str, stl, ste:
            let (_, srcType) = stack.peek()
            if let destLoc = inst.memLocation {
                allLocations.insert(destLoc)
                let (destName, destType) = findStackLabel(destLoc)
                switch destType {
                case _ where (destType != nil && destType!.hasPrefix("SET ")):
                    let (_, at) = stack.peek()
                    if at == "INTEGER" {
                        let (_, setData) = stack.popSet()
                        return "\(destName) := \(setData)"
                    } else {
                        let (a, _) = stack.pop(true)
                        return "\(destName) := \(a)"
                    }
                case "CHAR":
                    let (src, _) = stack.pop(true)
                    if let ch = Int(src), ch >= 0x20 && ch <= 0x7E {
                        return "\(destName) := '\(String(format: "%c", ch))'"
                    } else {
                        return "\(destName) := \(src)"
                    }
                case "BOOLEAN":
                    let (src, _) = stack.pop(true)
                    if src == "0" {
                        return "\(destName) := FALSE"
                    } else if src == "1" {
                        return "\(destName) := TRUE"
                    } else {
                        return "\(destName) := \(src)"
                    }
                    
                default:
                    let (src, _) = stack.pop(true)
                    if let type = destType, !type.isEmpty && type != "UNKNOWN"  {
                        setLocType(src, type)
                    }
                    if let type = srcType, !type.isEmpty && type != "UNKNOWN" {
                        setLocType(destLoc.displayName, type)
                    }
                    return "\(destName) := \(src)"
                }
            } else {
                let (src, _) = stack.pop()
                return "\(inst.memLocation?.displayName ?? "unknown") := \(src)"
            }
        case cip, cbp, cxp, clp, cgp:
            if let dest = inst.destination {
                return handleCallProcedure(dest, stack: &stack)
            }
            return "missing destination!"
            
            // MARK: - Arithmetic / logic opcodes
            
        case abi:
            let (a, _) = stack.pop("INTEGER")
            setLocType(a, "INTEGER")
            stack.push(("ABI(\(a))", "INTEGER"))
            return nil
        case abr:
            let (a, _) = stack.popReal()
            setLocType(a, "REAL")
            stack.push(("ABR(\(a))", "REAL"))
            return nil
        case adi:
            let (a, _) = stack.pop("INTEGER")
            setLocType(a, "INTEGER")
            let (b, _) = stack.pop("INTEGER")
            setLocType(b, "INTEGER")
            stack.push(("\(b) + \(a)", "INTEGER"))
            return nil
        case adr:
            let (a, _) = stack.popReal()
            setLocType(a, "REAL")
            let (b, _) = stack.popReal()
            setLocType(b, "REAL")
            stack.push(("\(a) + \(b)", "REAL"))
            return nil
        case land:
            let (a, _) = stack.pop("BOOLEAN")
            setLocType(a, "BOOLEAN")
            let (b, _) = stack.pop("BOOLEAN")
            setLocType(b, "BOOLEAN")
            stack.push(("\(b) AND \(a)", "BOOLEAN"))
            return nil
        case lor:
            let (a, _) = stack.pop("BOOLEAN")
            setLocType(a, "BOOLEAN")
            let (b, _) = stack.pop("BOOLEAN")
            setLocType(b, "BOOLEAN")
            stack.push(("\(b) OR \(a)", "BOOLEAN"))
            return nil
        case lnot:
            let (a, _) = stack.pop("BOOLEAN")
            setLocType(a, "BOOLEAN")
            stack.push(("NOT \(a)", "BOOLEAN"))
            return nil
        case dvi:
            let (a, _) = stack.pop("INTEGER")
            setLocType(a, "INTEGER")
            let (b, _) = stack.pop("INTEGER")
            setLocType(b, "INTEGER")
            stack.push(("\(b) DIV \(a)", "INTEGER"))
            return nil
        case dvr:
            let (a, _) = stack.popReal()
            setLocType(a, "REAL")
            let (b, _) = stack.popReal()
            setLocType(b, "REAL")
            stack.push(("\(b) / \(a)", "REAL"))
            return nil
        case modi:
            let (a, _) = stack.pop("INTEGER")
            setLocType(a, "INTEGER")
            let (b, _) = stack.pop("INTEGER")
            setLocType(b, "INTEGER")
            stack.push(("\(b) MOD \(a)", "INTEGER"))
            return nil
        case mpi:
            let (a, _) = stack.pop("INTEGER")
            setLocType(a, "INTEGER")
            let (b, _) = stack.pop("INTEGER")
            setLocType(b, "INTEGER")
            stack.push(("\(b) * \(a)", "INTEGER"))
            return nil
        case mpr:
            let (a, _) = stack.popReal()
            setLocType(a, "REAL")
            let (b, _) = stack.popReal()
            setLocType(b, "REAL")
            stack.push(("\(b) * \(a)", "REAL"))
            return nil
        case ngi:
            let (a, _) = stack.pop("INTEGER")
            setLocType(a, "INTEGER")
            stack.push(("-\(a)", "INTEGER"))
            return nil
        case ngr:
            let (a, _) = stack.popReal()
            setLocType(a, "REAL")
            stack.push(("-\(a)", "REAL"))
            return nil
        case sbi:
            let (a, _) = stack.pop("INTEGER")
            setLocType(a, "INTEGER")
            let (b, _) = stack.pop("INTEGER")
            setLocType(b, "INTEGER")
            stack.push(("\(b) - \(a)", "INTEGER"))
            return nil
        case sbr:
            let (a, _) = stack.popReal()
            setLocType(a, "REAL")
            let (b, _) = stack.popReal()
            setLocType(b, "REAL")
            stack.push(("\(b) - \(a)", "REAL"))
            return nil
        case sqi:
            let (a, _) = stack.pop("INTEGER")
            setLocType(a, "INTEGER")
            stack.push(("\(a) * \(a)", "INTEGER"))
            return nil
        case sqr:
            let (a, _) = stack.popReal()
            setLocType(a, "REAL")
            stack.push(("\(a) * \(a)", "REAL"))
            return nil
        case flo:
            let a = stack.popReal()  // TOS
            setLocType(a.val, "REAL")
            let (b, _) = stack.pop()  // TOS-1
            setLocType(b, "INTEGER")
            stack.push((b, "REAL"))  // real(TOS-1)->TOS-1
            stack.push(a)  // put previous TOS back
            return nil
        case flt:
            let (a, _) = stack.pop("INTEGER")
            setLocType(a, "INTEGER")
            stack.push((a, "REAL"))
            return nil
        case chk:
            let (a, at) = stack.pop()
            let (b, bt) = stack.pop()
            let (c, ct) = stack.pop()
            let type = (at != "UNKNOWN" ? at : (bt != "UNKNOWN" ? bt : ct)) ?? ""
            setLocType(a, type)
            setLocType(b, type)
            setLocType(c, type)
            stack.push((c, type))
            return nil
            
            // MARK: - Set opcodes
            
        case dif:
            let (set1Len, set1) = stack.popSet()
            let (set2Len, set2) = stack.popSet()
            let maxLen = max(set1Len, set2Len)
            for i in 0..<maxLen {
                stack.push(("(\(set2) AND NOT \(set1)){\(i)}", "SET"))
            }
            stack.push(("\(maxLen)", "INTEGER"))
            return nil
        case inn:
            let (_, set) = stack.popSet()
            let (chkVal, _) = stack.pop()
            setLocType(chkVal, "INTEGER")
            stack.push(("\(chkVal) IN \(set)", "BOOLEAN"))
            return nil
        case int:
            let (set1Len, set1) = stack.popSet()
            let (set2Len, set2) = stack.popSet()
            let maxLen = max(set1Len, set2Len)
            for i in 0..<maxLen {
                stack.push(("(\(set1) AND \(set2)){\(i)}", "SET"))
            }
            stack.push(("\(maxLen)", "INTEGER"))
            return nil
        case uni:
            let (set1Len, set1) = stack.popSet()
            let (set2Len, set2) = stack.popSet()
            let maxLen = max(set1Len, set2Len)
            for i in 0..<maxLen {
                stack.push(("(\(set1) OR \(set2)){\(i)}", "SET"))
            }
            stack.push(("\(maxLen)", "INTEGER"))
            return nil
        case srs:
            let (a, _) = stack.pop()
            let (b, _) = stack.pop()
            if let av = Int(a) {
                let wordsRequired = (av / 16) + 1
                for i in 0..<wordsRequired {
                    stack.push(("[\(b)..\(a)]{\(i)}", "SET"))
                }
                stack.push(("\(wordsRequired)", "INTEGER"))
            } else {
                stack.push(("\(b)..\(a)", "SET"))
                stack.push(("1", "INTEGER"))
            }
            return nil
        case sgs:
            let (a, _) = stack.pop("INTEGER", true)
            if let av = Int(a) {
                let wordsRequired = (av / 16) + 1
                for i in 0..<wordsRequired {
                    stack.push(("[\(a)]{\(i)}", "SET"))
                }
                stack.push(("\(wordsRequired)", "INTEGER"))
            } else {
                stack.push(("\(a)", "SET"))
                stack.push(("1", "INTEGER"))
            }
            return nil
        case adj:
            let count = inst.params[0]
            let (_, set) = stack.popSet()
            if count == 1 {
                // special case where only one word is needed to represent the set, so we can just push the set itself without the word index
                stack.push((set, "INTEGER"))
            } else {
                for i in 0..<count {
                    stack.push(("\(set){\(i)}", "INTEGER"))
                }
            }
            return nil
            
            // MARK: - Typed comparison opcodes
            
        case eql:
            handleComparison(inst.comparatorDataType, &stack, "=")
            return nil
        case geq:
            handleComparison(inst.comparatorDataType, &stack, ">=")
            return nil
        case grt:
            handleComparison(inst.comparatorDataType, &stack, ">")
            return nil
        case leq:
            handleComparison(inst.comparatorDataType, &stack, "<=")
            return nil
        case les:
            handleComparison(inst.comparatorDataType, &stack, "<")
            return nil
        case neq:
            handleComparison(inst.comparatorDataType, &stack, "<>")
            return nil
            
            // MARK: - Integer/char comparison opcodes
            
        case equi:
            handleIntegerComparison(&stack, "=")
            return nil
        case geqi:
            handleIntegerComparison(&stack, ">=")
            return nil
        case grti:
            handleIntegerComparison(&stack, ">")
            return nil
        case leqi:
            handleIntegerComparison(&stack, "<=")
            return nil
        case lesi:
            handleIntegerComparison(&stack, "<")
            return nil
        case neqi:
            handleIntegerComparison(&stack, "<>")
            return nil
            
            // MARK: - Load / push opcodes
            
        case sldc0...sldc127:
            stack.push((String(inst.opcode), "INTEGER"))
            return nil
        case lao, lae, lda, lla:
            // addresses
            if let loc = inst.memLocation {
                let stackLabel = findStackLabel(loc)
                stack.push((stackLabel.0, (stackLabel.1 ?? "") ), isPointer: true)
                allLocations.insert(loc)
            }
            return nil
        case ldo, lod, lde, ldl, sldl1...sldl16, sldo1...sldo16:
            if let loc = inst.memLocation {
                stack.push(findStackLabel(loc))
                allLocations.insert(loc)
            }
            return nil
            
        case ldc:
            let count = inst.params[0]
            for i in (0..<count).reversed() {
                let val = inst.params[1 + i]
                stack.push(("\(val)", "INTEGER"))
            }
            return nil
        case ldci:
            let val = inst.params[0]
            stack.push(("\(val)", "INTEGER"))
            return nil
        case ldcn:
            stack.push(("NIL", "POINTER"))
            return nil
        case lsa:
            let s = inst.stringParameter ?? ""
            stack.push(("\'\(s)\'", "STRING"))
            return nil
        case lpa:
            let txtRep = inst.stringParameter ?? ""
            stack.push(("'\(txtRep)'", "PACKED ARRAY"))
            return nil
        case ldm:
            let ldmCount = inst.params[0]
            let (wdOrigin, _) = stack.pop()
            for i in 0..<ldmCount {
                stack.push(("\(wdOrigin){\(i)}", "INTEGER"))
            }
            return nil
        case ldb:
            let (a, _) = stack.pop()
            let (b, _) = stack.pop()
            stack.push(("\(b)[\(a)]", "BYTE"))
            return nil
        case ldp:
            let (abit, _) = stack.pop()
            let (awid, _) = stack.pop()
            let (a, _) = stack.pop()
            stack.push(("\(a):\(awid):\(abit)", "INTEGER"))
            return nil
        case inc:
            let val = inst.params[0]
            let (a, t) = stack.pop()
            if let t = t, t.hasPrefix("ARRAY") {
                stack.push(("\(a)[\(val)]", String(t.split(separator: " ").last!)))
            } else if let type = t, let structInfo = knownRecords.first(where: { $0.name == type }), let field = structInfo.members[val] {
                stack.push(("\(a).\(field.name)", field.type))
            }
            else {
                stack.push(("\(a) + \(val)", t))
            }
            return nil
        case ind:
            let val = inst.params[0]
            let (a, t) = stack.pop()
            if let type = t, let structInfo = knownRecords.first(where: { $0.name == type }), let field = structInfo.members[val] {
                stack.push(("\(a).\(field.name)", field.type))
                return nil
            }
            stack.push(("\(a) + \(val)", "INTEGER"))
            return nil
        case ixa:
            let _ = inst.params[0]
            let (eltIndex, _) = stack.pop()
            let (arrayBase, t) = stack.pop()
            if let type = t, type.starts(with: "ARRAY") {
                let elementType = String(type.split(separator: " ").last!)
                stack.push(("\(arrayBase)[\(eltIndex)]", elementType))
                return nil
            }
            stack.push(("\(arrayBase)[\(eltIndex)]", t))
            return nil
        case ixp:
            let elementsPerWord = inst.params[0]
            let fieldWidth = inst.params[1]
            let (idx, _) = stack.pop()
            let basePtr = stack.pop()
            stack.push(basePtr)
            stack.push(("\(fieldWidth)", "INTEGER"))
            stack.push(("\(idx)*\(elementsPerWord)", "INTEGER"))
            return nil
        case ixs:
            let (index, _) = stack.peek()
            setLocType(index, "INTEGER")
            let _ = stack.peek(1)
            let _ = stack.peek(2)
            return nil
        case sind0...sind7:
            let offs = inst.params[0]
            let (a, t) = stack.pop()
            if let t = t, t.hasPrefix("ARRAY") {
                stack.push(("\(a)[\(offs)]", String(t.split(separator: " ").last!)))
            } else if let type = t, let structInfo = knownRecords.first(where: { $0.name == type }), let field = structInfo.members[offs] {
                stack.push(("\(a).\(field.name)", field.type))
            } else {
                stack.push(("*(\(a) + \(offs))", t))
            }
            return nil

        // MARK: - Call standard procedure

        case csp:
            let procNum = inst.params[0]
            if let (cspName, parms, returnType) = cspProcs[procNum] {
                var callParms: [String] = []
                for p in parms {
                    var parm: String = ""
                    if p.type == "REAL" {
                        (parm, _) = stack.popReal()
                    } else {
                        (parm, _) = stack.pop(p.type)
                        setLocType(parm, p.type)
                    }
                    callParms.append(parm)
                }
                let callStr = "\(cspName)(\(callParms.reversed().joined(separator:", ")))"
                if !returnType.isEmpty {
                    stack.push((callStr, returnType))
                    return nil
                } else {
                    return callStr
                }
            }
            return nil

        default:
            return nil
        }
    }

    // MARK: - Helpers

    private mutating func handleComparison(
        _ dataType: String,
        _ stack: inout StackSimulator,
        _ opString: String
    ) {
        if dataType == "SET" {
            let (_, a) = stack.popSet()
            let (_, b) = stack.popSet()
            stack.push(("\(b) \(opString) \(a)", "BOOLEAN"))
        } else if dataType == "REAL" {
            let (a, _) = stack.popReal()
            setLocType(a, dataType)
            let (b, _) = stack.popReal()
            setLocType(b, dataType)
            stack.push(("\(b) \(opString) \(a)", "BOOLEAN"))
        } else {
            let (a, _) = stack.pop()
            setLocType(a, dataType)
            let (b, _) = stack.pop()
            setLocType(b, dataType)
            stack.push(("\(b) \(opString) \(a)", "BOOLEAN"))
        }
    }

    /// Integer/char comparison helper shared by equi, geqi, grti, leqi, lesi, neqi.
    private mutating func handleIntegerComparison(
        _ stack: inout StackSimulator,
        _ opString: String
    ) {
        var (a, ta) = stack.pop()
        var (b, tb) = stack.pop()
        if ta == "CHAR" || tb == "CHAR" {
            setLocType(a, "CHAR")
            a = chkCharType(a)
            setLocType(b, "CHAR")
            b = chkCharType(b)
        } else {
            setLocType(a, "INTEGER")
            setLocType(b, "INTEGER")
        }
        stack.push(("\(b) \(opString) \(a)", "BOOLEAN"))
    }

    private func chkCharType(_ loc: String) -> String {
        if let ch = Int(loc) {
            if ch >= 0x20 && ch <= 0x7E {
                return String(format: "'%c'", ch)
            } else {
                return String(format: "CHAR(%i)", ch)
            }
        } else {
            return loc
        }
    }

    mutating func handleCallProcedure(_ loc: Location, stack: inout StackSimulator)
        -> String?
    {
        guard let called = allProcedures.first(where:{ $0.segment == loc.segment && $0.procedure == loc.procedure })
                 else {
            return loc.displayName + "()"  // fallback to just displaying the location
        }

        let parmCount = called.parameters.count
        var aParams: [String] = []
        if called.isFunction {
            // pop and discard the return variable space (always two words)
            _ = stack.pop()
            _ = stack.pop()
        }
        var i = parmCount - 1
        while i >= 0 {
            // TODO: SET values contain a length on the stack but not in function parameters,
            // so we probably need to pop it as a set, not just blindly.
            switch called.parameters[i].type {
            case "CHAR":
                let (a, _) = stack.pop()
                if let ch = Int(a), ch >= 0x20 && ch <= 0x7E {
                    aParams.append("'\(String(format: "%c", ch))'")
                } else {
                    aParams.append(a)
                }
                setLocType(a, "CHAR")
                i -= 1
            case "BOOLEAN":
                let (a, _) = stack.pop()
                if a == "0" {
                    aParams.append("FALSE")
                } else if a == "1" {
                    aParams.append("TRUE")
                } else {
                    aParams.append(a)
                }
                setLocType(a, "BOOLEAN")
                i -= 1
            case "REAL":
                let (a, _) = stack.popReal()
                aParams.append(a)
                setLocType(a, "REAL")
                i -= 1
            case let pfx where pfx.hasPrefix("SET"):
                let (a, at) = stack.peek()
                if at == "INTEGER" {
                    let (setLen, setData) = stack.popSet()
                    aParams.append(setData)
                    i -= setLen
                } else {
                    if let ai = Int(a), ai > 0 {
                        aParams.append(a)
                        i -= ai
                    } else {
                        aParams.append(a)
                        i -= 1
                    }
                }
            default:
                let (a, _) = stack.pop()
                aParams.append(a)
                setLocType(a, called.parameters[i].type)
                i -= 1
            }
        }

        let callSignature =
            "\(called.shortDescription)(\(aParams.reversed().joined(separator:", ")))"

        if called.isFunction {
            stack.push((callSignature, called.returnType))
            return nil
        } else {
            return callSignature
        }
    }
}
