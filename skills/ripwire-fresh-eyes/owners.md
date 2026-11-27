# ripwire-fresh-eyes — reference: owners (read on demand; the recipe is in SKILL.md)

Contents: ownership and bus factor (`--owners`, `bf="1"`) · per-function size ranking · reachable non-local mutable state · the shape metrics and `join="deep+untested"` · the file-unit `historical` family · why there is no composite score

5. **Ownership / knowledge risk** — `ripwire <dir> --owners[=SYM] --legend=compact`
   `<owners files="N"><f p="…" authors="1" bf="1" top="…@…" share="1.00"/>` (recency-weighted, 6-month
   half-life). `authors=` distinct authors; `share=` the top author's fraction of weighted commits;
   **`bf="1"` = one person holds >80% (bus-factor risk)**; `top=` = who to ask / who should review.
   `--owners=SYM` resolves to just that symbol's defining file — the "who should review my change to
   `buildGraph`" answer. Measures *git authorship* (recency-biased), not who *should* own the code.
   **Worst case:** a file that's BOTH a top hotspot (step 1) AND `bf="1"` — gnarly code only one person
   understands.

   **Per-function size ranking** — `ripwire <dir> --biggest-first --legend=compact`
   `<readability functions="N" shown="40" capped="1"><fn p="…:512" n="buildGraph" lines="1244" toks="6753"
   ops="4359" vocab="382" vol="57923.4" ent="6.26" posnett="0.000"/>` — the Posnett/Hindle/Devanbu (MSR 2011)
   closed-form model, rows ordered by Halstead volume, token entropy and length, largest first: `vol=`
   Halstead volume, `ent=` Shannon token entropy, `lines=` the definition's line span, `posnett=` the fitted
   sigmoid. It needs no git history. Three caveats to carry: one token-class table serves every language, so
   `vol=` is a cross-language approximation; the formula was fitted on snippets of 20 lines or fewer, so on a
   1,000-line function `posnett=` saturates at `0.000` — never read the number as a grade; and the claim
   that the ORDER predicts which functions need a later fix is **withdrawn** — held to narrow token-count
   bands the association disappears in 8 of 10 deciles, so the order is a size proxy, not an independent
   readability signal (ripwire's `docs/EVALS.md` §8). Use it to find the largest, densest
   bodies; use `--hotspots` (step 1) for where pain has actually been paid.

   **Reachable non-local mutable state** — `ripwire <dir> --nonlocal-state --legend=compact`
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

   **THE SINGLE COMMAND — `ripwire <dir> --quality-panel[=strict|default|lenient] --legend=compact`. When the question is
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
   **C/C++ only**, absent rather than `0` elsewhere. **`ev=` on the same row (essential complexity, McCabe:
   absent/`1` = single-entry/single-exit, extract-method applies mechanically; `2+` = a jump — see
   `ev_why=`) — tells you whether the shape you are about to prescribe a fix for is a cheap lift or an
   expensive rewrite before you commit to one.** **Which fix each shape calls for, and its precondition
   → ripwire-quality-bar's shape → refactor playbook.**
   **The numbers in the example rows on this page are ILLUSTRATIVE OF A SHAPE, not values to expect** — these
   counters are under active calibration (an else-clause over-count fix in flight moves `humps=` down
   substantially, and `ccx=`/`nest=` with it, on else-heavy functions). Durable is what you do with the row:
   `humps=1` vs many, the two ratios, and the semantics above. Read the row in front of you.

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

   **Corroborated rot, four families only — `ripwire <dir> --ensemble --legend=compact`.** The narrower join, and the one
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

   **How much is NOT in front of you — `ripwire <dir> --context-ratio --legend=compact`.** The other lenses ask how hard a
   function is to read *once you have it open*; this one asks how much you must open *besides* it.
   `<s p="src/main.cpp:10177" n="main" sites="1050" ents="131" ents_out="85" ent_ratio="0.649" files="37"
   files_out="36" rtok="165317" rtok_out="61968" read_ratio="0.375" ext="141" amb_names="19"/>` — `ents=` distinct
   in-corpus definitions its reference sites resolve to, `ents_out=`/`ent_ratio=` how many live outside its
   own file, and `rtok=`/`rtok_out=`/`read_ratio=` the same split weighted by the **tokens a reader must
   actually read**. Read the two ratios *together*: `main` above needs 65% of its entities from elsewhere but
   only 37% of its reading volume, because the biggest things it touches are next door. A per-file rollup
   follows the symbol rows and is a **union over the whole file** (includes and imports included), not the sum
   of those rows. Three things to carry: it credits its own prior art — the fraction is Beck & Diehl's
   per-class congruence (FSE 2011) flipped, and the refinement is the reader weighting plus the use of every
   reference role, not just calls; resolution is **name-based**, so `amb_names=` names resolved to several
   definitions and `ents=` is a floor; and `ext=` is dominated by locals and parameters, so it is **not** an
   external-dependency count and never enters either ratio.

   **Comments that say nothing — `ripwire <dir> --comment-coherence --legend=compact`.** Per function/method **with a doc
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
