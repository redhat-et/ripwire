### Fixed — a committed filename can no longer be read as commit metadata (`git log` framing) (#433, thanks @pt-act)

Every `git log --name-only` consumer in the history miners framed its stream with a line-based reader and a
`__C__` marker matched as a line prefix, so a repository containing a file whose name begins with the marker
bytes had that file read as commit metadata. Measured on a hostile fixture (files named `__C__`,
`__C__x|1694000000.cpp`, `__C__ 1694000000.cpp`, `a<LF>b.cpp`, `q"uote.cpp`, `sp ace.cpp`, `back\slash.cpp`,
`pi|pe.cpp`, `--dashdash.cpp`): `--owners` analysed 8 of 11 files, five of them owned by an author email that
appears in no commit, one file's top owner flipped to a different real author, and the newline-named file lost
its churn entirely.

One reader now parses the stream for all five consumers (`gitLogFileSets`, `gitLogNameOnlyRaw`,
`gitFileCommitCountsInDayWindow`, `gitLogDecayedFileMining`, `gitFileAuthors`):
`git log -z --name-only --format=%x00__C__%x00%ae%x00%at%x00%ct`, with the marker a whole-field sentinel a path
can never spell and one field of lookahead so a merge's prefix empty is not mistaken for a record boundary.
Any POSIX-legal filename — newlines, quotes, backslashes, pipes, leading dashes, the marker itself —
round-trips byte-exact, and ownership answers with the author, never the committer. On trees with ordinary
names the answers are byte-identical to before, pinned by a golden recorded from the pre-change binary over
`--owners`, `--hotspots` and `--cochange`.

The history-walk cache's `kQChurnCacheScheme` moves 3 → 4: a blob written by a pre-lane binary holds the old
reader's stream, which for the repositories this fix targets is the corrupted one, and no key component can
tell that blob from a fresh read. Every repository's history is walked once more after the upgrade; on trees
with ordinary names the walk produces the same stream, so the cost is one cold walk and no changed answer.

**The walkers' stop contract rides the field read.** The line readers this replaces checked the abandon flag
before every line; the first cut of the field reader checked it only between fields, so a stream whose fields
never arrive — a git answering in its default format, or a shim streaming bare lines — held the read inside one
unterminated field until end-of-stream instead of stopping at the next unit. The flag is now polled once per
byte, and the memory-guard fixture that measures it refuses in about a second where the narrowed read blocked
for the whole stream.

**One case is disclosed, not fixed:** a merge whose FIRST combined path is a file literally named `__C__`
still reads as pathless — its prefix empty is followed by the marker-spelled path, which the boundary rule
cannot tell from a real record boundary, so that merge's files lose their attribution. Its next three paths
are read as a phantom record's email and epochs (which never parse, so ownership skips it); a fifth and later
combined path rides that phantom at epoch 0, which the co-change sets count as one more commit and
`--rank-by=churn-decay` weights as if it were HEAD's. The full fix is a format sentinel change, owned by a
follow-on spec. `test/gitframingcheck.sh` pins both the fix and this collision's exact observable, including
where the two churn miners disagree by design.
