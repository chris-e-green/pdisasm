# ADR 0004: Document contract

`DisassemblyDocument` owns renderable nodes, sections, source-map entries, and document-node provenance. Renderers consume the document and must not mutate legacy analysis objects.

The target document product is a `DisassemblyDocumentSet` for each disassembly run rather than a single monolithic output stream. The set contains individually addressable representation documents:

- Pascal procedure P-code documents;
- Pascal procedure pseudocode documents;
- assembler procedure assembly documents;
- optional run-level documents for globals, diagnostics, summaries, and call-graph views.

CLI output remains a rendering policy over the document set: the plain-text renderer flattens enabled representation documents in stable procedure order so P-code and pseudocode can appear intertwined as before. GUI output should present representation documents independently, for example as separate windows, tabs, or panes.

Navigation between documents is explicit data. Cross-document links connect equivalent P-code and pseudocode regions, instruction-to-derived-statement provenance, call sites, callees, callers, declarations, references, diagnostics, and comments. GUI navigation should resolve those links through typed IDs such as `DocumentNodeID`, `ProcedureID`, `InstructionID`, and `LocationID`; rendered anchor strings are display compatibility only.
