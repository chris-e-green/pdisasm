# Interpreter tools

These scripts inspect Apple Pascal interpreter binaries and extract boot blocks
from disk images. They are macOS-oriented and intentionally remain separate
from the supported `pdisasm-cli` interface.

## Interpreter inventory

The inventory scripts require `zsh`, `bgrep`, `xxd`, `gawk`, and the macOS
`md5` command.

Inspect every recognized interpreter under an archive directory:

```sh
./allinterpreters.sh ~/pascal > interpreters.csv
```

If the directory is omitted, `~/pascal` is used. Inspect one interpreter by
combining the header and data row:

```sh
./header.sh
./getinterpreter.sh path/to/SYSTEM.APPLE
```

When an interpreter is in a finder result's `files` directory,
`getinterpreter.sh` reads `volumeName` automatically from the adjacent
`manifest.json` and includes it in the CSV. For other layouts, supply it
explicitly with `--volume-name NAME`.

Handler-table entries that share the handler used by opcodes 211 and 212 are
written as `UNIMPL`. Zero handler addresses are written as `RSRVD`; other
handlers retain their `0x`-prefixed hexadecimal representation.

To analyze all extracted finder results, run:

```sh
./allinterpreters.sh ./pascal-results/images > interpreters.csv
```

The batch continues when an individual interpreter cannot be analyzed, writes
that diagnostic to standard error, and exits nonzero after reporting the final
failure count. Redirect standard error to retain the complete failure list.
Rows whose fields are otherwise identical are combined: the first path and
volume remain primary, while additional paths and volumes are listed in the
`Comment` field.

Diagnostics are written to standard error. CSV is written to standard output.
An interpreter is rejected if no CSP table is found or if more than one
candidate table matches. Segment names from companion `SYSTEM.PASCAL` and
`SYSTEM.LIBRARY` codefiles are emitted in dictionary-slot order, separated by
semicolons. Their segment numbers are emitted in adjacent columns in the same
order.

## Boot block extraction

Boot extraction additionally requires `cp2`:

```sh
./extractboot.sh disk.po output/bootsect.bin
```

When the output is omitted, the default is
`files/<disk-image-name>/bootsect.bin`.

## Recursive disk-image discovery

`find-pascal-images.sh` scans raw disk images and nested compressed archives,
deduplicates qualifying images by SHA-256, and extracts interpreters,
`SYSTEM.PASCAL`, optional `SYSTEM.LIBRARY`, and the first two logical boot
blocks. It writes a CSV summary, per-image JSON manifests, and an error log.

```sh
./find-pascal-images.sh --output ./pascal-results ~/pascal
```

Known disk and archive extensions are examined by default. Add `--probe-all`
to try extensionless and mislabeled files as well; this is substantially slower
for large collections. The output directory must be outside the source tree.
Run `./find-pascal-images.sh --help` for recursion and expanded-size limits.

## Tests

The regression test creates synthetic interpreter data in a temporary
directory and does not require archived system files:

```sh
./test-tools.sh
./test-find-pascal-images.sh
```
