# unrescalleesfix — the callees answer's `<unres>` line (test/unrescalleescheck.sh)

A call whose name IS defined in this tree but that kept no edge and no decline record (resolve disposition Unresolved or
QualifiedExternal) was silent on `--callees`: no row, no `<dc>`, only the corpus-wide `graph_unresolved=` gauge.

- `c/run.c` — `run` calls `local_c` (bound), `py_only` (defined only in `py/tool.py`: every definition is another language's,
  so the call is Unresolved), `strlen` (defined nowhere in the tree: never listed) and `shared` twice (two same-language
  definitions in other directories: a tier-3 decline, a `<dc>` row, never `<unres>`).
- `c/leaf.c` — `quiet` calls only `local_c`: no `<unres>` line, no legend clause (0 bytes).
- `py/tool.py`, `d1/shared.c`, `d2/shared.c` — the definitions above.
- `rs/` — `load` calls `api::read_key()`, a re-export the written qualifier rules out (or binds; the gate reads which).
