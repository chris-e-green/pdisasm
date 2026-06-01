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
            showStackState: true,
            showPseudoCode: true,
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
        XCTAssertTrue(output.contains("PROCEDURE TURTLEGR.MOVETO(X:INTEGER; Y:INTEGER)"))
        XCTAssertTrue(output.contains("L1=Y:INTEGER"))
        XCTAssertTrue(output.contains("L2=X:INTEGER"))
        XCTAssertTrue(output.contains("TURTLEGR.MOVETOI(X, Y)"))

        let movetoSignature = try XCTUnwrap(result.allProcedures.first {
            $0.segment == 20 && $0.procedure == 6
        })
        let movetoProcedure = try XCTUnwrap(result.codeSegments[20]?.procedures.first {
            $0.identifier?.procedure == 6
        })
        let xLocation = try XCTUnwrap(result.allLocations.first {
            $0.segment == 20 && $0.procedure == 6 && $0.addr == 2
        })
        let yLocation = try XCTUnwrap(result.allLocations.first {
            $0.segment == 20 && $0.procedure == 6 && $0.addr == 1
        })

        XCTAssertEqual(movetoSignature.parameterLocations.map(\.displayName), ["X", "Y"])
        XCTAssertTrue(movetoSignature.parameterLocations[0] === xLocation)
        XCTAssertTrue(movetoSignature.parameterLocations[1] === yLocation)
        XCTAssertTrue(movetoProcedure.instructions.values.contains {
            $0.memLocation === xLocation
        })
        XCTAssertTrue(movetoProcedure.instructions.values.contains {
            $0.memLocation === yLocation
        })

        let turtlexSignature = try XCTUnwrap(result.allProcedures.first {
            $0.segment == 20 && $0.procedure == 12
        })
        let turtlexProcedure = try XCTUnwrap(result.codeSegments[20]?.procedures.first {
            $0.identifier?.procedure == 12
        })
        let turtlexReturnLocation = try XCTUnwrap(result.allLocations.first {
            $0.segment == 20 && $0.procedure == 12 && $0.addr == 1
        })

        XCTAssertEqual(turtlexReturnLocation.description, "TURTLEX:INTEGER")
        XCTAssertTrue(turtlexSignature.returnLocation === turtlexReturnLocation)
        XCTAssertTrue(turtlexProcedure.instructions.values.contains {
            $0.memLocation === turtlexReturnLocation
        })
        XCTAssertTrue(output.contains("L1=TURTLEX:INTEGER"))
        XCTAssertTrue(output.contains("TURTLEX := DISPSTATE.TURTLEX"))
        XCTAssertTrue(output.contains("L: TURTLEX"))
    }
}
