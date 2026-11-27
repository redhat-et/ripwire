### Added — the large-repo phase balance, measured, and `bench/largescale.py`, the harness that re-derives it

Every phase table in
`bench/PROFILE.md` was taken on a 1,560–1,849-file corpus, and one of its rows is actively misleading
at scale: `resolve refs + build CSR`, published at **~1% of cold**, is **61.8% of cold wall clock** on
llvm-project (80,576 indexed files / 1,399,098 symbols / 4,013,203 edges) — and single-threaded, while
the parse pool beside it uses every core. `bench/largescale.py` is the harness: one verb, one mode,
a ladder of corpora, headline wall clock and peak RSS from the plain binary (`ru_maxrss` via
`os.wait4`), phase shares from a `-DRIPWIRE_PROFILE=ON` build, and per-phase log-log slopes against
both file and symbol counts so a density difference between repos cannot be read as a complexity
defect. Over the language-matched pair envoy → llvm-project, `ingest` is **linear** in files (slope
1.00) and `buildGraph` is **not** (1.54 in files, 1.46 in symbols, 1.16 in edges); its per-reference
resolve loop is 1.71 / 1.62 / 1.29. Two readings are corrected rather than added to: the warm path no
longer rebuilds the graph at any size measured, llvm-project included — the warm snapshot's graph
section serves 80,576 files — and the crawl replay's apparently super-linear cost is the **operating
system**, not ripwire: a standalone 8-thread `lstat` floor over the same trees costs 0.43 µs/path on
kubernetes and 1.56 µs/path on llvm-project, so the replay sits within 1.44x of a floor it cannot beat
without doing fewer stats. `test/largescalecheck.sh` gates the harness's two silent-failure modes —
that its counts pattern reads the map's **unquoted** `files=`/`symbols=` comment (and that the quoted
spelling really does find nothing), and that its warm `reparsed=` column discriminates instead of
reading 0 on every arm.
