public class SegDictionary: CustomStringConvertible {
    public var segTable: [Int: Segment]
    public var intrinsics: Set<UInt8>
    public var comment: String

    public var description: String {
        let sortedSegments = segTable.sorted {
            $0.value.codeAddress < $1.value.codeAddress
        }

        let tableRows = sortedSegments.map { (slot, segment) in
            return
                "| \(slot) | \(segment.segNum) | \(segment.name) | \(String(format:"%04X", segment.codeAddress)) | \(segment.codeLength) | \(segment.segmentKind) | \(String(format:"%04X", segment.textAddress)) | \(segment.machineType) | \(segment.version) |"
        }

        return """
            ## Segment Table

            | slot | segNum | name | codeAddress | codeLength | kind | textAddr | machineType | version |
            |-----:|-------:|------|---------:|---------:|------|---------:|-------|--------:|
            \(tableRows.joined(separator: "\n"))

            intrinsics: `\(intrinsics)`

            comment: \(comment)

            """
    }

    public init(
        segTable: [Int: Segment],
        intrinsics: Set<UInt8>,
        comment: String
    ) {
        self.segTable = segTable
        self.intrinsics = intrinsics
        self.comment = comment
    }
}
