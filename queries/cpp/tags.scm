; ripwire C++ tags — vendored from tree-sitter-cpp v0.23.4 queries/tags.scm,
; AUGMENTED with @reference.call (the upstream C++ tags ship definitions ONLY).

; ---- definitions (upstream) ----

(struct_specifier name: (type_identifier) @name body:(_)) @definition.class

(declaration type: (union_specifier name: (type_identifier) @name)) @definition.class

(function_declarator declarator: (identifier) @name) @definition.function

(function_declarator declarator: (field_identifier) @name) @definition.method

(function_declarator declarator: (qualified_identifier name: (identifier) @name)) @definition.method

; ---- out-of-line definitions at 2+ qualifier segments (ripwire addition — C1, memgraph F1) ----
; The upstream pattern above is the DEFINITION twin of the 2-segment CALL pattern the §H4 round replaced,
; and it fails for the same reason: tree-sitter-cpp nests qualified_identifier RIGHT-recursively, so
; `void nsD::OuterD::InnerD::deep3()` is qualified_identifier(scope: nsD, name: qualified_identifier(
; scope: OuterD, name: qualified_identifier(scope: InnerD, name: deep3))) and `name: (identifier)` binds
; nothing past the second `::`. The def was dropped at EXTRACTION — no `--skipped` row, no floor, no
; `unresolved=` — so every caller of such a method read as a leaf and the symbol was unreachable from every
; verb. Measured on memgraph (whose house style is exactly this shape): 575 of 4526 qualified out-of-line
; defs invisible, 16 of 29 extracted in one 35 KB file. ripwire's own src/ has ZERO instances, which is
; precisely why the definition half survived the round that fixed the reference half.
;
; WHY A SECOND PATTERN RATHER THAN WIDENING THE FIRST TO `name: (_)`. The reference side widened in place
; because its 2-segment pattern would otherwise DOUBLE-MINT (ingest.cpp performs no ref-level dedup). Here
; the two patterns are disjoint by construction: `declarator:` anchors both to the function_declarator, and
; the inner qualified_identifier this pattern binds is the OUTER one's `name:` child, never a declarator —
; so a given definition matches exactly one of them at every depth. Keeping them separate leaves every
; pre-fix capture byte-identical and keeps the depth-1 operator pattern below unambiguous. Widening to
; `(_)` would additionally sweep in `destructor_name` and `template_function` declarators, which are a
; different (still open, still disclosed) gap and not this one.
;
; The captured node is the INNER qualified_identifier — ingest.cpp descends it to the innermost `name:`
; link (innermostQualifiedName), which restores all three properties the depth-1 path already has: the
; bare final name, a `nameByte` on the identifier itself, and a PARENT whose `scope:` field is the
; IMMEDIATE enclosing type — so `deep3` keys as `InnerD::deep3`, not as the outermost `nsD::deep3`.
(function_declarator declarator: (qualified_identifier name: (qualified_identifier) @name)) @definition.method

; ---- operator methods (ripwire addition) ----
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

; ---- module-level settings constants (ripwire addition — r3 q10) ----
; Same rationale and --match-verified declarator shapes as queries/c/tags.scm (the C++ grammar
; extends tree-sitter-c): file-scope `static const char* DEFAULT_HOSTS[] = { … }` tables and
; namespace-scope `inline constexpr int MAX_DEPTH = 12;`. Two scope wrappers because namespace
; (and extern "C") bodies are declaration_list, not translation_unit; class members are
; field_declaration_list, so member fields never match either pattern (they get their own capture
; below, 2026-08-12). Gated in ingest.cpp (dropConstantCapture): SCREAMING_SNAKE keeps (the r3 q10
; convention), and since the 2026-08-12 module-constant round a const/constexpr/constinit
; type_qualifier on the declaration ALSO keeps, case-blind — the qualifier keyword is the evidence
; (the Rust const_item rationale), which is what makes `constexpr std::uint32_t kParserVer = 61;`
; findable by name. Mutable non-SCREAMING globals still drop.

(translation_unit
  (declaration
    declarator: (init_declarator
      declarator: [
        (identifier) @name
        (pointer_declarator declarator: (identifier) @name)
        (array_declarator declarator: (identifier) @name)
        (pointer_declarator declarator: (array_declarator declarator: (identifier) @name))
      ])) @definition.constant)

