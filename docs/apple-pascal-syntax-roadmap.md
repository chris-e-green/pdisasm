# Apple UCSD Pascal Syntax Reconstruction Task List

This document tracks work needed to improve `pdisasm` from a Pascal-like
pseudocode generator into a more complete Apple II UCSD Pascal source
reconstruction tool. It is based on a review of the current pseudocode, type,
call, and control-flow generation paths.

The current implementation already reconstructs many useful Pascal-like
fragments: assignments, calls, scalar literals, arithmetic and Boolean
expressions, arrays, records, strings, set operations, and several structured
control-flow patterns. The main gap is that generation is largely
instruction/stack-expression oriented rather than AST/source oriented, so output
is useful pseudocode but not yet a complete Apple Pascal compilation unit.

## Goals

- Preserve the existing human-readable pseudocode and disassembly behavior.
- Add a path toward source-valid Apple Pascal reconstruction where feasible.
- Clearly distinguish source-valid Pascal from decompiler pseudo-intrinsics and
  raw p-code artifacts.
- Keep all uncertain decompilation decisions explicit, metadata-assisted, and
  testable.
- Support Apple Pascal dialect/version differences without hard-coding one
  release's behavior into every renderer.

## Non-goals

- Perfect recovery of original source formatting, comments, or identifier names
  without metadata.
- Guaranteed recompilation of every arbitrary p-code binary in the first pass.
- Removing low-level pseudocode artifacts from diagnostic output modes.
- Replacing disassembly output with source output; both should coexist.

## Phase 1: Establish Source Reconstruction Architecture

### 1.1 Add a Pascal expression AST

Create a structured expression model so code generation no longer needs to pass
most expressions around as interpolated strings.

Suggested expression cases:

- Identifier/reference expression.
- Integer literal.
- Real literal.
- Character literal.
- String literal.
- Boolean literal.
- Nil pointer literal.
- Unary operation.
- Binary operation.
- Function call.
- Array indexing.
- Record field access.
- Pointer dereference.
- Address/reference expression for `VAR` parameters.
- Set literal.
- Range literal.
- Raw/pseudo expression fallback.

Tasks:

- [x] Add a `PascalExpr` type.
- [x] Add a `PascalBinaryOperator` type with precedence and associativity.
- [x] Add a `PascalUnaryOperator` type with precedence.
- [x] Add a renderer that inserts parentheses only where required.
- [x] Add unit tests for arithmetic precedence.
- [x] Add unit tests for Boolean precedence.
- [x] Add unit tests for comparison expressions.
- [x] Add unit tests for nested calls and indexing.
- [x] Add a raw-expression escape hatch for existing pseudocode strings.
- [x] Keep current text rendering available during migration.

### 1.2 Add a Pascal statement AST

Create statement nodes for source-like output. Instruction-level pseudocode
strings should be converted gradually into statement nodes.

Suggested statement cases:

- Assignment.
- Procedure call.
- Compound statement / statement list.
- `IF ... THEN`.
- `IF ... THEN ... ELSE`.
- `WHILE ... DO`.
- `REPEAT ... UNTIL`.
- `FOR ... TO ... DO`.
- `FOR ... DOWNTO ... DO`.
- `CASE ... OF`.
- `GOTO`.
- Label declaration/labelled statement.
- Return/exit pseudo-statement where appropriate.
- Inline assembler marker/fallback.
- Raw/pseudo statement fallback.

Tasks:

- [x] Add a `PascalStmt` type.
- [x] Add a `PascalBlock` or `PascalStmtList` type.
- [x] Add a source renderer that owns indentation and semicolon placement.
- [x] Add tests for semicolon placement between simple statements.
- [x] Add tests for no semicolon before `ELSE`.
- [x] Add tests for nested `BEGIN`/`END` rendering.
- [x] Add raw/pseudo statement fallback support.
- [x] Introduce a conversion path from existing `PseudoCodeStatement` to
      `PascalStmt` for assignments and raw text.

### 1.3 Separate pseudocode and source rendering modes

The current renderer should remain stable. Add a distinct mode for source-like
Apple Pascal output.

Tasks:

- [x] Define output modes: current pseudocode, source-like Pascal, and raw
      diagnostic pseudocode. _(Current pseudocode remains the default, and source-like Pascal can be requested separately; raw diagnostic pseudocode remains the existing fallback path.)_
- [x] Add CLI option naming for source-like output, for example
      `--show-pascal-source` or `--show-source`.
