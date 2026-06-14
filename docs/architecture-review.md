# pdisasm Architecture Review and Target Architecture

## Executive summary

pdisasm is best understood as a disassembler workbench for Apple Pascal P-code binaries. The core product loop is: load a code file, decode segment and procedure structure, apply user/system metadata, infer stack/type/procedure information, render human-readable disassembly and pseudocode, and let users improve metadata through the GUI so subsequent runs become more intelligible.

The project already has a useful separation between a core Swift package (`pdisasm`), a CLI (`pdisasm-cli`), and a macOS GUI (`pdisasm-gui-lib` / `pdisasm-gui`). Preserve that direction. The largest architectural risk is that the core analysis pipeline is still organized around mutable reference models, process-global filesystem conventions, repeated whole-program passes, and presentation-aware side effects. That makes correctness hard to reason about, limits scalability to larger binaries or batch workflows, and forces the GUI to duplicate persistence logic that should belong to the domain/application layer.

The target architecture should make disassembly an explicit, deterministic pipeline over immutable snapshots, move metadata persistence behind repository interfaces, introduce stable domain identifiers and indexes, separate rendering from analysis, and expose both CLI and GUI through the same application-service API.

## Inferred product behavior

### Primary users and workflow

- A reverse engineer or maintainer opens an Apple Pascal code file (`.bin` or equivalent codefile image).
- The app reads the segment dictionary, identifies code and data segments, decodes Pascal and assembler procedures, tracks call relationships, and resolves memory locations.
- The app combines inferred facts with user/system metadata from Application Support files: labels, procedures, records, type definitions, globals, and comments.
- The app emits several synchronized views of the same program:
  - segment/procedure structure;
  - raw P-code or 6502 assembly;
  - inferred stack state;
  - pseudocode;
  - variables, globals, diagnostics, and type conflicts.
- Users can search, filter sections, select/copy output, jump between procedures, and edit labels, procedure signatures, and comments.
- Edits are written to metadata files and the disassembly is rerun so the output reflects the new knowledge.

### Non-functional expectations implied by the app

- Determinism: the same binary plus same metadata should produce the same result.
- Recoverability: malformed or partially understood binaries should produce diagnostics rather than crashing.
- Incremental enrichment: user metadata should be preserved and should override lower-confidence inferred metadata.
- Responsiveness: the GUI should remain interactive while disassembling, rendering, and searching.
- Inspectability: generated output should explain conflicts and uncertainty instead of silently choosing one interpretation.

## Existing architecture snapshot

```text
pdisasm-cli / pdisasm-gui
        |
        v
Application entry points
- runPdisasm / disassemble(...)
- DisassemblyViewModel.runDisassembly(...)
        |
        v
Core pipeline in pdisasm
1. read codefile and segment dictionary
2. load metadata from Application Support
3. decode code segments/procedures
4. normalize calls and locations
5. stack simulation, type inference, signature synchronization
6. render structured output or text
7. optionally write metadata
        |
        v
Filesystem metadata
- labels_*.csv
- procedures_*.csv
- records_*.json
- types_*.pas
- comments_*.json
```

## Good parts to preserve

1. **Package-level separation exists.** The core disassembler is a library target and both CLI and GUI consume it. This is the right foundation for shared behavior and automated testing.
2. **Structured output is already modeled.** `OutputLine`, `LineKind`, anchors, edit targets, and instruction/location references give the GUI a semantic model instead of forcing it to scrape plain text.
3. **Diagnostics are part of the result.** Returning diagnostics and type conflicts is better than hiding uncertainty in logs or throwing on every unknown construct.
4. **Metadata is externalized.** CSV/JSON/Pascal metadata files are easy to inspect, edit, back up, and version independently from the binary.
5. **The GUI avoids blocking the main actor for disassembly.** Running disassembly and rendering in detached tasks is the correct direction for responsiveness.
6. **There is broad regression coverage.** Snapshot, fixture, decoder, stack simulator, and edge-case tests indicate a culture of protecting reverse-engineering behavior.

## Architectural flaws and scalability risks

### 1. The core pipeline is procedural and mutation-heavy

`disassemble(...)` coordinates reading files, metadata resolution, decoding, normalization, analysis, rendering inputs, diagnostics, and optional metadata writes. Many stages mutate shared collections (`allLocations`, `allProcedures`, `allCallers`) and reference-typed model objects in place.

**Risk:** adding new analyses will increase pass-order coupling. A later pass can accidentally depend on mutation from an earlier pass without a type-level contract. Parallelization and caching are difficult because the pipeline does not expose stable intermediate snapshots.

**Target direction:** represent each pipeline step as a pure or mostly-pure transformer with explicit inputs and outputs. Where mutation is needed for performance, keep it inside the stage and return an immutable `ProgramSnapshot`.

