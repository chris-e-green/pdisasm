import Foundation

public extension DisassemblyRunResult {
    func patchingComment(_ comment: DisassemblyComment) -> (result: DisassemblyRunResult, patchedNodes: [DocumentNodeID]) {
        let patch = document.patchingComment(comment)
        let patchedResult = DisassemblyRunResult(
            legacyResult: legacyResult.patchingComment(comment),
            snapshot: snapshot,
            document: patch.document,
            indexes: DocumentIndexes.buildPatched(document: patch.document),
            report: report
        )
        return (patchedResult, patch.patchedNodes)
    }
}

extension DisassemblyResult {
    func patchingComment(_ comment: DisassemblyComment) -> DisassemblyResult {
        guard let procedure = comment.procedure,
              let codeSegment = codeSegments[comment.segment],
              let targetProcedure = codeSegment.procedures.first(where: { $0.identifier?.procedure == procedure }),
              let instruction = targetProcedure.instructions[comment.addr]
        else {
            return self
        }

        let trimmed = comment.comment.trimmingCharacters(in: .whitespacesAndNewlines)
        instruction.userComment = trimmed.isEmpty ? nil : trimmed
        return self
    }
}

extension DocumentIndexes {
    static func buildPatched(document: DisassemblyDocument) -> DocumentIndexes {
        var procedureNodes: [ProcedureID: DocumentNodeID] = [:]
        var locationNodes: [LocationID: [DocumentNodeID]] = [:]
        var instructionNodes: [InstructionID: DocumentNodeID] = [:]
        var symbolNodes: [String: [DocumentNodeID]] = [:]
        var searchIndex: [String: [DocumentNodeID]] = [:]

        for node in document.nodes {
            let line = node.line
            if let reference = document.sourceMap[node.id] {
                if let procedureID = reference.procedureID, line.anchor != nil {
                    procedureNodes[procedureID] = node.id
                }
                if let locationID = reference.locationID {
                    locationNodes[locationID, default: []].append(node.id)
                }
                if let instructionID = reference.instructionID {
                    instructionNodes[instructionID] = instructionNodes[instructionID] ?? node.id
                }
            }
            for token in line.text.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" }) {
                let key = String(token).uppercased()
                symbolNodes[key, default: []].append(node.id)
                searchIndex[key, default: []].append(node.id)
            }
            for word in line.text.split(whereSeparator: { $0.isWhitespace }) {
                searchIndex[String(word).uppercased(), default: []].append(node.id)
            }
        }

        return DocumentIndexes(
            procedureNodes: procedureNodes,
            locationNodes: locationNodes,
            instructionNodes: instructionNodes,
            symbolNodes: symbolNodes,
            searchIndex: searchIndex.mapValues { Array(Set($0)).sorted { $0.description < $1.description } }
        )
    }
}
