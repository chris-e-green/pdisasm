# ADR 0003: Snapshot boundary

`ProgramSnapshot` is the immutable handoff from decoding and analysis to document, rendering, GUI, and export layers. User-visible facts carry provenance so callers can distinguish decoded, inferred, and metadata-backed values.
