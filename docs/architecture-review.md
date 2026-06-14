# pdisasm Replacement Architecture Review

## 1. Executive summary

pdisasm is a reverse-engineering workbench for Apple Pascal P-code codefiles. The current codebase has the right top-level product split: a reusable disassembler library, a command-line adapter, a macOS GUI library, and a GUI executable. The implementation also has strong domain momentum: structured output lines, diagnostics, stack simulation, type inference, metadata files, and broad test coverage already exist.

The central architectural issue is that the core library is not yet shaped as a deterministic analysis product. It is organized as a long procedural run that performs file I/O, metadata discovery, mutable decoding, cross-reference normalization, analysis, rendering preparation, diagnostics, and metadata writeback through shared objects. The GUI then duplicates infrastructure concerns such as metadata filename selection, CSV/JSON persistence, rerun orchestration, and rendered-line search.

The replacement architecture should not be a rewrite for its own sake. It should preserve the domain knowledge and test fixtures while replacing the seams around it. The target system is a staged pipeline that transforms bytes and metadata into immutable program snapshots, documents, indexes, and renderable views. CLI and GUI entry points should call the same application services. Metadata edits should be commands handled by a metadata service, returning explicit invalidation scopes instead of forcing every UI action to know how much of the pipeline to rerun.

## 2. Architectural audit

### 2.1 Current module topology

```text
Package.swift
├── pdisasm          Core library: codefile parsing, metadata, decoding, analysis, rendering models
├── pdisasm-cli      CLI argument parsing and execution
├── pdisasm-gui-lib  SwiftUI/AppKit-facing view models and views
├── pdisasm-gui      GUI executable shell
└── pdisasmTests     Unit, fixture, integration, and snapshot tests
```

This topology is directionally correct. The replacement design should first introduce new seams inside the existing targets, then optionally split physical package targets once the APIs stabilize.

### 2.2 Existing execution flow

```text
CLI / GUI
  │
  ├─ read selected file URL and presentation options
  │
  ▼
runPdisasm / disassemble
  │
  ├─ read codefile and segment dictionary
  ├─ derive Application Support metadata filenames from file name and system version
  ├─ load labels, procedures, records, types, globals, comments
  ├─ decode code/data segments and procedures
  ├─ mutate procedure, location, and caller collections during normalization
  ├─ run stack, type, call, and signature analysis passes
  ├─ collect diagnostics and type conflicts
  └─ return DisassemblyResult plus renderable line data
  │
  ▼
CLI text / GUI structured lines
```

### 2.3 Strengths to preserve

- **Reusable library boundary.** The core implementation is already in a library target consumed by both the CLI and GUI.
- **Typed domain concepts.** The codebase contains explicit models for segments, procedures, locations, calls, instructions, diagnostics, stack simulation, pseudocode, and metadata.
- **Structured output.** GUI-facing output lines have kinds, anchors, references, and edit targets rather than only plain strings.
- **Recoverability mindset.** Diagnostics and edge-case tests show the system is expected to continue when a binary is partially understood.
- **Human-editable metadata.** CSV, JSON, and Pascal-like metadata are inspectable and can be versioned outside the binary.
- **Substantial regression suite.** Snapshot and fixture tests provide safety rails for refactoring the analysis pipeline.

### 2.4 Principal risks

#### Risk 1: the core pipeline has implicit stage contracts

The disassembly entry point currently owns too many responsibilities. File loading, metadata context construction, decode orchestration, normalization, analysis, rendering support, and persistence concerns are co-located. Shared mutable collections and reference-typed model objects encode stage ordering implicitly.

**Impact:** future analyses become harder to add safely because they may depend on side effects from previous passes. Caching, parallelization, deterministic replay, and scoped reruns are difficult.

**Replacement:** define explicit pipeline stages with typed inputs and outputs. Internally mutable algorithms are acceptable, but every public stage boundary should return immutable value snapshots.

#### Risk 2: metadata persistence leaks into analysis and GUI code

