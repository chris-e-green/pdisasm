# New architecture implementation verification

Verification date: 2026-06-19.

## Result

The replacement architecture is **partially implemented and materially further along than the previous verification snapshot**. The branch has real service-oriented seams from `docs/architecture-review.md`: canonical IDs, a shared `DisassemblyService`, immutable snapshot/document/index products, a metadata repository facade, export renderers, typed metadata edit commands, coarse pipeline stage facades, provenance/status models, and source-map coverage metrics.

The implementation is still transitional. The application boundary is now service-shaped, deterministic metadata can be injected, and tests cover important architecture seams, but the central decode/reference/analysis/signature work is still wrapped by a legacy mutable disassembler rather than split into the deterministic staged architecture described in the review.

The next work should therefore avoid a broad rewrite. The recommended path is to keep hardening the existing seams, split the remaining legacy middle into independently testable stages, and then make document generation snapshot-first for normal runs.

## Implemented

- Core package boundaries are in place inside the existing Swift package: `pdisasm` has no target dependencies, the CLI depends only on `pdisasm`, and the package has no external dependencies.
- macOS-only GUI targets are guarded by `#if os(macOS)`, so Linux builds and tests compile only portable targets.
- Canonical IDs exist for code files, segments, procedures, instructions, locations, call edges, metadata facts, documents, and document nodes, with adapter initializers for legacy identifiers and references.
- `DisassemblyService` provides a shared application API that returns a legacy result, immutable `ProgramSnapshot`, `DisassemblyDocument`, `DocumentIndexes`, and `RunReport`.
- `DisassemblyRunRequest` has source, explicit metadata snapshot, optional workspace, options, and cancellation-token fields.
- `RunStatus`, `StageStatus`, `StageReport`, and `RunReport` distinguish success, degraded success, cancellation, and fatal errors, and map run status to process exit codes.
- `CodefileLoadStage`, `MetadataMergeStage`, `LegacyPipelineStages`, `SnapshotBuildStage`, and `DocumentBuildStage` provide coarse stage facades with typed inputs/outputs and metrics.
- Deterministic metadata injection is now supported for service runs that provide an explicit `MetadataSnapshot`; workspace loading is an adapter that resolves metadata before the legacy analysis call.
- `ProgramSnapshot` includes code-file summary, segment dictionary summary, type-environment summary, segment/procedure/instruction/location facts, call indexes, diagnostics, and selected provenance for user-visible facts.
- `DisassemblyDocument` includes sections, document nodes, node lookup, a source-map field, comment patching support, and a source-map coverage metric.
- `DocumentIndexes` exposes procedure, location, instruction, symbol, and token search indexes.
- Metadata persistence is isolated behind `MetadataRepository`, `FileBackedMetadataRepository`, `InMemoryMetadataRepository`, `MetadataScopeResolver`, provenance-aware bundles/snapshots, and `MetadataEditingService` invalidation scopes.
- Typed metadata edit commands now exist for labels, procedure names, parameters, return types, and comments, with validation against a current `ProgramSnapshot` when available.
- Metadata invalidation scopes now include document-only updates, document patches, procedure signatures, call-graph propagation, full disassembly, and no-op/error cases.
- The CLI is a thin adapter that parses fixed arguments, invokes `DisassemblyService` or `BatchDisassemblyService`, selects text, JSON, or call-graph output, and exits using `RunStatus.processExitCode`.
- Rendering/export seams exist for text documents, stable JSON export, and DOT call-graph export.
- Architecture-focused tests cover deterministic byte-source runs with in-memory metadata, stage facades, source-map references, provenance, status semantics, metadata precedence, typed edit commands, invalidation, and consolidated-target dependency checks.
- Linux test coverage currently passes for the portable targets.

## Remaining gaps

### 1. The middle of the analysis pipeline is still legacy-backed

`DisassemblyService` now calls separate codefile-load, metadata-merge, snapshot-build, and document-build stages, but the decode/reference/analysis/signature work still flows through `LegacyPipelineStages`, which delegates to `disassemble(...)`. This means the central domain work remains a mutable legacy operation with a new service boundary around it.

Required changes:

- Extract `SegmentDecodeStage`, `ReferenceResolutionStage`, `AnalysisStage`, and `SignatureConvergenceStage` from the legacy runner.
- Preserve current algorithms initially, but give each stage typed input/output values, metrics, diagnostics, and fatality/completeness rules.
- Move stage report construction out of the legacy runner and into the stages that own the corresponding work.
- Add in-memory unit tests for each extracted stage before attempting behavioral changes.

### 2. Deterministic metadata injection is mostly implemented but still coupled to legacy adapters

