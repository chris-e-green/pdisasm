import Foundation

struct StructuredPascalSourceBuilder {
    private let procedure: Procedure
    private let graph: ControlFlowGraph
    private let functionResultStorage: FunctionResultStorage?
    private let functionName: String?
    private let allLocations: Set<Location>
    private let conditionals: [Int: StructuredControlFlowRegion]
    private let loops: [Int: StructuredLoopRegion]
    private let forLoops: [Int: StructuredForRegion]
    private let cases: [Int: StructuredCaseRegion]
    private let caseGateways: Set<Int>
    private let fallbacksBySource: [Int: [GotoFallback]]
    private let fallbackTargets: Set<Int>
    private let omittedAddresses: Set<Int>
    private var visited: Set<Int> = []

    init(procedure: Procedure, allLocations: Set<Location>) {
        let builtAnalyzer = StructuredControlFlowAnalyzer(
            procedure: procedure
        )
        self.procedure = procedure
        self.graph = builtAnalyzer.graph
        self.functionResultStorage = procedure.identifier?.functionResultStorage
        self.functionName = procedure.identifier.map {
            $0.procName ?? defaultProcedureName(for: $0)
        }
        self.allLocations = allLocations

        let conditionalRegions = builtAnalyzer.conditionalRegions()
        self.conditionals = Dictionary(
            uniqueKeysWithValues: conditionalRegions.map {
                ($0.conditionBlock, $0)
            }
        )
        let loopRegions = builtAnalyzer.loopRegions()
        self.loops = Dictionary(
            uniqueKeysWithValues: loopRegions.map { ($0.headerBlock, $0) }
        )
        let countedLoops = builtAnalyzer.forRegions()
        self.forLoops = Dictionary(
            uniqueKeysWithValues: countedLoops.map {
                ($0.loop.headerBlock, $0)
            }
        )
        let caseRegions = builtAnalyzer.caseRegions().filter {
            $0.selectorExpression?.isEmpty == false
        }
        self.cases = Dictionary(
            uniqueKeysWithValues: caseRegions.map { ($0.dispatchBlock, $0) }
        )
        let detectedCaseGateways = Set(
            caseRegions.compactMap(\.gatewayBlock)
        )
        self.caseGateways = detectedCaseGateways

        let fallbacks = builtAnalyzer.gotoFallbacks().filter {
            !detectedCaseGateways.contains($0.edge.source)
        }
        self.fallbacksBySource = Dictionary(grouping: fallbacks) {
            $0.edge.source
        }
        self.fallbackTargets = Set(
            fallbacks.compactMap { $0.edge.destination }
        )
        self.omittedAddresses = Set(
            countedLoops.flatMap {
                $0.setupAddresses.union([
                    $0.comparisonAddress,
                    $0.updateStoreAddress,
                ])
            }
        )
    }

    var hasStructuredRegions: Bool {
        !conditionals.isEmpty
            || !loops.isEmpty
            || !cases.isEmpty
            || !fallbacksBySource.isEmpty
    }

    mutating func build() -> [PascalStmt] {
        guard hasStructuredRegions else { return [] }
        var statements: [PascalStmt] = []
        for entry in graph.entryBlocks.sorted() {
            guard !visited.contains(entry) else { continue }
            statements.append(
                contentsOf: buildSequence(
                    from: entry,
                    stoppingAt: [],
                    allowedBlocks: nil
                )
            )
        }
        for block in graph.blocks.keys.sorted() where !visited.contains(block) {
            statements.append(
                contentsOf: buildSequence(
                    from: block,
                    stoppingAt: [],
                    allowedBlocks: nil
                )
            )
        }
        return statements
    }

    private mutating func buildSequence(
        from start: Int,
        stoppingAt stops: Set<Int>,
        allowedBlocks: Set<Int>?
    ) -> [PascalStmt] {
        var statements: [PascalStmt] = []
        var current: Int? = start

        while let block = current,
            !stops.contains(block),
            !visited.contains(block),
            allowedBlocks?.contains(block) != false
        {
            if fallbackTargets.contains(block) {
                statements.append(.label(label(for: block), nil))
            }

            if let loop = loops[block] {
                if let forLoop = forLoops[block],
                    let statement = buildFor(forLoop)
                {
                    statements.append(statement)
                } else {
                    statements.append(buildLoop(loop))
                }
                current = loop.continuationBlock
                continue
            }

            if let region = conditionals[block],
                let branch = graph.conditionalControlFlow(from: block)
            {
                visited.insert(block)
                statements.append(contentsOf: blockStatements(in: block))
                let thenBody = buildSequence(
                    from: branch.trueBlock,
                    stoppingAt: [region.continuationBlock],
                    allowedBlocks: region.thenBlocks
                )
                let condition = conditionExpression(
                    at: block,
                    marker: "IF",
                    suffix: "THEN BEGIN"
                )
                switch region.kind {
                case .ifThen:
                    statements.append(
                        .ifThen(
                            condition: condition,
                            thenBlock: .block(thenBody)
                        )
                    )
                case .ifThenElse:
                    let elseBody = buildSequence(
                        from: branch.falseBlock,
                        stoppingAt: [region.continuationBlock],
                        allowedBlocks: region.elseBlocks
                    )
                    statements.append(
                        .ifElse(
                            condition: condition,
                            thenBlock: .block(thenBody),
                            elseBlock: .block(elseBody)
                        )
                    )
                }
                current = region.continuationBlock
                continue
            }

            if let region = cases[block] {
                visited.insert(block)
                statements.append(contentsOf: blockStatements(in: block))
                statements.append(buildCase(region))
                current = region.continuationBlock
                continue
            }

            visited.insert(block)
            statements.append(contentsOf: blockStatements(in: block))
            statements.append(contentsOf: fallbackStatements(from: block))
            current = nextSequentialBlock(after: block)
        }
        return statements
    }

