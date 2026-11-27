### Added — per-verb and per-request `PROFILE_SCOPE`s: the largest per-query cost is no longer one unlabelled bucket

`main.cpp`'s `main: query + emit (the verb, after the graph)` scope carried a comment saying "the
verbs' own scopes nest inside it". For the `--for` family that was aspirational: `runForLens`,
`runForVerbRoute` and `runPackTask` had no scopes of their own, so the scope nested nothing. Measured
on a warm llvm-project `--for`, that one bucket reads **2,920 ms**, of which the already-instrumented
ranking (398) and BM25 (207) account for ~605 — leaving **~2.3 s, the largest per-query term in the
whole profile, bigger than the ranking**, with no label on it. The four handler calls the large-repo
profile actually lands in are now bracketed (`runForVerbRoute`, `runForLens`, `runPackTask`,
`runDefaultMap`), which answers *which* handler owns the time; on libzmq `runForLens` is 48.02 ms of
the 48.10 ms bucket, so it is essentially the whole of it. Four seams and not all ~50 on purpose.

Separately and more importantly for agents: **the MCP server has its own dispatch and never enters
`dispatchMainBody`**, so the path an agent session actually uses had no per-call timer at all — which
is how a per-query cost came to be read off a one-invocation cold row. `dispatchMcpLine`
(`src/mcp.h`), the single request-handling path both the stdio loop and the HTTP server route
through, now carries one scope, so `calls=` separates a session's per-request cost from the ingest
and `buildGraph` it pays once.

Zero-cost-off is verified rather than asserted: with the markers added, the default build's output is
**byte-identical** to the pre-change binary on four arms (flagless map and `--for`, on two corpora),
and it emits no profiler text on either stream. `test/verbscopecheck.sh` gates placement in the
source, that contract in the binary, and — when a `-DRIPWIRE_PROFILE=ON` tree exists — that the
scopes actually fire with `calls>=1`, skipping that arm with a reason when it does not. Its arm B is
the control that keeps the placement check from being vacuous: a seam deliberately left
uninstrumented must be reported uninstrumented by the same matcher.
