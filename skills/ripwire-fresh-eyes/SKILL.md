---
name: ripwire-fresh-eyes
description: >
  Assess maintenance risk in code you did NOT write — an already identified subsystem: "what's gnarly
  here / where's the rot / is this area safe to touch?". Use it when PLANNING A REFACTOR or investigating
  a suspected god object — find the high-complexity cluster, its blast radius, and its co-change
  seams. One structured pass over maintenance hotspots, dead code, duplicate bodies, AST smells, ownership
  / bus-factor risk, and hidden (co-change) coupling — scope any pass to a subsystem with a DIR argument.
  Use when taking ownership of an existing module, planning a refactor, hunting consolidation, deciding who
  should review, or producing a health snapshot. Reads a function's nesting PROFILE (`humps=`/`deep=`/
  `locals=`), not `nest=` alone, so a tangle and a long blocked-sequential body stop looking identical — then
  routes to ripwire-quality-bar for which refactor that shape calls for.
  Everything emits FACTS, not verdicts — you judge. Backed
  by ripwire (deterministic, on PATH). This is for an explicit risk/rot/refactor question after the target
  area is identified; cold structure mapping belongs to ripwire-orient. For any DIFF — yours or an incoming
  PR — use ripwire-change-check; this skill is whole subsystems, not diffs. A single-lens question is a
  single call — run only the lenses the question names, not the whole battery.
allowed-tools: Bash, Read
---

# Fresh-eyes risk review with ripwire

