### Changed — the PGO training workload reaches the paged map, --lint, --clones, --expand and --grep

`scripts/pgobuild.sh` trained with six verbs on this checkout, and its comment spoke of two corpora it did not use.
It now also runs page 2 of a paged map, `--lint`, `--clones`, `--expand` and `--grep`, the comment says exactly what is
trained, and a training run that exits non-zero on this checkout fails the build instead of shipping a profile with a
hole in it. `scripts/pgobuild.sh --check-training BIN` runs the same list without building; `optremarkscheck` uses it
to prove every listed verb runs and exits 0, and that no benchmark corpus is named. Output bytes are unchanged: PGO
changes speed, never an answer.
