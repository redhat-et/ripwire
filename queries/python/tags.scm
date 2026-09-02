; ripwire Python tags — vendored verbatim from tree-sitter-python v0.23.6 queries/tags.scm.

(module (expression_statement (assignment left: (identifier) @name) @definition.constant))

(class_definition
  name: (identifier) @name) @definition.class

(function_definition
  name: (identifier) @name) @definition.function

; ── Python shape round (test/pyshapecheck.sh — derived 2026-08-04, RE-MEASURED 2026-08-10 at
; kParserVer 59 on django@c334c1a8ff and pydantic@8898b8f; every count below is capture SITES from a
; SINGLE-capture --match confirmation, cross-checked against a CPython-ast ground truth). ──

; Annotated class attribute `x: T [= v]` — the typed field surface: pydantic model fields,
; dataclass fields, TypedDict/NamedTuple members, ClassVar (2 django + 5 653 pydantic sites, 0%
; EXCLUSIVE recall before). The `type:` field is the structural line that keeps django's 12 131
; plain un-annotated data attrs (`field = models.CharField()`) OUT of the map.
; Member-variable round (card A3, 2026-09-02): the annotated class attribute is a FIELD (t="field",
; id=path::Owner::field) — it was t="var" before; the same sites, the honest kind. The keep test is
; unchanged (the type: field IS the structural discriminant; dropGatedCapture keeps every annotated
; class-body capture — see fieldCaptureKept's Python arm).
(class_definition body: (block (expression_statement (assignment left: (identifier) @name type: (type)) @definition.field)))

; Instance attribute bound in a method: `self.x = …` / `self.x: T = …` at ANY depth under the method
; (an `if` in __init__ still declares it). tree-sitter has no descendant operator and tags-pass
; predicates never run, so the pattern is LOOSE — it matches `obj.x = …` too — and the gate lives in
; ingest_names.h fieldCaptureKept: the receiver must be the bare identifier `self` and the assignment
; must sit inside a function inside a class. ONE symbol per (class, name): ingest_sidecap.h keeps the
; lowest-byte assignment per key (the definition), every later one is a role="write" use-site
; (test/fieldusescheck.sh arm F). `cls.x = …` is not captured (disclosed).
(assignment left: (attribute object: (identifier) attribute: (identifier) @name)) @definition.field

; Plain class-body assignment, kept ONLY when the enclosing class's base NAME is an enum family
; (132 sites in django — stdlib enum plus the Choices family — and 108 in pydantic). The semantic
; half lives in dropGatedCapture/isPyEnumMemberTarget — tags-pass predicates never run, so the name
; test cannot live here.
(class_definition body: (block (expression_statement (assignment left: (identifier) @name !type) @definition.enummember)))

; A lambda bound to a class attribute is callable surface (26 pydantic sites) — the same line the
; JS round drew for field_definition bound to an arrow.
(class_definition body: (block (expression_statement (assignment left: (identifier) @name right: (lambda)) @definition.function)))

; ONE guard level of module bindings: TYPE_CHECKING blocks, platform ifs, import-fallback trys —
; 29+2+8+27+70+8+0 django and 157+0+19+0+16+6+0 pydantic sites lived one guard deep. Case-BLIND like
; the vendored module pattern above (constcheck.sh §5); two guard levels stay out (pyshapecheck §4).
; A tuple-unpack or a chained `a = b = v` INSIDE a guard is not reachable from a direct-child
; `left: (identifier)` capture and stays out — 6 django / 7 pydantic sites, disclosed in the gate.
(module (if_statement (block (expression_statement (assignment left: (identifier) @name) @definition.constant))))
(module (if_statement alternative: (elif_clause (block (expression_statement (assignment left: (identifier) @name) @definition.constant)))))
(module (if_statement alternative: (else_clause (block (expression_statement (assignment left: (identifier) @name) @definition.constant)))))
(module (try_statement (block (expression_statement (assignment left: (identifier) @name) @definition.constant))))
(module (try_statement (except_clause (block (expression_statement (assignment left: (identifier) @name) @definition.constant)))))
(module (try_statement (else_clause (block (expression_statement (assignment left: (identifier) @name) @definition.constant)))))
(module (try_statement (finally_clause (block (expression_statement (assignment left: (identifier) @name) @definition.constant)))))

; Tuple-unpack module binding `A, B = 1, 2` — one def per identifier (2 django sites).
(module (expression_statement (assignment left: (pattern_list (identifier) @name)) @definition.constant))

(call
  function: [
      (identifier) @name
      (attribute
        attribute: (identifier) @name)
  ]) @reference.call
