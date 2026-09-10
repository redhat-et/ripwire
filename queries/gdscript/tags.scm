; ripwire GDScript tags — authored here, not vendored: PrestonKnopp/tree-sitter-gdscript ships no
; queries/tags.scm. Every pattern below was read off a real parse (ts_node_string) of a fixture
; exercising the construct, not from node-types.json, because two of the shapes are not what the
; node-type list suggests (see the @export/@onready note under VARIABLES).

; ---- classes ----

; `class_name Hero` — the file-level global class. In Godot this is THE symbol of a .gd file: it is
; what other files name in a type annotation and what the editor's class list shows. A file may
; carry at most one.
(class_name_statement
  name: (name) @name) @definition.class

; `class Inner:` — a named inner class.
(class_definition
  name: (name) @name) @definition.class

; ---- functions ----

; A GDScript file IS a class body, so a top-level `func` is semantically a method. It is captured as
; a FUNCTION anyway, to match how every other language in this repo treats a file-scope definition
; and so that a .gd free function ranks in the same tier as a Python module-level def. A `func`
; inside an explicit `class Inner:` block gets t="method", which is the distinction that carries
; information here.
(source
  (function_definition
    name: (name) @name) @definition.function)

(class_body
  (function_definition
    name: (name) @name) @definition.method)

; ---- constants and enums ----

; `const MAX := 5`. NOT gated on SCREAMING_SNAKE (constCaptureNeedsScreamingGate returns false for
; GDScript, deliberately): like Rust's const_item, the `const` keyword is the evidence, not the case.
(const_statement
  name: (name) @name) @definition.constant

; `enum State { IDLE, RUN }` — the enum's own name.
(enum_definition
  name: (name) @name) @definition.type

; Enum MEMBERS ride @definition.constant rather than @definition.enummember: the latter is gated by
; isPyEnumMemberTarget (ingest_names.h), which tests a Python class's base-name for an enum family
; and drops everything else — a GDScript enumerator would be silently discarded by it. A GDScript
; enumerator is a constant by construction (the `enum` keyword is the evidence), so the ungated
; constant capture is both correct and honest here.
; Each enumerator carries its OWN @definition.constant role node. Capturing the enclosing
; enumerator_list instead gives every member the same span: the NAME capture still yields the
; correct line (l= comes from @name), but --expand=MEMBER_N then returns the ENTIRE enum body
; for every member. Measured on a 40-member enum before this shape was adopted.
(enumerator_list
  (enumerator
    left: (identifier) @name) @definition.constant)

; ---- variables and signals ----

; `var hp`, `@export var hp`, `@onready var spr`. VERIFIED SHAPE: in Godot 4 the annotation form
; parses as a plain (variable_statement (annotations …) name: (name)), NOT as the grammar's
; export_variable_statement / onready_variable_statement nodes — those are the Godot 3 spellings and
; do not fire on modern code. One pattern therefore covers all three.
;
; Captured as @definition.var, NOT @definition.field: fieldCaptureKept() returns false for every
; language but Python and C/C++, so a field capture from GDScript would be dropped without a trace.
; @definition.var also keeps these as real map symbols — an @export var is part of a Godot class's
; public surface and belongs in the ranked map, and a field never enters the symbol universe at all.
(source
  (variable_statement
    name: (name) @name) @definition.var)

(class_body
  (variable_statement
    name: (name) @name) @definition.var)

; `signal died(who)`. ripwire has no event/signal SymKind, and a signal is a declared member of the
; class rather than a callable, so it lands on @definition.var (t="var"). DISCLOSED as a deliberate
; approximation: it keeps Godot's signal surface visible and greppable in the map instead of dropping
; it, which is the direction this floor is allowed to be wrong in.
(signal_statement
  name: (name) @name) @definition.var

; ---- references (calls) ----

; VERIFIED SHAPE: `f(x)` is (call (identifier) arguments:); `o.m(x)` is
; (attribute (identifier) (attribute_call (identifier) arguments:)); `a.b.m(x)` nests the same
; attribute_call one level deeper. `super.take(x)` also parses as an attribute + attribute_call —
; `super` is an ordinary identifier to this grammar — so it is covered by the same two patterns and
; the grammar's own base_call node never fires on it.
(call
  (identifier) @name) @reference.call

(attribute_call
  (identifier) @name) @reference.call