### 2. Analysis and persistence are coupled

The disassembly entry point constructs a metadata context from the source file and reads/writes directly under Application Support. The GUI also writes labels, procedure signatures, and comments directly to those same formats.

**Risk:** CLI, GUI, tests, and future batch tools will diverge. It is hard to support alternate metadata stores, project-local metadata, dry runs, import/export, conflict resolution, or cloud sync.

**Target direction:** define `MetadataRepository` and `MetadataWorkspace` protocols. The core pipeline receives metadata as values. Application services own repository selection, merge policy, and writeback.

### 3. GUI view model contains application and infrastructure logic

`DisassemblyViewModel` manages UI state, background tasks, output filtering, search, metadata filename selection, CSV parsing/escaping, JSON comment persistence, and rerun orchestration.

**Risk:** this class will continue to grow as every product feature arrives. It is hard to test without AppKit/SwiftUI context, and metadata bugs may be fixed in one path but not another.

**Target direction:** split into:

- `DisassemblyDocumentController`: open/restore/rerun document use cases;
- `MetadataEditingService`: edit label/signature/comment commands;
- `OutputFilterModel` and `SearchIndex`: pure UI-support models;
- thin `DisassemblyViewModel`: observable state and command forwarding only.

### 4. Whole-program reruns are the only consistency mechanism

After metadata edits, the GUI writes the file and reruns the full disassembly. Search and filtering are already optimized, but semantic edits invalidate the entire pipeline.

**Risk:** this is acceptable for small fixtures but will not scale to larger libraries, many open documents, or live editing. It also obscures whether an edit only changes rendering or changes inference.

**Target direction:** introduce invalidation scopes:

- comment-only edit: patch rendered line/comment overlay, no analysis rerun;
- label rename/type edit: rerun affected procedure/segment analyses where possible;
- signature edit: rerun call graph/type propagation for dependent callers/callees;
- metadata schema import: full rerun.

Full rerun can remain the correctness fallback while incremental paths are added.

### 5. Domain identity is not centralized

The code uses several ad hoc identity shapes: segment/procedure pairs, optional lexical levels, addresses, strings like `"2.3"`, and CSV rows. Matching logic is repeated in GUI helpers and core functions.

**Risk:** collisions and stale references become likely as support expands to multiple files, overlaid segments, assembler entry points, or procedure aliases.

**Target direction:** define canonical identity types:

- `ProgramID` or `CodeFileID`;
- `SegmentID`;
- `ProcedureID`;
- `InstructionID`;
- `LocationID`;
- `MetadataScope` (`system(version)`, `file(fileID)`, `project(path)`).

Every rendered line and metadata row should carry these IDs rather than requiring textual reconstruction.

### 6. Output rendering is too close to analysis data structures

Rendering currently consumes mutable domain objects and encodes GUI affordances (line kinds, edit ranges, anchors) directly in the core output model.

**Risk:** plain text output, structured GUI output, future JSON export, and HTML/Markdown reports will constrain each other. Rendering can accidentally rely on mutable analysis state rather than a stable output contract.

**Target direction:** introduce an intermediate `DisassemblyDocument` model: segments, procedures, instructions, pseudocode blocks, declarations, diagnostics, and cross references. Renderers convert the document into CLI text, GUI lines, JSON, DOT, or Markdown.

### 7. Search is line-scan based and tied to filtered output

The GUI has an asynchronous chunked regex scan over visible lines, which is a pragmatic improvement. However, search currently treats rendered lines as the source of truth.

**Risk:** searching large outputs remains O(rendered lines) per query and cannot easily support structured searches such as `procedure:`, `segment:`, `type:`, `calls:`, `addr:`, or symbol-only matches.

**Target direction:** build a lightweight `SearchIndex` when a document is rendered. Index text tokens plus structured fields and update it incrementally for comment/label edits.

### 8. Metadata merge semantics are implicit

There is clear intent around source precedence (`unknown`, `inferred`, `procedureSignature`, `metadata`, `user`), but repository-level merge behavior is scattered. Some loads replace collections; others union or append.

**Risk:** user edits can be shadowed, duplicate procedures can accumulate, and system metadata can override file metadata in surprising ways.

**Target direction:** make merge policy explicit and testable:

```text
system defaults < version metadata < file metadata < project metadata < user edits
```

Every merged fact should keep provenance and confidence.

### 9. Error handling mixes recoverable diagnostics with thrown failures

The decoder often records diagnostics and continues, while file and parsing errors may throw or be swallowed depending on the path.

**Risk:** callers cannot consistently tell whether output is complete, degraded, or invalid. Silent metadata parse failures can produce misleading disassembly.

**Target direction:** return a `RunReport` with:

