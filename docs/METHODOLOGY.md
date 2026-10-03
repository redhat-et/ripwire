# How this tool is built — a method, not a manifesto

ripwire is a deterministic tool whose output an agent is expected to trust without reading the
source. That is a strong claim, and the only thing that makes it survivable is the process below.
None of it is specific to this codebase; it transfers to anything where the output *looks plausible
whether or not it is correct*.

Three ideas do most of the work: **gate before code**, **capture-audit**, and
**sibling-completeness**.

---

## 1. Write the gate before the code it measures

A ranking, a token estimate, a call graph, and a similarity score all look reasonable when they are
wrong. There is no compiler error, no crash, no visibly bad output. Code-then-test in that setting
does not produce a test — it produces a *transcript* of whatever the code happened to do.

So the order is fixed: decide what the property is, write the check that would catch its absence,
watch it fail, then write the code that makes it pass.

The corollary is what makes it real: **a gate that cannot observe what it asserts is worse than no
gate**, because it reports confidence. Two shapes of that failure have shipped here:

- **Compiled-away observation.** A gate asserting a degrade path asserts on a diagnostic that the
  release build compiles out. For three development cycles every degrade-path gate in CI was green
  because it could not see the thing it checked. The fix was to run the whole suite in *both* build
  flavours — not to write more gates.
- **Vanished probe target.** A gate that anchors on "the most recent commit" goes inert the moment
  the most recent commit is documentation-only: no diff, no rows, nothing to assert, green. The fix
  is a **presence guard** — assert the thing you are about to search for actually exists, *then*
  assert the property.

Both are the same bug: the measurement's precondition was never itself measured. A useful habit is
to periodically **force each gate to fail** and check that it does.

---

## 2. Capture-audit: read your own output as a stranger would

Periodically, run **every** verb, on a real repository, and record the actual output into one
document. Then read that document as an unfamiliar user, and write down every place where the output
is misleading, ambiguous, over-confident, or silently incomplete.

This finds a class of defect that no unit test looks for, because each individual output is *valid*:

- a count that reads like a total but is a floor;
- a `0` that means "not found" and will be read as "does not exist";
- two verbs using the same word for different quantities (call *sites* versus caller/callee *pairs*);
- a truncation with no disclosure;
- a header that names a denominator it does not actually count;
- an estimate presented with the confidence of a measurement.

Every finding becomes a gate, so it cannot come back. The capture itself is then worth keeping and
regenerating: it doubles as the source of the generated command reference and as a harvest of real
command lines for the differential harness.

Two practical rules learned the expensive way:

- **The capture must not pollute retrieval.** A document that quotes every verb and every flag wins
  every lexical query about the tool. Keep it in a directory the crawler skips, and demote
  self-declared generated documents in the ranking.
- **Regenerate against the final binary**, not the one you started the round with, or the capture
  documents behavior that no longer exists.

---

## 3. Sibling-completeness: the dominant defect class

When a fix lands on one member of a family, **it almost never lands on the siblings.**

A count is marked as a floor on `--callers` but not on `--callees`, `--uses` and `--impact`. A
refusal gets a did-you-mean on one selector and not the other five. One language's qualified calls
are resolved precisely and six others keep guessing. A paging vocabulary reaches nineteen verbs and
misses six. An MCP verb renders differently from its CLI sibling.

None of these is a bug in the fix. Each is a bug in its *scope*.

The practice that follows is mechanical, and it is the highest-yield habit in this whole document:

> **After any fix, enumerate the family and check every member.** Not a sample — the enumeration.
> Then write one gate over the *whole family*, not over the instance you fixed.

A family-wide gate — "every verb that emits a count states its unit", "every selector that can miss
refuses with a suggestion", "every language's call forms are exercised by name" — is worth more than
a dozen instance gates, because it fails for the *next* sibling too, including one that does not
exist yet.

The corollary for review: when reviewing a fix, do not ask "is this correct?" Ask **"what are its
siblings, and did they move?"**

---

## 4. Adversarial review, and letting the reviewer be wrong

Work here is reviewed by a reviewer whose explicit job is to find the round *broken* — not to
approve it. That framing matters: a reviewer asked to confirm will confirm.

