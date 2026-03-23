public enum SegmentKind: Int {
    case linked, hostseg, segproc, unitseg, seprtseg, unlinked_intrins,
        linked_intrins, dataseg
}

public struct Segment: CustomStringConvertible {
    public var codeAddress: Int
    public var codeLength: Int
    public var name: String = ""
    public var segmentKind: SegmentKind = .dataseg
    public var textAddress: Int = 0
    public var segNum: Int = 0
    public var machineType: Int = 0
    public var version: Int = 0

    public var description: String {
        return
            "Segment(name: \"\(name)\", codeAddress: \(String(format:"%04X", codeAddress)), len: \(codeLength))"
    }

    public init(
        codeAddress: Int,
        codeLength: Int,
        name: String,
        segmentKind: SegmentKind,
        textAddress: Int,
        segNum: Int,
        machineType: Int,
        version: Int
    ) {
        self.codeAddress = codeAddress
        self.codeLength = codeLength
        self.name = name
        self.segmentKind = segmentKind
        self.textAddress = textAddress
        self.segNum = segNum
        self.machineType = machineType
        self.version = version
    }
}
