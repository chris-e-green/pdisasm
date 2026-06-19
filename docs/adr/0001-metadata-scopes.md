# ADR 0001: Metadata scopes

Metadata is loaded through `MetadataScopeResolver` from version, file, and explicit scopes. File-scoped facts take precedence over version-scoped bundled facts, and explicit snapshots bypass repository resolution for deterministic tests and automation.
