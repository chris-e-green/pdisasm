# ADR 0005: Invalidation policy

Metadata edit commands return explicit invalidation scopes. Comment and display-only label edits can patch documents; procedure signature/type edits rerun the procedure scope or propagate over the call graph.
