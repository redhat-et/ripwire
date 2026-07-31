; ctxpack TypeScript tags — written for ctxpack.
; The upstream tree-sitter-typescript tags.scm targets .d.ts declaration files
; (function_signature / method_signature) and ships no @reference.call, so it extracts
; almost nothing from ordinary .ts/.tsx source. This set covers real source: concrete
; declarations + arrow-function-bound consts + call/new references. Used for BOTH
; typescript and tsx (the tsx grammar is a superset).

; ---- definitions ----

(function_declaration
  name: (identifier) @name) @definition.function

(generator_function_declaration
  name: (identifier) @name) @definition.function

(class_declaration
  name: (type_identifier) @name) @definition.class

(abstract_class_declaration
  name: (type_identifier) @name) @definition.class

(interface_declaration
  name: (type_identifier) @name) @definition.interface

(enum_declaration
  name: (identifier) @name) @definition.class

(type_alias_declaration
  name: (type_identifier) @name) @definition.type

(method_definition
  name: (property_identifier) @name) @definition.method

; const foo = (..) => {..}  /  const foo = function(){..}  -> a named function
(lexical_declaration
  (variable_declarator
    name: (identifier) @name
    value: [ (arrow_function) (function_expression) ])) @definition.function

; declaration-file signatures (kept so .d.ts still yields symbols)
(function_signature
  name: (identifier) @name) @definition.function

(method_signature
  name: (property_identifier) @name) @definition.method

; ---- references ----

(call_expression
  function: (identifier) @name) @reference.call

(call_expression
  function: (member_expression
    property: (property_identifier) @name)) @reference.call

(new_expression
  constructor: (identifier) @name) @reference.call

; H4: qualified `new` — `new ns.Inner()` / `new a.b.C()`. member_expression nests LEFT (property: is
; always the final segment at any depth), so this binds the constructed CLASS name regardless of
; namespace depth — same ctor-ref-to-class-def precedent as the bare form above. Verified with
; --match on fixtures/ts at 2 AND 3 segments (H4_grammarSurvey_2026-07-30.md §SHAPES).
(new_expression
  constructor: (member_expression
    property: (property_identifier) @name)) @reference.call