Explicit `MetadataSnapshot` input now works and tests prove `.bytes` plus in-memory metadata can run without reading application-support metadata. However, the metadata snapshot is still translated into the legacy disassembler path, and some file/version metadata scope decisions remain close to compatibility logic.

Required changes:

- Keep `MetadataScopeResolver` as the application-layer adapter for workspace/application-support metadata.
- Continue removing filename-oriented metadata assumptions from analysis internals.
- Ensure every metadata-dependent analysis path consumes the resolved `MetadataSnapshot`, not repository or file-system state.
- Add regression tests for project/workspace/application-support precedence as new scopes are introduced.

### 3. Cancellation is still boundary-oriented

The request supports `CancellationToken`, and stages check cancellation at service/stage boundaries. The legacy disassembler remains mostly synchronous and cannot reliably stop in the middle of decode, reference resolution, stack simulation, type inference, or signature convergence.

Required changes:

- Thread a lightweight cancellation/progress context through the extracted decode and analysis stages.
- Check cancellation at segment, procedure, instruction, and fixed-point-iteration boundaries.
- Preserve the distinct cancelled status/error so CLI, batch, and GUI callers can distinguish cancellation from malformed input.
- Update GUI loading paths to cancel obsolete runs when a new file or option set is selected.

### 4. Document generation is not yet snapshot-first for normal runs

The `DisassemblyDocument` contract is in place, source-map coverage is measured, and a snapshot-derived document builder exists. For normal disassembly runs, however, `DocumentBuildStage` still builds compatibility documents from legacy structured output lines and reverse-maps those lines to snapshot facts.

Required changes:

- Build normal document nodes from `ProgramSnapshot` wherever possible instead of from legacy structured lines.
- Add source references for procedure headers, variable/location declarations, pseudocode statements, P-code instructions, assembler lines, diagnostics, and comments.
- Keep the current structured-line renderer as a compatibility renderer and regression oracle while the snapshot-first document renderer matures.
- Add source-map coverage thresholds for representative fixtures so regressions are visible in tests and `RunReport` metrics.

### 5. Metadata editing still has compatibility escape hatches

Typed metadata commands and validation exist, but compatibility APIs still allow raw metadata filenames and the GUI metadata editor still supports direct raw-file discovery/editing workflows. This is useful for low-level maintenance, but it should not remain the primary edit path.

Required changes:

- Keep filename/raw-file APIs documented as advanced escape hatches only.
- Route normal GUI metadata edits through typed `MetadataEditCommand` values and `MetadataEditingService`.
- Validate edit targets against the current `ProgramSnapshot` before writing whenever a snapshot is available.
- Centralize CSV/JSON/Pascal metadata parsing and saving behind repository APIs.
- Ensure atomic write-with-backup behavior covers all file-backed saves used by typed edit commands.

### 6. GUI architecture has not fully moved to session/controller ownership

A `DocumentSessionController` exists, but the GUI is not yet fully reduced to a presentation layer over application services. View models still own some rerun orchestration, search state, metadata editor plumbing, rendered-line filtering, and navigation behavior.

Required changes:

- Make `DocumentSessionController` the only GUI-facing owner of open sessions, reruns, invalidation handling, and cancellation.
- Move filtered-line construction and sidebar derivation into a presentation model built from `DisassemblyDocument` and `DocumentIndexes`.
- Move search to `DocumentIndexes.search(_:)`, falling back to rendered text only for compatibility.
- Convert selection/navigation to `DocumentNodeID`, `ProcedureID`, `LocationID`, and `InstructionID`; keep string anchors only for display compatibility.

### 7. Provenance and status are present but not complete

`FactProvenance`, metadata provenance, `RunStatus`, and stage status are now in place. Snapshot facts carry selected provenance, and CLI exit mapping exists. The model still does not capture complete provenance for every user-visible name/type/signature/comment/inferred fact, and fixed-point convergence detail is still coarse.

Required changes:

- Add provenance to all user-visible names, types, signatures, comments, and inferred facts that can affect user trust.
- Add bounded fixed-point convergence reporting for signature/type propagation.
- Preserve fatal/degraded/incomplete/cancelled distinctions across batch and GUI reporting.
- Make metadata warnings, malformed-procedure degradation, and non-convergence visible in both CLI and GUI status surfaces.

### 8. Physical target split remains deferred

The logical architecture still lives inside the single `pdisasm` target. This remains acceptable while APIs churn, but it allows accidental dependency drift.

Required changes:

- Keep physical target splitting deferred until stage boundaries stabilize.
- Continue enforcing directory/file-level dependency rules with tests or lightweight architecture checks while targets remain consolidated.
- Split targets only after `domain`, `metadata`, `analysis`, `document`, `rendering`, and `application` APIs stop churning.

## Recommended implementation plan

### Phase A: finish splitting the legacy middle

