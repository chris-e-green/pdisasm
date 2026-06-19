# ADR 0004: Document contract

`DisassemblyDocument` owns renderable nodes, sections, source-map entries, and document-node provenance. Renderers consume the document and must not mutate legacy analysis objects.
