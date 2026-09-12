# tokenaudit — is `est_tokens=` true?

`est_tokens=` is the number `--token-budget` gates on, the number `--max-tokens` fits to, and the number
the tool prints when it says what an answer cost. Until 2026-09-09 nothing in the tree compared it to a
real tokenizer. `test/tokenbudgetcheck.sh` validated its *properties* — present, positive, deterministic,
monotone under a tighter budget, bounded by an allowance derived from the estimate's own constants — and
its own header said the accuracy number "is REPORTED by the agent in the T1 write-up". That write-up was
2026-07. METHODOLOGY §9 principle 6 says measuring gets its own instrument; this directory is it.

Two artifacts, deliberately split by whether they may need a Python package:

| File | Needs tiktoken | What it is |
| --- | --- | --- |
| `sweep.py` | yes | the survey: ~25 invocations × N corpora, est vs real, per verb, plus the legend's share in real tokens |
| `pin.py` | yes | writes `test/estcalib.manifest` — real o200k/cl100k counts on the frozen fixture `test/estcalibfix` |
| `test/tokenbudgetcheck.sh` #18 | **no** | the gate: reads the manifest, holds every pin inside a band and the set's MAPE under a ceiling |

The split is the point. G3 is one deterministic build step with nothing host-installed, so a gate that
imported tiktoken would be a dependency the build contract forbids. The tokenizer runs by hand and writes
numbers; the gate reads numbers. Same shape as `test/printf_parity.manifest`.

The corpus **labels** are what the results JSON records — never a path, never a private tree's name.
`test/ripwirepubliccheck.sh` caught all three leak classes in this directory's first committed results
file; `sweep.py` now writes labels by construction so the gate has nothing to catch.

### Re-pin log — and why a regenerated manifest needs one

`pin.py` rewrites **every** row. A commit that re-pins because one verb's bytes moved therefore also
refreshes any row that had silently drifted since the last regeneration, and its message will, in all good
faith, describe those rows with the reason it had for the one. That has already happened once, so the rows
say it themselves from here on.

| Date | Commit | Rows that moved | Why |
| --- | --- | --- | --- |
| 2026-09-09 | `91fce8ea` | all | first pin (`--expand` at `543 544 454`) |
| 2026-09-11 | `64fa0c2b` | `for-budgeted` 374→420, `expand` 543→541 | for-budgeted: the rung-zero note added 182 B to the budgeted `--for` document. **expand: unrelated — that row had simply been stale since `91fce8ea`.** |
| 2026-09-12 | this branch | `for-budgeted` 420→419 | the rung-zero note's closing clause corrected, one byte shorter |

**The correction on record.** `64fa0c2b`'s message says the re-pin happened because "the pinned tokenizer
counts predated the rung-zero note". True of `for-budgeted`; **false of `expand`**, which moved in the same
commit for an unrelated reason. Measured: `--expand=billableTotal` on `test/estcalibfix` is BYTE-IDENTICAL
between `5b3c0b98` (the commit this branch forked from) and this branch's head — 1 836 B either way,
`est_tokens="455"` on both — and nothing on this branch touches that path. The real counts were 541/542/455
against a pinned 543/544/454, i.e. the row had been stale for 188 `src/` commits. The message is not
amended; history here is fixed forward.

```bash
python3 -m venv /tmp/tokvenv && /tmp/tokvenv/bin/pip install tiktoken
/tmp/tokvenv/bin/python bench/tokenaudit/sweep.py --bin build/ripwire \
    --corpus self=. --corpus other=/path/to/another/tree \
    --out bench/tokenaudit/results/tokenaudit-YYYY-MM-DD.json
/tmp/tokvenv/bin/python bench/tokenaudit/pin.py --bin build/ripwire   # regenerates the manifest
python3 -c "import json,statistics as s; d=json.load(open('bench/tokenaudit/results/tokenaudit-2026-09-09.json'))"
```

## What the 2026-09-09 run measured

