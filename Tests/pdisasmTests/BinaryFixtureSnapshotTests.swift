import XCTest
@testable import pdisasm
import Foundation

final class BinaryFixtureSnapshotTests: XCTestCase {
    func testBinaryFixtureSnapshot() throws {
        let binURL = Bundle.module.url(forResource:"sample", withExtension: "bin", subdirectory: "Fixtures")!
        let data = try Data(contentsOf: binURL)
        // load snapshot and verify it records the same size as the binary
        let snapURL = Bundle.module.url(forResource:"sample_bin_snapshot", withExtension: "txt", subdirectory: "Fixtures")!
        let snap = try String(contentsOf: snapURL, encoding: .ascii)
        XCTAssertTrue(snap.contains("Filename: sample.bin"))
        // parse size from snapshot and compare to actual data length
        if let sizeLine = snap.split(separator: "\n").first(where: { $0.hasPrefix("Size:") }) {
            let parts = sizeLine.split(separator: ":").map({ $0.trimmingCharacters(in: .whitespaces) })
            if parts.count > 1, let declared = Int(parts[1]) {
                XCTAssertEqual(data.count, declared)
            } else {
                XCTFail("Could not parse Size from snapshot")
            }
        } else {
            XCTFail("Snapshot missing Size line")
        }
    }
}