The current metadata context derives Application Support filenames from the source file and segment version. The GUI also performs metadata edits and persistence-oriented behavior.

**Impact:** CLI, GUI, tests, and future automation can diverge. Project-local metadata, dry runs, import/export, backups, sync, and conflict handling all become harder.

**Replacement:** introduce `MetadataRepository`, `MetadataWorkspace`, `MetadataMerger`, and `MetadataEditingService`. The pipeline receives a `MetadataSnapshot`; application services choose where metadata comes from and how edits are persisted.

#### Risk 3: domain identity is fragmented

The system uses several identity forms: segment/procedure pairs, lexical levels, addresses, instruction references, anchor strings, metadata row keys, and GUI sidebar strings.

**Impact:** aliases, assembler entry points, multiple codefiles, overlaid segments, stale rendered-line references, and metadata conflicts will become increasingly risky.

**Replacement:** define canonical IDs for codefiles, segments, procedures, instructions, locations, calls, metadata facts, and rendered document nodes. String anchors become a UI serialization detail.

#### Risk 4: rendering and analysis are too coupled

The output layer exposes useful structured lines, but it also mixes rendering concerns with analysis objects. Rendered text is treated as a search corpus and sometimes as an editing/navigation substrate.

**Impact:** CLI text, GUI lines, JSON export, Markdown reports, graph output, and search behavior can constrain one another.

**Replacement:** introduce a `DisassemblyDocument` intermediate representation. Renderers consume documents; search indexes consume documents; edit commands target canonical IDs.

#### Risk 5: full rerun is the only consistency strategy

The GUI reruns disassembly after metadata edits. This is correct as a conservative fallback, but it is not a scalable invalidation model.

**Impact:** comments, labels, and display-only edits pay the same cost as type/signature edits. Larger binaries and interactive metadata editing will feel slower.

**Replacement:** metadata commands return invalidation scopes: no analysis, document patch, procedure rerun, segment rerun, call-graph propagation, or full rerun.

#### Risk 6: analysis status is under-specified

Diagnostics exist, but the run result does not yet distinguish clearly among fatal failure, degraded success, incomplete procedure analysis, metadata load/write warnings, and fixed-point non-convergence.

**Impact:** CLI exit behavior, GUI status, tests, and automated batch processing cannot reliably reason about completeness.

**Replacement:** return a `RunReport` that contains fatal errors, warnings, per-stage metrics, completeness flags, metadata status, and convergence status.

## 3. Replacement architecture

### 3.1 Design principles

1. **Deterministic by default.** The same bytes, metadata snapshot, options, and tool version produce the same snapshot and document.
2. **Side effects at the edges.** File I/O, Application Support paths, user defaults, and UI state live outside the analysis pipeline.
3. **Immutable stage boundaries.** Pipeline stages may use mutation internally but publish immutable results.
4. **Stable identity everywhere.** All facts, references, rendered nodes, and edit commands carry typed IDs.
5. **One application API.** CLI, GUI, tests, and future batch tools use the same services.
6. **Diagnostics are product output.** Partial understanding is represented explicitly, not hidden in logs.
7. **Full rerun remains a fallback.** Incremental paths are introduced only when their invalidation rules are testable.

### 3.2 Logical components

```text
pdisasm-domain
  Canonical IDs, value models, diagnostics, run options, stage reports

pdisasm-codefile
  Byte source abstraction, codefile reader, segment dictionary decoder, raw segment slicing

pdisasm-metadata
  Metadata schemas, repositories, workspace resolution, provenance, merge policy, edit commands

pdisasm-analysis
  P-code and 6502 decoding, procedure discovery, control flow, stack simulation,
  type inference, signature propagation, call graph construction

pdisasm-document
  ProgramSnapshot, DisassemblyDocument, cross-reference indexes, search index

pdisasm-rendering
  CLI text renderer, GUI line renderer, JSON renderer, graph renderer

pdisasm-application
  DisassemblyService, MetadataEditingService, DocumentSessionController,
  incremental invalidation policy, progress/cancellation hooks

pdisasm-cli
  Argument parsing, service invocation, renderer selection, process exit mapping

pdisasm-gui-lib
  Observable state, view-specific presentation models, commands forwarded to services
```

