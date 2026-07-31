---
name: ripwire-fresh-eyes
description: >
  Assess risk in code you did NOT write — a whole repo or one unfamiliar subsystem: "review this codebase /
  what's gnarly here / where's the rot / is this area safe to touch?". Also the entry point when you're
  PLANNING A REFACTOR or suspect a god object — find the high-complexity cluster, its blast radius, and its
  co-change seams. One structured pass over maintenance hotspots, dead code, duplicate bodies, AST smells,
  ownership / bus-factor risk, and hidden (co-change) coupling — scope any pass to a subsystem with a DIR
  argument. Use when inheriting a repo, sizing up an unfamiliar module before editing it, planning a
  refactor, hunting consolidation, deciding who should review, or producing a health snapshot. Everything
  emits FACTS, not verdicts — you judge. Backed by ripwire (deterministic, on PATH). For any DIFF — yours or
  an incoming PR — use ripwire-change-check; this skill is whole subsystems, not diffs.
allowed-tools: Bash, Read
---

# Fresh-eyes risk review with ripwire

> Routing:
> • Any DIFF — your own, or an incoming PR you're reviewing — about to push or merge → **ripwire-change-check**.
> • Architecture health (deps metrics, layering rules, modules) → **ripwire-layers**.
> • Finding where a specific BUG lives → **ripwire-find-bug**.
> • Not sure which skill? → **ripwire-router**.
>
> **Scope it to one unfamiliar subsystem** you're about to touch, instead of the whole tree, two ways:
> point `<dir>` at the subdirectory (`ripwire src/net --hotspots`), or keep the repo root and `--exclude` the
> rest. `--dead-code=DIR` also scopes directly. This is how you turn the repo-wide sweep into a
> "what's-gnarly-in-code-I-didn't-write" read of one module.

`<dir>` = repo root. Add `--exclude=build --exclude=.git` (repeatable) to keep build artifacts out — they
otherwise show up as false clones and dead code. This composes descriptive passes into one snapshot; run the
sections your question needs.

