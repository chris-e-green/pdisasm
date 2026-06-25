import Foundation

// MARK: - Control Flow Analyzer

/// Analyzes control-flow opcodes (fjp, ujp, xjp) and annotates instructions
/// with pseudo-code for IF/ELSE, WHILE, REPEAT/UNTIL, CASE, and GOTO constructs.
struct ControlFlowAnalyzer {
    var ujpToSkipSet: Set<Int> = []
    var ujpCaseDest: Set<Int> = []
    var ujpCaseDefaultDest: Set<Int> = []
    var flagForLabel: Set<Int> = []
    var pseudoCodeAddressesToSkip: Set<Int> = []

    private enum ForLoopDirection {
        case to
        case downto

        var keyword: String {
            switch self {
            case .to: return "TO"
            case .downto: return "DOWNTO"
            }
        }
    }

    private struct ForLoopMatch {
        let variable: String
        let start: String
        let limit: String
        let direction: ForLoopDirection
        let updateAddress: Int
        let setupAddresses: Set<Int>
    }

    /// Processes a control-flow instruction and returns the pseudo-code string (if any).
    ///
    /// - Parameters:
    ///   - inst: The instruction to process.
    ///   - address: The address of the current instruction.
    ///   - idx: The index of the current instruction in `sortedInstructions`.
    ///   - sortedInstructions: The sorted instruction list (may be mutated for prePseudoCode).
    ///   - simulator: The stack simulator (used by ujp/CASE to pop the case index).
    ///   - proc: The procedure being analyzed (for entryPoints).
    /// - Returns: The pseudo-code string, or nil if none.
    mutating func processInstruction(
        _ inst: Instruction,
        address: Int,
        idx: Int,
        sortedInstructions: [(key: Int, value: Instruction)],
        simulator: inout StackSimulator,
        proc: Procedure
    ) -> String? {
        switch inst.opcode {
        case fjp:
            return handleFJP(
                inst, address: address,
                sortedInstructions: sortedInstructions,
                simulator: &simulator, proc: proc
            )
        case xjp:
            return "END (* CASE *)"
        case ujp:
            return handleUJP(
                inst, address: address, idx: idx,
                sortedInstructions: sortedInstructions,
                simulator: &simulator, proc: proc
            )
        default:
            return nil
        }
    }

    // MARK: - FJP (False Jump)