These can initially be Swift namespaces/files within existing package targets. Physical target extraction should wait until dependency direction is clean.

### 3.3 Target dependency rule

```text
GUI / CLI
  → application
    → rendering / document
      → analysis / metadata / codefile
        → domain
```

Forbidden dependencies:

- domain must not depend on Foundation filesystem APIs except where unavoidable for value formatting;
- analysis must not read or write Application Support;
- rendering must not mutate analysis objects;
- GUI must not parse metadata files directly;
- CLI must not duplicate pipeline orchestration.

### 3.4 Canonical identity model

Recommended IDs:

```swift
struct CodeFileID: Hashable, Codable, Sendable { let value: String }
struct SegmentID: Hashable, Codable, Sendable { let file: CodeFileID; let number: Int }
struct ProcedureID: Hashable, Codable, Sendable { let segment: SegmentID; let number: Int }
struct InstructionID: Hashable, Codable, Sendable { let procedure: ProcedureID; let offset: Int }
struct LocationID: Hashable, Codable, Sendable {
    let segment: SegmentID
    let procedure: ProcedureID?
    let lexicalLevel: Int?
    let address: Int?
}
struct CallEdgeID: Hashable, Codable, Sendable { let origin: InstructionID; let target: ProcedureID }
```

Identity rules:

- IDs are created during codefile ingestion and preserved throughout analysis, document building, rendering, search, and metadata edits.
- String forms such as `"2.3"` are display/serialization forms, not domain identity.
- Metadata rows store typed IDs or canonical serialized IDs.
- If legacy CSV formats cannot store full IDs immediately, adapters translate between legacy keys and typed IDs at repository boundaries.

### 3.5 Core request/result contracts

```swift
struct DisassemblyRunRequest: Sendable {
    let source: CodeFileSource
    let metadata: MetadataSnapshot
    let options: DisassemblyOptions
    let cancellation: CancellationToken?
}

struct DisassemblyRunResult: Sendable {
    let snapshot: ProgramSnapshot
    let document: DisassemblyDocument
    let indexes: DocumentIndexes
    let report: RunReport
}
```

`CodeFileSource` can represent bytes, a file URL, or a test fixture. The service layer resolves URLs into bytes before invoking deterministic analysis.

### 3.6 Program snapshot

```swift
struct ProgramSnapshot: Sendable {
    let file: CodeFileSummary
    let segmentDictionary: SegmentDictionarySnapshot
    let segments: [SegmentID: SegmentSnapshot]
    let procedures: [ProcedureID: ProcedureSnapshot]
    let instructions: [InstructionID: InstructionSnapshot]
    let callsByOrigin: [ProcedureID: [CallEdge]]
    let callsByTarget: [ProcedureID: [CallEdge]]
    let locations: [LocationID: LocationFact]
    let typeEnvironment: TypeEnvironmentSnapshot
    let diagnostics: [Diagnostic]
}
```

Snapshot rules:

- snapshots are immutable and safe to share between background tasks and the main actor;
- every fact keeps provenance where useful: decoded, inferred, system metadata, file metadata, user edit;
- all lookup-heavy relationships have indexes built once, not repeated linear scans in UI code;
- snapshots do not contain presentation-only state such as selected line, current search match, or filtered visibility.

### 3.7 Pipeline stages