**Inheriting this subsystem?** Check `ripwire <dir> --notes` first — a prior agent's pinned gotcha
(`--note-add`'d trap, flake, or invariant) is the cheapest fact you can pick up before you start reading.

## Core health passes

1. **Maintenance hotspots** — `ripwire <dir> --hotspots`
   ```
   <hotspots window="12mo" ranked="33"><f p="./src/main.cpp" churn="53" ccx="1365" score="72345" top="main:1306"/> …
   ```
   `score = churn × ccx` (commits × Σ cognitive complexity). Top files = where developers keep working *and*
   the code is hard — the highest-leverage places to improve. `top=` names the worst function.
   **Recent regression, not an all-time read?** `--hotspots --since="2 weeks ago"` (or `--since=HEAD~20`)
   scopes churn to commits after that point; unresolvable/absent `--since` degrades silently to all-history.

1b. **What is BUILT but DARK here?** — `ripwire <dir> --flags` (`=SUBSTR` to narrow)
   ```
   <flags gates="98" dark_gates="90" compile="32" cmake="9" env="57"><gate name="X_HARMONY_SFX" kind="compile"
     default="0" dark="1" regions="7" loc="45" reads="8" p="sound/audioWiringFlags.h" l="47"/> …
   ```
   Inheriting a repo, the invisible half is the code that ships compiled OUT. This harvests all three gate
   patterns — `#ifndef`/`#define` header gates, CMake `option()`, `getenv()` reads — with each gate's
   **default** and the size of the code it guards, dark first. Two things `--grep` cannot tell you: when a
   name is BOTH a header gate defaulting to `0` and a CMake `option(... ON)`, the **CMake default wins**
   (it is what the build passes) and the header appears as an `<also>` row — the contradiction a reader who
   greps the header gets wrong; and a gate whose default IS another gate's name resolves through the alias
   chain, so a master switch reports `<aliases n=…>` instead of a misleading `loc="0"`.
   **Limits:** lexical, not preprocessed — this is the in-repo default, never the value *your* build used.
   A gate needs a value (`#ifndef F` / `#define F 0`); valueless pairs are include guards and are excluded.
   A gate read as a value (`constexpr bool k = F != 0;` then `if constexpr`) honestly reports `regions="0"`
   here — **`--flip` below lifts exactly that limit.**

1b-ii. **If I flip THIS one, what lights up?** — `ripwire <dir> --flags --flip=NAME`
   ```
   <flip gate="X_RRF_ALL" kind="cmake" default="ON" dark="0" family="12" regions="0" loc="0" branches="43"
     bindings="11" hosts="11" downstream="95" dependents="146" tests="23" untested="0">
     <member name="X_RRF_ISLANDS" via="alias" branches="12"/> …
     <lights r="0" b="43"><b p="canyon/simLevel.cpp" l="133" gate="X_RRF_WIDTHWAVE" via="kWidthWave"
       sym="buildStripTable"/> …
   ```
   A list of ~90 dark gates is a map, not a decision. This is the decision: for ONE gate, the code that
   becomes live (`#if` regions **and** the `if constexpr` branch sites a value-style gate governs), the
   **symbols** holding it, what those transitively call (`downstream` — what starts executing), who depends
   on them (`dependents`), the **tests** that reach them, and `untested` — the hosts no test covers. That
   last number is the honest answer to "is it safe to flip?".
   Alias chains run **both ways**: flipping a master rolls up every child that `#define`s to it, flipping a
   child lights only that child and names its `<parent>` plus the siblings the parent's flip would add.
   `kind="cmake"` also steers the *build graph* (an `if(NAME) target_sources(...)` can add whole files) —
   those sites are listed as `<c>` rows and deliberately **not** followed. `kind="env"` is `runtime="1"`:
   no delimited region, so the hosts are the symbols that consult the variable.
   **Limits:** lexical and single-line, never preprocessed. A binding split across two lines is missed. The
   value lane reads C-family source only and treats a file declaring its **own** constant of that name as
   shadowing the gate's (C++ scoping) — but a *third* header's same-named constant, included rather than
   redeclared, would still count. A lit site inside no indexed def (a guarded member field, a file-scope
   `constexpr`, a test-macro body) counts into `filescope=` instead of a host. `--detail=N` lifts the row
   caps. Report only — always exit 0; an unknown gate name refuses (exit 1) and names the near-misses.

1c. **Can I TRUST this repo's docs?** — `ripwire <dir> --doc-drift` (`=SUBSTR` to narrow to one doc)
   ```
   <doc-drift docs="129" clean="110" anchors="1995" checked="716" unchecked="1279" drift="110">
     <doc p="AUDIT2_fable2026.md" anchors="50" checked="34" drift="9"><a k="file-line" l="186" c="80"
       why="line-moved" ref="src/main.cpp:317" sym="isGitUrl" got="communityPresentation"/> …
   ```
   Inheriting a repo, the design docs and audits are how you learn it — and the stale ones are how you learn
   it *wrong*. Run this **before** you read them: it verifies the CHECKABLE anchors (`file:line` refs,
   backticked symbol mentions, `= N` constants, `[N]` array extents) against the live index and reports only
   what no longer holds, per doc. A doc with `drift="9"` gets read with suspicion; the 110 clean ones do not.
   `why=` names the cause — `missing-file`, `past-eof`, `line-moved` (with `got=` naming the symbol that now
   occupies the line), `undefined`, `const-value`, `array-extent`.
   **Limits:** anchors, not prose — `§Status` lines, dates and "N of M done" tallies are NOT checked, and it
   says so rather than pretending. Every lane under-reports deliberately (a name is stale only if it occurs
   nowhere in the code as a token; a number only if the corpus binds it uniquely in a declaration), and
   `checked + unchecked = anchors` with each declined check named in an `<unchecked>` row. Exit is always 0:
   drift is a report, not a gate.

   **Want it to BECOME a gate?** — `ripwire <dir> --doc-drift --gateability`. The reason CI can't gate on
   drift is usually a handful of UNDATED design docs: with no date the lexical lanes can't tell "stale" from
   "a record of what was true then", so their rows stay unclassifiable. This lists exactly those docs and
   what one annotation each would fix:
   ```
   <gateability docs="17" projected_drift="0">
     <fix p="PLAN_phases.md" live="6"/> …
   ```
   `live=` is that doc's still-failing anchors; `projected_drift=` is the repo-wide drift you'd be left with
   if every listed doc got one ISO date in its H1 or a front-matter self-date line. Treat it as an **upper
   bound on the win, not a mandate** — dating a doc that is genuinely live hides real rot rather than
   resolving it. Use it to turn "CI stays non-gating forever" into a finite to-do list.

   **Add `--with-history` when the mention lane matters.** `undefined` only means "defined nowhere here",
   which on a repo whose PLAN docs name unbuilt features is *expected*, not rot — measured on a 2900-file
   repo, 243 of 325 `undefined` rows were names that had never existed there. `--with-history` makes one
   `git log` pass over everything reachable from HEAD and splits the lane: `why="deleted"` with `got="removed
   in <commit> (<date>)"` and `at=` the file (real rot, ~75% fewer rows but every true positive kept), versus
   `<unchecked r="never-in-history">` for names the repo never had. It is opt-in because the walk costs ~3 s
   on that repo against a 0.64 s default; the result is memoized per (repo, HEAD sha), so every later
   question on the same commit — including `--whereis --with-history` — is a cache load.

2. **Dead code** — `ripwire <dir> --dead-code[=DIR]`
   `<dead-code count="N" confidence="high" evidence="internal-linkage+zero-callers"><d n="orphan" …/>` —
   source-defined free functions with explicit internal linkage and **in-degree 0** in the indexed call
   graph. `--dead-code=DIR` scopes to a sub-tree. Methods, declarations, headers, and external-linkage entry
   points are excluded, so `count="0"` means "no high-confidence candidates," not "no dead code." Name-based
   and tree-local — **verify before deleting**: confirm against the compiler's unused-symbol diagnostics or a
   linker map; ripwire narrows the field, the toolchain proves it.

3. **Duplicate bodies** — `ripwire <dir> --clones`
   `<clones groups="N" type3="M"><group type="2" tokens="161" n="2"><f n="line" p="…:31"/><f n="line"
   p="…:28"/></group>`. `type="2"` = exact/renamed (identifiers + literals normalized, so a renamed copy
   still matches); `type="3"` = a gapped NEAR-miss (similarity 0.80–1.0, an inserted/changed statement) —
   check `type=` before assuming two members are byte-identical. Larger `tokens=` = more dedup value; a fix
   to one likely belongs in all. **Rule of Three:** extract on the *third* occurrence, not the second — a
   little duplication beats the *wrong* abstraction.

4. **AST smells** — `ripwire <dir> --lint`
   `<lint findings="N"><rule name="magic-number" count="82"/> …` then per-finding `<f rule= p= …>` with the
   enclosing symbol. No-build, AST-only — a fast complement to clang-tidy, not a replacement. Skim the
   per-rule counts for the dominant smell.

   **Your own rules** — `ripwire <dir> --lint-rules=DIR` loads YAML ast-grep-style rules from `DIR` and runs
   them alongside (or instead of) the built-ins; findings share the same `<f rule= sev= p= …>message</f>`
   shape. A malformed rule alerts to stderr and is skipped (sibling rules still load); zero loaded rules
   exits 1. Writing a rule (the query grammar, the `inside`/`not-inside`/`not-matches` combinators, a worked
   example) → **[`lint-rules.md`](lint-rules.md)**.

5. **Ownership / knowledge risk** — `ripwire <dir> --owners[=SYM]`
   `<owners files="N"><f p="…" authors="1" bf="1" top="…@…" share="1.00"/>` (recency-weighted, 6-month
   half-life). `authors=` distinct authors; `share=` the top author's fraction of weighted commits;
   **`bf="1"` = one person holds >80% (bus-factor risk)**; `top=` = who to ask / who should review.
   `--owners=SYM` resolves to just that symbol's defining file — the "who should review my change to
   `buildGraph`" answer. Measures *git authorship* (recency-biased), not who *should* own the code.
   **Worst case:** a file that's BOTH a top hotspot (step 1) AND `bf="1"` — gnarly code only one person
   understands.

## Hidden-coupling pass — "a change here keeps breaking unrelated files"

6. **Behavioural coupling** — `ripwire <dir> --cochange`
   Bare `--cochange` emits ONLY the *surprising* pairs — files that change together in git but share **no
   static dependency** either way:
   `<cochange pairs="N"><pair a="…" b="…" together="17" deg="1.00" surprising="1"/>…`
   (`together` = commits co-appearing, `deg` = fraction of the rarer file's commits). Pure behavioural
   coupling — shared global state, parallel ownership, or an implicit protocol; statically-linked pairs are
   filtered out as expected. For ONE file's full partner list, `--cochange=FILE`.

7. **Structural coupling** — `ripwire <dir> --deps`
   `<deps>` with god-files ranked by `afferent` (dependents) and each file's `instab` (1 = leaf, 0 = core).
   High-afferent, high-instability files are unstable hubs — every change there fans out. Cross with the
   step-6 surprising partners: a clone group (step 3) that *also* co-changes is a maintenance coupling — a
   fix must land in both copies.

## Planning a refactor / "this class is a god object"

When the job is *"I'm about to restructure this — where's the seam and what will it break?"*, chain three
passes into a refactor brief:

1. **Find the high-complexity cluster** — `ripwire <dir> --communities` (cohesive call-graph modules) or
   `ripwire <dir> --metrics --top-k=40` and read `ccx`/`lcom4`. `lcom4>1` is a **god object by the numbers**
   — N disjoint method clusters that want to be N types; the community/`--zoom` view names the members that
   belong together. Pick the cluster to break apart.
2. **Its blast radius** — `ripwire <dir> --impact=SYM` on the cluster's lead symbol → `reaches="N"` = every
   caller a signature change would touch. Large `reaches=` → stage behind a shim, don't big-bang it.
   `--affected=<files>` names the tests to keep green through the move.
3. **Its co-change seams** — `ripwire <dir> --cochange=FILE` on the file you're splitting → files that
   historically move with it. A `surprising="1"` partner (no static dependency) is **hidden coupling the
   refactor must preserve or explicitly cut** — fold it into the plan before you start.

→ **Refactor brief:** the cluster to split (with its `lcom4`/`ccx` evidence), the blast radius + test gate,
and the co-change partners to keep in sync. For CI-enforcing the boundary you extract → **ripwire-layers**.

## Output

A one-page health snapshot:
- **Hotspots** — top 3 files by `score`, each with its worst function.
- **Cleanup wins** — count of high-confidence dead-code candidates (all still marked *verify*) + the largest
  clone group (biggest dedup payoff).
- **Dominant smell** — the highest-count lint rule and where it clusters.
- **Knowledge risk** — `bf="1"` files, flagging any that are also hotspots.
- **Hidden coupling** — top surprising co-change pairs + any that overlap a clone group.
- **One-line verdict** — healthy / has-debt / needs-attention, with the single highest-priority item first.

This is the structural read — it doesn't run tests or a compiler. Pair with the build's warnings and test
suite; use **ripwire-change-check** for a specific diff rather than the whole repo.

**Date the snapshot.** A health report is quoted back weeks later, long after the numbers moved. The
git-aware verbs stamp the commit they measured at — `--map-diff`/`--doc-drift` carry `at="<sha>[+dirty]"`,
`--stray-content` carries `head="<sha>"` — but most of this skill's passes (`--hotspots`, `--clones`,
`--lint`, `--dead-code`, `--cochange`, `--owners`) carry **none**. Open the snapshot with the sha you ran
at (`git rev-parse --short HEAD`) so a reader can tell a live finding from an archaeological one.
