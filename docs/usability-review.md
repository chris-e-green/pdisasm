# pdisasm usability review

## Purpose and method

This is a static UX review of the current Swift package, focused on the work of
a reverse engineer: opening an unfamiliar binary, judging output quality,
following relationships, correcting recovered facts, and exporting or
repeating the analysis. It reviews the CLI, macOS GUI, metadata editor, output
model, documentation, tests, and stated roadmap. It is not a replacement for
observed usability testing; visual rendering, VoiceOver behaviour, and real
world file sizes should be validated with representative users and binaries.

Severity uses **P0** for a workflow that produces misleading or unusable
results, **P1** for a high-frequency task failure or serious loss of trust,
**P2** for a substantial efficiency/discoverability problem, and **P3** for a
polish or accessibility risk.

## Executive summary

The project has a promising foundation for an analyst: a native file workflow,
incremental search, multi-line copy, a segment/procedure index, typed metadata,
structured documents, diagnostics, JSON/DOT export, and cancellation-aware
runs. The primary UX risk is not a lack of features; it is that important
analysis context is hidden, fragmented, or inconsistent between surfaces.

Prioritize three things first:

1. Make the CLI's default output match the documented and expected analysis
   view.
2. Make the GUI an inspection workspace rather than a flat rendered-text
   viewer: expose representation, confidence, diagnostics, and typed
   navigation.
3. Make edits safe and explainable by showing provenance, scope, validation,
   and the effect of a save before it is committed.

## Findings and recommendations

