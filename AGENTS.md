# AGENTS.md

## Project overview

`pdisasm` is a Swift package for inspecting Apple Pascal P-code binaries. It
contains a core disassembly library, a command-line frontend, and macOS SwiftUI
targets. The package has no external Swift package dependencies.

`CLAUDE.md` is a companion guide for tools that load it. Keep shared guidance
in these two files consistent; otherwise, use `docs/adr/` and
`docs/new-architecture-verification.md` for additional architecture detail.

## Repository layout

- `Sources/pdisasm/`: core parsing, decoding, analysis, metadata, export, and
  rendering code.
- `Sources/pdisasm-cli/`: thin command-line adapter around `DisassemblyService`.
- `Sources/pdisasm-gui-lib/`: SwiftUI views and GUI view models.
- `Sources/pdisasm-gui/`: macOS application entry point.
- `Tests/pdisasmTests/`: unit, fixture, integration, and snapshot tests.
- `metadata/`: bundled, read-only metadata used as defaults.
- `docs/`: architecture verification notes and planning documents.
- `docs/adr/`: architectural decisions and stable design contracts.

## Build and test

Run these from the repository root:

```sh
swift build
swift test
swift test --parallel
swift test --filter ClassName
swift test --filter ClassName/testMethodName
```

The test target uses Swift language mode v5. All other targets use Swift v6.
The GUI targets are built only on macOS.

For manual CLI checks:

```sh
swift run pdisasm-cli path/to/file.bin
swift run pdisasm-cli path/to/file.bin --show-source --dialect apple-pascal
swift run pdisasm-gui  # macOS only
```

## Architecture and change guidance

- Keep `pdisasm-cli` and the GUI as adapters; disassembly behavior belongs in
  the core library and application services.
- `DisassemblyService.run` owns the five-stage pipeline: `CodefileLoadStage`,
  `MetadataMergeStage`, `LegacyPipelineStages`, `SnapshotBuildStage`, and
  `DocumentBuildStage`.
- The mutable legacy decode model (`CodeSegment`, `Procedure`, `Instruction`,
  `Location`) is used during analysis. `ProgramSnapshot` and
  `DisassemblyDocument` are the immutable products consumed by output and GUI
  code. Avoid leaking mutable legacy objects across new public boundaries.
- Preserve deterministic behavior: the same bytes, metadata snapshot, options,
  and tool version should yield the same result.
- Keep metadata precedence and provenance intact. Bundled metadata has lower
  precedence than user metadata; use the metadata repository/editing APIs rather
  than adding parsing or persistence logic to GUI code.
- Treat canonical IDs as typed domain values. Translate legacy string forms only
  at persistence, export, or presentation boundaries.
- The central legacy analysis pass is intentionally transitional. Prefer small,
  tested seams around it over broad rewrites. Consult `docs/adr/` and
  `docs/new-architecture-verification.md` before changing snapshot, document,
  metadata, invalidation, or run-status contracts.

### Pascal dialect

`ApplePascalDialect` (`.applePascal` and `.ucsdPSystem`) flows through
`DisassemblyOptions` to `ApplePascalDialectPolicy`, which controls keywords,
the CASE default keyword, unit syntax, and standard procedures. UCSD-specific
behavior is not yet verified; unverified differences use Apple Pascal behavior
as a placeholder, not as final dialect policy.

### Metadata system

`MetadataWorkspace` combines a writable user directory with optional bundled,
read-only metadata. User facts take precedence over bundled facts. The file
repository supports CSV labels and procedures, JSON comments and records, and
`.pas` type definitions. Apply edits through `MetadataEditingService`; its edit
result includes diagnostics and `MetadataInvalidationScope` information so
callers can re-render at the appropriate scope instead of always rerunning the
full disassembly.

### Variable addressing

Rendered pseudocode uses these address-derived names. Preserve the convention
when changing decoding, analysis, or source generation:

- `G{n}`: global variable in segment 0.
- `MP{n}`: Mark Pointer-relative local variable.
- `BASE{n}`: base-pointer-relative variable.

## Testing expectations

- Add or update focused XCTest coverage for behavioral changes.
- Use existing binary fixtures in `Tests/pdisasmTests/Fixtures/`; do not change
  golden snapshots or metadata merely to mask a regression.
- `BinaryFixtureSnapshotTests` compares rendered output against reference
  strings. `AssemblerFixtureRegressionTests` and `CrossProcedure*` cover
  multi-segment scenarios built from in-memory procedures.
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
