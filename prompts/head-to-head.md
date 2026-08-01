# Head-to-head — measure ripwire against a baseline, honestly

Pick a competitor and beat it, or find out you do not. The point of this loop is not a marketing
table; it is the **loss buckets**. Where the baseline won is the finding, and it is the part that
tells you what to build next.

`bench/headtohead/` holds the last run of this: `bench/headtohead/REPORT.md` (methodology, versions,
the win/loss matrix, per-instance loss buckets), `bench/headtohead/paired_table.md`, and the
machine-readable results. Read it before you design yours — matching its shape makes the two
comparable.

## Step 1 — decide the arms

- **ripwire** — state the exact invocation and the **cache state**. Warm-with-a-prebuilt-index and
  cold-per-run are different tools; a comparison that mixes them is not a comparison.
- **the baseline** — either a competing context/retrieval tool, or **bare grep plus whole-file
  reads**, which is the honest floor and the thing most users actually do. Pin its version or commit.

Both arms answer the **same questions** against the **same repository** at the **same commit**, with
the **same gold** and the **same metric code**. If the metric is implemented twice it will disagree
with itself; implement it once and call it from both arms.

## Step 2 — the questions

N real questions, chosen **before** you run either arm. Write them down first — a question set
selected after seeing the results is not evidence.

Real means: the kind of thing someone actually asks mid-task. "Where is the retry logic", "who calls
this and would break if I change it", "which tests cover this file", "how does a request reach the
database". Not "find the function named `foo`", which every tool wins.

State N. State how the questions were chosen. State every exclusion and why — the target is **zero
exclusions**, and an excluded instance is a finding about the metric, not a free win.

## Step 3 — measure two things

1. **Tokens to correct answer.** Total bytes of context consumed before the correct answer was
   reachable, per arm, per question. Count what the arm actually emitted, not what it could have
   emitted with better flags. Define "correct" by the gold, before the run.
2. **Wall time.** Median and spread, cache state named next to every figure. Report the multiple if
   you want, but report the cache states in the same sentence — otherwise the multiple is a lie of
   omission even when every number in it is true.

Pair the results per question (same question, both arms) rather than comparing aggregates. Paired
tables survive scrutiny; averaged ones do not.

## Step 4 — publish the losses first

For every question the baseline won or tied:

- **bucket it** — wrong ranking, missing edge (dynamic dispatch, callback, macro), question shape
  the verb does not serve, output the reader could not act on, or the baseline is simply better here;
- **quote the output** both arms produced;
- **re-run it** to confirm it is reproducible and not a cache or ordering artifact;
- say what would fix it, or say that nothing should — some losses are the honest shape of the tool.

Then publish the table. Wins after losses, in the same document.

## Honesty rules

- **Never publish a number without an instrument that pins it.** Every figure names the command, the
  corpus, the commit, N, and the cache state. A number nobody can re-run is not a result.
- **A zero is a measurement; absent is not zero.** A verb returning nothing on a question is a
  measurement of that verb on that question — but a count of `0` from a call-graph verb is a floor,
  and scoring it as "the tool says there are none" is a metric bug on your side.
- **No metric shopping.** Choose the metric before the run and report it whether or not it flatters
  the tool. If you compute more than one, report all of them.
- **Say what the comparison does NOT show.** Different cache states, one corpus, one language, N too
  small — write the limits next to the table, the way `docs/EVALS.md` §7 and §8 do.
- If ripwire loses overall, that is the result. Publish it and plan from it.

## Step 5 — land it

The table and the loss buckets go into `docs/EVALS.md` with their instrument, corpus and pinning
file, alongside the existing entries. Numbers in `README.md` may only quote what `docs/EVALS.md`
pins. If a figure has no gate, gate it or drop it.

## Process

- Arms in **separate git worktrees** so neither can contaminate the other's cache or index.
- Run the harness in the **foreground**; never end a turn waiting on a backgrounded measurement.
- **Adversarial verifier after the run**, briefed to break the comparison: unequal cache states,
  post-hoc question selection, a metric implemented twice, an exclusion that quietly favours one arm.
  Its findings are claims, not verdicts — a re-run that refutes it wins.
- `python3 test/pargates.py . ./build/ripwire -j 6` green in the foreground before you publish;
  commit the raw results and the writeup separately.

**Write the plan — arms, questions, metrics, exclusions — then STOP for my go-ahead.**
