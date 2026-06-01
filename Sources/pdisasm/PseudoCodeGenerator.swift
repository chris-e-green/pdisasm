import Foundation

// MARK: - Pseudo-code Generator

/// Generates high-level pseudo-code from decoded instructions and stack states
struct PseudoCodeGenerator {
    let allProcedures: [ProcedureIdentifier]
    let knownRecords: Set<PascalRecord>
    var allLocations: Set<Location>
    var labelLookup: [String: Location]
    var typeConflicts: [TypeConflict] = []

//    init(allProcedures: [ProcedureIdentifier], knownRecords: Set<PascalRecord>, allLocations: Set<Location>, labelLookup: [String: Location]) {
//        self.allProcedures = allProcedures
//        self.knownRecords = knownRecords
//        self.allLocations = allLocations
//        self.labelLookup = labelLookup
//    }

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
    
    mutating func generateForInstruction(
        _ inst: Instruction,
        stack: inout StackSimulator,
        loc: Location?
    ) -> String? {
        switch inst.opcode {
        case sto:
            let srcValue = stack.popStackValue()
            let destValue = stack.popStackValue()
            let src = stack.assignmentSourceText(srcValue)
            var destName = stack.assignmentTargetText(destValue)
            let srcType = srcValue.type
            let destType = destValue.type
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
            let srcValue = stack.popStackValue()
            let destValue = stack.popStackValue()
            let src = stack.assignmentSourceText(srcValue)
            let dest = stack.assignmentTargetText(destValue)
            setLocType(src, "STRING")
            setLocType(dest, "STRING")
            return "\(dest) := \(src)"
        case mov:
            let srcValue = stack.popStackValue()
            let dstValue = stack.popStackValue()
            let src = stack.assignmentSourceText(srcValue)
            let dst = stack.assignmentTargetText(dstValue)
            return "\(dst) := \(src)"
        case stp:
            let aValue = stack.popStackValue()
            let (bbit, _) = stack.pop()
            let (bwid, _) = stack.pop()
            let bValue = stack.popStackValue()
            let a = stack.assignmentSourceText(aValue)
            let b = bValue.type == "REAL"
                ? representationBitsText(bValue, width: bwid, bit: bbit, stack: stack)
                : stack.assignmentTargetText(bValue)
            if bValue.type == "REAL" {
                return "\(b) := \(a)"
            }
            return "\(b):\(bwid):\(bbit) := \(a)"
        case stb:
            let srcValue = stack.popStackValue()
            let dstoffsValue = stack.popStackValue()
            let dstaddrValue = stack.popStackValue()
            let src = stack.assignmentSourceText(srcValue, withoutParentheses: true)
            let dstoffs = stack.assignmentSourceText(dstoffsValue)
            let dstaddr = dstaddrValue.type == "REAL"
                ? representationByteText(dstaddrValue, offset: dstoffs, stack: stack)
                : stack.assignmentTargetText(dstaddrValue)
            let dstoffstype = dstoffsValue.type
            let dstaddrtype = dstaddrValue.type
            if dstaddrtype == "STRING" && dstoffstype == "INTEGER" {
                if let offset = Int(dstoffs), offset > 0 {
                    if let ch = Int(src), ch >= 0x20 && ch <= 0x7E {
                        return "\(dstaddr)[\(dstoffs)] := '\(String(format: "%c", ch))'"
                    }
                }
            }
            if dstaddrValue.type == "REAL" {
                return "\(dstaddr) := \(src)"
            }
            return "\(dstaddr)[\(dstoffs)] := \(src)"
        case stm:
            let stmCount = inst.params[0]
            var src: String = ""
            var prevElement: String = ""
            var srcdata: [String] = []
            let (_, t1) = stack.peek()
            let topValue = stack.peekStackValue()
            let nextValue = stack.peekStackValue(1)
            let topRealBase = stack.realRepresentationBaseName(stack.peekStackValue())
            let nextRealBase = stack.realRepresentationBaseName(stack.peekStackValue(1))
            let storesRealRepresentation = topRealBase != nil && topRealBase == nextRealBase
            var storedType: String? = nil
            if stmCount == 2 && (t1 == "REAL" || storesRealRepresentation) {
                (src, _) = stack.popReal()
                storedType = "REAL"
            } else if stmCount == 2,
                (topValue.type == nil || topValue.type == "UNKNOWN"),
                nextValue.isAddressLike
            {
                let srcValue = stack.popStackValue()
                inferStackValueType(srcValue, "REAL", evidence: "STM 2-word source")
                storedType = "REAL"
                src = stack.assignmentSourceText(StackValue(
                    text: srcValue.text,
                    type: "REAL",
                    kind: srcValue.kind,
                    location: srcValue.location,
                    payload: srcValue.payload
                ), withoutParentheses: true)
            } else {
                for _ in 0..<stmCount {
                    let elementValue = stack.popStackValue()
                    let element = stack.assignmentSourceText(elementValue, withoutParentheses: true)
                    let elementParts = element.split(separator: "{")
                    if String(elementParts[0]) != prevElement {
                        prevElement = String(elementParts[0])
                        srcdata.append(String(elementParts[0]))
                    }
                }
                src = srcdata.joined(separator: ", ")
            }
            let dstValue = stack.popStackValue()
            let dst = stack.assignmentTargetText(dstValue)
            let t = dstValue.type
            if storedType == "REAL" {
                setLocType(dstValue.location, "REAL", evidence: "STM 2-word destination")
                setLocType(dst, "REAL", evidence: "STM 2-word destination")
            }
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
            let aValue = stack.popStackValue()
            inferStackValueType(aValue, "INTEGER", evidence: "ADI operand")
            let a = typedOperandText(aValue, "INTEGER", stack: stack)
            let bValue = stack.popStackValue()
            inferStackValueType(bValue, "INTEGER", evidence: "ADI operand")
            let b = typedOperandText(bValue, "INTEGER", stack: stack)
            stack.push(("\(b) + \(a)", "INTEGER"))
            return nil
        case adr:
            let (a, _) = popRealOperand(&stack, evidence: "ADR operand")
            let (b, _) = popRealOperand(&stack, evidence: "ADR operand")
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
            let aValue = stack.popStackValue()
            inferStackValueType(aValue, "INTEGER", evidence: "DVI operand")
            let a = typedOperandText(aValue, "INTEGER", stack: stack)
            let bValue = stack.popStackValue()
            inferStackValueType(bValue, "INTEGER", evidence: "DVI operand")
            let b = typedOperandText(bValue, "INTEGER", stack: stack)
            stack.push(("\(b) DIV \(a)", "INTEGER"))
            return nil
        case dvr:
            let (a, _) = popRealOperand(&stack, evidence: "DVR operand")
            let (b, _) = popRealOperand(&stack, evidence: "DVR operand")
            stack.push(("\(b) / \(a)", "REAL"))
            return nil
        case modi:
            let aValue = stack.popStackValue()
            inferStackValueType(aValue, "INTEGER", evidence: "MODI operand")
            let a = typedOperandText(aValue, "INTEGER", stack: stack)
            let bValue = stack.popStackValue()
            inferStackValueType(bValue, "INTEGER", evidence: "MODI operand")
            let b = typedOperandText(bValue, "INTEGER", stack: stack)
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
            let (a, _) = popRealOperand(&stack, evidence: "MPR operand")
            let (b, _) = popRealOperand(&stack, evidence: "MPR operand")
            stack.push(("\(b) * \(a)", "REAL"))
            return nil
        case ngi:
            let (a, _) = stack.pop("INTEGER")
            setLocType(a, "INTEGER")
            stack.push(("-\(a)", "INTEGER"))
            return nil
        case ngr:
            let (a, _) = popRealOperand(&stack, evidence: "NGR operand")
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
            let (a, _) = popRealOperand(&stack, evidence: "SBR operand")
            let (b, _) = popRealOperand(&stack, evidence: "SBR operand")
            stack.push(("\(b) - \(a)", "REAL"))
            return nil
        case sqi:
            let (a, _) = stack.pop("INTEGER")
            setLocType(a, "INTEGER")
            stack.push(("\(a) * \(a)", "INTEGER"))
            return nil
        case sqr:
            let (a, _) = popRealOperand(&stack, evidence: "SQR operand")
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
            stack.push((String(inst.opcode), "INTEGER"), kind: .constant)
            return nil
        case lao, lae, lda, lla:
            // addresses
            if let loc = inst.memLocation {
                let stackLabel = findStackLabel(loc)
                stack.push(
                    (stackLabel.0, (stackLabel.1 ?? "")),
                    isPointer: true,
                    kind: .address,
                    location: loc
                )
                allLocations.insert(loc)
            }
            return nil
        case ldo, lod, lde, ldl, sldl1...sldl16, sldo1...sldo16:
            if let loc = inst.memLocation {
                stack.push(StackValue(
                    text: findStackLabel(loc).0,
                    type: findStackLabel(loc).1,
                    kind: .value,
                    location: loc
                ))
                allLocations.insert(loc)
            }
            return nil
            
        case ldc:
            let count = inst.params[0]
            for i in (0..<count).reversed() {
                let val = inst.params[1 + i]
                stack.push(("\(val)", "INTEGER"), kind: .constant)
            }
            return nil
        case ldci:
            let val = inst.params[0]
            stack.push(("\(val)", "INTEGER"), kind: .constant)
            return nil
        case ldcn:
            stack.push(("NIL", "POINTER"), kind: .pointer)
            return nil
        case lsa:
            let s = inst.stringParameter ?? ""
            stack.push(("\'\(s)\'", "STRING"), kind: .constant)
            return nil
        case lpa:
            let txtRep = inst.stringParameter ?? ""
            stack.push(("'\(txtRep)'", "PACKED ARRAY"), kind: .constant)
            return nil
        case ldm:
            let ldmCount = inst.params[0]
            let origin = stack.popStackValue()
            let wdOrigin = stack.parenthesizedText(origin)
            for i in 0..<ldmCount {
                if origin.type == "REAL" {
                    stack.push(representationWordValue(origin, offset: i, stack: stack))
                } else {
                    stack.push(StackValue(
                        text: "\(wdOrigin){\(i)}",
                        type: "INTEGER",
                        kind: .value,
                        location: origin.location
                    ))
                }
            }
            return nil
        case ldb:
            let index = stack.popStackValue()
            let base = stack.popStackValue()
            let offset = stack.parenthesizedText(index)
            stack.push(StackValue(
                text: representationByteText(base, offset: offset, stack: stack),
                type: "BYTE",
                kind: .value,
                location: base.type == "REAL" ? nil : base.location
            ))
            return nil
        case ldp:
            let (abit, _) = stack.pop()
            let (awid, _) = stack.pop()
            let base = stack.popStackValue()
            stack.push(StackValue(
                text: representationBitsText(base, width: awid, bit: abit, stack: stack),
                type: "INTEGER",
                kind: .value,
                location: base.type == "REAL" ? nil : base.location
            ))
            return nil
        case inc:
            let val = inst.params[0]
            let base = stack.popStackValue()
            let a = stack.parenthesizedText(base)
            let t = base.type
            let resultKind = stack.derivedAddressKind(from: base)
            if let t = t, t.hasPrefix("ARRAY") {
                stack.push(StackValue(text: "\(a)[\(val)]", type: String(t.split(separator: " ").last!), kind: resultKind, location: base.location))
            } else if let type = t, let structInfo = knownRecords.first(where: { $0.name == type }), let field = structInfo.members[val] {
                stack.push(StackValue(text: "\(a).\(field.name)", type: field.type, kind: resultKind, location: base.location))
            }
            else {
                stack.push(StackValue(text: "\(a) + \(val)", type: t, kind: resultKind, location: base.location))
            }
            return nil
        case ind:
            let val = inst.params[0]
            let base = stack.popStackValue()
            let a = stack.parenthesizedText(base)
            let t = base.type
            if let type = t, let structInfo = knownRecords.first(where: { $0.name == type }), let field = structInfo.members[val] {
                stack.push(StackValue(text: "\(a).\(field.name)", type: field.type, kind: .value, location: base.location))
                return nil
            }
            if base.type == "REAL" {
                stack.push(representationWordValue(base, offset: val, stack: stack))
            } else {
                stack.push(StackValue(
                    text: representationWordText(base, offset: "\(val)", stack: stack),
                    type: "INTEGER",
                    kind: .value,
                    location: base.location
                ))
            }
            return nil
        case ixa:
            let _ = inst.params[0]
            let index = stack.popStackValue()
            let base = stack.popStackValue()
            let eltIndex = stack.parenthesizedText(index)
            let arrayBase = stack.parenthesizedText(base)
            let t = base.type
            let resultKind = stack.derivedAddressKind(from: base)
            if let type = t, type.starts(with: "ARRAY") {
                let elementType = String(type.split(separator: " ").last!)
                stack.push(StackValue(text: "\(arrayBase)[\(eltIndex)]", type: elementType, kind: resultKind, location: base.location))
                return nil
            }
            stack.push(StackValue(text: "\(arrayBase)[\(eltIndex)]", type: t, kind: resultKind, location: base.location))
            return nil
        case ixp:
            let elementsPerWord = inst.params[0]
            let fieldWidth = inst.params[1]
            let idxValue = stack.popStackValue()
            let idx = stack.assignmentSourceText(idxValue)
            let basePtr = stack.popStackValue()
            stack.push(basePtr)
            stack.push(("\(fieldWidth)", "INTEGER"), kind: .constant)
            stack.push(("\(idx)*\(elementsPerWord)", "INTEGER"), kind: .expression)
            return nil
        case ixs:
            let (index, _) = stack.peek()
            setLocType(index, "INTEGER")
            let _ = stack.peek(1)
            let _ = stack.peek(2)
            return nil
        case sind0...sind7:
            let offs = inst.params[0]
            let base = stack.popStackValue()
            let a = stack.parenthesizedText(base)
            let t = base.type
            if let t = t, t.hasPrefix("ARRAY") {
                stack.push(StackValue(text: "\(a)[\(offs)]", type: String(t.split(separator: " ").last!), kind: .value, location: base.location))
            } else if let type = t, let structInfo = knownRecords.first(where: { $0.name == type }), let field = structInfo.members[offs] {
                stack.push(StackValue(text: "\(a).\(field.name)", type: field.type, kind: .value, location: base.location))
            } else {
                if t == "REAL" {
                    stack.push(representationWordValue(base, offset: offs, stack: stack))
                } else {
                    stack.push(StackValue(
                        text: representationWordText(base, offset: "\(offs)", stack: stack),
                        type: t,
                        kind: .value,
                        location: base.location
                    ))
                }
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
            inferRealOperand(stack, evidence: "REAL comparison operand")
            let (a, _) = stack.popReal()
            setLocType(a, dataType, evidence: "REAL comparison operand")
            inferRealOperand(stack, evidence: "REAL comparison operand")
            let (b, _) = stack.popReal()
            setLocType(b, dataType, evidence: "REAL comparison operand")
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
                let value = stack.popStackValue()
                inferStackValueType(value, "CHAR", evidence: "\(called.shortDescription) argument \(called.parameters[i].name)")
                let a = typedOperandText(value, "CHAR", stack: stack)
                if let ch = Int(a), ch >= 0x20 && ch <= 0x7E {
                    aParams.append("'\(String(format: "%c", ch))'")
                } else {
                    aParams.append(a)
                }
                i -= 1
            case "BOOLEAN":
                let value = stack.popStackValue()
                inferStackValueType(value, "BOOLEAN", evidence: "\(called.shortDescription) argument \(called.parameters[i].name)")
                let a = typedOperandText(value, "BOOLEAN", stack: stack)
                if a == "0" {
                    aParams.append("FALSE")
                } else if a == "1" {
                    aParams.append("TRUE")
                } else {
                    aParams.append(a)
                }
                i -= 1
            case "REAL":
                let (a, _) = stack.popReal()
                aParams.append(a)
                setLocType(a, "REAL", evidence: "\(called.shortDescription) argument \(called.parameters[i].name)")
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
                let inferredType = stack.peekStackValue().type ?? called.parameters[i].type
                let topValue = stack.peekStackValue()
                let nextValue = stack.peekStackValue(1)
                if inferredType == "REAL"
                    || (i > 0
                        && isAutoGeneratedParameter(called.parameters[i - 1])
                        && isAutoGeneratedParameter(called.parameters[i])
                        && isRealAggregatePair(topValue, nextValue))
                {
                    if isRealAggregatePair(topValue, nextValue) {
                        inferRealAggregatePairType(
                            topValue,
                            nextValue,
                            evidence: "\(called.shortDescription) inferred REAL argument"
                        )
                    }
                    let (a, _) = stack.popReal()
                    aParams.append(a)
                    if i > 0,
                       isAutoGeneratedParameter(called.parameters[i - 1]),
                       isAutoGeneratedParameter(called.parameters[i]) {
                        _ = called.parameters[i - 1].assignType("REAL", source: .inferred)
                        called.parameters.remove(at: i)
                        i -= 2
                    } else {
                        _ = called.parameters[i].assignType("REAL", source: .inferred)
                        i -= 1
                    }
                    setLocType(a, "REAL", evidence: "\(called.shortDescription) inferred argument")
                } else {
                    let value = stack.popStackValue()
                    let type = called.parameters[i].type
                    if let actualType = value.type,
                       !actualType.isEmpty,
                       actualType != "UNKNOWN",
                       type == "UNKNOWN" {
                        _ = called.parameters[i].assignType(actualType, source: .inferred)
                        inferStackValueType(value, actualType, evidence: "\(called.shortDescription) argument \(called.parameters[i].name)")
                        let a = typedOperandText(value, actualType, stack: stack)
                        aParams.append(a)
                    } else {
                        inferStackValueType(value, type, evidence: "\(called.shortDescription) argument \(called.parameters[i].name)")
                        let a = typedOperandText(value, type, stack: stack)
                        aParams.append(a)
                    }
                    i -= 1
                }
            }
        }

        let callSignature =
            "\(called.shortDescription)(\(aParams.reversed().joined(separator:", ")))"

            if called.isFunction {
            stack.push(StackValue(
                text: callSignature,
                type: called.returnType,
                kind: .expression,
                location: Location(
                    segment: called.segment,
                    procedure: called.procedure,
                    addr: 1
                )
            ))
            return nil
        } else {
            return callSignature
        }
    }
}
