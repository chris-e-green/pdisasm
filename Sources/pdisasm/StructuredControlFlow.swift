public enum StructuredControlFlowRegionKind: Hashable, Sendable {
    case ifThen
    case ifThenElse
}

public struct StructuredControlFlowRegion: Hashable, Sendable {
    public let kind: StructuredControlFlowRegionKind
    public let conditionBlock: Int
    public let thenBlocks: Set<Int>
    public let elseBlocks: Set<Int>
    public let continuationBlock: Int

    public init(
        kind: StructuredControlFlowRegionKind,
        conditionBlock: Int,
        thenBlocks: Set<Int>,
        elseBlocks: Set<Int>,
        continuationBlock: Int
    ) {
        self.kind = kind
        self.conditionBlock = conditionBlock
        self.thenBlocks = thenBlocks
        self.elseBlocks = elseBlocks
        self.continuationBlock = continuationBlock
    }
}

public struct StructuredControlFlowAnalyzer {
    public let graph: ControlFlowGraph

    public init(graph: ControlFlowGraph) {
        self.graph = graph
    }

    public init(procedure: Procedure) {
        self.init(graph: ControlFlowGraph(procedure: procedure))
    }

    public func conditionalRegions() -> [StructuredControlFlowRegion] {
        graph.blocks.keys.sorted().compactMap(conditionalRegion)
    }

    public func conditionalRegion(
        at conditionBlock: Int
    ) -> StructuredControlFlowRegion? {
        guard let branch = graph.conditionalControlFlow(from: conditionBlock),
            let continuation = graph.immediatePostDominator(of: conditionBlock),
            continuation != conditionBlock
        else {
            return nil
        }

        if branch.falseBlock == continuation {
            guard branch.trueBlock != continuation,
                let thenBlocks = armBlocks(
                    from: branch.trueBlock,
                    conditionBlock: conditionBlock,
                    continuationBlock: continuation
                ),
                validateArm(
                    thenBlocks,
                    conditionBlock: conditionBlock,
                    continuationBlock: continuation
                )
            else {
                return nil
            }
            return StructuredControlFlowRegion(
                kind: .ifThen,
                conditionBlock: conditionBlock,
                thenBlocks: thenBlocks,
                elseBlocks: [],
                continuationBlock: continuation
            )
        }

        guard branch.trueBlock != continuation,
            let thenBlocks = armBlocks(
                from: branch.trueBlock,
                conditionBlock: conditionBlock,
                continuationBlock: continuation
            ),
            let elseBlocks = armBlocks(
                from: branch.falseBlock,
                conditionBlock: conditionBlock,
                continuationBlock: continuation
            ),
            !thenBlocks.isEmpty,
            !elseBlocks.isEmpty,
            thenBlocks.isDisjoint(with: elseBlocks),
            validateArm(
                thenBlocks,
                conditionBlock: conditionBlock,
                continuationBlock: continuation
            ),
            validateArm(
                elseBlocks,
                conditionBlock: conditionBlock,
                continuationBlock: continuation
            )
        else {
            return nil
        }

        return StructuredControlFlowRegion(
            kind: .ifThenElse,
            conditionBlock: conditionBlock,
            thenBlocks: thenBlocks,
            elseBlocks: elseBlocks,
            continuationBlock: continuation
        )
    }

    private func armBlocks(
        from start: Int,
        conditionBlock: Int,
        continuationBlock: Int
    ) -> Set<Int>? {
        if start == continuationBlock {
            return []
        }
        var visited: Set<Int> = []
        var pending = [start]
        while let block = pending.popLast() {
            if block == continuationBlock {
                continue
            }
            guard block != conditionBlock,
                graph.blocks[block] != nil,
                graph.dominates(conditionBlock, block: block),
                !graph.externalEntryBlocks.contains(block)
            else {
                return nil
            }
            guard visited.insert(block).inserted else { continue }
            pending.append(contentsOf: graph.successors(of: block))
        }
        return visited
    }

    private func validateArm(
        _ blocks: Set<Int>,
        conditionBlock: Int,
        continuationBlock: Int
    ) -> Bool {
        guard !blocks.isEmpty else { return false }
        var reachesContinuation = false
        for block in blocks {
            let outsidePredecessors = graph.predecessors(of: block)
                .subtracting(blocks)
                .subtracting([conditionBlock])
            guard outsidePredecessors.isEmpty else { return false }

            let outgoing = graph.successors(of: block)
            let outsideSuccessors = outgoing
                .subtracting(blocks)
                .subtracting([continuationBlock])
            guard outsideSuccessors.isEmpty else { return false }
            if outgoing.contains(continuationBlock) {
                reachesContinuation = true
            }
        }
        return reachesContinuation
    }
}
