### Fixed — `forrootlegendcheck` arm 4 no longer reports a slow MCP call as a dialect drift (#813)

The gate that pins the `root=` legend clause on both `--for` dialects asked the MCP twin for a
whole-repo answer under a 30 s subprocess deadline — a tenth of what every sibling gate that runs
`--mcp` against the repo root allows (`anchorhonestycheck`, `foranchornscheck`,
`forbasenamedefaultcheck`, `impactdepthcheck` all use 300 s). On run 45920074167, leg
`release (macos-26, plain, appleclang, shard 1/4)`, the call ran past that deadline under three
parallel gate workers; the job log records `subprocess.TimeoutExpired … timed out after 30 seconds`.
The uncaught exception exited non-zero, so the arm printed
`MCP for twin is missing the root= legend clause (dialects have drifted)` about a dialect it never
read — the clause was present in both dialects on that very binary, and every other arm, leg and
shard was green.

A cold whole-repo MCP `for` is 2.4–2.6 s on a quiet dev host and about 15 s per whole-repo arm on that
CI leg, so 30 s was never headroom. Two changes, neither of which touches what the arm asserts: the
deadline is now the house 300 s, and a timeout reports itself on its own `FAIL` line instead of being
read as a drift. A genuinely missing clause still fails this arm exactly as before — proved with a
binary shim that deletes the clause from the MCP answer only.
