; ripwire Python tags — vendored verbatim from tree-sitter-python v0.23.6 queries/tags.scm.

(module (expression_statement (assignment left: (identifier) @name) @definition.constant))

(class_definition
  name: (identifier) @name) @definition.class

(function_definition
  name: (identifier) @name) @definition.function

; ── Python shape round (2026-08-04, test/pyshapecheck.sh — measured on django@7d75c0b and
; pydantic@2e5f0e2; every count below is from a SINGLE-capture --match confirmation). ──

; Annotated class attribute `x: T [= v]` — the typed field surface: pydantic model fields,
; dataclass fields, TypedDict/NamedTuple members, ClassVar (31 django + 6 199 pydantic sites,
; ~1-3% extracted before). The `type:` field is the structural line that keeps django's 12 987
; plain un-annotated data attrs (`field = models.CharField()`) OUT of the map.
(class_definition body: (block (expression_statement (assignment left: (identifier) @name type: (type)) @definition.constant)))

; Plain class-body assignment, kept ONLY when the enclosing class's base NAME is an enum family
; (60 stdlib + 91 Choices members in django, 245 in pydantic). The semantic half lives in
; dropGatedCapture/isPyEnumMemberTarget — tags-pass predicates never run, so the name test
; cannot live here.
(class_definition body: (block (expression_statement (assignment left: (identifier) @name !type) @definition.enummember)))

; A lambda bound to a class attribute is callable surface (11 pydantic sites) — the same line the
; JS round drew for field_definition bound to an arrow.
(class_definition body: (block (expression_statement (assignment left: (identifier) @name right: (lambda)) @definition.function)))

; ONE guard level of module bindings: TYPE_CHECKING blocks, platform ifs, import-fallback trys —
; 34+2+6+108 django and 170+1+15+17 pydantic sites lived one guard deep. Case-blind like the
; vendored module pattern above (constcheck.sh §5); two guard levels stay out (pyshapecheck §4).
(module (if_statement (block (expression_statement (assignment left: (identifier) @name) @definition.constant))))
(module (if_statement alternative: (elif_clause (block (expression_statement (assignment left: (identifier) @name) @definition.constant)))))
(module (if_statement alternative: (else_clause (block (expression_statement (assignment left: (identifier) @name) @definition.constant)))))
(module (try_statement (block (expression_statement (assignment left: (identifier) @name) @definition.constant))))
(module (try_statement (except_clause (block (expression_statement (assignment left: (identifier) @name) @definition.constant)))))
(module (try_statement (else_clause (block (expression_statement (assignment left: (identifier) @name) @definition.constant)))))
(module (try_statement (finally_clause (block (expression_statement (assignment left: (identifier) @name) @definition.constant)))))

; Tuple-unpack module binding `A, B = 1, 2` — one def per identifier (6 django sites).
(module (expression_statement (assignment left: (pattern_list (identifier) @name)) @definition.constant))

(call
  function: [
      (identifier) @name
      (attribute
        attribute: (identifier) @name)
  ]) @reference.call
