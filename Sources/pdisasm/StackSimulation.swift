import Foundation

// MARK: - Stack Simulation and Pseudo-Code Generation
@discardableResult
func simulateStackAndGeneratePseudocode(
    proc: Procedure,
    knownRecords: Set<PascalRecord>,
    allProcedures: inout [ProcedureIdentifier],
    allLocations: inout Set<Location>
) -> [TypeConflict] {
    proc.entryPoints.insert(proc.enterIC)
    proc.entryPoints.insert(proc.exitIC)

    var simulator = StackSimulator()
    var pseudoGen = PseudoCodeGenerator(
        allProcedures: allProcedures,
        knownRecords: knownRecords,
        allLocations: allLocations
    )
    var controlFlow = ControlFlowAnalyzer()

    let sortedInstructions = proc.instructions.sorted(by: { $0.key < $1.key })

    for idx in sortedInstructions.indices {
        let (address, inst) = sortedInstructions[idx]
        var pseudoCode: String? = nil

        switch inst.opcode {
        case fjp, ujp, xjp:
            pseudoCode = controlFlow.processInstruction(
                inst,
                address: address,
                idx: idx,
                sortedInstructions: sortedInstructions,
                simulator: &simulator,
                proc: proc
            )
        default:
            pseudoCode = pseudoGen.generateForInstruction(
                inst,
                stack: &simulator,
                loc: nil
            )
        }

        inst.pseudoCode = pseudoCode
        inst.stackState = simulator.stackDescription
    }

    // Write back location mutations from the pseudo-code generator
    allLocations = pseudoGen.allLocations

    controlFlow.flagForLabel.forEach {
        proc.instructions[$0]?.prePseudoCode.append(
            "LAB\($0):"
        )
    }

    return pseudoGen.typeConflicts
}
