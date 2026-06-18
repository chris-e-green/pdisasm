# New architecture implementation verification

Verification date: 2026-06-18.

## Result

The replacement architecture is **partially implemented**. The branch now has the first service-oriented seams from `docs/architecture-review.md`: canonical IDs, a shared `DisassemblyService`, immutable snapshot/document/index products, a metadata repository facade, and export renderers. However, much of the implementation is still an adapter over the legacy mutable disassembler rather than the deterministic staged architecture described in the review.

The next work should therefore avoid a broad rewrite. The recommended path is to harden the existing seams, move remaining side effects out of callers, and then split the legacy runner into independently testable stages.

## Implemented

- Core package boundaries are in place inside the existing Swift package: `pdisasm` has no target dependencies, the CLI depends only on `pdisasm`, and the package has no external dependencies.
- macOS-only GUI targets are guarded by `#if os(macOS)`, so Linux builds and tests compile only portable targets.
- Canonical IDs exist for code files, segments, procedures, instructions, locations, call edges, metadata facts, documents, and document nodes.
- `DisassemblyService` provides a shared application API that returns a legacy result, immutable `ProgramSnapshot`, `DisassemblyDocument`, `DocumentIndexes`, and `RunReport`.
- `DisassemblyRunRequest` has source, metadata snapshot, optional workspace, options, and cancellation-token fields.
- `ProgramSnapshot` includes code-file summary, segment dictionary summary, type-environment summary, segment/procedure/instruction/location facts, call indexes, and diagnostics.
- `DisassemblyDocument` includes sections, document nodes, node lookup, and a source-map field.
- `DocumentIndexes` exposes procedure, location, instruction, symbol, and token search indexes.
- Metadata persistence is isolated for labels, procedures, and comments behind `MetadataRepository`, `FileBackedMetadataRepository`, provenance-aware bundles/snapshots, and `MetadataEditingService` invalidation scopes.
- The CLI is a thin adapter that parses fixed arguments, invokes `DisassemblyService` or `BatchDisassemblyService`, and selects text, JSON, or call-graph output.
- Rendering/export seams exist for text documents, stable JSON export, and DOT call-graph export.
- Linux test coverage currently passes for the portable targets.

## Remaining gaps

### 1. Deterministic metadata injection is incomplete

`DisassemblyRunRequest.metadata` exists, but `DisassemblyService` still delegates to the legacy `disassemble(...)` path, which resolves and loads metadata through a workspace. This means the service contract does not yet fully satisfy the architecture goal that bytes, metadata snapshot, options, and tool version determine the result.

Required changes:

- Add a legacy-runner entry point that accepts a fully merged `MetadataSnapshot` instead of deriving all metadata from file names and application-support paths.
- Move file/version metadata name selection into an application-layer resolver that returns scopes plus provenance.
- Add tests that run from `.bytes` plus in-memory metadata and assert no application-support metadata is read.
- Keep workspace-based loading as an adapter that produces the snapshot before analysis.

### 2. Pipeline stages are reported but not separated

`RunReport` and `StageReport` exist, but the pipeline is still mostly one synchronous legacy operation plus snapshot/document build. The explicit stages in the architecture review are not separate units with typed inputs and outputs.

Required changes:

- Extract `CodefileLoadStage`, `MetadataMergeStage`, `SegmentDecodeStage`, `ReferenceResolutionStage`, `AnalysisStage`, `SignatureConvergenceStage`, `SnapshotBuildStage`, and `DocumentBuildStage` types.
- Start by wrapping existing code in stage facades without changing algorithms.
- Add per-stage unit tests using in-memory inputs.
- Define stage fatality/completeness rules so malformed procedures degrade the run instead of being treated like infrastructure failures.

### 3. Cancellation only works at service boundaries

The request supports `CancellationToken`, and `DisassemblyService` checks it before and after legacy work. The legacy disassembler remains synchronous and cannot be interrupted mid-decode or mid-analysis.

