import Foundation

enum CodeDataError: Error {
    case unexpectedEndOfData
    case stringDecodingFailed
    case invalidXJPParameters
}

struct CodeData {
    let data: Data
    var instructionPointer: Int
    var header: Int

    init(data: Data, instructionPointer: Int = 0, header: Int = 0) {
        self.data = data
        self.instructionPointer = instructionPointer
        self.header = header
    }

    /// Read a byte from `CodeData` at `instructionPointer`, updating `instructionPointer`.
    /// - Returns: The byte value as a UInt8.
    /// - Throws: `CodeDataError.unexpectedEndOfData` if the read goes past the end of the data.
    @available(*, deprecated, message:"Use readByte(at:) for non-advancing reads or ensure instructionPointer is managed safely.")
    mutating func readByte() throws -> UInt8 {
        guard instructionPointer < data.count else { throw CodeDataError.unexpectedEndOfData }
        let retval = data[instructionPointer]
        instructionPointer += 1
        return retval
    }

    /// Read and decode a 'BIG' value from `CodeData`, at `instructionPointer`, updating `instructionPointer`.
    /// - Returns: The decoded value.
    /// - Throws: `CodeDataError.unexpectedEndOfData` if the read goes past the end of the data.
    @available(*, deprecated, message:"Use readBig(at:) for non-advancing reads or ensure instructionPointer is managed safely.")
    mutating func readBig() throws -> Int {
        let firstByte = try readByte()

        if firstByte <= 127 {
            return Int(firstByte)
        } else {
            // Check for the second byte before reading it.
            guard instructionPointer < data.count else {
                throw CodeDataError.unexpectedEndOfData
            }
            let high = Int(firstByte & 0x7F)
            let low = data[instructionPointer]
            instructionPointer += 1
            return (high << 8) | Int(low)
        }
    }

    /// Get a word from `CodeData` at `instructionPointer`, updating `instructionPointer`.
    ///  - Returns: The little-endian word stored at the current location.
    /// - Throws: `CodeDataError.unexpectedEndOfData` if the read goes past the end of the data.
    @available(*, deprecated, message:"Use readWord(at:) for non-advancing reads or ensure instructionPointer is managed safely.")
    mutating func readWord() throws -> UInt16 {
        guard instructionPointer + 1 < data.count else {
            throw CodeDataError.unexpectedEndOfData
        }
        let low = UInt16(data[instructionPointer])
        let high = UInt16(data[instructionPointer + 1])
        instructionPointer += 2
        return (high << 8) | low
    }

    /// Get an unsigned word from `CodeData` at a specific index without advancing `instructionPointer`.
    ///  - Parameters:
    ///   - at: The position from which to read the word.
    ///  - Returns: The little-endian word stored at the index.
    /// - Throws: `CodeDataError.unexpectedEndOfData` if the read goes past the end of the data.
    func readWord(at position: Int) throws -> UInt16 {
        guard position >= 0 && position + 1 < data.count else {
            throw CodeDataError.unexpectedEndOfData
        }
        let low = UInt16(data[position])
        let high = UInt16(data[position + 1])
        return (high << 8) | low
    }

    /// Get a signed word from `CodeData` at a specific index without advancing `instructionPointer`.
    ///  - Parameters:
    ///   - at: The position from which to read the word.
    ///  - Returns: The little-endian word stored at the index.
    /// - Throws: `CodeDataError.unexpectedEndOfData` if the read goes past the end of the data.
    func readInt(at position: Int) throws -> Int {
        guard position >= 0 && position + 1 < data.count else {
            throw CodeDataError.unexpectedEndOfData
        }
        let low = Int(data[position])
        let high = Int(data[position + 1])
        let val = (high << 8) | low
        if val > 32767 {
            return val - 65536
        } else {
            return val
        }
    }

    /// Non-advancing byte read with bounds checking.
    func readByte(at position: Int) throws -> UInt8 {
        guard position >= 0 && position < data.count else {
            throw CodeDataError.unexpectedEndOfData
        }
        return data[position]
    }

    /// Non-advancing BIG read with bounds checking. Returns (value, byteCount).
    func readBig(at position: Int) throws -> (Int, Int) {
        guard position >= 0 && position < data.count else {
            throw CodeDataError.unexpectedEndOfData
        }
        let first = data[position]
        if first <= 127 {
            return (Int(first), 1)
        } else {
            guard position + 1 < data.count else {
                throw CodeDataError.unexpectedEndOfData
            }
            let val = Int(first & 0x7F) << 8 | Int(data[position + 1])
            return (val, 2)
        }
    }

