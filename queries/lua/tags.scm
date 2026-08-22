; ripwire Lua tags — written for ripwire (.lua). Derived from the upstream
; tree-sitter-grammars/tree-sitter-lua v0.5.0 node-types.json and verified against real parses
; (test/luafix + the lua/busted shape-recall run).
;
; Lua has no `class` and no `import`. Everything a module exports is a VALUE stored in a table, so the
; five definition shapes below are the five spellings the language actually uses for "here is a named
; function", and they are the whole of the OOP-ish structure a call graph can see:
;   1. function f( .. )              — a free (global or local) function
;   2. function M.f( .. )            — a module-table function, the dominant library idiom
;   3. function M:f( .. )            — a METHOD (implicit `self`), the dominant object idiom
;   4. M.f = function( .. ) end      — the assignment spelling of 2
;   5. { f = function( .. ) end }    — the table-constructor spelling of 2 (the `return { … }` module)
;
; Calls: `f()`, `M.f()` and `M:f()` are all `function_call` with a `name:` field; the captured name is
; the final identifier, which is what byName resolves on.
;
; Deliberately NOT captured (noise): plain variable assignments, table fields whose value is not a
; function, `local` declarations of non-functions, and loop/closure locals.
;
; Deliberately NOT captured (CANNOT be, and it is disclosed rather than faked) — the honest floor:
;   - METATABLES. `setmetatable( obj, { __index = Base } )` is Lua's entire inheritance mechanism, and
;     it is an ordinary runtime function call over an ordinary table. There is no syntax to read, so
;     ripwire emits NO inheritance edge for Lua: `--lego` and --uses role="extends" are empty on a Lua
;     corpus. A zero there means "none found", never "none exists" — the house rule, stated out loud.
;     `Base.__index = Base` likewise mints nothing.
;   - Dispatch through a variable: `local fn = M.f; fn()` calls `fn`, and `obj[ key ]()` names nothing
;     at all. Both produce no resolvable edge.
;   - The IIFE module idiom: `local shorten = (function() … end)()`. Shape 4 below declines it, and
;     correctly so — the assignment's value node is a `parenthesized_expression`, not a
;     `function_definition`, and what the call actually binds is that expression's RETURN value, which
;     no static reading of the text can name. MEASURED, not predicted: found on plenary.nvim's
;     `lua/plenary/path.lua`, which defines `shorten` and `_get_parent` this way. It degrades honestly
;     rather than guessing — `--uses=_get_parent` reports `defs="0" external="1" count="2"`, i.e. "two
;     use-sites, no definition found here", never a wrong definition.
;   - `require "mod"` is NOT an import directive — Lua has no import syntax; require is an ordinary
;     global function. It is therefore captured by the plain call pattern below (exactly as Ruby's
;     `require` is), NOT by ingest.cpp::captureIncludes, and Lua is correspondingly absent from
;     lintrules.h's dependencyCapable set: a Lua file is never a node in the --deps/--arch graph.

; ---- definitions ----

; function f( .. ) end   /   local function f( .. ) end
(function_declaration
  name: (identifier) @name) @definition.function

; function M.f( .. ) end — the module-table function; the FIELD is the name calls resolve to
(function_declaration
  name: (dot_index_expression
    field: (identifier) @name)) @definition.function

; function M:f( .. ) end — colon syntax, an implicit-`self` method
(function_declaration
  name: (method_index_expression
    method: (identifier) @name)) @definition.method

; f = function( .. ) end   /   local f = function( .. ) end
; The two leading anchors are load-bearing: they pin the pattern to the FIRST name and the FIRST value
; of a multiple assignment, so `a, b = 1, function() end` cannot bind the function's def to `a`.
(assignment_statement
  (variable_list
    .
    name: (identifier) @name)
  (expression_list
    .
    value: (function_definition))) @definition.function

; M.f = function( .. ) end — the assignment spelling of a module-table function
(assignment_statement
  (variable_list
    .
    name: (dot_index_expression
      field: (identifier) @name))
  (expression_list
    .
    value: (function_definition))) @definition.function

; { f = function( .. ) end } — the `return { f = … }` module shape
(table_constructor
  (field
    name: (identifier) @name
    value: (function_definition))) @definition.function

; ---- references (calls) ----
; f( .. ), M.f( .. ) and M:f( .. ) — one node kind, three name shapes.
(function_call
  name: [
    (identifier) @name
    (dot_index_expression
      field: (identifier) @name)
    (method_index_expression
      method: (identifier) @name)
  ]) @reference.call