```text
1. CodefileLoadStage
   Input: bytes and source identity
   Output: raw codefile, segment dictionary, raw segment slices
   Fatal: unreadable or structurally invalid codefile

2. MetadataMergeStage
   Input: repository facts, file/version context, merge policy
   Output: MetadataSnapshot with provenance and diagnostics
   Fatal: never, unless configured as strict

3. SegmentDecodeStage
   Input: raw segments and metadata hints
   Output: decoded segment/procedure/instruction facts
   Fatal: no; invalid procedures become diagnostics and incomplete procedure flags

4. ReferenceResolutionStage
   Input: decoded facts and call/location hints
   Output: normalized locations, call graph, cross references
   Fatal: no

5. AnalysisStage
   Input: resolved program and metadata type environment
   Output: stack states, inferred variables, type facts, pseudocode IR
   Fatal: no; unknowns become diagnostics

6. SignatureConvergenceStage
   Input: call graph, inferred signatures, metadata signatures
   Output: final signature facts and convergence report
   Fatal: no; non-convergence is a warning with bounded iteration count

7. SnapshotBuildStage
   Input: final mutable analysis workspace
   Output: immutable ProgramSnapshot and indexes
   Fatal: no if previous stages produced at least a degraded program

8. DocumentBuildStage
   Input: ProgramSnapshot and document options
   Output: DisassemblyDocument
   Fatal: no
```

### 3.8 Metadata architecture

Metadata is modeled as facts plus provenance:

```swift
enum MetadataScope: Hashable, Codable, Sendable {
    case bundledSystem(version: Int)
    case applicationSupport(file: CodeFileID)
    case projectDirectory(URL)
    case transientUserSession(UUID)
}

struct MetadataFact<Value: Sendable>: Sendable {
    let id: MetadataFactID
    let scope: MetadataScope
    let provenance: MetadataProvenance
    let value: Value
}
```

Default precedence:

```text
bundled defaults
  < system version metadata
  < project metadata
  < file metadata
  < current user edits
```

Repository API:

```swift
protocol MetadataRepository: Sendable {
    func load(_ scopes: [MetadataScope]) async throws -> [MetadataBundle]
    func save(_ bundle: MetadataBundle, to scope: MetadataScope) async throws
}
```

Editing API:

```swift
enum MetadataEditCommand: Sendable {
    case upsertLabel(LocationID, name: String, type: String?)
    case renameProcedure(ProcedureID, name: String)
    case upsertParameter(ProcedureID, index: Int, name: String, type: String?)
    case upsertReturnType(ProcedureID, type: String?)
    case upsertComment(InstructionID, text: String?)
}

enum InvalidationScope: Sendable {
    case none
    case patchDocument([DocumentNodeID])
    case rerunProcedure(ProcedureID)
    case rerunSegment(SegmentID)
    case propagateCallGraph(Set<ProcedureID>)
    case fullRerun
}
```

`MetadataEditingService` responsibilities:

1. validate edit target against the current snapshot;
2. apply merge/precedence rules;
3. write atomically with backup when persistence is requested;
4. return diagnostics and invalidation scope;
5. never require the GUI to know metadata filenames or CSV escaping rules.

### 3.9 Document and rendering architecture

`DisassemblyDocument` is the rendering-neutral representation:

```swift
struct DisassemblyDocument: Sendable {
    let id: DocumentID
    let title: String
    let sections: [DocumentSection]
    let nodesByID: [DocumentNodeID: DocumentNode]
    let sourceMap: [DocumentNodeID: SourceReference]
}
```

Renderers:

- `PlainTextRenderer`: CLI and snapshot fixtures;
- `StructuredLineRenderer`: GUI table/list rows with kinds, anchors, edit ranges, and references;
- `JSONRenderer`: machine-readable exports;
- `GraphRenderer`: call graph/control-flow graph exports.

Rendering rules:

- renderers consume `DisassemblyDocument`, not mutable procedures;
- renderers may be cached by document ID and options;
- display filters hide/show rendered nodes without changing the underlying document;
- search indexes are built from document nodes plus structured fields, not only from rendered text.

### 3.10 Application services

