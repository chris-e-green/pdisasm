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

public enum StructuredLoopRegionKind: Hashable, Sendable {
    case whileLoop
    case repeatUntilLoop
}

public struct StructuredLoopRegion: Hashable, Sendable {
    public let kind: StructuredLoopRegionKind
    public let headerBlock: Int
    public let conditionBlock: Int
    public let bodyBlocks: Set<Int>
    public let continuationBlock: Int
    public let backEdges: Set<ControlFlowEdge>
    public let exitEdges: Set<ControlFlowEdge>
    public let continueEdges: Set<ControlFlowEdge>

    public init(
        kind: StructuredLoopRegionKind,
        headerBlock: Int,
        conditionBlock: Int,
        bodyBlocks: Set<Int>,
        continuationBlock: Int,
        backEdges: Set<ControlFlowEdge>,
        exitEdges: Set<ControlFlowEdge>,
        continueEdges: Set<ControlFlowEdge>
    ) {
        self.kind = kind
        self.headerBlock = headerBlock
        self.conditionBlock = conditionBlock
        self.bodyBlocks = bodyBlocks
        self.continuationBlock = continuationBlock
        self.backEdges = backEdges
        self.exitEdges = exitEdges
        self.continueEdges = continueEdges
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

    public func loopRegions() -> [StructuredLoopRegion] {
        naturalLoops()
            .compactMap(loopRegion)
            .sorted {
                if $0.headerBlock != $1.headerBlock {
                    return $0.headerBlock < $1.headerBlock
                }
                return $0.conditionBlock < $1.conditionBlock
            }
    }

    private struct NaturalLoop {
        let header: Int
        let blocks: Set<Int>
        let backEdges: Set<ControlFlowEdge>
    }

    private func naturalLoops() -> [NaturalLoop] {
        let backEdges = graph.edges.filter { edge in
            guard let destination = edge.destination else { return false }
            return graph.dominates(destination, block: edge.source)
        }
        var blocksByHeader: [Int: Set<Int>] = [:]
        var edgesByHeader: [Int: Set<ControlFlowEdge>] = [:]
        for edge in backEdges {
            guard let header = edge.destination else { continue }
            blocksByHeader[header, default: []].formUnion(
                naturalLoopBlocks(from: edge.source, to: header)
            )
            edgesByHeader[header, default: []].insert(edge)
        }
        return blocksByHeader.map { header, blocks in
            NaturalLoop(
                header: header,
                blocks: blocks,
                backEdges: edgesByHeader[header] ?? []
            )
        }
    }

    private func naturalLoopBlocks(from tail: Int, to header: Int) -> Set<Int> {
        var blocks: Set<Int> = [header, tail]
        var pending = tail == header ? [] : [tail]
        while let block = pending.popLast() {
            for predecessor in graph.predecessors(of: block) {
                guard blocks.insert(predecessor).inserted else { continue }
                if predecessor != header {
                    pending.append(predecessor)
                }
            }
        }
        return blocks
    }

    private func loopRegion(_ loop: NaturalLoop) -> StructuredLoopRegion? {
        guard graph.externalEntryBlocks.intersection(loop.blocks).isEmpty,
            hasSingleEntry(loop)
        else {
            return nil
        }

        if let branch = graph.conditionalControlFlow(from: loop.header),
            loop.blocks.contains(branch.trueBlock),
            !loop.blocks.contains(branch.falseBlock)
        {
            return makeLoopRegion(
                kind: .whileLoop,
                loop: loop,
                conditionBlock: loop.header,
                continuationBlock: branch.falseBlock
            )
        }

        let repeatConditions = loop.blocks.compactMap { block -> ConditionalControlFlow? in
            guard let branch = graph.conditionalControlFlow(from: block),
                branch.falseBlock == loop.header,
                !loop.blocks.contains(branch.trueBlock)
            else {
                return nil
            }
            return branch
        }
        guard repeatConditions.count == 1, let condition = repeatConditions.first else {
            return nil
        }
        return makeLoopRegion(
            kind: .repeatUntilLoop,
            loop: loop,
            conditionBlock: condition.conditionBlock,
            continuationBlock: condition.trueBlock
        )
    }

    private func hasSingleEntry(_ loop: NaturalLoop) -> Bool {
        for block in loop.blocks where block != loop.header {
            if !graph.predecessors(of: block).subtracting(loop.blocks).isEmpty {
                return false
            }
        }
        return true
    }

    private func makeLoopRegion(
        kind: StructuredLoopRegionKind,
        loop: NaturalLoop,
        conditionBlock: Int,
        continuationBlock: Int
    ) -> StructuredLoopRegion {
        let exitEdges = Set(
            graph.edges.filter { edge in
                guard loop.blocks.contains(edge.source),
                    let destination = edge.destination
                else {
                    return false
                }
                return !loop.blocks.contains(destination)
            }
        )
        let continueTarget = conditionBlock
        let continueEdges = Set(
            graph.edges.filter { edge in
                guard loop.blocks.contains(edge.source),
                    edge.destination == continueTarget
                else {
                    return false
                }
                return edge.kind == .unconditionalBranch
            }
        )
        return StructuredLoopRegion(
            kind: kind,
            headerBlock: loop.header,
            conditionBlock: conditionBlock,
            bodyBlocks: loop.blocks.subtracting([conditionBlock]),
            continuationBlock: continuationBlock,
            backEdges: loop.backEdges,
            exitEdges: exitEdges,
            continueEdges: continueEdges
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
