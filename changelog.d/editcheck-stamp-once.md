### Changed — `--edit-check` reads the `at=` stamp once per answer

`--edit-check` builds two documents in one call: the verdict-only candidate and the full document. Both carry `at=`, and each read the stamp (`git rev-parse HEAD`, `git status --porcelain`, the shallow probe) for itself. So every answer whose candidate was taken, clean tree or dirty, started a second `git status --porcelain` and two more `rev-parse` children for a value the process already held. The full document now carries the candidate's read, so the stamp's three children run once. Nothing writes to the work tree between the two reads, so the output is byte-identical. The `--dry-run` preview never takes the candidate and already read the stamp once; it is unchanged.

The STAMP record that serves a one-shot `--for` (`ripwire-qstamp-*`, #752) cannot answer the dirty bit and is not used here. The record keys only files in the git directory and the environment. An unstaged edit or a new untracked file changes none of those, so a stored `+dirty` bit would be served stale.

Gate: `test/editcheckstampcheck.sh` counts git children through a PATH shim, for a clean tree, a dirty tree, and a control where the candidate is not taken.
