# Sibling sweep — find the members the fix never reached

**When a fix lands on one member of a family, it almost never lands on the siblings.** A count is
marked as a floor on one verb and not on the other four. A refusal gets a did-you-mean on one
selector and not the other six. A paging vocabulary reaches nineteen verbs and misses six. An MCP
verb renders differently from its CLI sibling.

None of those is a bug in the fix. Each is a bug in its *scope*. This is the highest-yield habit in
this project, it is cheap to run, and it hits almost every time. Background: `docs/METHODOLOGY.md` §3.

Build first:

```bash
cmake -S . -B build && cmake --build build -j
```

## Step 1 — pick the mechanisms

Anything the output **discloses** is a mechanism with a family. Start from what a user can see, not
from the code:

- **Floors and units** — `counts_floor="1"`, `amb=`, `ambiguous=`, `unresolved=`, and the per-verb
  statement of what is being counted (call **sites** versus caller/callee **pairs**).
- **Paging and caps** — `--limit`, `--offset`, `--top-k`, `--pack-top-n`, and the disclosure
  vocabulary `total=` / `shown=` / `capped=` / `truncated=`.
- **Budgets** — `--token-budget`, `--max-tokens`, `--pack-budget-bytes`, and `over_ceiling=1`.
- **Refusal shapes** — every selector that can name something absent, and its did-you-mean.
- **Redaction** — `--no-redact`, and every surface that emits file content or git identity.
- **Dialects** — `--json` and `--format=` against the default XML for the same run.
- **Provenance and stamps** — the window a git-backed verb reports, cache state, `--doctor`'s claims.

Pick one, or several. One mechanism per lane.

## Step 2 — ENUMERATE the family from SOURCE, not from the docs

This is the step that makes the sweep work, and it is the step people skip. The documentation lists
the members someone remembered; the source lists all of them.

- Find the **emitter or dispatch site** in `src/` — where the attribute is written, where the flag
  is parsed, where the refusal is raised. `src/serialize.h`, `src/cli.h`, `src/mcpverbs.h`,
  `src/selectorrefuse.h`, `src/didyoumean.h`, `src/pageview.h`, `src/redact.h` are the usual homes.
- Enumerate **every call site of that emitter**, and every branch of that dispatch table. Use
  ripwire on itself: `./build/ripwire . --uses=<emitter>` for every read/write site,
  `--callers=<emitter>` for the call edges, `--grep=<attribute string>` for the literal.
- Write the enumeration down as a **checklist with every member named**. Not a sample — the
  enumeration. If you cannot name the members, you have not found the family yet.

Then probe **every member the docs did not name**. Run it. Record what it actually printed. The
members that were never documented are exactly where the fix did not land, which is why the docs
cannot be the source of the list.

Cross the CLI/MCP seam deliberately: for each CLI verb, check its MCP sibling renders the same
mechanism. Divergence there is invisible from either side alone.

## Step 3 — one gate over the WHOLE family

A family-wide gate is worth more than a dozen instance gates, because it fails for the **next**
sibling too, including one that does not exist yet. Write it as a property over the enumeration:

- "every verb that emits a count states its unit"
- "every selector that can miss refuses with a suggestion"
- "every verb that caps discloses what it cut"
- "every CLI verb's MCP sibling emits the same disclosure attributes"

Requirements on the gate itself:

- **Red first.** Run it against the pre-fix binary and watch it go red on the members you found. A
  gate that cannot observe what it asserts is worse than no gate.
- **Presence guard.** Assert the thing you are about to search for actually exists, *then* assert
  the property. A gate whose probe target can vanish goes green while inert.
- **Anchor your counts** — `grep -c '^  PASS'`, not `grep -c PASS`, or a banner line joins the tally.
- Add the new `test/*check.sh` to `test/regression.sh` in the same commit or `test/manifestcheck.sh`
  fails.

## Honesty rules

- **A zero is a measurement; absent is not zero.** The sweep's most common finding is a sibling
  emitting an unlabelled zero a reader will take as "does not exist" — HIGH, every time.
- **A refusal names the flag, the problem, and an example** of the accepted form.
- **Never publish a number without an instrument that pins it** — "N members swept" only counts if
  the enumeration is in the plan and reproducible.

## Process

- One **mechanism per lane**, producer agents in **git worktrees**. Lanes that share `src/` files
  produce conflicts, not throughput — split by mechanism, not by file count.
- Producers run **their own gates in the foreground**; the full suite is the orchestrator's job.
- **Adversarial verifier after every merge wave**, briefed to find the wave broken, and pointed at
  the enumeration specifically: its first question is "which member is missing from this list?"
  Findings are claims, not verdicts.
- Zero unacknowledged `--quality-delta` regressions; `python3 test/pargates.py . ./build/ripwire -j 6`
  green in the foreground; commit per verified family.

**Write the plan — mechanisms, enumerations, family gates — then STOP for my go-ahead.**