| Priority | Issue and evidence | Recommendation | Basis and success measure |
| --- | --- | --- |
| P0 | **The CLI default hides the primary analysis representations.** `PdisasmCLI` initializes `showMarkup`, `showPcode`, and `showPseudocode` to `false`, then explicitly passes those values to `renderDisassemblyDocument`. The README says a normal invocation prints disassembly and pseudocode, while the library-level `DisassemblyOptions` defaults those views to `true`. | Make normal CLI output show P-code and pseudocode (and decide deliberately whether headings/markup are on). Keep flags as explicit opt-in/opt-out presentation controls; a `--quiet` or representation selector is clearer than a set of only-enable flags. Add `--help` examples that show the default and a representation-only invocation. | Reverse engineers need a trustworthy first view; an apparently successful command that omits the main analysis is easy to misdiagnose. A default invocation on the bundled fixture should visibly include P-code and pseudocode, with a regression test comparing the enabled line kinds. |
| P1 | **The GUI cannot select dialect or view source reconstruction.** The CLI exposes `--dialect` and `--show-source`, but `DocumentSessionController` builds GUI options from only `verbose` and `showStackState`; the GUI display menu has no source or dialect control. This is especially material because UCSD behaviour is explicitly provisional. | Add an analysis-options control before/reload: dialect, source reconstruction, and a concise warning for provisional UCSD output. Persist the selection per document. Place source in a distinct representation tab/pane, not as an interleaved toggle in the main table. | Dialect and source mode change interpretation, not cosmetic display. A user should be able to identify the active dialect and switch it without leaving the GUI; the resulting document should label the representation and policy used. |
| P1 | **Run quality is not surfaced as a first-class outcome in the GUI.** `RunReport` records degraded, cancelled, and fatal states, stage metrics, warnings, metadata warnings, and convergence. The GUI status bar reports segment/procedure/line counts, while diagnostics appear only as ordinary output rows and only subtle red backgrounds distinguish them. | Add a persistent run-status summary beside the file name: success/degraded/cancelled, warning count, metadata warning count, and convergence. Selecting it should open a Diagnostics panel grouped by stage and severity, with links to affected procedures/instructions where possible. | In reverse engineering, uncertainty is evidence. Users must distinguish “no issue” from “analysis completed with gaps.” Acceptance: a malformed or non-convergent fixture visibly reports degraded status and its reason without requiring a text search. |
| P1 | **The main GUI is a single flattened document rather than an investigation workspace.** Sidebar selection scrolls the one table to a procedure anchor. The table has only line number and text; calls, locations, source maps, P-code, pseudocode, and assembly are not navigable representations. The existing TODO and architecture review already call for hierarchical panes and cross-links. | Move toward a three-pane investigation layout: segment/file overview, procedure/call list, and selected representation. Provide explicit P-code, pseudocode, source, and assembler views with synchronized selection. Add callers, callees, cross-references, locations, and diagnostics as inspector tabs, using typed IDs rather than text matching. | Analysts repeatedly move between a call site, callee, variable, and evidence. Scrolling a flat transcript is slow and loses context. Test with tasks such as “find every caller of procedure X” and “inspect the declaration and all uses of global Y”; both should complete through visible navigation, without manual search. |
| P1 | **Provenance and confidence are mostly invisible at the point of use.** The model stores metadata precedence and selected fact provenance, and type sources exist, but the output table and edit sheets show only a name/type string. An analyst cannot tell whether a label/type was decoded, inferred, bundled, or user-supplied before replacing it. | Add an inspector/details popover for every editable procedure, location, and comment: value, source/provenance, precedence, inference rationale where available, and affected output. Mark uncertain inferred facts with an icon/text label, not colour alone. Preserve the provenance in copy/export. | Trustworthy reverse-engineering tools expose evidence and uncertainty so that edits are informed rather than destructive. Success: before editing a type, a user can identify its source and see whether a user fact would override it. |
| P1 | **Metadata editing has two inconsistent mental models and insufficient safety cues.** Inline edits use `MetadataEditingService`, but the separate window is described in code as a low-level raw-file editor, discovers only Application Support files, and exposes CSV/JSON/Pascal text editing. It does not explain scope/precedence or show whether an open file's active workspace is being edited. Existing architecture verification identifies raw editing as an advanced escape hatch. | Make typed, contextual edits the default: open an inspector from the selected fact, state the target scope and destination, validate before save, and preview invalidation/rerun impact. Clearly label the raw editor “Advanced,” show its exact workspace and precedence, offer backup/restore, and warn before saving malformed or shadowed facts. | Metadata errors can silently change future analyses. Acceptance: an analyst can answer “where will this edit be saved, what does it override, and what will update?” before Save; invalid CSV/JSON/type definitions cannot be persisted without an actionable warning. |
| P2 | **Edit and navigation affordances are hidden or ambiguous.** Double-clicking a rendered row may edit a procedure signature, comment, or location based on character offset; the context menu exposes only “Edit Comment,” not location/signature editing. A procedure-like token does not navigate to its target. | Use explicit inline links and inspector buttons: “Go to definition,” “Show callers,” “Rename,” “Edit type,” and “Add/Edit comment.” Keep double-click only as a documented shortcut with visible hover/selection feedback. | Hidden gestures are hard to discover and risky when the same action can open different editors. Success: a first-time user can navigate to a referenced procedure and edit a location through labelled controls, with no guesswork about click position. |
| P2 | **Display controls mix cheap filtering with expensive re-analysis without explaining the cost.** Markup, P-code, pseudocode, and variables filter existing lines; enabling Stack State re-runs the disassembly. The menu does not communicate this difference, duration, or cancellation control. | Separate “View” filters from “Analysis options.” When an option requires rerun, show “Re-analyse” in the label, retain the previous document until the new result is ready, show progress/cancel, and preserve selection/scroll by typed target. | Predictable response time is essential in exploratory work. Success: toggling a view never clears the document; changing a rerun option clearly indicates work is underway and leaves the last valid result available. |
| P2 | **Search is capable but under-explained and weakly scoped.** It supports case-insensitive whole-word wildcard matching, asynchronous progress, and indexed search fallback, but the UI provides only a generic field and match count. It has no visible “no matches” state, scope selector, result list, or search by address/procedure/location/caller. | Add a search-mode/scope control with plain text, identifier/address, procedure, location, and diagnostic modes. Show the active matching rules and an explicit no-results message. Offer a result list with representation and procedure context, and keep the current query/filter visible. | Text search is a fallback, not a substitute for semantic navigation. Measure time-to-find for an address, a generated variable, and a callee; each should return contextual results without users learning wildcard rules. |
| P2 | **The current output table suppresses structural scanning cues.** It has no visible column headers, hierarchy, folding, representation label, address column, or severity column. Line kind is communicated mainly by low-alpha background colour and a long mixed text cell. | Make the table representation-aware: include address/offset, procedure, representation, and severity columns where applicable; allow section collapse and sticky procedure context. Provide accessible text/icon labels for line kinds and do not use colour as the only signal. | Reverse-engineering output is dense. Stable structure reduces visual search and supports keyboard/assistive-technology users. Validate at default macOS contrast settings and with a long fixture: procedure boundaries, diagnostics, and representation changes must remain identifiable without colour. |
| P2 | **The CLI is difficult to learn safely.** Help is a single usage line, `--rewrite` overwrites generated metadata, exports have single-file restrictions, a default input is implicit, and batch output reports only a start message plus process status. | Replace the one-line help with grouped options, defaults, examples, exit-status meanings, and prominent write/export constraints. Require a confirmation flag or a dry-run summary before destructive metadata rewrite; print per-file summaries and failures in batch mode. | Terminal users need discoverability and safe automation. Acceptance: `--help` alone explains how to inspect one file, export JSON/DOT, select a workspace/dialect, and avoid unintended writes; batch runs list each outcome and path. |
| P3 | **Onboarding and recovery are thin.** The empty state gives a simple open-file instruction, while supported input expectations, metadata location, dialect limitations, diagnostic meaning, and recovery from a failed/partial run are dispersed across README and code. | Add a short in-app “Getting started” sheet and contextual help: supported files, a sample fixture, representation explanation, metadata storage, keyboard shortcuts, and the meaning of degraded output. Make error states offer retry, reveal file, and copy diagnostics. | The first successful interpretation is where users form a mental model of the tool. Test with a new user opening the sample fixture: they should locate a procedure, inspect diagnostics, and understand how an inferred name can be corrected without external documentation. |

