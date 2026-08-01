# Ranking eval loop — mine real misses, then measure the fix

A ranking change is the easiest kind of change to ship on a hunch and the hardest to be right about,
because a re-ranked top-10 looks plausible either way. This loop makes that impossible: the misses
come from real sessions, the labels are written before the ranker is run, and nothing ships without
a held-out delta.

Read `docs/EVALS.md` §1 (the instruments) and §4 (ranking changes, measured) before you start.

## Step 0 — recalibrate labels, once, at the START

Label drift is real: a case labeled during an earlier loop may have been written against a ranker
that no longer exists. Recalibration happens **only here, at the start**, and every change is
written down with its reason in the same commit. Recalibrating mid-loop — after you have seen the
new ranker's output — is how an eval quietly becomes a transcript of the code.

If nothing needs recalibrating, say so explicitly and move on.

## Step 1 — mine your own sessions for misses

```bash
python3 bench/mine_traces.py --help
```

It mines `(query, gold_files)` pairs from local Claude Code session transcripts: the user's prompt
is the query, the files that task's `Edit`/`Write` calls actually touched are the gold. It tags
sessions that used ripwire itself, so the consumer never grades the tool's own homework as
independent evidence — **keep that separation, and report assisted and unassisted arms separately.**
Score the artifact with `./build/ripwire . --eval-mined=<minedpair.jsonl>` (recall@5/10/20, Acc@k,
MRR per arm). The misses are your candidate cases; a miss is only worth promoting if you can state
what the *right* answer was and why.

## Step 2 — turn misses into labeled cases

The labels live in `bench/recalleval/labels_ranking.tsv` (is the right symbol ranked first?) and
`bench/recalleval/labels_recall.tsv` (is the right document recalled?). Both carry the protocol
statement at the top, and it is the only reason the instrument means anything:

> every gold symbol was chosen by **reading the source** and deciding which symbol IS the on-task
> answer — never by running `--for` and transcribing the current top ranks.

So: read the source, decide the answer, write the row. **Then** run the ranker. An eval whose labels
were harvested from the tool's own output can only ever confirm the tool. These labels are allowed
to say the current ranker is wrong, and they have.

Split discipline: cases you author now are **held-out**. Do not tune against them and then report
them as the result. If you tune, tune on a train split and report the held-out one.

## Step 3 — change the ranker, measure, keep or drop

```bash
python3 bench/recalleval/run_recalleval.py .      # the held-out retrieval eval
./build/ripwire . --eval-retrieval                # known-item retrieval, four rankers, MRR + recall@1/5/10
./build/ripwire . --eval                          # co-change recall vs BM25
python3 bench/locbench/run_locbench.py --help     # localization, frozen public dataset, repo-disjoint split
```

The bars a change must clear, all three, before it can ship:

- **pollution@5** — fixture and generated-path contamination in the top 5. Must not rise.
- **MRR strict** — must not fall.
- **the recall lane** — `bench/recalleval/labels_recall.tsv`. Must not fall.

A change that improves one bar and breaks another has not won; say which trade it makes and let me
decide. A change that moves nothing measurable **does not ship** — record it as a negative result
(`docs/EVALS.md` §7 and §8 are where those live) so nobody re-attempts it in six months.

State the corpus and the N with every number. A delta with no N is not a result.

## Honesty rules

- **Never publish a number without an instrument that pins it.** No "feels better", no
  hand-inspected top-10, no screenshot of a good run.
- **A zero is a measurement; absent is not zero.** A recall of 0 on a case means the gold was not
  returned — check the gold is actually indexed before you call it a ranker miss.
- **A refusal names the flag, the problem, and an example.** If a mined query makes a selector
  refuse, that is a refusal-quality finding, not a ranking finding — file it separately.
- The retrieval evals are **benchmarks, not goldens**: on a live repository the numbers move as
  documents and commits land. The gate suite is the golden. Never pin a benchmark number as a gate.

## Process

- Producer agents in **git worktrees**, one lane each; keep label authoring and ranker changes in
  **separate lanes and separate commits** so a reviewer can check the labels without the diff that
  benefits from them.
- Producers run **their own gates in the foreground**; the full suite is the orchestrator's job.
- **Red first** — a new gate must be shown failing against the pre-change binary.
- **Adversarial verifier after every merge wave**, briefed to find it broken; findings are claims,
  not verdicts, and a measurement that refutes the verifier wins.
- Zero unacknowledged `--quality-delta` regressions; `python3 test/pargates.py . ./build/ripwire -j 6`
  green in the foreground; commit per verified item.

**Write the plan — recalibrations, mined cases, the ranker change, the bars — then STOP for my go-ahead.**