- [x] Ensure current `--show-pseudocode` behavior remains unchanged.
- [x] Add tests proving existing pseudocode snapshots do not change when source
      mode is disabled. _(Existing output tests continue to cover the default path; new source-mode coverage is additive.)_
- [x] Add first source-mode snapshot tests for simple procedures.
- [x] Document each output mode in the README.

## Phase 2: Literal and Token Correctness

### 2.1 Centralize Pascal literal escaping

Character and string literal rendering should be handled in one place rather
than through ad hoc interpolation.

Tasks:

- [x] Add `renderPascalCharLiteral`.
- [x] Add `renderPascalStringLiteral`.
- [x] Escape embedded single quotes correctly.
- [x] Decide dialect-specific rendering for non-printable characters. _(Conservative starting policy: render as `CHR(n)`.)_
- [x] Decide dialect-specific rendering for high-bit Apple II characters. _(Conservative starting policy: render as `CHR(n)`.)_
- [x] Add tests for printable ASCII characters.
- [x] Add tests for single quote characters.
- [x] Add tests for control characters.
- [x] Add tests for empty strings.
- [x] Add tests for strings containing quotes.
- [x] Replace direct `String(format: "%c", ...)` literal generation with the
      central helpers.

### 2.2 Normalize Pascal range syntax

Pascal ranges should render as `..`, not `...`, unless a raw diagnostic mode is
intentionally showing a non-Pascal artifact.

Tasks:

- [x] Replace source-mode case label ranges with `..`.
- [x] Audit set literal range rendering for consistent `..` syntax.
- [x] Add tests for case labels with singleton values.
- [x] Add tests for case labels with contiguous ranges.
- [x] Add tests for mixed singleton and range labels.
- [x] Preserve old representation in raw diagnostic mode if needed.

### 2.3 Define keyword and identifier escaping rules

Recovered or metadata-supplied names may conflict with Pascal keywords or contain
characters that are not source-valid.

Tasks:

- [x] Add an Apple Pascal keyword list.
- [x] Add identifier validation.
- [x] Add identifier sanitization for generated names.
- [x] Add a policy for metadata names that are not source-valid. _(Conservative source-mode policy: replace invalid characters with `_`, prefix names that start with non-letters, and suffix keywords with `_`.)_
- [x] Add tests for keyword collisions.
- [x] Add tests for names with spaces or punctuation.
- [x] Add tests for generated labels and temporaries.

## Phase 3: Type Model and Declaration Generation

### 3.1 Introduce a structured Pascal type model

Current type handling often relies on string prefixes such as `ARRAY` and `^`.
Replace this gradually with a structured type representation.

Suggested type cases:

- Built-in scalar type.
- Named type reference.
- Enumerated scalar type.
- Subrange type.
- Pointer type.
- Array type.
- Packed array type.
- Record type.
- Variant record type.
- Set type.
- File type.
- String type.
- Packed field/bit-field pseudo type.
- Unknown type.
- Raw type fallback.

Tasks:

- [x] Add `PascalType`.
- [x] Add `PascalArrayType` with packed flag, index types, and element type.
- [x] Add `PascalSetType`.
- [x] Add `PascalPointerType`.
- [x] Add `PascalFileType`.
- [x] Add `PascalRecordType` and `PascalVariantRecordType`.
- [x] Add parser conversion from existing type strings to `PascalType`.
- [x] Add renderer conversion from `PascalType` to source text.
- [x] Keep raw string fallback for unknown metadata.
- [x] Add tests for every supported type category.

### 3.2 Improve array and packed array handling

Array access should use declared index types, lower bounds, dimensions, and
packing information where available.

Tasks:

- [x] Preserve array index lower and upper bounds in the type model.
- [x] Support multi-dimensional arrays.
- [x] Support `PACKED ARRAY [...] OF CHAR` as a string-like structure when
      appropriate.
- [x] Distinguish byte indexing from Pascal array indexing.
- [x] Update `ixa`, `inc`, `ind`, and related paths to use structured array
      metadata.
- [x] Add tests for one-dimensional arrays.
- [x] Add tests for non-zero lower bounds.
- [x] Add tests for multi-dimensional arrays.
- [x] Add tests for packed character arrays.
- [x] Add fallback comments when an index calculation cannot be confidently
      mapped back to source syntax.

### 3.3 Improve set handling

Set word fragments should not leak into source-like output unless explicitly in
raw mode.

