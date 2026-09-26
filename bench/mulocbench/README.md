# bench/mulocbench — MULocBench adapter (design written, no harness run yet)

**Read [`docs/research/mulocbench-baseline.md`](../../docs/research/mulocbench-baseline.md) first.**
That document is the design, the pre-registration (verb mapping, metric definitions, eligibility
rules, what we'd report vs withhold), the questions worth putting to the benchmark's authors, and the
owner-run fetch steps. This directory holds only `run_mulocbench.py`, an **untested** skeleton written
against that design, and (once mined) `dataset.lock`.

[MULocBench](https://arxiv.org/abs/2509.25242) (arXiv:2509.25242) is 1,100 issues from 46 Python
projects with non-code gold locations (config, docs, tests, assets — not just functions) — the
distribution `bench/locbench` and `bench/multiswe` structurally cannot score, since both mine gold
from a source-code fix diff.

**Status: no MULocBench data is on this disk, no number exists yet.** `run_mulocbench.py`'s `main()`
refuses to run for exactly that reason (zero-silent-skip contract — an unfinished harness says so
loudly rather than pretending to score). The new pieces relative to `bench/locbench`/`bench/multiswe`
— dataset-native gold extraction (not diff-derived), class-level ranking, and a per-issue F1 scorer —
are written and smoke-compiled against synthetic input, not against a real row.
