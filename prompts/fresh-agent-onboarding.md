# Fresh-agent onboarding — hand the tool to someone with zero context

The people this tool has to work for are agents that have never seen it. You cannot learn what they
will do by asking someone who already knows the flags. So run the experiment properly: give a
**zero-context agent** a real task and read its transcript as the finding list.

You are the orchestrator here, not the subject. Do not do the task yourself.

## Step 1 — set up the subject

Build the tool and install what a first-time user would get:

```bash
cmake -S . -B build && cmake --build build -j
./install.sh                 # ripwire onto PATH
skills/install.sh            # the agent skills (symlinks back into skills/)
```

Spawn a **fresh agent** with:

- a real task in a real repository (not this one — a tool's own repo is the easiest corpus it will
  ever face, and the agent can read the source to compensate);
- the tool available, and nothing else about it: no flag cheatsheet, no worked examples, no hints
  from you mid-run;
- an instruction to narrate which command it runs and why, so the transcript is readable.

If you want the MCP path measured too, run a second subject with `ripwire --mcp` wired in and
nothing else changed. Report the two separately — the surfaces are discovered differently.

**Do not coach.** The moment you help, the experiment is over and the transcript stops being
evidence. If the subject stalls, let it stall and write the stall down.

## Step 2 — read the transcript as the finding list

Four buckets. Every row quotes the transcript line.

1. **Found and used correctly** — verb, moment, what it saved.
2. **Found and misused** — it ran the verb and drew the wrong conclusion. This is the most valuable
   bucket, and it is almost always an **output-honesty** defect rather than a discovery one: a floor
   read as a total, a `0` read as "does not exist", `--uses` counts compared against `--callers`
   counts as though they measured the same thing. File these against the output, not the help text.
3. **Never discovered** — a verb that would have answered a question it grepped for instead. The fix
   is `--help` wording, a skill trigger, or a name — decide which, and say why.
4. **Tried and bounced** — it reached for something reasonable that refused, errored, or returned
   something it could not act on. A refusal it could not recover from is HIGH severity.

Add one number: **tokens the subject spent to reach the correct answer**, against a naive
grep-plus-read baseline for the same answer. `docs/EVALS.md` §5 is the existing table; extend it,
and do not contradict it without an instrument.

## Step 3 — fix from evidence, and re-run the naive agent as the gate

Fixes come from buckets 2, 3 and 4 only. Nothing goes in the plan because it seemed like a good
idea while reading.

- **Output fixes** (bucket 2) — a floor label, a unit name, a legend, a disclosure. Gated by a
  family-wide `test/*check.sh`, not a single-verb one.
- **Help and description fixes** (bucket 3) — `--help` is the authoritative flag list and
  `docs/COMMANDS.md` is generated from it, so the help text is the real edit; regenerate the doc
  rather than editing it directly.
- **Skill trigger fixes** (bucket 3) — `skills/*/SKILL.md` descriptions. Gate them with
  `--eval-skills=FILE` on a labeled `prompt<TAB>skill<TAB>provenance` TSV, so routing is scored
  deterministically instead of judged by eye.
- **Refusal fixes** (bucket 4) — the refusal must name the **flag, the problem, and an example** of
  the accepted form, with a did-you-mean from a real edit distance.

**The gate for the round is a re-run with a NEW fresh agent**, same task shape, no memory of the
first: did the buckets move? Report bucket sizes before and after. A fix that does not move a bucket
is a negative result — write it down rather than deleting it.

## Honesty rules

- **A zero is a measurement; absent is not zero.** Bucket 2 exists mostly because this rule was not
  visible enough in the output; keep the fixes on that side.
- **Never publish a number without an instrument that pins it.** "Onboarding is easier now" is not a
  result; a bucket count and a token delta on a re-run are.
- One subject is an anecdote. Say N. If N is 1, label the finding as a lead, not a measurement.

## Process

- Producer agents in **git worktrees**, one lane each; keep help-text, skills and output lanes apart.
- Producers run **their own gates in the foreground**; the full suite is the orchestrator's job.
- **Red first**: prove a new gate fails against the pre-fix binary before trusting it green.
- **Adversarial verifier after every merge wave**, briefed to find it broken; its findings are
  claims, not verdicts.
- Zero unacknowledged `--quality-delta` regressions; `python3 test/pargates.py . ./build/ripwire -j 6`
  green in the foreground; commit per verified item.

**Write the plan — subject setup, task, buckets, fixes, the re-run gate — then STOP for my go-ahead.**
