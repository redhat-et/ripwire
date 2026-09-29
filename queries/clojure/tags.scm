; A defining list has a symbolic head followed by a symbolic declared name.
; ingest_clojure.h classifies the head and excludes quote/discard contexts.
(list_lit
  [(comment) (dis_expr)]* .
  value: (sym_lit name: (sym_name) @clojure.head)
  [(comment) (dis_expr)]* .
  value: (sym_lit name: (sym_name) @name)) @definition.clojure

; Only symbolic list heads can be direct calls. Special forms and declaration
; heads are excluded by the Clojure capture filter.
(list_lit
  [(comment) (dis_expr)]* .
  value: (sym_lit name: (sym_name) @name)) @reference.call
