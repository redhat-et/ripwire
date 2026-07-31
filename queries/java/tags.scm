; ripwire Java tags — written for ripwire (.java). Derived from the upstream
; tree-sitter-java v0.23.5 grammar node-types, verified against an AST dump (see the
; javarubycheck fixture). Java is a big grammar; we capture the OOP structure the call
; graph cares about and deliberately skip field/local noise.
;
; Java structure the call graph cares about:
;   - type declarations:  class / interface / enum → def nodes (the containers)
;   - method + constructor declarations → the def nodes calls resolve TO
;   - method invocations + object creations → the call references (edges)
;   - imports → reference edges to the imported name's final segment
;
; Deliberately NOT captured (noise): fields, local variables, annotations, `@name` on
; every type mention. Only defs + calls + imports become graph nodes/edges — matching
; every other language here.

; ---- definitions ----

(class_declaration
  name: (identifier) @name) @definition.class

(interface_declaration
  name: (identifier) @name) @definition.interface

(enum_declaration
  name: (identifier) @name) @definition.type

(method_declaration
  name: (identifier) @name) @definition.method

; `Foo( .. ) { .. }` — a constructor; name is the type identifier
(constructor_declaration
  name: (identifier) @name) @definition.method

; ---- references (calls + imports) ----

; foo( .. )  and  obj.foo( .. )  — both are method_invocation with a (identifier) name field
(method_invocation
  name: (identifier) @name) @reference.call

; new Foo( .. ) — object creation resolves to the constructor / class name
(object_creation_expression
  type: (type_identifier) @name) @reference.call

; H4: qualified `new` — `new Outer.Inner()` / `new a.Outer.Inner()`. scoped_type_identifier is FLAT
; at 2 segments (both type_identifier children direct) but RIGHT-recursive at 3+ (the outer node's
; own direct type_identifier child is always just the final one, the rest nest inside a child
; scoped_type_identifier `scope:`) — either way the trailing anchor `.` binds only the LAST
; type_identifier child of the OUTER node, which is always the constructed class name. Verified with
; --match at 2 and 3 segments (H4_grammarSurvey_2026-07-30.md §SHAPES; anchor semantics confirmed
; empirically, not just from the survey's candidate).
(object_creation_expression
  type: (scoped_type_identifier
    (type_identifier) @name .)) @reference.call

; import a.b.C;  — the last scoped-identifier segment is the imported name
(import_declaration
  (scoped_identifier
    name: (identifier) @name)) @reference.call
