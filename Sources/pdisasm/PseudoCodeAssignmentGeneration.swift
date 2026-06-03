import Foundation

extension PseudoCodeGenerator {
    mutating func generateAssignmentStatement(
        for inst: Instruction,
        stack: inout StackSimulator
    ) -> PseudoCodeStatement? {
        switch inst.opcode {
        case sto:
            return generateStoreAssignment(stack: &stack)
        case sas:
            return generateStringAssignment(stack: &stack)
        case mov:
            return generateMoveAssignment(stack: &stack)
        case stp:
            return generatePackedFieldAssignment(stack: &stack)
        case stb:
            return generateByteAssignment(stack: &stack)
        default:
            return nil
        }
    }

    private mutating func generateStoreAssignment(
        stack: inout StackSimulator
    ) -> PseudoCodeStatement {
        let srcValue = stack.popStackValue()
        let destValue = stack.popStackValue()
        var src = stack.assignmentSourceText(srcValue)
        var destName = stack.assignmentTargetText(destValue)
        let srcType = srcValue.type
        let destType = destValue.type
        switch destType {
        case "CHAR":
            if let ch = Int(src), ch >= 0x20 && ch <= 0x7E {
                src = "'\(String(format: "%c", ch))'"
            }
        case "BOOLEAN":
            if src == "0" {
                src = "FALSE"
            } else if src == "1" {
                src = "TRUE"
            }
        default:
            src = scalarLiteralText(src, destinationType: destType)
            if let type = destType, !type.isEmpty && type != "UNKNOWN" {
                setLocType(src, type)
            }
            if let type = srcType, !type.isEmpty && type != "UNKNOWN" {
                setLocType(destName, type)
            }
        }
        if let type = destType, type.starts(with: "ARRAY") {
            destName = "\(destName)[0]"  // for now just show the first element being assigned
        }
        return .assignment(targetValue: destValue, targetText: destName, source: src)
    }

    private mutating func generateStringAssignment(
        stack: inout StackSimulator
    ) -> PseudoCodeStatement {
        let srcValue = stack.popStackValue()
        let destValue = stack.popStackValue()
        let src = stack.assignmentSourceText(srcValue)
        let dest = stack.assignmentTargetText(destValue)
        setLocType(src, "STRING")
        setLocType(dest, "STRING")
        return .assignment(targetValue: destValue, targetText: dest, source: src)
    }

    private func generateMoveAssignment(
        stack: inout StackSimulator
    ) -> PseudoCodeStatement {
        let srcValue = stack.popStackValue()
        let dstValue = stack.popStackValue()
        let src = stack.assignmentSourceText(srcValue)
        let dst = stack.assignmentTargetText(dstValue)
        return .assignment(targetValue: dstValue, targetText: dst, source: src)
    }

    private func generatePackedFieldAssignment(
        stack: inout StackSimulator
    ) -> PseudoCodeStatement {
        let aValue = stack.popStackValue()
        let (bbit, _) = stack.pop()
        let (bwid, _) = stack.pop()
        let bValue = stack.popStackValue()
        let a = stack.assignmentSourceText(aValue)
        let b = bValue.type == "REAL"
            ? representationBitsText(bValue, width: bwid, bit: bbit, stack: stack)
            : stack.assignmentTargetText(bValue)
        let target = bValue.type == "REAL" ? b : "\(b):\(bwid):\(bbit)"
        return .assignment(targetValue: bValue, targetText: target, source: a)
    }

    private func generateByteAssignment(
        stack: inout StackSimulator
    ) -> PseudoCodeStatement {
        let srcValue = stack.popStackValue()
        let dstoffsValue = stack.popStackValue()
        let dstaddrValue = stack.popStackValue()
        var src = stack.assignmentSourceText(srcValue, withoutParentheses: true)
        let dstoffs = stack.assignmentSourceText(dstoffsValue)
        let dstaddr = dstaddrValue.type == "REAL"
            ? representationByteText(dstaddrValue, offset: dstoffs, stack: stack)
            : stack.assignmentTargetText(dstaddrValue)
        let dstoffstype = dstoffsValue.type
        let dstaddrtype = dstaddrValue.type
        if dstaddrtype == "STRING",
           dstoffstype == "INTEGER",
           let offset = Int(dstoffs),
           offset > 0,
           let ch = Int(src),
           ch >= 0x20 && ch <= 0x7E {
            src = "'\(String(format: "%c", ch))'"
        }
        let target = dstaddrValue.type == "REAL" ? dstaddr : "\(dstaddr)[\(dstoffs)]"
        return .assignment(targetValue: dstaddrValue, targetText: target, source: src)
    }
}