- fatal error, if the codefile cannot be read or minimally parsed;
- warnings for skipped segments/procedures and metadata failures;
- completeness flags by segment/procedure;
- metadata load/write status.

### 10. Memory and CPU costs grow with repeated rendered snapshots

The GUI stores all rendered lines, filtered lines, indexes, editable maps, search matches, and the full disassembly result. The pipeline also repeats analysis passes to converge signatures.

**Risk:** larger binaries will multiply memory use, and repeated stack/type passes may become quadratic if call graph and symbol lookup remain linear scans.

**Target direction:** maintain indexed snapshots:

- `proceduresByID`;
- `instructionsByID` or per-procedure instruction arrays;
- `locationsByID` and `locationsByName`;
- `callsByOrigin` and `callsByTarget`;
- lazy rendered sections for GUI virtualization.

## Target architecture

### Architectural principles

1. **Deterministic core.** Core analysis should not depend on process-global paths, UI state, or current time except where explicitly injected.
2. **Explicit stages.** Each stage declares input and output models.
3. **Immutable snapshots at boundaries.** Mutable internals are allowed only within a stage.
4. **One application API.** CLI and GUI should use the same use cases.
5. **Metadata as data, not side effect.** Load, merge, edit, and persist metadata through repositories and commands.
6. **Progressive scalability.** Keep full rerun as fallback, but design APIs that can support incremental invalidation.

### Proposed module boundaries

```text
pdisasm-core
  Domain IDs and value models
  Codefile reader
  Segment/procedure/instruction decoders
  Analysis passes
  Diagnostics

pdisasm-metadata
  Metadata schemas
  MetadataRepository protocol
  CSV/JSON/Pascal repository implementation
  Merge policies and provenance

pdisasm-application
  DisassemblyService
  MetadataEditingService
  Project/session orchestration
  Incremental invalidation policy

pdisasm-rendering
  DisassemblyDocument
  Text/CLI renderer
  Structured GUI renderer
  JSON/Markdown/DOT renderers

pdisasm-cli
  Argument parsing only
  Calls application services and renderers

pdisasm-gui-lib
  Observable view models
  Document state
  Search/filter/navigation models
```

This can be implemented inside the existing package targets first; physical target splits can follow once seams are stable.

### Target data flow

```text
OpenDocumentCommand
        |
        v
MetadataWorkspaceResolver
        |
        +--> MetadataRepository.load(scope list)
        |
        v
DisassemblyService.run(request)
        |
        +--> CodeFileReader.read
        +--> SegmentDictionaryDecoder.decode
        +--> MetadataMerger.merge
        +--> ProgramDecoder.decodeSegments
        +--> AnalysisPipeline.run(stages)
        +--> ProgramSnapshot + RunReport
        |
        v
DocumentBuilder.build(snapshot)
        |
        +--> Renderer.render(document, options)
        +--> SearchIndex.build(document)
        |
        v
CLI / GUI presentation
```

### Core domain model

Recommended primary types:

```swift
struct CodeFileID: Hashable, Codable { let value: String }
struct SegmentID: Hashable, Codable { let file: CodeFileID; let number: Int }
struct ProcedureID: Hashable, Codable { let segment: SegmentID; let number: Int }
struct InstructionID: Hashable, Codable { let procedure: ProcedureID; let address: Int }
struct LocationID: Hashable, Codable {
    let segment: SegmentID
    let procedure: Int?
    let lexicalLevel: Int?
    let address: Int?
}
```

Recommended snapshot shape:

```swift
struct ProgramSnapshot: Sendable {
    let file: CodeFileSummary
    let segments: [SegmentID: SegmentSnapshot]
    let procedures: [ProcedureID: ProcedureSnapshot]
    let callsByOrigin: [ProcedureID: [CallEdge]]
    let callsByTarget: [ProcedureID: [CallEdge]]
    let locations: [LocationID: LocationFact]
    let types: TypeEnvironment
    let diagnostics: [Diagnostic]
}
```

### Analysis pipeline stages

1. **Codefile structure stage**
   - Input: bytes.
   - Output: segment dictionary and raw segment slices.
   - Failure mode: fatal if no valid codefile structure exists.

2. **Metadata merge stage**
   - Input: repository facts and segment version/file ID.
   - Output: `MetadataSnapshot` with provenance.
   - Failure mode: degraded run with metadata diagnostics.

3. **Decode stage**
   - Input: segment slices and metadata hints.
   - Output: procedures, instructions, initial call edges, raw locations.
   - Failure mode: skip invalid procedures with procedure-level diagnostics.

4. **Resolution stage**
   - Input: decoded program.
   - Output: normalized locations, caller lexical levels, assembler targets.

5. **Stack/type analysis stage**
   - Input: resolved program and type environment.
   - Output: stack states, inferred variables, type conflicts, pseudocode IR.

