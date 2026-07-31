; ripwire Bash tags — written for ripwire (.sh/.bash/.zsh). tree-sitter-bash ships no
; upstream tags.scm, so this is derived from the v0.23.3 grammar's node-types, verified
; against an AST dump (see the langcheck fixture).
;
; Bash structure the call graph cares about:
;   - function definitions:  `name() { .. }`  AND  `function name { .. }` — both parse to
;     (function_definition name: (word) ..), so ONE rule covers both spellings.
;   - command invocations:   every `cmd arg..` is (command name: (command_name (word))). We
;     capture the command name as a call reference. Built-ins / external tools (echo, printf,
;     cd, git, ..) resolve to no def and stay edgeless — only a call to a function DEFINED in
;     the same script (or another indexed script) becomes a real <c> call edge. This matches
;     every other language: an unresolved callee is dropped, a resolved one is an edge.
;
; Deliberately NOT captured (noise): local variables, `export VAR=`, expansions. Bash is
; variable-heavy; indexing every assignment would swamp the map with edge-free var nodes.

; ---- definitions ----

; `greet() { .. }` and `function greet { .. }` — both are function_definition name:(word)
(function_definition
  name: (word) @name) @definition.function

; ---- references (calls) ----

(command
  name: (command_name (word) @name)) @reference.call
