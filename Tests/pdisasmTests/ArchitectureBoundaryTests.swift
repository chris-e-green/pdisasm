import XCTest

final class ArchitectureBoundaryTests: XCTestCase {
    func testConsolidatedTargetsKeepForbiddenDependenciesOutOfCoreFiles() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources")
        let core = sources.appendingPathComponent("pdisasm")
        let forbidden = ["import SwiftUI", "import AppKit"]
        let files = try FileManager.default.contentsOfDirectory(
            at: core,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "swift" }

        for file in files {
            let text = try String(contentsOf: file)
            for importLine in forbidden {
                XCTAssertFalse(text.contains(importLine), "\(file.lastPathComponent) must not contain \(importLine)")
            }
        }
    }

    func testArchitectureDecisionRecordsExistForPhaseFBoundaries() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let adrDirectory = root.appendingPathComponent("docs/adr")
        let expected = [
            "0001-metadata-scopes.md",
            "0002-id-serialization.md",
            "0003-snapshot-boundary.md",
            "0004-document-contract.md",
            "0005-invalidation-policy.md",
            "0006-run-status-semantics.md",
        ]
        for name in expected {
            XCTAssertTrue(FileManager.default.fileExists(atPath: adrDirectory.appendingPathComponent(name).path), "Missing ADR \(name)")
        }
    }
}
