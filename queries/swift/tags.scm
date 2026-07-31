; ctxpack Swift tags — for alex-pinkus/tree-sitter-swift (node types verified vs node-types.json).
; Definitions + @reference.call (the stock tree-sitter-swift tags.scm ships definitions only).

; ---- definitions ----
(function_declaration name: (simple_identifier) @name) @definition.function
(protocol_function_declaration name: (simple_identifier) @name) @definition.method   ; a protocol's contract methods
(class_declaration name: (type_identifier) @name) @definition.class                  ; class / struct / enum / actor / extension
(protocol_declaration name: (type_identifier) @name) @definition.interface           ; the Lego socket
(property_declaration name: (pattern) @name) @definition.var

; init / subscript / deinit — the members whose "name" is a keyword, not an identifier (mirrors C++
; ctors / operator[] / dtor, which ARE captured). tree-sitter-swift models each as a *_declaration node
; with NO name field; the `init`/`subscript`/`deinit` keyword is an anonymous token. Capture that token
; as @name (exactly like the C++ (operator_cast) @name pattern) so the symbol name is `init`/`subscript`/
; `deinit`. Applies to CONCRETE members AND protocol requirements (a protocol's `init(...)` / `subscript`
; requirement parses to the same node), matching how protocol_function_declaration is captured above.
(init_declaration      "init"      @name) @definition.method
(subscript_declaration "subscript" @name) @definition.method
(deinit_declaration    "deinit"    @name) @definition.method

; ---- references (calls): foo()  and  a.b() ----
(call_expression (simple_identifier) @name) @reference.call
(call_expression
  (navigation_expression suffix: (navigation_suffix suffix: (simple_identifier) @name))) @reference.call
