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
            rewrite: false
        )
        let output = renderDisassembly(
            result,
            showMarkup: true,
            showPCode: true,
            showPseudoCode: false,
            showDot: false,
            verbose: false
        )

        // 3) Assert specific invariants from your bug report
        // Replace these with exact lines/symbols from your failing case.
        XCTAssertTrue(output.contains("## Segment"))
        XCTAssertTrue(output.contains("PROCEDURE TURTLEGR.PROC30"))
        XCTAssertTrue(output.contains("-> 0c3c: 60      RTS"))

        // Example targeted assertions you should customize:
        // XCTAssertTrue(output.contains("-> 0d10:"))
        // XCTAssertTrue(output.contains("*0d34")) // relocation text if expected
        // XCTAssertFalse(output.contains("unexpected bad line"))
        XCTAssertTrue(output.contains("-> 0c3d: 10 23   BPL $0c62"))
        XCTAssertFalse(output.contains("-> 0c3d:  10 23"))
    }
}