(declaration_list
  (declaration
    declarator: (init_declarator
      declarator: [
        (identifier) @name
        (pointer_declarator declarator: (identifier) @name)
        (array_declarator declarator: (identifier) @name)
        (pointer_declarator declarator: (array_declarator declarator: (identifier) @name))
      ])) @definition.constant)

; ---- class-static constants (ripwire addition — the module-constant round, 2026-08-12) ----
; `static constexpr int kMaxDepth = 3;` inside a class/struct/union body is a field_declaration
; (NOT a declaration/init_declarator — in-class member initializers bind through the default_value
; field), so the module-scope patterns above never see it: pre-fix NO class-static constant was
; indexed, not even a SCREAMING one (probed 2026-08-12). This pattern is deliberately LOOSE — it
; also matches every plain default-member-initializer (`int retries = 3;`) — because tags-pass
; predicates never run (see the cast-keyword note below) and child ORDER between `static` and
; `constexpr` is not fixed in source. The whole keep decision lives in ingest.cpp
; (fieldConstantCaptureKept): keep iff the field carries BOTH a `static` storage_class_specifier
; AND a const/constexpr/constinit type_qualifier — per-instance fields (default-initialized or
; const non-static) drop. Bitfields bind through bitfield_clause, never default_value, and cannot
; match. Class-scope variable templates sit under template_declaration, not directly in the
; field_declaration_list, and are out of scope (disclosed, not captured).
(field_declaration_list
  (field_declaration
    declarator: [
      (field_identifier) @name
      (pointer_declarator declarator: (field_identifier) @name)
      (array_declarator declarator: (field_identifier) @name)
    ]
    default_value: (_)) @definition.constant)

; ---- CUDA memory-space module bindings (ripwire addition — the cudacheck §7b close-out) ----
; `__constant__ float rk_scaleTable[ 64 ];` carries NO initializer (host fills it via
; cudaMemcpyToSymbol), so the init_declarator patterns above can never match it — that, not the
; qualifier, was the measured 2026-08-04 gap. These two patterns take the UNINITIALIZED shape: a
; module-scope declaration with a plain (non-init, non-function) declarator. They carry NO qualifier
; constraint at all, for two stacked reasons measured on the vendored grammars: (1) the query cannot
; name the `__constant__` token — this file also compiles against tree-sitter-cpp (.cpp/.h/.metal),
; which lacks it, and ts_query_new would reject the whole query there; (2) a `(type_qualifier)` child
; constraint sees only `__constant__`/`__managed__` — tree-sitter-cuda parses `__device__` as an
; ANONYMOUS token child of the declaration (its only named children are the type and the declarator),
; invisible to any named-node constraint. The whole qualifier test therefore lives in ingest.cpp
; (cudaMemorySpaceQualifierOf), the same capture-time home as isCppCastKeyword, because tags-pass
; predicates never run (see the cast-keyword note below). Policy enforced there: `__constant__`
; extracts case-blind (the keyword is the evidence — the Rust const_item rationale);
; `__device__`/`__managed__` are mutable device globals and stay behind the SCREAMING gate; no
; memory-space token drops. The BLAST RADIUS of these unconstrained patterns is all of Lang::Cpp
; (.cpp/.cc/.cxx/.h/.hpp/.hh/.metal, not just .cu/.cuh), so it was measured, not argued (2026-08-10,
; port round): on ripwire's own src/ and on four real C++/CUDA trees the maps are BYTE-IDENTICAL to
; the pre-port binary's everywhere the qualifier is absent — every raw non-CUDA match is dropped by
; the ingest test, and the only added rows anywhere carry a memory-space qualifier in a .cu/.cuh.
; Function prototypes never match (their declarator is a function_declarator); function-local
; `__shared__` tiles never match (their scope is a compound_statement, not
; translation_unit/declaration_list).

(translation_unit
  (declaration
    declarator: [
      (identifier) @name
      (pointer_declarator declarator: (identifier) @name)
      (array_declarator declarator: (identifier) @name)
      (array_declarator declarator: (array_declarator declarator: (identifier) @name))
      (pointer_declarator declarator: (array_declarator declarator: (identifier) @name))
    ]) @definition.constant)