Tasks:

- [x] Add an internal `PascalSetValue` representation.
- [x] Track set literals independently from set word fragments.
- [x] Render singleton sets as `[x]`.
- [x] Render range sets as `[a..b]`.
- [x] Render combined sets as `[a, b, c]` where possible.
- [x] Render set union, intersection, and difference as source-valid expressions
      when operands are known.
- [x] Emit raw comments for irreducible set word operations.
- [x] Add tests for integer sets.
- [x] Add tests for character sets.
- [x] Add tests for enumerated sets.
- [x] Add tests for multi-word sets.

### 3.4 Emit declaration sections

Source-like output should include declaration sections when enough information is
available.

Tasks:

- [x] Generate `LABEL` declarations for remaining `GOTO` labels.
- [x] Generate `CONST` declarations from parsed/inferred constants.
- [x] Generate `TYPE` declarations from metadata and inferred types.
- [x] Generate `VAR` declarations for globals, locals, parameters, and temporaries
      as appropriate.
- [x] Avoid duplicate declarations for type aliases and named records.
- [x] Preserve deterministic declaration ordering.
- [x] Add tests for procedures with local variables.
- [x] Add tests for data-segment globals.
- [x] Add tests for labels produced by irreducible control flow.
- [x] Add tests for enum and subrange declarations.

### 3.5 Extend metadata parsing for Apple Pascal declarations

The existing metadata type parser supports useful subsets. Extend it toward a
more complete Apple Pascal declaration subset.

Tasks:

- [x] Parse `FILE OF` types.
- [x] Parse `TEXT` file aliases where appropriate.
- [x] Parse `SET OF` types.
- [x] Parse pointer types with named and forward-referenced pointees.
- [x] Parse mutually recursive pointer/record declarations.
- [x] Parse packed records where supported.
- [x] Parse packed arrays with arbitrary index types.
- [x] Parse named constants beyond simple integers where useful.
- [x] Parse procedure/function type aliases if encountered in metadata.
- [x] Add parser diagnostics for unsupported declaration forms.
- [x] Add fixture metadata files covering each declaration form.

## Phase 4: Procedure, Function, and Unit Structure

### 4.1 Emit procedure and function headers

Use known and inferred `ProcedureIdentifier` information to render source-like
headers.

Tasks:

- [x] Render `PROCEDURE Name(...);` headers.
- [x] Render `FUNCTION Name(...): ReturnType;` headers.
- [x] Render empty parameter lists correctly.
- [x] Render grouped parameters with the same type where useful.
- [x] Render return types from metadata/inference.
- [x] Add tests for procedure headers.
- [x] Add tests for function headers.
- [x] Add tests for missing/unknown parameter types.
- [x] Add fallback comments for uncertain signatures.

### 4.2 Infer and render parameter modes

Apple Pascal source distinguishes value parameters from `VAR` parameters. P-code
may not always make this obvious, so this should be metadata-assisted and
confidence-scored.

Tasks:

- [x] Add parameter mode to the procedure signature model.
- [x] Support explicit metadata for `VAR` parameters.
- [x] Infer likely `VAR` parameters from address-passing patterns.
- [x] Infer value parameters from scalar value-passing patterns.
- [x] Mark uncertain parameter modes.
- [x] Render uncertain modes conservatively or with comments.
- [x] Add tests for known value parameters.
- [x] Add tests for known `VAR` parameters.
- [x] Add tests for ambiguous pointer/address parameters.

### 4.3 Model function result storage

The call generator already handles reserved function result space. Source mode
should render function results in source-valid form.

Tasks:

- [x] Model hidden result storage separately from explicit parameters.
- [x] Avoid rendering hidden result slots as normal arguments.
- [x] Detect assignments to the function name inside function bodies.
- [x] Render function return assignments as `FunctionName := value` when
      appropriate.
- [x] Add tests for scalar function returns.
- [x] Add tests for real function returns.
- [x] Add tests for record/string aggregate returns if supported by the target
      dialect.

### 4.4 Reconstruct module/unit scaffolding

When enough segment and metadata information exists, render a complete source
container rather than only procedure bodies.

Tasks:

