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
   probability per verb (a call followed by a native read or grep within the next three tool calls is
   non-terminal). A default changed without that number is a guess; the round's own budget proposal for the cold
   map was one, and the data said the budget flag does not make an answer more terminal — it trims a ranking from
   the tail and cannot know which row would have ended the search.

   *The harness-policy exclusion (owner ruling, 2026-09-05, terminality round A).* Claude Code's harness reads a
   file before it edits it — the Read-before-edit policy. On the EDIT verbs (`--replace-symbol-body`,
   `--insert-*-symbol`, `--edit-plan`, `--safe-delete` and their MCP twins) that Read follows the receipt whatever
   the receipt says, so counting it as a post-call sweep would measure the runner's policy and call it the verb's
   terminality; other runners (codex, opencode, aider) carry no such policy, and Claude's may change. The metric
   therefore NEVER charges a Read of the edit's own target file against an edit verb: it is reported as
   `policy-read` beside the number and excluded from it (`bench/substitution_report.py` §5b, the EDIT band
   registered in `docs/EVALS.md` "Terminality round A"). What the edit verbs are judged on is the sweep of some
   OTHER file, a native edit of the same file, and the redundant `--edit-check` after a receipt that already
   carried the check — and the primary arm for that number is a runner WITHOUT the policy (`bench/agentloop`
   codex / opencode); the live meter's EDIT band is the uncontrolled, secondary reading. The edit verbs are
   improved regardless of the policy. Do not "fix" the metric back to counting the policy Read: a number that
   moves with the harness and not with the tool is not the objective in principle 1.

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
