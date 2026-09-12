# Codex routing check — operator notes

Give the evaluator only `codex_prompt.md`, unchanged. Do not give it these notes, answer keys, or reference answers. Record the source commit, Codex version/model, installed catalog and description hashes, startup warnings, raw response, and token usage for each fresh turn.

## 1. Install and choose the catalog before running

Use an up-to-date checkout, then choose the treatment explicitly:

```sh
# Normal user catalog: excludes the contributor-only compiler-remark skill.
bash skills/install.sh --codex

# Full catalog for working on Ripwire itself and comparing all 85 positives.
bash skills/install.sh --codex --contributor
```

Run **one** of these commands per treatment. The second includes `ripwire-opt-remarks`; the first deliberately prunes it. The frozen C2 key contains two positives for that skill, so a default install cannot reproduce the full-catalog reference treatment. Do not count those two rows as default-catalog routing failures or silently change the historical key.

Open a fresh Codex session after installation: an existing session may retain its earlier catalog. Record `codex --version` and `ripwire . --doctor --agent=codex`. Check the startup output for the "Skill descriptions were shortened to fit the skills context budget" warning. If it appears, record the other installed skills and the actual treatment before changing any budget setting. Do not tune configuration between turns without labelling the change.

## 2. The blind turn

Paste `bench/skillrater/results/2026-09-07/codex_prompt.md` as one message. It contains 138 prompts (85 labelled positives, 53 negatives), no labels and no descriptions; Codex routes from the catalog it loaded itself. Save the raw TSV response before scoring, for example as `/tmp/answers_codex_default.tsv` or `/tmp/answers_codex_contributor.tsv`. Preserve raw events and stderr when using the CLI so tool calls and truncation warnings can be checked.

Require all 138 unique IDs, exactly three tab-separated columns, and installed skill names or `none`. Missing, duplicate, unknown or malformed rows invalidate the run; the scorer is not a substitute for this format check. The prompt forbids tools and reading skills; record any violation rather than presenting the run as blind.

One turn is roughly 5K tokens of prompt text and 2K output; loaded skills, system instructions and other runtime context add to the actual input. Record measured usage rather than budgeting only the prompt text (the 2026-09-09 live-catalog run used 23,824 input tokens).

## 3. Score against the matching treatment

```sh
# Default catalog: 83 applicable positives and all 53 negatives.
python3 bench/skillrater/score.py \
  bench/skillrater/results/2026-09-07/keys/key_C2.tsv \
  /tmp/answers_codex_default.tsv --exclude-labels=ripwire-opt-remarks

# Contributor catalog: all 85 positives and all 53 negatives.
python3 bench/skillrater/score.py \
  bench/skillrater/results/2026-09-07/keys/key_C2.tsv \
  /tmp/answers_codex_contributor.tsv
```

Keep the full unfiltered default-catalog score as a diagnostic if useful, but label its two unavailable-skill rows. Never compare the 83-positive filtered score directly with an 85-positive historical score.

The frozen full-catalog reference on these 138 prompts is Opus 85/85, Sonnet 84/85, Fable 84/85, all with 0/53 negative fires. The scorer reports hit@1, hit@2 and per-skill results. A default-catalog comparison requires rescoring the historical answer files with the same exclusion. Record model, catalog and context differences alongside comparisons.

After using failures to change descriptions, this packet is a regression set for that work. Use independently prepared prompts for forward validation, freeze labels before evaluation, and do not call score-driven retries held-out evidence.

## 4. Optional old-description comparison

For the pre-round descriptions, create a separate worktree at `c7914e8d`. Install from that worktree, start a fresh session, run the same unchanged prompt and score with `keys/key_A.tsv` (the 18-skill labels). Record exactly which skills were active rather than assuming the old installer supports the current contributor option.

After the comparison, reinstall from the current checkout with the intended default or contributor command from step 1. Confirm doctor/catalog parity again. Record both treatments and their limitations in `docs/EVALS.md`; preserve the historical packet and answer files.
