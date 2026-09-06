; Elixir definitions are ordinary calls in the grammar. captureTagsFacts applies
; the keyword/head/quote filters in ingest_elixir.h; tags predicates are not evaluated.
; Anchors restrict definition names to the FIRST argument (never a call's body).
(call target: (identifier)
  (arguments . (alias) @name)) @definition.module
(call target: (identifier)
  (arguments . [
    (identifier) @name
    (call target: (identifier) @name)
    (binary_operator left: [
      (call target: (identifier) @name)
      (identifier) @name
    ] operator: "when")
  ])) @definition.function

(call target: [
  (identifier) @name
  (dot right: (identifier) @name)
]) @reference.call
(binary_operator operator: "|>" right: (identifier) @name) @reference.call

; Bare identifiers outside pipes are ambiguous variables/zero-arity calls and omitted.
; Quoted AST is omitted; macro expansion, dynamic dispatch, alias/import/use resolution,
; protocol dispatch and generated definitions are not inferred. Macros/guards are fn
; symbols: their Elixir bodies are parsed, unlike the C preprocessor macro kind.

; ExUnit's literal test descriptions are named test functions. Interpolated titles are
; excluded by the capture filter because they do not have a static name.
(call target: (identifier)
  (arguments . (string) @name)
  (do_block)) @definition.function
