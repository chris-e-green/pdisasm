# pdisasm replacement architecture

This branch treats the prototype as a behavioural specification and starts the replacement around explicit boundaries:

- **Core disassembly model**: `pdisasm` owns the binary model, decoded procedures, locations, procedure identifiers, calls, diagnostics, and rendering inputs.
- **Metadata persistence**: metadata import/export is isolated behind `MetadataStore`, with a small in-tree CSV implementation for the exact metadata tables the application uses. This removes runtime dependence on a general CSV package and makes metadata handling deterministic and unit-testable.
- **Command line adapter**: `pdisasm-cli` is a thin argument adapter around `runPdisasm`; it has no external parser dependency and no disassembly logic.
- **Platform adapters**: platform-specific paths are isolated in `PlatformPaths.swift`; GUI targets are only built on macOS where AppKit/SwiftUI exist.

## Prototype weaknesses addressed

- Package resolution could fail before any app code built because all targets depended on network-fetched packages.
- The CLI depended on a parser framework for a small fixed flag surface.
- Metadata persistence coupled core startup to a third-party CSV encoder/decoder.
- Linux CI/test runs attempted to compile macOS-only GUI sources.
- Application-support lookup used a macOS-only convenience without a non-macOS fallback.

## Behavioural compatibility

Externally visible CLI flags are preserved: optional filename plus `--verbose`, `--rewrite`, `--show-markup`, `--show-pcode`, `--show-stack-state`, `--show-pseudocode`, and `--show-dot`. Metadata files are still read from the user application-support directory, with repository `metadata/` files used as read-only bundled defaults when user metadata does not exist.