Required changes:

- Thread a lightweight cancellation/progress context through the extracted stages.
- Check cancellation at segment, procedure, and fixed-point-iteration boundaries.
- Return a distinct cancelled result/error that callers can distinguish from malformed input.
- Update GUI loading paths to cancel obsolete runs when a new file or option set is selected.

### 4. Metadata editing is still partly filename-oriented and not fully validated

`MetadataEditingService` exists, but some APIs still require callers to pass file identifiers or metadata filenames. The GUI metadata editor still discovers, parses, and saves metadata files directly for general editing workflows.

Required changes:

- Replace filename parameters in edit commands with typed targets and metadata scopes.
- Validate edit targets against the current `ProgramSnapshot` before writing.
- Centralize CSV/JSON/Pascal metadata parsing and saving behind repository APIs.
- Add atomic write-with-backup behavior for all file-backed saves.
- Keep a separate advanced raw-file editor only if it is intentionally documented as a low-level utility.

### 5. GUI architecture has not moved to session/controller ownership

The GUI view models still own rerun orchestration, search state, metadata editor plumbing, and rendered-line navigation. The planned `DocumentSessionController`, `DocumentPresentationModel`, `SearchController`, and `MetadataEditCoordinator` are not implemented.

Required changes:

- Introduce `DocumentSessionController` as the only GUI-facing owner of open sessions, reruns, invalidation handling, and cancellation.
- Move filtered-line construction and sidebar derivation into a presentation model built from `DisassemblyDocument` and `DocumentIndexes`.
- Move search to the document index rather than scanning rendered lines as the primary path.
- Convert selection/navigation to `DocumentNodeID`, `ProcedureID`, `LocationID`, and `InstructionID`; keep string anchors only for display compatibility.

### 6. Source maps and document indexes need deeper population

The document has a `sourceMap`, but its population depends on references exposed by the legacy renderer. Many document nodes cannot yet be mapped precisely back to source instructions, locations, or procedure facts.

Required changes:

- Build document nodes from `ProgramSnapshot` wherever possible instead of reverse-mapping rendered legacy lines.
- Add source references for procedure headers, variable/location declarations, pseudocode statements, P-code instructions, assembler lines, diagnostics, and comments.
- Add snapshot tests for source-map coverage on representative fixtures.
- Use source-map coverage metrics in `RunReport` so regressions are visible.

### 7. Immutable snapshots lack complete provenance and status detail

`ProgramSnapshot` captures key facts, but not all useful facts carry provenance. `RunReport` does not yet fully distinguish fatal failures, degraded success, incomplete procedure analysis, metadata warnings, fixed-point non-convergence, and cancellation.

Required changes:

- Add provenance to user-visible names, types, signatures, comments, and inferred facts.
- Expand run status into fatal/degraded/incomplete/cancelled categories.
- Add bounded fixed-point convergence reporting for signature/type propagation.
- Map report status to CLI exit behavior and GUI status messages.

### 8. Physical target split remains deferred

The logical architecture still lives inside the single `pdisasm` target. This is acceptable for now, but it allows accidental dependency drift.

Required changes:

- Keep physical target splitting deferred until stage boundaries stabilize.
- In the meantime, enforce directory/file-level dependency rules with tests or a lightweight architecture check script.
- Split targets only after `domain`, `metadata`, `analysis`, `document`, `rendering`, and `application` APIs stop churning.

## Recommended implementation plan

### Phase A: lock current seams and deterministic inputs

1. Add an in-memory metadata repository and tests for metadata precedence.
2. Add a service test that runs from `.bytes` and an explicit metadata snapshot.
3. Introduce a metadata scope resolver that converts workspace/project/application-support state into a `MetadataSnapshot` before analysis.
4. Add a legacy adapter that accepts `MetadataSnapshot` directly.

Exit criteria:

