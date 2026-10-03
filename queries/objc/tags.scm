; ripwire Objective-C / Objective-C++ tags — for amaanq/tree-sitter-objc (inherits tree-sitter-C).
; Captures the ObjC layer (classes / methods / protocols / [message sends]) + C-style funcs/calls.
; Patterns derived from the grammar's highlights.scm + a verified parse dump. This grammar does NOT
; understand C++ (templates / namespaces / ::), so C++-heavy regions of a .mm error-recover & are partial.

; ---- definitions ----
; class name = the identifier immediately after @interface/@implementation (anchored, before superclass:)
(class_interface      "@interface"      . (identifier) @name) @definition.class
(class_implementation "@implementation" . (identifier) @name) @definition.class
(protocol_declaration . (identifier) @name) @definition.interface
; method name = first selector identifier after the return type (anchored → ONE symbol per method,
; not one per keyword fragment, e.g. drawMesh:withEnc: → "drawMesh")
(method_definition  (method_type) . (identifier) @name) @definition.method
(method_declaration (method_type) . (identifier) @name) @definition.method
; C functions (inherited from tree-sitter-C)
(function_definition declarator: (function_declarator declarator: (identifier) @name)) @definition.function

; ---- references ----
; ObjC message sends [recv selector:...]; keyword fragments self-clean (unresolved names drop in the graph)
(message_expression method: (identifier) @name) @reference.call
; C-style calls foo(...)
(call_expression function: (identifier) @name) @reference.call
; C-style field/struct-pointer calls ops->init(...) / val.init(...) — parity with the parent C
; grammar (queries/c/tags.scm), which already carries this line; the ObjC layer had it missing (H4).
; Refs mostly stay unresolved: ObjC field-calls are function-pointer struct fields (methods use
; message sends, not field_expression), so this is a zero-cost honesty gain, not a resolution gain —
; matches C's own documented behavior for the same shape.
(call_expression function: (field_expression field: (field_identifier) @name)) @reference.call

; ---- import capture (the shared vocabulary of issue #358) ----
; ONE capture name for every include spelling this grammar has. The node is the path TOKEN as written,
; delimiters included — `"dep.h"`, `<dep.h>`, or a bare macro name — and the CFamily normaliser turns it
; into a bare path plus the quote-vs-angle bit. Read off a real parse with `--match`, never predicted
; (13 hits over the test/importcapcheck.sh fixture: every #include in all three grammars plus the two
; ObjC #import). The UNANCHORED shape is what reaches an include written inside an #if/#else/#elif guard,
; which is the union-over-arms posture ingest_relations.h already documents — a spurious edge, never a
; missing one.
(preproc_include
  path: (_) @import.path)