6. **Signature synchronization stage**
   - Input: inferred calls/locations/procedure signatures.
   - Output: updated signature facts and conflict diagnostics.
   - Note: iterate to a bounded fixed point and report non-convergence instead of duplicating hard-coded passes.

7. **Document build stage**
   - Input: final snapshot.
   - Output: immutable `DisassemblyDocument` for rendering/search.

### Metadata architecture

Define commands instead of ad hoc file edits:

```swift
enum MetadataEditCommand {
    case upsertLabel(LocationID, name: String, type: String?)
    case upsertProcedureName(ProcedureID, name: String)
    case upsertParameter(ProcedureID, index: Int, name: String, type: String?)
    case upsertReturnType(ProcedureID, type: String?)
    case upsertComment(InstructionID, text: String?)
}
```

`MetadataEditingService` should:

1. validate command against the current snapshot;
2. load the appropriate metadata scope;
3. apply the edit in memory;
4. write atomically with backup;
5. return an invalidation scope.

### GUI architecture

Keep the GUI state machine simple:

```text
DisassemblyViewModel
  - selected file
  - loading/error/status
  - current rendered document
  - current UI options
  - delegates commands to services

DocumentPresentationModel
  - segments/procedures sidebar data
  - filtered output sections
  - selection state

SearchController
  - query
  - index
  - matches/current match
```

The view model should not parse CSV, choose metadata filenames, or construct repository paths.

### CLI architecture

The CLI should be a thin adapter:

1. parse arguments;
2. build `DisassemblyRunRequest`;
3. call `DisassemblyService`;
4. choose renderer/options;
5. print output and diagnostics;
6. exit non-zero only for fatal run failures, not ordinary reverse-engineering warnings.

### Scalability roadmap

#### Phase 1: Establish seams without behavior change

- Add `DisassemblyRunRequest` and `DisassemblyService` wrapper around existing `disassemble(...)`.
- Add `MetadataRepository` protocol and move GUI metadata edits behind `MetadataEditingService` while preserving current file formats.
- Add canonical ID wrappers and bridge them to existing models.
- Add tests for metadata merge precedence and edit commands.

#### Phase 2: Snapshot and indexing

- Build `ProgramSnapshot` after the current mutable pipeline completes.
- Create indexes for procedures, locations, calls, and instructions.
- Refactor renderers to consume the snapshot/document instead of mutable procedure objects.
- Replace string anchors with typed IDs converted to strings only at the UI boundary.

#### Phase 3: Pipeline stage isolation

- Extract decode, normalization, stack/type inference, and signature synchronization into stage types.
- Make pass iteration bounded and report convergence status.
- Add per-stage timing and count metrics to diagnostics.

#### Phase 4: Incremental UI behavior

- Apply comment edits without rerunning analysis.
- Apply label-only edits by patching document/rendered output where safe.
- Use dependency indexes for scoped reruns after signature/type edits.
- Add cancellation/progress for long-running runs.

#### Phase 5: Project/workspace support

- Support project-local metadata directories in addition to Application Support.
- Add import/export and metadata validation commands.
- Add JSON output for external tooling.

## Decision records to create next

1. **ADR: Metadata scope and precedence.** Decide whether Application Support remains the default, whether project-local metadata is supported, and how conflicts are resolved.
2. **ADR: Stable identity model.** Specify exact ID fields and serialization for segments, procedures, instructions, and locations.
3. **ADR: Snapshot vs mutable model.** Define which types are immutable API contracts and which remain mutable internals.
4. **ADR: Renderer contract.** Decide whether `OutputLine` remains core API or moves to GUI rendering.
5. **ADR: Incremental invalidation policy.** Document which edit commands require full, scoped, or no rerun.

## Assumptions challenged

- **Assumption: disassembly must rerun after every edit.** Comments and many label changes are presentation overlays; rerunning is safe but unnecessarily expensive.
- **Assumption: Application Support is the metadata source of truth.** This is convenient for an app, but poor for reproducible research, collaboration, and CI fixtures.
- **Assumption: rendered lines are the search corpus.** Users will eventually need symbol-, address-, procedure-, and type-aware search.
- **Assumption: two analysis passes are enough.** Signature/type propagation should be modeled as a fixed-point process with convergence diagnostics.
- **Assumption: procedure number plus segment is always sufficient.** As assembler support and multiple files/projects grow, canonical IDs must include file/workspace scope and instruction/location identity.

## Quality bar for future changes

Any substantial new feature should answer:

1. Which pipeline stage owns this behavior?
2. Is the behavior deterministic for the same binary and metadata?
3. What metadata scope and precedence apply?
4. What is the invalidation scope after an edit?
5. Can the CLI and GUI both use the same service?
6. What diagnostics are emitted when the feature cannot fully understand the input?
7. What index prevents repeated linear scans on large programs?
