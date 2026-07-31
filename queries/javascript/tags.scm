; ripwire JavaScript tags — written for ripwire (.js/.jsx/.mjs/.cjs).
; tree-sitter-javascript is the PARENT grammar of tree-sitter-typescript, so this mirrors
; queries/typescript/tags.scm almost exactly — the differences are all "JS has no type layer":
;   - a class name is (identifier), NOT (type_identifier)   [JS has no distinct type namespace]
;   - no interface_declaration / abstract_class_declaration / type_alias / *_signature
;   - JS adds class EXPRESSIONS (class), function EXPRESSIONS with a name, object-literal method
;     pairs (pair key: value: arrow), and CommonJS require() (captured as a plain call below).
; Verified against the v0.23.1 grammar with an AST dump (see the langcheck fixture).

; ---- definitions ----

(function_declaration
  name: (identifier) @name) @definition.function

(generator_function_declaration
  name: (identifier) @name) @definition.function

; named function EXPRESSION: `const f = function foo(){..}` — the inner name is a def too
(function_expression
  name: (identifier) @name) @definition.function

(class_declaration
  name: (identifier) @name) @definition.class

; class EXPRESSION: `const C = class Foo {..}`
(class
  name: (identifier) @name) @definition.class

(method_definition
  name: (property_identifier) @name) @definition.method

; const foo = (..) => {..}  /  const foo = function(){..}  -> a named function
(lexical_declaration
  (variable_declarator
    name: (identifier) @name
    value: [ (arrow_function) (function_expression) ])) @definition.function

; var foo = () => {..}  (legacy `var` form)
(variable_declaration
  (variable_declarator
    name: (identifier) @name
    value: [ (arrow_function) (function_expression) ])) @definition.function

; object-literal method:  { run: () => {..} }  /  { run: function(){..} }
(pair
  key: (property_identifier) @name
  value: [ (arrow_function) (function_expression) ]) @definition.function

; ---- references (calls) ----
; A bare `require("x")` / `import()` is itself a call_expression with an (identifier) function,
; so it is captured by the first rule below — no separate import rule needed for the call graph.

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
; --match on fixtures/js at 2 AND 3 segments (H4_grammarSurvey_2026-07-30.md §SHAPES).
(new_expression
  constructor: (member_expression
    property: (property_identifier) @name)) @reference.call
