# Improve the quality panel with the codebase in front of you

You are working in a real repository with ripwire on PATH. That makes you the instrument this
project's own gates cannot build: the gates pin the panel's *mechanics* (determinism, emission
invariants, disclosed floors), but whether the panel's shortlist matches what a maintainer of THIS
code would actually worry about is a judgment call — and you are standing in the one repo where you
can render it. Call your current repo **CORPUS** below and substitute the real path everywhere.

The panel's contract, so you know what you are auditing: it ranks symbols by how many **independent
evidence families** fire on them — `structural`, `lexical`, `confusion`, `historical`, `colocation`,
`state` — it refuses composite scores on principle, and every number it prints is either exact, a
labelled floor, or absent — absent meaning "condition not met", never "unknown". A finding against
any of that is a finding against the product, not against your corpus.

## Step 1 — capture the claims

Build or locate the binary (`ripwire <dir> --doctor` if unsure it is current), then run
`ripwire CORPUS --quality-panel` and `ripwire CORPUS --metrics` and save both raw outputs. Read the
legend line by line before anything else: every attribute you will judge below is defined there, and
a legend line you cannot act on is already a finding (class **b**, Step 5).

## Step 2 — judge the hits, blind

Pick 8–12 rows from the panel spanning its range: the top of the shortlist, rows carrying the
structural nesting profile (`nest=` max beside `humps=` regions and `deep=` lines), a row with high
`nest` but `humps=1`, a small-`loc` row with `deep` a large fraction of the body, a row carrying
`join="deep+untested"`, and a couple flagged by non-structural families only.

For each, **read the body first, metrics covered**. Write one sentence as the maintainer: tangled,
or orderly with one deep spot? Refactor-worthy, or fine as it is? *Then* uncover the row and compare.
Blind order matters — a verdict written after the numbers is anchored on the thing under test.

Score agreement **per family, not per row**. A row can be rightly shortlisted for `confusion` while
its structural story is wrong, and averaging that away is exactly the composite-score mistake the
panel refuses. Note specifically: does `humps`/`deep` separate blocked-sequential from tangled where
`nest=` alone would not? And is a family's credit *inherited* rather than earned — `historical` churn
is measured per FILE, so every symbol in a churny file carries its file's `churn=`/`hrank=` verbatim.
The legend says so; discount accordingly. If you still counted it as the row's own evidence, or the
row does not give you what you need to discount it, that is a finding.

## Step 3 — hunt the misses

Name 3–5 functions in CORPUS that **you** know are traps — the ones you dread touching — that the
panel did *not* shortlist. For each, diagnose which stage lost it: the symbol never extracted
(grammar gap — confirm with a targeted `--grep` of its text), extracted but the relevant metric is
blind to its failure mode (idiom distortion), or measured but under every family's bar (threshold).
The misses are worth more than the hits: hits confirm, misses steer.

## Step 4 — integrity and idiom checks

Sample the whole output, not just your 8–12: profile attributes present exactly when the nesting bar
fires; `deep` never exceeds `loc`; floors labelled as floors. Do **not** assert `deep >= humps` —
`deep` counts LINES and `humps` counts REGIONS, and two regions genuinely share a line in a one-line
`if(c){x;}else{y;}` or anywhere minified, so `deep` below `humps` is correct output there. What IS a
finding is regions on demonstrably DISTINCT lines that only bill one of them; check a specific symbol
before you file it. Then the idioms of CORPUS's language: match/switch arms, callback and promise
chains, comprehensions, guard-clause ladders, error-handling pyramids — for each idiom the panel
flagged or suspiciously spared, one concrete symbol with your verdict. A well-maintained corpus whose
top rows look absurd is signal about the metric; say so plainly.

## Step 5 — write the plan, then stop

Order by evidence strength × user impact. Each item carries its class, because the classes get
different disciplines:

- **(a) emission bug** — invariant violated, wrong body measured. Fix shape named to the file, and
  the gate that fails today, written BEFORE the fix, in `test/`.
- **(b) honesty/disclosure** — output correct but the legend over-claims or under-warns. Cheapest
  class, ship first.
- **(c) metric blind spot** — an idiom scored against the metric's own intent. Design note plus a
  fixture gate; name the sibling languages that share the idiom and write the gate over the family.
- **(d) ranking or threshold change** — anything that moves which rows appear. This class **owes a
  pre-registered calibration round**: your disagreements become held-out labeled cases first, the
  change is measured against them, and it lands or is dropped on that number. No drive-by threshold
  nudges, however obvious they feel.

## Honesty rules

- A hypothesis is not a finding until re-measured. If you cannot reproduce it with a command and a
  symbol name from CORPUS, drop it.
- Your blind verdicts are the ground truth here — never revise one after seeing the numbers. If the
  metric changed your mind, record BOTH opinions; that tension is the datum.
- Do not gerrymander: excluding a directory or file kind to make a number look right is a class (d)
  change and owes the round like any other.
- The panel must stay a set of families that can disagree. If your plan's best idea is a weighted
  blend of them, the plan is wrong.

**End by presenting the plan and stopping for the user's go-ahead. Nothing lands before they approve.**
