; ripwire C tags — written for ripwire (.c). Derived from the upstream tree-sitter/tree-sitter-c
; v0.24.1 queries/tags.scm (definitions only: struct/union/enum/typedef/function) plus the SAME
; @reference.call augmentation the C++ tags.scm already carries (upstream C tags ship definitions
; ONLY, matching upstream C++). tree-sitter-c is the grammar tree-sitter-cpp itself EXTENDS, so the
; lower node shapes below (function_declarator, field_expression, call_expression) are byte-for-byte
; the same as the C++ patterns in queries/cpp/tags.scm — this file mirrors them, C-only surface.
;
; C structure the call graph cares about:
;   - struct/union/enum/typedef -> def nodes (the containers + the type-alias bucket)
;   - function DEFINITIONS (function_declarator inside a function_definition, or a bare prototype
;     declaration) -> the def nodes calls resolve TO
;   - object-like (#define X 1) and function-like (#define F(x) ...) macros -> def nodes, same
;     @definition.macro bucket Rust's macro_definition already uses (macro-edges round: ingest.cpp's
;     defKind maps "macro" -> SymKind::Macro, t="macro" — the kind now says what the thing is; a
;     call-shaped invocation of a function-like macro's name is a role="macro" edge, never role="call",
;     and its replacement text is body-scanned for outgoing calls. Empty-body FUNCTION-LIKE macros are
;     dropped in ingest.cpp — an empty replacement defines nothing callable; object-like stay indexed)
;   - calls (bare `f()` and `recv->f()` / `recv.f()` via a struct field) -> the call references (edges)
;   - `#include` is captured separately by ingest.cpp::captureIncludes (NOT here — matches every
;     other C-family language; resolve.h's `.c`/`.h` IncludeLang::CFamily entry already existed).
;
; Deliberately NOT captured (noise, matching the C++/Java/Ruby convention): plain variables, struct
; fields, enumerators. NOT modeled: function POINTERS assigned dynamically (`ops->init = my_init;`
; then `ops->init()`) — the field_expression call pattern below fires on the CALL site syntax, not
; on data-flow, so it captures `s.fn()`/`s->fn()` call shapes the same way C++ member calls are
; captured; resolving WHICH function a pointer field holds is out of this tool's static-syntax scope
; (same limitation the C++ tags.scm documents for operator-overload calls).

; ---- definitions ----

(struct_specifier
  name: (type_identifier) @name
  body: (_)) @definition.class

(declaration
  type: (union_specifier
    name: (type_identifier) @name)) @definition.class

(enum_specifier
  name: (type_identifier) @name) @definition.type

(type_definition
  declarator: (type_identifier) @name) @definition.type

(function_declarator
  declarator: (identifier) @name) @definition.function

; #define NAME ...            (object-like macro)
(preproc_def
  name: (identifier) @name) @definition.macro

; #define NAME(params) ...    (function-like macro)
(preproc_function_def
  name: (identifier) @name) @definition.macro

; settings constants (r3 q10 — bench/headtohead/r3-headroom-2026-08-03): file-scope
; `static const int C_MAX_BUFFER_BYTES = 4096;` and the pointer/array table forms
; (`static const char* DEFAULT_HOSTS[] = { … };`) — feature-flag/settings tables at
; translation-unit scope. The (translation_unit …) wrapper keeps function-local declarations out;
; the declarator alternation covers the three --match-verified nestings (identifier /
; pointer→identifier / array→identifier) plus array-of-pointers (pointer→array→identifier).
; SCREAMING_SNAKE-gated in ingest.cpp, so `int c_mutable_global = 3;` stays unindexed — the
; "plain variables" noise exclusion above still holds for everything convention marks mutable.
(translation_unit
  (declaration
    declarator: (init_declarator
      declarator: [
        (identifier) @name
        (pointer_declarator declarator: (identifier) @name)
        (array_declarator declarator: (identifier) @name)
        (pointer_declarator declarator: (array_declarator declarator: (identifier) @name))
      ])) @definition.constant)

; ---- references (calls) ----

(call_expression
  function: (identifier) @name) @reference.call

(call_expression
  function: (field_expression
    field: (field_identifier) @name)) @reference.call