(declaration_list
  (declaration
    declarator: [
      (identifier) @name
      (pointer_declarator declarator: (identifier) @name)
      (array_declarator declarator: (identifier) @name)
      (array_declarator declarator: (array_declarator declarator: (identifier) @name))
      (pointer_declarator declarator: (array_declarator declarator: (identifier) @name))
    ]) @definition.constant)

; The same uninitialized shape under a PREPROCESSOR CONDITIONAL — measured against NVIDIA/cuda-samples
; (2026-08-04): the header-guard idiom (`#ifndef X_CUH` around the whole file) and the dual-compile
; `#ifdef __CUDACC__` region both make the declaration a child of preproc_ifdef/preproc_if (else/elif
; branches are their own node kinds), so the translation_unit/declaration_list anchors above never see
; it — volumeRender's `__constant__ float3x4 c_invViewMatrix;` and particles' `__constant__ SimParams
; cudaParams;` were measured misses. These four wrappers are deliberately UNANCHORED (guards nest:
; `#ifndef` guard + `#if` region is two levels), so they also fire on function-local declarations under
; a conditional — safe because legal CUDA allows the three memory-space qualifiers ONLY at namespace
; scope, so every function-local match lacks the qualifier and drops in ingest. 2-D tables
; (quasirandomGenerator's `c_Table[A][B]`) get the nested array_declarator alternative. The INITIALIZED
; patterns above deliberately do NOT gain preproc wrappers: that would newly extract #if-gated
; SCREAMING constants in plain C++ — a real behavior change for non-CUDA code that needs its own
; r3-q10-style measurement round, not a rider on this one.

(preproc_ifdef
  (declaration
    declarator: [
      (identifier) @name
      (pointer_declarator declarator: (identifier) @name)
      (array_declarator declarator: (identifier) @name)
      (array_declarator declarator: (array_declarator declarator: (identifier) @name))
      (pointer_declarator declarator: (array_declarator declarator: (identifier) @name))
    ]) @definition.constant)

(preproc_if
  (declaration
    declarator: [
      (identifier) @name
      (pointer_declarator declarator: (identifier) @name)
      (array_declarator declarator: (identifier) @name)
      (array_declarator declarator: (array_declarator declarator: (identifier) @name))
      (pointer_declarator declarator: (array_declarator declarator: (identifier) @name))
    ]) @definition.constant)

(preproc_else
  (declaration
    declarator: [
      (identifier) @name
      (pointer_declarator declarator: (identifier) @name)
      (array_declarator declarator: (identifier) @name)
      (array_declarator declarator: (array_declarator declarator: (identifier) @name))
      (pointer_declarator declarator: (array_declarator declarator: (identifier) @name))
    ]) @definition.constant)

(preproc_elif
  (declaration
    declarator: [
      (identifier) @name
      (pointer_declarator declarator: (identifier) @name)
      (array_declarator declarator: (identifier) @name)
      (array_declarator declarator: (array_declarator declarator: (identifier) @name))
      (pointer_declarator declarator: (array_declarator declarator: (identifier) @name))
    ]) @definition.constant)

; ---- function-like macros (macro-edges round) ----
; A FUNCTION-LIKE `#define NAME(args) body` becomes an indexed symbol (ingest.cpp defKind maps "macro" ->
; SymKind::Macro, t="macro" — a disclosed-degraded kind: the replacement text is an unparsed token in this
; grammar, so edges out of the body come from ingest.cpp's captureMacroBodyCalls lexical scan, and a
; call-shaped invocation of the name is re-tagged role="macro", never role="call"). This closes the
; macro-only-header hole (a header holding nothing but macros contributed ZERO symbols; ensemble.h's
; coverage precondition names exactly that shape). Deliberately NOT captured on the C++ path: OBJECT-LIKE
; `#define MAXN 42` (preproc_def) — a value alias, not a call-edge participant (the C tags.scm keeps its
; historical preproc_def capture, now honestly kinded t="macro"). Empty-body function-like macros are
; dropped in ingest.cpp (preprocFunctionDefHasBody): an empty replacement defines nothing callable.
(preproc_function_def
  name: (identifier) @name) @definition.macro

; ---- references (ripwire addition — calls drive the PageRank edges) ----

(call_expression
  function: (identifier) @name) @reference.call

(call_expression
  function: (field_expression
    field: (field_identifier) @name)) @reference.call

; QUALIFIED CALLS AT ANY DEPTH. tree-sitter-cpp nests
; qualified_identifier RIGHT-recursively — `rw::inner::targetFn` is
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

; USING-DECLARATION RE-EXPORTS (r9 loss bucket 1): `using lib::doWork;` — at namespace scope, inside a
; namespace body, or at class scope (`using Base::method;` — same node kind, matched wherever it appears) —
; is a single-symbol re-export, and pre-lever it minted NO reference at all: the site was invisible to
; --uses even though call RESOLUTION through the re-exported name already worked. The site is now a
; role="import" use-site of the target (ingest.cpp maps @reference.import → RefRole::Import; import refs
; never enter the call graph — graph.h admits Call+Macro only, so a never-called re-export gains the row
; and no edge). The name field binds the INNER node, so a 3+-segment `using a::b::c;` captures `b::c` and
; the existing H4 re-split recovers name `c` / immediate qualifier `b`, exactly as for qualified calls.
;
; EXCLUDED AT CAPTURE TIME, not here (ingest.cpp usingDeclarationIsDirective — passesPredicates is not
; wired into the tags pass, same story as the cast keywords): `using namespace ns;` (no single-symbol
; target; its qualified form `using namespace lib::nested;` matches this pattern and must be dropped) and
; `using enum E;` (re-exports the ENUMERATORS, not the named type). `using alias = type;` is a different
; node kind (alias_declaration) and never matches. A bare `using namespace x;` (unqualified) binds no
; qualified_identifier and never matches either.
(using_declaration
  (qualified_identifier
    name: (_) @name)) @reference.import

; EXPLICIT-TEMPLATE-ARGUMENT CALLS: `tmplFn<int>( a )` parses as
; call_expression function: (template_function name: (identifier) arguments: (template_argument_list)) —
; a distinct node kind none of the patterns above match, so these were dropped by the same silent mechanism
; (measured: `--callers=writeTally` returned 0 with a def and two call sites).
;
; WHY THE CAST KEYWORDS ARE NOT EXCLUDED HERE. tree-sitter-cpp parses `static_cast<T>(x)` as this exact
; shape, so this pattern also matches all four C++ cast keywords (171 sites in src/ alone). The natural fix
; — a `(#not-eq? @name "static_cast")` predicate — does NOT work: ripwire's passesPredicates is wired into
; --match/--lint only, never into the tags pass (measured: the predicate left --uses=static_cast at 165).
; The exclusion therefore lives at capture time in ingest.cpp (isCppCastKeyword), where it is enforceable.
(call_expression
  function: (template_function
    (identifier) @name)) @reference.call

; MACRO-DEFINED TEST BODIES (LB-E, r10 gitnexus harvest 2026-08-20): `TEST_CASE( "title" ) { … }` —
; doctest/Catch2's block-forming test macros — cannot be expanded by tree-sitter, so the source parses
; as TWO SIBLING nodes: an (expression_statement (call_expression …) (MISSING ";")) and a bare
; (compound_statement …). Neither is a definition, so pre-70 the body's calls attributed to NOTHING
; (measured on this repo: five pageRankDouble call sites invisible to --callers while --grep found all
; five — and --test-gate/--affected/tested= all rest on exactly those test→subject edges).
;
; This pattern captures the SHAPE ONLY: any identifier-call statement whose immediate next named
; sibling is a compound_statement. It deliberately over-matches — a real `logCall( "x" );` followed by
; an unrelated block inside a function body is this exact shape — because tags-pass predicates never
; run (same story as the cast keywords above). The three real gates live at capture time in
; ingest.cpp's testMacroBlockPartsOf: the callee must be a KNOWN test macro (kTestBlockMacroNames),
; the statement must carry the error-recovery MISSING ";" (a real semicolon disqualifies), and a title
; string literal must be present in the argument list (it becomes the symbol's name; the identifier
; captured as @name here is only the name-list key). TEST_CASE_TEMPLATE/SCENARIO_TEMPLATE are a
; documented gap: error recovery swallows their block INTO the argument list, so no sibling
; compound_statement exists and this pattern cannot see them.
((expression_statement
  (call_expression
    function: (identifier) @name)) @definition.testmacroblock
 .
 (compound_statement))
