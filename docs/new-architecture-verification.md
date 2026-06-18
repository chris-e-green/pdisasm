# New architecture implementation verification

Verification date: 2026-06-18.

## Result

The replacement architecture is partially implemented. The branch has the core seams needed to run the new service-oriented path, but several aspirational pieces from `docs/architecture-review.md` remain unimplemented or intentionally deferred.

## Implemented

- Core package boundaries are in place inside the existing Swift package: `pdisasm` has no target dependencies, the CLI depends only on `pdisasm`, and the package has no external dependencies.
- macOS-only GUI targets are guarded by `#if os(macOS)`, so Linux builds and tests compile only portable targets.
- Canonical IDs exist for code files, segments, procedures, instructions, locations, call edges, documents, and document nodes.
- `DisassemblyService` provides a shared application API that returns a legacy result, immutable `ProgramSnapshot`, `DisassemblyDocument`, `DocumentIndexes`, and `RunReport`.
- Metadata persistence is isolated behind `MetadataRepository`, `FileBackedMetadataRepository`, provenance-aware bundles/snapshots, and `MetadataEditingService` invalidation scopes.
- The CLI is a thin adapter: it parses fixed arguments, invokes `DisassemblyService` or `BatchDisassemblyService`, and selects text, JSON, or call-graph output.
- Rendering/export seams exist for text documents, stable JSON export, and DOT call-graph export.
- The automated test suite passes on Linux: 348 tests executed, 1 snapshot-generation test skipped, and 0 failures.

## Gaps and caveats

- The logical architecture is not split into separate physical targets such as `pdisasm-domain`, `pdisasm-analysis`, or `pdisasm-document`; those boundaries are currently represented by files/types inside the `pdisasm` target.
- `DisassemblyRunRequest` now exposes a cancellation token and `DisassemblyService` checks it at service boundaries, but the legacy disassembler it delegates to is still synchronous and cannot be interrupted mid-stage.
- The request-level `metadata` snapshot is present but the service still delegates to the legacy runner and workspace-based metadata loading; metadata is not fully injected as deterministic input to every pipeline stage.
- Stage reporting exists, but the full named pipeline from the architecture review is not surfaced as discrete stages with separate immutable inputs/outputs.
- `ProgramSnapshot` now includes code-file summary, segment-dictionary snapshot, and type-environment summary fields, but not provenance on every useful fact.
- `DisassemblyDocument` now stores document sections and a source-map field; source-map population is still limited because the legacy renderer only exposes references on some output lines.
- A token search index exists in `DocumentIndexes`; `DocumentSessionController` is not implemented.
- Metadata editing does not yet validate every edit target against the current snapshot, perform explicit atomic backup writes, or hide all metadata filename details from every caller.
- The GUI still owns view-model level state and metadata editor plumbing; the documented replacement structure based on a session controller/search controller is not complete.

## Verification commands

- `git status --short`
- `rg -n "struct (CodeFileID|SegmentID|ProcedureID|InstructionID|LocationID|CallEdgeID)|struct DisassemblyRunRequest|struct ProgramSnapshot|struct DisassemblyDocument|struct DocumentIndexes|struct MetadataEditingService|protocol MetadataRepository|struct DisassemblyService|struct BatchDisassemblyService|JSONDocumentExporter|CallGraphExporter|renderDisassemblyDocument|#if os\\(macOS\\)|dependencies: \\[\\]" Sources Package.swift`
- `swift test`
