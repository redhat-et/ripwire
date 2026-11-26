### Changed — the agent skills' SKILL.md bodies are 14% shorter, with routing unchanged

The 17 shipped skills were rewritten against Anthropic's current Agent Skills guidance. Bodies, which load when a skill triggers, went from 47,243 to 40,466 bytes, and every skill is shorter. Descriptions, which load in every session, went from 5,461 to 5,339 bytes. The 13 reference files over 100 lines gained a contents line (+3,787 bytes in all). No skill was added, removed or renamed. Every command a body spells was run against the binary.

Routing was measured before any edit, on the 282-row labelled corpus `test/skillevalfix/prompts.tsv`, which this round left unchanged:

- Lexical `--eval-skills` `bm25-desc` hit@1: 147 of 214 before and after.
- Blind model raters, given only the descriptions: Haiku 208 and 207 of 214 on two runs before, 208 after. Sonnet 204 and 208 before, 207 after.
- Over two runs per model, pass^2 (rows right in both runs) is unchanged: Haiku 207 of 214, Sonnet 204 of 214. Balanced accuracy, which weighs the 68 negatives equally with the 214 positives, is 0.974–0.986 per run after, against 0.977–0.986 before.
- A stricter variant, with no second person and no cross-skill pointers, was measured against a rule written in advance and rejected. Sonnet fired on 2 negatives in each run, and Haiku's pass^2 fell by 2.

`claude -p` was not signed in on the measuring machine, so the raters were Claude Code subagents pinned to a model. Their context listed the old descriptions, which can only favour the before arm. The method, the packets and every answer file are in `bench/skillrater/results/2026-11-26/`. `bench/skillsize.py` measures the three tiers, and `bench/skillrater/passk.py` scores pass^k and balanced accuracy. `test/skillshapecheck.sh` keeps every body under 500 lines and gives every reference over 100 lines a contents line. Each of those rules is proven to fail on a planted copy.
