; ripwire Java tags — written for ripwire (.java). Derived from the upstream
; tree-sitter-java v0.23.5 grammar node-types, verified against an AST dump (see the
; javarubycheck fixture). Java is a big grammar; we capture the OOP structure the call
; graph cares about and deliberately skip field/local noise.
;
; Java structure the call graph cares about:
;   - type declarations:  class / interface / enum → def nodes (the containers)
;   - method + constructor declarations → the def nodes calls resolve TO
;   - method invocations + object creations → the call references (edges)
;   - imports → IMPORT reference edges (role="import", @reference.import) to the imported name's
;     final segment — a dependency edge, not a call (T13/fix3: was @reference.call, which double-
;     counted --callers=/--impact= fan-in by one phantom "caller" per importing file)
;
; Deliberately NOT captured (noise): fields, local variables, annotations, `@name` on
; every type mention. Only defs + calls + imports become graph nodes/edges — matching
; every other language here. ONE exception (r3 q10): SCREAMING_SNAKE constant fields —
; see the settings-constant pattern below.

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

; settings constants (r3 q10 — bench/headtohead/r3-headroom-2026-08-03): `static final int
; MAX_POOL_SIZE = 32;` — the config-constant idiom. The pattern captures every field declarator
; (the grammar exposes no cheap static+final discriminant), and the SCREAMING_SNAKE gate in
; ingest.cpp (constCaptureNeedsScreamingGate) keeps the field-noise exclusion above intact:
; camelCase instance fields stay unindexed. Shape verified with --match on the constcheck fixture.
(field_declaration
  declarator: (variable_declarator
    name: (identifier) @name)) @definition.constant

; ---- references (calls + imports) ----

; foo( .. )  and  obj.foo( .. )  — both are method_invocation with a (identifier) name field
(method_invocation
  name: (identifier) @name) @reference.call

; Candidate Type::method member name (issue #74). This query CANNOT distinguish a simple type
; receiver from a variable receiver: the pinned grammar spells both as `identifier`. Ingest stamps
; the site as JavaTypeCandidate and graph.h admits it only with a type-receiver proof (indexed class
; plus lexical shadowing at the site); every failed proof stops before name fallback. The anchor
; captures only the member, and Type::new has no identifier after `::`, so it stays uncaptured.
(method_reference
  "::"
  (identifier) @name .) @reference.call

; new Foo( .. ) — object creation resolves to the constructor / class name
(object_creation_expression
  type: (type_identifier) @name) @reference.call

; H4: qualified `new` — `new Outer.Inner()` / `new a.Outer.Inner()`. scoped_type_identifier is FLAT
; at 2 segments (both type_identifier children direct) but RIGHT-recursive at 3+ (the outer node's
; own direct type_identifier child is always just the final one, the rest nest inside a child
; scoped_type_identifier `scope:`) — either way the trailing anchor `.` binds only the LAST
; type_identifier child of the OUTER node, which is always the constructed class name. Verified with
; --match at 2 and 3 segments; anchor semantics confirmed empirically, not just assumed from the
; grammar shape.
(object_creation_expression
  type: (scoped_type_identifier
    (type_identifier) @name .)) @reference.call

; import a.b.C;  — the last scoped-identifier segment is the imported name. T13/fix3: an import is a
; DEPENDENCY edge, not a call — @reference.import (not @reference.call) so ingest_sidecap.h's generic
; "reference.import" check routes it to RefRole::Import, which graph.h's isResolvableCallReference
; (Call+Macro only) excludes from the call-graph CSR: it still rides --uses as a role="import" use-site
; (same shape C++'s `using ns::name;` already gets), but --callers/--impact fan-in no longer count it.
;
; This answers the owner call train-12 left open beside this rule. #60 gave every file a synthetic
; module-scope owner, and an import sits outside every named definition, so as a @reference.call it
; minted a CALLER edge: in test/kotlinfix, --callers=square read 1 -> 2, the second "caller" being
; Greeter.kt's `import com.example.util.square`. Java behaved identically and was inert only because a
; fixture's `import java.util.List` names nothing defined in-tree. Java and Kotlin were the only two
; languages with this shape; every other module-scope owner in this tree owns real top-level executable
; code. test/kotlincheck.sh §1a pins the behaviour so it cannot go silent again.
(import_declaration
  (scoped_identifier
    name: (identifier) @name)) @reference.import

; #446 round 2 (Java): base-clause types as @reference.base captures — the
; superclass (extends) and super_interfaces (implements) clauses under a named
; class declaration. The inner type_identifier is @name so the RawRef stays
; identical to the walk's. Anonymous classes (no name:) do not match, matching
; the C++ round's nameless-struct exclusion.
(class_declaration
  name: (identifier)
  (superclass
    [ (type_identifier) @name
      (generic_type (type_identifier) @name) ])) @reference.base

(class_declaration
  name: (identifier)
  (super_interfaces
    (type_list
      [ (type_identifier) @name
        (generic_type (type_identifier) @name) ]))) @reference.base
