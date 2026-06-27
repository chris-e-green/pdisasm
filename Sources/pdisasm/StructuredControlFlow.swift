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
    public let structuralBackEdge: ControlFlowEdge
    public let backEdges: Set<ControlFlowEdge>
    public let exitEdges: Set<ControlFlowEdge>
    public let continueEdges: Set<ControlFlowEdge>

    public init(
        kind: StructuredLoopRegionKind,
        headerBlock: Int,
        conditionBlock: Int,
        bodyBlocks: Set<Int>,
        continuationBlock: Int,
        structuralBackEdge: ControlFlowEdge,
        backEdges: Set<ControlFlowEdge>,
        exitEdges: Set<ControlFlowEdge>,
        continueEdges: Set<ControlFlowEdge>
    ) {
        self.kind = kind
        self.headerBlock = headerBlock
        self.conditionBlock = conditionBlock
        self.bodyBlocks = bodyBlocks
        self.continuationBlock = continuationBlock
        self.structuralBackEdge = structuralBackEdge
        self.backEdges = backEdges
        self.exitEdges = exitEdges
        self.continueEdges = continueEdges
    }
}

public enum GotoFallbackReason: Hashable, Sendable {
    case irreducible
    case loopExit
    case loopContinue
}

public struct GotoFallback: Hashable, Sendable {
    public let edge: ControlFlowEdge
    public let reason: GotoFallbackReason

    public init(edge: ControlFlowEdge, reason: GotoFallbackReason) {
        self.edge = edge
        self.reason = reason
    }
}

public enum StructuredForDirection: Hashable, Sendable {
    case to
    case downto
}

public struct StructuredForVariable: Hashable, Sendable {
    public let segment: Int
    public let procedure: Int?
    public let lexicalLevel: Int?
    public let address: Int?
    public let name: String

    public init(
        segment: Int,
        procedure: Int?,
        lexicalLevel: Int?,
        address: Int?,
        name: String
    ) {
        self.segment = segment
        self.procedure = procedure
        self.lexicalLevel = lexicalLevel
        self.address = address
        self.name = name
    }

    init(_ location: Location) {
        self.init(
            segment: location.segment,
            procedure: location.procedure,
            lexicalLevel: location.lexLevel,
            address: location.addr,
            name: location.displayName
        )
    }
}

public struct StructuredForRegion: Hashable, Sendable {
    public let direction: StructuredForDirection
    public let variable: StructuredForVariable
    public let loop: StructuredLoopRegion
    public let initializationStoreAddress: Int
    public let setupAddresses: Set<Int>
    public let startExpression: String
    public let limitExpression: String
    public let comparisonAddress: Int
    public let updateStoreAddress: Int

    public init(
        direction: StructuredForDirection,
        variable: StructuredForVariable,
        loop: StructuredLoopRegion,
        initializationStoreAddress: Int,
        setupAddresses: Set<Int>,
        startExpression: String,
        limitExpression: String,
        comparisonAddress: Int,
        updateStoreAddress: Int
    ) {
        self.direction = direction
        self.variable = variable
        self.loop = loop
        self.initializationStoreAddress = initializationStoreAddress
        self.setupAddresses = setupAddresses
        self.startExpression = startExpression
        self.limitExpression = limitExpression
        self.comparisonAddress = comparisonAddress
        self.updateStoreAddress = updateStoreAddress
    }
}

public struct StructuredCaseArm: Hashable, Sendable {
    public let values: Set<Int>
    public let entryBlock: Int
    public let blocks: Set<Int>

    public init(values: Set<Int>, entryBlock: Int, blocks: Set<Int>) {
        self.values = values
        self.entryBlock = entryBlock
        self.blocks = blocks
    }
}

public struct StructuredCaseRegion: Hashable, Sendable {
    public let dispatchBlock: Int
    public let selectorExpression: String?
    public let gatewayBlock: Int?
    public let arms: [StructuredCaseArm]
    public let defaultEntryBlock: Int
    public let defaultBlocks: Set<Int>
    public let continuationBlock: Int

    public init(
        dispatchBlock: Int,
        selectorExpression: String? = nil,
        gatewayBlock: Int? = nil,
        arms: [StructuredCaseArm],
        defaultEntryBlock: Int,
        defaultBlocks: Set<Int>,
        continuationBlock: Int
    ) {
        self.dispatchBlock = dispatchBlock
        self.selectorExpression = selectorExpression
        self.gatewayBlock = gatewayBlock
        self.arms = arms
        self.defaultEntryBlock = defaultEntryBlock
        self.defaultBlocks = defaultBlocks
        self.continuationBlock = continuationBlock
    }
}

public struct StructuredControlFlowAnalyzer {
    public let graph: ControlFlowGraph
    private let instructions: [Int: Instruction]

    public init(graph: ControlFlowGraph) {
        self.graph = graph
        self.instructions = [:]
    }

