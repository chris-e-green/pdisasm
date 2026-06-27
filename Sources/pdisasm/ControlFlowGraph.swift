public struct ControlFlowCallTarget: Hashable, Sendable {
    public let segment: Int?
    public let procedure: Int?
    public let address: Int?
    public let standardProcedure: Int?

    public init(
        segment: Int?,
        procedure: Int?,
        address: Int?,
        standardProcedure: Int? = nil
    ) {
        self.segment = segment
        self.procedure = procedure
        self.address = address
        self.standardProcedure = standardProcedure
    }

    init(_ location: Location) {
        self.init(
            segment: location.segment,
            procedure: location.procedure,
            address: location.addr,
            standardProcedure: nil
        )
    }

    static func standard(_ identifier: Int?) -> ControlFlowCallTarget {
        ControlFlowCallTarget(
            segment: nil,
            procedure: nil,
            address: nil,
            standardProcedure: identifier
        )
    }
}

public enum ControlFlowEdgeKind: Hashable, Sendable {
    case conditionalBranch
    case unconditionalBranch
    case `fallthrough`
    case caseBranch(values: Set<Int>)
    case caseDefault
    case call(ControlFlowCallTarget)
    case `return`
}

public struct ControlFlowEdge: Hashable, Sendable {
    public let source: Int
    public let destination: Int?
    public let kind: ControlFlowEdgeKind

    public init(
        source: Int,
        destination: Int?,
        kind: ControlFlowEdgeKind
    ) {
        self.source = source
        self.destination = destination
        self.kind = kind
    }
}

public struct ConditionalControlFlow: Hashable, Sendable {
    public let conditionBlock: Int
    public let trueBlock: Int
    public let falseBlock: Int

    public init(conditionBlock: Int, trueBlock: Int, falseBlock: Int) {
        self.conditionBlock = conditionBlock
        self.trueBlock = trueBlock
        self.falseBlock = falseBlock
    }
}

public struct BasicBlock: Hashable, Sendable {
    public let startAddress: Int
    public let instructionAddresses: [Int]
    public let isEntry: Bool
    public let isExternalEntry: Bool
    public let isExit: Bool

    public var endAddress: Int {
        instructionAddresses.last ?? startAddress
    }

    public init(
        startAddress: Int,
        instructionAddresses: [Int],
        isEntry: Bool,
        isExternalEntry: Bool,
        isExit: Bool
    ) {
        self.startAddress = startAddress
        self.instructionAddresses = instructionAddresses
        self.isEntry = isEntry
        self.isExternalEntry = isExternalEntry
        self.isExit = isExit
    }
}

public struct ControlFlowGraph {
    public let blocks: [Int: BasicBlock]
    public let edges: Set<ControlFlowEdge>
    public let entryBlocks: Set<Int>
    public let exitBlocks: Set<Int>
    public let externalEntryBlocks: Set<Int>
    public let dominators: [Int: Set<Int>]
    public let postDominators: [Int: Set<Int>]

