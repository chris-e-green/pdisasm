//
//  AssemblerFixtureRegressionTests.swift
//  pdisasm
//
//  Created by Christopher Green on 7/5/2026.
//

import XCTest
@testable import pdisasm
import Foundation

final class AssemblerFixtureRegressionTests: XCTestCase {
    func testAssemblerAddressingRegression() throws {
        // 1) Load fixture path from test bundle
        let fixtureURL = try XCTUnwrap(
            Bundle.module.url(
                forResource: "SYSTEM.LIBRARY-02-00",
                withExtension: "bin",
                subdirectory: "Fixtures"
            )
        )

        // 2) Run full disassembly pipeline on the real fixture
        let result = try disassemble(
            filename: fixtureURL.path,
            verbose: false,
            writeMetadata: false
        )
        let output = renderDisassembly(
            result,
            showMarkup: true,
            showPCode: true,
            showPseudoCode: false,
            showDot: false,
            verbose: false
        )

        // 3) Assert stable invariants from the fixture output.
        XCTAssertTrue(output.contains("## Segment"), "Expected at least one segment heading")
        XCTAssertTrue(
            output.contains("### PROCEDURE TURTLEGR.PROC30") || output.contains("TURTLEGR.PROC30"),
            "Expected TURTLEGR.PROC30 procedure header to appear"
        )
        XCTAssertTrue(output.contains("0c3c:"), "Expected RTS instruction address to appear")
        XCTAssertTrue(output.contains("RTS"), "Expected RTS instruction to appear")
        XCTAssertTrue(output.contains("0c3d:"), "Expected branch instruction address to appear")
        XCTAssertTrue(output.contains("BPL $0c62"), "Expected branch target formatting to appear")

        // Keep one formatting-sensitive check only if spacing normalization is intentional.
        XCTAssertFalse(output.contains("-> 0c3d:  10 23"), "Unexpected double-space byte formatting regression")
    }
}
