# Full audit of ripwire

Audit this repository across five lenses. Run the lenses **in parallel** — they are independent and
they find different things. Every finding carries evidence a stranger can re-run.

Build first, because four of the five lenses need a binary:

```bash
cmake -S . -B build && cmake --build build -j        # no build type: Release blinds the degrade gates
```

## Lens 1 — bugs

Wrong output, crashes, silent truncation, a flag that does not do what `--help` says. Start where
the tool itself says the risk is: `./build/ripwire . --hotspots`, `--lint`, `--clones`, and
`--report`. Then read the code those point at. A bug is only a finding once you have a **reproducer
argv** that shows it.

## Lens 2 — performance (measure, never assume)

No claim in this lens without a timing. Distinguish the two states explicitly, because they differ
by orders of magnitude and conflating them is how a false speed claim gets published:

- **cold** — `--no-cache`, or after deleting the cache the tool reports.
- **warm** — a second run against a live cache.

Run `./build/ripwire . --doctor` first: it states the environment, the cache state and what it
believes about the tree. `bench/perfgate.sh` and `bench/representative_perfgate.sh` are the measurement
harnesses — as of 2026-08-08 (owner directive: perf budgets are not the model — "best tool first, then
make it fast") both run in LEDGER mode: they print medians and append a dated entry to `bench/PROFILE.md`
instead of comparing against a budget and failing. A performance finding in this lens is a measured
number with a `bench/PROFILE.md` entry (or a fresh run) behind it, not a hunch about a slow-feeling verb —
but it is YOUR judgment call whether a number is worth flagging, not a red exit code.

## Lens 3 — skill and verb matching

Does the **right verb fire at the right moment**? Take ten real questions an agent asks mid-task
("who calls this", "is this safe to change", "which tests cover it", "where does this flow go") and
check which verb an agent would actually reach for, given only `--help` and `skills/`. Two failure
shapes to separate: a verb that exists but is never reached (**routing**), and a moment with no verb
at all (**gap**). `--eval-skills=FILE` scores deterministic skill routing against a labeled TSV —
use it rather than judging the routing by eye.

## Lens 4 — tool-use efficiency

**Tokens per answered question.** For each question in lens 3, compare the tokens the ripwire path
costs against the naive path (grep plus whole-file reads) for the *same* correct answer. Count real
bytes from real runs. `docs/EVALS.md` §5 already publishes this for some verbs — including the
counterexamples where a verb costs *more* than it saves. Extend that table; do not contradict it
without an instrument.

## Lens 5 — ecosystem scan

Search for research papers and GitHub repositories doing something this tool should learn from:
repo-map construction, code retrieval and ranking, call-graph resolution, agent context budgeting.

Rank by **momentum, not total stars** — commits and releases in the last few months, issues actually
being closed, a maintainer who is still there. A 30k-star repo last touched two years ago is not a
signal. For each candidate: what it does that ripwire does not, whether the idea transfers to a
zero-dependency deterministic C++ tool, and the cheapest experiment that would confirm or kill it.
An idea with no cheap experiment goes in a "not now, and here is why" list, not into the plan.

## The plan

One comprehensive plan, findings ordered by severity:

- **HIGH** — output a user would act on is wrong, or a published claim is not true.
- **MEDIUM** — missing capability, a measured performance regression, a verb that never fires.
- **LOW** — polish, wording, discoverability.

Each finding: the evidence (argv, timing, transcript line, or link), the decided fix shape named
down to the file, and **the gate** — the check in `test/` that fails today and passes after. A
finding with no gate is not ready to be worked; either write the gate into the plan or move the
finding to an open-questions list.

## Honesty rules

- **A zero is a measurement; absent is not zero.** Counts that cannot be totals are floors and say
  so. Do not close a finding by hiding the floor.
- **Refusals name the flag, the problem, and an example** of the accepted form.
- **Never publish a number without an instrument that pins it.** Every performance and efficiency
  number in the plan names the command that reproduces it.
- Negative results get written down. An idea that measured flat is worth more recorded than deleted;
  `docs/EVALS.md` §7 and §8 are where they live.

## Process

Run the plan as an **orchestrator**, matching task to model: cheap models for enumeration, fixture
authoring and mechanical sweeps; your strongest for resolver, ranking and concurrency work.

- Producer agents in **git worktrees**, one lane each, one source file per lane where possible.
- Producers run **their own gates in the foreground**; the full suite is the orchestrator's job.
- **Red first** — a new gate must be shown failing against the pre-fix binary before it is trusted.
- An **adversarial verifier after every merge wave**, briefed to find the wave broken rather than to
  approve it. Its findings are claims, not verdicts; a measurement that refutes it wins.
- Zero unacknowledged `--quality-delta` regressions before a lane reports done.
- `python3 test/pargates.py . ./build/ripwire -j 6` green in the foreground; commit per verified item.

**Write the plan, then STOP for my go-ahead.**
