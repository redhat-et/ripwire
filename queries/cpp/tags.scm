; ctxpack C++ tags — vendored from tree-sitter-cpp v0.23.4 queries/tags.scm,
; AUGMENTED with @reference.call (the upstream C++ tags ship definitions ONLY).

; ---- definitions (upstream) ----

(struct_specifier name: (type_identifier) @name body:(_)) @definition.class

(declaration type: (union_specifier name: (type_identifier) @name)) @definition.class

(function_declarator declarator: (identifier) @name) @definition.function

(function_declarator declarator: (field_identifier) @name) @definition.method

(function_declarator declarator: (qualified_identifier name: (identifier) @name)) @definition.method

; ---- operator methods (ctxpack addition) ----
; The upstream C++ tags capture methods only via identifier/field_identifier/qualified_identifier
; declarators; an OPERATOR's declarator is a distinct node kind (operator_name for symbolic/subscript/
; call/arrow ops, operator_cast for conversion ops), so operators were invisible. These three patterns
; mirror the method patterns above for each operator declarator kind. The @name span is the whole
; operator token — `operator==`, `operator[]`, `operator<<` (the last emitted XML-escaped as
; `operator&lt;&lt;`). LIMITATION: operator CALL edges are out of scope. Implicit `a == b` parses as a
; binary_expression (not a call_expression); resolving it to operator== needs semantic overload
; resolution, outside the tool's contract. Even EXPLICIT `a.operator==(b)` does not parse as a clean
; `field_expression field:(operator_name)` call in this grammar (its function child resolves to `a`),
; so no @reference.call pattern is added for it. Operators are captured as DEFINITIONS only; their
; fan-in stays low.

; member operator (in-class):  bool operator==( const V& ) const;  V& operator=( ... );  T& operator()( int );
(function_declarator declarator: (operator_name) @name) @definition.method

; out-of-line operator definition:  bool V::operator==( const V& ) const { ... }
(function_declarator declarator: (qualified_identifier name: (operator_name) @name)) @definition.method

; conversion operator:  operator bool() const;  operator MyType() const;  (declarator kind = operator_cast;
; the whole node spans `operator bool() const`, so ingest.cpp trims it to the `operator <type>` name)
(operator_cast) @name @definition.method

(type_definition declarator: (type_identifier) @name) @definition.type

(enum_specifier name: (type_identifier) @name) @definition.type

(class_specifier name: (type_identifier) @name) @definition.class

; ---- references (ctxpack addition — calls drive the PageRank edges) ----

(call_expression
  function: (identifier) @name) @reference.call

(call_expression
  function: (field_expression
    field: (field_identifier) @name)) @reference.call

; QUALIFIED CALLS AT ANY DEPTH (§H4, PLAN_h4QualifiedCalls_2026-07-30.md). tree-sitter-cpp nests
; qualified_identifier RIGHT-recursively — `ctx::inner::targetFn` is
; qualified_identifier(scope: ctx, name: qualified_identifier(scope: inner, name: targetFn)) — so the
; 2-segment pattern this REPLACES (`name: (identifier)`) bound nothing past the second `::`: 31 in-repo
; call sites on the CLI↔MCP seams produced NO reference at all, invisible to --uses/--callers/--edit-check
; AND to `ambiguous=`/`unresolved=` (the drop is at EXTRACTION, before resolution can account for it).
; `name: (_)` is depth-unbounded and also covers the `name: (template_function)` case (`ns::tmplFn<int>()`),
; which needs no pattern of its own.
;
; WHY THE 2-SEGMENT PATTERN IS REPLACED, NOT KEPT ALONGSIDE. ingest.cpp mints ONE RawRef per query match and
; performs no ref-level dedup, so a 2-segment call matching both patterns is minted TWICE (measured on the
; W1 throwaway tree: `--uses=fnv1aMultiply` 27 → 56), and the duplicates double-count into `ambiguous=` AND
; `unresolved=`. One pattern, one match, one reference.
;
; The captured @name is now the inner node, whose TEXT still carries the remaining scope
; (`inner::targetFn`); ingest.cpp re-splits it at the last TOP-LEVEL `::` into name + immediate qualifier so
; the canonical `qualifier::name` tier keeps resolving these precisely at every depth. finalSegment() alone
; is NOT safe here — it truncates at the first `<`, which would name
; `numeric_limits<std::size_t>::max()` as `numeric_limits`.
(call_expression
  function: (qualified_identifier
    name: (_) @name)) @reference.call

; EXPLICIT-TEMPLATE-ARGUMENT CALLS: `tmplFn<int>( a )` parses as
; call_expression function: (template_function name: (identifier) arguments: (template_argument_list)) —
; a distinct node kind none of the patterns above match, so these were dropped by the same silent mechanism
; (measured: `--callers=writeTally` returned 0 with a def and two call sites).
;
; WHY THE CAST KEYWORDS ARE NOT EXCLUDED HERE. tree-sitter-cpp parses `static_cast<T>(x)` as this exact
; shape, so this pattern also matches all four C++ cast keywords (171 sites in src/ alone). The natural fix
; — a `(#not-eq? @name "static_cast")` predicate — does NOT work: ctxpack's passesPredicates is wired into
; --match/--lint only, never into the tags pass (measured: the predicate left --uses=static_cast at 165).
; The exclusion therefore lives at capture time in ingest.cpp (isCppCastKeyword), where it is enforceable.
(call_expression
  function: (template_function
    (identifier) @name)) @reference.call