    private mutating func handleFJP(
        _ inst: Instruction,
        address: Int,
        sortedInstructions: [(key: Int, value: Instruction)],
        simulator: inout StackSimulator,
        proc: Procedure
    ) -> String? {
        let dest = inst.params[0]
        var (cond, condType) = simulator.pop("BOOLEAN", true)
        if condType != "BOOLEAN" {
            cond = "ODD(\(cond))"
        }
        var pseudoCode: String? = nil
        if dest > address {  // jumping forward so an IF
            if let targetIdx = sortedInstructions.firstIndex(where: {
                $0.key == dest
            }) {
                let prevIdx = sortedInstructions.index(before: targetIdx)
                if prevIdx >= sortedInstructions.startIndex {
                    let prev = sortedInstructions[prevIdx]
                    if prev.value.opcode == ujp {
                        if prev.value.params[0] > prev.key
                            && !hasSharedUjpTarget(
                                prev.value.params[0],
                                sortedInstructions: sortedInstructions
                            )
                        {
                            // IF/ELSE
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
                            if prev.value.params[0] < prev.key,
                                let forLoop = detectForLoop(
                                condition: cond,
                                loopStart: prev.value.params[0],
                                updateStoreIdx: prevIdx - 1,
                                sortedInstructions: sortedInstructions
                            ) {
                                pseudoCode =
                                    "FOR \(forLoop.variable) := \(forLoop.start) \(forLoop.direction.keyword) \(forLoop.limit) DO BEGIN"
                                pseudoCodeAddressesToSkip.insert(forLoop.updateAddress)
                                pseudoCodeAddressesToSkip.formUnion(forLoop.setupAddresses)
                                sortedInstructions[targetIdx].value
                                    .prePseudoCode.append(
                                        "END (* FOR \(forLoop.variable) := \(forLoop.start) \(forLoop.direction.keyword) \(forLoop.limit) *)"
                                    )
                                ujpToSkipSet.insert(prevIdx)
                            } else if prev.value.params[0] < prev.key {
                                pseudoCode = "WHILE \(cond) DO BEGIN"
                                sortedInstructions[targetIdx].value
                                    .prePseudoCode.append(
                                        "END (* WHILE \(cond) *)"
                                    )
                                ujpToSkipSet.insert(prevIdx)
                            } else {
                                sortedInstructions[targetIdx].value
                                    .prePseudoCode.append(
                                        "END (* IF \(cond) *)"
                                    )
                                pseudoCode = "IF \(cond) THEN BEGIN"
                            }
                        }
                    } else {
                        // IF without ELSE
                        sortedInstructions[targetIdx].value.prePseudoCode
                            .append("END (* IF \(cond) *)")
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
        return pseudoCode
    }

    private func hasSharedUjpTarget(
        _ target: Int,
        sortedInstructions: [(key: Int, value: Instruction)]
    ) -> Bool {
        sortedInstructions.filter {
            $0.value.opcode == ujp && $0.value.params.first == target
        }.count > 1
    }

    private func detectForLoop(
        condition: String,
        loopStart: Int,
        updateStoreIdx: Int,
        sortedInstructions: [(key: Int, value: Instruction)]
    ) -> ForLoopMatch? {
        guard sortedInstructions.indices.contains(updateStoreIdx),
            updateStoreIdx >= 3
        else {
            return nil
        }

        let updateStore = sortedInstructions[updateStoreIdx]
        guard isDirectStore(updateStore.value.opcode),
            let loopVariable = updateStore.value.memLocation
        else {
            return nil
        }

        let arithmetic = sortedInstructions[updateStoreIdx - 1]
        let constant = sortedInstructions[updateStoreIdx - 2]
        let variableLoad = sortedInstructions[updateStoreIdx - 3]

        let direction: ForLoopDirection
        switch arithmetic.value.opcode {
        case adi:
            direction = .to
        case sbi:
            direction = .downto
        default:
            return nil
        }

        guard isOneConstant(constant.value),
            isDirectLoad(variableLoad.value.opcode),
            variableLoad.value.memLocation == loopVariable
        else {
            return nil
        }

        let variableName = loopVariable.displayName
        guard var limit = forLoopLimit(
            from: condition,
            variableName: variableName,
            direction: direction
        ), let startAssignment = forLoopAssignment(
            variableName: variableName,
            loopStart: loopStart,
            sortedInstructions: sortedInstructions
        ) else {
            return nil
        }

        var setupAddresses: Set<Int> = [startAssignment.address]
        if let foldedLimit = forLoopFoldedLimitAssignment(
            variableName: limit,
            loopStart: loopStart,
            sortedInstructions: sortedInstructions
        ) {
            limit = foldedLimit.value
            setupAddresses.insert(foldedLimit.address)
        }

        return ForLoopMatch(
            variable: variableName,
            start: startAssignment.value,
            limit: limit,
            direction: direction,
            updateAddress: updateStore.key,
            setupAddresses: setupAddresses
        )
    }

    private func isDirectLoad(_ opcode: UInt8) -> Bool {
        switch opcode {
        case ldo, lod, lde, ldl, sldl1...sldl16, sldo1...sldo16:
            return true
        default:
            return false
        }
    }

    private func isDirectStore(_ opcode: UInt8) -> Bool {
        switch opcode {
        case sro, str, stl, ste:
            return true
        default:
            return false
        }
    }

    private func isOneConstant(_ instruction: Instruction) -> Bool {
        switch instruction.opcode {
        case 1:
            return true
        case ldci:
            return instruction.params.first == 1
        default:
            return false
        }
    }

    private func forLoopLimit(
        from condition: String,
        variableName: String,
        direction: ForLoopDirection
    ) -> String? {
        let operatorText = direction == .to ? " <= " : " >= "
        let parts = condition.components(separatedBy: operatorText)
        guard parts.count == 2,
            parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                == variableName
        else {
            return nil
        }
        return parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func forLoopAssignment(
        variableName: String,
        loopStart: Int,
        sortedInstructions: [(key: Int, value: Instruction)]
    ) -> (value: String, address: Int)? {
        for (address, instruction) in sortedInstructions.reversed()
            where address < loopStart
        {
            guard isDirectStore(instruction.opcode),
                instruction.memLocation?.displayName == variableName,
                let pseudoCode = instruction.pseudoCode
            else {
                continue
            }
            let assignmentPrefix = "\(variableName) := "
            guard pseudoCode.hasPrefix(assignmentPrefix) else {
                return nil
            }
            return (
                String(pseudoCode.dropFirst(assignmentPrefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                address
            )
        }
        return nil
    }

    private func forLoopFoldedLimitAssignment(
        variableName: String,
        loopStart: Int,
        sortedInstructions: [(key: Int, value: Instruction)]
    ) -> (value: String, address: Int)? {
        guard let assignment = forLoopAssignment(
            variableName: variableName,
            loopStart: loopStart,
            sortedInstructions: sortedInstructions
        ), Int(assignment.value) != nil
            || assignment.value.contains("[")
            || assignment.value.hasPrefix("LENGTH(")
        else {
            return nil
        }
        return assignment
    }

    // MARK: - UJP (Unconditional Jump)

    private mutating func handleUJP(
        _ inst: Instruction,
        address: Int,
        idx: Int,
        sortedInstructions: [(key: Int, value: Instruction)],
        simulator: inout StackSimulator,
        proc: Procedure
    ) -> String? {
        if ujpToSkipSet.contains(idx) {
            return nil
        }
        if ujpCaseDest.contains(inst.params[0])
            || ujpCaseDefaultDest.contains(inst.params[0])
        {
            return "END (* CASE n *)"
        }
        let dest = inst.params[0]
        if dest > address,
            let targetIdx = sortedInstructions.firstIndex(where: {
                $0.key == dest
            })
        {
            let target = sortedInstructions[targetIdx]
            if target.value.opcode == xjp {
                let (index, _) = simulator.pop()
                let low = target.value.params[0]
                let high = target.value.params[1]
                let defLoc = target.value.params[2]
                ujpCaseDefaultDest.insert(defLoc)
                let defAddr = target.value.params[3]
                ujpCaseDest.insert(defAddr)
                var addrToCaseValue: [Int: [Int]] = [:]
                for caseValue in low...high {
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
                        let first = caseValues.first!
                        let group = caseValues.prefix(while: {
                            $0 == caseValues.first!
                                + (caseValues.firstIndex(of: $0)!)
                                - (caseValues.firstIndex(of: first)!)
                        })
                        if group.count == 1 {
                            caseLabel.append("\(group[0])")
                        } else {
                            caseLabel.append(
                                "\(group.first!)..\(group.last!)"
                            )
                        }
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
                flagForLabel.insert(dest)
                proc.entryPoints.insert(dest)
                return "CASE \(index) OF"
            }
        }
        if dest > address {
            flagForLabel.insert(dest)
            proc.entryPoints.insert(dest)
            return "GOTO LAB\(dest)"
        } else {
            flagForLabel.insert(dest)
            proc.entryPoints.insert(dest)
            return "GOTO LAB\(dest)"
        }
    }
}
