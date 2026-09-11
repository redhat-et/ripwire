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
; not read either; and attr_accessor/attr_writer/attr_reader define nothing in the source TEXT, so
; their generated methods are not symbols and a write against one is an honest nothing, never a
; wrong edge.
(call
  method: (identifier) @name) @reference.call
