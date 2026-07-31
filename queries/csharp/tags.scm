; ripwire C# tags — written for ripwire (.cs). Derived from the upstream
; tree-sitter/tree-sitter-c-sharp v0.23.5 grammar node-types (verified against node-types.json /
; grammar.js — the vendored queries/tags.scm ships no @reference.call and captures far less than we
; need, so this is hand-written, mirroring the Java/TypeScript convention already in this repo).
;
; C# structure the call graph cares about:
;   - type declarations: class / struct / interface / record / enum  -> def nodes (the containers)
;   - method / constructor / property declarations -> the def nodes calls resolve TO
;   - invocations + object creations -> the call references (edges)
;   - `using` directives -> captured separately by ingest.cpp::captureIncludes (NOT here — matches
;     how every other language's imports are handled: tags.scm never captures imports directly).
;
; Deliberately NOT captured (noise, matching Java/Ruby): fields, local variables, attributes.

; ---- definitions ----

(class_declaration
  name: (identifier) @name) @definition.class

(struct_declaration
  name: (identifier) @name) @definition.struct

(interface_declaration
  name: (identifier) @name) @definition.interface

; `record Foo(...)` / `record class Foo` / `record struct Foo` share ONE node type (record_declaration);
; the grammar does not expose a field distinguishing the `struct` form, so both bucket as class-like
; (records are reference-type-like containers for the call graph either way).
(record_declaration
  name: (identifier) @name) @definition.class

; enum Foo { A, B }  — typedef/alias/enum bucket (matches Java's enum_declaration -> definition.type)
(enum_declaration
  name: (identifier) @name) @definition.type

(method_declaration
  name: (identifier) @name) @definition.method

; Foo( .. ) { .. }  — a constructor; name is the type identifier (matches Java's constructor_declaration)
(constructor_declaration
  name: (identifier) @name) @definition.method

; get/set / expression-bodied properties — matches Swift's property_declaration -> definition.var
(property_declaration
  name: (identifier) @name) @definition.var

; ---- references (calls) ----

; foo( .. )  — bare call (local/static method)
(invocation_expression
  function: (identifier) @name) @reference.call

; obj.foo( .. )  /  Type.StaticMethod( .. )
(invocation_expression
  function: (member_access_expression
    name: (identifier) @name)) @reference.call

; Foo<T>( .. )  — a bare generic method call
(invocation_expression
  function: (generic_name (identifier) @name)) @reference.call

; obj.Foo<T>( .. )  — a generic method call via member access
(invocation_expression
  function: (member_access_expression
    name: (generic_name (identifier) @name))) @reference.call

; w?.Bump( .. )  /  a?.b?.C( .. )  — conditional-access ("?.") call, the modern C# null-safety idiom.
; Shape (probed with --match on test/csharpcondfix, tree-sitter-c-sharp v0.23.5): the invocation's
; `function:` child is the CONDITIONAL_ACCESS_EXPRESSION, and the invoked name sits one level down in a
; MEMBER_BINDING_EXPRESSION (`.Bump`) — a node kind none of the patterns above mention, so every `?.`-guarded
; call was dropped at extraction. `(invocation_expression function: (member_binding_expression ...))` matches
; ZERO sites (probed) — the conditional_access wrapper is mandatory. For a doubly-guarded chain (`a?.b?.C()`)
; the OUTER conditional_access is the function and its member_binding child is the final segment, so this one
; pattern covers any `?.` depth; the inner `?.b` link is a receiver, not a call, and correctly binds nothing.
(invocation_expression
  function: (conditional_access_expression
    (member_binding_expression
      name: (identifier) @name))) @reference.call

; w?.Gen<T>( .. )  — the generic variant of the above (member_binding's name is a generic_name, mirroring the
; member_access_expression/generic_name pair already present for the non-conditional form).
(invocation_expression
  function: (conditional_access_expression
    (member_binding_expression
      name: (generic_name (identifier) @name)))) @reference.call

; NOTE (verified, corrects the H4 survey's §SHAPES caveat): `a?.B.C()` — a `?.` link followed by a PLAIN `.`
; link — needs NO new pattern. Only the guarded link is a member_binding; the invoked `.C` is an ordinary
; member_access_expression, so the `obj.foo( .. )` pattern above has always captured it. The `?.`-chain forms
; that DO need the patterns above are exactly those whose FINAL link is `?.`.

; new Foo( .. )  — object creation resolves to the constructor / class name
(object_creation_expression
  type: (identifier) @name) @reference.call

(object_creation_expression
  type: (generic_name (identifier) @name)) @reference.call

(object_creation_expression
  type: (qualified_name
    name: (identifier) @name)) @reference.call
