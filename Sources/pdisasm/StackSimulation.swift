import Foundation

// MARK: - Stack Simulation and Pseudo-Code Generation
@discardableResult
func simulateStackAndGeneratePseudocode(
    proc: Procedure,
    knownRecords: Set<PascalRecord>,
    typeAliases: [String: String] = [:],
    scalarTypes: [String: PascalScalarType] = [:],
    allProcedures: inout [ProcedureIdentifier],
    allLocations: inout Set<Location>,
    diagnostics: DiagnosticCollector? = nil
) -> [TypeConflict] {
    proc.entryPoints.insert(proc.enterIC)
    proc.entryPoints.insert(proc.exitIC)

    var simulator = StackSimulator(diagnostics: diagnostics)
    var pseudoGen = PseudoCodeGenerator(
        allProcedures: allProcedures,
        knownRecords: knownRecords,
        typeAliases: typeAliases,
        scalarTypes: scalarTypes,
        allLocations: allLocations
    )
    var controlFlow = ControlFlowAnalyzer()

    for instruction in proc.instructions.values {
        instruction.pseudoCode = nil
        instruction.pseudoCodeStatement = nil
        instruction.stackState = nil
        instruction.prePseudoCode.removeAll()
        instruction.forLoopEvidence = nil
    }

    let sortedInstructions = proc.instructions.sorted(by: { $0.key < $1.key })

    for idx in sortedInstructions.indices {
        let (address, inst) = sortedInstructions[idx]
        var pseudoCode: String? = nil
        var pseudoCodeStatement: PseudoCodeStatement? = nil

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
            pseudoCodeStatement = pseudoCode.map {
                PseudoCodeStatement(renderedText: $0, locations: pseudoGen.allLocations)
            }
        default:
            pseudoCodeStatement = pseudoGen.generateStatementForInstruction(
                inst,
                stack: &simulator,
                loc: nil
            )
            pseudoCode = pseudoCodeStatement?.renderedText
            if controlFlow.pseudoCodeAddressesToSkip.contains(address) {
                pseudoCodeStatement = nil
                pseudoCode = nil
            }
        }

        inst.pseudoCodeStatement = pseudoCodeStatement
        inst.pseudoCode = pseudoCode
        inst.stackState = simulator.stackDescription
    }

    for address in controlFlow.pseudoCodeAddressesToSkip {
        proc.instructions[address]?.pseudoCodeStatement = nil
        proc.instructions[address]?.pseudoCode = nil
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