    public init(procedure: Procedure) {
        let addresses = procedure.instructions.keys.sorted()
        guard let firstAddress = addresses.first else {
            blocks = [:]
            edges = []
            entryBlocks = []
            exitBlocks = []
            externalEntryBlocks = []
            dominators = [:]
            postDominators = [:]
            return
        }

        let addressSet = Set(addresses)
        let canonicalEntry = addressSet.contains(procedure.enterIC)
            ? procedure.enterIC
            : firstAddress
        let externalEntries = procedure.externalEntryPoints
            .intersection(addressSet)
            .subtracting([canonicalEntry, procedure.exitIC])
        var leaders: Set<Int> = [firstAddress, canonicalEntry]
        leaders.formUnion(externalEntries)

        for (index, address) in addresses.enumerated() {
            guard let instruction = procedure.instructions[address] else {
                continue
            }
            leaders.formUnion(Self.branchTargets(for: instruction).intersection(addressSet))
            if Self.endsBlock(instruction),
                index + 1 < addresses.count
            {
                leaders.insert(addresses[index + 1])
            }
        }

        let sortedLeaders = leaders.sorted()
        var blockInstructions: [Int: [Int]] = [:]
        var addressToBlock: [Int: Int] = [:]
        var leaderIndex = 0
        for address in addresses {
            while leaderIndex + 1 < sortedLeaders.count,
                address >= sortedLeaders[leaderIndex + 1]
            {
                leaderIndex += 1
            }
            let leader = sortedLeaders[leaderIndex]
            blockInstructions[leader, default: []].append(address)
            addressToBlock[address] = leader
        }

        let entryBlockSet = Set([canonicalEntry]).union(externalEntries)
        var graphEdges: Set<ControlFlowEdge> = []
        for leader in sortedLeaders {
            guard let instructionAddresses = blockInstructions[leader],
                let lastAddress = instructionAddresses.last,
                let lastInstruction = procedure.instructions[lastAddress]
            else {
                continue
            }

            for address in instructionAddresses {
                guard let instruction = procedure.instructions[address],
                    Self.isCall(instruction)
                else { continue }
                let target = instruction.destination.map(ControlFlowCallTarget.init)
                    ?? .standard(
                        instruction.opcode == csp
                            ? instruction.params.first
                            : nil
                    )
                graphEdges.insert(
                    ControlFlowEdge(
                        source: leader,
                        destination: nil,
                        kind: .call(target)
                    )
                )
            }

            let nextBlock = sortedLeaders.first(where: { $0 > leader })
            func addEdge(to address: Int, kind: ControlFlowEdgeKind) {
                guard let destination = addressToBlock[address] else { return }
                graphEdges.insert(
                    ControlFlowEdge(
                        source: leader,
                        destination: destination,
                        kind: kind
                    )
                )
            }

            if !lastInstruction.isPascal {
                if let nextBlock {
                    addEdge(to: nextBlock, kind: .fallthrough)
                }
            } else {
                switch lastInstruction.opcode {
                case fjp:
                    if let target = lastInstruction.params.first {
                        addEdge(to: target, kind: .conditionalBranch)
                    }
                    if let nextBlock {
                        addEdge(to: nextBlock, kind: .fallthrough)
                    }
                case ujp:
                    if let target = lastInstruction.params.first {
                        addEdge(to: target, kind: .unconditionalBranch)
                    }
                case xjp:
                    if lastInstruction.params.count >= 4 {
                        addEdge(
                            to: lastInstruction.params[3],
                            kind: .caseDefault
                        )
                        let first = lastInstruction.params[0]
                        let last = lastInstruction.params[1]
                        if first <= last {
                            var valuesByTarget: [Int: Set<Int>] = [:]
                            for value in first...last {
                                let parameterIndex = 4 + value - first
                                guard parameterIndex < lastInstruction.params.count else {
                                    break
                                }
                                valuesByTarget[
                                    lastInstruction.params[parameterIndex],
                                    default: []
                                ].insert(value)
                            }
                            for (target, values) in valuesByTarget {
                                addEdge(
                                    to: target,
                                    kind: .caseBranch(values: values)
                                )
                            }
                        }
                    }
                case rnp, rbp, xit:
                    graphEdges.insert(
                        ControlFlowEdge(
                            source: leader,
                            destination: nil,
                            kind: .return
                        )
                    )
                default:
                    if let nextBlock {
                        addEdge(to: nextBlock, kind: .fallthrough)
                    }
                }
            }
        }

        let blocksWithSuccessors = Set(
            graphEdges.compactMap { edge in
                edge.destination == nil ? nil : edge.source
            }
        )
        let returnBlocks = Set(
            graphEdges.compactMap { edge in
                edge.kind == .return ? edge.source : nil
            }
        )
        let exitBlockSet = returnBlocks.union(
            Set(sortedLeaders).subtracting(blocksWithSuccessors)
        )

        var builtBlocks: [Int: BasicBlock] = [:]
        for leader in sortedLeaders {
            builtBlocks[leader] = BasicBlock(
                startAddress: leader,
                instructionAddresses: blockInstructions[leader] ?? [],
                isEntry: entryBlockSet.contains(leader),
                isExternalEntry: externalEntries.contains(leader),
                isExit: exitBlockSet.contains(leader)
            )
        }

        blocks = builtBlocks
        edges = graphEdges
        entryBlocks = entryBlockSet
        exitBlocks = exitBlockSet
        externalEntryBlocks = externalEntries

        let successors = Self.adjacency(
            nodes: Set(sortedLeaders),
            edges: graphEdges
        )
        dominators = Self.computeDominators(
            nodes: Set(sortedLeaders),
            roots: entryBlockSet,
            adjacency: successors
        )
        postDominators = Self.computeDominators(
            nodes: Set(sortedLeaders),
            roots: exitBlockSet,
            adjacency: Self.reversed(successors)
        )
    }

    public func successors(of block: Int) -> Set<Int> {
        Set(
            edges.compactMap {
                $0.source == block ? $0.destination : nil
            }
        )
    }

    public func predecessors(of block: Int) -> Set<Int> {
        Set(
            edges.compactMap {
                $0.destination == block ? $0.source : nil
            }
        )
    }

    public func dominates(_ dominator: Int, block: Int) -> Bool {
        dominators[block]?.contains(dominator) ?? false
    }

