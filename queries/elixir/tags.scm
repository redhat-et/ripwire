; Elixir definitions are ordinary calls in the grammar. The tags pass evaluates the
; string predicates below (#eq?/#any-of?/#not-any-of?, #355; never #match?), so the
; definition keywords are data HERE: the #any-of? list on @_keyword is the only copy,
; and ingest_elixir.h's tree walks read it back from the compiled query. The remaining
; head checks (quoted syntax, test titles, typed attributes) are in ingest_elixir.h, with the
; shared inert-region walk in ingest_inert.h. Capturing every call as @inert/@live
; would still need C++ head checks and enlarge this hot capture stream.
; Anchors restrict definition names to the FIRST argument (never a call's body).
(call target: (identifier)
  (arguments . [(alias) (dot) (atom)] @name)) @definition.module
; A keyword-headed definition: `def f(x)`, `defp g(a) when a > 0`, `def a + b`. @_keyword is
; predicate-only (the tags pass ignores its role); the two patterns carry the SAME lists, and
; test/tagspredicatecheck.sh arm A keeps them equal. `def unquote(name)(x)` and a bare `when`
; head name nothing static, so #not-any-of? drops them.
((call target: (identifier) @_keyword
  (arguments . [
    (identifier) @name
    (call target: (identifier) @name)
    (binary_operator left: [
      (call target: (identifier) @name)
      (identifier) @name
    ] operator: "when")
  ])) @definition.function
  (#any-of? @_keyword "def" "defp" "defmacro" "defmacrop" "defguard" "defguardp" "defdelegate")
  (#not-any-of? @name "unquote" "when"))
((call target: (identifier) @_keyword
  (arguments . [
    (binary_operator operator: _ @name)
    (unary_operator operator: _ @name)
    (binary_operator left: [
      (binary_operator operator: _ @name)
      (unary_operator operator: _ @name)
    ] operator: "when")
  ])) @definition.function
  (#any-of? @_keyword "def" "defp" "defmacro" "defmacrop" "defguard" "defguardp" "defdelegate")
  (#not-any-of? @name "unquote" "when"))

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
; A metadata attribute (@doc, @spec, ...) defines nothing: the #not-any-of? list on @_attribute
; is the only copy of those names, and ingest_elixir.h reads it back so a reference INSIDE one
; is not a call site (#355). The typed attributes (@type, @callback, ...) stay a C++ kind decision.
((unary_operator operator: "@" operand:
  (call target: (identifier) @name @_attribute)) @definition.attribute
  (#not-any-of? @_attribute "doc" "moduledoc" "typedoc" "spec" "impl" "behaviour" "behavior" "derive" "enforce_keys"
    "dialyzer" "on_load" "before_compile" "after_compile" "after_verify" "optional_callbacks" "compile" "external_resource"
    "vsn" "file"))
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
