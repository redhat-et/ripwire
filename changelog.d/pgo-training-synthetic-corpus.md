### Changed — a PGO training run that fails now fails the build, and the training list is gated

`scripts/pgobuild.sh` carried on past a training run that exited non-zero, so a renamed symbol or a mistyped flag
silently trained nothing for its verb; on this checkout such a run now fails the build. Its comment spoke of two
corpora it never used and now says exactly what is trained (the list itself is unchanged).
`scripts/pgobuild.sh --check-training BIN` runs the training list without building; `optremarkscheck` uses it to prove
every listed verb runs and exits 0, and that no benchmark corpus is named. Output bytes are unchanged.