    private mutating func buildLoop(
        _ loop: StructuredLoopRegion
    ) -> PascalStmt {
        switch loop.kind {
        case .whileLoop:
            visited.insert(loop.conditionBlock)
            let branch = graph.conditionalControlFlow(from: loop.conditionBlock)
            let bodyStart = branch?.trueBlock ?? loop.bodyBlocks.min()
            let body = bodyStart.map {
                buildSequence(
                    from: $0,
                    stoppingAt: [
                        loop.conditionBlock,
                        loop.continuationBlock,
                    ],
                    allowedBlocks: loop.bodyBlocks
                )
            } ?? []
            return .whileDo(
                condition: conditionExpression(
                    at: loop.conditionBlock,
                    marker: "WHILE",
                    suffix: "DO BEGIN"
                ),
                body: .block(body)
            )
        case .repeatUntilLoop:
            visited.insert(loop.headerBlock)
            var body = blockStatements(in: loop.headerBlock)
            let remainingBodyStart = graph.successors(of: loop.headerBlock)
                .filter {
                    $0 != loop.conditionBlock
                        && loop.bodyBlocks.contains($0)
                }
                .min()
            if let remainingBodyStart {
                body.append(
                    contentsOf: buildSequence(
                        from: remainingBodyStart,
                        stoppingAt: [
                            loop.conditionBlock,
                            loop.continuationBlock,
                        ],
                        allowedBlocks: loop.bodyBlocks
                    )
                )
            }
            visited.insert(loop.conditionBlock)
            let conditionStatements = blockStatements(in: loop.conditionBlock)
            return .repeatUntil(
                body: body + conditionStatements,
                condition: conditionExpression(
                    at: loop.conditionBlock,
                    marker: "UNTIL",
                    suffix: nil
                )
            )
        }
    }

    private mutating func buildFor(
        _ region: StructuredForRegion
    ) -> PascalStmt? {
        visited.insert(region.loop.conditionBlock)
        let branch = graph.conditionalControlFlow(
            from: region.loop.conditionBlock
        )
        let bodyStart = branch?.trueBlock ?? region.loop.bodyBlocks.min()
        let body = bodyStart.map {
            buildSequence(
                from: $0,
                stoppingAt: [
                    region.loop.conditionBlock,
                    region.loop.continuationBlock,
                ],
                allowedBlocks: region.loop.bodyBlocks
            )
        } ?? []
        return .forLoop(
            variable: region.variable.name,
            start: .raw(region.startExpression),
            limit: .raw(region.limitExpression),
            direction: region.direction == .to ? .to : .downto,
            body: .block(body)
        )
    }

    private mutating func buildCase(
        _ region: StructuredCaseRegion
    ) -> PascalStmt {
        var armBodies: [Int: [PascalStmt]] = [:]
        var arms: [PascalCaseArm] = []
        for arm in region.arms {
            let body = buildSequence(
                from: arm.entryBlock,
                stoppingAt: [region.continuationBlock],
                allowedBlocks: arm.blocks
            )
            armBodies[arm.entryBlock] = body
            arms.append(
                PascalCaseArm(
                    labels: caseLabels(for: arm.values),
                    body: body
                )
            )
        }
        let defaultBody: [PascalStmt]? = if region.defaultBlocks.isEmpty {
            nil
        } else if let sharedBody = armBodies[region.defaultEntryBlock] {
            sharedBody
        } else {
            buildSequence(
                from: region.defaultEntryBlock,
                stoppingAt: [region.continuationBlock],
                allowedBlocks: region.defaultBlocks
            )
        }
        return .caseStatement(
            PascalCaseStatement(
                expression: .raw(region.selectorExpression ?? "0"),
                arms: arms,
                defaultBody: defaultBody
            )
        )
    }

