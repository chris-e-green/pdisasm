public class CodeSegment {
    public var procedureDictionary: ProcedureDictionary
    public var procedures: [Procedure] = []

    public init(procedureDictionary: ProcedureDictionary, procedures: [Procedure]) {
        self.procedureDictionary = procedureDictionary
        self.procedures = procedures
    }
}