    public init(procedure: Procedure) {
        self.graph = ControlFlowGraph(procedure: procedure)
        self.instructions = procedure.instructions
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

    public func forRegions() -> [StructuredForRegion] {
        loopRegions().compactMap(forRegion)
    }

    public func caseRegions() -> [StructuredCaseRegion] {
        graph.blocks.keys.sorted().compactMap(caseRegion)
    }

    public func caseRegion(at dispatchBlock: Int) -> StructuredCaseRegion? {
        let outgoing = graph.edges.filter { $0.source == dispatchBlock }
        let decodedCaseEdges = outgoing.compactMap {
            edge -> (destination: Int, values: Set<Int>)? in
            guard case let .caseBranch(values) = edge.kind,
                let destination = edge.destination
            else {
                return nil
            }
            return (destination, values)
        }
        let defaultTargets = outgoing.compactMap { edge -> Int? in
            guard edge.kind == .caseDefault else { return nil }
            return edge.destination
        }
        let dispatchEvidence = graph.blocks[dispatchBlock]?
            .instructionAddresses
            .compactMap { instructions[$0]?.caseDispatchEvidence }
            .first
        guard defaultTargets.count == 1,
            let continuation = graph.immediatePostDominator(of: dispatchBlock)
        else {
            return nil
        }
        let defaultTarget = defaultTargets[0]
        let caseEdges = decodedCaseEdges.filter {
            $0.destination != defaultTarget
        }
        guard !caseEdges.isEmpty else { return nil }

        var arms: [StructuredCaseArm] = []
        var occupiedBlocks: Set<Int> = []
        for edge in caseEdges {
            guard let blocks = caseArmBlocks(
                from: edge.destination,
                dispatchBlock: dispatchBlock,
                continuationBlock: continuation
            ), occupiedBlocks.isDisjoint(with: blocks)
            else {
                return nil
            }
            occupiedBlocks.formUnion(blocks)
            arms.append(
                StructuredCaseArm(
                    values: edge.values,
                    entryBlock: edge.destination,
                    blocks: blocks
                )
            )
        }
        arms.sort {
            let leftValue = $0.values.min() ?? Int.max
            let rightValue = $1.values.min() ?? Int.max
            return leftValue == rightValue
                ? $0.entryBlock < $1.entryBlock
                : leftValue < rightValue
        }

        guard let defaultBlocks = caseArmBlocks(
            from: defaultTarget,
            dispatchBlock: dispatchBlock,
            continuationBlock: continuation
        ) else {
            return nil
        }
        if !arms.contains(where: { $0.entryBlock == defaultTarget }),
            !occupiedBlocks.isDisjoint(with: defaultBlocks)
        {
            return nil
        }

        return StructuredCaseRegion(
            dispatchBlock: dispatchBlock,
            selectorExpression: dispatchEvidence?.selectorExpression,
            gatewayBlock: dispatchEvidence.flatMap { evidence in
                graph.blocks.keys.first(where: { block in
                    graph.blocks[block]?.instructionAddresses.contains(
                        evidence.gatewayAddress
                    ) == true
                })
            },
            arms: arms,
            defaultEntryBlock: defaultTarget,
            defaultBlocks: defaultBlocks,
            continuationBlock: continuation
        )
    }

    public func gotoFallbacks() -> [GotoFallback] {
        let conditionals = conditionalRegions()
        let loops = loopRegions()
        let cases = caseRegions()
        var consumedEdges: Set<ControlFlowEdge> = []
        var reasons: [ControlFlowEdge: GotoFallbackReason] = [:]

        for region in conditionals {
            consumedEdges.formUnion(
                graph.edges.filter { $0.source == region.conditionBlock }
            )
            let armBlocks = region.thenBlocks.union(region.elseBlocks)
            consumedEdges.formUnion(
                graph.edges.filter {
                    armBlocks.contains($0.source)
                        && $0.destination == region.continuationBlock
                }
            )
        }

        for region in loops {
            consumedEdges.formUnion(
                graph.edges.filter { $0.source == region.conditionBlock }
            )
            consumedEdges.insert(region.structuralBackEdge)
            for edge in region.exitEdges
            where !(edge.source == region.conditionBlock
                && edge.destination == region.continuationBlock)
            {
                consumedEdges.remove(edge)
                reasons[edge] = .loopExit
            }
            for edge in region.continueEdges {
                consumedEdges.remove(edge)
                reasons[edge] = .loopContinue
            }
        }

        for region in cases {
            consumedEdges.formUnion(
                graph.edges.filter { $0.source == region.dispatchBlock }
            )
            let armBlocks = region.arms.reduce(into: region.defaultBlocks) {
                $0.formUnion($1.blocks)
            }
            consumedEdges.formUnion(
                graph.edges.filter {
                    armBlocks.contains($0.source)
                        && $0.destination == region.continuationBlock
                }
            )
        }

        return graph.edges.compactMap { edge in
            guard Self.requiresExplicitTransfer(edge),
                !consumedEdges.contains(edge)
            else {
                return nil
            }
            return GotoFallback(
                edge: edge,
                reason: reasons[edge] ?? .irreducible
            )
        }.sorted {
            if $0.edge.source != $1.edge.source {
                return $0.edge.source < $1.edge.source
            }
            return ($0.edge.destination ?? Int.max)
                < ($1.edge.destination ?? Int.max)
        }
    }

    private func forRegion(
        from loop: StructuredLoopRegion
    ) -> StructuredForRegion? {
        guard loop.kind == .whileLoop,
            let header = graph.blocks[loop.conditionBlock],
            header.instructionAddresses.count >= 2,
            let comparison = forComparison(
                at: header.instructionAddresses[
                    header.instructionAddresses.count - 2
                ]
            ),
            let updateBlock = graph.blocks[loop.structuralBackEdge.source],
            let update = forUpdate(
                in: updateBlock,
                direction: comparison.1
            ),
            let branchAddress = header.instructionAddresses.last,
            let evidence = instructions[branchAddress]?.forLoopEvidence,
            evidence.direction == comparison.1,
            evidence.variable == StructuredForVariable(update.variable),
            evidence.updateStoreAddress == update.storeAddress,
            header.instructionAddresses.contains(where: {
                guard let instruction = instructions[$0] else { return false }
                return Self.isDirectLoad(instruction.opcode)
                    && instruction.memLocation == update.variable
            }),
            evidence.initializationStoreAddress < loop.headerBlock,
            !evidence.startExpression.isEmpty,
            !evidence.limitExpression.isEmpty
        else {
            return nil
        }

        return StructuredForRegion(
            direction: comparison.1,
            variable: StructuredForVariable(update.variable),
            loop: loop,
            initializationStoreAddress:
                evidence.initializationStoreAddress,
            setupAddresses: evidence.setupAddresses,
            startExpression: evidence.startExpression,
            limitExpression: evidence.limitExpression,
            comparisonAddress: comparison.0,
            updateStoreAddress: update.storeAddress
        )
    }

    private func forComparison(
        at address: Int
    ) -> (Int, StructuredForDirection)? {
        guard let instruction = instructions[address] else { return nil }
        switch instruction.opcode {
        case leq, leqi:
            return (address, .to)
        case geq, geqi:
            return (address, .downto)
        default:
            return nil
        }
    }

    private func forUpdate(
        in block: BasicBlock,
        direction: StructuredForDirection
    ) -> (variable: Location, storeAddress: Int)? {
        let addresses = block.instructionAddresses
        guard addresses.count >= 5,
            let branchAddress = addresses.last,
            instructions[branchAddress]?.opcode == ujp
        else {
            return nil
        }
        let updateAddresses = Array(addresses.dropLast().suffix(4))
        guard updateAddresses.count == 4,
            let load = instructions[updateAddresses[0]],
            let constant = instructions[updateAddresses[1]],
            let arithmetic = instructions[updateAddresses[2]],
            let store = instructions[updateAddresses[3]],
            Self.isDirectLoad(load.opcode),
            Self.isOneConstant(constant),
            arithmetic.opcode == (direction == .to ? adi : sbi),
            Self.isDirectStore(store.opcode),
            let variable = store.memLocation,
            load.memLocation == variable
        else {
            return nil
        }
        return (variable, updateAddresses[3])
    }

    private func caseArmBlocks(
        from start: Int,
        dispatchBlock: Int,
        continuationBlock: Int
    ) -> Set<Int>? {
        if start == continuationBlock {
            return []
        }
        guard let blocks = armBlocks(
            from: start,
            conditionBlock: dispatchBlock,
            continuationBlock: continuationBlock
        ), validateArm(
            blocks,
            conditionBlock: dispatchBlock,
            continuationBlock: continuationBlock
        ) else {
            return nil
        }
        return blocks
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
    ) -> StructuredLoopRegion? {
        let structuralBackEdge: ControlFlowEdge?
        switch kind {
        case .whileLoop:
            structuralBackEdge = loop.backEdges.max {
                $0.source < $1.source
            }
        case .repeatUntilLoop:
            structuralBackEdge = loop.backEdges.first {
                $0.source == conditionBlock && $0.destination == loop.header
            }
        }
        guard let structuralBackEdge else { return nil }
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
                    edge.destination == continueTarget,
                    edge != structuralBackEdge
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
            structuralBackEdge: structuralBackEdge,
            backEdges: loop.backEdges,
            exitEdges: exitEdges,
            continueEdges: continueEdges
        )
    }

    private static func requiresExplicitTransfer(
        _ edge: ControlFlowEdge
    ) -> Bool {
        switch edge.kind {
        case .conditionalBranch, .unconditionalBranch, .caseBranch,
            .caseDefault:
            return true
        case .fallthrough, .call, .return:
            return false
        }
    }

    private static func isDirectLoad(_ opcode: UInt8) -> Bool {
        switch opcode {
        case ldo, lod, lde, ldl, sldl1...sldl16, sldo1...sldo16:
            return true
        default:
            return false
        }
    }

    private static func isDirectStore(_ opcode: UInt8) -> Bool {
        switch opcode {
        case sro, str, stl, ste:
            return true
        default:
            return false
        }
    }

    private static func isOneConstant(_ instruction: Instruction) -> Bool {
        instruction.opcode == 1
            || instruction.opcode == ldci && instruction.params.first == 1
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
