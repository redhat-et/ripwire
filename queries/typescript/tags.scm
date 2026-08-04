; ripwire TypeScript tags — written for ripwire.
; The upstream tree-sitter-typescript tags.scm targets .d.ts declaration files
; (function_signature / method_signature) and ships no @reference.call, so it extracts
; almost nothing from ordinary .ts/.tsx source. This set covers real source: concrete
; declarations + arrow-function-bound consts + call/new references. Used for BOTH
; typescript and tsx (the tsx grammar is a superset).

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

; const foo = (..) => {..}  /  const foo = function(){..}  -> a named function
(lexical_declaration
  (variable_declarator
    name: (identifier) @name
    value: [ (arrow_function) (function_expression) ])) @definition.function

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

(new_expression
  constructor: (identifier) @name) @reference.call

; H4: qualified `new` — `new ns.Inner()` / `new a.b.C()`. member_expression nests LEFT (property: is
; always the final segment at any depth), so this binds the constructed CLASS name regardless of
; namespace depth — same ctor-ref-to-class-def precedent as the bare form above. Verified with
; --match on fixtures/ts at 2 AND 3 segments, empirically, not just assumed from the grammar shape.
(new_expression
  constructor: (member_expression
    property: (property_identifier) @name)) @reference.call
