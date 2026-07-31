# test/ — the gate suite

Every `test/*check.sh` is a self-contained gate: it builds its own fixture (usually a sandbox
tree, and its own throwaway git repo when it needs history), runs the binary named by
`$CTXPACK_BIN`, and exits non-zero with a `FAIL` line naming what broke.

Run them all in parallel:

```bash
python3 test/pargates.py . ./build/ctxpack -j 6
```

`test/regression.sh` is the sequential driver and holds the canonical gate list;
`test/pargates.py` discovers `test/*.sh` from disk instead.

## Deliberate secret-shaped literals (do not "fix")

`--redact` scrubs credential-shaped strings out of emitted bodies. Proving that requires
credential-shaped strings to exist in a corpus, so these files contain **synthetic, non-functional
secrets on purpose**:

- `test/redactfix/creds.cpp`
- `test/redactfix/deploy_notes.md`
- the inline heredoc fixtures inside `test/redactcheck.sh`, `test/jsonredactcheck.sh`,
  `test/mcpredactcheck.sh`, `test/bodydialectcheck.sh` and `test/w3fixlegendcheck.sh`
- the documentation examples in `src/redact.h` (e.g. AWS's own published
  `AKIAIOSFODNN7EXAMPLE` placeholder)

None of them is or ever was a live credential; they are shape-matched placeholders. The public
scrub gate `test/ripwirepubliccheck.sh` exempts exactly these paths and fails on a
credential-shaped literal found anywhere else.
