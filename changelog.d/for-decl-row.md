### Added — `--for` lists a function's prototypes when a signature change is in question

A `--for` task about one C, C++ or Go function's signature (signature, prototype, new argument), or the function's bare name, now carries `<decl_rows>`: its definition and every non-test declaration, including the header prototypes `--defs` folds into the definition's row. Present only when such a declaration exists; capped at 8 rows with `next=--defs=`.
