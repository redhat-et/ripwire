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

; ---- JS shape round (test/jsshapecheck.sh — webpack@957bf3a + node@427d2e1 lib/, 2026-08-04) ----

; class field bound to an arrow/function — the bound-method idiom, the JS spelling of the TS shape
; closed in d2854f4 (the two tags.scm are separate; the TS fix did not cover this file). Scoped to
; callable VALUES for the same reason as TS: plain data fields are 98 (webpack) / 542 (node lib)
; sites of pure noise. `static` is an optional anonymous token, so this matches static fields too.
; The property alternation carries #private fields (`#drain = () => {..}`) — same idiom, same map row.
(field_definition
  property: [ (property_identifier) (private_property_identifier) ] @name
  value: [ (arrow_function) (function_expression) ]) @definition.method

; #private method — `#push(x) {..}` is a method_definition whose name is a
; private_property_identifier, which the property_identifier pattern above never matched:
; 232 invisible methods in node lib/ alone. The name keeps its `#`.
(method_definition
  name: (private_property_identifier) @name) @definition.method

; CJS export assignment — `module.exports.NAME = fn` / `exports.NAME = fn` mints a function ON the
; export object (47 webpack/lib sites, 0 extracted before this round). Structurally these patterns
; capture EVERY `a.b = fn` / `a.b.c = fn`; the object-text scoping (exports / module.exports) lives
; in ingest.cpp (isCjsExportTarget) because tags-pass predicates never run — see the SCREAMING_SNAKE
; precedent above. `!name`-scoped to ANONYMOUS values: a named function expression already defines
; its inner name, and capturing both would double the row.
(assignment_expression
  left: (member_expression
    object: (identifier)
    property: (property_identifier) @name)
  right: [ (arrow_function) (function_expression !name) ]) @definition.cjsexport

(assignment_expression
  left: (member_expression
    object: (member_expression
      object: (identifier)
      property: (property_identifier))
    property: (property_identifier) @name)
  right: [ (arrow_function) (function_expression !name) ]) @definition.cjsexport

; prototype method — `Foo.prototype.bar = function (..) {..}`, the pre-class idiom node lib/ still
; carries 332 sites of; the 163 with ANONYMOUS values were invisible (the rest rode a named inner
; function expression, hence the same `!name` scope). The inner `object:` is unconstrained so any
; qualifier depth matches (`net.exports.Socket.prototype.x`); the `.prototype.` text test is the
; ingest.cpp gate (isPrototypeMemberTarget) — instance-slot assignments (`sock.onclose = fn`,
; `this.state.h = fn`) share the shape and must stay out.
(assignment_expression
  left: (member_expression
    object: (member_expression
      property: (property_identifier))
    property: (property_identifier) @name)
  right: [ (arrow_function) (function_expression !name) ]) @definition.protomethod

; ---- module-level settings constants (r3 q10 — bench/headtohead/r3-headroom-2026-08-03) ----
; Mirrors queries/typescript/tags.scm (same rationale, same --match-verified shapes; the JS grammar
; shares the program/lexical_declaration/export_statement nodes). The legacy `var CONFIG = {...}`
; spelling is included — pre-ES6 settings tables are exactly the config-module target — but `let`
; is not (a mutable counter, not config). SCREAMING_SNAKE-gated in ingest.cpp like TS.

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

(program
  (variable_declaration
    (variable_declarator
      name: (identifier) @name)) @definition.constant)

(export_statement
  (variable_declaration
    (variable_declarator
      name: (identifier) @name)) @definition.constant)

; ---- references (calls) ----
; A bare `require("x")` / `import()` is itself a call_expression with an (identifier) function,
; so it is captured by the first rule below — no separate import rule needed for the call graph.

(call_expression
  function: (identifier) @name) @reference.call

(call_expression
  function: (member_expression
    property: (property_identifier) @name)) @reference.call

; #private method call — `this.#push(x)` / `Transport.#register(y)`. Without this the #private
; defs above would enter the graph as unreachable islands (the property_identifier pattern one up
; never matches a private_property_identifier).
(call_expression
  function: (member_expression
    property: (private_property_identifier) @name)) @reference.call

(new_expression
  constructor: (identifier) @name) @reference.call

; H4: qualified `new` — `new ns.Inner()` / `new a.b.C()`. member_expression nests LEFT (property: is
; always the final segment at any depth), so this binds the constructed CLASS name regardless of
; namespace depth — same ctor-ref-to-class-def precedent as the bare form above. Verified with
; --match on fixtures/js at 2 AND 3 segments, empirically, not just assumed from the grammar shape.
(new_expression
  constructor: (member_expression
    property: (property_identifier) @name)) @reference.call
