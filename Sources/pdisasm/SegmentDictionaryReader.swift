import Foundation

struct SegmentDictionaryReader {
    let codeData: CodeData

    func read() throws -> SegDictionary {
        let diskInfo = CodeData(data: codeData.data.subdata(in: 0..<64))
        let segName = CodeData(data: codeData.data.subdata(in: 64..<192))
        let segKind = CodeData(data: codeData.data.subdata(in: 192..<224))
        let textAddr = CodeData(data: codeData.data.subdata(in: 224..<256))
        let segInfo = CodeData(data: codeData.data.subdata(in: 256..<288))
        let intrinsSegs = CodeData(data: codeData.data.subdata(in: 288..<296))
        let comment = CodeData(data: codeData.data.subdata(in: 433..<512))

        var segTable: [Int: Segment] = [:]

        for segIdx in 0...15 {
            let codeAddress = Int(try diskInfo.readWord(at: segIdx * 4))
            let codeLength = Int(try diskInfo.readWord(at: segIdx * 4 + 2))
            var name = ""
            for j in 0...7 {
                name.append(
                    String(
                        UnicodeScalar(
                            Int(try segName.readByte(at: segIdx * 8 + j))
                        )!
                    )
                )
            }
            name = name.trimmingCharacters(in: [" "])
            let kind = SegmentKind(
                rawValue: Int(try segKind.readWord(at: segIdx * 2))
            )
            var segNum = Int(try segInfo.readByte(at: segIdx * 2))
            if segNum == 0 { segNum = segIdx }
            let machineType = Int(try segInfo.readByte(at: segIdx * 2 + 1) & 0x0F)
            let version = Int(
                (try segInfo.readByte(at: segIdx * 2 + 1) & 0xE0) >> 5
            )
            let text = try textAddr.readWord(at: segIdx * 2)
            if codeLength > 0 {
                segTable[segIdx] = Segment(
                    codeAddress: codeAddress,
                    codeLength: codeLength,
                    name: name,
                    segmentKind: kind ?? .dataseg,
                    textAddress: Int(text),
                    segNum: segNum,
                    machineType: machineType,
                    version: version
                )
            }
        }

        var intrinsicSet = Set<UInt8>()
        for (i, value) in intrinsSegs.data.enumerated().reversed() {
            for j in 0..<8 {
                if (value >> j) & 1 == 1 {
                    intrinsicSet.insert(UInt8(i * 8 + j))
                }
            }
        }

        let commentStr = comment.data.filter { $0 > 0 }.compactMap {
            UnicodeScalar($0)
        }.map(
            String.init
        ).joined()

        return SegDictionary(
            segTable: segTable,
            intrinsics: intrinsicSet,
            comment: commentStr
        )
    }
}

func readCodeFileStructure(codeData: CodeData) throws -> SegDictionary {
    try SegmentDictionaryReader(codeData: codeData).read()
}
