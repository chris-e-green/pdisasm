import Foundation

// MARK: - Pseudo-code Generator

/// Generates high-level pseudo-code from decoded instructions and stack states
struct PseudoCodeGenerator {
    let allProcedures: [ProcedureIdentifier]
    let knownRecords: Set<PascalRecord>
    let typeAliases: [String: String]
    let scalarTypes: [String: PascalScalarType]
    var allLocations: Set<Location>
    var labelLookup: [String: Location]
    var typeConflicts: [TypeConflict] = []

//    init(allProcedures: [ProcedureIdentifier], knownRecords: Set<PascalRecord>, allLocations: Set<Location>, labelLookup: [String: Location]) {
//        self.allProcedures = allProcedures
//        self.knownRecords = knownRecords
//        self.allLocations = allLocations
//        self.labelLookup = labelLookup
//    }

    init(
        allProcedures: [ProcedureIdentifier],
        knownRecords: Set<PascalRecord>,
        typeAliases: [String: String] = [:],
        scalarTypes: [String: PascalScalarType] = [:],
        allLocations: Set<Location>
    ) {
        self.allProcedures = allProcedures
        self.knownRecords = knownRecords
        self.typeAliases = typeAliases
        self.scalarTypes = scalarTypes
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
        generateStatementForInstruction(inst, stack: &stack, loc: loc)?.renderedText
    }

    mutating func generateStatementForInstruction(
        _ inst: Instruction,
        stack: inout StackSimulator,
        loc: Location?
    ) -> PseudoCodeStatement? {
        if let assignment = generateAssignmentStatement(for: inst, stack: &stack) {
            return assignment
        }

        return generateRenderedInstruction(inst, stack: &stack, loc: loc)
            .map(PseudoCodeStatement.rendered)
    }

