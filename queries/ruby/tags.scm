; ripwire Ruby tags — written for ripwire (.rb). Derived from the upstream
; tree-sitter-ruby v0.23.1 grammar node-types, verified against an AST dump (see the
; javarubycheck fixture).
;
; Ruby structure the call graph cares about:
;   - class / module definitions → def nodes (containers; module is a namespace/mixin)
;   - `def name` / `def self.name` method definitions → the def nodes calls resolve TO
;   - method calls → the call references (edges). A bare `foo` with no receiver and no
;     args parses as (identifier); `foo(..)` / `obj.foo` parses as (call). We capture the
;     (call) form's method name — the reliable, unambiguous call site.
;   - require / require_relative → reference edges (they ARE plain (call) nodes, captured
;     by the call rule below — no separate rule needed).
;
; Deliberately NOT captured (noise): instance/local variables, blocks, and CamelCase constant
; aliases (`CamelAlias = Struct.new(:x)` — a class-ish alias, not a settings value). SCREAMING_SNAKE
; constant assignments ARE captured — see the settings-constant pattern below (r3 q10).

; ---- definitions ----

(class
  name: [ (constant) (scope_resolution) ] @name) @definition.class

(module
  name: [ (constant) (scope_resolution) ] @name) @definition.module

; `def greet ... end`  and  `def self.greet ... end` — both are (method name: ..)/(singleton_method).
; A setter `def name=(v)` names itself with a (setter) node whose text is `name=` — that text IS the
; method's name, and the call side spells the same name for `obj.name = v` (ingest reads the
; (assignment left: (call …)) parent — see the call rule below), so the two meet by name like any
; other edge. test/rubysettercheck.sh.
(method
  name: [ (identifier) (operator) (setter) ] @name) @definition.method

(singleton_method
  name: [ (identifier) (operator) (setter) ] @name) @definition.method

; settings constants (r3 q10 — bench/headtohead/r3-headroom-2026-08-03): `PASSWORD_HASHERS = [...]`
; at toplevel or class level. (constant) is Ruby's own syntactic class for uppercase-initial names,
; so a lowercase local `x = 1` (left: (identifier)) can never match; the SCREAMING_SNAKE gate in
; ingest.cpp (constCaptureNeedsScreamingGate) then drops CamelCase aliases. Unscoped on purpose:
; a method-local constant assignment is a Ruby SyntaxError (dynamic constant assignment), so this
; pattern structurally cannot capture locals. Shape verified with --match on the constcheck fixture.
(assignment
  left: (constant) @name) @definition.constant

; ---- references (calls) ----
; `foo(..)`, `obj.foo`, and `require "x"` / `require_relative "y"` are all (call) nodes —
; the method field is the callee name. A def named `foo` in the same (or another indexed)
; file becomes a real <c> edge; unresolved names (require, stdlib) drop, as everywhere else.

; A setter CALL `obj.name = v` parses as (assignment left: (call method: (identifier))) — the same
; (call) shape as a read, so this rule captures it too. ingest renames that capture `name=` (the
; assignment's `left:` field is the (call)), so it resolves to `def name=` and never to the getter.
; Stated floors, all pinned by test/rubysettercheck.sh: an operator_assignment (`obj.count += 1`,
; `obj.count ||= 1`) reads AND writes and one capture carries one name, so it keeps the getter edge
; only; a left_assignment_list (`a.x, b.y = 1, 2`) wraps its targets one level below `left:` and is
; not read either. This rule still captures only the CALL shape — but note the parser-version-121
; REVERSAL: the class-level attribute DSL (attr_reader/attr_writer/attr_accessor/attribute/attributes
; — EXACTLY these five; ActiveSupport's cattr_accessor/mattr_accessor/thread_mattr_accessor/
; class_attribute/attr_internal are deliberately not in the family) is no longer "an honest nothing".
; A class-level DSL call — receiver-less, so `obj.attr_reader :x` is still somebody's own method —
; mints Var defs (one per simple_symbol argument, plus the `<x>=` setter for the writer-side macros
; attr_writer/attr_accessor/attribute; attr_reader and the plural `attributes` — third-party DSLs
; measured READERS-ONLY, e.g. AMS/jsonapi-serializer/dry-struct — spell no setter) via the C++ side-
; capture in ingest_names.h, so a write against a defined attribute binds to the `<name>=` def instead
; of dropping. An INLINE-VISIBILITY wrapper (`private attr_reader :x`, Ruby 3 / RuboCop inline) is
; class-DSL position too: the macro evaluates first and the method IS defined, then visibility applies.
; The DSL call itself stays a reference like this one; test/rubyattrscheck.sh pins both sides.
; Disclosed floors of the DSL capture, each pinned by an arm: a `begin`- or modifier-`if`-guarded call
; and the do-block BODY of an `included`/`class_methods` (ActiveSupport::Concern), of
; `Struct.new`/`Class.new`/`Module.new`, or a non-modifier `if … then … end` block are NOT unwrapped to
; class position; and only `simple_symbol` arguments define — a quoted (`:"x"`/`:'x'`), string, or
; splat/`%i[]` argument stays an honest nothing. All of these define real methods at runtime; the
; silence is stated, never silent. Also a floor: accessors inside `class << Registry` (another object's
; singleton class) define nothing, since a def on the enclosing class would be wrong; `class << self`
; accessors define on the class. `module_function attr_accessor :x` is not a visibility wrapper (it
; raises in a class and in a module) and defines nothing.
(call
  method: (identifier) @name) @reference.call
; Parser version 122 (test/rubyschemacheck.sh), the Rails SCHEMA capture: a file whose tree holds a
; `create_table "x", … do |t| … end` call is a rendered db/schema.rb (content-gated — path plays no
; part), and each `t.<type> "name"` / `t.<type> :name` in the table block mints ONE data-kind def
; (SymKind::Section at Lang::Ruby, see model.h) via the C++ side-capture in ingest_names.h, span = the
; name token — Rails-generated attribute uses (`product.price`) then bind to the column and enter the
; call graph. The four id spellings and `t.timestamps` also name columns (implicit `id` /
; `id: false` / `id: :uuid` / `primary_key: "x"` / created_at+updated_at). The DSL CALLS stay
; references like this one (`string`, `datetime`, `create_table` remain external). Stated floors:
; `t.index`/`references`/`belongs_to`/`polymorphic` name no column; duplicate columns across tables
; stay SEPARATE defs (`id` on N tables -> defs="N"); `where("price > ?")` fragments stay opaque. A
; MIGRATION never contributes: a class-wrapped create_table (string- or symbol-named) is refused by
; the class/module-nest gate — the schema is the ONE source of column names; add_column/remove_column/
; change_column are argument data and read nowhere (a column added then dropped never registers).
