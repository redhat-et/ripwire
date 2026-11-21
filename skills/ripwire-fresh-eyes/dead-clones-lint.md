# ripwire-fresh-eyes — reference: dead-clones-lint (read on demand; the recipe is in SKILL.md)

2. **Dead code** — `ripwire <dir> --dead-code[=DIR] --legend=compact`
   `<dead-code count="N" evidence="internal-linkage+zero-callers"><d n="orphan" …/>` — no `confidence=`
   attribute (removed 2026-09-20: it was a fixed literal, not a derived signal) — source-defined free
   functions with explicit internal linkage and **in-degree 0** in the indexed call graph.
   `--dead-code=DIR` scopes to a sub-tree. Methods, declarations, headers, and external-linkage entry
   points are excluded, so `count="0"` means "no candidates met the evidence rule," not "no dead code."
   Name-based and tree-local — **verify before deleting**: confirm against the compiler's unused-symbol
   diagnostics or a linker map; ripwire narrows the field, the toolchain proves it.

3. **Duplicate bodies** — `ripwire <dir> --clones --legend=compact`
   `<clones groups="N" type3="M"><group type="2" tokens="161" n="2"><f n="line" p="…:31"/><f n="line"
   p="…:28"/></group>`. `type="2"` = exact/renamed (identifiers + literals normalized, so a renamed copy
   still matches); `type="3"` = a gapped NEAR-miss (similarity 0.80–1.0, an inserted/changed statement) —
   check `type=` before assuming two members are byte-identical. Larger `tokens=` = more dedup value; a fix
   to one likely belongs in all. **Rule of Three:** extract on the *third* occurrence, not the second — a
   little duplication beats the *wrong* abstraction.
   A group carrying `idiom="…"` (`threshold-ladder`, `switch-name-table`, `builder-chain`, `one-statement`, `call-sequence`)
   plus `demoted="1"` is one the detector judged an IDIOM COLLISION, not shared logic: same shape, no shared
   domain identifiers, different scopes — five unrelated bucketing ladders in five subsystems match each
   other's token stream and consolidating them would be the wrong abstraction. For `one-statement` (a body
   of one `return`) and `call-sequence` (a body of calls only, where the callees are the meaning), parameter names, `std::` names and container words like `find`/`size` do not count as
   shared, and a copy that only renamed its parameters never demotes. Demoted groups still print
   and still count; they stop *gating*. The idiom is named precisely so you can overrule it by reading the
   bodies — treat it as the tool showing its work, not as a row it decided for you.

4. **AST smells** — `ripwire <dir> --lint --legend=compact`
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

   **What rules exist, and are they even structurally possible on this corpus? — `ripwire <dir>
   --lint-catalog`.** The full built-in registry: every rule's severity, category, one-line rationale, its
   registered languages, and the release it shipped in — no corpus needed, so it answers "what could `--lint`
   ever find here" before you run it. A plain `--lint` run then discloses the corpus-specific half:
   `applicable="0"` on a `<rule>` row means none of that rule's registered languages are present at all (its
   `count="0"` is structural inertness, not a measurement — e.g. `magic-number` is C/C++/ObjC-only and reports
   `applicable="0"` on a pure-Go tree), and the root's `inert_rules=N` tallies how many rows that is true for.
   **Scoping a `--lint` run to one family — `--lint-select=PREFIX[,...]` / `--lint-ignore=PREFIX[,...]`**
   (comma-separated, `*` for "every rule"): `--lint-select=cache-` runs only the `cache-*` family, disclosing
   `selected="K of N"` on the root so a filtered zero is never confusable with an unfiltered one; an
   unresolvable PREFIX refuses with a near-miss rather than silently matching nothing.
   **A rule row with `count_capped="1"`** spent its per-rule match budget (5000 by default), so its `count=` is a FLOOR;
   the root then carries `findings_next=` — paste it: it re-runs only those rules under a 10x `--lint-max-per-rule=N`
   (SARIF: `runs[0].properties.findingsNext`), and a re-run still floored names its own.

   **The one naming lens that proposes a FIX, not just evidence — `ripwire <dir> --naming-consistency --legend=compact`.**
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

   **Local-variable naming, opt-in and explicitly not the default — `ripwire <dir> --lint --legend=compact --naming-locals`.**
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
