### Added — the large-repo phase balance, measured, and `bench/largescale.py`, the harness that re-derives it

Every phase table in
`bench/PROFILE.md` was taken on a 1,560–1,849-file corpus, and one of its rows is actively misleading
at scale: `resolve refs + build CSR`, published at **~1% of cold**, is **65.6% of cold wall clock** on
llvm-project (80,576 indexed files / 1,399,098 symbols / 4,013,203 edges) — and single-threaded, while
the parse pool beside it uses every core. `bench/largescale.py` is the harness: one verb, one mode,
a ladder of corpora, headline wall clock and peak RSS from the plain binary (`ru_maxrss` via
`os.wait4`), phase shares from a `-DRIPWIRE_PROFILE=ON` build, and per-phase log-log slopes against
both file and symbol counts so a density difference between repos cannot be read as a complexity
defect. Measured inside a quiet window, medians of 3, every warm cell verified `reparsed=0`: llvm-project
is **33.464 s cold / 3,862 MiB peak RSS** and **0.990 s warm / 1,905 MiB** — so on a 48 GB machine
memory is not the binding constraint at 80k files, a single core is. `buildGraph`'s share of cold
wall runs **6.4% → 65.6%** across eight corpora while PageRank stays **0.1–2.4%** at every size, so
this file's original "the ranking is the cheap part" survives and the line beside it does not. The
super-linearity is stated without a slope fit: the resolve loop costs **3.82 µs per symbol on envoy
and 13.59 on llvm-project** (2.29 → 4.74 per edge), same language, same extractor — it does more
work per reference as the corpus grows. Fitted, over five C-family points: `buildGraph` 1.31 in
files / 1.23 in symbols, resolve loop 1.37 / 1.28, `ingest` 0.74 / 0.69 (sub-linear, because the
cold parse is parallel). Two confounds are named rather than averaged away: a slope fitted across
all eight corpora measures the language mix (kubernetes has 2.0x envoy's files and a *lower*
`buildGraph`), and C is not C++ (cpython has 1.07x envoy's symbols and 0.80x its `buildGraph`). Two readings are corrected rather than added to: the warm path no
longer rebuilds the graph at any size measured, llvm-project included — the warm snapshot's graph
section serves 80,576 files — and the crawl replay's apparently super-linear cost is the **operating
system**, not ripwire: `bench/statfloor.c`, an 8-thread `lstat` floor over the same trees, costs
0.40 µs/path on kubernetes and 0.57 on llvm-project, and the replay's 144.6 ms sits within **1.29x**
of a 112.2 ms floor it cannot beat without doing fewer stats. The first pass at this comparison was
taken under load and said 3.6x and 443.3 ms; the contention landed on the larger tree, which is how
a loaded machine impersonates super-linear growth. The conclusion held and the magnitude was wrong
by 3x, so both figures are recorded. `test/largescalecheck.sh` gates the harness's two silent-failure modes —
that its counts pattern reads the map's **unquoted** `files=`/`symbols=` comment (and that the quoted
spelling really does find nothing), and that its warm `reparsed=` column discriminates instead of
reading 0 on every arm.
