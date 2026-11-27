# ripwire-fresh-eyes — reference: dark-docs-plans (read on demand; the recipe is in SKILL.md)

Contents: 1b. What is BUILT but DARK here? · 1b-ii. If I flip THIS one, what lights up? · 1c. Can I TRUST this repo's docs? · 1d. Did a task in this plan just never get launched?

1b. **What is BUILT but DARK here?** — `ripwire <dir> --flags --legend=compact` (`=SUBSTR` to narrow)
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

1b-ii. **If I flip THIS one, what lights up?** — `ripwire <dir> --flags --legend=compact --flip=NAME`
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

1c. **Can I TRUST this repo's docs?** — `ripwire <dir> --doc-drift --legend=compact` (`=SUBSTR` to narrow to one doc)
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

   **Want it to BECOME a gate?** — `ripwire <dir> --doc-drift --legend=compact --gateability`. The reason CI can't gate on
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

1d. **Did a task in this plan just never get launched?** — `ripwire <dir> --plan-lint=FILE --legend=compact`. Where 1c
   explicitly does NOT check `§Status` lines, dates or "N of M done" tallies, this is the narrow
   structural check that closes that one gap — a wave-closer's job, mechanized. It is opt-in per FILE
   (never a directory sweep) because the house PLAN dialect it recognizes is deliberately narrow: a task
   card is exactly an H3 heading opening with a task id (`T5`, `T10`, `T7b`), a status ledger is exactly
   one heading (any level) reading "Status" once a leading section mark is stripped. A file showing
   neither an H3 card nor a ledger heading reports `dialect="0"` and nothing further runs — most plans
   are exactly that file, and this is not a failing lint for them.
   ```
   <plan-lint file="wave.md" dialect="1" cards="6" ledger="1" git="1" stale_commits="20" gating="1">
     <card id="T5" line="40" status="missing" why="unlaunched" gating="1"/> …
   ```
   Once `dialect="1"`: a card's status is satisfied EITHER by a glyph on the LAST non-blank line of its
   own body OR by a `§Status` ledger line naming its id — folded by DIGITS, so a bare card `T7` is also
   answered by a lettered ledger mention `T7a`/`T7b` (the real house shape when a card's own body names
   lettered sub-tasks and the ledger tracks each separately) — with the card's own body winning when it
   has one. Unresolved is `status="missing"`, with `why=` naming the exact shape: `unlaunched` (a ledger
   exists and never names this id at all — the exact field failure this verb exists to catch: a card that
   was planned but never started, silent until a human happened to notice), `unresolved` (the ledger names
   it but no line carries a glyph), or `no-glyph` (this document carries no ledger at all, so the card's
   own body was the only possible source). An hourglass line whose git-blamed commit sits more than
   `stale_commits=` commits behind HEAD is `stale="1"` (never claimed outside a git repo; blames whichever
   line the status actually resolved to, marked `src="ledger"` when that is the ledger and not the card);
   a task id named in the ledger with no matching card (same digit fold) is a `ledger-orphan`; an owed/OWED
   mention with no check-mark or cross anywhere LATER in the SAME document is undischarged.
   **Limits, stated up front:** never semantics — it does not judge whether a card's claims are true (that
   stays 1c's job); single-document only (a successor plan's discharge of an owed item is invisible here);
   substring matching on "owed"/"OWED" with no disambiguation (a doc that merely quotes the word reads the
   same as a real marker); a document that uses card headings as plain labels with NO status mechanism
   anywhere (no ledger, no glyph on any card) still reads every card as `missing` — a known, disclosed gap,
   not a guessed-at fix. Unlike `--doc-drift`'s always-0 report, this **gates**: exit 2 when `dialect="1"`
   and any row carries `gating="1"`, exit 0 clean or `dialect="0"`, exit 1 only when FILE could not be read.
