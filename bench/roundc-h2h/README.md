# Round C head-to-head — the harness

Runs the comparison pre-registered in `docs/EVALS.md`
("Head-to-head vs gortex / cocoindex-code / codanna — PRE-REGISTERED 2026-09-06"). The result, including
the placebo verdict that stopped it from making a ranking claim, is in that same section.

| file | what it is |
| --- | --- |
| `derive_questions.py` | re-derives the registration's 30 frozen questions and their gold from the corpus by the registered arithmetic. Nothing is hand-written; it reproduces the frozen table exactly (all 30 commits, all 30 `n`, all five eligible/stride pairs). |
| `scorer.py` | **the** metric. One implementation, called from every arm — a metric implemented twice disagrees with itself. Its audit columns are descriptive facts from the same pass, never a second metric. |
| `arms.py` | the arm adapters and the verb map, frozen from each tool's own `--help` **before any score existed**. Third-party arms run through a sanitizing `env -i` launcher. |
| `runner.py` | pairs the arms per question, alternates arm order by question-index parity, runs the placebo last (its budget is what ripwire consumed). |
| `questions.json`, `results.json` | the derived instrument and the recorded run. |

## Re-running it

You need the corpus at the pin (`RocksDB 0e2801ac30b3f283c3b14e523ba3667eca024f09`, 12,938 revisions), the
two foreign arms installed out-of-tree, and their daemons warm. Paths are set at the top of `arms.py`.

Three things a re-run must keep, because each was a defect found the first time:

1. **`rg --sort path`.** Without it the floor arm's score is nondeterministic — ×276 across five identical
   runs was observed. An arm with no single value cannot be published.
2. **A short `TMPDIR`.** macOS caps a unix socket path at 104 bytes; a session-scratchpad `TMPDIR` makes
   gortex's daemon fail to start with `bind: invalid argument`.
3. **`.git/info/exclude`, not the corpus's `.gitignore`.** `ccc init` writes `/.cocoindex_code/` into the
   project *and appends to the tracked `.gitignore`*, which silently changes what every gitignore-aware arm
   indexes. Revert it.
