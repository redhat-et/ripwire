# cppbench — the first C++ localization-quality number

All of ctxpack's public localization evidence so far (`bench/locbench/`) is **Python-only** — Loc-Bench
and SWE-bench-Lite are both Python benchmarks. C++ is the language this project's own house style is
built around, so a Python-only scoreboard is an honest gap. `run_cppbench.py` closes it with a benchmark
built the same way LocBench works, but from a **real C++ repo's own commit history** instead of a
curated public dataset.

## What it measures

Each instance = one real commit from [**SFML**](https://github.com/SFML/SFML) (Simple and Fast
Multimedia Library — a public, zlib-licensed, multi-module C++ game/multimedia framework: windowing,
graphics, audio, network, system), mined at the pinned commit `a91a7f6a888a4636493107c33d4faec96bdc1509`
(2026-05-29, `master`): **query** = the commit message, **gold** = the `.cpp`/`.h`/`.mm` files (and,
where derivable from `git diff`'s built-in C-family function-context hunk headers, the functions) that
commit touched. The harness, per instance:

1. **archive the repo AT THE PARENT commit** (`git archive <parent-sha> | tar -x` into a scratch dir —
   never the commit itself, so the fix the message describes is not yet visible to the localizer, and
   never `git worktree`/`checkout`/`clone` against the source repo's own `.git`, which stays strictly
   read-only);
2. run ctxpack as the localizer in three arms — `--for` (shipping default, incl. the B8 query-mention
   anchor), `--for --no-mention-boost` (the anchor switched off), `--query` (pure lexical BM25, no lens
   framing);
3. **parse** the flat ranked `--format=candidates` export;
4. **score** strict file@1/3/5/10 (ALL gold files within the top-k of one flat rank — LocAgent's
   definition, arXiv 2503.09089 §4.1), lenient any-gold-within-top-10, and first-hit MRR.

Deterministic given `(dataset.lock, ctxpack binary)`: no LLM, no RNG, frozen instance order, and every
arm run is verified byte-identical twice before it is scored (zero-silent-skip contract — an archive,
index, or ctxpack failure aborts loudly rather than dropping an instance).

## Why SFML (corpus selection)

Evaluated three candidate public C++ corpora by running the harness's own mining filter over each
repo's full history (`git log --all`, all branches, no cherry-picking) and comparing yield toward the
120-instance cap:

| corpus | commits scanned to fill cap=120 | density | why not / why |
|---|---|---|---|
| [fmt](https://github.com/fmtlib/fmt) | 623 (19.3%) | mostly single-header, narrow diffs | smaller module surface, fewer multi-file commits |
| [EnTT](https://github.com/skypjack/entt) | 2420 (5.0%) | header-only ECS, template-heavy | lowest density by far — 20× the scan just to fill the cap, mostly single-file/short-message commits |
| **SFML** (chosen) | 518 (**23.2%**) | multi-module (window/graphics/audio/network/system), descriptive bugfix-style messages | highest density AND the closest structural match to the original private corpus's multi-subsystem, multi-file commit shape |

SFML wins on both axes that matter here: it needs the *fewest* commits scanned per eligible instance
(best signal density), and its module boundaries (graphics vs. audio vs. network vs. window) produce
the same kind of cross-file, subsystem-scoped diffs the original dataset had — the header-only libraries
(fmt, EnTT) skew toward single-file template changes, a poor match for a multi-file localization task.

## Honest caveats (the losses with the wins)

- **Commit-message queries are easier than issue reports.** A commit message is written by the person
  who *already fixed the bug*, after the fact — it routinely names the exact files/functions/knobs
  touched. A LocBench-style issue is written by someone who does **not** yet know the fix. These numbers
  are optimistic relative to LocBench's and are **not directly comparable** to the Python scoreboard in
  `bench/locbench/README.md` — different query distribution, different gold granularity, different repo.
- **Single repo, single project's commit-message culture.** All 120 instances are SFML — one project's
  style (concise, often prefixed `Fixed`/`Added`/`Changed`, occasionally pasting a compiler error or
  issue number). The direction (which arm wins) is informative; the absolute magnitude is not a portable
  C++ constant, and is not expected to match a differently-styled codebase.
- **Gold is scoped to `.cpp`/`.h`/`.mm`** — a changed `.frag`/`.vert`/`.md`/asset file in the same commit
  is not gold (ctxpack does not index those as ranked symbols, and neither did LocBench's non-Python
  skip). Renamed files count under their OLD path (the one present at the parent commit); newly ADDED
  files are excluded from gold, mirroring LocBench's `added_functions` exclusion — both are structurally
  absent from the indexed parent tree, an automatic miss for **any** static localizer, not a ctxpack
  weakness.
- **Function-level gold is best-effort.** It comes from `git diff`'s built-in C/ObjC hunk-header function
  context (no LLM, no heuristic beyond git's own xfuncname patterns) and is recorded per instance in the
  JSON output for future work, but is **not** part of the scored metrics here (file-level only) — hunk
  context is frequently empty (top-of-file changes, pure data/flag edits) or coarse, so treating it as a
  strict function-level score would overstate precision this harness cannot back up. `gold_funcs` counts
  are visible per-instance in `bench/cppbench/results/sfml.json` for anyone who wants to build on it.
- **Mining excludes, not runtime skips.** Of 526 SFML commits scanned (newest-first, `git log --all`,
  deduped by sha): 0 merges/root, 5 reverts, 289 short-message, 110 outside the 1..5 `.cpp/.h/.mm`
  gold-file-count window, 0 format-only (`git diff -w` empty), 2 embedding a contributor's own local
  home-directory path (compiler-error pastes carrying the account name — excluded so the shipped
  dataset never ships a third-party username) — leaving exactly the 120-commit cap. These are dataset-*construction*
  choices (mandated by the task spec plus the local-path hygiene rule, not tuned to flatter the score),
  counted in `dataset.lock`'s `mining_stats`, and distinct from the **zero** runtime skips during scoring
  proper.

## Arms

| arm | invocation | what it is |
|---|---|---|
| `for` | `ctxpack <repo> --for="<commit message>"` | shipping default task lens, incl. the B8 mention anchor |
| `for-no-mention` | `ctxpack <repo> --for="<commit message>" --no-mention-boost` | ablation: anchor OFF |
| `query` | `ctxpack <repo> --query="<commit message>"` | pure lexical BM25, no lens framing |

The mention anchor (`test/mentioncheck.sh`) lifts a file/module/`Scope.symbol` literally NAMED in the
query text — commit messages that say "fix X in `Window/WindowImplX11.cpp`" or name a knob defined in a
specific file are exactly its shape, so this ablation isolates how much of the C++ number the anchor
buys over the same lens with it switched off.

## Dataset (`dataset.lock`)

Deterministic mining, frozen by a canonical `content_sha256` over `(sha, parent, gold_files)` — a second
run **trusts** the lock file (self-consistency check against a hand-edit or corruption) rather than
re-mining, unless `--refresh-dataset` is passed. Selection rule (spec-mandated, plus the local-path
hygiene exclusion added for public release):

- `git log --all --no-merges` over the source repo (every branch, not just HEAD — a large project has
  many active feature branches; HEAD alone sees a thin slice of the eligible commit population), newest-
  first, deduped by sha;
- single-parent (no merges, no root), not a revert (`^Revert `/`This reverts commit`);
- commit message ≥ 8 words after stripping ticket-id-shaped tokens (`FOO-123`, `#123`);
- 1..5 changed `.cpp`/`.h`/`.mm` files that **exist at the parent** (added files excluded — see caveats);
- not format-only (`git diff -w --shortstat` empty across the gold fileset);
- message does not embed a contributor's own local home-directory path (an absolute macOS `Users` /
  Linux `home` / Windows `C:\Users` path — a common compiler-error/backtrace copy-paste artifact that
  carries the account name);
- capped at 120.

`dataset.lock`'s `source_repo` field records the corpus's public URL (provenance only — `git archive`
needs a real local clone, so `--source-repo` must always point at one on disk; see **How to run** below).

## Archive-at-parent checkout (read-only on the source repo)

`git archive <parent-sha>` piped straight into `tar -x` in a scratch dir — never `git worktree` /
`checkout` / `clone` against the source repo's own `.git`. Archives are cached by parent sha — many
sibling commits share a parent — with LRU eviction bounded to `--archive-cache-cap` (default 8)
concurrently-extracted trees, so scratch disk use stays bounded regardless of instance count. A
`.ctxpack_extract_complete` marker is written only after `tar` exits 0; a cached dir without it (a
previous run killed mid-extract) is discarded and re-extracted rather than silently indexed as a partial
tree. Index caches are keyed by parent sha, so an interrupted run resumes without repeating finished
parse work.

## How to run

```sh
# one-command reproduction: clone SFML at the pinned commit and run the shipped dataset.lock against it
git clone --filter=blob:none https://github.com/SFML/SFML.git /tmp/sfml-corpus && \
    git -C /tmp/sfml-corpus checkout a91a7f6a888a4636493107c33d4faec96bdc1509 && \
    CTXPACK=./build/ctxpack python3 bench/cppbench/run_cppbench.py \
        --source-repo /tmp/sfml-corpus --work-dir /tmp/cppbench \
        --json-out bench/cppbench/results/sfml.json \
        --scoreboard-out bench/cppbench/results/sfml_scoreboard.md

# smoke gate — ctxpack's OWN repo, 3-commit slice, no dependency on any external clone
bash test/cppbenchcheck.sh

# build a DIFFERENT eval on a different corpus entirely
python3 bench/cppbench/run_cppbench.py --source-repo /path/to/any/git/repo \
    --work-dir /tmp/cppbench-other --dataset-lock /tmp/other.lock --refresh-dataset \
    --json-out /tmp/other-results.json
```

`--source-repo` has **no default** and must always be a local clone on disk (`git archive` cannot run
against a bare URL) — pass it every time, including when reusing the shipped `dataset.lock` (whose own
`source_repo` field is provenance, not a live path).

## Results — SFML, n=120 mined / 115 scored, `--all`-branch mining (2026-07-22)

5 instances had **no indexable gold file** (their gold files are absent from ctxpack's ranked universe
at that parent — e.g. platform-specific sources outside the indexed set) and are excluded with a printed
per-instance reason at run time; the other 115 scored with **zero** silent skips and every arm run
verified byte-identical twice.

| arm | file@1 | file@3 | file@5 | file@10 | any@10 | MRR | wall/inst (warm) |
|---|---|---|---|---|---|---|---|
| `for` (shipping default) | 7.0% | 14.8% | 20.0% | 31.3% | 45.2% | 0.219 | 0.78s |
| `for --no-mention-boost` | 7.0% | 14.8% | 20.0% | 31.3% | 45.2% | 0.219 | 0.23s |
| `query` (BM25 baseline) | 7.0% | 14.8% | 20.0% | 31.3% | 45.2% | 0.219 | 0.26s |

Strict@10 by gold-set size (identical across all three arms): **single-file (n=72) 47.2%**, multi-file
(n=43) 7.0%. Whole run: 718.9s wall over 120 instances (~6.0s/instance including one cold index build
per unique parent tree; the per-arm warm localizer call is the 0.23–0.78s column).

**Honest reading (the losses with the wins):**

- **The public C++ number: strict file@10 31.3%, any@10 45.2%, first-hit MRR 0.22.** Single-file
  localization lands roughly half the time in the top ten; strict multi-file localization (ALL 2–5 gold
  files in the top 10) is the hard case at 7.0% — the same single-vs-multi cliff the Python LocBench
  run shows, steeper here.
- **All three arms are IDENTICAL at file granularity on this corpus.** SFML's commit messages are
  short, conventional (`Fixed X`, `Added Y`), and rarely name file paths — so the B8 mention anchor has
  nothing to anchor (+0.0pp everywhere, only a wall-clock cost), and the `--for` lens's framing adds
  nothing over plain BM25 on queries this terse. Same negative as on the previous (private) corpus,
  now via the opposite mechanism: that corpus's messages named too *many* files, this one's name too
  *few*. Either way, post-hoc commit messages are not the query shape where the lens or the anchor
  earn their keep — that remains issue-style prose (Python LocBench: lens ≫ query, ~4.5× lenient;
  anchor +4.9pp held-out).
- **These numbers are materially lower than the previous private-corpus run** (any@10 45.2% vs ~89%,
  MRR 0.22 vs 0.62). The mechanism is visible in the queries: that corpus's messages were long,
  identifier-dense, post-hoc technical notes (an easy retrieval shape); SFML's are terse
  changelog-style summaries whose vocabulary often barely overlaps the code. A benchmark that got
  *easier-looking* numbers from a *harder-to-publish* corpus was exactly the kind of non-portable
  claim the caveats section warned about — the public number is the honest baseline going forward.
- **Not comparable to `bench/locbench/` numbers** (post-hoc queries, single repo, file-level-only
  gold) — see the caveats above.

Reproduce: see the one-command block above. Per-instance rows (including derived `gold_funcs`) are in
`bench/cppbench/results/sfml.json`; the frozen instance list is `bench/cppbench/dataset.lock`.
