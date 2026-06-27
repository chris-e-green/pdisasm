import Foundation

extension PseudoCodeGenerator {
    private func discardFunctionReturnSpace(from stack: inout StackSimulator) {
        // Function calls reserve two words for the callee result before arguments.
        _ = stack.pop()
        _ = stack.pop()
    }

    private mutating func callArguments(
        for called: ProcedureIdentifier,
        stack: inout StackSimulator
    ) -> [String] {
        var arguments: [String] = []
        var index = called.parameters.count - 1

        while index >= 0 {
            let consumed = appendCallArgument(
                for: called,
                parameterIndex: index,
                stack: &stack,
                arguments: &arguments
            )
            index -= consumed
        }

        return arguments
    }

    @discardableResult
    private mutating func appendCallArgument(
        for called: ProcedureIdentifier,
        parameterIndex: Int,
        stack: inout StackSimulator,
        arguments: inout [String]
    ) -> Int {
        let parameter = called.parameters[parameterIndex]
        let evidence = "\(called.shortDescription) argument \(parameter.name)"
        observeParameterMode(
            for: called,
            parameterIndex: parameterIndex,
            value: stack.peekStackValue()
        )

        switch parameter.type {
        case "CHAR":
            let value = stack.popStackValue()
            inferStackValueType(value, "CHAR", evidence: evidence)
            let argument = typedOperandText(value, "CHAR", stack: stack)
            if let ch = Int(argument) {
                arguments.append(renderPascalCharLiteral(ch))
            } else {
                arguments.append(argument)
            }
            return 1
        case "BOOLEAN":
            let value = stack.popStackValue()
            inferStackValueType(value, "BOOLEAN", evidence: evidence)
            let argument = typedOperandText(value, "BOOLEAN", stack: stack)
            if argument == "0" {
                arguments.append("FALSE")
            } else if argument == "1" {
                arguments.append("TRUE")
            } else {
                arguments.append(argument)
            }
            return 1
        case "REAL":
            let (argument, _) = stack.popReal()
            arguments.append(argument)
            setLocType(argument, "REAL", evidence: evidence)
            return 1
        case let setType where setType.hasPrefix("SET"):
            return appendSetCallArgument(stack: &stack, arguments: &arguments)
        default:
            return appendInferredCallArgument(
                for: called,
                parameterIndex: parameterIndex,
                stack: &stack,
                arguments: &arguments
            )
        }
    }

    private func observeParameterMode(
        for called: ProcedureIdentifier,
        parameterIndex: Int,
        value: StackValue
    ) {
        guard called.parameters.indices.contains(parameterIndex) else { return }
        let parameter = called.parameters[parameterIndex]
        guard parameter.parameterModeSource.precedence < ParameterModeSource.metadata.precedence
        else { return }

        let proposedMode: ParameterMode?
        if value.payload.realWord != nil {
            proposedMode = .value
        } else {
            switch value.kind {
            case .address:
                let type = parameter.type.trimmingCharacters(in: .whitespacesAndNewlines)
                let valueType = value.type?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                proposedMode = type == "POINTER"
                    || type.hasPrefix("^")
                    || valueType == "POINTER"
                    || valueType.hasPrefix("^")
                    ? nil
                    : .variable
            case .value, .constant, .expression:
                proposedMode = .value
            case .pointer:
                proposedMode = nil
            }
        }
        guard let proposedMode else { return }

        switch parameter.parameterModeSource {
        case .unknown:
            called.parameters[parameterIndex].parameterMode = proposedMode
            called.parameters[parameterIndex].parameterModeSource = .inferred
        case .inferred:
            if parameter.parameterMode != proposedMode {
                called.parameters[parameterIndex].parameterMode = .unknown
            }
        case .metadata, .user:
            break
        }
    }

    private mutating func appendSetCallArgument(
        stack: inout StackSimulator,
        arguments: inout [String]
    ) -> Int {
        let (argument, argumentType) = stack.peek()
        if argumentType == "INTEGER" {
            let (setLength, setData) = stack.popSet()
            arguments.append(setData)
            return setLength
        }

        arguments.append(argument)
        if let count = Int(argument), count > 0 {
            return count
        }
        return 1
    }

    private mutating func appendInferredCallArgument(
        for called: ProcedureIdentifier,
        parameterIndex: Int,
        stack: inout StackSimulator,
        arguments: inout [String]
    ) -> Int {
        let parameter = called.parameters[parameterIndex]
        let inferredType = stack.peekStackValue().type ?? parameter.type
        let topValue = stack.peekStackValue()
        let nextValue = stack.peekStackValue(1)
        if inferredType == "REAL"
            || (parameterIndex > 0
                && isAutoGeneratedParameter(called.parameters[parameterIndex - 1])
                && isAutoGeneratedParameter(called.parameters[parameterIndex])
                && isRealAggregatePair(topValue, nextValue))
        {
            if isRealAggregatePair(topValue, nextValue) {
                inferRealAggregatePairType(
                    topValue,
                    nextValue,
                    evidence: "\(called.shortDescription) inferred REAL argument"
                )
            }
            let (argument, _) = stack.popReal()
            arguments.append(argument)
            if parameterIndex > 0,
               isAutoGeneratedParameter(called.parameters[parameterIndex - 1]),
               isAutoGeneratedParameter(called.parameters[parameterIndex]) {
                _ = called.parameters[parameterIndex - 1].assignType("REAL", source: .inferred)
                called.parameters[parameterIndex - 1].parameterMode =
                    called.parameters[parameterIndex].parameterMode
                called.parameters[parameterIndex - 1].parameterModeSource =
                    called.parameters[parameterIndex].parameterModeSource
                called.parameters.remove(at: parameterIndex)
                setLocType(argument, "REAL", evidence: "\(called.shortDescription) inferred argument")
                return 2
            }

            _ = called.parameters[parameterIndex].assignType("REAL", source: .inferred)
            setLocType(argument, "REAL", evidence: "\(called.shortDescription) inferred argument")
            return 1
        }

        let value = stack.popStackValue()
        let type = parameter.type
        if let actualType = value.type,
           !actualType.isEmpty,
           actualType != "UNKNOWN",
           actualType != "POINTER",
           type == "UNKNOWN" {
            _ = called.parameters[parameterIndex].assignType(actualType, source: .inferred)
            inferStackValueType(value, actualType, evidence: "\(called.shortDescription) argument \(parameter.name)")
            arguments.append(typedOperandText(value, actualType, stack: stack))
        } else {
            inferStackValueType(value, type, evidence: "\(called.shortDescription) argument \(parameter.name)")
            arguments.append(typedOperandText(value, type, stack: stack))
        }
        return 1
    }

    mutating func handleCallProcedure(_ loc: Location, stack: inout StackSimulator)
        -> String?
    {
        guard let called = allProcedures.first(where: {
            $0.segment == loc.segment && $0.procedure == loc.procedure
        }) else {
            return loc.displayName + "()"  // fallback to just displaying the location
        }

        if called.isFunction {
            discardFunctionReturnSpace(from: &stack)
        }
        let aParams = callArguments(for: called, stack: &stack)

        let callSignature =
            "\(called.shortDescription)(\(aParams.reversed().joined(separator:", ")))"

        if called.isFunction {
            stack.push(StackValue(
                text: callSignature,
                type: called.returnType,
                kind: .expression,
                location: called.returnLocation ?? Location(
                    segment: called.segment,
                    procedure: called.procedure,
                    addr: 1
                )
            ))
            return nil
        } else {
            return callSignature
        }
    }
}
