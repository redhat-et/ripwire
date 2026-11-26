### Changed — `--whereis` skips the call-graph build it never reads

`--whereis` answers from the index (the `@FILE:LINE` seed, HEAD's def sites, the near-miss) and from the repository's refs, a git blob scan. It never read the call graph, but every run that was not served from the warm snapshot built one and threw it away. It now joins `--deps` and `--arch` in the verbs that skip the build when they are the dispatch winner and no modifier reads the graph (`--pin-census`, `--metrics`, `--for`, `--exemplar` and the signature emitters still keep it). The answer is unchanged byte for byte. A run that skips the build stores no graph in the warm snapshot, so the next graph verb builds its own and does not serve an empty one. The MCP `whereis` verb is not changed: it answers from the server's shared index.

MEASURED_LINE

`test/whereisnographcheck.sh` holds the skip: for a class, a free function, a method, a macro, a branch-only function, a name HEAD deleted (`--with-history`), an `@FILE:LINE` seed and a zero, `--whereis` prints no graph phase and the same bytes as a graph-built run; a graph verb, a graph verb that outranks `--whereis`, and `--pin-census` still build; and a warm snapshot written by `--whereis` neither serves an absent graph nor drops a stored one.