- [x] Add a `PascalSourceUnit` model.
- [x] Render a fallback `PROGRAM` wrapper for standalone binaries.
- [x] Render `UNIT` wrappers when metadata identifies a unit.
- [x] Render `INTERFACE` and `IMPLEMENTATION` sections when known.
- [x] Render `USES` clauses from metadata.
- [x] Render segment procedure/function annotations when supported.
- [x] Add tests for minimal program output.
- [x] Add tests for minimal unit output.
- [x] Add tests for procedures grouped by segment.
- [x] Document limitations when original unit boundaries are unrecoverable.

Source container metadata can restore known unit names, dependencies, and section
segment lists. When it is absent, segment kinds can identify likely units but
cannot recover the original interface declarations or exact implementation
boundaries; reconstructed source emits an explicit limitation comment and places
available procedure bodies in `IMPLEMENTATION`.

## Phase 5: Control-Flow Reconstruction

### 5.1 Build an explicit control-flow graph

Move beyond local jump heuristics by building a CFG for each procedure.

Tasks:

- [x] Split procedures into basic blocks.
- [x] Record edges for conditional branches, unconditional branches, fallthrough,
      case jump tables, calls, and returns.
- [x] Mark entry blocks, exit blocks, and external entry points.
- [x] Add dominator analysis.
- [x] Add post-dominator analysis.
- [x] Add tests for simple straight-line blocks.
- [x] Add tests for conditional branches.
- [x] Add tests for loops.
- [x] Add tests for multiple entry points.
- [x] Add tests for irreducible control flow.

### 5.2 Recover structured regions

Use CFG analysis to identify source-level structured statements.

Tasks:

- [x] Identify `IF` regions.
- [x] Identify `IF/ELSE` regions.
- [ ] Identify pre-test `WHILE` loops.
- [ ] Identify post-test `REPEAT/UNTIL` loops.
- [ ] Identify counted `FOR` loops.
- [ ] Identify `CASE` jump-table regions.
- [ ] Detect loop exits and continue-like jumps.
- [ ] Preserve `GOTO` for irreducible leftovers.
- [x] Add nested control-flow tests.
- [ ] Add tests for loops containing conditionals.
- [ ] Add tests for conditionals containing loops.

### 5.3 Improve `FOR` loop recognition

The current control-flow analyzer recognizes some loop patterns. Make this more
robust and explicit.

Tasks:

- [ ] Document Apple Pascal compiler p-code patterns for `FOR ... TO`.
- [ ] Document Apple Pascal compiler p-code patterns for `FOR ... DOWNTO`.
- [ ] Track loop variable initialization separately from loop update.
- [ ] Track loop limit evaluation.
- [ ] Avoid suppressing setup/update assignments unless the loop pattern is
      confidently recognized.
- [ ] Add tests for `FOR ... TO`.
- [ ] Add tests for `FOR ... DOWNTO`.
- [ ] Add tests for non-unit step fallbacks if encountered.
- [ ] Add tests for nested `FOR` loops.

### 5.4 Improve `CASE` reconstruction

Current `CASE` rendering is useful but not fully source-like.

Tasks:

- [ ] Add a `PascalCaseStatement` model.
- [ ] Add `PascalCaseArm` with labels and statement list.
- [ ] Support singleton labels.
- [ ] Support range labels using `..`.
- [ ] Support multiple labels per arm.
- [ ] Identify default/otherwise targets.
- [ ] Decide dialect/version spelling for default arms.
- [ ] Render case-arm semicolons correctly.
- [ ] Add tests for jump tables with shared destinations.
- [ ] Add tests for default arms.
- [ ] Add tests for sparse and dense case tables.

### 5.5 Generate label declarations for remaining gotos

Fallback `GOTO LAB...` output should be source-valid when source mode is enabled.

Tasks:

- [ ] Track all emitted labels per procedure.
- [ ] Emit a `LABEL` declaration section.
- [ ] Render labelled statements as `LABnnn:`.
- [ ] Ensure label names are valid Apple Pascal labels or valid generated
      identifiers according to the selected dialect.
- [ ] Add tests for forward gotos.
- [ ] Add tests for backward gotos.
- [ ] Add tests for multiple gotos to one label.

## Phase 6: Apple Pascal Dialect and Runtime Knowledge

### 6.1 Add dialect/version configuration

Apple Pascal and UCSD p-System details vary by version. Make those differences
explicit.

Tasks:

- [ ] Add an `ApplePascalDialect` or `PSystemDialect` enum.
- [ ] Add dialect selection to configuration.
- [ ] Add CLI option for dialect selection.
- [ ] Default to current behavior when no dialect is selected.
- [ ] Add dialect-specific keyword lists.
- [ ] Add dialect-specific standard procedure tables.
- [ ] Add dialect-specific file/unit conventions.
- [ ] Add tests proving dialect selection changes only intended output.