```swift
actor DisassemblyService {
    func run(_ request: DisassemblyRunRequest) async -> DisassemblyRunResult
}

actor DocumentSessionController {
    func open(url: URL, options: DisassemblyOptions) async -> DocumentSession
    func apply(_ command: MetadataEditCommand, to session: DocumentSessionID) async -> EditResult
    func rerun(_ session: DocumentSessionID, scope: InvalidationScope) async -> DocumentSession
}
```

Service responsibilities:

- resolve workspace and metadata scopes;
- load and merge metadata;
- run the deterministic pipeline;
- build document/index/rendered-line artifacts;
- expose progress and cancellation;
- own rerun/invalidation policy;
- present a single API to CLI and GUI.

### 3.11 GUI replacement structure

```text
DisassemblyViewModel
  - selected file/session
  - loading/error/status
  - current presentation model
  - forwards commands to DocumentSessionController

DocumentPresentationModel
  - sidebar sections
  - filtered rendered lines
  - selected output lines
  - current scroll requests

SearchController
  - query state
  - async index lookup
  - current match navigation

MetadataEditCoordinator
  - draft state only
  - command construction
  - validation messages returned from service
```

The GUI should not:

- construct Application Support metadata paths;
- parse or write CSV/JSON metadata;
- infer whether an edit needs a full rerun;
- use rendered anchor strings as domain identifiers.

### 3.12 CLI replacement structure

CLI flow:

1. parse arguments;
2. create a `DisassemblyRunRequest` through `DisassemblyCommandFactory`;
3. invoke `DisassemblyService`;
4. render requested format;
5. write diagnostics to stderr or structured output;
6. exit `0` for successful/degraded disassembly, non-zero only for fatal errors or strict-mode violations.

## 4. Greenfield implementation plan

### Phase 0: protect behavior before refactoring

- Identify golden fixtures for representative Pascal, assembler, malformed, system-library, metadata-rich, and GUI-edit workflows.
- Add snapshot tests for structured document output, not just final text.
- Add tests that assert diagnostics for malformed inputs and metadata parse failures.
- Add performance baselines for large fixture disassembly and GUI search.

Exit criteria:

- existing behavior is captured well enough to refactor without relying on manual inspection;
- CI can compare old text output and new document-derived text output.

### Phase 1: introduce domain IDs and request/result wrappers

- Add canonical ID value types.
- Add `DisassemblyRunRequest`, `DisassemblyRunResult`, `RunReport`, and `DisassemblyOptions`.
- Wrap the existing `disassemble(...)` implementation behind `DisassemblyService` without changing behavior.
- Create adapters from legacy segment/procedure/location references to new IDs.

Exit criteria:

- CLI and GUI can call the service wrapper;
- legacy tests still pass;
- new IDs appear in structured output and edit targets.

### Phase 2: isolate metadata

- Define `MetadataRepository`, `MetadataWorkspace`, `MetadataBundle`, and `MetadataSnapshot`.
- Move file naming, Application Support resolution, CSV/JSON parsing, and atomic writes behind repository implementations.
- Replace GUI metadata writes with `MetadataEditingService` commands.
- Add merge precedence tests and edit-command tests.

Exit criteria:

- GUI no longer parses or writes metadata formats directly;
- CLI, GUI, and tests can use file-backed or in-memory metadata repositories;
- every merged metadata fact has provenance.

### Phase 3: build immutable snapshots and indexes

- Build `ProgramSnapshot` from the current mutable pipeline output.
- Add procedure, instruction, location, call-origin, call-target, and symbol indexes.
- Add a document builder that consumes `ProgramSnapshot`.
- Make text output render from `DisassemblyDocument` and compare against existing snapshots.

Exit criteria:

- renderers no longer need direct access to mutable procedures;
- GUI navigation and edits target typed IDs;
- repeated linear scans in common UI paths are replaced by indexes.

### Phase 4: split pipeline stages

- Extract codefile loading, metadata merge, decode, reference resolution, analysis, signature convergence, snapshot build, and document build into explicit stage types.
- Replace hard-coded repeated signature/type passes with a bounded fixed-point loop.
- Add per-stage metrics and completeness flags to `RunReport`.
- Ensure each stage can be tested independently with in-memory inputs.