    /// Non-advancing helper to read a self-referenced pointer at `position`.
    func getSelfRefPointer(at position: Int) throws -> Int {
        let w = try readWord(at: position)
        return position - Int(w)
    }

    /// Decodes a relative address offset, which can be a short jump or a long jump via a jump table.
    /// - Returns: The absolute destination address.
    /// - Throws: `CodeDataError` if any underlying read fails.
    @available(*, deprecated, message:"Use readAddress(at:) for non-advancing reads or ensure instructionPointer is managed safely.")
    mutating func readAddress() throws -> Int {
        let offset = try readByte()

        if offset > 0x7F {
            // Backwards jump: uses an offset from the header to find an entry in a jump table.
            let jte = header + Int(offset) - 256
            let jumpTableEntry = try self.readWord(at: jte)
            return jte - Int(jumpTableEntry)
        } else {
            // Forward jump: a simple relative offset from the current instruction pointer.
            return instructionPointer + Int(offset) + 1  // instructionPointer is already advanced by readByte()
        }
    }

    func readAddress(at position: Int) throws -> Int {
        let offset = try readByte(at: position)

        if offset > 0x7F {
            let jte = header + Int(offset) - 256
            let jumpTableEntry = try readWord(at: jte)
            return jte - Int(jumpTableEntry)
        } else {
            return position + Int(offset) + 2
        }
    }

    /// Reads a length-prefixed string.
    /// - Returns: The decoded string.
    /// - Throws: `CodeDataError` on failure.
    @available(*, deprecated, message:"Use readString(at:) for non-advancing reads or ensure instructionPointer is managed safely.")
    mutating func readString() throws -> String {
        let count = Int(try readByte())
        guard instructionPointer + count <= data.count else {
            throw CodeDataError.unexpectedEndOfData
        }

        let stringData = data[instructionPointer..<(instructionPointer + count)]
        instructionPointer += count

        guard let result = String(data: stringData, encoding: .ascii) else {
            throw CodeDataError.stringDecodingFailed
        }
        return result
    }

    func readString(at position: Int) throws -> String {
        let count = Int(try readByte(at: position))
        let start = position + 1
        guard start + count <= data.count else {
            throw CodeDataError.unexpectedEndOfData
        }

        let stringData = data[start..<(start + count)]
        guard let result = String(data: stringData, encoding: .ascii) else {
            throw CodeDataError.stringDecodingFailed
        }
        return result
    }

    /// Reads a length-prefixed byte array.
    @available(*, deprecated, message:"Use readByteArray(at:) for non-advancing reads or ensure instructionPointer is managed safely.")
    mutating func readByteArray() throws -> [UInt8] {
        let count = Int(try readByte())
        guard instructionPointer + count <= data.count else {
            throw CodeDataError.unexpectedEndOfData
        }
        let byteArray = Array(data[instructionPointer..<instructionPointer + count])
        instructionPointer += count
        return byteArray
    }

    func readByteArray(at position: Int) throws -> [UInt8] {
        let count = Int(try readByte(at: position))
        let start = position + 1
        guard start + count <= data.count else {
            throw CodeDataError.unexpectedEndOfData
        }
        return Array(data[start..<start + count])
    }

    /// Reads a word-aligned array of `count` words.
    @available(*, deprecated, message:"Use readWordArray(at:count:) for non-advancing reads or ensure instructionPointer is managed safely.")
    mutating func readWordArray(count: Int) throws -> [UInt16] {
        guard instructionPointer + (count * 2) <= data.count else {
            throw CodeDataError.unexpectedEndOfData
        }
        var words: [UInt16] = []
        words.reserveCapacity(count)
        for _ in 0..<count {
            words.append(try readWord())
        }
        return words
    }

    func readWordArray(at position: Int, count: Int) throws -> [UInt16] {
        guard position >= 0 && position + (count * 2) <= data.count else {
            throw CodeDataError.unexpectedEndOfData
        }
        return try (0..<count).map { index in
            try readWord(at: position + index * 2)
        }
    }

    /// Returns 512-byte blocks from `Data`.
    /// - Parameters:
    ///   - blockNum: the starting block number.
    ///   - length: the number of bytes to return.
    /// - Returns: A `Data` object of `length` bytes, starting at block `blockNum`.
    /// Safe variant of extracting a 512-byte aligned code block.
    /// If the requested range is out of bounds, this returns an empty `Data`.
    func getCodeBlock(at blockNum: Int, length: Int) -> Data {
        let start = Int(blockNum) * 512
        let end = start + Int(length)
        guard start >= 0, end <= self.data.count else { return Data() }
        return self.data.subdata(in: start..<end)
    }

}
