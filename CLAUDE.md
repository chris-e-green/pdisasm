# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

`AGENTS.md` is the companion tool-neutral guide. Keep shared guidance in these
two files consistent.

## Commands

```bash
swift build                         # build all targets
swift test                          # run all tests
swift test --parallel               # run tests in parallel (CI default)
swift test --filter ClassName       # run a specific test class
swift test --filter ClassName/testMethodName  # run a single test

swift run pdisasm-cli path/to/file.bin              # disassemble a file
swift run pdisasm-cli path/to/file.bin --show-source --dialect apple-pascal
swift run pdisasm-gui                               # launch the macOS SwiftUI app (macOS only)
```

The test target uses Swift language mode v5; all other targets use v6. The GUI targets (`pdisasm-gui`, `pdisasm-gui-lib`) are only compiled on macOS.

## Architecture

### Package targets

- **`pdisasm`** — core library: parsing, decoding, analysis, metadata, export, and rendering. No external dependencies.
- **`pdisasm-cli`** — thin adapter around `DisassemblyService`; parses CLI flags and writes output/files.
- **`pdisasm-gui-lib`** / **`pdisasm-gui`** — SwiftUI views, view models, and macOS app entry point.

### Change guidance

- Keep the CLI and GUI as adapters; disassembly behavior belongs in the core
  library and application services.
- The mutable legacy decode model (`CodeSegment`, `Procedure`, `Instruction`,
  `Location`) is used during analysis. `ProgramSnapshot` and
  `DisassemblyDocument` are immutable products for output and GUI code; do not
  leak mutable legacy objects across new public boundaries.
- Preserve deterministic behavior: the same bytes, metadata snapshot, options,
  and tool version should yield the same result.
- Preserve metadata precedence and provenance, and use the metadata
  repository/editing APIs rather than adding parsing or persistence to GUI code.
- Treat canonical IDs as typed domain values. Translate legacy string forms only
  at persistence, export, or presentation boundaries.
- The central legacy analysis pass is transitional. Prefer small, tested seams
  around it over broad rewrites; consult `docs/adr/` and
  `docs/new-architecture-verification.md` before changing snapshot, document,
  metadata, invalidation, or run-status contracts.

### Disassembly pipeline (`DisassemblyService.run`)

`DisassemblyService` orchestrates five sequential stages:

1. **`CodefileLoadStage`** — reads raw bytes, validates the segment dictionary header.
2. **`MetadataMergeStage`** — loads metadata from CSV/JSON files via `MetadataRepository` and merges bundles by precedence into a `MetadataSnapshot`.
3. **`LegacyPipelineStages`** — calls `disassemble()`, which returns a legacy
   mutable `DisassemblyResult` after it:
   - decodes the segment dictionary (`SegmentDictionaryReader`);
   - decodes each procedure's P-code or 6502 opcodes (`OpcodeDecoder`,
     `WDC6502`);
   - performs control-flow analysis (`ControlFlowGraph`,
     `StructuredControlFlowAnalyzer`);
   - simulates the P-code stack (`StackSimulator`);
   - generates pseudocode (`PseudoCodeGenerator`); and
   - renders structured Pascal source (`StructuredPascalSourceBuilder`).
4. **`SnapshotBuildStage`** — converts the mutable legacy model into the immutable value-type `ProgramSnapshot` (segments, procedures, instructions, locations, call graph).
5. **`DocumentBuildStage`** — renders `ProgramSnapshot` into a `DisassemblyDocument`: a flat list of `DocumentNode`s each wrapping an `OutputLine`, plus section groupings and a source map.

### Data model split

There are two parallel representations of disassembly data:

**Legacy model** (mutable, reference types, used during decoding):
- `CodeSegment`, `Procedure`, `Instruction`, `Location` — directly mutated by decoding and analysis passes.
- `DisassemblyResult` — wraps the decoded state passed to the snapshot builder.

**Modern model** (immutable, value types, used for output and GUI):
- `ProgramSnapshot` — the canonical read-only view of the full program (keyed dictionaries of `SegmentSnapshot`, `ProcedureSnapshot`, `InstructionSnapshot`, `LocationFact`, `CallEdge`).
- `DisassemblyDocument` — the rendered document; nodes are indexed by `DocumentIndexes` for GUI navigation and search.

### Metadata system

- `MetadataWorkspace` pairs a writable directory (user Application Support) with an optional read-only bundled directory (`metadata/`).
- `MetadataScope` is a typed enum mapping logical scopes (system labels, file procedures, file comments, records, type definitions, etc.) to file names and precedence levels. Bundled metadata has precedence 0; user edits have precedence 10.
- `FileBackedMetadataRepository` loads CSV (labels, procedures), JSON (comments, records, globals, source units), and `.pas` type definition files.
- `MetadataSnapshot(merging:)` applies precedence rules so higher-precedence facts win per key.
- Use `MetadataEditingService` to apply label, comment, and procedure-signature edits. Its results provide diagnostics and invalidation information so callers can re-render at the appropriate scope (document-only patch, procedure signature reload, full disassembly, and so on).

### Pascal dialect

`ApplePascalDialect` (`.applePascal` / `.ucsdPSystem`) is carried through `DisassemblyOptions` into `ApplePascalDialectPolicy`, which controls keyword sets, the CASE default keyword, unit syntax support, and the standard procedure table. UCSD-specific behavior is not yet verified; unverified differences fall back to Apple Pascal behavior as a placeholder, not as final dialect policy.

### Variable addressing conventions

- `G{n}` — global variable (segment 0)
- `MP{n}` — local variable (Mark Pointer relative)
- `BASE{n}` — base-pointer relative

### Test fixtures

Binary fixtures live in `Tests/pdisasmTests/Fixtures/`. `BinaryFixtureSnapshotTests` compare rendered output against reference strings. `AssemblerFixtureRegressionTests` and `CrossProcedure*` tests exercise multi-segment call scenarios using in-memory constructed procedures.

## Testing expectations

- Add or update focused XCTest coverage for behavioral changes.
- Use existing binary fixtures in `Tests/pdisasmTests/Fixtures/`; do not change golden snapshots or metadata merely
  to mask a regression.
- Run the narrowest relevant test target first, then `swift test` for changes
  that affect shared core behavior, metadata, snapshots, CLI output, or GUI view
  models.
- Keep malformed-input handling non-crashing and preserve diagnostic/run-status
  behavior.

## Working conventions

- Follow surrounding Swift style and keep changes scoped to the requested
  behavior.
- Do not introduce external dependencies without explicit approval.
- Do not modify generated build artifacts such as `.build/` or `.swiftpm/`.
- Treat `metadata/` as bundled defaults. User-editable metadata normally lives
  outside the repository unless an explicit CLI workspace is supplied.
- Before editing, check the worktree and avoid overwriting unrelated user
  changes.
