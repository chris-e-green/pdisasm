import Foundation

// MARK: - Stack Simulation and Pseudo-Code Generation
func simulateStackAndGeneratePseudocode(
    proc: Procedure,
    allProcedures: inout [ProcedureIdentifier],
    allLocations: inout Set<Location>
) {
    func handleComparison(
        _ dataType: String,
        _ simulator: inout StackSimulator,
        _ opString: String
    ) {
        if dataType == "SET" {
            let (_, a) = simulator.popSet()
            let (_, b) = simulator.popSet()
            simulator.push(("\(b) \(opString) \(a)", "BOOLEAN"))
        } else {
            let (a, _) = simulator.pop()
            setLocType(a, dataType)
            let (b, _) = simulator.pop()
            setLocType(b, dataType)
            simulator.push(("\(b) \(opString) \(a)", "BOOLEAN"))
        }
    }

    /// Integer/char comparison helper shared by equi, geqi, grti, leqi, lesi, neqi.
    /// Pops two values, detects CHAR vs INTEGER, and pushes a BOOLEAN result.
    func handleIntegerComparison(
        _ simulator: inout StackSimulator,
        _ opString: String
    ) {
        var (a, ta) = simulator.pop()
        var (b, tb) = simulator.pop()
        if ta == "CHAR" || tb == "CHAR" {
            setLocType(a, "CHAR")
            a = chkCharType(a)
            setLocType(b, "CHAR")
            b = chkCharType(b)
        } else {
            setLocType(a, "INTEGER")
            setLocType(b, "INTEGER")
        }
        simulator.push(("\(b) \(opString) \(a)", "BOOLEAN"))
    }

    func setLocType(_ locStr: String, _ type: String) {
        // if the location is a memory reference, set the type.
        if locStr.contains(/^S[0-9]*_P[0-9]*_L[0-9]*_A/) {
            // convert string location to Location
            let l = Location(from: locStr)
            // find in allLocations and set type
            allLocations.first(where: { $0 == l })?.type = type
        }
    }
    
    func chkCharType(_ loc:String) -> String {
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

    // by using strings, we can store and manipulate symbolic data rather than just locations/ints
    var flagForEnd: [(Int, Int)] = []
    let indentLevel = 1
    var ujpToSkipSet: Set<Int> = Set<Int>()
    var ujpCaseDest: Set<Int> = Set<Int>()
    var ujpCaseDefaultDest: Set<Int> = Set<Int>()

    proc.entryPoints.insert(proc.enterIC)
    proc.entryPoints.insert(proc.exitIC)

    // Build lookup dictionaries for O(1) access instead of O(n) linear searches
    var procLookup: [String: ProcedureIdentifier] = [:]
    for p in allProcedures {
        let key = "\(p.segment):\(p.procedure)"
        procLookup[key] = p
    }

    var labelLookup: [String: Location] = [:]
    for label in allLocations {
        let key =
            "\(label.segment):\(label.procedure ?? -1):\(label.addr ?? -1)"
        labelLookup[key] = label
    }

    // Initialize components for clean separation of concerns
    var simulator = StackSimulator()
    let pseudoGen = PseudoCodeGenerator(
        procLookup: procLookup,
        labelLookup: labelLookup,
        allLocations: allLocations
    )

    // Alias for backward compatibility during refactoring
    var currentStack: [String] {
        get { simulator.stack }
        set { simulator.stack = newValue }
    }

    // Helper to lookup label by Location
    func findStackLabel(_ loc: Location) -> (String, String?) {
        let key = "\(loc.segment):\(loc.procedure ?? -1):\(loc.addr ?? -1)"
        if let ll = labelLookup[key] {
            return (ll.displayName, ll.displayType)
        } else {
            return (loc.displayName, loc.displayType)
        }
    }

    let sortedInstructions = proc.instructions.sorted(by: { $0.key < $1.key })
    var flagForLabel: Set<Int> = Set<Int>()

    for idx in sortedInstructions.indices {
        let (address, inst) = sortedInstructions[idx]
        // Process stack effects and build instruction using decoded information
        var pseudoCode: String? = nil  // Set by specific opcodes that generate assignments/control flow

        // Apply stack operations and generate pseudo-code based on mnemonic
        switch inst.opcode {
        case sldc0...sldc127:
            simulator.push((String(inst.opcode), "INTEGER"))
        case abi:
            // Absolute value of integer (TOS)
            let (a, _) = simulator.pop("INTEGER")
            setLocType(a, "INTEGER")
            simulator.push(("ABI(\(a))", "INTEGER"))
        case abr:
            // Absolute value of real (TOS)
            let (a, _) = simulator.popReal()
            simulator.pushReal("ABR(\(a))")
        case adi:
            // Add integers (TOS + TOS-1)
            let (a, _) = simulator.pop("INTEGER")
            setLocType(a, "INTEGER")
            let (b, _) = simulator.pop("INTEGER")
            setLocType(b, "INTEGER")
            simulator.push(("\(b) + \(a)", "INTEGER"))
        case adr:
            // Add reals (TOS + TOS-1)
            let (a, _) = simulator.popReal()
            let (b, _) = simulator.popReal()
            simulator.pushReal("\(a) + \(b)")
        case land:
            // Logical AND (TOS & TOS-1)
            let (a, _) = simulator.pop("BOOLEAN")
            setLocType(a, "BOOLEAN")
            let (b, _) = simulator.pop("BOOLEAN")
            setLocType(b, "BOOLEAN")
            simulator.push(("\(b) AND \(a)", "BOOLEAN"))
        case dif:
            // Set difference (TOS-1 AND NOT TOS)
            let (set1Len, set1) = simulator.popSet()
            let (set2Len, set2) = simulator.popSet()
            let maxLen = max(set1Len, set2Len)
            for i in 0..<maxLen {
                simulator.push(("(\(set2) AND NOT \(set1)){\(i)}", "SET"))
            }
            simulator.push(("\(maxLen)", "INTEGER"))
        case dvi:
            // Divide integers (TOS-1 / TOS)
            let (a, _) = simulator.pop("INTEGER")
            setLocType(a, "INTEGER")
            let (b, _) = simulator.pop("INTEGER")
            setLocType(b, "INTEGER")
            simulator.push(("\(b) / \(a)", "INTEGER"))
        case dvr:
            // Divide reals (TOS-1 / TOS)
            let (a, _) = simulator.popReal()
            let (b, _) = simulator.popReal()
            simulator.pushReal("\(b) / \(a)")
        case chk:
            // Check subrange (TOS-1 <= TOS-2 <= TOS)
            let _ = simulator.pop()
            let _ = simulator.pop()
            let c = simulator.pop()
            simulator.push(c)
        case flo:
            // Float next to TOS (int TOS-1 to real TOS)
            let a = simulator.pop()  // TOS
            let (b, _) = simulator.pop()  // TOS-1
            setLocType(b, "INTEGER")
            simulator.push(a)  // put previous TOS back
            simulator.pushReal(b)  // real(TOS-1)->TOS
        case flt:
            // Float TOS (int TOS to real TOS)
            let (a, _) = simulator.pop("INTEGER")
            setLocType(a, "INTEGER")
            simulator.pushReal(a)
        case inn:
            // Set membership (TOS-1 in set TOS)
            let (_, set) = simulator.popSet()
            let (chk, _) = simulator.pop()
            simulator.push(("\(chk) IN \(set)", "BOOLEAN"))
        case int:
            // Set intersection (TOS AND TOS-1)
            let (set1Len, set1) = simulator.popSet()
            let (set2Len, set2) = simulator.popSet()
            let maxLen = max(set1Len, set2Len)
            for i in 0..<maxLen {
                simulator.push(("(\(set1) AND \(set2)){\(i)}", "SET"))
            }
            simulator.push(("\(maxLen)", "INTEGER"))
        case lor:
            // Logical OR (TOS | TOS-1)
            let (a, _) = simulator.pop("BOOLEAN")
            setLocType(a, "BOOLEAN")
            let (b, _) = simulator.pop("BOOLEAN")
            setLocType(b, "BOOLEAN")
            simulator.push(("\(b) OR \(a)", "BOOLEAN"))
        case modi:
            // Modulo integers (TOS-1 % TOS)
            let (a, _) = simulator.pop("INTEGER")
            setLocType(a, "INTEGER")
            let (b, _) = simulator.pop("INTEGER")
            setLocType(b, "INTEGER")
            simulator.push(("\(b) % \(a)", "INTEGER"))
        case mpi:
            // Multiply integers (TOS * TOS-1)
            let (a, _) = simulator.pop("INTEGER")
            setLocType(a, "INTEGER")
            let (b, _) = simulator.pop("INTEGER")
            setLocType(b, "INTEGER")
            simulator.push(("\(b) * \(a)", "INTEGER"))
        case mpr:
            // Multiply reals (TOS * TOS-1)
            let (a, _) = simulator.popReal()
            let (b, _) = simulator.popReal()
            simulator.pushReal("\(b) * \(a)")
        case ngi:
            // Negate integer
            let (a, _) = simulator.pop("INTEGER")
            setLocType(a, "INTEGER")
            simulator.push(("-\(a)", "INTEGER"))
        case ngr:
            // Negate real
            let (a, _) = simulator.popReal()
            simulator.pushReal("-\(a)")
        case lnot:
            // Logical NOT (~TOS)
            let (a, _) = simulator.pop("BOOLEAN")
            setLocType(a, "BOOLEAN")
            simulator.push(("NOT \(a)", "BOOLEAN"))
        case srs:
            // Subrange set [TOS-1..TOS] (creates set on stack)
            let (a, _) = simulator.pop()
            let (b, _) = simulator.pop()
            if let av = Int(a) {
                let wordsRequired = (av + 1) % 16
                for i in 0..<wordsRequired {
                    simulator.push(("(\(b)..\(a)){\(i)}", "SET"))
                }
                simulator.push(("\(wordsRequired)", "INTEGER"))
            } else {
                // fudge... no way to know how big it will be!
                simulator.push(("\(b)..\(a)", "SET"))
                simulator.push(("1", "INTEGER"))
            }
        case sbi:
            // Subtract integers (TOS-1 - TOS)
            let (a, _) = simulator.pop("INTEGER")
            setLocType(a, "INTEGER")
            let (b, _) = simulator.pop("INTEGER")
            setLocType(b, "INTEGER")
            simulator.push(("\(b) - \(a)", "INTEGER"))
        case sbr:
            // Subtract reals (TOS-1 - TOS)
            let (a, _) = simulator.popReal()
            let (b, _) = simulator.popReal()
            simulator.pushReal("\(b) - \(a)")
        case sgs:
            // Build singleton set [TOS]
            let (a, _) = simulator.pop("INTEGER")
            if let av = Int(a) {
                let wordsRequired = (av + 1) % 16
                for i in 0..<wordsRequired {
                    simulator.push(("(\(a)){\(i)}", "SET"))
                }
                simulator.push(("\(wordsRequired)", "INTEGER"))
            } else {
                simulator.push(("[\(a)]", "SET"))
                simulator.push(("1", "INTEGER"))
            }
        case sqi:
            // Square integer (TOS * TOS)
            let (a, _) = simulator.pop("INTEGER")
            setLocType(a, "INTEGER")
            simulator.push(("\(a) * \(a)", "INTEGER"))
        case sqr:
            // Square real (TOS * TOS)
            let (a, _) = simulator.popReal()
            simulator.pushReal("\(a) * \(a)")
        case sto:
            // Store indirect word (TOS into TOS-1)
            pseudoCode = pseudoGen.generateForInstruction(
                inst,
                stack: &simulator,
                loc: nil
            )
        case ixs:
            // Index string array (check 1 <= TOS <= len of str byte ptr TOS-1)
            _ = simulator.pop()  // discard index
            _ = simulator.pop()  // discard byte ptr offset
            _ = simulator.pop()  // discard byte ptr base
        case uni:
            // Set union (TOS OR TOS-1)
            let (set1Len, set1) = simulator.popSet()
            let (set2Len, set2) = simulator.popSet()
            let maxLen = max(set1Len, set2Len)
            for i in 0..<maxLen {
                simulator.push(("(\(set1) OR \(set2)){\(i)}", "SET"))
            }
            simulator.push(("\(maxLen)", "INTEGER"))
        case lde:
            // Load extended word (pushes value onto stack)
            if let loc = inst.memLocation {
                simulator.push(findStackLabel(loc))
                allLocations.insert(loc)
            }
        case csp:
            // Call standard procedure
            let procNum = inst.params[0]
            if let (cspName, parms, returnType) = cspProcs[procNum] {
                var callParms: [String] = []
                for p in parms {
                    var parm: String = ""
                    if p.type == "REAL" {
                        (parm, _) = simulator.popReal()
                    } else {
                        (parm, _) = simulator.pop(p.type)
                        setLocType(parm, p.type)
                    }
                    callParms.append(parm)
                }
                // If there is a return value, push it onto the stack because it will be used
                // by subsequent instructions.
                if !returnType.isEmpty {
                    if returnType == "REAL" {
                        simulator.pushReal(
                            "\(cspName)(\(callParms.reversed().joined(separator:", ")))"
                        )
                    } else {
                        simulator.push(
                            (
                                "\(cspName)(\(callParms.reversed().joined(separator:", ")))",
                                returnType
                            )
                        )
                    }
                } else {
                    // no return value so just generate pseudo-code
                    pseudoCode =
                        "\(cspName)(\(callParms.reversed().joined(separator:", ")))"

                }
            }
        case ldcn:
            simulator.push(("NIL", "POINTER"))
        case adj:
            // Adjust set to count words (expanding or compressing), discard length and push set data
            let count = inst.params[0]
            let (_, set) = simulator.popSet()
            for i in 0..<count {
                simulator.push(("\(set){\(i)}", "INTEGER"))
            }
            simulator.push(("\(count)", "INTEGER"))
        case fjp:
            // False jump to addr (implements IF, WHILE and the UNTIL part of REPEAT/UNTIL)
            let dest = inst.params[0]
            var (cond, condType) = simulator.pop("BOOLEAN", true)
            if condType != "BOOLEAN" {
                // if it wasn't a boolean, most likely to actually to have been a call to ODD()
                cond = "ODD(\(cond))"
            }
            if dest > address {  // jumping forward so an IF
                if let targetIdx = sortedInstructions.firstIndex(where: {
                    $0.key == dest
                }) {
                    let prevIdx = sortedInstructions.index(before: targetIdx)
                    if prevIdx >= sortedInstructions.startIndex {
                        let prev = sortedInstructions[prevIdx]
                        // check if the previous instruction is an unconditional jump,
                        if prev.value.opcode == ujp {
                            // if it's forward it's likely an IF/ELSE
                            if prev.value.params[0] > prev.key {
                                let elseDest = prev.value.params[0]
                                if let elseEndIdx =
                                    sortedInstructions.firstIndex(where: {
                                        $0.key == elseDest
                                    })
                                {
                                    sortedInstructions[elseEndIdx].value
                                        .prePseudoCode.append(
                                            "END (* ELSE \(cond) *)"
                                        )
                                }
                                pseudoCode = "IF \(cond) THEN BEGIN"
                                sortedInstructions[targetIdx].value
                                    .prePseudoCode.append(
                                        "END ELSE BEGIN"
                                    )
                                ujpToSkipSet.insert(prevIdx)
                            } else {
                                // WHILE
                                pseudoCode = "WHILE \(cond) DO BEGIN"
                                sortedInstructions[targetIdx].value
                                    .prePseudoCode.append(
                                        "END (* WHILE \(cond) *)"
                                    )
                                ujpToSkipSet.insert(prevIdx)
                            }

                        } else {
                            // likely an IF without ELSE
                            sortedInstructions[targetIdx].value.prePseudoCode
                                .append("END (* IF \(cond) *)")
                            flagForEnd.append((dest, indentLevel))
                            pseudoCode = "IF \(cond) THEN BEGIN"
                        }
                    }
                }
            } else {  // jumping backwards so a REPEAT/UNTIL
                if let targetIdx = sortedInstructions.firstIndex(where: {
                    $0.key == dest
                }) {
                    sortedInstructions[targetIdx].value.prePseudoCode.append(
                        "REPEAT"
                    )
                    pseudoCode = "UNTIL \(cond)"
                }
            }
            proc.entryPoints.insert(dest)
        case inc:
            // Inc field ptr (TOS+val)
            let val = inst.params[0]
            let (a, _) = simulator.pop()
            simulator.push(("\(a) + \(val)", "POINTER"))
        case ind:
            // Static index and load word (TOS+val)
            let val = inst.params[0]
            let (a, _) = simulator.pop()
            simulator.push(("\(a) + \(val)", "INTEGER"))
        case ixa:
            // Index array (TOS * element size + TOS-1)
            let _ = inst.params[0]  // Element size, used for address calculation but not in pseudo-code
            let (eltIndex, _) = simulator.pop()
            let (arrayBase, _) = simulator.pop()
            simulator.push(("\(arrayBase)[\(eltIndex)]", "POINTER"))
        case lao:
            // Load global address
            if let loc = inst.memLocation {
                simulator.push(findStackLabel(loc))
                allLocations.insert(loc)
            }
        case lsa:
            // Load string address
            let s = inst.stringParameter ?? ""
            simulator.push(("\'\(s)\'", "STRING"))
        case lae:
            // Load extended address
            if let loc = inst.memLocation {
                simulator.push(findStackLabel(loc))
                allLocations.insert(loc)
            }
        case mov:
            // Move words from TOS to TOS-1
            pseudoCode = pseudoGen.generateForInstruction(
                inst,
                stack: &simulator,
                loc: nil
            )
        case ldo:
            // Load global word
            if let loc = inst.memLocation {
                simulator.push(findStackLabel(loc))
                allLocations.insert(loc)
            }
        case sas:
            // String assign
            pseudoCode = pseudoGen.generateForInstruction(
                inst,
                stack: &simulator,
                loc: nil
            )
        case sro:
            // Store global word
            if let loc = inst.memLocation {
                allLocations.insert(loc)
                pseudoCode = pseudoGen.generateForInstruction(
                    inst,
                    stack: &simulator,
                    loc: loc
                )
            }
        case xjp:
            pseudoCode = "END (* CASE *)"
        case cip, cbp, cxp, clp, cgp:
            // Call procedure (intermediate, base, external, local, global)
            if let loc = inst.destination {
                pseudoCode = pseudoGen.handleCallProcedure(
                    loc,
                    stack: &simulator
                )
            }
        case eql:
            // Equal (TOS-1 = TOS)
            handleComparison(inst.comparatorDataType, &simulator, "=")
        case geq:
            // Greater than or equal (TOS-1 >= TOS)
            handleComparison(inst.comparatorDataType, &simulator, ">=")
        case grt:
            // Greater than (TOS-1 > TOS)
            handleComparison(inst.comparatorDataType, &simulator, ">")
        case lda:
            // Load address
            if let loc = inst.memLocation {
                simulator.push(findStackLabel(loc))
                allLocations.insert(loc)
            }
        case ldc:
            // Load multiple-word constant
            let count = inst.params[0]
            for i in (0..<count).reversed() {  // words are in reverse order
                let val = inst.params[1 + i]
                simulator.push(("\(val)", "INTEGER"))
            }
        case leq:
            // Less than or equal (TOS-1 <= TOS)
            handleComparison(inst.comparatorDataType, &simulator, "<=")
        case les:
            // Less than (TOS-1 < TOS)
            handleComparison(inst.comparatorDataType, &simulator, "<")
        case lod:
            // Load intermediate word
            if let loc = inst.memLocation {
                simulator.push(findStackLabel(loc))
                allLocations.insert(loc)
            }
        case neq:
            // Not equal (TOS-1 <> TOS)
            handleComparison(inst.comparatorDataType, &simulator, "<>")
        case str:
            // Store TOS
            if let loc = inst.memLocation {
                pseudoCode = pseudoGen.generateForInstruction(
                    inst,
                    stack: &simulator,
                    loc: loc
                )
                allLocations.insert(loc)
            }
        case ujp:
            if ujpToSkipSet.contains(idx) {
                // This UJP was already handled as part of an IF/ELSE structure
                break
            }
            if ujpCaseDest.contains(inst.params[0])
                || ujpCaseDefaultDest.contains(inst.params[0])
            {
                // This UJP is part of a CASE structure
                pseudoCode = "END (* CASE n *)"
                break
            }
            // Unconditional jump
            let dest = inst.params[0]
            // check the destination to see if it's forward, and pointing to an XJP (a CASE)
            if dest > address,
                let targetIdx = sortedInstructions.firstIndex(where: {
                    $0.key == dest
                })
            {
                let target = sortedInstructions[targetIdx]
                if target.value.opcode == xjp {
                    let (index, _) = simulator.pop()  // get the case index value
                    pseudoCode = "CASE \(index) OF"
                    // it's a case.
                    let low = target.value.params[0]
                    let high = target.value.params[1]
                    let defLoc = target.value.params[2]
                    ujpCaseDefaultDest.insert(defLoc)
                    let defAddr = target.value.params[3]
                    ujpCaseDest.insert(defAddr)
                    var addrToCaseValue: [Int: [Int]] = [:]
                    // go through them once to group by destination
                    for caseValue in low...high {
                        // get the destination for this case
                        let cDestAddr = target.value.params[
                            4 + (caseValue - low)
                        ]
                        if addrToCaseValue[cDestAddr] == nil {
                            addrToCaseValue[cDestAddr] = []
                        }
                        addrToCaseValue[cDestAddr]?.append(caseValue)
                    }
                    for (cDestAddr, caseValues) in addrToCaseValue {
                        var caseLabel: [String] = []
                        var caseValues = caseValues.sorted()
                        while !caseValues.isEmpty {
                            let first = caseValues.first!  // we can force unwrap as we checked above
                            // group consecutive values
                            let group = caseValues.prefix(while: {
                                $0 == caseValues.first!
                                    + (caseValues.firstIndex(of: $0)!)
                                    - (caseValues.firstIndex(of: first)!)
                            })
                            // if the group has only one value, add it as is
                            if group.count == 1 {
                                caseLabel.append("\(group[0])")
                            } else {
                                // otherwise, add it as a range
                                caseLabel.append(
                                    "\(group.first!)...\(group.last!)"
                                )
                            }
                            // remove the processed values from the caseValues
                            caseValues = Array(
                                caseValues.dropFirst(group.count)
                            )
                        }
                        if let cDest = sortedInstructions.firstIndex(where: {
                            $0.key == cDestAddr
                        }) {
                            sortedInstructions[cDest].value.prePseudoCode
                                .append(
                                    "\(caseLabel.joined(separator: ", ")): BEGIN"
                                )
                        }

                    }

                    break
                }
            }
            if dest > address {  // jumping forward so an IF
                pseudoCode = "GOTO LAB\(dest)"
            } else {
                // jumping backwards, likely a loop - probably a while.
                pseudoCode = "GOTO LAB\(dest)"
            }
            flagForLabel.insert(dest)
            proc.entryPoints.insert(dest)
        case ldp:
            // Load packed field (TOS)
            let (abit, _) = simulator.pop()
            let (awid, _) = simulator.pop()
            let (a, _) = simulator.pop()
            simulator.push(("\(a):\(awid):\(abit)", "INTEGER"))
        case stp:
            // Store packed field (TOS into TOS-1)
            pseudoCode = pseudoGen.generateForInstruction(
                inst,
                stack: &simulator,
                loc: nil
            )
        case ldm:
            // Load multiple words (pushes onto stack)
            let ldmCount = inst.params[0]
            let (wdOrigin, _) = simulator.pop()
            for i in 0..<ldmCount {
                simulator.push(("\(wdOrigin){\(i)}", "INTEGER"))
            }
        case stm:
            // Store multiple words (pops from stack)
            pseudoCode = pseudoGen.generateForInstruction(
                inst,
                stack: &simulator,
                loc: nil
            )
        case ldb:
            // Load byte at byte ptr TOS-1 + TOS
            let (a, _) = simulator.pop()
            let (b, _) = simulator.pop()
            simulator.push(("\(b)[\(a)]", "BYTE"))
        case stb:
            // Store byte at byte ptr TOS-1 + TOS
            pseudoCode = pseudoGen.generateForInstruction(
                inst,
                stack: &simulator,
                loc: nil
            )
        case ixp:
            // Index packed array TOS-1[TOS]
            let elementsPerWord = inst.params[0]
            let fieldWidth = inst.params[1]
            let (idx, _) = simulator.pop()
            let basePtr = simulator.pop()
            simulator.push(basePtr)
            simulator.push(("\(fieldWidth)", "INTEGER"))
            simulator.push(("\(idx)*\(elementsPerWord)", "INTEGER"))
        case equi:
            handleIntegerComparison(&simulator, "=")
        case geqi:
            handleIntegerComparison(&simulator, ">=")
        case grti:
            handleIntegerComparison(&simulator, ">")
        case leqi:
            handleIntegerComparison(&simulator, "<=")
        case lesi:
            handleIntegerComparison(&simulator, "<")
        case neqi:
            handleIntegerComparison(&simulator, "<>")
        case lla:
            // Load local address
            if let loc = inst.memLocation {
                simulator.push(findStackLabel(loc))
                allLocations.insert(loc)
            }
        case ldci:
            // Load one-word constant
            let val = inst.params[0]
            simulator.push(("\(val)", "INTEGER"))
        case ldl:
            // Load local word
            if let loc = inst.memLocation {
                simulator.push(findStackLabel(loc))
                allLocations.insert(loc)
            }
        case stl:
            // Store TOS into local address
            if let loc = inst.memLocation {
                allLocations.insert(loc)
                pseudoCode = pseudoGen.generateForInstruction(
                    inst,
                    stack: &simulator,
                    loc: loc
                )
            }
        case lpa:
            // Load packed array
            let txtRep = inst.stringParameter ?? ""
            simulator.push(("'\(txtRep)'", "PACKED ARRAY"))
        case ste:
            // Store extended word (TOS into word at address)
            if let loc = inst.memLocation {
                allLocations.insert(loc)
                pseudoCode = pseudoGen.generateForInstruction(
                    inst,
                    stack: &simulator,
                    loc: loc
                )
            }
        case sldl1...sldl16:
            // Short load local word
            if let loc = inst.memLocation {
                simulator.push(findStackLabel(loc))
                allLocations.insert(loc)
            }
        case sldo1...sldo16:
            // Short load global word
            if let loc = inst.memLocation {
                simulator.push(findStackLabel(loc))
                allLocations.insert(loc)
            }
        case sind0...sind7:
            // Short index load (word *TOS+offset)
            let offs = inst.params[0]
            let (a, _) = simulator.pop()
            simulator.push(("*(\(a) + \(offs))", "POINTER"))
        default:
            break
        }

        inst.pseudoCode = pseudoCode
        inst.stackState = currentStack
    }

    flagForLabel.forEach {
        proc.instructions[$0]?.prePseudoCode.append(
            "LAB\($0):"
        )
    }
}
