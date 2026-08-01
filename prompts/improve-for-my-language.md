# Improve ripwire for my language

You have been using ripwire on this codebase for a while. The language it is written in is the
subject of this round — call it **LANGUAGE** below and substitute the real one everywhere.

Your evidence is **this session's own transcript**, not your impressions of the tool. Go back
through it before you write anything.

## Step 1 — harvest the evidence (transcript only)

Produce three lists. Every row cites the moment it came from: what I asked, which command you ran,
what came back.

1. **Where ripwire answered the question.** Which verb, what it returned, what you did *not* have to
   read because of it.
2. **Where you fell back.** Every `rg`/`grep`, every whole-file read, every "let me just open it and
   look". For each: what you were actually trying to learn, which verb *should* have answered it, and
   why the one you tried did not. A fallback you made out of habit while a verb would have worked is
   a **discoverability** finding, not a capability finding — label it as such, they get different fixes.
3. **Where the output was right but unreadable or untrusted.** A count you could not interpret, a
   legend you had to guess at, a refusal you could not act on, a rank you did not believe.

If the transcript does not support a claim, drop the claim. No remembered grievances.

## Step 2 — localise it to LANGUAGE

For every gap in list 2 and 3, decide which of these it is, and prove it against this tree:

- **Grammar coverage** — a construct in LANGUAGE that produces no symbol. Confirm with
  `./build/ripwire <dir> --grep=<the construct's text>` returning the line but no enclosing symbol,
  or the symbol missing from the map entirely. Name the tree-sitter node kind.
- **Symbol kinds** — the construct parses but lands under the wrong kind, or a kind LANGUAGE needs
  does not exist. Check what the map actually emits before you claim it.
- **Call-form resolution** — LANGUAGE's qualified/method/associated call forms producing no edge.
  Check `ambiguous=` and `unresolved=` in the header on a LANGUAGE-heavy directory; a high number
  there is the symptom.
- **Ranking** — the right symbol exists and is reachable but ranks low for a natural task phrasing.
  This one is only real if you can write it as a labeled case (see below).
- **Legends and disclosure** — the output is correct but does not say what it means for LANGUAGE.

Read `docs/ARCHITECTURE.md` §1 (`ingest → graph → rank`) before you assign any of these, so the fix
lands in the right stage of the pipeline.

## Step 3 — write the plan

Ordered by (evidence strength × user impact), not by how interesting the fix is. Each item carries:

- **Finding** — one sentence, with the transcript moment.
- **Severity** — HIGH (wrong output a user would act on) / MEDIUM (missing capability) / LOW (polish).
- **Decided fix shape** — the actual change, named down to the file. Not "improve LANGUAGE support".
- **The gate** — the check that fails today and passes after, by name, in `test/`. A ranking claim's
  gate is a **held-out labeled case in `bench/recalleval/`**, never a hand-inspected top-10.
- **Siblings** — LANGUAGE is one member of a family. Which other languages have the same gap? A
  fix that lands on one and not its siblings is the dominant defect class here; see
  `docs/METHODOLOGY.md` §3. Write the gate over the family.

## Honesty rules

- **A zero is a measurement; absent is not zero.** If a count cannot be a total it is a floor and
  must be labelled `counts_floor="1"`. Do not "fix" a LANGUAGE gap by making a floor look like a total.
- **A refusal names the flag, the problem, and an example** of the accepted form. A selector that
  matches nothing refuses; it does not answer `0`.
- **Never publish a number without an instrument that pins it.** "Better for LANGUAGE" is not a
  result; a held-out delta on labeled cases is.

## Process

Then run the plan as an **orchestrator**, matching task to model: cheap models for mechanical
enumeration and fixture writing, your strongest for resolver and ranking work.

- Producer agents work in **git worktrees**, one lane each; keep lanes off each other's source files.
- Each producer runs **its own gates in the foreground** — the full suite is the orchestrator's job.
- **Red first**: prove a new gate fails against the pre-fix binary before you trust it green.
- An **adversarial verifier** runs after every merge wave, briefed to find the wave broken. Its
  findings are claims, not verdicts — a measurement that refutes it wins.
- `./build/ripwire . --quality-delta` clean before any lane reports done; zero unacknowledged
  regressions.
- Full suite in the foreground: `python3 test/pargates.py . ./build/ripwire -j 6`. Commit per
  verified item, gate name in the message.

**Write the plan, then STOP for my go-ahead.**
