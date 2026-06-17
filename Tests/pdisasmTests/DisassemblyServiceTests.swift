import XCTest
@testable import pdisasm

final class DisassemblyServiceTests: XCTestCase {
    func testCanonicalIDAdaptersPreserveLegacyIdentityParts() {
        let codeFileID = CodeFileID("fixture")
        let legacyProcedure = ProcedureIdentifier(isFunction: false, segment: 2, procedure: 3)
        let procedureID = ProcedureID(codeFile: codeFileID, legacy: legacyProcedure)
        XCTAssertEqual(procedureID.segment.codeFile, codeFileID)
        XCTAssertEqual(procedureID.segment.number, 2)
        XCTAssertEqual(procedureID.number, 3)

        let instructionID = InstructionID(
            codeFile: codeFileID,
            legacy: InstructionReference(segment: 2, procedure: 3, addr: 42)
        )
        XCTAssertEqual(instructionID?.procedure, procedureID)
        XCTAssertEqual(instructionID?.offset, 42)

        let location = Location(segment: 2, procedure: 3, lexLevel: 1, addr: 4)
        let locationID = LocationID(codeFile: codeFileID, legacy: location)
        XCTAssertEqual(locationID.segment.number, 2)
        XCTAssertEqual(locationID.procedure, procedureID)
        XCTAssertEqual(locationID.lexicalLevel, 1)
        XCTAssertEqual(locationID.address, 4)
    }

    func testServiceWrapsLegacyDisassemblyWithoutChangingRenderedOutput() throws {
        let fixture = try XCTUnwrap(Bundle.module.url(
            forResource: "SYSTEM.LIBRARY-02-00",
            withExtension: "bin",
            subdirectory: "Fixtures"
        ))
        let legacy = try disassemble(filename: fixture.path, verbose: false)
        let wrapped = try DisassemblyService().run(DisassemblyRunRequest(
            source: .file(fixture),
            options: DisassemblyOptions(verbose: false)
        ))
        XCTAssertEqual(wrapped.legacyResult.sourceFilename, legacy.sourceFilename)
        XCTAssertEqual(wrapped.legacyResult.codeSegments.count, legacy.codeSegments.count)
        XCTAssertEqual(wrapped.legacyResult.allProcedures.count, legacy.allProcedures.count)
        XCTAssertEqual(
            renderDisassembly(wrapped.legacyResult, showMarkup: true, showPCode: true, showPseudoCode: true),
            renderDisassembly(legacy, showMarkup: true, showPCode: true, showPseudoCode: true)
        )
        XCTAssertEqual(wrapped.snapshot.codeFileID, CodeFileID(legacy.sourceFilename))
        XCTAssertEqual(wrapped.report.stages.first?.name, "legacyDisassembly")
    }
}
