# pdisasm

![CI](https://github.com/chris-e-green/pdisasm/actions/workflows/ci.yml/badge.svg?branch=main)

pdisasm is a Swift package for inspecting Apple Pascal P-code binaries. The
repository now contains three related programs/libraries:

- `pdisasm`: the core disassembly library. It parses segment dictionaries,
  decodes Apple Pascal P-code and 6502 assembly procedures, performs control-flow
  and stack analysis, applies metadata, infers procedure/location types, builds a
  structured program snapshot, and renders human-readable disassembly and
  pseudocode.
- `pdisasm-cli`: a command-line frontend for one-off or batch disassembly runs.
  It can print formatted output, export a JSON document, export a Graphviz call
  graph, and optionally rewrite metadata.
- `pdisasm-gui` and `pdisasm-gui-lib`: a macOS SwiftUI application for opening
  binaries, navigating segments/procedures, searching output, toggling display
  layers, copying selected lines, editing metadata-backed names/types/comments,
  and opening a metadata editor window.

The package has no external Swift package dependencies. GUI targets are only
added on macOS; the core library, CLI, and tests are available to Swift Package
Manager on supported platforms.

## Requirements

- Swift 6.1 or newer.
- macOS 14 or newer for the SwiftUI GUI targets.

## Quick start

```bash
swift build
swift test
swift run pdisasm-cli path/to/file.bin --verbose
```

If no filename is supplied, the CLI defaults to the bundled
`Tests/pdisasmTests/Fixtures/SYSTEM.LIBRARY-02-00.bin` fixture.

## Command-line usage

```text
USAGE: pdisasm-cli [file ...] [--batch] [--workspace dir] [--json file] [--call-graph file] [--verbose] [--rewrite] [--show-markup] [--show-pcode] [--show-stack-state] [--show-pseudocode] [--show-source] [--show-dot]
```

Common examples:

```bash
# Print disassembly and pseudocode for one binary.
swift run pdisasm-cli path/to/file.bin

# Run several files in batch mode.
swift run pdisasm-cli file1.bin file2.bin file3.bin

# Read/write metadata from an explicit workspace directory.
swift run pdisasm-cli path/to/file.bin --workspace ./metadata

# Export a structured JSON document for one binary.
swift run pdisasm-cli path/to/file.bin --json out/disassembly.json

# Export a Graphviz DOT call graph for one binary.
swift run pdisasm-cli path/to/file.bin --call-graph out/calls.dot
```

Options:

- `--batch`: force batch mode. Supplying more than one input file also enables
  batch mode automatically.
- `--workspace dir`: use `dir` as both the writable and bundled metadata
  directory for the run.
- `--json file` / `--export-json file`: write a structured JSON export. This is
  only valid with a single input file.
- `--call-graph file` / `--export-call-graph file`: write a Graphviz DOT call
  graph. This is only valid with a single input file.
- `--verbose`: include verbose diagnostics/details in rendered output.
- `--rewrite`: write inferred labels/procedure metadata back to the selected
  metadata workspace, overwriting existing generated files.
- `--show-markup`: include markup formatting in the rendered document.
- `--show-pcode`: include decoded P-code lines.
- `--show-stack-state`: include stack-state annotations where available.
- `--show-pseudocode`: include generated pseudocode.
- `--show-source` / `--show-pascal-source`: include the experimental source-like Apple Pascal reconstruction output. This is additive and does not replace the existing pseudocode output.
- `--show-dot`: enable DOT-oriented output paths used by the disassembly layer.
- `--help` / `-h`: print CLI help.

Exit codes are derived from the run report: `0` for success, `2` for degraded
success, `130` for cancellation, and `1` for fatal errors.

## macOS GUI

On macOS, run the SwiftUI app with:

```bash
swift run pdisasm-gui
```

The GUI provides:

- file opening and reload controls;
- a segment/procedure sidebar;
- a table-based disassembly view with selectable/copyable rows;
- incremental search with next/previous match navigation;
- display toggles for markup, P-code, stack state, pseudocode, variables, and
  verbose output;
- inline sheets for editing location names/types, procedure signatures, and
  comments; and
- a separate metadata editor window.

User metadata is stored in `Application Support/pdisasm` by default. Repository
metadata under `metadata/` is used as bundled read-only metadata when user files
are not present.

## Metadata and bundled data

The `metadata/` directory contains CSV metadata for known labels and procedures
for selected Apple Pascal system files. The core metadata layer can also read
JSON comments, global labels, known records, and Pascal type definition files
when present in the active metadata workspace.

Metadata facts are merged with decoded and inferred facts using explicit
provenance and precedence rules, so user edits can override generated or bundled
information.

## Repository layout

```text
Sources/pdisasm/          Core parser, decoder, analysis, metadata, export, and rendering code
Sources/pdisasm-cli/      Command-line adapter
Sources/pdisasm-gui-lib/  SwiftUI views and GUI view models
Sources/pdisasm-gui/      macOS app entry point
Tests/pdisasmTests/       Unit, snapshot, fixture, and integration tests
metadata/                 Bundled metadata CSV files
docs/                     Architecture notes and ADRs
```

See `ARCHITECTURE.md` and `docs/adr/` for more detail about current design
boundaries and decisions.
