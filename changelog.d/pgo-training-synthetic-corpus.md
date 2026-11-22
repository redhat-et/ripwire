### Changed — PGO training covers more of ripwire without diluting its hot paths

`scripts/pgobuild.sh` trained six verbs on this checkout, though its comment spoke of two corpora. Training is now two
groups written to separate raw profiles and merged weighted: a CORE group (the original runs, unchanged, weight 4 —
`RIPWIRE_PGO_CORE_WEIGHT`) and a COVERAGE group (weight 1): page 2 of a paged map, `--lint`, `--clones`, `--expand`,
`--grep` and `--for` by name and by path on this checkout, plus the full verb list on a synthetic tree that
`scripts/pgocorpus.py` writes at build time (seeded, deterministic, standard library only: namespaces sharing the class
names `Base`/`Impl`/`A`/`B`, deep namesake inheritance, overloads, call-result chains, and one slice of each other
language family). A training run that exits non-zero on this checkout now fails the build.
`scripts/pgobuild.sh --check-training BIN` runs the same list without building; `optremarkscheck` uses it to prove every
listed verb runs, the core group is exactly the original runs, the generator writes the same bytes twice, and no
benchmark corpus is named. Output bytes are unchanged: PGO changes speed, never an answer.
