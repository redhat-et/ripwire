; ripwire Kotlin tags — written for ripwire (.kt). Derived from fwcd/tree-sitter-kotlin's own
; upstream queries/tags.scm (commit 1852ea17, vendored at third_party/deps/kotlin), adapted onto
; this repo's capture vocabulary — NOT copied verbatim, unlike Python's (whose grammar happens to
; already match). class_declaration/object_declaration/companion_object/property_declaration carry
; NO named fields in this grammar (unlike Java's `name:`), so every capture here is positional —
; verified against the vendored grammar's node-types.json, not assumed from upstream's shape.
;
; Kotlin structure the call graph cares about:
;   - class / object / companion object declarations → def nodes (the containers). interface and
;     enum class share class_declaration's node type (a modifier keyword, not a separate node) —
;     both land here as @definition.class, same disclosed floor upstream's own query has.
;   - function declarations → the def nodes calls resolve TO. ONE node type
;     (function_declaration) covers top-level functions, class members AND extension functions
;     (`fun Foo.bar()`) alike — like Python's function_definition, tagged uniformly rather than
;     split into function/method, since the grammar gives no structural way to tell them apart
;     without a scope walk (that walk is ingest_sidecap.h's job, not the tags pass's).
;   - call expressions (bare and via navigation) → the call references (edges).
;   - imports → reference edges to the imported name's final segment, mirroring Java's import rule
;     exactly (including its capture kind: @reference.call, not @reference.import — matched for
;     consistency with the one other JVM-family query in this tree).
;
; Deliberately NOT captured (first cut, disclosed floor, not an oversight):
;   - property_declaration (`val`/`var`, class or top-level): Kotlin's constant-vs-mutable
;     distinction is the `const` MODIFIER keyword, not a case convention, and tags-pass predicates
;     never run — the same reason Rust's const_item/static_item skip constCaptureNeedsScreamingGate
;     entirely (the keyword IS the evidence there). Kotlin's `const val` needs that same
;     keyword-checked gate in ingest.cpp, not yet written; capturing every property unconditionally
;     here would flood the symbol table with every mutable field as a spurious "constant" the day
;     this lands, so the safer floor is to capture NONE until the gate exists. Not "measured zero" —
;     "not measured yet".
;   - enum_entry (individual enum constants): Java's own tags.scm makes the same call — only the
;     enum's container type is a def node, not each of its values.
;   - type_alias: rare enough, and genuinely ambiguous whether it should read as @definition.type
;     (Java's enum uses that tag) or @definition.class; deferred rather than guessed.

; ---- definitions ----

(class_declaration
  (type_identifier) @name) @definition.class

(object_declaration
  (type_identifier) @name) @definition.class

; Companion objects are usually anonymous (`companion object { ... }`) — the type_identifier child
; is only present for a NAMED companion (`companion object Factory { ... }`). An anonymous one simply
; produces no @name capture and is not indexed as its own symbol, which is correct: its members still
; get their own function_declaration captures below, scoped to the enclosing class by
; ingest_sidecap.h, same as an anonymous Java static initializer block never becomes a symbol either.
(companion_object
  (type_identifier) @name) @definition.class

(function_declaration
  (simple_identifier) @name) @definition.function

; ---- references (calls + imports) ----

; foo( .. ) — a bare call, no receiver.
(call_expression
  (simple_identifier) @name) @reference.call

; obj.foo( .. ) / Obj.foo( .. ) — a call through navigation (member access).
(call_expression
  (navigation_expression
    (navigation_suffix
      (simple_identifier) @name))) @reference.call

; `class Foo : Bar(args)` — explicit superclass constructor delegation. Ordinary `Foo()` instance
; construction does NOT reach here: Kotlin has no `new` keyword, so `Foo()` parses as a plain
; call_expression with a bare (simple_identifier) callee and is already covered by the bare-call rule
; above (constructor and function calls share one namespace in this grammar, unlike Java's separate
; object_creation_expression). This rule only adds the narrower delegation-clause case.
(constructor_invocation
  (user_type
    (type_identifier) @name)) @reference.call

; import a.b.C  — the last dotted segment is the imported name. Kotlin's import_header wraps a FLAT
; `identifier` node (multiple simple_identifier children, not Java's right-recursive
; scoped_identifier), so the trailing anchor `.` is what picks the LAST segment here, not a `name:`
; field — verified against node-types.json: identifier's children are `[simple_identifier]` (repeated).
(import_header
  (identifier
    (simple_identifier) @name .)) @reference.call
