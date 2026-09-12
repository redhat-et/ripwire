; Elixir definitions are ordinary calls in the grammar. captureTagsFacts applies
; the keyword/head/quote filters in ingest_elixir.h; tags predicates are not evaluated.
; Anchors restrict definition names to the FIRST argument (never a call's body).
(call target: (identifier)
  (arguments . [(alias) (dot) (atom)] @name)) @definition.module
(call target: (identifier)
  (arguments . [
    (identifier) @name
    (call target: (identifier) @name)
    (binary_operator left: [
      (call target: (identifier) @name)
      (identifier) @name
    ] operator: "when")
  ])) @definition.function
(call target: (identifier)
  (arguments . [
    (binary_operator operator: _ @name)
    (unary_operator operator: _ @name)
    (binary_operator left: [
      (binary_operator operator: _ @name)
      (unary_operator operator: _ @name)
    ] operator: "when")
  ])) @definition.function

(call target: [
  (identifier) @name
  (dot right: (identifier) @name)
]) @reference.call
(binary_operator operator: "|>" right: (identifier) @name) @reference.call

; Context and bare-name candidates share the query engine. The Elixir capture filter
; resolves lexical aliases/imports and excludes bound variables, patterns and quoted AST.
(call) @elixir.context
(identifier) @name @reference.bare

; Types and callbacks are declarations; ordinary attributes may evaluate expressions.
(unary_operator operator: "@" operand:
  (call target: (identifier) @name)) @definition.attribute
(unary_operator operator: "@" operand:
  (call target: (identifier)
    (arguments . (binary_operator left: [
      (identifier) @name
      (call target: (identifier) @name)
    ] operator: "::")))) @definition.type
(unary_operator operator: "@" operand:
  (call target: (identifier)
    (arguments . (binary_operator left:
      (binary_operator left: [
        (identifier) @name
        (call target: (identifier) @name)
      ] operator: "::") operator: "when")))) @definition.type
(unary_operator operator: "@" operand: (identifier) @name) @reference.attribute
(binary_operator operator: _ @name) @reference.operator
(unary_operator operator: _ @name) @reference.operator

; ExUnit's literal test descriptions are named test functions. Interpolated titles are
; excluded by the capture filter because they do not have a static name.
(call target: (identifier)
  (arguments . (string) @name)
  (do_block)) @definition.function