1. Extract `SegmentDecodeStage`, `ReferenceResolutionStage`, `AnalysisStage`, and `SignatureConvergenceStage` as coarse wrappers around existing code.
2. Define stage input/output structs matching the review contract.
3. Preserve existing behavior and rendered output while relocating stage ownership and report construction.
4. Add in-memory tests for each stage.

Exit criteria:

- Each major analysis stage can be invoked in a test with in-memory inputs.
- `RunReport` stage metrics and diagnostics identify where degraded output originated.
- `LegacyPipelineStages` no longer hides decode/reference/analysis/signature work behind one opaque call.

### Phase B: make document generation snapshot-first

1. Build procedure, variable, instruction, pseudocode, assembler, diagnostic, and comment nodes from `ProgramSnapshot`.
2. Treat the current structured-line renderer as a compatibility renderer, not the document source of truth.
3. Improve source-map and index coverage until GUI navigation no longer depends on rendered anchor strings.
4. Keep text snapshots comparing the new document-derived renderer to current output.

Exit criteria:

- Renderers no longer require mutable legacy procedures for normal output.
- Source-map coverage is measured, thresholded, and tested.

### Phase C: centralize metadata edits and invalidation

1. Route normal GUI edits through typed metadata commands.
2. Validate commands against `ProgramSnapshot` and return diagnostics with invalidation scope.
3. Ensure atomic file-backed saves with backups for all typed edit paths.
4. Keep raw metadata file editing as an explicitly documented advanced utility.

Exit criteria:

- GUI edit paths no longer choose metadata filenames for normal operations.
- Comment edits patch documents; signature/type edits return procedure/call-graph/full-rerun scopes.

### Phase D: add GUI session ownership and cancellation

1. Make `DocumentSessionController` own open/rerun/apply-edit/cancel behavior.
2. Split current GUI state into session state, presentation model, search controller, and edit coordinator.
3. Move search to `DocumentIndexes.search(_:)`, falling back to rendered text only for compatibility.
4. Cancel stale runs when options or selected files change.

Exit criteria:

- The GUI is a presentation layer over application services.
- Rerun and invalidation policy exists in one place.
- Stale background work is cancelled predictably.

### Phase E: formalize status, provenance, and architecture enforcement

1. Complete provenance for user-visible facts in snapshots/documents.
2. Add convergence/detail reporting for type and signature propagation.
3. Expand architecture checks for forbidden imports/dependencies while targets remain consolidated.
4. Keep ADRs updated as stage, metadata, document, invalidation, and status contracts evolve.

Exit criteria:

- Batch/CI callers can distinguish success, degraded success, cancellation, fatal errors, non-convergence, and malformed-input degradation.
- Future refactors have enforceable boundaries and documented decisions.

### Phase F: split physical targets after boundaries stabilize

1. Split `domain`, `metadata`, `analysis`, `document`, `rendering`, and `application` APIs into separate package targets only after stage APIs stop churning.
2. Preserve existing CLI and GUI public behavior during the split.
3. Keep architecture-boundary tests as package dependency tests once targets are separate.

Exit criteria:

- Target dependencies match the review's intended dependency direction.
- Accidental dependency drift is prevented by Swift package structure instead of only tests.

## Suggested next pull requests

1. **Legacy middle stage extraction PR:** split `LegacyPipelineStages` into `SegmentDecodeStage`, `ReferenceResolutionStage`, `AnalysisStage`, and `SignatureConvergenceStage` wrappers with typed outputs and per-stage tests.
2. **Snapshot-first document PR:** make normal document generation use `ProgramSnapshot`, add source-map coverage thresholds, and keep renderer-output snapshots stable.
3. **GUI typed-edit PR:** route normal label/procedure/comment edits through `MetadataEditingService` and reserve raw metadata editing for advanced workflows.
4. **GUI session/cancellation PR:** consolidate open/rerun/apply-edit/cancel behavior in `DocumentSessionController` and cancel stale runs.
5. **Provenance/status completion PR:** add full fact provenance and convergence/degradation reporting across CLI, batch, and GUI surfaces.

## Verification commands

- `git status --short --branch`
- `rg -n "struct (CodeFileID|SegmentID|ProcedureID|InstructionID|LocationID|CallEdgeID)|struct DisassemblyRunRequest|struct ProgramSnapshot|struct DisassemblyDocument|struct DocumentIndexes|struct MetadataEditingService|protocol MetadataRepository|struct DisassemblyService|struct BatchDisassemblyService|JSONDocumentExporter|CallGraphExporter|renderDisassemblyDocument|struct CodefileLoadStage|struct MetadataMergeStage|struct LegacyPipelineStages|RunStatus|StageStatus|#if os\\(macOS\\)|dependencies: \\[\\]" Sources Package.swift`
- `swift test`