    public func postDominates(_ postDominator: Int, block: Int) -> Bool {
        postDominators[block]?.contains(postDominator) ?? false
    }

    public func immediateDominator(of block: Int) -> Int? {
        Self.immediateRelation(of: block, relations: dominators)
    }

    public func immediatePostDominator(of block: Int) -> Int? {
        Self.immediateRelation(of: block, relations: postDominators)
    }

    public func conditionalControlFlow(
        from block: Int
    ) -> ConditionalControlFlow? {
        let outgoing = edges.filter { $0.source == block }
        let trueBlocks = outgoing.compactMap { edge -> Int? in
            guard edge.kind == .fallthrough else { return nil }
            return edge.destination
        }
        let falseBlocks = outgoing.compactMap { edge -> Int? in
            guard edge.kind == .conditionalBranch else { return nil }
            return edge.destination
        }
        guard trueBlocks.count == 1, falseBlocks.count == 1 else {
            return nil
        }
        return ConditionalControlFlow(
            conditionBlock: block,
            trueBlock: trueBlocks[0],
            falseBlock: falseBlocks[0]
        )
    }

    private static func branchTargets(for instruction: Instruction) -> Set<Int> {
        guard instruction.isPascal else { return [] }
        switch instruction.opcode {
        case fjp, ujp:
            return Set(instruction.params.prefix(1))
        case xjp:
            guard instruction.params.count >= 4 else { return [] }
            return Set(instruction.params.dropFirst(3))
        default:
            return []
        }
    }

    private static func endsBlock(_ instruction: Instruction) -> Bool {
        guard instruction.isPascal else { return false }
        switch instruction.opcode {
        case fjp, ujp, xjp, rnp, rbp, xit:
            return true
        default:
            return false
        }
    }

    private static func isCall(_ instruction: Instruction) -> Bool {
        guard instruction.isPascal else { return false }
        switch instruction.opcode {
        case csp, cip, cbp, cxp, clp, cgp:
            return true
        default:
            return false
        }
    }

    private static func adjacency(
        nodes: Set<Int>,
        edges: Set<ControlFlowEdge>
    ) -> [Int: Set<Int>] {
        var result = Dictionary(
            uniqueKeysWithValues: nodes.map { ($0, Set<Int>()) }
        )
        for edge in edges {
            guard let destination = edge.destination else { continue }
            result[edge.source, default: []].insert(destination)
        }
        return result
    }

    private static func reversed(
        _ adjacency: [Int: Set<Int>]
    ) -> [Int: Set<Int>] {
        var result = Dictionary(
            uniqueKeysWithValues: adjacency.keys.map { ($0, Set<Int>()) }
        )
        for (source, destinations) in adjacency {
            for destination in destinations {
                result[destination, default: []].insert(source)
            }
        }
        return result
    }

    private static func computeDominators(
        nodes: Set<Int>,
        roots: Set<Int>,
        adjacency: [Int: Set<Int>]
    ) -> [Int: Set<Int>] {
        guard !nodes.isEmpty else { return [:] }
        let validRoots = roots.intersection(nodes)
        let predecessors = reversed(adjacency)
        let reachable = reachableNodes(from: validRoots, adjacency: adjacency)
        var result: [Int: Set<Int>] = [:]

        for node in nodes {
            if validRoots.contains(node) || !reachable.contains(node) {
                result[node] = [node]
            } else {
                result[node] = reachable
            }
        }

        var changed = true
        while changed {
            changed = false
            for node in reachable.subtracting(validRoots) {
                let incoming = (predecessors[node] ?? []).intersection(reachable)
                let intersection: Set<Int>
                if let first = incoming.first {
                    intersection = incoming.dropFirst().reduce(result[first] ?? []) {
                        $0.intersection(result[$1] ?? [])
                    }
                } else {
                    intersection = []
                }
                let updated = intersection.union([node])
                if result[node] != updated {
                    result[node] = updated
                    changed = true
                }
            }
        }
        return result
    }

    private static func immediateRelation(
        of node: Int,
        relations: [Int: Set<Int>]
    ) -> Int? {
        guard let related = relations[node]?.subtracting([node]) else {
            return nil
        }
        return related.first { candidate in
            guard let candidateRelations = relations[candidate] else {
                return false
            }
            return related.allSatisfy {
                $0 == candidate || candidateRelations.contains($0)
            }
        }
    }

    private static func reachableNodes(
        from roots: Set<Int>,
        adjacency: [Int: Set<Int>]
    ) -> Set<Int> {
        var visited: Set<Int> = []
        var pending = Array(roots)
        while let node = pending.popLast() {
            guard visited.insert(node).inserted else { continue }
            pending.append(contentsOf: adjacency[node] ?? [])
        }
        return visited
    }
}
