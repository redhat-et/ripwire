# r6 feasibility probe — run before pre-registration, not after rejection

**2026-08-06.** Three rounds (`r1_anchorhop`, `r1cpp_anchorhop`, `r4_siblift`) have been rejected at
±0.00pp attacking the multi-file stratum. Each cost a full grid to learn that its mechanism could not
move the @10 frontier. This probe exists so a fourth round has to clear a cheaper bar first: **does
the mechanism have anything to walk to?**

## What r6 would be

Structural expansion seeded from a **confirmed top-ranked gold file** — materially different from the
rejected rounds, which seeded from *mention anchors* (guesses about what the query named) or chose a
neighbour by score (`r4_siblift`, whose post-mortem blamed exactly that chooser). Here the seed is a
file the ranker already placed in the top 10, and the walk follows structural edges.

## Why the round is worth registering at all

Round 4's held-out failures decompose sharply. Of 22 multi-file failures:

| root cause | n | reachable by |
| --- | --- | --- |
| sibling ranked but too low (median rank 26) | 9 | reranking (r5 pooling) |
| **sibling indexed but scores ~zero on the query** | **7** | **structural expansion — this round** |
| whole instance missed (primary at rank 39, 70) | 4 | neither |
| symbol-less gold (`.md`/`.json`) | 3 files | candidate-source gap |

The mechanism behind the 7: a sibling is a file that changed *because* the primary changed. The
primary carries the issue's vocabulary; the siblings carry the consequences and often contain none of
the issue's words. A query-driven ranker has no signal for them — which is also why the multi-file
observed rate (21.4%) is only **0.30×** what independence at the single-file rate (90.6%) would
predict. The failures are correlated, and this is the correlation.

## The probe

`r6_probe.py`, over the 7 target instances in `targets.json`. For each gold file it asks the weakest
question any expansion mechanism needs to answer yes to: **is this file's module name present in the
text of a peer gold file?** (an import, a qualified call, an attribute path).

## Result

**28 of 40 gold files (70%) are named inside a peer gold file.** The edge is there for most targets.

The 12 that are not visible form a coherent group — `setup.py`, `config_default.json`,
`config_microscopy.json`, an examples script, `estimator_checks.py`. Peripheral files that no
structural walk from source will reach; they belong to the candidate-source gap, not to this round.

## What this result does NOT license

Three reasons 70% is an **upper bound**, all of which must be carried into the pre-registration rather
than discovered afterwards:

1. **The test is permissive.** "Module name appears in text" is far weaker than "a resolvable
   import/call edge exists in ripwire's own graph". `sancus-compiler` mixes `.py`, `.c` and `.h`, and
   cross-language edges are only drawn on real include/import/FFI evidence.
2. **It tests reachability from ANY peer gold file, not from the one actually found.** A sibling named
   only by another *missed* sibling is unreachable by a walk that starts at the primary. Tightening
   this needs per-gold-file ranks, which the arm JSON does not currently store — worth adding before
   r6 runs.
3. **n = 7 instances, 40 files.**

Realistic expectation: expansion reaches **3–5** of the 7, not 7. Combined with r5 pooling's ceiling
of 9, the two mechanisms address at most ~14 of the 22 multi-file failures and realistically fewer.
That is still the largest available move, and it is nothing like the naive "58.3% → 73%" that the raw
near-miss count suggests.

**Verdict: register r6.** Not because it is likely to be large, but because for the first time in four
attempts on this stratum the mechanism has a verified edge to walk, and the probe that established
that cost one script instead of one grid.
