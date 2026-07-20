# pdisasm GUI Functional Specification

This document describes the macOS GUI as currently implemented. It is intended as an implementation-derived functional specification that can be compared with the original product intentions.

## 1. System Overview

The GUI is a macOS SwiftUI application composed of two targets:

- `pdisasm-gui`: the app entry point, menu commands, window definitions, and app delegate.
- `pdisasm-gui-lib`: reusable SwiftUI/AppKit views and observable view models that drive disassembly display and metadata editing.

The GUI is available only on macOS and requires macOS 14 or newer through the package platform declaration. It wraps the core `pdisasm` library and `DisassemblyService` to open Apple Pascal P-code binaries, render disassembly output, navigate segments and procedures, search the generated output, copy selected rows, edit metadata-backed names/types/comments, and inspect/edit metadata files stored in the user metadata workspace.

## 2. Supported Runtime Context

- The Swift package declares the core library, CLI, and tests on all supported platforms, but the GUI library and executable targets are added only under `#if os(macOS)`.
- The app uses Swift language mode 6 for both GUI targets.
- The GUI application promotes itself to a regular macOS application at launch so it has a menu bar, Dock icon, and standard quit support when run via `swift run`.

## 3. Windows and Application Shell

### 3.1 Main Window

The main `WindowGroup` hosts `ContentView` and defaults to a 1200×820 window. The title is the last opened file name when a file is loaded, otherwise `pdisasm`.

The main window uses a `NavigationSplitView`:

- Sidebar: segment/procedure navigation.
- Detail: disassembly output, loading/error/empty states, edit sheets, and status bar.

### 3.2 Metadata Editor Window

A second window group is registered with title `Metadata Editor` and id `metadata-editor`. It is opened from the File/New command replacement via `Metadata Editor` or the Command-Shift-M shortcut. The window receives the list of metadata filenames relevant to the currently loaded disassembly through shared GUI app state.

### 3.3 Settings Window

The settings scene contains informational text only. It states that metadata files are stored in `Application Support/pdisasm`.

## 4. Menu Commands and Keyboard Shortcuts

The application customizes standard command groups:

- Replaces New/Open menu behavior with:
  - `Open…` (`⌘O`), invoking the focused main-window file importer action.
  - `Metadata Editor` (`⇧⌘M`), opening the metadata editor window.
- Replaces Undo/Redo with commands that forward `undo:` and `redo:` through `NSApp.sendAction`.
- Replaces Cut/Copy/Paste with commands that forward text-editing actions; Copy first checks whether disassembly rows are selected and copies selected output lines if so.
- Adds Find commands after text editing:
  - `Find in Disassembly` (`⌘F`), focusing the search field.
  - `Find Next` (`⌘G`), moving to the next search match when matches exist.
  - `Find Previous` (`⇧⌘G`), moving to the previous search match when matches exist.
- Adds display toggles after the toolbar command group for Markup, P-Code, Stack State, Pseudocode, Variables, and Verbose Output. These are disabled when no main window exposes display-option focused values.

## 5. File Opening, Persistence, and Reload

### 5.1 Opening Files

The toolbar `Open File` button and `Open…` command show a file importer that accepts any data file and allows a single selection. On successful selection, the view model:

1. Opens a new document session for the URL and cancels any active run.
2. Stores the URL as the current file.
3. Adds the URL to the system recent-documents list.
4. Persists a security-scoped bookmark in user defaults.
5. Starts a disassembly run.

### 5.2 Last File Restoration

On the main view's first appearance, the view model attempts to resolve the persisted bookmark. If it resolves and security-scoped access can be started, the app reopens that file and runs disassembly automatically. Stale bookmarks are refreshed.

### 5.3 Reloading

When a file is open, the toolbar shows `Reload`. It reruns disassembly for the current file and is disabled while a run is loading.

## 6. Disassembly Execution Lifecycle

`DocumentSessionController` owns the document session, the current run task, cancellation token, source URL, and most recent run result.

### 6.1 Run Behavior

A run requires an open file. Starting a run cancels any previous run and creates a new generation number plus cancellation token. The controller invokes `DisassemblyService.run` on a detached user-initiated task with:

- Source: the current file URL.
- Options: current verbose setting and current stack-state setting.
- Cancellation: a GUI-owned cancellation token.

When the service returns, the controller builds a presentation model containing:

- The legacy disassembly result.
- The structured run result and document.
- Output lines from document nodes.
- Sidebar segment/procedure items.
- Metadata filenames relevant to the loaded file.

Generation checks prevent stale asynchronous results from replacing newer runs.

### 6.2 Loading and Error States

