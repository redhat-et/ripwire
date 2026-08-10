; ripwire TOML tags — written for ripwire (.toml). Derived from the upstream
; tree-sitter-grammars/tree-sitter-toml v0.7.0 grammar node-types, verified against an AST dump
; (see the tomllangcheck fixture).
;
; TOML is DATA, not code: it has no functions, classes, or call sites. The value here is
; CONFIG VISIBILITY — pyproject.toml / Cargo.toml / rustfmt.toml become findable by --for /
; --grep with their enclosing table as the symbol. There are NO @reference captures — TOML
; emits zero call edges, and langCompatible (graph.h) keeps a TOML key from ever resolving a
; Rust/Python name of the same spelling (a `serde` dependency key never becomes an edge target
; of a `serde` function).
;
; ── WHY THIS IS NOT queries/json/tags.scm WITH THE NOUNS CHANGED ──────────────────────────────
; JSON's rule is "top-level + SECOND-level object keys", a depth cut measured from the document
; ROOT. Ported literally to TOML it captures 38.3% of keys and misses every key under a 2-dotted
; table: `[tool.ruff.lint]` puts `select`/`ignore` at root-relative depth 4.
;
; In TOML the navigable unit is the TABLE HEADER, so key depth is measured RELATIVE TO THE
; HEADER — and the AST gives that for free. `document → table → pair` is the shape whatever the
; header's dotted depth, because the dots live INSIDE one `dotted_key` node rather than nesting
; the tree. A key is therefore always exactly one level below its header with no depth
; predicate written anywhere below; `[tool.ruff.lint]`'s keys sit at the same AST depth as
; `[project]`'s. That is the whole design, and it is why the patterns look flat.
;
; Measured on 90 real public repos (321 .toml files) — the counts that chose each decision:
;   plain `key =` 6 594 · `[table]` header 2 561 (258 files) · array value 1 270 ·
;   `[[array-of-tables]]` 300 (75 files) · inline table 213 · dotted key `a.b.c =` only 197.
;   `[table]` header dotted depth: 1:446 · 2:1421 (the mode) · 3:415 · 4:191 · 5:87 · 6:1.
;
; ── THE TABLE OF DECISIONS ────────────────────────────────────────────────────────────────────
;   [table] header        → a symbol named by the FULL dotted header (`tool.ruff.lint`), so
;                           `--grep=tool.ruff` lands. The def node is the whole (table), so
;                           --expand on a header yields the table's contents, and its keys nest
;                           inside it the way a class's methods nest inside the class.
;   keys under a table    → symbols, one level below their header, at ANY header depth.
;   [[array-of-tables]]   → ONE symbol per header, named by the header; elements are not
;                           separately numbered. AoT dotted depth is bimodal (1:115, 3:176) —
;                           the name carries the meaning, an index would not.
;   dotted key `a.b.c =`  → ONE symbol under its full dotted spelling. Only 197 of them against
;                           6 594 plain keys; splitting would triple noise on the rarest form.
;                           Free here: (dotted_key) is a single node, and a `(pair (bare_key))`
;                           pattern cannot match its parts because they are not DIRECT children.
;   inline table `{…}`    → NOT descended; the owning key is the symbol. Same posture as JSON's
;                           "arrays are never descended". Free here too: every `pair` pattern
;                           below is anchored under (document)/(table)/(table_array_element), and
;                           an inline table's pairs are children of (inline_table).
;   top-level plain key   → a symbol. The dominant form.
;
; ── TWO GRAMMAR FACTS THE PATTERNS DEPEND ON ──────────────────────────────────────────────────
; 1. This grammar has NO FIELD NAMES. Unlike tree-sitter-json, `pair` carries no `key:`/`value:`
;    fields, so the key is matched POSITIONALLY. That is sound rather than lucky: the key node
;    types (bare_key / dotted_key / quoted_key) and the value node types (string / integer /
;    float / boolean / array / inline_table / the four date-time types) are DISJOINT sets in
;    node-types.json, so `(pair (bare_key) @name)` cannot capture a value.
; 2. `quoted_key` has no string-content child (only an optional escape_sequence), so unlike
;    JSON — where `(string (string_content))` strips the quotes — a quoted key's symbol name
;    KEEPS its quotes: `"__init__.py"`, not `__init__.py`. Disclosed rather than silently
;    dropped: omitting quoted keys would make a `[tool.ruff.lint.per-file-ignores]` table look
;    empty, and a zero must mean "none found", never "none exists".

; ---- plain keys at the document root (before any table header) ----
(document
  (pair
    [ (bare_key) (dotted_key) (quoted_key) ] @name) @definition.section)

; ---- [table] header — named by its FULL dotted spelling ----
(table
  [ (bare_key) (dotted_key) (quoted_key) ] @name) @definition.section

; ---- keys under a [table], at ANY header depth ----
(table
  (pair
    [ (bare_key) (dotted_key) (quoted_key) ] @name) @definition.section)

; ---- [[array-of-tables]] header — one symbol per header ----
(table_array_element
  [ (bare_key) (dotted_key) (quoted_key) ] @name) @definition.section

; ---- keys under an [[array-of-tables]] ----
(table_array_element
  (pair
    [ (bare_key) (dotted_key) (quoted_key) ] @name) @definition.section)
