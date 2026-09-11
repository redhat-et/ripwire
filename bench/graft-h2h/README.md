# Head-to-head vs Graft — the harness

Runs `prompts/head-to-head.md` against trailhq/Graft 0.17.0 on the Round C instrument, unchanged. The
registration, both runs, the loss buckets and the check axis are in `docs/EVALS.md`
("Head-to-head vs Graft (trailhq/Graft 0.17.0) — REGISTERED, RUN, LOSSES CONVERTED TO CODE, RE-RUN (2026-09-07)").

| file | what it is |
| --- | --- |
| `arms_graft.py` | the two Graft columns. The verb map was FROZEN from `graft --help` before any score existed: `graft-ask` is the question verbatim on every shape; `graft-expert` is the verb an expert picks per shape from the help text alone. |
| `run_graft.py` | pairs every arm per question on `../roundc-h2h/questions.json`, alternates arm order by qid parity, runs the placebo last at ripwire-warm's emitted bytes, scores everything through `../roundc-h2h/scorer.py`. `OUT=results_post.json` for a re-run. |
| `check_axis.py` | the CHECK axis: a worktree at `c~1` with the SOURCE half of `c`'s diff applied uncommitted; `graft blast` vs `ripwire --situ` and `--test-gate`; gold = the tests `c` itself touched (not in the diff). |
| `readout.py` | per-arm totals, the three-way paired verdicts (win / tie / loss with mutually-incomplete rows as ties), per-shape completions, losses listed first. |
| `results.json` | the pre-fix run (ripwire `5726d4d9`). Its floor column is nondeterministic — see below — and is not quoted. |
| `results_post.json` | the post-fix run (ripwire `f139025e`), foreign columns re-run and byte-identical to the first run on 30/30. |
| `rerun_ripwire.py`, `results_post2.json` | lane 2 (the tail fix, ripwire `9273f346`): ripwire cold/warm and the placebo re-run on the frozen 30, the foreign columns carried from `results_post.json` unchanged. |
| `results_check_pre.json`, `results_check.json` | the check axis before and after. |

The raw per-arm outputs are written to `raw/`, `raw_results_post/` and `raw_check*/` and are NOT tracked:
ripwire echoes `root=` and the scratch path carries a session id.

## Re-running it

`RW_H2H_HOME=<scratch tree> RIPWIRE_BIN=<ripwire> RW_H2H_RG=<rg> python3 run_graft.py`. The scratch tree holds
`corpus/rocksdb` (ripwire, the floor, the placebo) and `corpus-graft/rocksdb` (Graft alone — its build appends
to the corpus `.gitignore` and writes `.ignore`), both worktrees at `0e2801ac30b3f283c3b14e523ba3667eca024f09`;
`run/senv.sh` (an `env -i` launcher with an allowlist and `DO_NOT_TRACK=1`); and `../bin/graft`, a wrapper over
Graft's `dist/cli.js` built from source (`npm ci --ignore-scripts`, then the tree-sitter native bindings
rebuilt one package at a time — a zsh `for` over an unquoted list does not split).

Three things a re-run must keep:

1. **`rg --sort path`** — Round C's README already required it and the committed `arms.py` lacked it; the floor
   moved on 4 of 30 rows between two otherwise identical runs. Fixed in `../roundc-h2h/arms.py`.
2. **Graft gets its own worktree of the corpus.** Nothing else may read that tree.
3. **Measure last.** The post-fix run was taken after the tree settled; a change to ripwire after it means
   another full run, not a patched column.
