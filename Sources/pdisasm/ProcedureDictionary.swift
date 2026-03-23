public class ProcedureDictionary {
    public var procedureCount: Int
    public var procedurePointers: [Int]

    public init(procedureCount: Int, procedurePointers: [Int]) {
        self.procedureCount = procedureCount
        self.procedurePointers = procedurePointers
    }
}
