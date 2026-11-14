### Changed — a warm `--quality-delta` no longer re-parses every file, and a repeat `A..B` reuses its base

The error-masking and placeholder rows of `--quality-delta` (swallowed exceptions, empty catch and `if err != nil {}`
bodies, `todo!()`, `NotImplementedError`, TODO-only bodies) were found by re-reading and re-parsing every source file
on every call, warm or cold. They are now found in the parse worker from the tree the ingest already built, stored in
each file's cache record, and read back on a warm call. A warm working-tree `--quality-delta` retires 43 % (envoy),
27 % (cockroach) and 69 % (vscode) fewer instructions (median of five interleaved pairs; cycles fall 41 / 28 / 65 %)
with the same answer bytes. The cache format moves to 51 (each file record gains its construct hits, 9 bytes each), so
an older cache is rebuilt once. Only a `--quality-delta` (or `--quality-baseline`) run finds the hits: any other verb
writes its records "constructs absent" and pays nothing: cold `--deps` and the cold default map stay within 0.2 % of
before. The next `--quality-delta` decodes such a record as usual and parses the file for the hits alone, which costs
about what every warm `--quality-delta` used to (1-2 % fewer instructions), and the rewritten record carries them. A cold
working-tree `--quality-delta` retires 17 / 12 / 18 % fewer instructions than before.

The base side of `--quality-delta=A..B` (its Snapshot for the selected kinds and its C-family macro names) is now
stored by base commit sha in a self-checking blob beside the head-snapshot cache, keyed also by the excludes, the
selected kinds, the file-size cap and the build's producer identity. A repeat `A..B` with the same base archives,
parses and scores only the target: a repeat `HEAD~10..HEAD` retires 80 % (envoy), 70 % (cockroach) and 90 % (vscode)
fewer instructions than before both changes, and its peak live heap falls 21 / 19 / 30 %. `--no-cache` neither reads
nor writes the blob; a corrupt or truncated blob is refused with a stderr line and recomputed. On a hit the base
archive's own per-file ingest warnings are not repeated (they name a per-process temporary path, so they were never
byte-stable).

New gates `test/qdconstructscheck.sh` (carried hits equal re-parsed hits cold, warm and uncached, with a premise count
that fails on zero) and `test/qbasecachecheck.sh` (a hit, a miss on a changed key, `--no-cache`, corrupt and truncated
blobs).