- `DisassemblyService` can run without reading application-support metadata when metadata is provided explicitly.
- CLI and GUI still support existing workspace metadata behavior through the resolver adapter.

### Phase B: extract stage facades around the legacy pipeline

1. Create stage input/output structs matching the review contract.
2. Move codefile loading and metadata merge out of the legacy runner first.
3. Wrap decode/reference/analysis/signature behavior as coarse stages while preserving legacy internals.
4. Populate `RunReport` exclusively from stage results.

Exit criteria:

- Each stage can be invoked in a test with in-memory inputs.
- Stage metrics and diagnostics identify where degraded output originated.

### Phase C: make document generation snapshot-first

1. Build procedure, variable, instruction, pseudocode, assembler, diagnostic, and comment nodes from `ProgramSnapshot`.
2. Treat the current structured-line renderer as a compatibility renderer, not the document source of truth.
3. Improve source-map and index coverage until GUI navigation no longer depends on rendered anchor strings.
4. Keep text snapshots comparing the new document-derived renderer to current output.

Exit criteria:

- Renderers no longer require mutable legacy procedures.
- Source-map coverage is measured and tested.

### Phase D: centralize metadata edits and invalidation

1. Define typed metadata edit commands for labels, procedure names, parameters, return types, and comments.
2. Validate commands against `ProgramSnapshot` and return diagnostics with invalidation scope.
3. Implement atomic file-backed saves with backups.
4. Replace GUI metadata writes with `MetadataEditingService` commands.

Exit criteria:

- GUI edit paths no longer parse metadata files or choose metadata filenames.
- Comment edits patch documents; signature/type edits return procedure/call-graph/full-rerun scopes.

### Phase E: add GUI session ownership

1. Implement `DocumentSessionController` for open/rerun/apply-edit/cancel behavior.
2. Split current GUI state into session state, presentation model, search controller, and edit coordinator.
3. Move search to `DocumentIndexes.search(_:)`, falling back to rendered text only for compatibility.
4. Cancel stale runs when options or selected files change.

Exit criteria:

- The GUI is a presentation layer over application services.
- Rerun and invalidation policy exists in one place.

### Phase F: formalize status, provenance, and architecture enforcement

1. Expand `RunReport` status semantics and CLI exit mapping.
2. Add provenance to all user-visible facts in snapshots/documents.
3. Add architecture checks for forbidden imports/dependencies while targets remain consolidated.
4. Create ADRs for metadata scopes, ID serialization, snapshot boundary, document contract, invalidation policy, and run status semantics.

Exit criteria:

- Batch/CI callers can distinguish success, degraded success, cancellation, and fatal errors.
- Future refactors have enforceable boundaries and documented decisions.

## Suggested next pull requests

1. **Deterministic metadata input PR:** in-memory repository, metadata scope resolver, direct snapshot injection into legacy runner, and tests proving no implicit app-support reads.
2. **Stage facade PR:** codefile-load and metadata-merge stages plus coarse legacy decode/analyze stages and richer `RunReport` metrics.
3. **Document source-map PR:** snapshot-first document nodes for procedure headers and instructions, source-map coverage metric, and fixture tests.
4. **Typed metadata command PR:** edit-command model, snapshot validation, atomic writes, and GUI comment-edit migration.
5. **Session controller PR:** GUI `DocumentSessionController`, cancellation of stale runs, and search via `DocumentIndexes`.

## Verification commands

- `git status --short`
- `rg -n "struct (CodeFileID|SegmentID|ProcedureID|InstructionID|LocationID|CallEdgeID)|struct DisassemblyRunRequest|struct ProgramSnapshot|struct DisassemblyDocument|struct DocumentIndexes|struct MetadataEditingService|protocol MetadataRepository|struct DisassemblyService|struct BatchDisassemblyService|JSONDocumentExporter|CallGraphExporter|renderDisassemblyDocument|#if os\\(macOS\\)|dependencies: \\[\\]" Sources Package.swift`
- `swift test`
