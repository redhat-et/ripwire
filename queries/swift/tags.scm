; ripwire Swift tags — for alex-pinkus/tree-sitter-swift (node types verified vs node-types.json).
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

; ---- shapes the 2026-08-04 real-corpus round measured at ~0% (test/swiftshapecheck.sh) ----
; Ground truth: Alamofire @0455bfb + swift-nio @7297328, blanked-scan cross-checked with
; single-capture --match queries.

; enum cases — 247 (Alamofire) + 1 209 (nio) sites, none extracted. One def per NAME (a comma
; list `case a, b` matches once per name); associated/raw values change nothing. Same
; @definition.constant bucket as C++ enumerators; enum_entry exists only in enum bodies, so no
; gate is needed — a switch ARM is a different node entirely.
(enum_entry name: (simple_identifier) @name) @definition.constant

; typealiases — 39 + 962 sites. A nio ChannelHandler's `typealias InboundIn` IS its wire
; contract. Same @definition.type bucket as C++ type_definition.
(typealias_declaration name: (type_identifier) @name) @definition.type
(associatedtype_declaration name: (type_identifier) @name) @definition.type

; protocol property requirements — 12 + 65 sites (nio's Channel alone declares 30+). The
; method requirements were captured (protocol_function_declaration above); the property half of
; the same contract was not. The name: field is the whole (pattern); the identifier is inside.
(protocol_property_declaration name: (pattern (simple_identifier) @name)) @definition.var

; operator functions — 4 + 62 sites, every one a BUILTIN token (`static func == (...)`);
; (custom_operator) alone measured ZERO on both corpora, so the anonymous-token alternation
; carries the real weight. The name: field also binds the return type on this grammar, which is
; why these are explicit tokens rather than a wildcard.
(function_declaration name: [ "==" "!=" "===" "!==" "<" ">" "<=" ">=" "+" "-" "*" "/" "%"
                              "+=" "-=" "*=" "/=" "%=" "&" "|" "^" "<<" ">>" "&&" "||" "??"
                              (custom_operator) ] @name) @definition.function

; ---- references (calls): foo()  and  a.b() ----
(call_expression (simple_identifier) @name) @reference.call
(call_expression
  (navigation_expression suffix: (navigation_suffix suffix: (simple_identifier) @name))) @reference.call