### 6.2 Expand standard procedure and library modeling

The existing CSP table is useful but incomplete for full Apple Pascal source
reconstruction.

Tasks:

- [ ] Verify CSP entries against Apple Pascal version-specific documentation.
- [ ] Add missing standard procedures/functions where appropriate.
- [ ] Model library functions such as `SIN`, `COS`, `LOG`, `ATAN`, `LN`, `EXP`,
      and `SQRT` when they appear through library calls rather than CSPs.
- [ ] Add metadata for common Apple system units.
- [ ] Add tests for each standard procedure signature.
- [ ] Add tests for no-argument standard functions.
- [ ] Add tests for real-valued standard functions.
- [ ] Add fallback rendering for unknown standard procedure numbers.

### 6.3 Model Apple Pascal system units and common libraries

Source reconstruction can improve if known Apple unit APIs are modeled.

Tasks:

- [ ] Create metadata format for known units and exported declarations.
- [ ] Add entries for common Apple Pascal system facilities.
- [ ] Infer `USES` clauses when calls reference known unit APIs.
- [ ] Render qualified or unqualified names according to source-mode policy.
- [ ] Add tests using known system-library fixtures.
- [ ] Document which units are modeled and which remain unknown.

## Phase 7: Pointers, L-values, and Address Semantics

### 7.1 Add an explicit l-value model

Assignments, `VAR` parameters, dereferences, fields, and array elements need a
source-valid l-value model.

Suggested l-value cases:

- Variable.
- Dereferenced pointer.
- Record field.
- Array element.
- Packed field.
- Byte/word pseudo-location.
- Raw fallback.

Tasks:

- [ ] Add `PascalLValue`.
- [ ] Convert assignment targets to l-values where possible.
- [ ] Render pointer dereferences using selected dialect syntax.
- [ ] Render field access after pointer dereference correctly.
- [ ] Render array-element assignment correctly.
- [ ] Render packed-field assignment as source-valid syntax where possible.
- [ ] Add tests for scalar variable assignment.
- [ ] Add tests for pointer dereference assignment.
- [ ] Add tests for record field assignment.
- [ ] Add tests for array element assignment.

### 7.2 Distinguish address expressions from value expressions

The stack simulator currently tracks pointer/address-like values. Source mode
should preserve the distinction explicitly.

Tasks:

- [ ] Add expression/l-value metadata for address vs value.
- [ ] Model address-taking for `VAR` parameter calls.
- [ ] Avoid rendering address arithmetic as array indexing unless proven.
- [ ] Add comments for ambiguous address calculations.
- [ ] Add tests for address loads.
- [ ] Add tests for `VAR` parameter calls.
- [ ] Add tests for pointer arithmetic fallbacks.

## Phase 8: Pseudo-Intrinsic Classification and Fallbacks

### 8.1 Classify generated output fragments

Every generated fragment should know whether it is source-valid Pascal,
dialect-specific Pascal, pseudocode, or raw p-code artifact.

Tasks:

- [ ] Add a classification enum for generated expressions/statements.
- [ ] Mark `REAL_BYTE`, `REAL_BITS`, word fragments, and similar constructs as
      pseudo-intrinsics.
- [ ] Mark raw p-code leftovers separately from intentional pseudocode helpers.
- [ ] Allow source mode to emit comments instead of invalid source expressions.
- [ ] Allow diagnostic mode to keep the current detailed artifacts.
- [ ] Add tests for classification.
- [ ] Add tests for source-mode fallback comments.

### 8.2 Replace avoidable pseudo-intrinsics with source constructs

Some pseudo-intrinsics can be eliminated when type information is good enough.

Tasks:

- [ ] Replace `REAL_BYTE`/`REAL_BITS` output with source-level operations when
      source-valid equivalents are known.
- [ ] Replace packed-field pseudo syntax with record/packed-record field names
      when metadata maps bit offsets to fields.
- [ ] Replace word-fragment array accesses with typed array/record access where
      possible.
- [ ] Add tests showing metadata improves source output.
- [ ] Add tests showing missing metadata falls back safely.

## Phase 9: Validation, Testing, and Tooling

### 9.1 Add source-output snapshot tests

Create stable fixtures for source-like output, separate from existing pseudocode
snapshots.

