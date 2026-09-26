# Gate vs. iterative degradation — a research note

**Status: first pass. A reading path plus a harness design, not a result.** Nothing here reports a
measured effect of a gate on a degradation trajectory — we have not run one. What follows is (1) a
reading path into `--quality-delta` for an outside researcher, written to stand alone, and (2) a
concrete design for the experiment that would actually answer the question, including the shape of
result that would prove the design's own premise wrong.

## The paper this responds to

Shivani Shukla, Himanshu Joshi and Romilla Syed, "Security Degradation in Iterative AI Code Generation: A Systematic Analysis of the
Paradox," accepted IEEE-ISTAS 2025, [arXiv:2506.11022](https://arxiv.org/abs/2506.11022). The paper
runs a controlled experiment — 400 code samples, 40 rounds, four prompting strategies — asking an
LLM to iteratively "improve" its own code, and finds critical vulnerabilities increase 37.6% after
five iterations. It names the mechanism "feedback loop security degradation": a model optimizing for
its own stated goal (functionality, readability, the thing the prompt asked for) trades away a
property nobody in the loop is measuring. The paper's own recommendation is human validation between
iterations — an external check, not another self-critique pass.

That is the premise this note takes seriously, generalized past security to code quality broadly:
if the reason iterative self-improvement degrades is that nothing *external and stable* is measuring
what degrades, the fix is not a better prompt, it is an oracle the model cannot rationalize past. This
is a design **hypothesis**, not a result borrowed from the paper — the paper does not test
`--quality-delta` or anything resembling it, and Part 2 exists because this note is not entitled to
claim otherwise.

## Where this hypothesis actually lives — and why not `docs/LINEAGE.md`

`docs/LINEAGE.md` folds a work only when "the lesson taken from it can be named in one sentence
**and** pointed at a real flag or source file" — a citation for something the paper *caused* us to
build. That is not this. `--quality-delta` predates this note; nothing about it changed on reading
Shukla et al. 2025. Filing this as a lineage row would misrepresent the tool's history to buy a citation.

The actual record of this position is the design comment at the top of `src/quality.h` (the file
that implements `--quality-delta`), which already states the mechanism this note is arguing from —
without citing this specific paper:

> `quality.h` — `--quality-baseline` / `--quality-delta`: the deterministic oracle for a code-quality
> **CONVERGENCE LOOP**. … the "delta, not absolute" discipline that lets a refine loop target *the
> regression it introduced* instead of chasing absolute numbers (**the defense against Goodhart /
> metric-gaming**).

That comment is design intent recorded where the code lives, not a claim staked in a document meant
to be an honest ledger of external influence. This note is the first place the two are put side by
side on purpose. If a later change actually adapts something from Shukla et al. 2025 — the vulnerability
taxonomy, the round-count design, a specific finding — *that* change earns a `LINEAGE.md` row at the
time it lands, not retroactively from this note.

---

## Part 1 — a reading path into `--quality-delta`, for an outside researcher

Read in this order. Each step names the file, and what you're checking for.

### 1. Start here

- `./build/ripwire --help` and [`docs/COMMANDS.md`](../COMMANDS.md) (`--quality-delta`,
  `--quality-delta=REV|A..B`, `--quality-baseline`, `--quality-ack`, `--ack-only`, `--dmm`) — the
  generated, always-current flag reference. If this note disagrees with `--help`, `--help` is right.
- `src/quality.h` lines 1–20 — the file's own one-paragraph design statement (quoted above in full
  context). It states the Goodhart defense explicitly: report only the *regression*, never an
  absolute score, because an absolute score is a target a model can learn to game without fixing
  anything.

### 2. The ten kinds, and where each is computed

All ten live in `src/quality.h`. `computeSnapshot` (line 3959) builds the per-symbol/per-group floor
from one tree; `computeDelta` (the function whose body spans roughly line 6700–7200) compares two
snapshots and emits only what got worse. Per-kind entry points (line numbers at `origin/main`
`755f9026`, this branch's base — they drift as the file changes, so treat them as a starting point,
not a pin):