Two things keep it honest in both directions:

- **The reviewer's findings are claims, not verdicts.** More than once, a reviewer's proposed fix
  shape or factual claim was **refuted by measurement**, and the measurement won. A review that
  cannot be wrong is not a review.
- **The record gets corrected.** When the running ledger of a round turned out to be wrong, it was
  corrected in place rather than quietly re-scoped.

The measurable outcome: in every round where an adversarial review pass ran after a merge, it found
something broken. The pattern is load-bearing, and "the merge looked clean" has never once been
evidence.

---

## 5. Publish the negative results

Two ranking experiments here produced no confirmed lift. They were not deleted and they were not
quietly left on: they are dropped from the help text and refuse to run without an explicit
development environment variable, with their own evaluation records attached.

Likewise the counterexamples: the verb that makes output *larger* on short symbols, the anchor worth
exactly +0.0pp on the wrong corpus, the search verb that costs more tokens than it saves, the ranker
that is excellent at importance and terrible at relatedness. All of them are in `docs/EVALS.md`
because a tool that only publishes its wins has not told you how to use it.

A negative result recorded is worth more than a feature shipped on a hunch — and it is the only
thing that stops the same idea being re-attempted every six months.

**And it must be recorded in the ledger everyone reads, in the same commit as the result.** A
verdict that lives only in a results directory is a verdict that drifts: this repo once left a
held-out REJECT in `bench/…/gate_verdict.txt`, never carried it into `docs/EVALS.md`, and five days
later re-commissioned the same mechanism as "unspent headroom" on the strength of the stale prose —
caught only because the new round's own §7 free-statistic contradicted the premise before anything
was spent. The rule: a round's verdict lands in `docs/EVALS.md` in the SAME commit as its results
directory, or the round is not finished.

---

## 6. What the honesty vocabulary buys

The output-level version of all of the above is a small fixed vocabulary that appears *in the
output*, not in the documentation: floors are labelled `counts_floor="1"`; ambiguity is counted
(`amb=`, `ambiguous=`); truncations disclose what was cut and why; a selector that matches nothing
**refuses** rather than answering `0`; an estimate says it is calibrated rather than exact.

The point is not modesty. It is that a consumer — increasingly, an automated one — can act
differently on "none found" than on "none exists", and can only do that if the difference reaches it.
Every one of those markers exists because a capture-audit read caught the output saying something it
could not support.

---

## 7. Audit the choice, not the trigger

Many mechanisms here have two stages: a **trigger** selects candidates (a lift fires on a name
match, a router picks a ranker, a hook decides to nudge, an anchor detects a mention), and a
**choice** orders or places what fired. The stages fail independently, and a healthy trigger
statistic says nothing about the choice — a trigger can reach the right symbol in two thirds of
instances while the ordering buries it at median rank 33.

The rule, earned the expensive way (the r5 nameboost round — see its REJECT in `docs/EVALS.md` §7):

- **A pre-registration's gating statistic must be end-to-end** — "is the right answer inside the
  top-K of what the mechanism would actually emit" — never a stage statistic like fire-rate,
  candidate-pool recall, or trigger precision. Stage statistics are diagnostics for explaining a
  result, not criteria for advancing one.
- **Compute the end-to-end statistic on train before spending anything scarce** — a grid sweep, a
  held-out set, a judged corpus. It is almost always free, and it is the cheapest kill available:
  r5's was computable before its grid ran and read 0/97; the round instead audited its trigger
  (60–69%, healthy), spent the grid, and learned nothing the free number had not already said.
- **When a round dies, record which stage killed it.** "The trigger reaches gold; the choice buries
  it" is a reusable finding that shapes the successor; "it didn't work" is not.

The general failure this prevents: auditing the stage that is easy to instrument instead of the
stage that carries the claim. A mechanism advances on the number a user would experience, or it
does not advance.

---

## 8. Placebo-controlled comparisons

A ranking win and a smaller-context-helps-regardless-of-content win look identical from the outside:
both raise the same accuracy number. The only way to tell them apart is to run a treatment that is
the same shape and the same cost as the real one but deliberately carries no useful signal, and check
that the real treatment still beats it.