Tasks:

- [ ] Add simple assignment fixture.
- [ ] Add arithmetic expression fixture.
- [ ] Add procedure call fixture.
- [ ] Add function call fixture.
- [ ] Add `IF` fixture.
- [ ] Add `IF/ELSE` fixture.
- [ ] Add `WHILE` fixture.
- [ ] Add `REPEAT/UNTIL` fixture.
- [ ] Add `FOR` fixture.
- [ ] Add `CASE` fixture.
- [ ] Add record/array fixture.
- [ ] Add set fixture.
- [ ] Add labels/goto fixture.

### 9.2 Add syntax validation where possible

If an Apple Pascal compiler, p-System tool, or grammar checker is available,
source mode should be validated automatically.

Tasks:

- [ ] Investigate available Apple Pascal syntax validation tools.
- [ ] Add optional test target for syntax validation.
- [ ] Make validation opt-in if the tool is not always available in CI.
- [ ] Add CI documentation for enabling validation.
- [ ] Record known false positives/unsupported syntax cases.

### 9.3 Add confidence annotations

Recovered source should expose uncertainty rather than silently emitting
misleading constructs.

Tasks:

- [ ] Add confidence levels for type inference.
- [ ] Add confidence levels for control-flow structuring.
- [ ] Add confidence levels for parameter mode inference.
- [ ] Render low-confidence decisions as comments in source mode.
- [ ] Surface confidence in JSON export if useful.
- [ ] Add tests for low-confidence fallbacks.

### 9.4 Document known limitations

Users should understand the difference between disassembly, pseudocode, and
source reconstruction.

Tasks:

- [ ] Add README section describing pseudocode vs source-like output.
- [ ] Add examples of source-valid output.
- [ ] Add examples of diagnostic pseudocode artifacts.
- [ ] Document metadata required for better output.
- [ ] Document Apple Pascal dialect assumptions.
- [ ] Document unsupported syntax and runtime features.

## Phase 10: Migration Plan

### 10.1 Keep existing behavior stable

The current pseudocode generator has tests and likely user expectations. New
source reconstruction should be additive.

Tasks:

- [ ] Avoid changing existing pseudocode output unless intentionally scoped.
- [ ] Add regression tests before refactoring string rendering.
- [ ] Migrate one opcode family at a time to AST output.
- [ ] Keep raw string fallback during migration.
- [ ] Compare old and new pseudocode outputs during transition.

### 10.2 Suggested migration order

Recommended order from safest to riskiest:

1. Literal escaping helpers.
2. Range syntax normalization in source mode.
3. Expression AST with raw fallback.
4. Assignment statement AST.
5. Procedure/function call statement AST.
6. Source renderer with semicolon management.
7. Procedure/function headers.
8. Declaration sections.
9. Structured array/record/set type model.
10. CFG-based control-flow reconstruction.
11. Dialect-specific unit and runtime modeling.

Tasks:

- [ ] Create tracking issues or milestones for each migration step.
- [ ] Add tests before each migration step.
- [ ] Ensure source mode and pseudocode mode can coexist throughout migration.

## Open Questions

- Which Apple Pascal release should be the primary target first?
- Should source mode aim for compilable Apple Pascal or readable source-like
  Pascal with comments for irreducible constructs?
- How should default `CASE` arms be rendered for each supported dialect?
- How should high-bit Apple II characters be represented in source output?
- What metadata format should represent unit imports and exported symbols?
- Should generated labels be numeric Pascal labels, symbolic labels, or dialect
  dependent?
- How aggressively should the decompiler infer `VAR` parameters without
  metadata?
- Should uncertain source constructs be emitted as code with comments, or as
  commented-out pseudocode?

## Acceptance Criteria for a First Source-Like Milestone

A practical first milestone could be considered complete when `pdisasm` can, in a
new source mode, emit a deterministic source-like Pascal procedure containing:

- A procedure or function header.
- Local variable declarations for known locals.
- A `BEGIN`/`END` body.
- Semicolon-correct assignments.
- Semicolon-correct procedure calls.
- Correctly escaped string and character literals.
- Basic arithmetic and Boolean expressions with correct parentheses.
- Simple `IF`, `WHILE`, and `REPEAT` constructs.
- Clear comments for any raw p-code artifacts that cannot yet be rendered as
  source-valid Pascal.

Existing pseudocode and disassembly output should continue to pass current tests
while this source mode is developed.