> Routing:
> • Any DIFF — your own, or an incoming PR you're reviewing — about to push or merge → **ripwire-change-check**.
> • **You have the measurement and now need the FIX** — which refactor a measured shape calls for, its
>   precondition, and the fix-then-prove loop → **ripwire-quality-bar**'s shape → refactor playbook.
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
     <doc p="docs/ARCHITECTURE.md" anchors="50" checked="34" drift="9"><a k="file-line" l="186" c="80"
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
     <fix p="docs/ARCHITECTURE.md" live="6"/> …
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

   **Two rule prefixes are also family evidence.** `naming-*` (`naming-case`/`naming-confusable`/
   `naming-predicate`/`naming-series`/`naming-setter`/`naming-short`/`naming-underscore`/`naming-wordy`) is
   exactly `--ensemble`'s/`--quality-panel`'s `lexical` family; `atom-*` (`atom-assign-as-value`/
   `atom-comma-operator`/`atom-embedded-crement`/`atom-implicit-predicate`/`atom-nested-ternary`/
   `atom-octal-literal`/`atom-reversed-subscript`) is `confusion`. A `--lint` finding under either prefix
   is the identical predicate the family join runs — reading it here just skips the join. **Not a moment to
   reach for mid-task:** `--naming-calibration` scores both spellings of this repo's own historical renames
   (old identifier vs. what it was renamed to) against the same `naming-*` predicates — it is how those
   rules were validated, a maintainer calibration harness (`test/namingcalibrationcheck.sh` pins the
   per-rule floor) with a `pairs=` sample size and its own legend calling itself a **noisy proxy**, not a
   verdict on any function you're looking at. It always exits 0.

   **The one naming lens that proposes a FIX, not just evidence — `ripwire <dir> --naming-consistency`.**
   Every other pass on this page tells you WHAT is wrong; this one is the deliberate exception, and only for
   one narrow reason: case-CONVENTION is Tier A (the research record's own tiering for "propose a fix only
   where the correct replacement is derivable from the corpus" — see `ripwire-quality-bar`'s zoom-in table
   for the other nine `--quality-delta` kinds, which stay evidence-only on purpose). It votes the corpus's
   OWN dominant case style (camel/pascal/snake/screaming) per `(language, kind)` group — decided only past a
   20-name sample floor AND 90% agreement, `UNAVAILABLE` with `why=` otherwise, never a guessed winner — and
   every off-convention name in a decided group gets `propose=`: its own subtokens mechanically recombined
   into that style. No dictionary, no synonym judgment — which is exactly why this is the one place a rename
   suggestion is safe to make. **It is still only a suggestion**, not a safe-to-blind-apply rename: applying
   one for real needs `--uses` to prove the complete reference set first. Exit 0 always, a lens like the rest
   of this page — abbreviation inconsistency and synonym unification (the other two Tier-A categories) stay
   unimplemented on purpose; both need a dictionary or a semantic judgment call this verb's design
   deliberately avoids.

   **Local-variable naming, opt-in and explicitly not the default — `ripwire <dir> --lint --naming-locals`.**
   A `--lint` modifier, not a standalone verb (a no-op without `--lint`): runs `naming-short`/`naming-wordy`/
   `naming-underscore`/`naming-case` — the same tags, same predicates as the Symbol-scoped checks above —
   against LOCAL variable names too, C/C++ only, and only where the risk is real: inside a function that
   already clears an existing size/complexity gate (`loc>80 OR nest>4 OR ccx>=15`) AND has `locals>=8`
   (measured, not guessed: median 9 among this repo's own 377 gated functions). `naming-short` additionally
   requires the local's own declaration depth `>=2` — a depth-1 `int n = argc;` never fires, a nested
   `int x` two blocks deep can. This deliberately reverses `naminglens.h`'s own stated invariant ("an
   un-indexed loop local can never be flagged") — read the WITHDRAWN note atop that file before trusting it.
   **NOT enabled inside a plain `--lint` run and not a candidate for that yet**: the plan's own hard blocker
   (a hand-curated fixture corpus AND a manual real-corpus audit for idiomatic-short-name skew — `i`/`j`/`k`/
   `buf`/`tmp`/`err`) has not run. Treat a `--naming-locals` finding as a candidate to eyeball, not a verdict,
   until that audit lands.

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

   **Per-function readability** — `ripwire <dir> --readability`
   `<readability functions="N" shown="40" capped="1"><fn p="…:512" n="buildGraph" lines="1244" toks="6753"
   ops="4359" vocab="382" vol="57923.4" ent="6.26" posnett="0.000"/>` — the Posnett/Hindle/Devanbu (MSR 2011)
   closed-form model, **least readable first**: `vol=` Halstead volume, `ent=` Shannon token entropy,
   `lines=` the definition's line span, `posnett=` the fitted sigmoid. Complements step 1: `--hotspots` ranks
   by complexity × *churn* (where pain has been paid), this ranks by how hard the text is to *read* right
   now, with no git history needed. Two caveats it states in its own legend and you should carry: one
   token-class table serves every language, so `vol=` is a cross-language approximation; and the formula was
   fitted on snippets of 20 lines or fewer, so on a 1,000-line function `posnett=` saturates at `0.000` —
   **read the ORDER of the rows, never the number as a grade.**

   **Reachable non-local mutable state** — `ripwire <dir> --nonlocal-state`
   `<fn p="src/infra/profilePmc.h:288" n="ensure_global_init" writes="2" reads="3" direct_writes="1"
   direct_reads="3" cells_total="3"><cell n="g_perf" p="…:284" dir="rw" at="…:339" at_dir="rw"/>…` — per
   function, the globals / file-scope statics / function-local statics / Python module globals it **or its
   transitive callees** touch, **most writes first**, with reads and writes kept apart. `writes=`/`reads=`
   fold in the callee closure; `direct_*` is what this body does itself; each `<cell>` names the declaration
   and either the use site here (`at=`, with `at_dir=` for what THIS body does) or the callee it came
   through (`via=`). Answers a different "is it safe to touch this?" than `--impact`: `--impact` is who
   calls you, this is what *state* you can perturb from here — the reason a change with a tiny caller set
   still breaks something across the repo. **`const`/`constexpr` declarations are not cells**, so a big
   `writes=` is genuinely shared mutable state, not a table of constants. Three things to carry: it is
   **unsound by construction** — no indirect calls, no pointer aliasing, no macro-named cells — so every
   count is a `counts_floor="1"` floor and a zero means *none found*; a local **shadowing** a cell's name
   can be charged to the cell; and it covers **C++/ObjC/Python only**, with every other indexed language
   named in `unanalyzed_langs=` on the root, which is *not measured*, not *measured zero*.

   **THE SINGLE COMMAND — `ripwire <dir> --quality-panel[=strict|default|lenient]`. When the question is
   just "where is the rot", start HERE, not at step 1.** It is the whole panel in one ranked report: the four
   families `--ensemble` joins, plus `colocation` (how much of what you must read to understand this function
   lives outside its own file) and `state` (this function's OWN BODY touching non-local mutable state) — six
   families, ranked by the count of distinct families and never by a composite.
   `<s p="./src/graph.h:462" n="buildGraph" fam="4" of="6" fired="structural,confusion,historical,colocation"
   uncounted="" unavail="" join="deep+untested"><e f="structural" counted="1" why="ccx=724 loc=1244 nest=9
   humps=30 deep=308 rrank=1"/><e f="colocation" counted="1" why="crank=33"/>…`
   Pick the preset by what you are doing, and note that a preset only **selects** families and **cuts** on the
   count — it never weights: `lenient` (all six, 1 must agree) is a *reading order*, about a third of any tree;
   `default` (all six, 2 must agree) is a review list; `strict` (the four families measured stable enough to
   stand behind a gate, 2 must agree) is the only rung to point CI at. `historical` and `colocation` are
   deliberately out of `strict` — each is a fixed-size worst-40 cut over a ranking whose population moves, so
   both re-shuffle across commits on code that did not change. A row still SHOWS them, as `uncounted=` with
   `counted="0"`, so you can see what the preset set aside. Everything the `--ensemble` paragraph below says
   about ordinal cuts and UNAVAILABLE applies here unchanged.

   **Read the structural `why=` as a PROFILE — `nest=` alone is a max, and on a subsystem you did not write
   that is exactly the wrong number to act on.** `nest=9` is one deepest line; it cannot tell a **tangled**
   body from a long **blocked-sequential** one whose max is a single inner loop. The row carries the profile
   beside it: **`humps=`** (how many maximal control-nesting regions reach the bar — CodeScene's "bumpy
   road", EXACT) and **`deep=`** (how many **LINES** lie inside them — a FLOOR, `deep_floor="1"`), against
   the `loc=` already on the row. Both are **absent exactly when `nest <` the bar** — not-deep, never a
   hidden `0` — and **`deep` below `humps` is legal output, not a defect** (`deep` counts lines, `humps`
   counts regions, and a one-line `if(c){x;}else{y;}` at the bar is two regions on one line). Two ratios do
   the discriminating: **`deep/loc`** separates tangled (high — depth is sustained) from blocked-sequential
   (low — a dispatch table or a setup block), and **`deep/humps`** separates one giant tangle (high — the
   expensive fix) from many tiny touches (low — repeated missing abstractions, each its own cheap
   extraction). `locals=` on the same row is the reader's working set — a FLOOR (`locals_floor="1"`),
   **C/C++ only**, absent rather than `0` elsewhere. **Which fix each shape calls for, and its precondition
   → ripwire-quality-bar's shape → refactor playbook.**

   **`join="deep+untested"`** is an annotation, not a seventh family: this row carries `deep=` *and* no
   indexed test reaches it. It changes nothing — not `fam=`, not `of=`, not the ordering, not which rows
   appear — and it is exactly the pair where a refactor is most wanted and least safe (**test first**,
   → **ripwire-write-tests**). It is **suppressed on every row when `tested_scope="0"`**, because on a corpus
   whose tests were never crawled "untested" describes the crawl and not the code, so read `tested_scope=` on
   the root before treating its absence as good news; `deep_untested=` counts them across the whole row set,
   which the `limit=` window does not change.

   **The `historical` family's unit is the FILE, not the symbol.** `churn=` and `hrank=` are file facts
   inherited verbatim by every symbol in that file, so a symbol in a busy file collects this family without
   any property of its own. On a subsystem read that is worth discounting explicitly: confirm at the symbol
   (`git log -p <file>`, or `--hotspots --since=`) before calling one function the churny one.

   **Corroborated rot, four families only — `ripwire <dir> --ensemble`.** The narrower join, and the one
   whose numbers are published; reach for it when you want exactly the calibrated four plus the per-file
   rollup. One lens firing is an
   opinion; the same function flagged by *several kinds of evidence at once* is a finding. `--ensemble` joins
   four **orthogonal** families — `structural` (the shape: `ccx`/`loc`/`nest`/`params` bars plus the
   readability rank), `lexical` (the `naming-*` rules on the identifier text), `confusion` (the `atom-*`
   rules on the syntactic construct), `historical` (git change frequency) — and ranks by the **count of
   distinct families**:
   `<s p="./src/graph.h:462" n="buildGraph" fam="3" of="4" fired="structural,confusion,historical"
   unavail=""><e f="structural" why="ccx=724 loc=1244 nest=9 humps=30 deep=308 rrank=1"/>…` — plus a
   per-file rollup whose `top_fam=` is the strongest single-symbol corroboration in that file. (The
   `humps=`/`deep=` profile and the per-FILE `historical` unit read exactly as in the panel above; this
   verb has no `join=` annotation.)
   **There is deliberately no composite score**: averaging correlated metrics re-weights one signal and calls
   it three (the Maintainability-Index failure), so `fam=` is ordinal and every row carries the evidence
   behind it — you never need a second command to see WHY. Two things to carry: `rrank=`/`hrank=` are
   **relative** cuts (the worst decile of *this* corpus, so something always fires), while the `ccx`/`loc`/
   `nest`/`params` bars are absolute and printed on the root; and a family that could not be measured is
   named in `unavail=` with `of=` dropping to 3 — **UNAVAILABLE is not the same as clean**, so on a corpus
   with no git history do not read the missing `historical` as "nothing is churning".

   **How much is NOT in front of you — `ripwire <dir> --context-ratio`.** The other lenses ask how hard a
   function is to read *once you have it open*; this one asks how much you must open *besides* it.
   `<s p="src/main.cpp:10177" n="main" sites="1050" ents="131" ents_out="85" ent_ratio="0.649" files="37"
   files_out="36" rtok="165317" rtok_out="61968" read_ratio="0.375" ext="141" amb="19"/>` — `ents=` distinct
   in-corpus definitions its reference sites resolve to, `ents_out=`/`ent_ratio=` how many live outside its
   own file, and `rtok=`/`rtok_out=`/`read_ratio=` the same split weighted by the **tokens a reader must
   actually read**. Read the two ratios *together*: `main` above needs 65% of its entities from elsewhere but
   only 37% of its reading volume, because the biggest things it touches are next door. A per-file rollup
   follows the symbol rows and is a **union over the whole file** (includes and imports included), not the sum
   of those rows. Three things to carry: it credits its own prior art — the fraction is Beck & Diehl's
   per-class congruence (FSE 2011) flipped, and the refinement is the reader weighting plus the use of every
   reference role, not just calls; resolution is **name-based**, so `amb=` names resolved to several
   definitions and `ents=` is a floor; and `ext=` is dominated by locals and parameters, so it is **not** an
   external-dependency count and never enters either ratio.

   **Comments that say nothing — `ripwire <dir> --comment-coherence`.** Per function/method **with a doc
   comment**, two content measures, most name-restating first: `<fn p="…:41" n="computeTotal" c_coeff="1.000"
   words="2" restate="2" cic="0.667" c_terms="2" i_terms="3" shared="2"/>`. `c_coeff` (Steidl/Hummel/Juergens,
   ICPC 2013) is the fraction of the comment's words within Levenshtein distance 2 of a word in the name —
   **HIGH is BAD**, it means the comment just restates the name (`// compute total` above `computeTotal`
   scores `c_coeff="1.000"`), the opposite of the naive "high coherence sounds good" reading. `cic`
   (Scalabrino, ICPC 2016/JSEP 2018) is the Jaccard overlap between the comment's vocabulary and the method's
   own identifier vocabulary (params, locals, callees, fields) — a different axis, expected to disagree with
   `c_coeff`, so read both rather than either alone. **UNAVAILABLE, never a zero**, where no doc comment
   exists at all (counted in `no_comment=` on the root) — this pass never guesses at an absent comment's
   quality. Different question from `--doc-drift` above: doc-drift asks whether a *markdown* claim is still
   *true*; this asks whether a *source doc-comment* carries *information* — neither checks the other's axis.

## Hidden-coupling pass — "a change here keeps breaking unrelated files"

6. **Behavioural coupling** — `ripwire <dir> --cochange`
   Bare `--cochange` emits ONLY the *surprising* pairs — files that change together in git but share **no
   static dependency** either way:
   `<cochange pairs="N" sub_windows="3"><pair a="…" b="…" together="17" deg="1.00" conf_ab="1.00"
   conf_ba="0.34" driver="a" recur="3" surprising="1"/>…`
   (`together` = commits co-appearing, `deg` = fraction of the rarer file's commits). Pure behavioural
   coupling — shared global state, parallel ownership, or an implicit protocol; statically-linked pairs are
   filtered out as expected. For ONE file's full partner list, `--cochange=FILE`.

   **Read `recur=` before you act on a row.** It is how many of the header's `sub_windows=` equal-commit-count
   slices of the window the pair actually co-changed in. `recur="1"` at any `together=` is a *single burst* —
   a refactor sprint, a rename wave — not a standing coupling, and it is the biggest source of rows that look
   alarming and are not. `ripwire <dir> --cochange --cochange-recur=2` drops them; the header then carries
   `min_recur=` so the shorter list is explained rather than mysterious.

   **`driver=` names the file to look at.** `conf_ab` is "of a's commits, the fraction that also touched b";
   `conf_ba` is the reverse. `driver="a"` means a is the one that never moves alone, so a is where the
   implicit dependency lives. `deg=` is just the larger of the two, and `driver=` is omitted on a tie.

   **`ripwire <dir> --cochange --cochange-groups`** collapses the violating pairs around the file each one
   implicates: `<group core="…" partners="3">` says "this file co-changes with three files it does not depend
   on" in one row instead of three. That is the row to act on — it names the fix target. The cover is greedy
   (`cover="greedy"`), so `groups=` is an upper bound on the minimum, not the minimum.

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

4. **Pick the fix from the SHAPE, not the score** — `ripwire <dir> --quality-panel` (or `--metrics`) on the
   cluster, then read `humps=`/`deep=`/`locals=` as above: many shallow humps → extract each one (cheap); one
   deep tangle → guard-clause inversion then state extraction (expensive); small-and-dense → read it first,
   density is often the algorithm; `join="deep+untested"` or high fan-in → **test before you touch it**. The
   full shape → fix → precondition table, and the fix-then-prove loop that closes it
   (`--quality-delta` → `--edit-check=SYM` → `--affected`), are in **ripwire-quality-bar**.

→ **Refactor brief:** the cluster to split (with its `lcom4`/`ccx` evidence and its nesting profile), the
blast radius + test gate, the co-change partners to keep in sync, and the named fix each shape calls for. For
CI-enforcing the boundary you extract → **ripwire-layers**.

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
