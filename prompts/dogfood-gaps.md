# Dogfood ripwire and log every gap

This is the loop the tool was built with. Do a **real task in this repository** using ripwire as
your only navigation instrument, and treat every moment you reach past it as a product defect.

Build it first:

```bash
cmake -S . -B build && cmake --build build -j
```

## Step 1 — pick a real task

Not a tour, not a toy. Something that genuinely requires understanding code you have not read:
implement a small verb, fix a failing gate, extend a language's call-form resolution, tighten a
refusal. If I gave you a task with this prompt, use that one. Otherwise pick one and tell me which,
in one line, before you start.

## Step 2 — the rule for the whole run

**ripwire is your only navigation tool.** `--for`, `--pack-task`, `--expand`, `--callers`,
`--callees`, `--uses`, `--impact`, `--grep`, `--match`, `--around`, `--path`, `--connect`,
`--affected`, `--situ`, `--exemplar`, `--lego`, `--recall`, `--from-trace` — all of it is fair game,
and `--help` is the authoritative list.

You are allowed to break the rule. You are not allowed to break it silently. **Every fallback is
logged at the moment it happens**, before you take the fallback:

```
FALLBACK #n
  moment:      what I was trying to learn, in one sentence
  tried:       the exact ripwire argv I ran (or: none — I did not think of one)
  got:         what came back, quoted
  fell back to: the exact rg/read command
  why:         the specific reason the verb did not answer it
  class:       capability | discoverability | trust | ergonomics
```

The four classes get four different fixes, so classify honestly:

- **capability** — no verb can answer this question.
- **discoverability** — a verb answers it and you did not find or think of it. This is a `--help`,
  `skills/`, or naming defect, not a missing feature.
- **trust** — the verb answered and you did not believe it, so you read the source to check. Say
  what would have made it credible: a floor label, a legend, provenance, a confidence marker.
- **ergonomics** — it answered, but the shape of the answer cost you more than reading the file
  would have.

Also log the inverse, because it calibrates everything else: **every moment ripwire saved you a
read.** Which verb, what you did not have to open.

## Step 3 — the gaps become the plan

Finish the task. Then turn the fallback log into an ordered plan:

- **Finding** — one sentence, quoting its `FALLBACK #n`.
- **Class and severity** — HIGH if it made you distrust or bypass correct output; MEDIUM for a
  missing capability; LOW for polish.
- **Decided fix shape** — named down to the file. A discoverability finding's fix is usually a help
  line or a skill trigger, not code; say so rather than inventing a feature.
- **The gate** — the check in `test/` that fails today and passes after. A discoverability fix's
  gate can be `--eval-skills=FILE` on a labeled routing TSV; a ranking fix's gate is a held-out
  labeled case in `bench/recalleval/`. Never a hand-inspected top-10.
- **Siblings** — the family the gap belongs to, and whether the other members have it too
  (`docs/METHODOLOGY.md` §3). Gate the family, not the instance.

Rank by how many fallbacks a fix would have prevented, not by how satisfying it is to build.

## Honesty rules

- **A zero is a measurement; absent is not zero.** If a verb answered `0` and you distrusted it,
  that is a **trust** finding about the floor labelling, and the fix is disclosure, not a
  different number.
- **A refusal names the flag, the problem, and an example** of the accepted form. A refusal you
  could not act on is a HIGH finding.
- **Never publish a number without an instrument that pins it.** "This felt faster" is not evidence;
  the fallback count is.
- Do not retrofit the log after the fact. A gap remembered at the end is weaker evidence than a gap
  written down at the moment, and the difference shows.

## Process

If the plan is big enough to need lanes:

- Producer agents in **git worktrees**, one lane each; keep lanes off each other's source files.
- Producers run **their own gates in the foreground** — the full suite is the orchestrator's job.
- **Red first**: prove each new gate fails against the pre-fix binary before trusting it green.
- **Adversarial verifier after every merge wave**, briefed to find it broken; its findings are
  claims, not verdicts.
- Zero unacknowledged `--quality-delta` regressions; `python3 test/pargates.py . ./build/ripwire -j 6`
  green in the foreground; commit per verified item.

**Write the plan, then STOP for my go-ahead.**