| kind | bar / threshold | computed at |
| --- | --- | --- |
| `complexity` | ccx > 15 (`kCcxBar`), AND grew | `perSymbolKind( "complexity", … )`, `src/quality.h:6860` |
| `verbosity` | LOC > 60 (`kLocBar`), AND grew | `perSymbolKind( "verbosity", … )`, `src/quality.h:6861` |
| `nesting` | max-nest > 4 (`kNestBar`), AND grew | `perSymbolKind( "nesting", … )`, `src/quality.h:6862` |
| `params` | param count > 5 (`kParamBar`), AND grew | `perSymbolKind( "params", … )`, `src/quality.h:6863` |
| `duplication` | new/grown clone group ≥ `kMinCloneTokens` (18) | `src/quality.h:7000`, clone detection in `src/clones.h` |
| `dead-code` | zero in-edges, not a registered/test/fixture exemption | `isDeadCandidate`, `src/quality.h:648`; emitted `src/quality.h:7029` |
| `api-surface` | a symbol becomes public, or a public signature's arity changes | `src/quality.h:7115` (visibility flip), `:7148` (arity/contract change) |
| `error-masking` | a construct in `findErrorMasking`'s built-in rule table (`src/lintrules.h`) | `errorMaskCountsBySym`, `src/quality.h:765`; emitted `:7183` |
| `short-horizon-churn` | a file rewritten ≥2 times inside a 14-day window AND touched by this diff | `src/quality.h:7310`, mined via `gitmine.h` |
| `new-clone-of-reused-helper` | a fresh clone of a helper whose existing fan-in ≥ 3 | `src/quality.h:7392` |

Four numeric kinds (`complexity`, `verbosity`, `nesting`, `params`) share one generic
`perSymbolKind` driven by a lambda that reads the metric off `Symbol` — read that one function and
you have read all four. The other six are presence/structural kinds with their own emission sites,
listed above.

**The materiality design, which the paper's own framing makes relevant.** A regression whose delta
is below a per-kind "minor" threshold (`kMinorCcxDelta = 3`, `kMinorLocDelta = 10`,
`kMinorParamDelta = 2`; nesting and the presence kinds have none — any instance is major) is reported
but does not gate exit 2 on its own. This exists because a +1-ccx edit to a function already over the
bar is technically a regression but is noise that would drown the findings a refine loop should
actually chase (`src/quality.h` comment above `kMinorCcxDelta`). If a degradation trajectory is a
slow accumulation of small unmeasured moves rather than one visible break, this threshold is exactly
where a gate could be *blind* to it by design — see §2.2's growth-rate instrument, added for this
reason.

### 3. The baseline model

Two floors, chosen automatically (`docs/COMMANDS.md` `--quality-delta` section, and
`computeHeadSnapshot`, `src/quality.h:3525`):

- **Sidecar** (`.ripwire_quality_baseline`, written by `--quality-baseline`) — honored only when
  pinned at exactly the current `git HEAD` (strict equality; an ancestor is a different tree). Stale
  → self-heals by deleting the file and falling back to the second floor. `--quality-baseline`
  itself **refuses** (exit 1) to pin on a dirty tree unless you pass `--allow-dirty`, specifically so
  the debt already in a working tree cannot be swallowed into the floor and read clean forever after.
- **git-HEAD** (no sidecar, or a stale one) — `computeHeadSnapshot` (`src/quality.h:3525`) does
  `git archive HEAD` into a temp directory and re-ingests it (`materializeCommitTree`,
  `src/quality.h:3345`), then compares the working tree against that.

### 4. The fix that just landed — a clean tree must never gate

