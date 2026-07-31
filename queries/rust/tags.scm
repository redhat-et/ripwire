; ripwire Rust tags — vendored from tree-sitter-rust v0.23.2 queries/tags.scm.
; Kept verbatim except: (1) the @reference.implementation patterns are dropped (impl blocks are
; not calls; they'd inflate edges without modeling call flow — SPEC §2a, calls drive edges);
; (2) H4 W3 adds the two `::`-path / turbofish call patterns below (upstream has neither, so
; upstream loses the dominant Rust call form too); (3) H4 W3 moves the @definition.method capture
; from the `declaration_list` wrapper onto the `function_item` — see the note at that pattern.

; ADT definitions

(struct_item
    name: (type_identifier) @name) @definition.class

(enum_item
    name: (type_identifier) @name) @definition.class

(union_item
    name: (type_identifier) @name) @definition.class

; type aliases

(type_item
    name: (type_identifier) @name) @definition.class

; method definitions
;
; H4 W3 SPAN FIX (divergence from the vendored upstream file — see header). The `@definition.method`
; capture used to sit on the `declaration_list` WRAPPER. That node has no `body:` field, so ingest's
; span-widening walk climbed one more level to the `impl_item`/`mod_item` (which does) and every method
; in a block got THE WHOLE BLOCK as its [startByte,endByte) span. Consequences, all measured before the
; fix: `--expand=bump` printed the entire `impl Widget { ... }`; per-method loc/cx/ccx/params/maxNest
; described the block, not the method; and — the one that breaks the call graph — reference
; enclosing-attribution resolved EVERY call in the block to whichever method the DefSweep's active stack
; happened to leave on top (the last-sorted identical span), so `Self::helper()` inside `bump` was
; attributed to `helper` calling ITSELF. The discriminator this pattern exists for is "the function_item
; sits inside a declaration_list" — that is expressed by the pattern SHAPE, so the capture belongs on the
; function_item, where `body:` is found immediately and no climb happens. Dedup is unaffected: identity is
; (fileId, name-token start byte) and Method still outranks Function on specificity.
(declaration_list
    (function_item
        name: (identifier) @name) @definition.method)

; function definitions

(function_item
    name: (identifier) @name) @definition.function

; trait definitions
(trait_item
    name: (type_identifier) @name) @definition.interface

; module definitions
(mod_item
    name: (identifier) @name) @definition.module

; macro definitions

(macro_definition
    name: (identifier) @name) @definition.macro

; references (calls)

(call_expression
    function: (identifier) @name) @reference.call

(call_expression
    function: (field_expression
        field: (field_identifier) @name)) @reference.call

; H4 (PLAN_h4QualifiedCalls_2026-07-30.md §3.2): `::`-path calls — the DOMINANT Rust call form
; (`Widget::new()`, `util::deep::deepfn()`, `Self::helper()`, `Widget::bump(&mut w)`), 100% invisible
; before this pattern. tree-sitter-rust nests scoped_identifier LEFT — `util::deep::deepfn` is
; `scoped_identifier(path: scoped_identifier(path: identifier, name: identifier), name: identifier)` —
; so the `name:` field IS the final segment at EVERY depth and ONE pattern covers all of them. The
; turbofish-on-a-TYPE spelling `Vec::<u32>::new()` is also this node kind
; (`scoped_identifier(path: generic_type, name: identifier)`, verified by --match), so it needs no
; second pattern. ingest.cpp mints the ref's `qualifier` from the `path:` sibling (see rustPathQualifier).
(call_expression
    function: (scoped_identifier
        name: (identifier) @name)) @reference.call

; H4: turbofish on a BARE function — `generic::<u32>(1)` — contains no `::`-PATH at all; its `function:`
; child is a distinct node kind, `generic_function(function: identifier)`. VERIFIED that the scoped
; variant `generic_function(function: (scoped_identifier))` does NOT occur (0 hits on the fixture:
; `Vec::<u32>::new` parses as scoped_identifier-over-generic_type, covered above), so this one nesting
; is the whole form. No cast trap here — Rust has no `static_cast<T>(x)` call-shaped keyword.
(call_expression
    function: (generic_function
        function: (identifier) @name)) @reference.call

(macro_invocation
    macro: (identifier) @name) @reference.call
