; ripwire PHP tags — written for ripwire (.php). Derived from the upstream
; tree-sitter/tree-sitter-php v0.24.2 `php/` sub-grammar's node-types.json and verified against real
; parses (test/phpfix + the laravel/framework shape-recall run). The upstream queries/tags.scm was the
; starting point but is NOT what ships here: it captures properties as fields, calls a method a
; `@definition.function`, and has no notion of the enum/const shapes this repo's r3-q10 config-constant
; lane cares about. This file follows the C# / Java convention already in the tree instead, because PHP's
; structure is the same structure: named types holding named methods, plus free functions.
;
; PHP structure the call graph cares about:
;   - type declarations: class / interface / trait / enum → def nodes (the containers)
;   - function + method declarations → the def nodes calls resolve TO
;   - calls: bare `f()`, `$o->m()`, `$o?->m()`, `A::m()`, and `new C()` → the call references (edges)
;   - `use Foo\Bar;` → captured separately by ingest.cpp::captureIncludes (NOT here — matches how every
;     other language's imports are handled; tags.scm never captures imports directly)
;   - `class C extends B implements I` → captured separately by ingest.cpp::captureBases (base_clause /
;     class_interface_clause), which is what feeds --uses role="extends" and --lego
;
; Deliberately NOT captured (noise, matching C#/Java/Ruby): properties, local/global variables,
; attributes, parameters, and the `namespace App\Http;` declaration itself. The last one is a
; deliberate match to queries/csharp/tags.scm, which also declines to make a namespace a symbol: a
; PHP namespace is a per-file header, so capturing it would mint one extra t="other" symbol in every
; single file of a corpus (≈6 400 of them on laravel/framework) that nothing ever resolves to.
;
; Deliberately NOT captured (CANNOT be, and it is disclosed rather than faked): PHP's dynamic call
; forms. `$fn()`, `$obj->$name()`, `call_user_func([$o, 'm'])`, `__call`/`__callStatic` magic
; dispatch and `new $class` all name their callee at RUN time. A static extractor has no name to
; bind, so those call sites produce no edge — the same honest floor every other language here
; carries for its own dynamic dispatch (see the `amb=`/`counts_floor=` disclosure conventions).

; ---- definitions ----

(class_declaration
  name: (name) @name) @definition.class

(interface_declaration
  name: (name) @name) @definition.interface

; A trait is PHP's horizontal-reuse unit: it declares methods that a using class acquires. Structurally
; that is the interface/protocol role (a named bag of members that classes bind to), so it buckets as
; t="iface" — which also puts it in --lego's implementor view, where it belongs. Disclosed difference
; from a real interface: a trait carries method BODIES, and `use SomeTrait;` inside a class body is NOT
; captured as an inheritance edge (it is a `use_declaration` inside declaration_list, not a base_clause).
(trait_declaration
  name: (name) @name) @definition.interface

; enum Status: string { case Active = 'active'; } — typedef/alias/enum bucket, matching Java's and C#'s
; enum_declaration → definition.type.
(enum_declaration
  name: (name) @name) @definition.type

(function_definition
  name: (name) @name) @definition.function

(method_declaration
  name: (name) @name) @definition.method

; ---- constants (r3 q10 settings-constant lane) ----
; PHP declares constants by KEYWORD, not by convention, so — unlike Java's and C#'s field_declaration
; patterns — these two need no SCREAMING_SNAKE gate (ingest.cpp's constCaptureNeedsScreamingGate
; deliberately does not list Php). Same reasoning Rust's const_item/static_item already ride: the
; keyword IS the evidence, so a lower-case `const version = '1'` is still a real constant and is kept.
(const_declaration
  (const_element
    (name) @name)) @definition.constant

(enum_case
  name: (name) @name) @definition.constant

; ---- references (calls) ----

; f( .. ) — bare call to a free function in the current namespace
(function_call_expression
  function: (name) @name) @reference.call

; \Foo\bar( .. ) / Foo\bar( .. ) — namespace-qualified free call; finalSegment keys on the last part
(function_call_expression
  function: (qualified_name (name) @name)) @reference.call

; $obj->m( .. )
(member_call_expression
  name: (name) @name) @reference.call

; $obj?->m( .. ) — the null-safe operator is a DISTINCT node kind (nullsafe_member_call_expression),
; exactly like C#'s `?.` conditional-access form, so it needs its own pattern or every null-safe call
; site is silently dropped.
(nullsafe_member_call_expression
  name: (name) @name) @reference.call

; A::m( .. ) / self::m( .. ) / parent::m( .. ) / static::m( .. )
(scoped_call_expression
  name: (name) @name) @reference.call

; new C( .. ) — object creation resolves to the constructor / class name. Unfielded on purpose: the
; grammar gives object_creation_expression no `type:` field, and its class-name children are exactly
; (name) and (qualified_name) — an `arguments` child cannot match either pattern, and `new class {}`
; (anonymous_class) matches neither, which is correct.
(object_creation_expression
  (name) @name) @reference.call

(object_creation_expression
  (qualified_name (name) @name)) @reference.call