An external, placebo-controlled study of fault-localization-guided repair makes the case concretely:
comparing three arms on the same failing candidates — blind whole-solution resampling, spectrum-based
localized infilling, and same-length infilling at a disjoint *random* code span as the placebo — is
what let it show localized infilling losing decisively to blind resampling at matched attempt count
(3:40, p = 3.0×10⁻⁹) ([arXiv:2609.00854](https://arxiv.org/abs/2609.00854)). Without the random-span
arm run at matched token cost, that result would have read as "targeted editing helps" instead of
what the placebo showed it to be.

**The standing rule:** every fault-localization or retrieval head-to-head registered in
`docs/EVALS.md` from this point on must include a random-rank or random-span placebo arm at matched
token cost alongside the real baseline(s), pre-registered the same way every other arm is. A round
that skips the placebo arm has not shown a ranking win — it has shown a context-size win, which is a
different and weaker claim, and the two must never be reported as if they were the same result.

---

*See `CONTRIBUTING.md` for how these rules land as concrete requirements on a change, and
`docs/EVALS.md` for the instruments and the numbers.*

---

## 9. Terminality versus ceilings — the principles that resolve them

Two goals pull at every default in this tool. The first is **terminality**: an agent asks one question and the
answer carries everything it needs, so no grep-and-read follows. The second is the **ceiling**: no answer may blow
the agent's context, so outputs are bounded. They look like a conflict — a complete answer wants to be long, a
bounded answer wants to be short — and a round that optimises only one of them makes the tool worse. The 2026-09-04
capture-audit round measured both sides (the meter's post-call sweep for terminality; bytes and legend share for
the ceiling) and settled on six principles. They are stated here because they decide defaults, legends and cuts,
which is where the two goals meet.

1. **Terminality is the objective; the ceiling is a constraint.** Maximise the probability that the agent needs
   no further native read after the call, subject to output ≤ budget. The substitution meter yields that
   probability per verb (a call followed by a native read or grep within the next five tool calls is
   non-terminal; `TERMINALITY_WINDOW` in `bench/substitution_report.py`). A default changed without that number is a guess; the round's own budget proposal for the cold
   map was one, and the data said the budget flag does not make an answer more terminal — it trims a ranking from
   the tail and cannot know which row would have ended the search.

   *The harness-policy exclusion (owner ruling, 2026-09-05, terminality round A).* Claude Code's harness reads a
   file before it edits it — the Read-before-edit policy. On the EDIT verbs (`--replace-symbol-body`,
   `--insert-before-symbol`, `--insert-after-symbol`, `--edit-plan`, `--safe-delete` and their MCP twins) that
   Read follows the receipt whatever the receipt says, so counting it as a post-call sweep would measure the
   runner's policy and call it the verb's terminality; other runners (codex, opencode, aider) carry no such
   policy, and Claude's may change. The metric therefore NEVER charges a Read of the edit's own target file
   against an edit verb: it is reported as `policy-read` beside the number and excluded from it
   (`bench/substitution_report.py` §5b, the EDIT band registered in `docs/EVALS.md` "Terminality round A").
   What the edit verbs are judged on is the sweep of some OTHER file, a native edit of the same file, and the
   redundant `--edit-check` after a receipt that already carried the check — and the primary arm for that number
   is a runner WITHOUT the policy (`bench/agentloop` codex / opencode); the live meter's EDIT band is the
   uncontrolled, secondary reading. The edit verbs are improved regardless of the policy. Do not "fix" the
   metric back to counting the policy Read: a number that moves with the harness and not with the tool is not
   the objective in principle 1.

2. **Cut at the content cliff, not at a byte count.** The ranker knows where relevance drops (`--adaptive`, the
   compact route that ships edges instead of bodies). A ceiling is the backstop for when no cliff is found. The
   ceiling bounds the tail, never the head: when a ceiling would cut something above the cliff, compress first,
   move prose into attributes second, and if it still does not fit, exceed the ceiling with `over_ceiling="1"`
   rather than drop the row that would have terminated the search.

3. **Never cut silently; a disclosed cut is still terminal.** A small answer that states exactly what it left out
   and hands over the one deterministic call that fetches it (`shown= total= capped="1" next="…"`) ends the
   search. What breaks terminality is not a second call, it is a second call the agent has to guess at. Two known
   calls beat one call followed by three greps.

4. **Honesty lives in attributes, not prose.** `shown`, `total`, `capped`, `counts_floor`, `over_ceiling`, `next`
   cost tens of bytes; a legend paragraph costs thousands. This is what lets a compact answer be complete about
   its own incompleteness. The round's compact legend dialect cut the ten-verb edit loop's legend bill from
   32,684 to 3,791 bytes with every completeness attribute kept — honesty and compactness stopped competing once
   the honesty moved out of the sentences.

5. **Compose on the server so the agent does not chain.** `--pack-task`, `--safe-delete`, `--handoff`, and the
   edit receipt that carries its own contract check and tests-to-run turn the three calls an agent would make
   into one, and because the composed verb shares one legend and one symbol table the output grows far less than
   three answers would. When two verbs are always run back to back, that is a composition the tool owes, not a
   habit the agent should keep.

6. **Separate finding from measuring, and give each its own instrument.** Finding (ranking, retrieval) is judged
   by recall at k on held-out tasks and by the terminality band; measuring (counts, floors, blast radius,
   budgets) by re-derivation gates that recompute the number from another verb or from the source. Neither may
   lie: a count that cannot be a total is a floor, a cut says how much it dropped, a ceiling attribute names the
   ceiling actually applied. "Algorithmic" means exactly this — every number has an instrument, every cut has a
   disclosure, and every default has an eval behind it, so the conflict between complete and bounded is decided
   by a measurement rather than by argument.

The practical order when an answer is bigger than its ceiling: rank; cut below the cliff and disclose the cut with
`next=`; if the head alone exceeds the ceiling, compress the legend, then the rows, then exceed with
`over_ceiling="1"`. Silence is the only option not on the list.

### 9.1 Addendum, 2026-09-23 — priority order is the mechanism; the ceiling only ever cuts what comes last

Principle 2 says the ceiling bounds the tail, never the head. Between 2026-08-22 and 2026-09-23 the 0.4.0–0.6.2
releases and the research lanes measured *how* that becomes true, and the answer is the same in every verb:
**the head is only safe from a cut if the cut walks the rows in priority order — rank before you cut — and
"priority" has to mean "the rows most likely to end the search", which is a verb-specific order, not source
order and never path or id order.** Emitting in that order is the simplest way to get it; a verb that documents
another emit order (bodies grouped by file) ranks, cuts, and then re-groups the survivors. The six principles
above stand unchanged; what follows is the record of the ordering findings that make them mechanical, each with
its number and its source, so the next default is set from the ledger rather than from taste.

**Two quantities the ledger is kept in.** *Terminality* is principle 1's objective and the substitution meter's
number: the share of a verb's calls not followed by a native read, grep, glob, find or git history call within
the next five tool calls
(`bench/substitution_report.py` §5, the FIND band registered in `docs/EVALS.md` "Terminality round A"). The
*chop rate* is the share of answers in which a §9 violation occurred: a HEAD row — a row the answer needed — was
removed by a ceiling (principle 2), or content was removed with no `shown= total= capped=` on the element
(principle 3). A disclosed tail cut with a deterministic `next=` is **not** a chop; a silent one is, whatever its
size. A cut that is counted but has no `next=` is a *dead-end cut*, counted apart: not a chop, but only half of
principle 3. Bytes are the cost, and the honest byte unit is bytes-before-the-row-that-answers (bytes to the correct
answer), because bytes after the answering row cost the agent little and bytes before it cost everything.
`docs/research/answer-completeness.md` carries the pre-registered scoreboard for both quantities and the
verb-by-verb inventory of where a cut can still be silent.

**The findings, as worked examples of the principles.** Four of the sources below are research notes that live on
research branches, not on main; each names its branch.

1. **Rank before you trim, and carry the rank onto the row.** `--for` grouped its bundle by file and sorted by
   line inside the group, so once the payload ceiling trimmed it the ranker's order was gone, and `r=` was
   assigned before the trim to carry it. On SWE-Explore at a 500-line budget, reading the rows in `r=` order
   (instrument v2) moved `hit_file_rate` from 0.281 to 0.311 on the same binary, while line recall fell from
   0.123 to 0.109: a MIXED result, reported with its decomposition (EVALS "SWE-Explore exploration lane
   (2026-08-28)", re-measured 2026-08-29; the earlier 0.260 → 0.281 step was the documentation-tier demotion, not
   ordering). A later round found the compact bundle showing 4 of a 40-candidate surface with the 36 trimmed rows
   served *nowhere*, because the file-grain tail excluded every file of the surface rather than the files of the
   rows shown. Re-pointing the tail at the trimmed rows, rank first,
   moved completed questions from 11/30 to 14/30 and gold from 34 to 42 of 129 (EVALS "LANE 2", `9273f346`).
   On 2026-09-05 (terminality round A, P7) the lens `<sigs>` began to emit in `r=` order and its ladder to drop
   from the rank tail. Principle 2 is not satisfied by having a rank; it is satisfied by cutting in it.

2. **Spend a budget in rank order, never in document order.** `--recall` put its sections back in document order
   and cut from the front: the #1-ranked section of the 616 KB `docs/COMMANDS.md`, at line 3,570 of 4,755, was
   served at none of 1,500, 4,000, 12,000 or 40,000 tokens. Spending the budget in rank order fixed it
   (CHANGELOG 0.6.0, `30b72ec0`). The same defect class in miniature: a 16-row callee cut that kept the lowest
   node ids kept 13 of `computeMergeScout`'s 22 callees, six of them STL noise, with the merge-scout functions
   last; on the verbs that have a query it now keeps rows by query rank (CHANGELOG 0.6.0, #95), while
   `--expand`, `--around` and `--exemplar`, which have none, still keep node-id order. An ambiguous `--expand`
   with no explicit `--top-k` emitted the ranked map before the bodies it was asked for, so the body landed 86%
   into the document; the body now comes first (CHANGELOG 0.6.2, #289).

3. **Answer first — the row the question names goes at the top.** When the task names a file with exactly one
   declaration/implementation partner, `--for` emits that partner as its first row, and `--situ` moves partners
   and siblings ahead of the blast radius (CHANGELOG 0.6.2). Precision over recall: absent, ambiguous or
   convention-less names get no row and no reordering, because a wrong first row is worse than none.

4. **Priority is verb-specific, and it has to be measured per verb.** Tests-to-run rows on `--affected`,
   `--situ` and `--test-gate` were path-sorted, which put a hit at row ~60 of 127; ordering by
   `changed=1`, then `partner=1`, then `hops=N` took one question from 6,233 to 2,073 bytes for 281 bytes of legend
   (EVALS Graft head-to-head, "Losses, bucketed" L2 and the post-fix run, `7dae6522`). `--rank-by=churn-decay` ordered `<recent>` by decayed weight and
   missed the gold; newest-first found it (L3, `c7688421`; that rests on q25 alone, which was asked at a pin that
   already contained its graded commit, so it is not established: EVALS, Graft round correction). `--slice=SYM:VAR` emitted seed rows in source order;
   def-use coverage order (`order="defuse"`) scores MRR 0.628 against 0.602 for a random-order control and 0.525
   for source order on 478 pairs from 173 Python instances, Δ = +0.026 with a 95% CI of [0.004, 0.049] — better on
   182 pairs, worse on 227, tied on 69, in-sample and Python only (EVALS "`--slice=SYM:VAR` def-use row order",
   pre-registered and measured 2026-09-22). That last result is the honest shape of an ordering win: real, small, and not uniform, so it is
   adopted as a default and stated with its loss count rather than sold as a lift. The one attempt to rank
   *further* — definitions before uses over the whole function span — was pre-registered and scored the next
   day and **failed**: R3@1 0.034 against the random control's 0.042, Δ = −0.008, 95% CI [−0.031, 0.019], 1 of 4
   registered conditions met, n = 173; nothing shipped and `order="defuse"` stays, because source order had
   measured worse than random on the same rows (`docs/research/arise-line-ranking-prereg.md` §9 on
   `lane/arise-result`, `13292db7`). An ordering claim is scoped to the pool it was measured on.

5. **Shrink rather than pad, and refuse a cliff that is not one.** A `--for` quota that filled in path order
   padded symbol-lookup bundles with zero-score rows that took 64–84% of the bytes; the relevance floor now stops
   the head at the last row with any evidence and says how many it kept (EVALS, 2026-08-22, cited there as
   `13291b9`; `eb975cf8` in today's history). The
   converse defect: `--adaptive` cut `update` from 231 symbols to 6 and `run` from 148 to 10 at a gap that was
   tie-break order among identically-named symbols, and claimed `confidence="high"` doing it. It now declines to
   narrow when a name-exact pool exceeds `kAdaptiveHomonymPoolFloor` (50) and the cut keeps at most twice the
   adaptive floor of 5 rows,
   serves the default head, and says why (CHANGELOG 0.6.2; investigated first in
   `docs/research/adaptive-short-query.md` on the `lane/research-adaptive-shortquery` branch). A cut is only a cliff cut if the ranker can say what produced the gap.

6. **A disclosed stub is a cut, so it must be cheaper than what it replaces.** Round one collapsed every
   `<lego>`/`<compose>` section to a counted stub, and the stub's task-echoing `next=` could exceed the section it
   replaced. The stub now fires only when `len(section) > len(stub) + len(kForSectionStubLegend)` (the legend
   clause, 262 B at `60b65f02`, charged whole) and `--sections=lego,compose` restores
   both byte-identically (CHANGELOG 0.6.2). Principle 3's "two known calls beat one call and three greps" holds
   only when the second call is cheaper than the bytes it saved.

7. **Price the ceiling in the unit you emit.** The `--for` ladder tested its ceiling at 2.36 bytes per token while
   `est_tokens=` priced markup at 2.50 and bodies at 3.80, so rungs dropped legend clauses from documents that
   already fit — on a five-symbol fixture, 354 tokens of headroom spent to buy nothing; a 70-byte post-ladder splice went unpriced and bundles
   shipped past the allowance with no rung fired at 14 of 111 budgets (CHANGELOG 0.6.1 #215; 0.6.0 `7caf968f`,
   `3d98f84d`). An explicit `--token-budget` above the default let `<sigs>` grow from 1,782 to 9,483 bytes and
   squeeze six served bodies down to two (measured before it landed; EVALS says those body counts do not
   reproduce at HEAD), until the auto-bundle's signature side was capped at `kForPayloadBudgetBytes` (EVALS
   "Auto-bundle section split under an explicit `--token-budget`", fixed in `57c1832f`). A mis-priced ceiling cuts
   the head while reporting that it did not.

8. **Bytes before the answering row is the cost that matters.** Making the legend a per-session dictionary on
   MCP left the same rows and the same attributes in place, and on the second call of a session cut `impact` on
   `compactLegendText` from 3,386 to 2,571 B (−24.1%), with the bytes before the first row falling from 78 to 8
   (CHANGELOG 0.6.2, the `ref` posture). The
   compact-legend default did the same on the CLI: `--callers` 6,305 → 3,212 B, `--edit-check` 9,750 → 3,313 B,
   rows unchanged (CHANGELOG 0.6.2). Neither changed a ranking; both moved the answer forward.

9. **Below the symbol there is a granularity floor, and it binds only under tight budgets.** With the correct
   function *given* and a 512-byte budget, delivering ranked slice lines put 32.1% of the gold lines in front of
   the agent where the whole function body put 17.6% (n = 150 instances whose body does not fit; the filter
   alone is worth +10.0 pp, the ranking a further +4.4 pp); the gap narrows as the budget grows, to +5.0 pp at
   4 KB on the 51 bodies that still do not fit, and the ranking gain was negative at 2 KB
   (`docs/research/slice-line-recall.md` R5, on the `lane/research-arise-slice` branch). The same note measured the
   limit: 70.8% of that corpus's gold lines sit in multi-function fixes a single-function slice cannot reach by
   construction, and extending reach across the directed call graph would recover 6.14% of that ceiling — under
   the pre-registered 20% kill line, so it was not built (§10). Line granularity is a lever for the head under a
   small budget, not a substitute for choosing the right function — and, after the `lane/arise-result` FAIL
   above, the lever is the *filter* (which lines) more than the *order* (which first).

10. **The stop-when-complete signal does not exist yet, and we say so.** `confidence=`/`margin_pct=` on `--for`
    have a measured false-warn rate of 0.779 (74 of 92 held-out instances flagged low, 60 of them right at
    file grain), so they cannot yet tell an agent to stop; `served_syms` — the served head's own row count —
    was scored against the band *false-warn ≤ 0.20 at miss-recall ≥ 0.50* under a pre-registered orientation
    (informed by an exploratory AUROC it had seen, as that note says: not blind) on
    the fingerprinted 92 and **failed**: func-grain AUROC 0.278 [0.177, 0.385] under the registered direction, no
    threshold clearing both floors (`docs/research/confidence-and-abstention.md` §5.4 and §10 on
    `lane/served-syms-result`, `50c554e6`; the opposite orientation is a hypothesis for a fresh sample, not a
    result). Until a signal meets that band on two samples, "terminate once the answer is complete" is a
    hypothesis, and the tool answers in full and discloses.

**What these add to the practical order at the end of §9.** Before "rank; cut below the cliff": *decide the
verb's priority order and cut in it* — the named row, then rank, with `r=` on the row, emitted in that order
unless the verb documents another, in which case the survivors are re-grouped after the cut; *price the ceiling
in the emitted unit*; *let the tail name what the head cut*. And one rule the rounds kept re-learning: **a
`--top-k`, quota, fanout or page cap applied to a list in source, path or id order is a head cut waiting to
happen**, because nothing ranks what it drops. The sites the 2026-09-23 survey found are in the inventory in
`docs/research/answer-completeness.md`, with whether each discloses at `60b65f02`. The survey is a floor: a
verb it does not list has not been shown to be free of silent cuts.

**What the disclosure attributes mean, as emitted.** The vocabulary is `src/pageview.h` THE TRUNCATION
VOCABULARY, and §9's names are the emitted ones: `shown=` (rows printed), `total=` (the verb's own count
attribute where it has one: `hits=`, `count=`, `importers=`), `capped="0|1"` (a boolean, never a count), `next=`,
`over_ceiling="1"`, and `counts_floor="1"` beside a `<noun>_capped=` floor marker. On an element trimmed by a
byte budget, **`total=` is the number of rows handed to the byte gate**: after the verb's documented candidate
window and after rows with nothing to print, before any byte budget (rule 5, extended to every byte gate on
2026-09-24). A byte cut can therefore never hide inside `total=`. A candidate window, such as `--for`'s 40-row
head, is not a byte cut. What lies past a window needs its own attribute, decided once for every ranking verb.

### 9.2 Addendum, 2026-10-02 — answering first; sizes are guards and stair-steps

§9 makes terminality the objective and the ceiling a constraint; this addendum states how that is scored while a
complete answer to every question is still out of reach. Until an answer can be complete it owes three things: it
stays bounded, it says what it does not know, and it names where to look next. A change is therefore judged on four
measures, not one:

- **Complete answers** — the share of questions answered so the agent can act without re-checking.
- **Honest-partial rate** — how often an incomplete answer says what it is missing instead of sounding confident.
- **False-confidence rate** — wrong answers that claim to be complete; the worst case, held near zero.
- **Next-clue usefulness** — for partial and wrong answers, whether the first suggested next step reaches what the
  question needed within one hop. Graded blind.

A size limit has exactly one of two roles, and a limit that has neither is removed. A **runaway guard** is a hard
ceiling well above typical answers; it exists to catch an output bug, so hitting it is a bug signal that needs an
explanation, and it says so when it trips. A **stair-step target** is a byte figure driven down release over
release; each row is explain-or-fail, so anything over it carries a stated reason, and it never drops content that
the uncapped variant shows is needed.

**A capped variant is always graded against its uncapped twin; the better-answering one ships; bytes break ties and
are driven down across releases without lowering complete answers.** Earlier compaction work sometimes cut useful
information, which is why every cut must be disclosed, recoverable, and measured against the uncapped twin.
