### Changed — quality-delta: a run of calls that shares no callee is an idiom collision, not a copy; range answers say when the files on disk moved on

Duplication rows gain a fifth recognized idiom, `call-sequence`: a body that is only call statements (no return,
declaration, assignment or control flow). Normalized, every such body reads `$I . $I ( … ) ;` repeated, so a
reused two-line helper (`sortUnique`: sort, then erase-unique) gated as a NEW clone of a four-call stream writer
and of a bench wrapper it has nothing in common with. A call-sequence group whose members share no callee or
other identifier (parameter names, `std::` chains and container words aside), sit in different files or scopes,
are under 80 tokens and are not one body with renamed parameters is now reported `sev="minor"` with
`idiom="call-sequence"` instead of gating. A shared callee, one namespace, or a parameter-only rename keeps it
gating. On this repo, tmux and hono the rule demotes no existing clone group; `test/cloneidiomcheck.sh` arm (P)
pins both directions.

`--quality-delta=A..B` now carries `stale_tree="1"` (and a one-line stderr note) when the files on disk are not B's
tree — uncommitted edits, untracked files, or a HEAD whose tree differs from B's (another commit with the same tree is
not stale) — so a green range answer is not read as a
pass for the files on disk. Never gating; `test/qdrefpaircheck.sh` arm (B2).