Before a run starts, the view model clears output, filtered lines, sidebar items, location indexes, search state, selection state, and any previous error. While running, the detail pane shows `Disassembling…`. Fatal errors are shown in an error unavailable-state view using the localized error description. Cancellation ends loading without replacing state.

## 7. Disassembly Display

### 7.1 Empty and Error States

The detail pane displays:

- `No Disassembly` when no output exists.
- `Error` when `errorMessage` is set.
- A progress view while `isLoading` is true.
- The disassembly table when output exists and no error/loading state applies.

The sidebar displays `No File Open` when no segments are available.

### 7.2 Output Header and Status Bar

The output header shows the current file name and a summary of enabled display options. A small progress indicator is included while search is running.

The status bar shows:

- `No file open` if no file is loaded.
- `Disassembling...` during runs.
- The current error text when an error exists.
- Otherwise counts for segments, procedures, filtered lines, selected rows, and search matches.
- The selected procedure identifier when one is selected.

### 7.3 Display Filters

The GUI stores all generated lines, then derives `filteredLines` based on display toggles. Optional line categories are controlled as follows:

- Markup lines shown only when Markup is enabled.
- P-Code lines shown only when P-Code is enabled.
- Pseudocode lines shown only when Pseudocode is enabled.
- Variable lines shown only when Variables is enabled.
- Global, header, and diagnostic lines are always shown.

Changing Markup, P-Code, Pseudocode, or Variables rebuilds filtered lines and search matches without rerunning disassembly. Changing Stack State reruns disassembly because stack-state annotations are generated by the underlying service. Verbose Output is included in summaries and passed into runs, but changing it does not currently trigger a rerun by itself.

## 8. Segment and Procedure Navigation

The sidebar lists decoded code segments sorted by segment number. Each section title is the segment name from the segment dictionary when available, otherwise `Segment N`. Procedures are displayed under their segment using the best available procedure short description.

Selecting a sidebar procedure stores its id as `segment.procedure`, looks up the corresponding filtered output index by line anchor, increments a scroll request counter, and asks the table to scroll to the procedure. If the selected procedure becomes hidden or unavailable after filtering, its filtered index becomes nil.

## 9. Output Table Interaction

The disassembly output uses an AppKit `NSTableView` embedded in SwiftUI. It has:

- A fixed-width line-number column showing `line.id + 1`.
- A monospace text column containing the disassembly line text.
- Vertical and horizontal scrolling.
- Multiple and empty selection.
- Plain table styling without headers.

The table synchronizes AppKit row selection with view-model selected output line ids. Selection can be copied through the toolbar button, context menu, or Copy command. Copied output is the selected visible lines' text joined with newline separators.

Double-clicking an output row initiates editing in this priority order:

1. Procedure signature element at the clicked character offset, if the row contains editable procedure-header targets.
2. Instruction comment, if the row has a comment reference.
3. Location name/type, if the row has a location reference or contains an editable location display name as a whole token.

The context menu contains Copy Selected Lines, Edit Comment, and Clear Selection. Edit Comment is enabled only for lines with a comment reference.

## 10. Search

### 10.1 Query Entry and Commitment

The toolbar contains a rounded search field. Typing schedules a debounced search commit after 250 ms. Pressing Return commits immediately. Empty or whitespace-only queries clear matches.

### 10.2 Matching Semantics

Search is case-insensitive and whole-word by default. The query is escaped as a regular expression except for wildcard support:

- `*` matches zero or more identifier characters (`A-Z`, `a-z`, `0-9`, `_`).
- `?` matches exactly one identifier character.

The final fallback regular expression is wrapped in word boundaries.

For non-wildcard queries, the GUI first asks the document indexes for matching node ids and maps them back to visible line indexes. If the indexed search yields visible matches, those are used. Otherwise, regex scanning is performed against visible output lines.

### 10.3 Large Output Behavior

For fewer than 3000 visible lines, fallback regex search is synchronous. For 3000 or more visible lines, the scan is chunked in batches of 750 lines and performed asynchronously. While asynchronous search is active, the toolbar displays progress, live match count, scanned line count, total line count, and percentage. The user can choose compact, medium, or wide width for this status area; the choice is persisted in user defaults.

### 10.4 Match Navigation

When matches exist, the toolbar shows `current/total`, Previous, and Next controls. Match navigation wraps at both ends. `⌘G` and `⇧⌘G` invoke the same actions. The table receives the current match index and match index set for scrolling/highlighting behavior.

## 11. Metadata-Backed Inline Editing

### 11.1 Location Editing

A location edit sheet presents the selected location's current name and type. Unknown display types are shown as an empty editable type field. Saving trims whitespace, constructs a `Location` with user type provenance when a type is supplied, and applies an upsert-label metadata edit through `MetadataEditingService` and `FileBackedMetadataRepository`.

