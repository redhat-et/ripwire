; ripwire Go tags — derived from tree-sitter-go v0.23.4 queries/tags.scm.
; Simplified: dropped the (comment)*@doc / #strip! / #set-adjacent! doc-comment machinery
; (we don't consume docs) and the bare (type_identifier)@name @reference.type (fires on every
; type mention — pure edge noise). Kept the definition set + call references.

; ---- definitions ----

(function_declaration
  name: (identifier) @name) @definition.function

(method_declaration
  name: (field_identifier) @name) @definition.method

; interface method requirements — the contract a Go interface declares (parity with Swift protocol
; func requirements and Go impl methods). tree-sitter-go models each requirement inside an
; interface_type as a `method_elem` with a `name: (field_identifier)` field (distinct from
; `method_declaration`, which has a receiver + body). Capture it as a method def so the interface's
; contract is visible, not just the interface TYPE.
(method_elem
  name: (field_identifier) @name) @definition.method

(type_spec
  name: (type_identifier) @name) @definition.type

(type_declaration (type_spec name: (type_identifier) @name type: (interface_type))) @definition.interface

(type_declaration (type_spec name: (type_identifier) @name type: (struct_type))) @definition.struct

(var_declaration (var_spec name: (identifier) @name)) @definition.var

(const_declaration (const_spec name: (identifier) @name)) @definition.constant

; ---- references (calls) ----

(call_expression
  function: [
    (identifier) @name
    (parenthesized_expression (identifier) @name)
    (selector_expression field: (field_identifier) @name)
    (parenthesized_expression (selector_expression field: (field_identifier) @name))
  ]) @reference.call

; H4 (2026-07-31): explicit generic instantiation `Generic[int](1)` was investigated for widening
; and REJECTED — not shipped. It does NOT parse as call_expression; it parses as
; `type_conversion_expression(type: generic_type(type: (type_identifier), type_arguments:
; (type_arguments (type_identifier))))`. Verified with --match on bench/h4fixtures/go/main.go: this
; is EXACTLY the same shape produced by ordinary index-then-call, `fs[i](3)`
; (bench/h4fixtures/go2/conv.go) — `fs` and `i` parse as `type_identifier` nodes just like `Generic`
; and `int` do; tree-sitter has no type-system information to tell a generic instantiation apart
; from an index expression on a slice/map of funcs. A query binding
; `(type_conversion_expression type: (generic_type type: (type_identifier) @name))` matches BOTH
; `Generic[int](1)` -> "Generic" AND `fs[i](3)` -> "fs" identically (confirmed empirically, not
; inferred) — it would mint a call-ref pointing at a local variable/index target that happens to
; share a name with a defined function, which is a wrong-edge class this tool does not otherwise
; ship. The qualified/selector form (`pkg.Generic[int](x)`) makes this WORSE, not better: it needs a
; THIRD shape (`generic_type type: (qualified_type name: (type_identifier))`) layered on top of the
; already-indiscriminable base case. Idiomatic Go (type-inferred `Generic(1)`) was never affected —
; it parses as a plain call_expression and is captured by the pattern above. See
; H4_grammarSurvey_2026-07-30.md §FP item 5 and PLAN_h4QualifiedCalls_2026-07-30.md item 5's own
; escape hatch ("REJECT this widening with the evidence instead of shipping it").
