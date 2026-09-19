; ripwire TSX tags — written for ripwire. .tsx ONLY.
;
; tree-sitter-typescript ships two grammars: plain "typescript" (queries/typescript/tags.scm — a .ts
; file cannot contain JSX, by the TypeScript language's own rule) and "tsx" (this one — a real
; superset that adds jsx_self_closing_element/jsx_opening_element/jsx_closing_element/
; jsx_namespace_name/…). Until #285 tsx really was a strict superset of typescript for every node
; queries/typescript/tags.scm named, so kLangTable's .tsx row shared that ONE query text (the same
; precedent .cu/.cuh still use: tree-sitter-cuda is a generated superset of tree-sitter-cpp, and both
; share querySub "cpp"). #285 needed patterns naming JSX-only node types, and tree-sitter's
; ts_query_new refuses the WHOLE query when even one pattern names a node type the grammar does not
; have — adding those patterns to the shared file made the plain typescript grammar fail to compile
; ANY pattern (measured: `[ripwire] tags.scm compile error for typescript at byte N (err 2) —
; skipping language`, which silently dropped every .ts symbol and reference, not just JSX ones).
;
; So this file exists to hold what typescript/tags.scm has PLUS the JSX additions, compiled only
; against the tsx grammar (kLangTable's .tsx row points at querySub "tsx", not "typescript"). Every
; non-JSX pattern below is a byte-for-byte copy of queries/typescript/tags.scm and MUST be kept in
; sync with it by hand — the same duplication precedent queries/c/tags.scm vs queries/cpp/tags.scm
; already carries for two related-but-diverging grammars, and for the identical structural reason: no
; include/import mechanism exists for tags.scm, and the two grammars now genuinely diverge (JSX nodes
; exist in one, not the other).

; ---- definitions ----

(function_declaration
  name: (identifier) @name) @definition.function

(generator_function_declaration
  name: (identifier) @name) @definition.function

(class_declaration
  name: (type_identifier) @name) @definition.class

(abstract_class_declaration
  name: (type_identifier) @name) @definition.class

(interface_declaration
  name: (type_identifier) @name) @definition.interface

(enum_declaration
  name: (identifier) @name) @definition.class

(type_alias_declaration
  name: (type_identifier) @name) @definition.type

(method_definition
  name: (property_identifier) @name) @definition.method

; `#render() {..}` — an ES #private method is a distinct node the pattern above never matched
; (same gap jsshapecheck closed for JS: the two tags.scm files are separate). 120 sites in
; openclaw @7a0a4c5f, 2026-08-04, with 326 `this.#x(...)` call sites — a class's whole internal
; call graph went missing.
(method_definition
  name: (private_property_identifier) @name) @definition.method

; `abstract foo(): T;` — the contract half of an abstract base. method_signature above only covers
; .d.ts-style signatures; an abstract member is its own node, so before this pattern an abstract
; class published its name and nothing a caller could bind to. 76 sites in openclaw — and --lego
; reads exactly this shape when it lists an interface's method contract beside its implementors.
(abstract_method_signature
  name: (property_identifier) @name) @definition.method

; `send = async (payload) => {..}` — a class field bound to a callable IS the class's callable
; surface: reachable as `obj.send(...)` exactly like a method_definition, and the whole point of the
; bound-method idiom. 287 sites in openclaw. Scoped to arrow/function VALUES on purpose: a
; public_field_definition with any value at all is >5000 sites there (a --match floor), i.e. mostly
; data members, and taking those would bury the map. Same reason the object-literal `pair` form
; stays out — see test/tsshapefix/objectliteral.ts.
(public_field_definition
  name: [ (property_identifier) (private_property_identifier) ] @name
  value: [ (arrow_function) (function_expression) ]) @definition.method

; const foo = (..) => {..}  /  const foo = function(){..}  -> a named function
(lexical_declaration
  (variable_declarator
    name: (identifier) @name
    value: [ (arrow_function) (function_expression) ])) @definition.function

; the lazy-facade export: `export const f: M["f"] = ((...args) => ..) as M["f"];`. The cast puts an
; as_expression (or satisfies_expression) where the pattern above looks for the arrow itself, so
; every one of these read as an unnamed const and — not being SCREAMING_SNAKE — was dropped by the
; convention gate. 105 sites in openclaw, and they are not marginal: that idiom is how its entire
; public `src/plugin-sdk/` surface is written, so each miss was an exported API entry point --for
; structurally could not surface.
(lexical_declaration
  (variable_declarator
    name: (identifier) @name
    value: [ (as_expression        (parenthesized_expression [ (arrow_function) (function_expression) ]))
             (satisfies_expression (parenthesized_expression [ (arrow_function) (function_expression) ])) ])) @definition.function

; ---- module-level settings constants (r3 q10 — bench/headtohead/r3-headroom-2026-08-03) ----
; `const PASSWORD_HASHERS = [...]` at module scope: a settings/config constant is a real, rankable
; symbol — before these patterns a whole settings module contributed ZERO symbols to the map, so
; --for structurally could not surface it (the r3 head-to-head's only unrecoverable loss).
; Shape verified with --match: the (program …) wrapper keeps function-local consts out; the export
; form nests (program (export_statement (lexical_declaration …))) so it needs its own pattern.
; "const"-keyword-anchored (a top-level `let` is a mutable counter, not config). Scoped to
; SCREAMING_SNAKE names in ingest.cpp (constCaptureNeedsScreamingGate — tags predicates never run),
; so `const retryBudget = 3` stays unindexed and an ALL-CAPS arrow const dedups to its Function def.

(program
  (lexical_declaration
    "const"
    (variable_declarator
      name: (identifier) @name)) @definition.constant)

(export_statement
  (lexical_declaration
    "const"
    (variable_declarator
      name: (identifier) @name)) @definition.constant)

; declaration-file signatures (kept so .d.ts still yields symbols)
(function_signature
  name: (identifier) @name) @definition.function

(method_signature
  name: (property_identifier) @name) @definition.method

; ---- references ----

(call_expression
  function: (identifier) @name) @reference.call

(call_expression
  function: (member_expression
    property: (property_identifier) @name)) @reference.call

; `this.#retry()` — the ref half of the #private method pattern above (326 openclaw sites;
; property_identifier never matches a private_property_identifier).
(call_expression
  function: (member_expression
    property: (private_property_identifier) @name)) @reference.call

(new_expression
  constructor: (identifier) @name) @reference.call

; H4: qualified `new` — `new ns.Inner()` / `new a.b.C()`. member_expression nests LEFT (property: is
; always the final segment at any depth), so this binds the constructed CLASS name regardless of
; namespace depth — same ctor-ref-to-class-def precedent as the bare form above. Verified with
; --match on fixtures/ts at 2 AND 3 segments, empirically, not just assumed from the grammar shape.
(new_expression
  constructor: (member_expression
    property: (property_identifier) @name)) @reference.call

; #285: `<Foo />` / `<Foo>…</Foo>` invokes Foo exactly like `Foo()` — bind the OPENING tag's name only
; (self-closing has no separate closing tag; a paired element's jsx_closing_element repeats the same
; name and is deliberately NOT captured, so one JSX invocation mints exactly one edge, not two).
; `<Foo.Bar />` binds through member_expression, the identical shape `Foo.Bar()` already captures two
; rules up, so it carries a receiver the resolver narrows on the same as a member call (ingest_binds.h
; receiverOf reads the parent of @name generically; it does not care whether the grandparent is a
; call_expression or a jsx_*_element). An intrinsic tag (`<div>`, `<h1>`) parses as the SAME
; (identifier) shape as a component tag — the grammar carries no case distinction — so the
; lower-case-first-letter filter lives in C++ at capture time (isJsxIntrinsicTagIdentifier,
; src/ingest_names.h): tags-pass predicates never run (`(#match? @name "^[A-Z]")` here would be
; silently ignored — see isCppCastKeyword's note above, measured, not assumed). A namespaced tag
; (`<svg:rect />`) needs no filter at all: verified with --match that its name field is a DIFFERENT
; grammar node, jsx_namespace_name, which no pattern below names, so it is never captured in the
; first place. A `<>…</>` fragment has no `name:` field and is likewise never captured.
(jsx_self_closing_element
  name: (identifier) @name) @reference.call

(jsx_self_closing_element
  name: (member_expression
    property: (property_identifier) @name)) @reference.call

(jsx_opening_element
  name: (identifier) @name) @reference.call

(jsx_opening_element
  name: (member_expression
    property: (property_identifier) @name)) @reference.call
