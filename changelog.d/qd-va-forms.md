### Changed — `defect="vacuous-assert"` reads a test script's exit-status dataflow, not a grep prefilter

The vacuous-assert facet now runs on a C++ port of the exit-status matcher in `test/lib/exitstatus.py`
(`src/shstatus.h`; `test/gateexitcheck.sh` H4 holds the two equal on 9,144 calls). It reports an assertion that
passes on an empty text (an absence `grep`, `[ -z ]`, a `cmp`/`diff`/`=` parity) when the text was read off a run
whose status nothing checks: a capture, a pipe without `pipefail`, a redirected file, a dropped wrapper status, a FAIL
reporter inside `$( )` or an unread `rc=$?`. Every test script is read (the `grep` prefilter is gone). Recall is 8 of
11 on this project's own fix commits (it was 0), with 0 new rows on a forward replay of the same files. The row stays
`sev="minor"`. The quality snapshot scheme moves to 35 (later members of the same release take it to 38).
