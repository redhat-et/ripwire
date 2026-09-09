# Head-to-head vs tgrep — the harness

Runs `prompts/head-to-head.md` against [microsoft/tgrep](https://github.com/microsoft/tgrep) 1.0.5
(`50f5d8f6a54e9e4d16d021954cfcd4e77d342d7b`, built from source with `cargo build --release`), with
`rg` as the floor. The registration, the run, the loss buckets and the verdict are in `docs/EVALS.md`
("Head-to-head vs tgrep (microsoft/tgrep 1.0.5) — index amortisation and hit-set agreement").

**The question this answers, and the question it does not.** ripwire's `--grep`/`--regex` *used to be*
a Zoekt-style trigram index and it was removed on 2026-07-27 (P3): building a per-invocation index
cost 1860 ms / 814 MB on a 2815-file tree and was thrown away after one query, which is strictly more
work than the single scan it replaced. That verdict is about a **per-invocation** index and it still
stands. tgrep's index is **resident** — built once, kept warm by a server, reused across every query
in a session — so it asks a different question: *at what corpus size, and after how many queries,
does a persisted index pay for itself?* The harness answers that with Q\*, not with "index vs scan".

| file | what it is |
| --- | --- |
| `queries.json` | the 16 frozen queries — 8 literals and 8 regexes of declared selectivity — plus the agreement subset and the reason each query is in the set. Frozen before any arm was timed. |
| `arms.py` | the five arm adapters and the frozen verb map, plus the one hit-set extractor each output shape needs. The delivery posture of every arm is part of its definition and is written down there. |
| `run.py` | the ladder driver: per corpus it measures ripwire's cold ingest, tgrep's index build (wall, peak RSS, index bytes), starts `tgrep serve`, waits for `Indexing: complete`, then times every (query, arm) cell. |
| `readout.py` | the tables: one-off costs, per-query medians, Q\*, the agreement matrix, and the in-cache index cost. |
| `results.json` | the recorded run. |

## The arms

| arm | invocation | delivery posture |
| --- | --- | --- |
| `rw-cold` | `ripwire ROOT --grep=…/--regex=…  --grep-in=any`, fresh `TMPDIR` | default 100-hit page |
| `rw-warm` | the same, `TMPDIR` already holding the per-root cache | default 100-hit page |
| `rw-warm-all` | warm + `--limit=1000000` | every hit — the only ripwire arm comparable to `rg`, and the one the agreement matrix reads |
| `tgrep-warm` | `tgrep --index-path IDX --sort path -n --no-heading -H [-F] -e PAT ROOT` against a resident `tgrep serve` | every hit |
| `tgrep-cold` | the same plus `--no-index` — tgrep's own brute-force scanner | every hit |
| `rg` | `rg --sort path -n --no-heading -H [-F] -e PAT ROOT` | every hit |

`tgrep-cold` is the control that separates *the index helps* from *the Rust scanner is faster*; without
it every tgrep win could be attributed to either.

**WARM MEANS THE PARSE, NOT THE TEXT.** ripwire's warm cache restores the tree-sitter symbol graph.
Every file is still read and scanned byte by byte on every `--grep` call — the cache is what `in=`
(the enclosing symbol) is served from, not the hit set. Measured on `go` (15,865 files): cold
1.83 s / 1.27 GB peak, warm 0.51 s — the 1.3 s difference is the parse, and the 0.51 s that remains
is the scan, paid again on every query.

## Re-running it

```bash
RW_H2H_HOME=<scratch> RIPWIRE_BIN=<ripwire> TGREP_BIN=<tgrep> \
RW_H2H_LADDER='{"go":"/path/to/go"}' python3 run.py go
python3 readout.py
```

`RW_H2H_HOME` holds `idx/<corpus>` (tgrep's index), `tmp/<corpus>` (the `TMPDIR` that holds ripwire's
warm cache) and `raw/` (every arm's captured output).

Four things a re-run must keep, because each was a defect found the first time:

1. **`rg --sort path`.** Round C's README already required it; without it the floor arm is
   nondeterministic.
2. **`raw/` lives OUTSIDE the checkout.** An untracked file anywhere in this tree makes
   `git status --porcelain` dirty, and every stamped verb reads that command from any crawl root
   inside the checkout for the `+dirty` half of its `at=` anchor — a `raw/` beside this script would
   flip every determinism arm running in parallel with the harness (the 2026-09-09 gate-isolation
   finding). `RAW_DIR=` overrides it; the default is `$RW_H2H_HOME/raw`.
3. **tgrep gets its own `--index-path` outside the corpus.** Left to itself `tgrep serve` writes
   `.tgrep/` into the tree being measured, which would modify a read-only measurement corpus and
   change what every gitignore-aware arm sees. Verified after the run: `canyonraid48` has no `.tgrep`
   and its `git status` is byte-for-byte what it was before.
4. **The llvm rung's ripwire cells are declared, not silent.** A single ripwire `--regex` run over
   llvm-project's 182,555 files is 3–4 minutes (`[Ee]rror[A-Z][a-zA-Z]+` 2 m 57 s,
   `[Qq]z[Xx]v.*[Jj]w` 3 m 27 s, `[0-9a-f]{8}-[0-9a-f]{4}` 4 m 07 s, and the *literal* `return`
   4 m 31 s warm), where tgrep and rg answer the same queries in under a second. A median of five on
   every ripwire cell there would have cost hours, so on that rung the ripwire arms run `RW_REPS=1`
   over the declared subset `RW_QUERIES=L1,L3,L6,R1,R3,R4`; tgrep and rg run all 16. `results.json`
   records `reps` on every cell and a `skipped` reason on every omitted one. `L2`/`L4` are omitted
   from ripwire's llvm subset for a second reason as well: `--limit=1000000` on `return` over that
   tree emits hundreds of megabytes of XML, which measures the capture harness rather than the tool.

## What the comparison does NOT show

- **One machine, shared.** Every figure was taken on one 18-core macOS arm64 host that was running
  other work at the time (concurrent harvest lanes). Arms were run back to back per query rather than
  interleaved, so contention can bias a single cell. The conclusions here turn on 10×–100× gaps and a
  Q\* that is one to two orders of magnitude below the observed per-session query count, none of
  which a 2× noise factor moves.
- **One `tgrep` server posture.** tgrep was measured with its index already built and its server
  warm — the posture its own README advertises. A cold `tgrep serve` answers from an *empty* index
  and returns nothing until the first build publishes; that failure mode is documented in tgrep's
  AGENTS.md and is not measured here.
- **Text search only.** Neither tgrep nor rg carries a symbol graph, so nothing here says anything
  about what `--grep` is actually for — the `in=` enclosing-symbol chain, the `<enc>` caller counts,
  and the `--handles` edit targets have no counterpart in either baseline. The comparison is
  deliberately narrow: it prices the *scan*, which is the part a resident index would replace.