### 11.2 Procedure Signature Editing

Procedure signature editing supports:

- Procedure name edits.
- Parameter name and type edits.
- Function return type edits.

The editable fields depend on the clicked header target. Saving preserves the existing procedure identity and applies the relevant metadata edit: rename procedure, upsert parameter, or upsert return type. Parameter type value `POINTER` is normalized to an empty type before saving. Empty types are stored with unknown type provenance; non-empty edited types use user provenance.

The edit context includes the current code file id, detected system metadata version, known system segment numbers, and all decoded procedures. Only functions can edit return type.

### 11.3 Comment Editing

A comment edit sheet presents the instruction reference and current user comment. Saving trims whitespace and applies an upsert-comment edit. If the edit can be represented as an instruction id, the returned invalidation scope is applied. If not, no invalidation is requested.

### 11.4 Invalidation Handling

After metadata edits:

- `.none` performs no update.
- `.documentOnly` and `.patchDocument` patch a comment in the current structured document when possible; otherwise they rerun disassembly.
- `.procedureSignature`, `.propagateCallGraph`, and `.fullDisassembly` rerun disassembly.

After rerun/patch, the view model rebuilds line filters, location indexes, sidebar data, and relevant metadata filenames. For location/comment edits initiated from a filtered output row, the table attempts to restore scroll position to the original filtered row index, clamped to the new filtered-line bounds.

## 12. Metadata Editor

### 12.1 File Discovery

The metadata editor discovers editable metadata files from the user application-support metadata directory (`Application Support/pdisasm`). It recognizes CSV files, `records_*.json`, and `types_*.pas` files. When no disassembly is open, it lists all editable metadata files in that directory. When a disassembly is open, it filters the list to metadata filenames considered relevant to that disassembly. It also adds missing relevant `types_*.pas` URLs to the file list, enabling creation/editing of relevant type files that do not yet exist.

### 12.2 Relevant Metadata Filenames

For a loaded binary, relevant filenames are generated from the binary file name without extension and the detected segment-dictionary version. The list includes labels, procedures, records, Pascal type definitions, and comments files for both file-specific and version-specific scopes where applicable.

### 12.3 CSV Editing

When a CSV metadata file is selected, the editor loads the first non-empty line as the header and each following non-empty line as a row. Rows are displayed in a grid with editable cells. Editing any cell updates the in-memory row immediately and marks the file dirty. The editor supports adding rows, deleting the selected row, context-menu row deletion, and saving.

For type-related CSVs, the editor ensures `typeSource` and `returnTypeSource` columns exist when corresponding `type` or `returnType` columns exist, and fills missing source values for non-empty type values.

### 12.4 Records JSON Editing

When a records JSON file is selected, the editor decodes an array of records. Each record has a name, optional system-record flag, and members keyed by offset. The UI supports:

- Filtering records by search text.
- Editing record names.
- Toggling the system-record flag.
- Adding and deleting records.
- Adding, deleting, and editing members.
- Editing member offset, name, type, and type source.

Member offsets must be valid integers when saving or updating the model; invalid offsets produce a localized error message.

### 12.5 Pascal Type Definition Editing

When a `types_*.pas` file is selected, the editor loads raw text into a monospace text editor. Text changes mark the file dirty. Saving writes the full text content.

### 12.6 Metadata Editor Search and Status

The metadata editor has its own search field. For CSV files, search filters rows by any cell value using case-insensitive containment. For records JSON, search filters by record name or any member field. The status bar reports selected file name, row/column counts, record/member counts, text character count, and whether the file is edited or saved.

## 13. User Data and Persistence

The GUI persists:

- Last opened file bookmark in user defaults under `lastOpenedFileBookmark`.
- Search status width preset in user defaults under `searchStatusWidthPreset`.
- Metadata edits through `MetadataEditingService` into the file-backed metadata repository, which defaults to the user metadata workspace.

Repository metadata under `metadata/` is not edited by the GUI metadata editor; the editor discovers user application-support files.

## 14. Notable Current Implementation Characteristics

The following behaviors are noteworthy for intention/implementation comparison:

- File importer accepts any data file, not specifically `.bin` UTIs.
- Verbose Output is passed into disassembly runs, but toggling it does not currently trigger rerun or refilter by itself.
- Stack State is the only display toggle that explicitly reruns disassembly.
- The metadata editor lists only user application-support metadata files, filtered to relevant filenames when a disassembly is open.
- Inline location editing can be triggered either by an explicit location reference or by finding a whole-token match for known editable location display names in the clicked line text.
- Indexed search is bypassed for wildcard queries and falls back to whole-word regex scanning.
- Comment invalidations may patch the current document without a full rerun when possible.