Exit criteria:

- pass ordering is expressed in stage composition, not incidental mutation;
- non-convergence and skipped procedures are visible diagnostics;
- stage-level tests cover malformed and partial inputs.

### Phase 5: implement incremental invalidation

Start conservatively:

1. comment edits patch document nodes and rendered lines without rerun;
2. display-only label edits patch document nodes when no analysis fact changes;
3. signature edits rerun dependent call graph scopes;
4. unknown or conflicting edits fall back to full rerun.

Exit criteria:

- every edit command has a tested invalidation scope;
- full rerun remains available and produces the same result as incremental paths;
- GUI remains responsive during reruns and supports cancellation.

### Phase 6: add workspace and export capabilities

- Support project-local metadata directories.
- Add metadata validation and import/export commands.
- Add JSON document output and call graph export.
- Add batch-mode CLI for multiple codefiles sharing one workspace.

Exit criteria:

- analysis is reproducible in CI with checked-in metadata;
- external tools can consume stable JSON;
- multiple files can be analyzed without identity collisions.

## 5. Greenfield vertical slice

If starting from an empty repository while preserving current product requirements, build in this order:

1. **Domain package:** IDs, diagnostics, run options, codefile summaries, metadata fact model.
2. **Codefile reader:** load bytes, parse segment dictionary, expose raw segment slices.
3. **Minimal decoder:** decode one procedure into instruction snapshots with diagnostics.
4. **Snapshot builder:** produce `ProgramSnapshot` and indexes for decoded procedures.
5. **Text renderer:** produce CLI-compatible text from `DisassemblyDocument`.
6. **Metadata repository:** read labels/procedures/comments from in-memory and file-backed stores.
7. **Application service:** deterministic run from bytes plus metadata to snapshot/document/report.
8. **CLI:** thin adapter over the service and text renderer.
9. **Analysis passes:** stack simulation, type inference, pseudocode, calls, signature convergence.
10. **GUI:** session controller, presentation model, structured line renderer, search index, metadata commands.
11. **Incremental editing:** command invalidation and scoped reruns.
12. **Exports/workspaces:** project metadata, JSON, graph output, batch analysis.

This order keeps every milestone runnable and testable.

## 6. Migration strategy from current code

- **Do not rewrite the decoder first.** Wrap it, snapshot its output, and preserve fixture behavior.
- **Move side effects outward first.** Metadata and file access seams unlock deterministic tests.
- **Introduce IDs before incremental behavior.** Invalidation is unsafe without stable identity.
- **Build new renderers in parallel.** Compare new document-derived text against current snapshots until equivalent.
- **Retire legacy paths only after parity.** Keep adapters until CLI, GUI, and tests use the new services.

## 7. Architecture decision records to create

1. **ADR-001: Metadata scopes and precedence.** Define system, project, file, and user-edit ordering.
2. **ADR-002: Canonical ID serialization.** Define stable string forms for codefile, segment, procedure, instruction, and location IDs.
3. **ADR-003: Snapshot boundary.** Define which models are immutable public contracts and which remain mutable internals.
4. **ADR-004: Document/rendering contract.** Decide the lifetime of `OutputLine` and the shape of `DisassemblyDocument`.
5. **ADR-005: Invalidation policy.** Define command-to-scope rules and fallback behavior.
6. **ADR-006: Run status semantics.** Define fatal, degraded, incomplete, warning, and strict-mode exit behavior.

## 8. Review checklist for future changes

Every substantial change should answer:

- Which pipeline stage owns the behavior?
- What canonical IDs does it create or consume?
- Is it deterministic for the same bytes, metadata, and options?
- What diagnostics are emitted for partial or failed understanding?
- Which metadata scope and precedence rules apply?
- What invalidation scope follows a related edit?
- Can CLI and GUI use the same service path?
- Which index prevents repeated linear scans?
- Which fixture or snapshot protects the behavior?
