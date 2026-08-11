; ripwire YAML tags — written for ripwire (.yml/.yaml). Derived from the upstream
; tree-sitter-grammars/tree-sitter-yaml v0.7.2 grammar, verified against an AST dump of the
; yamllangcheck fixtures (probe-first: every decision below names the node shape that forced it).
;
; YAML is DATA, not code: it has no functions, classes, or call sites. The value here is
; CONFIG VISIBILITY — CI workflows / k8s manifests / ansible playbooks become findable by
; --for / --grep with their enclosing mapping key as the symbol. There are NO @reference
; captures — YAML emits zero call edges, and langCompatible (graph.h) keeps a YAML key from
; ever resolving a code symbol of the same spelling (a `serde:` key never becomes an edge
; target of a `serde` function).
;
; ── WHY THIS IS A COPY OF NEITHER queries/json/tags.scm NOR queries/toml/tags.scm ────────────
; JSON's rule is "top-level + SECOND-level object keys", written as two enumerable patterns
; because JSON nests only through objects. Ported literally to YAML it captures 27.1% of real
; keys — and 25.3% of ALL keys sit directly inside a SEQUENCE element (the `steps:` /
; `containers:` / `tasks:` shape), which a root-depth rule drops 100%. YAML's rule is
; mapping-depth <= 2 with sequence levels TRANSPARENT (44.0% measured on the 90-repo breadth
; corpus, 4 449 files / 34 209 keys). TOML's header-relative rule does not apply either: YAML
; has no table headers — nesting lives in the TREE, not inside a dotted name.
;
; Sequence transparency is NOT expressible as a finite set of tags patterns: sequences nest
; arbitrarily (`- - key:`), so the ancestor chain between a pair and the document is unbounded.
; The patterns below therefore capture EVERY mapping pair, and the depth cut lives in ingest
; (dropGatedCapture's definition.yamlkey arm — the same in-C++ home as every other predicate a
; tags pattern cannot express; tags-pass #eq?/#match? predicates never run in ripwire).
;
; ── THE TABLE OF DECISIONS (each from measured frequency — PLAN 2026-08-10 / docs/EVALS.md) ──
;   mapping key           → a symbol IF its mapping-depth <= 2, sequences not counted (ingest
;                           enforces; the pair node is the def, so --expand yields the subtree).
;                           Block and flow style are ONE rule: `{a: 1}` is the same mapping node
;                           in YAML's data model, merely presented inline — a flow_pair key at
;                           mdepth <= 2 is a symbol exactly like its block twin.
;   anchor `&a`           → part of the VALUE it annotates, never a symbol (anchors in 1.73% of
;                           files). Structural here: @name matches only the key's scalar, and an
;                           (anchor) child beside it does not block the pattern.
;   alias `*a`            → dropped, never expanded (aliases in 1.55% of files; alias-AS-KEY
;                           measured 0 in 4 449 files). Structural: an alias key is not a scalar,
;                           so no pattern below can capture it; alias VALUES are never captured.
;   merge key `<<:`       → dropped (0.22%): a symbol named `<<` helps nobody. NOT structural —
;                           `<<` parses as an ordinary plain_scalar key — so the drop is by name,
;                           in the same ingest arm as the depth cut.
;   multi-doc streams     → each `document` re-enters at depth 1 (0.11% of files, max 5 docs).
;                           Free here: depth is counted per ancestor chain and documents never nest.
;   block scalar `|`/`>`  → a VALUE, never descended (20.5% of files). Structural: a
;                           (block_scalar) is one token with no pairs inside — 384 of them in the
;                           corpus contain key-like text a line-regex would happily mint symbols
;                           from, which is the strongest argument for a real parser here.
;   duplicate keys        → both minted (0.16%): the map's same-name merge discloses overloads=2.
;   non-string keys       → the LITERAL source text (1.70%): GH Actions' `on:` resolves to a bool
;                           under YAML 1.1, and the literal `on` is what a user greps for. Free
;                           here: @name is the (plain_scalar), whatever scalar child it wraps.
;   quoted keys           → keep their quotes (the TOML quoted_key posture, disclosed): the
;                           double/single_quote_scalar node has no inner content child to strip.
;   dotted plain key      → ONE symbol under its full spelling (`dotted.plain.key`) — ingest's
;                           defNameFromCapture skips finalSegment for data-config languages.
;
; ── THE GRAMMAR FACTS THE PATTERNS DEPEND ON (from the v0.7.2 AST probe) ─────────────────────
; 1. Pairs carry real FIELD NAMES: block_mapping_pair and flow_pair both expose `key:`, so the
;    key is matched by field, not positionally (unlike TOML, which has no fields).
; 2. A key is `(flow_node <scalar>)` where <scalar> is plain_scalar (wrapping string/integer/
;    boolean/…_scalar) or a quote scalar; the alternation below lists exactly those, so aliases,
;    block_node keys (`? |` explicit form) and other exotica never match — dropped, disclosed here.

; ---- block mapping pair — any depth; ingest cuts at mapping-depth <= 2, sequences transparent ----
(block_mapping_pair
  key: (flow_node [ (plain_scalar) (double_quote_scalar) (single_quote_scalar) ] @name)) @definition.yamlkey

; ---- flow mapping pair (`{a: 1}`) — same rule, same cut: flow is a presentation style, not a kind ----
(flow_pair
  key: (flow_node [ (plain_scalar) (double_quote_scalar) (single_quote_scalar) ] @name)) @definition.yamlkey
