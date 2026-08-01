# Command tour — walk a new user through every verb

Take a reader who has never run this tool and walk them through **every** command, live, on this
repository. The tour's value is not the list — `docs/COMMANDS.md` is already the list. It is the
answer to *when do I reach for this instead of grep*, written next to real output.

```bash
cmake -S . -B build && cmake --build build -j        # no build type
./build/ripwire --help                                # the authoritative flag list
```

## Step 1 — the inventory

Take the verbs from `docs/COMMANDS.md`'s contents section, in its family order:

**understand a codebase cold** · **navigate / answer a question** · **zoom the detail ladder** ·
**assess quality / structure** · **self-diagnosis** · **security** · **knobs / modes**

Reconcile that list against `./build/ripwire --help` **before you start writing**. Any verb in one
and not the other is a finding for step 4, and it is the first thing you should look for.

## Step 2 — run each one, for real

For every verb, against this repository:

- **the invocation** — the exact argv, copy-pasteable, no placeholders a reader has to guess at;
- **the real output** — pasted from the run, trimmed with a visible marker if it is long, never
  hand-written to look like output;
- **the question it answered** — one sentence, phrased the way a user would actually ask it;
- **when to reach for it over grep** — the specific moment. This is the sentence the tour exists for,
  so make it concrete: what grep would have cost, what this returned instead. If the honest answer
  is "grep is fine here", write that; a tour that claims every verb beats grep is not usable;
- **what it does NOT tell you** — the limit the binary itself states. Call edges are heuristic and
  name-based, so counts are floors (`counts_floor="1"`); `amb="K"` means the resolver split weight
  across K ambiguous targets. Read a 0 as "none found", never "none exists".

Group knobs with the verbs they shape rather than giving each its own section — `--limit`/`--offset`
belong next to the verbs that page, `--token-budget` next to the bundling verbs, `--json` and
`--format` shown once as dialects.

## Step 3 — pick the delivery form

One of these, chosen for the audience, stated in one line with the reason:

- **Markdown document** — the default. Skimmable, diffable, greppable, and it can live in the repo.
- **Demo script** — a runnable shell script that executes the tour in order with narration. Best for
  a live session. It must exit non-zero if any command fails, so a stale tour cannot pass silently.
- **asciinema plan** — a timed scene list: the commands, the pauses, the on-screen callouts, the
  target runtime. Best for an embedded recording. Write the plan; recording is a separate step.

## Step 4 — file the drift findings

For every verb, three sources should agree: **`--help`**, **its `docs/COMMANDS.md` entry**, and
**what it actually did just now**. Where they disagree, that is a **doc-drift finding** — file it,
do not silently paper over it in the tour.

- `--help` is authoritative. `docs/COMMANDS.md` is generated from it, so a disagreement between
  those two means the document needs regenerating:
  `python3 docs/docs_commands_build.py --bin build/ripwire`, with `--check` as the drift comparison
  that `test/docscommandscheck.sh` runs.
- Live behavior disagreeing with `--help` is a **code or help-text bug**, and it is the highest
  severity of the three. Reproducer argv, expected, actual.
- `./build/ripwire . --doc-drift=<substr>` finds documentation drift inside the corpus; use it on
  the tour text once the tour exists.

Each finding: severity, the three quoted sources, the decided fix, and the gate that would have
caught it.

## Honesty rules

- **A zero is a measurement; absent is not zero.** If a demo command returns `0`, explain which it
  is rather than quietly picking a different example that returns something. A tour built only from
  commands that produce pretty output is an advertisement.
- **A refusal names the flag, the problem, and an example** of the accepted form — so show one
  deliberately. A reader who has seen a refusal can act on the next one.
- **Never publish a number without an instrument that pins it.** Any figure in the narration comes
  from `docs/EVALS.md` with its instrument, or it does not appear.
- Show at least one verb where the output is **larger or slower** than the naive approach, and say
  so. `docs/EVALS.md` §7 lists the real ones.

## Process

- Work in a **git worktree**; keep the tour artifact and any drift fixes in **separate commits**.
- Run every command in the **foreground** and paste what it actually printed.
- **Adversarial verifier before delivery**, briefed to find a command in the tour that does not run
  as written, an output block that was not produced by the command above it, and any verb from
  `--help` that the tour skipped. Its findings are claims, not verdicts.
- `bash test/deckcheck.sh` for fabricated flags in the prose it scans, `bash test/ripwirepubliccheck.sh`
  for leaks, and `python3 test/pargates.py . ./build/ripwire -j 6` green in the foreground.

**Write the plan — inventory, form, the verbs in order, the drift findings you already see — then
STOP for my go-ahead.**
