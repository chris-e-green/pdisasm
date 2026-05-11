import Foundation

// MARK: - Control Flow Analyzer

/// Analyzes control-flow opcodes (fjp, ujp, xjp) and annotates instructions
/// with pseudo-code for IF/ELSE, WHILE, REPEAT/UNTIL, CASE, and GOTO constructs.
struct ControlFlowAnalyzer {
    var ujpToSkipSet: Set<Int> = []
    var ujpCaseDest: Set<Int> = []
    var ujpCaseDefaultDest: Set<Int> = []
    var flagForLabel: Set<Int> = []

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
                        if prev.value.params[0] > prev.key {
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
                            // WHILE
                            pseudoCode = "WHILE \(cond) DO BEGIN"
                            sortedInstructions[targetIdx].value
                                .prePseudoCode.append(
                                    "END (* WHILE \(cond) *)"
                                )
                            ujpToSkipSet.insert(prevIdx)
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
                                "\(group.first!)...\(group.last!)"
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