`results/tokenaudit-2026-09-09.json`: 25 invocations on this repository and on a 1,500-file private C++
tree, `ripwire 0.5.0 built_from=4c10be9d7`, tiktoken `o200k_base` (and `cl100k_base` beside it — the two
agree to within 1.4% on every row, which is the ≤4% spread `kTokenCalib`'s header claims, re-derived).
No Anthropic `count_tokens` arm: `ANTHROPIC_API_KEY` was not in the environment, so **Claude's own
tokenizer is unmeasured here** and o200k_base remains the public stand-in the table was calibrated against.

**1. `est_tokens=` is printed by 9 of the 25 invocations.** The sixteen that print no price include every
navigation verb — `--callers`, `--callees`, `--impact`, `--uses`, `--affected`, `--edit-check`, `--grep`,
`--test-gate`, `--hotspots`, `--lint`, `--tree`, `--clones` — and both JSON dialects. These are exactly the
answers whose legend share is largest, so the price is missing where it is highest. A `--edit-check` on a
macro with thousands of call sites emitted **348,224 B / 99,006 real tokens in one answer**, priced at
nothing.

**2. The signed error is not centred and is not one-directional.** Per-verb, against o200k:

| verb | this repo | 1500-file C++ tree | fixture pin |
| --- | --- | --- | --- |
| map | +2.8% | +9.8% | +11.3% |
| map `--top-k=10` | +15.9% | +19.0% | +21.4% (`--top-k=5`) |
| `--metrics` | +4.4% | +7.2% | +5.4% |
| `--pack-signatures` | +17.0% | +18.5% | +17.5% |
| `--expand` | +1.9% | **−18.4%** | **−16.4%** |
| `--for` (named) | +26.1% | +35.6% | +33.1% |
| `--for` (conceptual) | +21.9% | +25.5% | — |
| `--pack-task` | +18.9% | +24.6% | +25.2% |
| `--around` | +14.7% | +13.7% | — |

Median +15.9% / +18.5%; MAPE over the eight pins 21%. The mechanism is measured, not guessed: real
bytes-per-token ranges **2.44 (dense signature rows) to 4.66 (legend prose)** across these documents,
while the conversion uses one language-keyed rate near 2.5 for markup and 3.8 for bodies. The error is a
property of the **document shape**, not of the corpus language the rate is keyed on — which is why adding
a language row cannot fix it, and why the `--expand` body rate that is right on large C++ bodies
under-reads by 16–18% on short dense ones.

**3. The legend's price, in the unit the owner mandated.** `--help` states the compact saving in bytes
("at least 50% of a small `--callers`/`--uses`/`--impact`/`--affected` answer") and
`test/legendcostcheck.sh` holds the binary to it in bytes. In **tokens** the same measurement on the
gate's own symbol (`lookupLang`) reads lower on all four, because the legend is prose (4.4 B/tok) and the
rows it is compared against are markup (2.7 B/tok):

| verb | byte saving | token saving | gap |
| --- | --- | --- | --- |
| `--callers` | 70.9% | 60.5% | 10.4 pt |
| `--uses` | 65.8% | 55.2% | 10.6 pt |
| `--impact` | 51.9% | **39.4%** | 12.5 pt |
| `--affected` | 70.1% | 65.8% | 4.3 pt |

`--impact` clears the published 50% floor in bytes and misses it in tokens. Across the whole sweep the
legend's token share ran 3.2% (whole map) to **79.8% (`--callees`)**, with `--edit-check` 62.9% and
`--test-gate` 52.4% on this repository — corroborating the magnitude of the outside evaluation that
started this (callstack/agent-device #2400, "a fixed per-call preamble, 62% of `--callers`' whole
response") while placing `--callers` itself at 42.9%/33.3% on the two corpora here.

**4. `--legend=compact` is not a saving on `--for`.** Measured −0.8% (this repo) and −1.9% (the C++ tree)
at `4c10be9d`: the compact posture emitted *more* tokens, because `--for` is budget-shaped and the bytes the
legend frees are refilled from the trim ladder's tail. Re-measured after the commit that added this
directory, the same two arms read −0.1% and −1.9% — the magnitude moves with the corpus, the direction is
what to carry: a wash or a small loss, never the 39-66% token saving the navigation verbs show. `--help`'s
advice ("MAKING REPEATED CALLS? USE compact") is right for the navigation verbs and wrong-signed for the
bundle it also names as "a little".

**5. What a `--token-budget=N` actually delivers.** Real o200k tokens as a fraction of the requested N,
and the reported `est_tokens` error at that budget:

| verb | N=1500 | N=3000 | N=6000 |
| --- | --- | --- | --- |
| `--for` delivered | 76% / 75% | 74% / 67% | 54% / 48% |
| `--for` est error | +38% / +42% | +25% / +27% | +22% / +26% |
| `--pack-task` delivered | 82% / 81% | 52% / 61% | 58% / 57% |

(this repo / the C++ tree). Part of the shortfall at a large N is content exhaustion — there is no more to
serve — but at the binding budgets the estimate over-reads by a quarter to two fifths, and the budget is a
hard ceiling on the estimate, so a caller asking for 3,000 tokens of context is handed about 2,000.

## What was NOT changed, and why

No constant in `kTokenCalib` moved. The error is per-document-shape and signed both ways: no single rate,
and no per-language row, corrects a +40% on a legend-heavy bundle and a −16% on a short body at the same
time. The change that would is a per-SPAN charge (prose bytes at a prose rate, the way `kBytesPerTokenBody`
already charges body bytes at a body rate) — a behaviour change to a number pinned by goldens,
`fornotesbudgetcheck`, `forbudgetmonotoncheck`, `packtaskquotacheck` and published budget figures. That is
a round, not a lane. What this round leaves behind is the instrument that makes the round's before/after
measurable, and one corrected sentence in `src/serialize.h` — "the number never systematically
under-reads" was false for `--expand` on two corpora and is now the measured range with the gate that
holds it.