## Recommended delivery sequence

### 1. Restore trustworthy first results

Fix CLI defaults and expand help. Add GUI run-status/diagnostics visibility and
show the active representation/dialect. These changes reduce the chance that a
user mistakes missing or degraded analysis for a valid result.

### 2. Make uncertainty and editing safe

Add provenance to the selected fact inspector, contextual typed edits, metadata
validation, save destination/precedence disclosure, and raw-editor safeguards.
This should be designed together: source, confidence, and edit effect are one
user decision.

### 3. Reframe the GUI around investigation tasks

Implement typed navigation and the procedure/call/location inspector before
adding more formatting. Then split representations into synchronized panes or
tabs. This follows the existing document-set and typed-ID architecture direction
in `docs/architecture-review.md` and avoids building more interaction on text
anchors.

### 4. Improve efficiency and accessibility

Add scoped search, sectioning, keyboard-visible actions, non-colour line-kind
indicators, and clear rerun behaviour. Test with long and malformed binaries,
not only the happy-path fixture.

## Research and validation plan

Recruit 5–7 users with a mix of Apple Pascal familiarity and general
reverse-engineering experience. Use an instrumented build and representative
clean, metadata-rich, malformed, and large binaries. Ask participants to:

1. Open a binary and determine whether the analysis is complete and reliable.
2. Find a procedure from one call site, then list its callers and inspect its
   P-code and pseudocode.
3. Determine the provenance of a variable type, correct it, and confirm the
   scope/effect of the change.
4. Find a warning, explain its impact, and export data for follow-up.
5. Run the same task in CLI mode, including a safe metadata workspace and batch
   run.

Track task completion, time, wrong edits, unexpected reruns, use of external
documentation, and whether users can correctly state the analysis status and
metadata provenance. Treat a user accepting inferred output as certain, or
editing the wrong metadata scope, as a critical trust failure even if the task
technically completes.

## Evidence reviewed

- `README.md` and `TODO.md` for documented capability and acknowledged GUI
  workflow gaps.
- `Sources/pdisasm-cli/main.swift` for CLI defaults, help, exports, and batch
  behaviour.
- `Sources/pdisasm-gui-lib/ContentView.swift`, `DisassemblyViewModel.swift`,
  `DisassemblyTableView.swift`, `DocumentSessionController.swift`,
  `MetadataEditorView.swift`, and `MetadataViewModel.swift` for GUI states,
  editing, search, navigation, and persistence behaviour.
- `Sources/pdisasm/DisassemblyService.swift`, `Output.swift`, `Export.swift`,
  and `Runner.swift` for option defaults, diagnostics, reports, and exports.
- `docs/architecture-review.md` and
  `docs/new-architecture-verification.md` for confirmed architectural and UX
  transition constraints.