    private func blockStatements(in block: Int) -> [PascalStmt] {
        guard let basicBlock = graph.blocks[block] else { return [] }
        var statements: [PascalStmt] = []
        for address in basicBlock.instructionAddresses {
            guard let instruction = procedure.instructions[address] else {
                continue
            }
            for pre in instruction.prePseudoCode.reversed()
            where !isLegacyStructuralMarker(pre)
            {
                statements.append(.raw(pre))
            }
            let fallbackPseudo = instruction.pseudoCode.map { text in
                PseudoCodeStatement(
                    renderedText: text,
                    locations: allLocations
                )
            }
            guard !omittedAddresses.contains(address),
                !isControlTransfer(instruction),
                let pseudo = instruction.pseudoCodeStatement ?? fallbackPseudo
            else {
                continue
            }
            statements.append(
                pseudo.pascalSourceStatement(
                    functionResultStorage: functionResultStorage,
                    functionName: functionName
                )
            )
        }
        return statements
    }

    private func fallbackStatements(from block: Int) -> [PascalStmt] {
        (fallbacksBySource[block] ?? []).compactMap { fallback in
            guard let destination = fallback.edge.destination else {
                return nil
            }
            let gotoStatement = PascalStmt.goto(
                label: label(for: destination)
            )
            switch fallback.edge.kind {
            case .conditionalBranch:
                return .ifThen(
                    condition: .unary(
                        .not,
                        fallbackConditionExpression(at: block)
                    ),
                    thenBlock: gotoStatement
                )
            case .unconditionalBranch:
                return gotoStatement
            default:
                return nil
            }
        }
    }

    private func nextSequentialBlock(after block: Int) -> Int? {
        let outgoing = graph.edges.filter {
            $0.source == block && $0.destination != nil
        }
        if let fallthroughEdge = outgoing.first(where: {
            $0.kind == .fallthrough
        }) {
            return fallthroughEdge.destination
        }
        if outgoing.count == 1,
            let edge = outgoing.first,
            edge.kind == .unconditionalBranch,
            (caseGateways.contains(block)
                || fallbacksBySource[block]?.contains(where: {
                    $0.edge == edge
                }) != true)
        {
            return edge.destination
        }
        return nil
    }

    private func conditionExpression(
        at block: Int,
        marker: String,
        suffix: String?
    ) -> PascalExpr {
        guard let text = terminalPseudoCode(in: block),
            let expression = contents(
                of: text,
                after: marker,
                before: suffix
            )
        else {
            return .raw("(* condition unavailable *) TRUE")
        }
        return .raw(expression)
    }

    private func fallbackConditionExpression(at block: Int) -> PascalExpr {
        for (marker, suffix) in [
            ("IF", "THEN BEGIN"),
            ("WHILE", "DO BEGIN"),
        ] {
            if let text = terminalPseudoCode(in: block),
                let expression = contents(
                    of: text,
                    after: marker,
                    before: suffix
                )
            {
                return .raw(expression)
            }
        }
        return .raw("(* condition unavailable *) FALSE")
    }

    private func caseLabels(for values: Set<Int>) -> [PascalExpr] {
        let sorted = values.sorted()
        guard var rangeStart = sorted.first else { return [] }
        var previous = rangeStart
        var labels: [PascalExpr] = []

        func appendRange(_ lower: Int, _ upper: Int) {
            if lower == upper {
                labels.append(.integer(lower))
            } else {
                labels.append(.range(.integer(lower), .integer(upper)))
            }
        }

        for value in sorted.dropFirst() {
            if value == previous + 1 {
                previous = value
            } else {
                appendRange(rangeStart, previous)
                rangeStart = value
                previous = value
            }
        }
        appendRange(rangeStart, previous)
        return labels
    }

    private func terminalPseudoCode(in block: Int) -> String? {
        guard let addresses = graph.blocks[block]?.instructionAddresses else {
            return nil
        }
        for address in addresses.reversed() {
            guard let instruction = procedure.instructions[address] else {
                continue
            }
            if let text = instruction.pseudoCodeStatement?.renderedText
                ?? instruction.pseudoCode
            {
                return text
            }
        }
        return nil
    }

    private func contents(
        of text: String,
        after prefix: String,
        before suffix: String?
    ) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(prefix) else { return nil }
        var value = String(trimmed.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespaces)
        if let suffix {
            guard value.hasSuffix(suffix) else { return nil }
            value = String(value.dropLast(suffix.count))
                .trimmingCharacters(in: .whitespaces)
        }
        return value.isEmpty ? nil : value
    }

    private func isControlTransfer(_ instruction: Instruction) -> Bool {
        guard instruction.isPascal else { return false }
        switch instruction.opcode {
        case fjp, ujp, xjp, rnp, rbp, xit:
            return true
        default:
            return false
        }
    }

    private func isLegacyStructuralMarker(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("END")
            || trimmed.hasPrefix("ELSE")
            || trimmed.hasPrefix("UNTIL")
            || trimmed.range(
                of: #"^[+-]?[0-9]+(?:\.\.[+-]?[0-9]+)?(?:,\s*[+-]?[0-9]+(?:\.\.[+-]?[0-9]+)?)*:\s*BEGIN$"#,
                options: .regularExpression
            ) != nil
            || trimmed.range(
                of: #"^LAB[0-9]+:$"#,
                options: .regularExpression
            ) != nil
    }

    private func label(for block: Int) -> String {
        "LAB\(block)"
    }
}
