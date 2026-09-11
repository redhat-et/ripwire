# Improve ripwire for my language

You have been using ripwire on this codebase — for one session or for months. **Both count, and
the first session counts most.** A returning user's transcript shows where the tool wears thin; a
newcomer's transcript is the only place the first five minutes are ever recorded — the install,
the first command, the first output nobody explained — and that friction is invisible from inside
the project. If this is your first session, the moments *before* your first useful answer are the
evidence, not noise to skip past.

The language this codebase is written in is the subject of this round — call it **LANGUAGE**
below and substitute the real one everywhere. Which binary you have does not matter: `ripwire` on
`PATH` (the installer's) or `./build/ripwire` (a checkout's) — the commands below say `ripwire`;
use whichever you ran.

Your evidence is **this session's own transcript**, not your impressions of the tool. Go back
through it before you write anything. The transcript already exists, so this costs nothing but the
reading.

**Where the result goes:** open an issue at <https://github.com/redhat-et/ripwire/issues> with the
Step 3 report as its body, titled `LANGUAGE: <the one-line finding you rank first>`. That issue is
the destination even if you do not intend to fix anything yourself — a report with its provenance
attached is the form the project runs on, and the maintainers cannot see your code. If you have no
GitHub account, hand the report to whoever pointed you at this file.

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

**If this was your first session, add a fourth list — the first five minutes.** The install line
and what it printed; the first command you ran and whether it was the README's or your own; the
first output and the first thing in it you did not understand; anything the tool asked you to know
that no page had told you. These are the findings a returning user can no longer see.

If the transcript does not support a claim, drop the claim. No remembered grievances.

## Step 2 — localise it to LANGUAGE

For every gap in list 2 and 3, decide which of these it is, and prove it against this tree:

- **Grammar coverage** — a construct in LANGUAGE that produces no symbol. Confirm with
  `ripwire <dir> --grep=<the construct's text>` returning the line but no enclosing symbol,
  or the symbol missing from the map entirely. Name the tree-sitter node kind if you can; quote the
  construct verbatim either way.
- **Symbol kinds** — the construct parses but lands under the wrong kind, or a kind LANGUAGE needs
  does not exist. Check what the map actually emits before you claim it.
- **Call-form resolution** — LANGUAGE's qualified/method/associated call forms producing no edge.
  Check `ambiguous=` and `unresolved=` in the header on a LANGUAGE-heavy directory; a high number
  there is the symptom.
- **Ranking** — the right symbol exists and is reachable but ranks low for a natural task phrasing.
  This one is only real if you can write it as a labeled case: the exact `--for` query, the symbol
  that should have led, and what led instead. That triple is the fix's test; without it the finding
  is an opinion.
- **Legends and disclosure** — the output is correct but does not say what it means for LANGUAGE.
- **First-run friction** (list 4) — not a LANGUAGE gap; keep it as its own section, unlocalised.

The pipeline is `ingest → graph → rank`
([`docs/ARCHITECTURE.md`](https://github.com/redhat-et/ripwire/blob/main/docs/ARCHITECTURE.md) §1);
say which stage each finding belongs to, so the fix lands in the right one.

## Step 3 — write the report and send it

Ordered by (evidence strength × user impact), not by how interesting the gap is. Open with a header
the maintainers can reproduce from: `ripwire --version`, the `<doctor …>` line from
`ripwire <dir> --doctor`, LANGUAGE, and the corpus size as the map's own header states it. Then, per
finding:

- **Finding** — one sentence, with the transcript moment: what you asked, the exact command, what
  came back (paste the relevant output, not a paraphrase).
- **Severity** — HIGH (wrong output a user would act on) / MEDIUM (missing capability) / LOW (polish).
- **Class** — one of the Step 2 kinds, or *discoverability*, or *first-run*.
- **A reproduction the maintainers can run** without your repository: the smallest LANGUAGE snippet
  that shows it, or a public repository and the command. A ranking finding's reproduction is the
  labeled triple above.
- **Siblings** — LANGUAGE is one member of a family. If you know another language has the same
  construct, name it; a fix that lands on one and not its siblings is the dominant defect class here.

Then open the issue (see the top of this file). Paste the report as-is; do not summarise it into an
impression.

## Honesty rules

- **A zero is a measurement; absent is not zero.** If a count cannot be a total it is a floor and
  must be labelled `counts_floor="1"`. Do not "fix" a LANGUAGE gap by making a floor look like a total.
- **A refusal names the flag, the problem, and an example** of the accepted form. A selector that
  matches nothing refuses; it does not answer `0`.
- **Never publish a number without an instrument that pins it.** "Better for LANGUAGE" is not a
  result; a held-out delta on labeled cases is.

## Maintainers only — turning the report into a plan

Everything below assumes a checkout of ripwire itself with `./build/ripwire` built. If that is not
you, you are done at Step 3.

Each report item becomes a plan item carrying:

- **Decided fix shape** — the actual change, named down to the file. Not "improve LANGUAGE support".
- **The gate** — the check that fails today and passes after, by name, in `test/`. A ranking claim's
  gate is a **held-out labeled case in `bench/recalleval/`**, never a hand-inspected top-10.
- **Siblings** — write the gate over the family, not the one language the report came from; see
  `docs/METHODOLOGY.md` §3.

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
