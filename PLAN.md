# Audit follow-up plan — 2026-08-04

This is the handoff for the next task. The broad audit implementation is complete; this file records the
remaining reviewer decisions, the Codex CLI experiment, and the external release work that could not be
finished in the same context window.

## Verified audit state

- Full gate run before the final documentation/evaluator edits: **338 pass, 1 expected skip, 0 fail**.
- ASan/UBSan, determinism, XML, plugin validation, deck render/visual review, and clang-format passed.
- New cache isolation, honest lint/docdrift behavior, transitive test reachability, skill routing, Codex
  plugin/CLI setup, compile-time `LexPair` memcpy eligibility, and 13 registered gates are implemented.
- Run the full foreground gate again after this handoff's Python/skill/README changes:
  `python3 test/pargates.py . ./build/ripwire -j 6`.

## Codex baseline versus ripwire CLI

The MCP experiment is invalid and must never be quoted. The requested treatment is the CLI.

The corrected harness is `bench/agentloop/run_agentloop.py` schema v2:

- arms: `baseline` and `ripwire_cli`;
- MCP table empty in both arms;
- per-run isolated `CODEX_HOME`; baseline has no skills, treatment gets only this checkout's ripwire skills;
- absolute ripwire binary prepended to `PATH`;
- raw Codex JSONL retained; records include command count, ripwire CLI count, and exact commands;
- task limiting is repository-round-robin; results checkpoint after every call; timeouts retain partial
  command evidence and gold-file localization.

Locked diagnostic: `astropy__astropy-12907`, seed 1. The SWE-bench reference patch changes
`astropy/modeling/separable.py`, replacing `_cstack`'s scalar `1` assignment with the right-hand matrix.
Both arms independently made that exact one-line fix.

| Arm | Gold-file hit | Input tokens | Output tokens | Wall | Commands |
| --- | --- | ---: | ---: | ---: | ---: |
| baseline | yes | 170,567 | 1,856 | 55.99 s | 8 |
| ripwire CLI, globally contaminated skills | yes | 257,007 | 2,661 | 89.47 s | 17 |
| ripwire CLI, isolated + corrected skills | yes | 197,637 | 1,953 | 64.91 s | 8 |

The initial ripwire CLI query immediately ranked the gold file. The large first loss came afterward:
globally installed ctxpack skills forced redundant hotspots/impact/PR/quality passes. Skill fixes removed
about 69% of that token overhead and 74% of that time overhead. The isolated arm remains an easy-task loss
versus grep/read: +15.9% input tokens and +15.9% wall time, with no localization gain.

### Next skill/binary experiments

1. Preserve the new **evidence-sufficiency stop** in `ripwire-find-bug`: when one ranked source read proves
   the defect, do not automatically run hotspots, impact, another skill, or a whole-file read.
2. Preserve the scope guards in `ripwire-change-check` and `ripwire-quality-bar`; a one-line leaf fix is not
   automatically a full merge/quality audit.
3. Reduce the treatment's remaining overhead. Measure separately:
   - skill-body injection/read cost;
   - `--for --max-tokens=4000` output cost versus `--adaptive --detail=1 --max-tokens=2000`;
   - whether a compact bug-localization skill can route directly from the ranked result to a narrow source
     range without losing difficult-task recall.
4. Run the bounded three-repository pilot only after step 3: Astropy, Requests, Xarray; two arms; one seed;
   six calls; projected $2–$9. Treat every loss as ranking, output-shape, skill-policy, missing-feature, or
   genuinely-unnecessary-tool evidence. Do not force a win.
5. Install/verify the official SWE-bench Docker evaluator before claiming solve rate. Current runs support
   localization/token/wall claims only. Then expand seeds and use repository-clustered analysis.
6. Refactor `run_one` before expanding the matrix; current quality-delta correctly reports its growth from
   ccx 12→23 and LOC 79→111.

## Quality-delta reviewer decision

Current run against git HEAD:

`regressions=48 minor=15 acked=0 preexisting-worse=38 new-symbol=10 gating=27`.

Gating rows are 23 short-horizon-churn, two complexity, one nesting, and one verbosity. The real structural
regressions are in the new evaluator work: `run_one` (complexity + verbosity) and `synthetic_fixture`
(complexity + nesting). The 23 churn rows say this audit revisited code changed recently; that is a useful
review signal but not proof those fixes are wrong. The ten new-symbol rows do not gate by design; review the
high-complexity `doctorCacheStats` and `inconsistentReturnLine`, while the `LexPair`/constructor dead-code
rows appear to be parser/model false positives.

Recommendation: **keep quality-delta, do not blanket-ack.** Accept the audited C++ changes only after a
reviewer inspects the churn list; refactor the evaluator's two Python hotspots in a follow-up or explicitly
record that debt. If acknowledgements are needed, use narrow `--ack-only` facets/ids, never bare
`--quality-ack`.

Research comparison: [arXiv:2505.23953](https://arxiv.org/abs/2505.23953) feeds the five most predictive
complexity metrics back only after failed code and iterates at most five times. It reports a 35.71% Pass@1
improvement versus 12.5% for execution-only feedback on one GPT-3.5/HumanEval setting, but agent gains on
BigCodeBench were only marginally above the baseline. Its threats include benchmark generalizability,
top-five SHAP selection, and LLM-generated tests. That supports an itemized, bounded feedback loop; it does
not support rejecting a passing patch solely because one complexity number rose. The repo's
[`quality-metrics.md`](skills/ripwire-quality-bar/quality-metrics.md) correctly weakens complexity to a
size-confounded correlate and trusts coupling/churn more strongly.

## Legacy temporary files

Measured in the macOS `$TMPDIR`: **132,246** direct legacy `ripwire-*` files: 71,908 caches, 60,328 locks,
about **460.4 MiB** total. Deleting them frees that disk space and directory entries/inodes and should make
temp-directory scans/backup/indexing less painful. It does not delete source or committed data. The cost is
that any still-relevant cache has one cold rebuild; deleting a live lock/cache while an old ripwire process
is active can cause duplicate work or a race. Stop ripwire/MCP processes first, then remove only the exact
legacy direct-file pattern. New private/sharded cache data is separate and should not be swept blindly.

## README and release

- README now opens with “Give your coding agent a map before it reads the repo,” a one-command example, and
  a compact measured-results table. “What it answers” remains immediately after Quickstart.
- GitHub topics still need adding, including `openai-codex` and `codex`.
- A local `v0.1.0` tag already points to old commit `c7364de`; do not move/delete it casually. Choose and bump
  the next version before tagging this audit (likely `v0.2.0`, reviewer decision).
- `.github/workflows/release.yml` builds four portable archives: macOS arm64/x64 and Linux arm64/x64, each
  with a SHA-256 file, then attaches them to the GitHub Release. **Do not commit executables to the repo.**
  Release assets belong on the tag's GitHub Release; Git history keeps source/workflows only.
- GitHub CLI authentication was invalid during this task. Re-authenticate, push the branch, add topics,
  push the new tag, watch all four build legs, download the assets, verify checksums and smoke-test at least
  the native archive before calling the release shipped.

## Remaining launch work

- Publish the GitHub topics and verified binary release.
- Re-run the updated Codex CLI pilot and publish honest losses beside wins.
- Turn the final audit into a concise issue/roadmap; then do outreach only after install-from-release works.
- Do not convert more shell gates to C++ without a measured payoff: the sampled shell-launch share was only
  about 0.09–3.1% of relevant gate time.
