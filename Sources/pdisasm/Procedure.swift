public class Procedure {
    public var lexicalLevel: Int = 0
    public var enterIC: Int = 0
    public var exitIC: Int = 0
    public var parameterSize: Int = 0
    public var dataSize: Int = 0
    public var identifier: ProcedureIdentifier?
    public var instructions: [Int: Instruction] = [:]
    public var entryPoints: Set<Int> = []
    
    public init() {}
    
    public var shortDescription: String {
        return "S\(identifier?.segment ?? -1)_P\(identifier?.procedure ?? -1)_L\(lexicalLevel)"
    }
}