    private mutating func generateRenderedInstruction(
        _ inst: Instruction,
        stack: inout StackSimulator,
        loc: Location?
    ) -> String? {
        switch inst.opcode {
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
                    if let ch = Int(src) {
                        return "\(destName) := \(renderPascalCharLiteral(ch))"
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
                    var (src, _) = stack.pop(true)
                    src = scalarLiteralText(src, destinationType: destType)
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
            let rhs = stack.popSetValue()
            let lhs = stack.popSetValue()
            stack.pushSetValue(lhs.difference(rhs))
            return nil
        case inn:
            let set = stack.popSetValue()
            let (chkVal, chkType) = stack.pop()
            let elementType = chkType == "CHAR" ? "CHAR" : "INTEGER"
            setLocType(chkVal, elementType)
            stack.push(("\(chkVal) IN \(formatSetMembership(set.sourceText, elementType: elementType))", "BOOLEAN"))
            return nil
        case int:
            let rhs = stack.popSetValue()
            let lhs = stack.popSetValue()
            stack.pushSetValue(lhs.intersection(rhs))
            return nil
        case uni:
            let rhs = stack.popSetValue()
            let lhs = stack.popSetValue()
            stack.pushSetValue(lhs.union(rhs))
            return nil
        case srs:
            let (a, _) = stack.pop()
            let (b, _) = stack.pop()
            let wordsRequired = Int(a).map { ($0 / 16) + 1 } ?? 1
            stack.pushSetValue(PascalSetValue.literal([
                PascalSetElement(lower: b, upper: a)
            ], wordCount: wordsRequired))
            return nil
        case sgs:
            let (a, _) = stack.pop("INTEGER", true)
            let wordsRequired = Int(a).map { ($0 / 16) + 1 } ?? 1
            stack.pushSetValue(PascalSetValue.literal([
                PascalSetElement(a)
            ], wordCount: wordsRequired))
            return nil
        case adj:
            let count = inst.params[0]
            let set = stack.popSetValue()
            if count == 1 {
                // special case where only one word is needed to represent the set, so we can just push the set itself without the word index
                stack.push((set.sourceText, "INTEGER"))
            } else {
                for i in 0..<count {
                    stack.push(("\(set.sourceText){\(i)}", "INTEGER"))
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
            stack.push(("'\(txtRep)'", "PACKED ARRAY OF CHAR"), kind: .constant)
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
            let baseType = resolveType(base.type)
            if baseType == "STRING" && offset == "0" {
                stack.push(StackValue(
                    text: "LENGTH(\(stack.parenthesizedText(base)))",
                    type: "INTEGER",
                    kind: .value,
                    location: base.location
                ))
                return nil
            }
            let byteText = byteAccessText(base, offset: offset, stack: stack)
            stack.push(StackValue(
                text: byteText,
                type: byteAccessType(for: baseType),
                kind: .value,
                location: baseType == "REAL" ? nil : base.location
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
            let t = resolveType(base.type)
            let resultKind = stack.derivedAddressKind(from: base)
            if let arrayType = resolvedArrayType(for: t) {
                let index = mapArrayIndex(
                    arrayType,
                    opcodeContext: "INC",
                    elementStride: nil,
                    rawIndex: "\(val)"
                )
                stack.push(StackValue(text: "\(a)[\(index.text)]", type: arrayType.elementType.renderedType, kind: resultKind, location: base.location))
            } else if let structInfo = recordDefinition(for: t), let field = structInfo.members[val] {
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
            let t = resolveType(base.type)
            if let structInfo = recordDefinition(for: t), let field = structInfo.members[val] {
                stack.push(StackValue(text: "\(a).\(field.name)", type: field.type, kind: .value, location: base.location))
                return nil
            }
            if base.type == "REAL" {
                stack.push(representationWordValue(base, offset: val, stack: stack))
            } else {
                stack.push(StackValue(
                    text: representationWordText(base, offset: "\(val)", stack: stack),
                    type: dereferencedType(base.type) ?? "INTEGER",
                    kind: .value,
                    location: base.location
                ))
            }
            return nil
        case ixa:
            let elementStride = inst.params[0]
            let index = stack.popStackValue()
            let base = stack.popStackValue()
            let eltIndex = stack.parenthesizedText(index)
            let arrayBase = stack.parenthesizedText(base)
            let t = resolveType(base.type)
            let resultKind = stack.derivedAddressKind(from: base)
            if let arrayType = resolvedArrayType(for: t) {
                let index = mapArrayIndex(
                    arrayType,
                    opcodeContext: "IXA",
                    elementStride: elementStride,
                    rawIndex: eltIndex
                )
                stack.push(StackValue(text: "\(arrayBase)[\(index.text)]", type: arrayType.elementType.renderedType, kind: resultKind, location: base.location))
                return nil
            }
            stack.push(StackValue(
                text: indexedValueText(base: arrayBase, index: eltIndex, baseType: t),
                type: indexedValueType(index: eltIndex, baseType: t),
                kind: resultKind,
                location: base.location
            ))
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
            let t = resolveType(base.type)
            if let arrayType = resolvedArrayType(for: t) {
                let index = mapArrayIndex(
                    arrayType,
                    opcodeContext: "SIND",
                    elementStride: nil,
                    rawIndex: "\(offs)"
                )
                stack.push(StackValue(text: "\(a)[\(index.text)]", type: arrayType.elementType.renderedType, kind: .value, location: base.location))
            } else if let structInfo = recordDefinition(for: t), let field = structInfo.members[offs] {
                stack.push(StackValue(text: "\(a).\(field.name)", type: field.type, kind: .value, location: base.location))
            } else {
                if t == "REAL" {
                    stack.push(representationWordValue(base, offset: offs, stack: stack))
                } else {
                    stack.push(StackValue(
                        text: representationWordText(base, offset: "\(offs)", stack: stack),
                        type: dereferencedType(t) ?? t,
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
            let a = stack.popSetValue()
            let b = stack.popSetValue()
            stack.push(("\(b.sourceText) \(opString) \(a.sourceText)", "BOOLEAN"))
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
            return renderPascalCharLiteral(ch)
        } else {
            return loc
        }
    }

    private func indexedValueText(base: String, index: String, baseType: String?) -> String {
        if resolveType(baseType) == "STRING" && index == "0" {
            return "LENGTH(\(base))"
        }
        return "\(base)[\(index)]"
    }

    private func indexedValueType(index: String, baseType: String?) -> String? {
        let baseType = resolveType(baseType)
        if baseType == "STRING" {
            return index == "0" ? "INTEGER" : "CHAR"
        }
        return arrayElementType(for: baseType) ?? baseType
    }

    private func dereferencedType(_ type: String?) -> String? {
        guard let type = resolveType(type), type.hasPrefix("^") else {
            return nil
        }
        let pointee = type.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
        return pointee.isEmpty ? nil : resolveType(pointee)
    }

    private func recordDefinition(for type: String?) -> PascalRecord? {
        guard let type = resolveType(type) else { return nil }
        return knownRecords.first { $0.name == type }
    }

    func recordField(at offset: Int, for type: String?) -> Identifier? {
        recordDefinition(for: type)?.members[offset]
    }

    private func resolveType(_ type: String?) -> String? {
        guard let type else { return nil }
        var current = type.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        var seen: Set<String> = []
        while let resolved = typeAliases[current], !seen.contains(current) {
            seen.insert(current)
            current = resolved.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }
        return current
    }

    func resolvePascalType(_ type: String?) -> PascalType? {
        guard let resolved = resolveType(type) else { return nil }
        return PascalType.parse(resolved)
    }

    func resolvedArrayType(for type: String?) -> PascalArrayType? {
        guard case .array(let arrayType) = resolvePascalType(type) else {
            return nil
        }
        return arrayType
    }

    func arrayElementType(for type: String?) -> String? {
        resolvedArrayType(for: type)?.elementType.renderedType
    }

    func isPackedCharArray(_ type: String?) -> Bool {
        guard let arrayType = resolvedArrayType(for: type) else {
            return false
        }
        return arrayType.isPacked && arrayType.elementType.renderedType == "CHAR"
    }

    func isStringLikeArray(_ type: String?) -> Bool {
        isPackedCharArray(type)
    }

    func stringLikeAssignmentType(for type: String?) -> String {
        if let resolved = resolveType(type),
           isStringLikeArray(resolved) {
            return resolved
        }
        return "STRING"
    }

    func byteAccessText(_ base: StackValue, offset: String, stack: StackSimulator) -> String {
        if base.type == "REAL" {
            return representationByteText(base, offset: offset, stack: stack)
        }
        if resolvedArrayType(for: base.type) != nil {
            return "BYTE_AT(\(stack.parenthesizedText(base)), \(offset))"
        }
        return representationByteText(base, offset: offset, stack: stack)
    }

    func byteAccessType(for type: String?) -> String {
        if resolveType(type) == "STRING" {
            return "CHAR"
        }
        if let arrayType = resolvedArrayType(for: type),
           arrayType.isPacked,
           arrayType.elementType.renderedType == "CHAR" {
            return "CHAR"
        }
        return "BYTE"
    }

    struct ArrayIndexMapping {
        var text: String
        var fallbackComment: String?
    }

    func mapArrayIndex(
        _ arrayType: PascalArrayType,
        opcodeContext: String,
        elementStride: Int?,
        rawIndex: String
    ) -> ArrayIndexMapping {
        let trimmedIndex = rawIndex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard arrayType.indexTypes.count == 1 else {
            return ArrayIndexMapping(
                text: arrayIndexFallbackText(
                    trimmedIndex,
                    comment: "\(opcodeContext) linear index for \(PascalType.array(arrayType).renderedType)"
                ),
                fallbackComment: "linear index for multidimensional array"
            )
        }

        guard case .subrange(let bounds) = arrayType.indexTypes[0] else {
            return ArrayIndexMapping(
                text: arrayIndexFallbackText(
                    trimmedIndex,
                    comment: "\(opcodeContext) index for \(arrayType.indexTypes[0].renderedType)"
                ),
                fallbackComment: "non-subrange array index type"
            )
        }

        guard let lowerBound = Int(bounds.lowerBound) else {
            return ArrayIndexMapping(
                text: arrayIndexFallbackText(
                    trimmedIndex,
                    comment: "\(opcodeContext) index for \(bounds.lowerBound)..\(bounds.upperBound)"
                ),
                fallbackComment: "symbolic lower bound"
            )
        }

        if lowerBound == 0 {
            return ArrayIndexMapping(text: trimmedIndex, fallbackComment: nil)
        }

        if let constantIndex = Int(trimmedIndex) {
            return ArrayIndexMapping(text: "\(constantIndex + lowerBound)", fallbackComment: nil)
        }

        let adjusted = "\(parenthesizeIndexExpression(trimmedIndex)) + \(lowerBound)"
        return ArrayIndexMapping(text: adjusted, fallbackComment: nil)
    }

    private func arrayIndexFallbackText(_ index: String, comment: String) -> String {
        "\(index) (* \(comment) *)"
    }

    private func parenthesizeIndexExpression(_ index: String) -> String {
        let operatorFragments = [" + ", " - ", " * ", " / ", " DIV ", " MOD "]
        if operatorFragments.contains(where: { index.uppercased().contains($0) }) {
            return "(\(index))"
        }
        return index
    }

    func scalarLiteralText(_ source: String, destinationType: String?) -> String {
        guard let resolvedType = resolveType(destinationType),
              let scalarType = scalarTypes[resolvedType],
              let value = Int(source.trimmingCharacters(in: .whitespacesAndNewlines)),
              let caseName = scalarType.namesByValue[value]
        else {
            return source
        }
        return caseName
    }

    private func formatSetMembership(_ set: String, elementType: String) -> String {
        guard elementType == "CHAR",
            set.hasPrefix("["),
            set.hasSuffix("]")
        else {
            return set
        }

        let body = set.dropFirst().dropLast()
        let elements = body.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let formatted = elements.map { element in
            let rangeParts = element.contains("...")
                ? element.components(separatedBy: "...")
                : element.components(separatedBy: "..")
            if rangeParts.count == 2,
                let lower = Int(rangeParts[0]),
                let upper = Int(rangeParts[1])
            {
                return "\(charLiteral(lower))..\(charLiteral(upper))"
            }
            if let value = Int(element) {
                return charLiteral(value)
            }
            return element
        }
        return "[" + formatted.joined(separator: ", ") + "]"
    }

    private func charLiteral(_ value: Int) -> String {
        renderPascalCharLiteral(value)
    }

}