`$ORCH/reports/t12-qd-noop.md` (this orchestration round, branch `lane/t12-qd-noop-diff`, head
`d54ce3da`). The mechanism: the git-HEAD floor is built by archiving and re-ingesting HEAD into a
temp directory, which is a **different file population** from the working tree whenever anything is
untracked, gitignored, export-ignored, sparse-checked-out, or otherwise present on one side and not
the other — a shallow clone, `.gitignore`d duplicate, or skip-worktree flag all reproduce it. Because
a dead-code verdict is a property of the *whole population* a symbol is ingested with, not of its own
file, a file present on only one side can flip a same-named definition's dead/alive verdict on a
symbol *both* sides share — and a no-op diff gates. Three review rounds converged on the same defect
class reached three different ways; the final fix (round 3, `d54ce3da`) replaces a hand-written model
of git's file-selection rules with git's own answer, rather than patching the model a third time. This
matters to a researcher reading the tool cold: it is the concrete shape of "the gate itself has bugs,"
and it is now closed for the no-op case specifically — read the report for what's still scoped out
(the Django `cls.`/`self.` dispatch half of the same issue, tracked separately, #237).

### 5. The ack ledger, and why it exists

`.ripwire_quality_acks` (format documented at the top of the file itself, and in
`--quality-ack`/`--ack-only` in `docs/COMMANDS.md`). An ack records a **reviewed** finding as known,
suppressing it until it *worsens past its acked magnitude* — a ratchet, not a mute. `--ack-only=KIND`
exists because bare `--quality-ack` accepts the whole current report, and accepting one deliberate
change alongside everything else unacked turns a ratchet into a rubber stamp — the tool's own
documentation names this failure mode explicitly and gives the scoped form as the way to avoid it.
For the degradation question this ledger is a hazard to control for: an iteration loop with a
human (or an agent) free to ack findings can make the *gate* report clean while debt still
accumulates under the ack. §2.4 treats acking as something the harness must record, not something it
assumes away.

### 6. The eval harness

[`docs/EVALS.md`](../EVALS.md) §1 tables every instrument this project has and what each measures;
§6 has `--quality-delta`'s own kind list restated with the exact `kind=` strings; §7 is a section of
*honest counterexamples* — measured findings that went against the tool's own claims, published on
purpose. `bench/` holds the harness code itself: `bench/recalleval/`, `bench/headtohead/`,
`bench/locbench/`, `bench/ensemblecal/`, each with its own README. `bench/ensemblecal/` is the
closest structural relative to what Part 2 proposes: it separately verifies a calibration hypothesis
(that four evidence families are orthogonal) with a stated honesty contract, and reports what it
would take for the hypothesis to be wrong.

### 7. What our own backtest says — read this before citing the tool as a detector

`$ORCH/reports/study-checks.md` §3 (backtest against ripwire's own commit history, `W` = window in
commits): at the realistic five-commit window, `--quality-delta` fires on **14/24 (58%) of states
that provably contained a finding somebody later fixed, and on 12/30 (40%) of control states with no
recorded defect.** 58% vs 40% is not discrimination — it is closer to a coin flip weighted by how
much code moved. The kind firing most on *defect-free* control states is `complexity` (10 of 30
control reds), the same kind whose per-symbol external-corpus signal (§4 of that report) is the one
structural metric that *does* separate human-authored defects from non-defects at 1.63× (95% CI
[1.11, 2.38]). Read plainly: `--quality-delta` measures accumulated debt, and debt correlates with
defect-proneness in the literature and in our own external check, but firing on a state is not the
same claim as identifying a defect in it. The tool's own documentation says "report only what got
worse … descriptive," and this backtest is the first time that sentence has been measured rather than
asserted. Any harness in Part 2 that treats a `--quality-delta` exit 2 as "a real regression was
introduced" is overclaiming; treat it as "measured debt increased," which is a different, still
useful, and honestly weaker claim.

### 8. Reading order, summarized

`docs/COMMANDS.md` (`--quality-delta` family) → `src/quality.h` lines 1–20 → the ten-kind table
above with the file open beside it → `$ORCH/reports/t12-qd-noop.md` → `.ripwire_quality_acks` header
comment → `docs/EVALS.md` §1 and §6 → `$ORCH/reports/study-checks.md` §3. That is roughly 45 minutes
to a working mental model, and it ends exactly where Part 2 starts: with the honest limit of what the
gate has been shown to do.

---

## Part 2 — a harness design for the degradation question

**The question Part 1's reading path does not answer:** does a deterministic external gate change
the *trajectory* of repeated self-improvement — the shape of the curve across iterations — or does it
only catch individual regressions after they already happened, leaving the underlying trajectory the
same? These are different claims. A gate that catches every regression it sees but never changes what
the model tries next iteration would still let the *next* unmeasured failure mode (the one the gate
doesn't check) degrade freely — Shukla et al. 2025's whole point is that *something* always degrades when
only *some* things are measured.

### 2.1 The loop

For each of N seed tasks (real small-to-medium functions or modules, ideally drawn from more than one
language ripwire indexes, since the ten kinds and their bars are language-general but their density
of hits is not measured to be):

```
state[0] = seed code, committed
for i in 1..K:
    prompt = "improve this code" + (gate feedback from state[i-1], IF gated arm)
    state[i] = model(prompt, state[i-1])
    measure(state[i])   # §2.2, run regardless of arm
    commit state[i]
```

Two arms per seed task, same model, same temperature, same seed code, same K:

- **UNGATED** — the prompt is "improve this code" (plus whatever the task needs for continuity, e.g.
  the running test suite's pass/fail if the task has one) and nothing else. This is the paper's own
  setup.
- **GATED** — the prompt additionally receives the previous iteration's `--quality-delta` (and, if
  in scope, `--test-gate`) report, unfiltered, as context the model is told to address before
  proposing the next change. No human is in the loop; the gate is the only external signal. This is
  deliberately the *weakest* form of "external and deterministic" — it tests whether the model
  reading the gate's own words changes behavior, not whether a human enforcing exit 2 would (a
  stronger, cheaper-to-argue-for design that isn't the interesting question: of course a hard stop
  changes what ships. The trajectory question is about the *code the model chooses to write*, not
  about a merge gate.)

K should be at least 10 — Shukla et al. 2025 reports the divergence sharpening between iteration 5 and 10; a
shorter loop cannot see whether a gate changes the *slope* rather than just one round's value.

### 2.2 What is measured each iteration

Everything below is computed fresh on `state[i]`, in both arms, whether or not that arm sees it in
its prompt — the ungated arm's own trajectory needs the same instruments or there's nothing to
compare against.

**Deterministic, ripwire-native (the ten kinds, from `--quality-delta --json` against `state[0]` as
the fixed baseline — not against `state[i-1]`, so a regression that got partially fixed and
re-introduced two iterations later is still visible; see §2.3):**
- All ten kinds' counts (`regressions`, `gating`, `minor`, per-`kind=` breakdown).
- `api-new-surface` and `register-macro-excluded` as printed floors, for context.
- Clone growth specifically (`duplication` + `new-clone-of-reused-helper` counts and the clone
  groups' member counts) — Shukla et al. 2025 doesn't measure this, but GitClear's agent-code findings that
  motivate `--quality-delta`'s own kinds (cited in `src/quality.h`'s comments) do, and duplication is
  cheap to accumulate silently under an "improve this" prompt that never says "don't repeat
  yourself."

**Deterministic, test-native:**
- Test pass/fail count, IF the seed task carries a test suite (`--test-gate --json`'s `tests=` /
  `untested=`, or the task's own runner if simpler). A trajectory that improves quality kinds while
  breaking tests is not a win for either arm's position.

**Deterministic, growth-rate (not in `--quality-delta`'s own output, but derivable from the raw
snapshot each iteration writes):**
- Sub-bar growth that `--quality-delta`'s "minor" threshold (§1.2) would not gate: raw ccx/LOC/nest/
  params values per touched symbol, iteration over iteration, regardless of whether any single step
  crossed a bar. This is the instrument for "the gate is blind to slow accumulation" — a real
  possibility given how the minor-severity design works, and worth measuring even though it isn't
  what the shipped tool reports.

**Public and deterministic, non-ripwire:**
- A public static security scanner appropriate to the seed task's language — e.g. Semgrep's default
  ruleset (multi-language, free, deterministic given a pinned ruleset version) or a
  language-appropriate equivalent (Bandit for Python, `cargo audit`/clippy for Rust). This is the
  instrument that actually answers the paper's own question (security), separate from ripwire's
  structural kinds, which do not claim to measure security. **Pin the scanner's version and ruleset
  hash in the run's metadata** — an unpinned scanner is not a repeatable instrument.

**Recorded, not computed:** whether the gated arm's model actually *acted* on the previous report
(a crude proxy: did the flagged symbol change in the next iteration at all) and whether any
`--quality-ack` was exercised (it should not be, in this design — acking belongs to a human reviewer,
and an unattended loop acking its own findings would silently defeat the gate; if a later variant lets
the model ack, that has to be a separate, explicitly labeled arm).

### 2.3 What "the trajectory changed" would mean, numerically — fixed in advance

Stated before any run, per the project's own pre-registration discipline (`study-checks.md`'s
external arm is the house precedent: the sampling amendment was written and executed *before* the
first measurement). Candidate instruments, all computed per seed task then aggregated:

1. **Cumulative-regression slope.** Fit `regressions[i]` (from §2.2, baseline-anchored so
   regressions don't wash out when partially fixed) against iteration `i`, per arm, per seed task.
   The claim "the gate changes the trajectory" requires the GATED slope to be statistically lower
   than the UNGATED slope, paired by seed task (Wilcoxon signed-rank across seed tasks, not a pooled
   t-test across iterations — iterations within one task's trajectory are not independent
   observations).
2. **Terminal-state comparison.** `regressions[K]` and scanner-finding-count`[K]`, GATED vs UNGATED,
   paired by seed task. This is the paper's own headline shape (end state after N rounds) and should
   be reported even though it's the weaker claim (it can differ without the *trajectory* differing —
   e.g. one late correction).
3. **Sub-bar growth rate** (§2.2's growth-rate instrument): does the GATED arm's raw metric growth
   per iteration (summed across touched symbols, below any bar) differ from UNGATED's? This is the
   instrument that would catch a gate that looks clean on `--quality-delta`'s own gating count while
   debt still accumulates just under every bar — the concern §1.2 raises.
4. **Security-finding trajectory**, same slope test as (1), on the scanner's output — this is the one
   that actually tests Shukla et al. 2025's claim in our setting, since none of ripwire's ten kinds are
   security checks.

**Pre-registered thresholds, to be set with the actual seed-task count and iteration count once
chosen (N and K bound the achievable power) — but the form is fixed now:** a slope difference is
"real" only if it clears a pre-specified effect size (not just p < 0.05 — with small N, significance
without an effect-size floor is how the ratchet-vs-detector confusion in §1.7 happens again one level
up), and the write-up reports the ungated-vs-gated comparison for **all four instruments**, not
whichever one came out favorable. Selective reporting of the metric that happened to move is the
single easiest way to manufacture the result this note wants to see.

### 2.4 The confound: the gate also changes the prompt

The GATED arm's prompt contains the previous quality-delta report; the UNGATED arm's does not. Any
measured difference could be "the model responded to structured, specific feedback about its own
code" rather than "the model responded to *this particular gate*" — a generic-text confound, not a
gate-specific effect. Two controls, both needed:

- **Matched-length neutral-text control (arm C).** Same prompt structure as GATED, but the appended
  text is a fixed, task-irrelevant block of roughly the same token length as a typical
  `--quality-delta` report (e.g. the tool's own `--legend` text, which is long, dense, and describes
  nothing about the current code). If GATED and C both outperform UNGATED equally, the effect is
  "more context helps," not "the gate helps," and the paper's mitigation claim does not transfer to
  this tool specifically.
- **Matched-content wrong-target control (arm D), if resourcing allows a fourth arm.** Feed the GATED
  prompt a real `--quality-delta` report — but from a *different* seed task, not this one. This
  isolates "specific, on-target feedback about this code" from "quality-delta-shaped feedback about
  something." If GATED clearly beats D, the effect is that the gate is *reading the actual code*, not
  merely primed by its vocabulary and structure.

Report GATED against UNGATED, C, and D (as available) side by side. The claim this note is actually
interested in is GATED vs. C, not GATED vs. UNGATED — the paper's baseline is silence, and beating
silence with *any* structured feedback would be a weak, likely-true result that says nothing about
determinism or externality specifically.

### 2.5 What result would count against our position

Stated plainly, in advance, because this is the part most likely to be skipped:

- **GATED does not clearly beat C (matched-length neutral text).** If a same-length block of
  unrelated text produces the same trajectory improvement as the actual quality report, the
  mechanism is "more tokens of structured-looking feedback," not "deterministic external
  measurement," and `src/quality.h`'s design comment (the Goodhart-defense framing) would be
  unsupported by this experiment specifically — it might still be true for other reasons, but this
  harness would not have shown it.
- **GATED's terminal state is better but its slope is not.** This would mean the gate produces one
  correction late in the loop (the model notices and fixes things right before the run ends) rather
  than changing the trajectory throughout — closer to "catches regressions after the fact" than
  "changes the trajectory," which is the distinction this whole design exists to draw, and the
  weaker of the two claims would be the honest one to publish.
- **The security-scanner trajectory (instrument 4) doesn't track the ripwire-kind trajectory
  (instrument 1) at all** — e.g. GATED improves structural debt but the scanner's finding count is
  flat or worse across both arms. This would mean structural-quality gating and security are close to
  orthogonal in this setting, which directly limits how far "a deterministic quality gate" can be
  read as an answer to a *security*-framed paper, no matter what instrument 1–3 show.
- **Sub-bar growth (instrument 3) is worse in GATED than UNGATED.** This would be the sharpest
  negative result: a model gaming the visible bar by keeping every individual metric just under
  threshold while the underlying code gets worse in aggregate — literally the Goodhart failure mode
  the gate exists to prevent, reappearing one level down. If this shows up, it belongs in
  `src/quality.h`'s own comments as a documented limit, not quietly dropped from the writeup.

Any one of these, on real data, is a more useful contribution than a clean win — this project's own
`docs/EVALS.md` §7 exists for exactly that reason, and a degradation-harness result belongs beside it
if it runs.

### 2.6 What we did not, and could not, do here

This is a design and a set of scaffolding scripts, not a study. Nobody has an LLM API wired into this
worktree, and no model calls were made to produce this document. The scripts in `bench/degradeloop/`
implement the deterministic half — the loop's bookkeeping, the measurement calls into
`--quality-delta`/`--test-gate`, and the trajectory-analysis math from §2.3 — with an explicit,
unimplemented seam where a real model call belongs, and every file says so at the top rather than
faking a call site that looks wired up. **No numbers in this document are results.** Anyone who runs
the harness and gets numbers should report them beside this design, including if they contradict
§2.5's stated position.

---

## What we would like help with

- **Seed tasks.** A good seed set needs real, non-trivial functions with a genuine "improve this"
  prompt that isn't already solved — ideally spanning at least two of ripwire's indexed languages, so
  the ten kinds' language-general bars actually get exercised differently. We don't have a vetted set.
- **A model-call adapter.** `bench/degradeloop/run_degradeloop.py`'s `call_model()` seam is written
  against a plain (prompt, code) → code interface deliberately — wiring it to a specific API is a
  few lines for whoever has one available and wants to run this.
- **The scanner choice per language**, pinned and justified — we picked Semgrep as the
  cross-language default in §2.2 but have not evaluated whether its default ruleset has the recall to
  see what Shukla et al. 2025's own taxonomy would flag.
- **A second opinion on the confound design (§2.4).** Arm D (matched-content, wrong-target) is the
  one we're least sure earns its cost against arm C alone — if C is enough to isolate the effect,
  D is one fewer arm to run.
- **Anyone who runs this** — even a small N, even one seed task, one language, K=10 — and reports the
  four instruments honestly, favorable or not. That is worth more than a larger version of this
  design document.
