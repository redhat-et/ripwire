; ctxpack Ruby tags — written for ctxpack (.rb). Derived from the upstream
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
; Deliberately NOT captured (noise): instance/local variables, constants, blocks.

; ---- definitions ----

(class
  name: [ (constant) (scope_resolution) ] @name) @definition.class

(module
  name: [ (constant) (scope_resolution) ] @name) @definition.module

; `def greet ... end`  and  `def self.greet ... end` — both are (method name: ..)/(singleton_method)
(method
  name: [ (identifier) (operator) ] @name) @definition.method

(singleton_method
  name: [ (identifier) (operator) ] @name) @definition.method

; ---- references (calls) ----
; `foo(..)`, `obj.foo`, and `require "x"` / `require_relative "y"` are all (call) nodes —
; the method field is the callee name. A def named `foo` in the same (or another indexed)
; file becomes a real <c> edge; unresolved names (require, stdlib) drop, as everywhere else.

(call
  method: (identifier) @name) @reference.call
