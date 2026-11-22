### Changed — the PGO training workload covers namesake-heavy C++ and every language family

`scripts/pgobuild.sh` trained on one corpus, this checkout, with six verbs, though its comment spoke of two.
It now also trains on a synthetic tree that `scripts/pgocorpus.py` writes at build time (seeded,
deterministic, standard library only): many namespaces sharing the class names `Base`/`Impl`/`A`/`B`, deep
namesake inheritance, out-of-line members, overloads, call-result chains, local lambdas, and one slice of each
other language family. On both corpora it runs the cold, warm and paged map, `--for` in three shapes,
`--pack-task`, `--lint`, `--expand`, `--grep`, `--clones`, `--callers` and `--impact`, and a training run that
exits non-zero now fails the build instead of shipping a profile with a hole in it.
`scripts/pgobuild.sh --check-training BIN` runs the same list without building; `optremarkscheck` uses it to
prove every listed verb runs on both corpora, that the generator writes the same bytes twice, and that no
benchmark corpus is named. Output bytes are unchanged: PGO changes speed, never an answer.
