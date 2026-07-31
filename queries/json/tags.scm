; ripwire JSON tags — written for ripwire (.json). Derived from the upstream
; tree-sitter-json v0.24.8 grammar node-types, verified against an AST dump (see the
; jsonlangcheck fixture).
;
; JSON is DATA, not code: it has no functions, classes, or call sites. The value here is
; CONFIG VISIBILITY — package.json / tsconfig.json / composer.json become findable by
; --for / --grep with their enclosing key as the symbol. We index a CURATED subset:
;
;   - TOP-LEVEL object keys           → def nodes, kind Section (t="sec"), like a heading
;   - SECOND-LEVEL keys under a        → def nodes, kind Section — this is the useful
;     top-level object value             granularity: each entry under "dependencies",
;                                         "scripts", "compilerOptions", etc.
;
; Deliberately NOT captured: values (strings/numbers/bools), array elements, and anything
; deeper than the second level (a package.json's dep list is level-2; leaves would explode
; the node count for no lookup value). There are NO @reference captures — JSON emits zero
; call edges, and langCompatible (graph.h) keeps a JSON key from ever resolving a C++/JS
; name of the same spelling (e.g. a "name" key never becomes an edge target of a `name` fn).
;
; The def node is the (pair); @name is the key string's content (quotes stripped by the
; grammar's string_content child, so the symbol name is `dependencies`, not `"dependencies"`).

; ---- top-level keys (direct children of the document's root object) ----
(document
  (object
    (pair
      key: (string (string_content) @name)) @definition.section))

; ---- second-level keys (a key inside a top-level object value) ----
(document
  (object
    (pair
      value: (object
        (pair
          key: (string (string_content) @name)) @definition.section))))
