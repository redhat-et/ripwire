; ripwire smali tags — written for ripwire (.smali).
; tree-sitter-smali (tree-sitter-grammars, ABI 14). The tags pass does not evaluate
; #eq? predicates, so an invoke is recognized by shape: an expression whose operand
; is a full_method_signature. That is how this grammar spells invoke-*.
;
; Indexed method names are NOT the bare method_signature. captureTagsFacts prefixes
; the enclosing class, so a definition and an invoke share one spelling:
;   Lcom/example/A;->addOne(I)I
;   Lcom/example/A;-><init>()V
; The '<' in <init>/<clinit> is part of the name. finalSegment is skipped for Smali
; because it would cut the name at that character and collide with the class.
; Whitespace around '->' is not part of the key: the indexer joins the class token and the
; signature token. method_definition has no body field; the body span starts at the first
; named node after method_signature, and a method with none stays bodyless.
;
; Not captured: fields, const-string, switches, annotations, .super, .implements.
; A method reference whose class is not in the corpus stays unresolved.

(class_definition
  (class_directive
    (class_identifier) @name)) @definition.class

(method_definition
  (method_signature) @name) @definition.method

(expression
  (body
    (full_method_signature) @name)) @reference.call
