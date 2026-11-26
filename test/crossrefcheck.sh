#!/usr/bin/env bash
# crossrefcheck.sh — the gate for --stray-content and --whereis (src/crossref.h).
#
#   test/crossrefcheck.sh
#   RIPWIRE_BIN=asan/ripwire test/crossrefcheck.sh
#
# The fixture is BUILT here, not committed: these verbs read git refs, so the corpus has to be a real
# repository with a real ref graph. Fixed author/committer dates keep it byte-reproducible.
#
# The synthetic ref graph, mirroring the four cases the verbs must separate:
#   feat-unmerged   — adds a brand-new file + symbol the live line never had        -> v="unmerged"
#   feat-superseded — rewrites a base line that HEAD ALSO rewrote, differently      -> v="superseded"
#                     (this is the case `git cherry` structurally cannot see: the commit is unmerged
#                      forever, but the work is already done on the live line)
#   feat-merged     — its content is byte-present on HEAD                           -> omitted entirely
#
# Exit 0 = ALL PASS, non-zero = SOME FAILED.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"   # BOTH seams: positional and RIPWIRE_BIN
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
# Every fixture repo below is built in a hermetic git environment (gitenvhermeticcheck (D): a gate that initialises a
# repository sources the shared helper, so an inherited GIT_DIR/GIT_WORK_TREE or agent home cannot leak into it).
. "$ROOT/test/lib/clean-env.sh"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "crossrefcheck: git unavailable — skipping"; exit 0; }

R="$TMP/repo"; mkdir -p "$R"
export GIT_AUTHOR_NAME=ripwire GIT_AUTHOR_EMAIL=ripwire@example.invalid
export GIT_COMMITTER_NAME=ripwire GIT_COMMITTER_EMAIL=ripwire@example.invalid
export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z" GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"
g(){ git -C "$R" "$@" >/dev/null 2>&1; }

g init -q -b main
g config commit.gpgsign false

# ── the base commit: the fork point every branch diverges from ────────────────────────────────────────
cat > "$R/engine.cpp" <<'EOF'
#include "engine.h"

int computeBudget( int frames )
{
    return frames * 16;
}

int legacyPinnedLimit()
{
    return 10;
}
EOF
cat > "$R/engine.h" <<'EOF'
#pragma once
int computeBudget( int frames );
int legacyPinnedLimit();
EOF
g add engine.cpp engine.h
g commit -qm base

# ── feat-superseded: replaces the pinned literal with a derived value ─────────────────────────────────
g checkout -qb feat-superseded
perl -0pi -e 's/    return 10;\n/    const int derived = computeBudget( 1 ) \/ 16;\n    return derived + 9;\n/' "$R/engine.cpp"
g commit -qam "derive the limit instead of pinning 10"

# ── feat-unmerged: brand-new file the live line never had ─────────────────────────────────────────────
g checkout -q main
g checkout -qb feat-unmerged
cat > "$R/contourSynth.cpp" <<'EOF'
#include "engine.h"

// A whole feature that exists ONLY on this branch.
int reliefFirstContourIndex()
{
    return 24;
}

int reliefContourCount()
{
    return 8;
}
EOF
g add contourSynth.cpp
g commit -qm "relief contour family"

# ── feat-merged: content that ends up byte-identical on the live line ─────────────────────────────────
g checkout -q main
g checkout -qb feat-merged
printf 'int sharedHelper( int x )\n{\n    return x + 1;\n}\n' >> "$R/engine.cpp"
g commit -qam "shared helper"

# ── the live line (HEAD): rewrites the SAME base line feat-superseded rewrote, differently, and also
#    takes feat-merged's content verbatim (a real merge) ────────────────────────────────────────────────
g checkout -q main
perl -0pi -e 's/    return 10;\n/    return computeBudget( 1 ) - 6;\n/' "$R/engine.cpp"
g commit -qam "compute the limit from the budget (live line)"
g merge -q --no-edit feat-merged

# ── §P11.5: a design doc on HEAD that QUOTES the definition ───────────────────────────────────────────
# The finding --whereis had: doc-quoted code outranked the real definition, because hits sorted on
# (HEAD, ref, isDef, path) and a doc path can sort above the source path. `AAA_design.md` is named to
# sort above `engine.cpp` on purpose, and the quoted signature is definition-SHAPED, so the lexical
# heuristic classifies it kind="def" exactly as it does the real one. Added as a separate commit after
# the merge so no branch's merge base or authored-line set moves — the stray-content arms above are
# unaffected by it.
cat > "$R/AAA_design.md" <<'EOF'
# Design

The budget entry point is

    int computeBudget( int frames )
    {
        return frames * 16;
    }

and callers must not bypass it.
EOF
g add AAA_design.md
g commit -qm "design doc quoting the budget entry point"

echo "crossrefcheck: BIN=$BIN  REPO=$R"

# ── 1) determinism ────────────────────────────────────────────────────────────────────────────────────
"$BIN" "$R" --stray-content >"$TMP/a" 2>/dev/null
"$BIN" "$R" --stray-content >"$TMP/b" 2>/dev/null
if cmp -s "$TMP/a" "$TMP/b"; then ok "stray-content determinism (byte-identical)"; else no "stray-content is non-deterministic"; fi
S="$( cat "$TMP/a" )"

# ── 2) the three verdicts ─────────────────────────────────────────────────────────────────────────────
verdict_of(){ printf '%s' "$S" | tr '<' '\n' | grep "^ref name=\"$1\"" | sed -n 's/.* v="\([a-z]*\)".*/\1/p'; }

[ "$( verdict_of feat-unmerged )" = "unmerged" ] \
    && ok 'feat-unmerged -> v="unmerged" (new content the live line never had)' \
    || { no "feat-unmerged verdict = '$( verdict_of feat-unmerged )' (want unmerged)"; printf '%s\n' "$S" | head -c 1200; }

[ "$( verdict_of feat-superseded )" = "superseded" ] \
    && ok 'feat-superseded -> v="superseded" (live line rewrote the same base line — the git-cherry blind spot)' \
    || { no "feat-superseded verdict = '$( verdict_of feat-superseded )' (want superseded)"; printf '%s\n' "$S" | head -c 1200; }

[ -z "$( verdict_of feat-merged )" ] \
    && ok "feat-merged omitted (its content is on the live line)" \
    || no "feat-merged wrongly reported as '$( verdict_of feat-merged )' — merged refs must be omitted"

# ── 3) `git cherry` really does call the superseded branch unmerged — the premise of the verb ──────────
[ "$( git -C "$R" cherry HEAD feat-superseded 2>/dev/null | grep -c '^+' )" -ge 1 ] \
    && ok "git cherry still calls feat-superseded unmerged (so this verb is not redundant with it)" \
    || no "git cherry sees feat-superseded as merged — the fixture no longer models the blind spot"

# ── 4) the superseded row carries its EVIDENCE (del/redone), not just a verdict ────────────────────────
printf '%s' "$S" | tr '<' '\n' | grep -q 'file p="engine.cpp" v="superseded".*del="[1-9]' \
    && ok "superseded file row reports its deletion-site evidence (del=/redone=)" \
    || { no "superseded row missing del=/redone= evidence"; printf '%s' "$S" | tr '<' '\n' | grep 'file p=' | head -4; }

# ── 5) --whereis: a branch-only symbol, and a HEAD symbol ──────────────────────────────────────────────
"$BIN" "$R" --whereis=reliefFirstContourIndex >"$TMP/w1" 2>/dev/null
grep -q 'on-head="0"' "$TMP/w1" \
    && ok 'whereis: branch-only symbol reports on-head="0"' || { no 'whereis: expected on-head="0"'; head -c 600 "$TMP/w1"; }
grep -q 'ref="feat-unmerged"' "$TMP/w1" \
    && ok "whereis: names the branch that has it" || { no "whereis: did not name feat-unmerged"; head -c 600 "$TMP/w1"; }
grep -q 'kind="def"' "$TMP/w1" \
    && ok "whereis: classifies the definition site as def" || { no "whereis: no def-kind hit"; head -c 600 "$TMP/w1"; }

# lean-answers lane: the ordering arms below read the doc-quoting row, a kind="ref" row the DEFAULT listing counts
# rather than prints — so they read the whole list (--whereis-listing=all, the pre-listing answer), and the twin
# after them holds the same facts on the default listing.
"$BIN" "$R" --whereis=computeBudget --whereis-listing=all >"$TMP/w2" 2>/dev/null
grep -q 'on-head="1"' "$TMP/w2" \
    && ok 'whereis: a live-line symbol reports on-head="1"' || { no 'whereis: expected on-head="1"'; head -c 600 "$TMP/w2"; }
grep -q 'ref="HEAD"' "$TMP/w2" \
    && ok "whereis: HEAD is listed first" || no "whereis: HEAD missing from a live-line symbol's hits"

"$BIN" "$R" --whereis=noSuchSymbolAnywhere 2>/dev/null | grep -q 'hits="0"' \
    && ok "whereis: an absent symbol reports hits=0 (not an error)" || no "whereis: absent symbol did not report hits=0"

# ── 5b) §P11.5 — SOURCE files outrank docs, so the real definition leads ───────────────────────────────
#
# Before the fix the sort key was (HEAD, ref, isDef, path, line), so a doc path that sorts above the
# source path put doc-QUOTED code on the first screen: on this repo `--whereis=rankGraphTeleport` opened
# with three kind="def" rows into docs/captures/*.md CDATA and reached src/graph.h:1148 only on row four.
# The key now carries the path tier (source, then test, then doc) between the ref and isDef.
#
# HONESTY ARM, and it is the point: the §P11.5 tier change did NOT sharpen definitionShaped(). The doc row
# is still emitted — a gate that let it disappear would be asserting a lie. Only the PRINT ORDER changed.
#
# §A7 UPDATE (2026-07-28): what the doc row's kind= says on HEAD did change, and deliberately. HEAD rows are
# documented as the PARSED answer, so they are now labelled from the INDEX (head_labels="index"): the index
# holds no definition of computeBudget in AAA_design.md, so that row reads kind="ref". The lexical heuristic
# — and its documented residual, a quoted signature reading as a definition — still owns every NON-HEAD ref
# row, which is what arm 5's branch-only symbol above and test/selectorhonestycheck.sh both pin. The arm below
# was inverted rather than deleted: it is still the guard against the doc row being silently re-classified,
# it just now asserts the label the index actually justifies.
# The tier orders rows WITHIN one ref — the outer grouping (HEAD first, then refs by name) is unchanged
# and load-bearing — so the ordering arms read HEAD's block, which is where the doc file lives.
tr '<' '\n' <"$TMP/w2" \
    | sed -n 's/^hit ref="\([^"]*\)".* p="\([^"]*\)" l="\([0-9]*\)" kind="\([a-z]*\)".*/\1 \4 \2:\3/p' >"$TMP/w2all"
sed -n 's/^HEAD //p' "$TMP/w2all" >"$TMP/w2rows"

[ "$( sed -n 1p "$TMP/w2rows" )" = "def engine.cpp:3" ] \
    && ok "whereis: row 1 is the SOURCE definition (engine.cpp), not the doc that quotes it" \
    || { no "whereis: row 1 is '$( sed -n 1p "$TMP/w2rows" )', want 'def engine.cpp:3'"; cat "$TMP/w2rows"; }

[ "$( grep -m1 '^def ' "$TMP/w2rows" )" = "def engine.cpp:3" ] \
    && ok "whereis: the first def row is the real definition site" \
    || { no "whereis: first def row is '$( grep -m1 '^def ' "$TMP/w2rows" )'"; cat "$TMP/w2rows"; }

grep -q 'AAA_design\.md' "$TMP/w2rows" \
    && ok "whereis: the doc-quoting row is still emitted (ordering drops nothing)" \
    || { no "whereis: the doc row vanished — this is an ORDERING change, not a filter"; cat "$TMP/w2rows"; }

grep -q '^ref AAA_design\.md' "$TMP/w2rows" \
    && ok 'whereis (§A7): the demoted doc row reads kind="ref" on HEAD — the index defines nothing there' \
    || { no "whereis: the HEAD doc row is not kind=\"ref\" — HEAD labels must come from the index"; cat "$TMP/w2rows"; }

grep -q 'head_labels="index"' "$TMP/w2" \
    && ok 'whereis (§A7): head_labels="index" discloses which mechanism labelled HEAD' \
    || { no 'whereis: head_labels="index" missing on a symbol the index defines'; grep -o '<whereis[^>]*>' "$TMP/w2"; }

grep -q 'refs_scanned="' "$TMP/w2" && ! grep -q '<whereis[^>]* refs="' "$TMP/w2" \
    && ok 'whereis (§A7): the scan denominator is refs_scanned=, not refs= (--stray-content spells the MATCHED set refs=)' \
    || { no "whereis: root still carries refs= (or lost refs_scanned=)"; grep -o '<whereis[^>]*>' "$TMP/w2"; }

docRow="$(  grep -n 'AAA_design\.md' "$TMP/w2rows" | head -1 | cut -d: -f1 )"
srcRow="$(  grep -n 'engine\.'       "$TMP/w2rows" | tail -1 | cut -d: -f1 )"
[ -n "$docRow" ] && [ -n "$srcRow" ] && [ "$docRow" -gt "$srcRow" ] \
    && ok "whereis: every source row (last at $srcRow) precedes the doc row (at $docRow)" \
    || no "whereis: docs interleave with source (doc $docRow, last source $srcRow)"

# TWIN on the default listing (lean-answers lane): the same def rows in the same order (source before the doc), the
# doc-quoting kind="ref" row not dropped but COUNTED — refs count= equals the whole list's kind="ref" rows.
#
# FOLD UPDATE (lane whereis-defs-fix): the three branches all inherit base's `int computeBudget( int frames )` at
# engine.cpp:3, so the definitions page lists that line ONCE, on the first branch by name, with refs="3"
# (foldSharedBranchDefs); the whole list above (--whereis-listing=all, the untouched twin) still prints each
# branch's own row. The arm now asserts the fold's arithmetic instead of row-for-row equality: every def row of the
# default is a def row of the whole list, in the same order, and the refs= counts (1 when absent) add up to the
# whole list's def rows — nothing is dropped, it is counted.
#
# FIX ROUND 2 (rule 4, by design): a branch row is now a PARSER's label, and a branch holding HEAD's own engine.h blob
# takes HEAD's index labels: the index lists the prototype `int computeBudget( int frames );` (engine.h:2) as a
# definition site, so it is kind="def" on the three branches as it already was on HEAD (the lexical test called the
# same bytes a ref on the branches only, because the line ends in `;`). With 8 def rows against 3 refs the defs page
# is no longer the SHORTER one (2470 B vs 2439 B), so the default serves the whole list; this arm's subject is the
# defs page's fold arithmetic, so it asks for that page by name (--whereis-listing=defs). The default's choice keeps
# its own arms (L15 and pagingsweepcheck).
"$BIN" "$R" --whereis=computeBudget --whereis-listing=defs >"$TMP/w2d" 2>/dev/null
tr '<' '\n' <"$TMP/w2d" | sed -n 's/^hit ref="\([^"]*\)".* p="\([^"]*\)" l="\([0-9]*\)" kind="\([a-z]*\)".*/\1 \4 \2:\3/p' >"$TMP/w2dall"
tr '<' '\n' <"$TMP/w2d" | grep '^hit ' | grep 'kind="def"' | awk '{ n = 1; if( match( $0, / refs="[0-9]+"/ ) ) { n = substr( $0, RSTART + 7, RLENGTH - 8 ) } print n }' >"$TMP/w2dweights"
W2REFS="$( grep -c ' ref ' "$TMP/w2all" )"
W2DEFS_ALL="$( grep -c ' def ' "$TMP/w2all" )"
W2DEFS_SUM="$( awk '{s+=$1} END{print s+0}' "$TMP/w2dweights" )"
{ [ "$( grep ' def ' "$TMP/w2dall" )" = "$( grep ' def ' "$TMP/w2all" | awk '{ k = ( $1 == "HEAD" ) ? "HEAD" NR : $2 " " $3 } !seen[k]++' )" ] && ! grep -q ' ref ' "$TMP/w2dall" \
  && [ "$W2DEFS_SUM" = "$W2DEFS_ALL" ] && [ "$W2DEFS_ALL" -ge 2 ] \
  && [ "$( sed -n 1p "$TMP/w2dall" )" = "HEAD def engine.cpp:3" ] && [ "$W2REFS" -ge 1 ] \
  && grep -q "<refs count=\"$W2REFS\"" "$TMP/w2d" && grep -q 'on-head="1"' "$TMP/w2d" && grep -q 'head_labels="index"' "$TMP/w2d"; } \
    && ok "whereis (default listing twin): the def rows of the whole list, source first, shared branch lines folded (refs= sums to $W2DEFS_ALL def rows); the $W2REFS kind=\"ref\" row(s), the doc row among them, counted by <refs count=>" \
    || { no "whereis (default listing twin): the default lost a def row, folded wrongly (refs= sum $W2DEFS_SUM vs $W2DEFS_ALL def rows) or miscounted the refs"; cat "$TMP/w2dall"; grep -o '<refs [^>]*>' "$TMP/w2d"; }
# The fold's witness on this fixture: the three branches' identical engine.cpp:3 line is one row, refs="3", on the
# first branch by name, and the whole list keeps all three (a count, never a drop). Fix round 2: engine.h:2 (HEAD's own
# blob on every branch, the index's prototype definition) folds the same way — two refs="3" rows.
W2FOLDED="$( tr '<' '\n' <"$TMP/w2d" | grep -c '^hit ref="feat-merged" .*kind="def" refs="3" ' )"
[ "$W2FOLDED" -eq 2 ] && [ "$( grep -c ' def engine.cpp:3' "$TMP/w2all" )" -eq 4 ] && [ "$( grep -c ' def engine.h:2' "$TMP/w2all" )" -eq 4 ] && ! grep -q ' refs="' "$TMP/w2" \
    && ok 'whereis (fold): the branches'"'"' shared engine.cpp:3 and engine.h:2 definitions are one row each, refs="3" on feat-merged; listing=all keeps all eight rows and carries no refs=' \
    || { no "whereis (fold): expected two feat-merged def rows with refs=\"3\" (got $W2FOLDED) and 4+4 engine.cpp:3/engine.h:2 def rows in the whole list"; cat "$TMP/w2dall"; }

# The finding's own repro, on this repo, when it is a git tree deep enough to answer. Skipped rather
# than failed on a shallow/absent checkout: this arm is a bonus over the fixture arms above, which
# already pin the ordering deterministically.
if git -C "$ROOT" rev-parse --verify -q HEAD >/dev/null 2>&1; then
    "$BIN" "$ROOT" --whereis=rankGraphTeleport >"$TMP/wreal" 2>/dev/null
    tr '<' '\n' <"$TMP/wreal" | sed -n 's/^hit .* p="\([^"]*\)" l="\([0-9]*\)" kind="\([a-z]*\)".*/\3 \1/p' >"$TMP/wrealrows"
    firstRealDef="$( grep -m1 '^def ' "$TMP/wrealrows" )"
    case "$firstRealDef" in
        "def src/graph.h") ok "whereis: rankGraphTeleport's first def row is src/graph.h (was a docs/captures CDATA row)" ;;
        "")                ok "whereis: rankGraphTeleport not found in this checkout — real-repo arm skipped" ;;
        *)                 no "whereis: rankGraphTeleport's first def row is '$firstRealDef', want src/graph.h" ;;
    esac
else
    ok "whereis: repo root is not a git tree — real-repo arm skipped"
fi

# ── 5b) --whereis on the OTHER refs: kind="def" only where a parser finds the definition, and the definitions page
#        lists a line that several refs hold ONCE (refs="N") ──────────────────────────────────────────────────────
# The 26b sweep (ideas-fable-26b #9): with the definitions page listing every kind="def" row of every ref, a defs="1"
# symbol listed 2113 "definitions" — 59 of the first 60 were call sites that merely ended in `}` or `)`
# (`if( !task.empty() ) { out += escapeXml( task, esc ); }`), a string literal's `impl `, a comment's `def `, and every
# ref's own copy of the one real line. Its own fixture: three branches hold the same shapes.cpp / calls.js (shape-b
# byte-identical to shape-a, shape-c with one extra comment line so its lines are numbered differently), beside the
# call shapes of C++, Python, JS, a string literal, a shell comment and a using-declaration. HEAD defines the name in
# budget.cpp, so HEAD's label comes from the index.
# FIX ROUND 2: every branch row is now a PARSER's label too (labelBranchRowsByParse): a branch holding HEAD's own blob of
# a path takes HEAD's index labels, any other blob holding a parse-worthy line is parsed by the index's own extraction.
SH="$TMP/shapes"; mkdir -p "$SH"
gs(){ git -C "$SH" "$@" >/dev/null 2>&1; }
gs init -q -b main
gs config commit.gpgsign false
printf '#pragma once\nint computeBudget( int frames );\n' > "$SH/budget.h"
printf 'int computeBudget( int frames )\n{\n    return frames * 16;\n}\n' > "$SH/budget.cpp"
gs add budget.h budget.cpp
gs commit -qm base
write_shapes(){   # $1 = extra leading comment lines for shapes.cpp (shifts every line number)
    { printf '%s' "$1"; cat <<'EOF'
#include "budget.h"
static int computeBudget( int frames ) { return frames * 32; }
auto computeBudget( long frames ) -> long { return frames; }
int notADef( int total )
{
    if( total == 0 ) { total += computeBudget( 1 ); }
    if( total == 1 ) { computeBudget( 2 ); }
    return computeBudget( 3 );
}
EOF
    } > "$SH/shapes.cpp"
    printf 'if computeBudget( 7 ):\n    pass\nx = computeBudget( 8 )\n' > "$SH/calls.py"
    printf 'await computeBudget( 9 )\ncomputeBudget( 10 ).then( x => x )\nclass Budget {\n  computeBudget( frames ) {\n    return frames\n  }\n}\n' > "$SH/calls.js"
    printf 'w.write( "<impl n=\\"" );  w.write( computeBudget( 11 ) );\nusing ns::computeBudget;\n' > "$SH/w.cpp"
    printf '# 0 def rows in computeBudget( 12 ) hits\n' > "$SH/note.sh"
}
gs checkout -qb shape-a
write_shapes ""
gs add shapes.cpp calls.py calls.js w.cpp note.sh
gs commit -qm "the shapes"
gs checkout -qb shape-b
printf 'unrelated\n' > "$SH/other.txt"
gs add other.txt
gs commit -qm "shape-b: the same shapes, plus an unrelated file"
gs checkout -q main
gs checkout -qb shape-c
write_shapes "// shape-c: one more line above, so every line number differs from shape-a's
"
gs add shapes.cpp calls.py calls.js w.cpp note.sh
gs commit -qm "shape-c: the same lines, numbered differently"
gs checkout -q main

"$BIN" "$SH" --whereis=computeBudget >"$TMP/sd" 2>/dev/null; rcSd=$?
"$BIN" "$SH" --whereis=computeBudget --whereis-listing=all >"$TMP/sa" 2>/dev/null; rcSa=$?
rows_of(){ tr '<' '\n' <"$1" | sed -n 's/^hit ref="\([^"]*\)".* p="\([^"]*\)" l="\([0-9]*\)" kind="\([a-z]*\)"\( test_local="1"\)\{0,1\}\( refs="[0-9]*"\)\{0,1\} t=.*/\1 \4 \2:\3\6/p'; }
rows_of "$TMP/sd" >"$TMP/sdrows"; rows_of "$TMP/sa" >"$TMP/sarows"
if [ $rcSd -ne 0 ] || [ $rcSa -ne 0 ] || ! grep -q '<whereis ' "$TMP/sd" || ! grep -q '<whereis ' "$TMP/sa"; then
    no "whereis (shapes): the fixture produced no <whereis> root (rc $rcSd / $rcSa)"
else
    # (i) RED on 93aeab1d: the nine call shapes read kind="def" on every branch. Every branch def row is one of the
    #     three definition shapes — the one-line body, the trailing return and the JS method — and no other line.
    #     Fix round 2 (rule 4, by design): plus budget.h's prototype `int computeBudget( int frames );` — HEAD's own
    #     budget.h blob on every branch takes HEAD's index label, and the index lists that prototype as a definition
    #     site (HEAD said def and the branches said ref for the same bytes; now both say def).
    DEF_T="$( tr '<' '\n' <"$TMP/sa" | grep '^hit ref="shape-' | grep 'kind="def"' | sed -n 's/.* t="\(.*\)"\/>$/\1/p' | sort -u )"
    EXPECT_T="$( printf '%s\n' 'computeBudget( frames ) {' 'auto computeBudget( long frames ) -&gt; long { return frames; }' 'static int computeBudget( int frames ) { return frames * 32; }' 'int computeBudget( int frames )' 'int computeBudget( int frames );' | sort -u )"
    [ "$DEF_T" = "$EXPECT_T" ] \
        && ok 'whereis (shapes): on the branches only the definition shapes read kind="def" (base'"'"'s budget.cpp, the one-line body, the trailing return, the JS method)' \
        || { no 'whereis (shapes): a call shape reads kind="def" on a branch, or a definition shape lost its label'; printf '%s\n' "$DEF_T"; }
    # (ii) each call shape is a kind="ref" row (present, labelled ref): the fix relabels, it never drops.
    missing=""
    for shape in 'total += computeBudget( 1 ); }' '{ computeBudget( 2 ); }' 'return computeBudget( 3 );' 'if computeBudget( 7 ):' 'x = computeBudget( 8 )' \
                 'await computeBudget( 9 )' 'computeBudget( 10 ).then' '&lt;impl n=' '0 def rows' 'using ns::computeBudget;'; do
        tr '<' '\n' <"$TMP/sa" | grep '^hit ref="shape-a"' | grep 'kind="ref"' | grep -qF "$shape" || missing="$missing [$shape]"
    done
    [ -z "$missing" ] \
        && ok 'whereis (shapes): the C++, Python, JS, string-literal, comment and using-declaration call shapes are kind="ref" rows on shape-a' \
        || { no "whereis (shapes): call shapes not found as kind=\"ref\" rows:$missing"; grep '^shape-a' "$TMP/sarows"; }
    # (iii) the fold: the definitions page lists each shared line once, on shape-a (first by name), refs="3" — shape-c
    #       holds the same text at other line numbers and still folds (the key is path + text, not the line).
    #       The base's budget.cpp:1 is on every branch too, so four shared lines: HEAD's two index rows + four shape-a rows.
    #       Fix round 2: five — budget.h:2 (HEAD's index label on HEAD's own blob, see (i)) folds as well: folded="10".
    [ "$( grep -c '^shape-a def .* refs="3"' "$TMP/sdrows" )" -eq 5 ] && ! grep -q '^shape-[bc] ' "$TMP/sdrows" \
      && [ "$( sed -n 1p "$TMP/sdrows" )" = "HEAD def budget.cpp:1" ] && [ "$( grep -c ' def ' "$TMP/sdrows" )" -eq 7 ] \
      && grep -q '^shape-c def shapes.cpp:3$' "$TMP/sarows" && grep -q '^shape-a def shapes.cpp:2 refs="3"' "$TMP/sdrows" \
      && grep -o '<whereis [^>]*>' "$TMP/sd" | grep -q ' listing="defs" folded="10" ' \
        && ok 'whereis (fold): the five shared definition lines are one row each on shape-a with refs="3" (folded="10" on the root); shape-c holds one at another line number and folds by text' \
        || { no 'whereis (fold): expected HEAD + five shape-a rows refs="3" and folded="10" on the definitions page'; cat "$TMP/sdrows"; grep -o '<whereis [^>]*>' "$TMP/sd"; }
    # (iv) the whole list is the untouched twin: every branch's own row, no refs=/folded= anywhere, rows == hits=.
    SA_HITS="$( grep -o '<whereis [^>]*' "$TMP/sa" | grep -o ' hits="[0-9]*"' | grep -o '[0-9]*' )"
    SA_ROWS="$( grep -c . "$TMP/sarows" )"
    #      Fix round 2: 17 def rows = HEAD's 2 + 3 branches x 5 (budget.h:2 included, see (i)).
    [ -n "$SA_HITS" ] && [ "$SA_ROWS" = "$SA_HITS" ] && ! grep -q ' refs="' "$TMP/sa" && ! grep -q ' folded="' "$TMP/sa" && [ "$( grep -c ' def ' "$TMP/sarows" )" -eq 17 ] \
        && ok "whereis (fold twin): --whereis-listing=all prints every row ($SA_ROWS == hits=$SA_HITS), 17 def rows, no refs= or folded=" \
        || { no "whereis (fold twin): rows $SA_ROWS vs hits=$SA_HITS, def rows $( grep -c ' def ' "$TMP/sarows" ) (want 17), or refs=/folded= leaked into the whole list"; grep -o '<whereis [^>]*>' "$TMP/sa"; }
    # (v) the counts agree across the two pages: hits= identical, and <refs count=> on the default equals the whole list's ref rows.
    SD_HITS="$( grep -o '<whereis [^>]*' "$TMP/sd" | grep -o ' hits="[0-9]*"' | grep -o '[0-9]*' )"
    [ "$SD_HITS" = "$SA_HITS" ] && grep -q "<refs count=\"$( grep -c ' ref ' "$TMP/sarows" )\"" "$TMP/sd" \
        && ok "whereis (fold): hits=$SD_HITS on both pages; <refs count=> equals the whole list's kind=\"ref\" rows" \
        || { no "whereis (fold): hits= or <refs count=> disagree between the pages"; grep -o '<whereis [^>]*>' "$TMP/sd"; grep -o '<refs [^>]*>' "$TMP/sd"; }
    # (vi) the legend defines refs= where it rides (full prose and compact dictionary), and the full page stays well-formed XML
    #      with the SHARED DEFINITIONS clause spliced into its comment (checklist 25: no `--` inside it).
    "$BIN" "$SH" --whereis=computeBudget --legend=full >"$TMP/sdf" 2>/dev/null
    "$BIN" "$SH" --whereis=computeBudget --legend=compact >"$TMP/sdc" 2>/dev/null
    if command -v xmllint >/dev/null 2>&1; then
        xmllint --noout "$TMP/sdf" 2>/dev/null && grep -q 'SHARED DEFINITIONS: refs="N"' "$TMP/sdf" \
            && ok 'whereis (fold legend): the full legend defines refs= (SHARED DEFINITIONS) and the page is well-formed XML' \
            || no 'whereis (fold legend): the full page is malformed or its legend does not define refs='
    else
        printf '  SKIP  whereis (fold legend): xmllint absent — the full page'"'"'s well-formedness is not checked\n'   # rv N2: a missing tool is a named SKIP
        grep -q 'SHARED DEFINITIONS: refs="N"' "$TMP/sdf" && ok 'whereis (fold legend): the full legend defines refs= (SHARED DEFINITIONS)' \
            || no 'whereis (fold legend): the full legend does not define refs='
    fi
    grep -q 'hit refs=N' "$TMP/sdc" \
        && ok 'whereis (fold legend): the compact dictionary defines hit refs=N on the page that carries it' \
        || no 'whereis (fold legend): the compact dictionary lacks the hit refs=N reading'
    "$BIN" "$SH" --whereis=computeBudget --whereis-listing=all --legend=compact >"$TMP/sac" 2>/dev/null; rcSac=$?
    # rv N1: an ABSENCE is read only off a run that succeeded and printed its <whereis> root.
    [ $rcSac -eq 0 ] && grep -q '<whereis ' "$TMP/sac" && ! grep -q 'hit refs=N' "$TMP/sac" && ! grep -q 'SHARED DEFINITIONS' "$TMP/sa" \
        && ok 'whereis (fold legend): neither legend carries the refs= reading on the whole list, which never prints it' \
        || no 'whereis (fold legend): the refs= reading rides a page without the attribute'
fi

# ── 6) refusals: bare --whereis, and a non-git root ────────────────────────────────────────────────────
if "$BIN" "$R" --whereis >/dev/null 2>&1;                 [ $? -eq 1 ]; then ok "bare --whereis refuses loudly (exit 1)"; else no "bare --whereis did not exit 1"; fi
mkdir -p "$TMP/plain"; printf 'int main(){return 0;}\n' > "$TMP/plain/m.cpp"
if "$BIN" "$TMP/plain" --stray-content >/dev/null 2>&1;   [ $? -eq 1 ]; then ok "--stray-content on a non-git root refuses loudly (exit 1)"; else no "--stray-content on a non-git root did not exit 1"; fi

# ── 7) the per-blob economy: N refs cost far less than N trees ─────────────────────────────────────────
BLOBS="$( printf '%s' "$S" | sed -n 's/.*<stray-content [^>]*blobs="\([0-9]*\)".*/\1/p' )"
REFS="$(  printf '%s' "$S" | sed -n 's/.*<stray-content [^>]*refs="\([0-9]*\)".*/\1/p' )"
[ -n "$BLOBS" ] && [ -n "$REFS" ] && [ "$BLOBS" -lt $(( REFS * 6 )) ] \
    && ok "per-blob dedup holds ($REFS refs -> $BLOBS distinct blobs)" \
    || no "blob count $BLOBS looks un-deduped for $REFS refs"

# ── 8) the labelled eval (--eval-stray): scores the CLASSIFIER, not a ranking ─────────────────────────
printf 'feat-unmerged\tunmerged\nfeat-superseded\tsuperseded\nfeat-merged\tmerged\n' > "$TMP/labels.tsv"
"$BIN" "$R" --eval-stray="$TMP/labels.tsv" >"$TMP/ev" 2>/dev/null; ev=$?
grep -q 'accuracy="100.0"' "$TMP/ev" && [ $ev -eq 0 ] \
    && ok "--eval-stray scores 3/3 on the labelled fixture (exit 0)" \
    || { no "--eval-stray did not score 100% (exit $ev)"; head -c 700 "$TMP/ev"; }

# A wrong label MUST fail the eval — otherwise the eval cannot detect a threshold regression at all.
printf 'feat-unmerged\tsuperseded\n' > "$TMP/badlabels.tsv"
"$BIN" "$R" --eval-stray="$TMP/badlabels.tsv" >/dev/null 2>&1
[ $? -eq 3 ] && ok "--eval-stray exits 3 on a mislabelled case (it can actually fail)" \
             || no "--eval-stray did not exit 3 on a deliberately wrong label"

"$BIN" "$R" --eval-stray="$TMP/nosuchfile.tsv" >/dev/null 2>&1
if [ $? -eq 1 ]; then ok "--eval-stray refuses loudly on a missing labels file"; else no "--eval-stray did not exit 1 on a missing file"; fi

# ── 8b) H13: a label naming a ref this repo does NOT have is refused, never scored as "merged" ──────────
# Before the fix, a ref absent from the classifier's report defaulted straight to Verdict::Merged with no
# check that the ref even exists — a fixture labelling three refs that were never real branches scored
# accuracy=66.7% on nothing (two nonexistent refs credited as correctly "merged"). The file reads fine and
# $R is a real git repo, so the OLD refusal message ("cannot read … or not a git repository") would be a
# lie here too; the new one must name the bogus ref instead.
printf 'zz-nonexistent-ref-h13\tmerged\n' > "$TMP/badref.tsv"
"$BIN" "$R" --eval-stray="$TMP/badref.tsv" >"$TMP/badref.out" 2>"$TMP/badref.err"; badRc=$?
[ "$badRc" -eq 1 ] \
    && ok "H13: --eval-stray refuses (exit 1) on a label whose ref does not exist" \
    || no "H13: --eval-stray exited $badRc (want 1) on a nonexistent-ref label"
grep -q 'zz-nonexistent-ref-h13' "$TMP/badref.err" \
    && ok "H13: the refusal NAMES the nonexistent ref" \
    || { no "H13: the refusal does not name the bad ref"; cat "$TMP/badref.err"; }
[ ! -s "$TMP/badref.out" ] \
    && ok "H13: the refused run wrote nothing to stdout (no accuracy computed on a bogus label)" \
    || { no "H13: the refused run still emitted a <stray-eval> report"; head -c 300 "$TMP/badref.out"; }

# Mixed file: one real (merged) ref plus one bogus ref — still refuses, and only the bogus one wins the
# blame (a real, correctly-scoreable label must not get silently swallowed by an unrelated bad one).
printf 'feat-merged\tmerged\nzz-nonexistent-ref-h13\tunmerged\n' > "$TMP/mixedref.tsv"
"$BIN" "$R" --eval-stray="$TMP/mixedref.tsv" >/dev/null 2>"$TMP/mixedref.err"; mixedRc=$?
[ "$mixedRc" -eq 1 ] && grep -q 'zz-nonexistent-ref-h13' "$TMP/mixedref.err" && ! grep -q '^feat-merged$' "$TMP/mixedref.err" \
    && ok "H13: a mixed file refuses naming ONLY the ref that does not exist (feat-merged is real)" \
    || { no "H13: mixed-file refusal did not isolate the bogus ref"; cat "$TMP/mixedref.err"; }

# unknown= is its own disclosed bucket on the root — never silently absorbed into correct/incorrect.
grep -q 'unknown="' "$TMP/ev" \
    && ok "H13: <stray-eval> discloses unknown= on the root (its own bucket, not folded into merged)" \
    || { no "H13: <stray-eval> root has no unknown= attribute"; head -c 300 "$TMP/ev"; }

# ── 9) well-formed, minified XML (G4) ─────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    if "$BIN" "$R" --stray-content 2>/dev/null | xmllint --noout - 2>/dev/null; then ok "stray-content XML well-formed"; else no "stray-content XML malformed"; fi
    if "$BIN" "$R" --whereis=computeBudget 2>/dev/null | xmllint --noout - 2>/dev/null; then ok "whereis XML well-formed"; else no "whereis XML malformed"; fi
else
    ok "xmllint unavailable — XML well-formedness skipped"
fi
if [ "$( grep -c '' "$TMP/a" )" -le 1 ]; then ok "output is minified (no stray newlines)"; else no "output contains newlines outside CDATA"; fi

# ── 10) §B8.2 — THE SECOND TRUNCATION VOCABULARY IS DEFINED WHERE IT IS EMITTED ───────────────────────
# Both verbs emit a `<more X="N"/>` remainder element. It is count-accurate and deliberate, and it was
# defined NOWHERE in either payload legend, while pageview.h's own doctrine calls shown=/capped=/next_offset=
# "the ONLY paging vocabulary". A reader who meets `<more hits="12"/>` has no way to learn whether it is a
# second cap they must page past or the same fact from the other end. The legend now says which.
legend_of(){ printf '%s' "$1" | grep -oE '<!--.*?-->' | head -1; }

# L1 (2026-09-19): the CLI default legend is compact; §B8.2/§B12.2/§B11.2 read the FULL legend prose and count real <hit> rows
# (the compact legend spells row shapes inside its comment), so these documents ask for the full legend.
# lean-answers lane: the arithmetic below is over the WHOLE list (hits=), so it pages listing=all; the twin after it
# holds the default listing's own sum (shown + more + refs count = hits).
W1="$( "$BIN" "$R" --whereis=computeBudget --limit=1 --legend=full --whereis-listing=all 2>/dev/null )"
WLEG="$( legend_of "$W1" )"
{ printf '%s' "$WLEG" | grep -q 'TRUNCATION' && printf '%s' "$WLEG" | grep -q 'more hits=N'; } \
    && ok "§B8.2 whereis: the legend DEFINES its own <more hits=> remainder" \
    || { no "§B8.2 whereis: <more hits=> is emitted and defined nowhere in the legend"; printf '%s\n' "$WLEG"; }
printf '%s' "$WLEG" | grep -q 'not a second cap' \
    && ok "§B8.2 whereis: the legend says it is NOT a second cap (the pageview.h doctrine holds)" \
    || no "§B8.2 whereis: the legend does not relate <more> to shown=/capped=/next_offset="

# ARITHMETIC, not prose: shown + more == the rows from this page's offset on.
W_SHOWN="$( printf '%s' "$W1" | grep -oE '<whereis [^>]*' | grep -oE 'shown="[0-9]+"' | grep -oE '[0-9]+' )"
W_HITS="$(  printf '%s' "$W1" | grep -oE '<whereis [^>]*' | grep -oE ' hits="[0-9]+"' | grep -oE '[0-9]+' )"
W_MORE="$(  printf '%s' "$W1" | grep -oE '<more hits="[0-9]+"' | grep -oE '[0-9]+' )"
W_ROWS="$(  printf '%s' "$W1" | grep -oE '<hit ' | grep -c '' )"
if [ -n "$W_MORE" ]; then
    { [ "$(( W_SHOWN + W_MORE ))" = "$W_HITS" ] && [ "$W_ROWS" = "$W_SHOWN" ]; } \
        && ok "§B8.2 whereis: shown($W_SHOWN) + more($W_MORE) == hits($W_HITS), and $W_ROWS rows were really emitted" \
        || no "§B8.2 whereis: shown=$W_SHOWN more=$W_MORE hits=$W_HITS rows=$W_ROWS — the remainder does not add up"
    # past-the-end page: the element must VANISH exactly when nothing is left, never print more="0".
    WEND="$( "$BIN" "$R" --whereis=computeBudget --limit=1 --offset="$W_HITS" --whereis-listing=all 2>/dev/null )"
    # the absence is read only off a run that produced its <whereis> root (a crash prints nothing and has no <more> either)
    if ! printf '%s' "$WEND" | grep -q '<whereis '; then
        no "§B8.2 whereis: the past-the-end page produced no <whereis> root"
    elif printf '%s' "$WEND" | grep -q '<more '; then
        no "§B8.2 whereis: a past-the-end page still emits a <more> remainder"
    else
        ok "§B8.2 whereis: the <more> remainder is absent on a page with nothing left"
    fi
else
    no "§B8.2 whereis: --limit=1 produced no <more hits=> to check (fixture has too few hits)"
fi
# TWIN on the default listing: the same arithmetic, the counted refs included — shown + more + refs count == hits.
# Fix round 2 (by design, see the default listing twin in 5b): on this fixture the defs page is no longer the shorter
# one, so the default serves the whole list; the arm names the defs page (--whereis-listing=defs) whose arithmetic it pins.
W1D="$( "$BIN" "$R" --whereis=computeBudget --whereis-listing=defs --limit=1 2>/dev/null )"
WD_SHOWN="$( printf '%s' "$W1D" | grep -oE '<whereis [^>]*' | grep -oE 'shown="[0-9]+"' | grep -oE '[0-9]+' )"
WD_HITS="$(  printf '%s' "$W1D" | grep -oE '<whereis [^>]*' | grep -oE ' hits="[0-9]+"' | grep -oE '[0-9]+' )"
WD_MORE="$(  printf '%s' "$W1D" | grep -oE '<more hits="[0-9]+"' | grep -oE '[0-9]+' )"
WD_REFS="$(  printf '%s' "$W1D" | grep -oE '<refs count="[0-9]+"' | grep -oE '[0-9]+' )"
WD_ROWS="$(  printf '%s' "$W1D" | sed 's/<!--.*-->//' | grep -oE '<hit ' | grep -c '' )"
# FOLD UPDATE (lane whereis-defs-fix): the branches' shared definition line is one row (refs="3"), and the root's folded=
# counts the two rows it stands for — shown + more + folded + refs count == hits. The whole-list arm above is the
# untouched twin (no folded= there: rows == hits).
WD_FOLDED="$( printf '%s' "$W1D" | grep -oE '<whereis [^>]*' | grep -oE ' folded="[0-9]+"' | grep -oE '[0-9]+' )"
{ [ -n "$WD_MORE" ] && [ -n "$WD_REFS" ] && [ "$(( WD_SHOWN + WD_MORE + ${WD_FOLDED:-0} + WD_REFS ))" = "$WD_HITS" ] && [ "$WD_ROWS" = "$WD_SHOWN" ]; } \
    && ok "§B8.2 whereis (default listing twin): shown($WD_SHOWN) + more($WD_MORE) + folded(${WD_FOLDED:-0}) + refs count($WD_REFS) == hits($WD_HITS)" \
    || no "§B8.2 whereis (default listing twin): shown=$WD_SHOWN more=$WD_MORE folded=${WD_FOLDED:-0} refs=$WD_REFS hits=$WD_HITS rows=$WD_ROWS"
[ "$WD_FOLDED" = "4" ] \
    && ok '§B8.2 whereis (default listing twin): folded="4" on the root — the two branch copies each of engine.cpp:3 and engine.h:2 behind the two refs="3" rows' \
    || no "§B8.2 whereis (default listing twin): folded=\"${WD_FOLDED:-absent}\" on the root, want 4"
WDEND="$( "$BIN" "$R" --whereis=computeBudget --whereis-listing=defs --limit=1 --offset="$WD_HITS" 2>/dev/null )"
if ! printf '%s' "$WDEND" | grep -q '<whereis '; then
    no "§B8.2 whereis (default listing twin): the past-the-end page produced no <whereis> root"
elif printf '%s' "$WDEND" | grep -q '<more '; then
    no "§B8.2 whereis (default listing twin): a past-the-end page still emits a <more> remainder"
else
    ok "§B8.2 whereis (default listing twin): no <more> past the end (the <refs> count is not a page remainder)"
fi

# the stray-content sibling: force the per-ref file listing (capped at 12) past its cap on its own branch.
g checkout -q main
g checkout -qb feat-wide
i=1; while [ $i -le 15 ]; do printf 'int wideOnly%02d( int v ) { return v + %d; }\n' "$i" "$i" > "$R/wide$i.cpp"; i=$(( i + 1 )); done
g add -A; g commit -qm "15 files only this branch has"
g checkout -q main
SW="$( "$BIN" "$R" --stray-content --legend=full 2>/dev/null )"
SLEG="$( legend_of "$SW" )"
{ printf '%s' "$SLEG" | grep -q 'TRUNCATION' && printf '%s' "$SLEG" | grep -q 'more files=N'; } \
    && ok "§B8.2 stray-content: the legend DEFINES its own <more files=> remainder" \
    || { no "§B8.2 stray-content: <more files=> is emitted and defined nowhere in the legend"; printf '%s\n' "$SLEG"; }
WIDE_ROW="$( printf '%s' "$SW" | tr '<' '\n' | grep -n '^ref name="feat-wide"' | cut -d: -f1 )"
S_FILES="$( printf '%s' "$SW" | tr '<' '\n' | grep '^ref name="feat-wide"' | grep -oE ' files="[0-9]+"' | grep -oE '[0-9]+' )"
S_MORE="$( printf '%s' "$SW" | sed 's/.*name="feat-wide"//' | grep -oE '<more files="[0-9]+"' | head -1 | grep -oE '[0-9]+' )"
S_ROWS="$( printf '%s' "$SW" | sed 's/.*name="feat-wide"//' | sed 's|</ref>.*||' | grep -oE '<file ' | grep -c '' )"
if [ -n "${S_MORE:-}" ] && [ -n "$WIDE_ROW" ]; then
    [ "$(( S_ROWS + S_MORE ))" = "$S_FILES" ] \
        && ok "§B8.2 stray-content: rows($S_ROWS) + more($S_MORE) == files($S_FILES) on the capped ref" \
        || no "§B8.2 stray-content: rows=$S_ROWS more=$S_MORE files=$S_FILES — the remainder does not add up"
    "$BIN" "$R" --stray-content --detail 2>/dev/null | sed 's/.*name="feat-wide"//' | sed 's|</ref>.*||' | grep -q '<more ' \
        && no "§B8.2 stray-content: --detail (uncapped) still emits a per-ref remainder" \
        || ok "§B8.2 stray-content: --detail lifts the cap and the remainder disappears"
else
    no "§B8.2 stray-content: the 15-file branch did not produce a capped ref listing"
fi

# ── 11) §B12.2 — "every ref" MEANS refs/heads, and the payload says so ────────────────────────────────
# Both legends over-claimed ("every ref", "across ALL branches") where only --help said "local". On a fresh
# clone — all work under refs/remotes/origin/*, the standard CI and agent shape — that covers ~nothing.
# The behavioural half is asserted first, so the clause is pinned to a FACT and not merely to its own words.
g update-ref refs/remotes/origin/ghost-branch "$( git -C "$R" rev-parse feat-unmerged )"
SR="$( "$BIN" "$R" --stray-content --legend=full 2>/dev/null )"
WR="$( "$BIN" "$R" --whereis=reliefFirstContourIndex --legend=full 2>/dev/null )"
{ printf '%s' "$SR" | grep -q 'ghost-branch' || printf '%s' "$WR" | grep -q 'ghost-branch'; } \
    && no "§B12.2 premise broken: a refs/remotes ref WAS scanned — the finding's factual basis changed" \
    || ok "§B12.2 behaviour: a refs/remotes/* ref is invisible to both verbs (the fact the clause discloses)"
for pair in "whereis:$WR" "stray-content:$SR"; do
    _name="${pair%%:*}"; _doc="${pair#*:}"; _leg="$( legend_of "$_doc" )"
    { printf '%s' "$_leg" | grep -q 'SCOPE: refs/heads only' && printf '%s' "$_leg" | grep -q 'FRESH CLONE'; } \
        && ok "§B12.2 $_name: the payload legend states the refs/heads scope and the fresh-clone consequence" \
        || { no "§B12.2 $_name: the payload legend still over-claims its ref coverage"; printf '%s\n' "$_leg"; }
done
printf '%s' "$WR" | grep -oE '<!--.*?-->' | head -1 | grep -q 'every ref whose TREE' \
    && no "§B12.2 whereis: the legend still opens with the unqualified 'every ref'" \
    || ok "§B12.2 whereis: the opening clause is qualified (every LOCAL ref)"

# no plan coordinate may reach emitted text — state the RULE, never the ID (w3fixlegendcheck's sweep, local copy)
if printf '%s%s' "$WR" "$SR" | grep -qE '§[A-Z]?[0-9]+(\.[0-9]+)*'; then
    no "§B8.2/§B12.2: a plan coordinate leaked into emitted legend text"
else
    ok "§B8.2/§B12.2: no plan coordinate in emitted text"
fi

# ── 12) §B11.2 — A ZERO THAT IS A SPELLING FACT SAYS SO ───────────────────────────────────────────────
# --whereis takes a BARE name. Handed the file:name spelling nine other verbs accept, it searched for the
# literal, found it nowhere, and answered hits="0" — true, useless, and byte-identical to the answer for a
# name this repo never had. The whole point is that the two zeros must now differ; the arms below assert
# BOTH directions, because a guard that fires on everything is as useless as one that fires on nothing.
qz(){ "$BIN" "$R" --whereis="$1" "${@:2}" 2>/dev/null; }
note_of(){ printf '%s' "$1" | grep -oE '<selector-note [^>]*/>'; }

Q="$( qz "engine.cpp:computeBudget" )"
GEN="$( qz "totallyNoSuchSymbolAnywhere" )"
{ printf '%s' "$Q" | grep -q 'hits="0"' && [ -n "$( note_of "$Q" )" ]; } \
    && ok "§B11.2 a file:name spelling's zero carries a selector-note" \
    || { no "§B11.2 a file:name spelling still answers a bare, confident hits=\"0\""; printf '%s\n' "$Q" | sed 's/.*-->//'; }
note_of "$Q" | grep -q 'retry="computeBudget"' \
    && ok "§B11.2 the note hands back the BARE name to retry with" \
    || { no "§B11.2 the note does not name the retry spelling"; note_of "$Q"; }
{ printf '%s' "$GEN" | grep -q 'hits="0"' && [ -z "$( note_of "$GEN" )" ]; } \
    && ok "§B11.2 a GENUINE nowhere-found keeps its bare zero (the note is not blanket noise)" \
    || { no "§B11.2 the note fired on a genuine nowhere-found — the two zeros must stay distinguishable"; printf '%s\n' "$GEN" | sed 's/.*-->//'; }
[ "$( printf '%s' "$Q" | sed 's/.*-->//' )" = "$( printf '%s' "$GEN" | sed 's/.*-->//' | sed 's/totallyNoSuchSymbolAnywhere/engine.cpp:computeBudget/' )" ] \
    && no "§B11.2 the two zeros are still byte-identical modulo the echoed spelling" \
    || ok "§B11.2 the qualified zero and the genuine zero are no longer the same document"

# the carve-outs, so the guard cannot become a new false claim of its own.
for spec in "rw::crossref::writeWhereis" "doThing:withOther:" "computeBudget"; do
    [ -z "$( note_of "$( qz "$spec" )" )" ] \
        && ok "§B11.2 '$spec' is left alone (:: id / trailing-colon selector / plain name)" \
        || no "§B11.2 the guard misfired on '$spec'"
done
# a REAL hit must never carry the note, even when the spelling is qualified-looking.
[ -z "$( note_of "$( qz "computeBudget" )" )" ] && ok "§B11.2 a nonzero answer never carries the note" \
                                                || no "§B11.2 the note appeared beside real hits"
printf '%s' "$( qz "engine.cpp:computeBudget" --legend=full )" | grep -oE '<!--.*?-->' | head -1 | grep -q 'SELECTOR:' \
    && ok "§B11.2 the legend defines the selector-note element it emits" \
    || no "§B11.2 selector-note is emitted and defined nowhere in the legend"

# MCP PARITY — the MCP whereis verb reads its index only for HEAD labels (§A7), so an index-based guard in the
# CLI handler would cover the CLI alone. This one lives in the shared writer; assert the MCP arm inherits it.
if command -v python3 >/dev/null 2>&1; then
    MW="$( printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"whereis","arguments":{"path":"%s","symbol":"engine.cpp:computeBudget"}}}\n' "$R" \
           | "$BIN" --mcp 2>/dev/null \
           | python3 -c 'import sys,json
for line in sys.stdin:
    line=line.strip()
    if not line: continue
    try: d=json.loads(line)
    except Exception: continue
    c=d.get("result",{}).get("content")
    if c: print(c[0].get("text",""))' )"
    [ -n "$( note_of "$MW" )" ] && ok "§B11.2 the MCP whereis verb carries the same selector-note" \
                                || { no "§B11.2 MCP whereis did not inherit the guard"; printf '%s\n' "$MW" | sed 's/.*-->//'; }
else
    printf '  SKIP  §B11.2 MCP parity (no python3)\n'
fi

# ── LEAN: the default listing and the tip/date hoist (lean-answers lane, src/crossref.h WhereisListing) ─────────
# The default lists every kind="def" row and COUNTS the kind="ref" rows in one <refs count= next=> element; the
# next= (--whereis-listing=refs) lists exactly those rows; --whereis-listing=all is the whole hit list, the uncapped
# variant the lean answer is graded against. A row on HEAD's commit omits tip=/date= (at= and head_date= carry them).
# Every assertion below compares the lean answer against the SAME binary's listing=all answer, so the arms read
# "nothing was lost" directly, not against a remembered byte shape.
LR="$TMP/lean"; mkdir -p "$LR"
lg(){ git -C "$LR" "$@" >/dev/null 2>&1; }
lg init -q -b main; lg config commit.gpgsign false
printf '# lean fixture\n' >"$LR/README.md"; lg add -A; lg commit -qm root
# the branch forks from the bare root, so its tree holds ONLY its own definition (the HEAD symbols stay single-tree)
lg checkout -qb feat-lean
printf 'int zqLean( int x, int y )\n{\n    return x + y;\n}\n' >"$LR/branch_only.c"
lg add -A
GIT_COMMITTER_DATE="2026-02-02T00:00:00Z" GIT_AUTHOR_DATE="2026-02-02T00:00:00Z" lg commit -qm "branch def"
lg checkout -q main
printf 'int zqLean( int x );\nint zqDefOnly( void );\n' >"$LR/lean.h"
printf '#include "lean.h"\nint zqLean( int x )\n{\n    return x + 1;\n}\nint zqDefOnly( void )\n{\n    return 3;\n}\n' >"$LR/lean.c"
printf '#include "lean.h"\nint useA( void ) { return zqLean( 1 ); }\nint useB( void ) { return zqLean( 2 ); }\n' >"$LR/use.c"
printf '# notes\n\nzqLean is the entry point; zqMentionOnly is a word no code defines.\n' >"$LR/NOTES.md"
{ printf '#include "lean.h"\n'; i=0; while [ $i -lt 70 ]; do printf 'int many%d( void ) { return zqLean( %d ); }\n' $i $i; i=$((i+1)); done; } >"$LR/many.c"
# fix round 1 (review B1): a symbol with ONE short ref row, where the defs page pays more than it elides
printf 'int zqOne( void ) { return 1; }\n' >"$LR/one.c"
printf 'int oneUse( void ) { return zqOne(); }\n' >"$LR/one_use.c"
lg add -A; lg commit -qm base
LHEAD="$( git -C "$LR" rev-parse --short=9 HEAD )"; LFEAT="$( git -C "$LR" rev-parse --short=9 feat-lean )"
lw(){ "$BIN" "$LR" --whereis="$1" --no-cache "${@:2}" 2>/dev/null; }
hits_of(){ tr '<' '\n' | grep "^hit " | grep "kind=\"$1\"" | sed 's|/>$||; s|/>.*||'; }
lroot(){ grep -o '<whereis [^>]*>' | head -1; }
LDEF="$( lw zqLean )"; LALL="$( lw zqLean --whereis-listing=all --limit=1000 )"
# (L1) the def rows: every kind="def" row of the whole list, byte for byte, in order — and no kind="ref" row
[ -n "$( printf '%s' "$LALL" | hits_of def )" ] && [ "$( printf '%s' "$LDEF" | hits_of def )" = "$( printf '%s' "$LALL" | hits_of def )" ] \
    && [ -z "$( printf '%s' "$LDEF" | hits_of ref )" ] \
    && ok "LEAN (L1): the default lists every kind=\"def\" row of listing=all, byte for byte, and no kind=\"ref\" row" \
    || { no "LEAN (L1): the default's def rows differ from listing=all's (or a ref row is listed)"; printf '%s\n' "$LDEF"; }
# (L2) the count is exact: refs count= == the kind="ref" rows of the whole list
NREF="$( printf '%s' "$LALL" | hits_of ref | wc -l | tr -d ' ' )"
CNT="$( printf '%s' "$LDEF" | grep -oE '<refs count="[0-9]+"' | grep -oE '[0-9]+' )"
[ -n "$CNT" ] && [ "$NREF" -gt 60 ] && [ "$CNT" = "$NREF" ] \
    && ok "LEAN (L2): <refs count=\"$CNT\"> equals the $NREF kind=\"ref\" rows listing=all prints" \
    || no "LEAN (L2): refs count='${CNT:-none}' vs $NREF ref rows in listing=all"
# (L3) next= round-trips: the pasted next= (all its pages) prints exactly listing=all's ref rows, byte for byte
NXT="$( printf '%s' "$LDEF" | grep -oE '<refs [^>]*next="[^"]*"' | sed 's/.*next="//; s/"$//' )"
case "$NXT" in "--whereis=zqLean --whereis-listing=refs") ok "LEAN (L3a): next= names the refs listing of the same symbol" ;;
               *) no "LEAN (L3a): next='$NXT'" ;; esac
P1="$( lw zqLean --whereis-listing=refs )"; P2="$( lw zqLean --whereis-listing=refs --offset=60 )"
{ printf '%s' "$P1" | hits_of ref; printf '%s' "$P2" | hits_of ref; } >"$TMP/lean_next"
printf '%s' "$LALL" | hits_of ref >"$TMP/lean_allref"
[ -s "$TMP/lean_allref" ] && cmp -s "$TMP/lean_next" "$TMP/lean_allref" && [ -z "$( printf '%s' "$P1" | hits_of def )" ] \
    && printf '%s' "$P1" | lroot | grep -q ' listing="refs"' && printf '%s' "$P1" | grep -q "<more hits=\"$(( NREF - 60 ))\"/>" \
    && ok "LEAN (L3b): next= (two pages, the first ending in <more hits=>) reproduces listing=all's ref rows byte for byte" \
    || { no "LEAN (L3b): the refs listing differs from listing=all's ref rows"; diff "$TMP/lean_next" "$TMP/lean_allref" | head -5; }
# (L4) zero refs: no <refs>, no listing=, byte-identical to listing=all
D0="$( lw zqDefOnly )"; A0="$( lw zqDefOnly --whereis-listing=all )"
[ -n "$( printf '%s' "$D0" | hits_of def )" ] && [ "$D0" = "$A0" ] && ! printf '%s' "$D0" | grep -q '<refs ' && ! printf '%s' "$D0" | lroot | grep -q 'listing=' \
    && ok "LEAN (L4): a symbol with no ref row prints no <refs> and is byte-identical to listing=all" \
    || { no "LEAN (L4): the zero-ref answer is not the whole list"; printf '%s\n' "$D0"; }
# (L5) zero defs: the mentions ARE the answer — every row, no <refs>, identical to listing=all
M0="$( lw zqMentionOnly )"; MA="$( lw zqMentionOnly --whereis-listing=all )"
[ -n "$( printf '%s' "$M0" | hits_of ref )" ] && [ "$M0" = "$MA" ] && ! printf '%s' "$M0" | grep -q '<refs ' \
    && ok "LEAN (L5): a name with no def row lists its mentions (identical to listing=all)" \
    || { no "LEAN (L5): the zero-def answer hid its mentions"; printf '%s\n' "$M0"; }
# (L6) the hoist: HEAD-commit rows carry no tip=/date=, the root says at= and head_date=; the branch row keeps both
HD="$( git -C "$LR" log -1 --format=%cs HEAD )"
printf '%s' "$LDEF" | lroot | grep -q " head_date=\"$HD\" at=\"$LHEAD\"" \
    && [ -z "$( printf '%s' "$LALL" | tr '<' '\n' | grep '^hit ref="HEAD"' | grep ' tip=\| date=' )" ] \
    && printf '%s' "$LALL" | tr '<' '\n' | grep -q "^hit ref=\"feat-lean\" tip=\"$LFEAT\" date=\"2026-02-02\" p=\"branch_only.c\"" \
    && ok "LEAN (L6): rows on HEAD's commit omit tip=/date= (at=$LHEAD, head_date=$HD); the branch row keeps tip=$LFEAT date=" \
    || { no "LEAN (L6): the tip/date hoist is wrong"; printf '%s\n' "$LDEF" | lroot; }
# (L7) the window reads the LISTED rows: --limit=1 on the 3-def answer cuts it (capped=1, <more hits=2>), drops complete=
L1R="$( lw zqLean --limit=1 )"
printf '%s' "$L1R" | lroot | grep -q ' shown="1" capped="1" total="3"' && printf '%s' "$L1R" | grep -q '<more hits="2"/>' \
    && ! printf '%s' "$L1R" | lroot | grep -q 'complete=' && printf '%s' "$LDEF" | lroot | grep -q ' complete="1"' \
    && ok "LEAN (L7): shown=/capped=/<more> window the def rows; complete= rides the uncut defs listing, not the cut one" \
    || { no "LEAN (L7): the window does not read the listed rows"; printf '%s\n' "$L1R" | lroot; }
# (L8) refusals: an unknown value, and the modifier without --whereis
"$BIN" "$LR" --whereis=zqLean --whereis-listing=bogus >/dev/null 2>&1; rcb=$?
"$BIN" "$LR" --whereis-listing=all >/dev/null 2>&1; rcn=$?
[ $rcb -eq 1 ] && [ $rcn -eq 1 ] && ok "LEAN (L8): --whereis-listing=bogus and a bare --whereis-listing refuse (exit 1)" \
    || no "LEAN (L8): refusal exits $rcb / $rcn (want 1 / 1)"
# (L9) both legends define what the lean answer carries
printf '%s' "$LDEF" | grep -oE '<!--.*?-->' | head -1 | grep -q 'listing=defs' \
    && printf '%s' "$LDEF" | grep -oE '<!--.*?-->' | head -1 | grep -q 'head_date=' && printf '%s' "$LDEF" | grep -oE '<!--.*?-->' | head -1 | grep -q 'refs count=' \
    && lw zqLean --legend=full | grep -oE '<!--.*?-->' | head -1 | grep -q 'LISTING:.*TIP AND DATE:' \
    && ok "LEAN (L9): compact and full legends define listing=, head_date=, refs count=" \
    || no "LEAN (L9): a lean attribute rides undefined"
# (L10) MCP twin: the same answers over MCP (default, listing all, refs) and the same refusal; one call per session
mcpw(){ printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"whereis","arguments":{"path":"%s","symbol":"zqLean"%s}}}\n' "$LR" "$1" \
           | "$BIN" --mcp 2>/dev/null | python3 -c 'import sys,json
for line in sys.stdin:
    line=line.strip()
    if not line: continue
    d=json.loads(line); c=d.get("result",{}).get("content")
    if d.get("result",{}).get("isError"): print("ISERROR",end="")
    elif c: print(c[0].get("text",""),end="")
    elif "error" in d: print("ERROR",d["error"].get("code"),end="")'; }
if command -v python3 >/dev/null 2>&1; then
    [ "$( mcpw '' )" = "$( lw zqLean )" ] && [ "$( mcpw ',"listing":"all"' )" = "$( lw zqLean --whereis-listing=all )" ] \
        && [ "$( mcpw ',"listing":"refs"' )" = "$( lw zqLean --whereis-listing=refs )" ] && [ "$( mcpw ',"listing":"bogus"' )" = "ISERROR" ] \
        && ok "LEAN (L10): MCP whereis default / listing:all / listing:refs are byte-identical to the CLI; listing:bogus refuses (an isError result, SEP-1303)" \
        || no "LEAN (L10): the MCP twin differs from the CLI"
    # (L10b) CodeRabbit 5468003465: a NON-STRING listing refuses through the shared shape gate and echoes the value SENT.
    # `listing` used to be read inside the whereis arm, after that gate, so listing:5 decoded to "" and the closed-set
    # refusal said "got ''". Near-miss twins: a string outside the set still echoes itself; a string inside it answers (L10).
    mcpwmsg(){ printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"whereis","arguments":{"path":"%s","symbol":"zqLean"%s}}}\n' "$LR" "$1" \
           | "$BIN" --mcp 2>/dev/null | python3 -c 'import sys,json
for line in sys.stdin:
    line=line.strip()
    if not line: continue
    d=json.loads(line)
    if "error" in d: print("ERROR",d["error"].get("code"),d["error"].get("message",""),end="")
    elif d.get("result",{}).get("isError"): print("ISERROR","".join(x.get("text","") for x in d["result"]["content"]),end="")
    elif d.get("result",{}).get("content"): print("ANSWER",end="")'; }
    for arm in '5|5' '["all"]|["all"]' '{"v":1}|{"v":1}' 'true|true' '"bogus"|bogus'; do
        val="${arm%%|*}"; echo_="${arm#*|}"
        m="$( mcpwmsg ",\"listing\":$val" )"
        case "$m" in
            "ISERROR invalid value for field: listing"*"got '$echo_'"*) ok "LEAN (L10b): MCP whereis listing:$val refuses (isError, SEP-1303) and echoes '$echo_'" ;;
            *) no "LEAN (L10b): MCP whereis listing:$val — want a -32602 refusal echoing '$echo_', got: ${m:-nothing}" ;;
        esac
    done
else
    printf '  SKIP  LEAN (L10) MCP twin (no python3)\n'
fi

# ── THE DEFAULT IS THE SHORTER PAGE (fix round 1, review B1; crossref.h whereisServedListing) ────────────────────
# When the defs page and the listing=all page show the SAME definitions, the default serves the defs page only when it is
# STRICTLY shorter, in bytes, than the all page (as written AND in the compact dialect); otherwise it serves the all page.
# (Fix round 2, review D1: when the defs page shows MORE definitions under the row cap, the default serves it whatever its
# bytes — the L15/L16 arms below.) An explicit --whereis-listing=defs is served as asked,
# so each arm reads the two explicit pages of the same binary and checks which one the default is, byte for byte.
nbytes(){ printf '%s' "$1" | wc -c | tr -d ' '; }
# (L11) a 1-ref symbol: the defs page is LONGER than the all page, so the default IS the all page (no listing=, no <refs>)
O_D="$( lw zqOne )"; O_A="$( lw zqOne --whereis-listing=all )"; O_F="$( lw zqOne --whereis-listing=defs )"
{ [ -n "$( printf '%s' "$O_A" | hits_of ref )" ] && printf '%s' "$O_F" | grep -q '<refs count="1"' \
  && [ "$( nbytes "$O_F" )" -gt "$( nbytes "$O_A" )" ] && [ "$O_D" = "$O_A" ]; } \
    && ok "LEAN (L11): 1-ref symbol — defs page $( nbytes "$O_F" ) B > all page $( nbytes "$O_A" ) B, so the default is byte-identical to listing=all" \
    || { no "LEAN (L11): the 1-ref default is not the (shorter) all page: default $( nbytes "$O_D" ) B, all $( nbytes "$O_A" ) B, defs $( nbytes "$O_F" ) B"; printf '%s\n' "$O_D" | lroot; }
# (L12) a many-ref symbol (73 refs) stays lean: the default IS the explicit defs page, strictly shorter than all
M_F="$( lw zqLean --whereis-listing=defs )"; M_A="$( lw zqLean --whereis-listing=all )"
{ [ "$LDEF" = "$M_F" ] && printf '%s' "$LDEF" | lroot | grep -q ' listing="defs"' && [ "$( nbytes "$M_F" )" -lt "$( nbytes "$M_A" )" ]; } \
    && ok "LEAN (L12): 73-ref symbol — the default is the defs page ($( nbytes "$M_F" ) B < all $( nbytes "$M_A" ) B)" \
    || no "LEAN (L12): the many-ref default is not the defs page (default $( nbytes "$LDEF" ) B, defs $( nbytes "$M_F" ) B, all $( nbytes "$M_A" ) B)"
# (L13) the TIE: three repos identical but for the length of the one ref row's text. The probe repo measures how much
# longer the defs page is (D); padding the ref row by D more bytes makes the two pages EQUAL. A tie serves all (equal
# bytes, more rows); one byte more and defs is strictly shorter, one byte less and all is.
mk_tie(){ local d="$TMP/tie$1"; mkdir -p "$d"; git -C "$d" init -q -b main >/dev/null 2>&1; git -C "$d" config commit.gpgsign false
          printf 'int zqTie( int x ) { return x; }\n' >"$d/tie.c"
          # The padding is split over TWO ref rows (lane whereis-lean): a t= over 300 bytes prints a 200-byte preview, so one
          # row padded by the whole overhead (~330 B) would stop growing a byte per pad byte; two rows of half each stay whole.
          local h=$(( $1 / 2 ))
          { printf 'int useT( void ) { return zqTie( 1 ); } // t%s\n' "$( head -c "$h" </dev/zero | tr '\0' 'p' )"
            printf 'int useU( void ) { return zqTie( 2 ); } // u%s\n' "$( head -c "$(( $1 - h ))" </dev/zero | tr '\0' 'q' )"; } >"$d/use.c"
          git -C "$d" add -A >/dev/null 2>&1; git -C "$d" commit -qm tie >/dev/null 2>&1; printf '%s' "$d"; }
tw(){ "$BIN" "$1" --whereis=zqTie --no-cache "${@:2}" 2>/dev/null; }
TP="$( mk_tie 1 )"; TD=$(( $( nbytes "$( tw "$TP" --whereis-listing=defs )" ) - $( nbytes "$( tw "$TP" --whereis-listing=all )" ) ))
if [ "$TD" -gt 1 ] 2>/dev/null; then
    for k in -1 0 1; do
        TR="$( mk_tie $(( 1 + TD + k )) )"
        T_D="$( tw "$TR" )"; T_F="$( tw "$TR" --whereis-listing=defs )"; T_A="$( tw "$TR" --whereis-listing=all )"
        TF="$( nbytes "$T_F" )"; TA="$( nbytes "$T_A" )"
        case $k in
            -1) { [ $(( TF - TA )) -eq 1 ] && [ "$T_D" = "$T_A" ]; } \
                    && ok "LEAN (L13a): defs page 1 B LONGER ($TF vs $TA) — the default is the all page" \
                    || no "LEAN (L13a): defs $TF / all $TA, default $( nbytes "$T_D" ) B — want the all page" ;;
            0)  { [ "$TF" -eq "$TA" ] && [ "$T_D" = "$T_A" ] && [ "$T_D" != "$T_F" ]; } \
                    && ok "LEAN (L13b): defs page and all page EQUAL ($TF B) — the tie serves the all page (more rows)" \
                    || no "LEAN (L13b): tie defs $TF / all $TA, default $( nbytes "$T_D" ) B — want the all page on a tie" ;;
            1)  { [ $(( TA - TF )) -eq 1 ] && [ "$T_D" = "$T_F" ]; } \
                    && ok "LEAN (L13c): defs page 1 B SHORTER ($TF vs $TA) — the default is the defs page" \
                    || no "LEAN (L13c): defs $TF / all $TA, default $( nbytes "$T_D" ) B — want the defs page" ;;
        esac
    done
else
    no "LEAN (L13): the tie probe measured no defs-page overhead (D='$TD'): the probe did not run"
fi
# (L14) MCP twin: the same served page over MCP — the 1-ref default is the all page, the tie serves all, the
# many-ref default is the defs page; each byte-identical to the CLI.
mcpq(){ printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"whereis","arguments":{"path":"%s","symbol":"%s"%s}}}\n' "$1" "$2" "$3" \
           | "$BIN" --mcp 2>/dev/null | python3 -c 'import sys,json
for line in sys.stdin:
    line=line.strip()
    if not line: continue
    d=json.loads(line); c=d.get("result",{}).get("content")
    if d.get("result",{}).get("isError"): print("ISERROR",end="")
    elif c: print(c[0].get("text",""),end="")
    elif "error" in d: print("ERROR",d["error"].get("code"),end="")'; }
if command -v python3 >/dev/null 2>&1; then
    TT="$TMP/tie$(( 1 + TD ))"
    { [ "$( mcpq "$LR" zqOne '' )" = "$O_A" ] && [ "$( mcpq "$LR" zqOne ',"listing":"defs"' )" = "$O_F" ] \
      && [ "$( mcpq "$LR" zqLean '' )" = "$M_F" ] && [ -d "$TT" ] && [ "$( mcpq "$TT" zqTie '' )" = "$( tw "$TT" --whereis-listing=all )" ]; } \
        && ok "LEAN (L14): MCP whereis serves the same page as the CLI default — all on the 1-ref symbol and the tie, defs on the 73-ref symbol" \
        || no "LEAN (L14): the MCP default serves a different page than the CLI"
else
    printf '  SKIP  LEAN (L14) MCP twin (no python3)\n'
fi

# ── COMPLETE ANSWERS FIRST (fix round 2, review D1; crossref.h whereisServedListing) ───────────────────────────────
# Under the shared row cap the all page can list FEWER definitions than the defs page (HEAD's references fill the cap
# before the branch definitions arrive). The default serves the page that SHOWS MORE definitions whatever its bytes; only
# when both show the same definitions do the bytes decide. The arms are fixture-built and compare the DEFAULT with the two
# explicit pages of the same binary, byte for byte.
defs_in(){ hits_of def | wc -l | tr -d ' '; }
dw(){ "$BIN" "$1" --whereis="$2" --no-cache "${@:3}" 2>/dev/null; }
# (L15) the cap bites: HEAD defines zqCap once and calls it 70 times; 64 branches each hold their OWN definition line
# (`return x + N`: 64 distinct lines, so none folds into another — foldSharedBranchDefs lists a line several refs share
# once, which is the lane whereis-defs-fix twin below), and HEAD adds one unrelated commit, so every branch row carries
# tip=/date=. The all page lists HEAD's definition and 59 references (60 rows), the defs page 60 definitions, and the
# defs page is the LONGER one in bytes — the default is defs.
D15="$TMP/cap15"; mkdir -p "$D15"; git -C "$D15" init -q -b main >/dev/null 2>&1; git -C "$D15" config commit.gpgsign false
printf 'int zqCap( int x ) { return x; }\n' >"$D15/def.c"
{ printf 'int useAll( void )\n{\n    int s = 0;\n'; i=0; while [ $i -lt 70 ]; do printf '    s += zqCap( %d );\n' $i; i=$((i+1)); done; printf '    return s;\n}\n'; } >"$D15/use.c"
printf '// head\n' >"$D15/other.c"
git -C "$D15" add -A >/dev/null 2>&1; git -C "$D15" commit -qm cap1 >/dev/null 2>&1
i=0; while [ $i -lt 64 ]; do
    git -C "$D15" checkout -qb "b$i" >/dev/null 2>&1
    printf 'int zqCap( int x ) { return x + %d; }\n' $i >"$D15/def.c"
    git -C "$D15" commit -qam "b$i" >/dev/null 2>&1
    git -C "$D15" checkout -q main >/dev/null 2>&1
    i=$((i+1))
done
printf 'int zqCap( int x ) { return x; }\n' >"$D15/def.c"
printf '// head, later\n' >"$D15/other.c"; git -C "$D15" add -A >/dev/null 2>&1
GIT_COMMITTER_DATE="2026-02-02T00:00:00Z" GIT_AUTHOR_DATE="2026-02-02T00:00:00Z" git -C "$D15" commit -qm cap2 >/dev/null 2>&1
C_D="$( dw "$D15" zqCap )"; C_A="$( dw "$D15" zqCap --whereis-listing=all )"; C_F="$( dw "$D15" zqCap --whereis-listing=defs )"
CD_A="$( printf '%s' "$C_A" | defs_in )"; CD_F="$( printf '%s' "$C_F" | defs_in )"
if [ "$CD_F" -gt "$CD_A" ] 2>/dev/null && [ "$( nbytes "$C_F" )" -gt "$( nbytes "$C_A" )" ] \
   && printf '%s' "$C_A" | lroot | grep -q ' capped="1"'; then
    { [ "$C_D" = "$C_F" ] && printf '%s' "$C_D" | lroot | grep -q ' listing="defs"'; } \
        && ok "LEAN (L15): capped, the defs page is LONGER ($( nbytes "$C_F" ) B vs $( nbytes "$C_A" ) B) but lists more definitions ($CD_F vs $CD_A) — the default is the defs page" \
        || { no "LEAN (L15): the default ($( nbytes "$C_D" ) B) is not the defs page ($( nbytes "$C_F" ) B, $CD_F defs) over the all page ($( nbytes "$C_A" ) B, $CD_A defs)"; printf '%s\n' "$C_D" | lroot; }
else
    no "LEAN (L15): premises not met: defs shown $CD_F vs all $CD_A, bytes $( nbytes "$C_F" ) vs $( nbytes "$C_A" ), all capped?"
fi
# (L15-FOLD, lane whereis-defs-fix) the same shape with the 64 branches at ONE commit: their 64 copies of the definition
# line are one row refs="64" (folded="63" on the root), the defs page is now the SHORTER page (2 rows) and is still the
# default — it lists more definitions (65 represented) than the capped all page (HEAD's one). RED on 93aeab1d: 60 rows,
# every one the same line, 4 more behind <more>.
D15F="$TMP/cap15fold"; mkdir -p "$D15F"; git -C "$D15F" init -q -b main >/dev/null 2>&1; git -C "$D15F" config commit.gpgsign false
cp "$D15/def.c" "$D15/use.c" "$D15F/"; printf '// head\n' >"$D15F/other.c"
git -C "$D15F" add -A >/dev/null 2>&1; git -C "$D15F" commit -qm cap1 >/dev/null 2>&1
i=0; while [ $i -lt 64 ]; do git -C "$D15F" branch "b$i" >/dev/null 2>&1; i=$((i+1)); done
printf '// head, later\n' >"$D15F/other.c"; git -C "$D15F" add -A >/dev/null 2>&1
GIT_COMMITTER_DATE="2026-02-02T00:00:00Z" GIT_AUTHOR_DATE="2026-02-02T00:00:00Z" git -C "$D15F" commit -qm cap2 >/dev/null 2>&1
C_FD="$( dw "$D15F" zqCap )"
if printf '%s' "$C_FD" | lroot | grep -q ' listing="defs" folded="63" ' && [ "$( printf '%s' "$C_FD" | defs_in )" = "2" ] \
   && [ "$( printf '%s' "$C_FD" | tr '<' '\n' | grep -c '^hit ref="b0" .*kind="def" refs="64" ' )" = "1" ] \
   && ! printf '%s' "$C_FD" | grep -q '<more '; then
    ok 'LEAN (L15-FOLD): 64 branches sharing one definition line are one row refs="64" (folded="63"); the 2-row defs page is the default with nothing behind <more>'
else
    no 'LEAN (L15-FOLD): the shared definition line is not folded into one refs="64" row on a 2-row defs page'; printf '%s\n' "$C_FD" | lroot; printf '%s' "$C_FD" | tr '<' '\n' | grep -c '^hit '
fi
# (L15-MCP) the same symbol over MCP (no `listing`): byte-identical to the CLI defs page.
if command -v python3 >/dev/null 2>&1; then
    { [ -n "$C_F" ] && [ "$( mcpq "$D15" zqCap '' )" = "$C_F" ] && [ "$( mcpq "$D15" zqCap ',"listing":"all"' )" = "$C_A" ]; } \
        && ok "LEAN (L15-MCP): MCP whereis serves the same defs page as the CLI default on the capped answer (listing:\"all\" still the all page)" \
        || no "LEAN (L15-MCP): the MCP default differs from the CLI's on the capped answer"
else
    printf '  SKIP  LEAN (L15-MCP) MCP twin (no python3)\n'
fi
# (L16) the negative for the bytes rule: 61 definitions on HEAD, one reference, a single branch. Both pages are capped at
# 60 rows and both show the SAME 60 definitions (definitions sort before references), and the all page is shorter (no
# <refs> element). The default is the all page: a fix that serves defs whenever the all page is capped, or that counts
# the TOTAL definitions instead of the SHOWN ones, goes red here.
D16="$TMP/cap16"; mkdir -p "$D16"; git -C "$D16" init -q -b main >/dev/null 2>&1; git -C "$D16" config commit.gpgsign false
i=0; while [ $i -lt 61 ]; do printf 'int zqMany( int );\n' >"$D16/h$i.h"; i=$((i+1)); done
printf 'int useMany( void ) { return zqMany( 1 ); }\n' >"$D16/use.c"
git -C "$D16" add -A >/dev/null 2>&1; git -C "$D16" commit -qm many >/dev/null 2>&1
M16_D="$( dw "$D16" zqMany )"; M16_A="$( dw "$D16" zqMany --whereis-listing=all )"; M16_F="$( dw "$D16" zqMany --whereis-listing=defs )"
M16_DA="$( printf '%s' "$M16_A" | defs_in )"; M16_DF="$( printf '%s' "$M16_F" | defs_in )"
if [ "$M16_DA" = "$M16_DF" ] && [ "$M16_DA" -ge 60 ] 2>/dev/null && printf '%s' "$M16_A" | lroot | grep -q ' capped="1"' \
   && printf '%s' "$M16_F" | lroot | grep -q ' capped="1"' && [ "$( nbytes "$M16_A" )" -lt "$( nbytes "$M16_F" )" ]; then
    { [ "$M16_D" = "$M16_A" ] && ! printf '%s' "$M16_D" | lroot | grep -q ' listing='; } \
        && ok "LEAN (L16): capped on both pages, the SAME $M16_DA definitions shown — the shorter all page ($( nbytes "$M16_A" ) B < $( nbytes "$M16_F" ) B) is the default" \
        || { no "LEAN (L16): the default ($( nbytes "$M16_D" ) B) is not the shorter all page ($( nbytes "$M16_A" ) B) when both show the same definitions"; printf '%s\n' "$M16_D" | lroot; }
else
    no "LEAN (L16): premises not met: defs shown $M16_DA (all) vs $M16_DF (defs), bytes $( nbytes "$M16_A" ) vs $( nbytes "$M16_F" )"
fi
if command -v python3 >/dev/null 2>&1; then
    [ "$( mcpq "$D16" zqMany '' )" = "$M16_A" ] \
        && ok "LEAN (L16-MCP): MCP whereis serves the same all page as the CLI when both pages show the same definitions" \
        || no "LEAN (L16-MCP): the MCP default differs from the CLI's on the capped, same-definitions answer"
else
    printf '  SKIP  LEAN (L16-MCP) MCP twin (no python3)\n'
fi

# ── 5c) PARSED BRANCH LABELS (lane whereis-defs-fix, fix round 2; crossref.h labelBranchRowsByParse) ──────────────
# A row of another ref is kind="def" only where a PARSER finds the definition: a branch holding HEAD's own blob of a path
# takes HEAD's index labels; any other blob holding a parse-worthy line is parsed by the index's own extraction
# (ingest.h definitionLinesInBlobs). The lexical shape test only CHOOSES blobs. One well-formed file per language family
# under head/ on main; byte-identical copies under sib/ on branch `sib` (another path: those blobs are PARSED, not
# mirrored); and under c1/ the definition shapes the round-1 lexical test lost (rv-whereis-defs-fix C1). Every line naming
# probeName carries @D (a definition) or @R (a reference). Two claims per marked line: the branch row says what the
# marker says, and it says what HEAD's index row says for the same bytes. RED on 93aeab1d (18 branch rows wrong: the C2
# call shapes read def) and on f1f11a7b (22: the C1 definition shapes read ref).
PB="$TMP/parsedlabels"; mkdir -p "$PB"
gp(){ git -C "$PB" "$@" >/dev/null 2>&1; }
mkp(){ mkdir -p "$( dirname "$PB/$1" )"; cat >"$PB/$1"; }
gp init -q -b main; gp config commit.gpgsign false
mkp head/a.c <<'EOF'
#define probeName( a ) ( (a) + 1 ) /* @D */
int caller( int a )
{
    if( a ) { a = probeName( a ); } /* @R */
    return probeName( a ); /* @R */
}
EOF
mkp head/b.cpp <<'EOF'
#include <functional>
struct T { int probeName( int a ) const; }; // @D
int T::probeName( int a ) const { return a; } // @D
void run( T& t, int a )
{
    t.probeName( a ); // @R
    if( a ) { a = t.probeName( a ); } // @R
    auto f = [ & ]( int x ) { return t.probeName( x ); }; // @R
    // probeName( a ) { // @R
}
EOF
mkp head/c.m <<'EOF'
@interface Box
- (int)probeName:(int)a; // @R (an @interface declaration its same-file @implementation shadows: one symbol, the definition)
@end
@implementation Box
- (int)probeName:(int)a { return a; } // @D
- (void)run { [self probeName:1]; } // @R
@end
EOF
mkp head/d.py <<'EOF'
def probeName(a):  # @D
    return a


class K:
    async def other(self):
        return probeName(1)  # @R


@probeName  # @R
def deco():
    x = probeName(2)  # @R
    print("probeName(x)")  # @R
EOF
mkp head/e.ts <<'EOF'
export function probeName(a: number): number { // @D
  return a;
}
export class Svc {
  static probeName(a: number) { return a; } // @D
  run(a: number) {
    probeName(a).toString(); // @R
    setTimeout(() => probeName(a), 0); // @R
  }
}
EOF
mkp head/f.js <<'EOF'
function probeName(a) { // @D
  return a;
}
describe('x', () => {
  probeName('x', () => { // @R
    return 1;
  });
});
EOF
mkp head/G.java <<'EOF'
public class G {
    public static int probeName(int a) { // @D
        return a;
    }
    int run(int a) {
        return probeName(a); // @R
    }
}
EOF
mkp head/h.rb <<'EOF'
class H
  def probeName(a) # @D
    a
  end
  def run(a)
    puts probeName(a) # @R
    probeName(a) do |x| # @R
      x
    end
  end
end
EOF
mkp head/i.go <<'EOF'
package p

func probeName(a int) int { // @D
	return a
}

func run(a int) {
	go probeName(a) // @R
	defer probeName(a) // @R
	if v := probeName(a); v > 0 { // @R
	}
}
EOF
mkp head/j.rs <<'EOF'
pub fn probe_other() {}
pub fn probeName(a: i32) -> i32 { // @D
    a
}
fn run(a: i32) -> i32 {
    let v = probeName(a); // @R
    probeName(v) // @R
}
EOF
mkp head/k.swift <<'EOF'
func probeName(_ a: Int) throws -> Int { // @D
    return a
}
func run() throws {
    let v = try probeName(1) // @R
    _ = v
}
EOF
mkp head/l.cs <<'EOF'
public class L
{
    public static int probeName(int a) { return a; } // @D
    public int Run(int a)
    {
        return probeName(a); // @R
    }
}
EOF
mkp head/m.sh <<'EOF'
probeName() { # @D
  echo "$1"
}
run() {
  probeName x # @R
}
EOF
mkp head/n.cpp <<'EOF'
struct N { int probeName; }; // @R (a field: not a symbol in the index, so never a def site on HEAD either)
EOF
mkp head/o.md <<'EOF'
# probeName

Call `probeName()` from the loop. <!-- @R -->
EOF
# The C2 call shapes and the review's checklist-29 near-misses (rv-whereis-defs-fix2 X3), each beside a true definition
# of the same name in a well-formed file of its language, so each file reads both ways: the definition def, the call ref.
# The call lines carry NO marker (an unmarked line wants ref): a trailing comment would change the shape a lexical reading
# sees, and the premise below is the bare shape.
# RED on 93aeab1d (its lexical reading calls several of these calls definitions).
mkp head/q.py <<'EOF'
def probeName(n):  # @D
    def wrap(f):
        return f
    return wrap


@probeName(1)
def other():
    return 2
EOF
mkp head/P.java <<'EOF'
public class P {
    public static int probeName(int a) { // @D
        return a;
    }
    @probeName(value = 1)
    int run(int a) {
        return a;
    }
}
EOF
mkp head/t.c <<'EOF'
#define probeName( x ) ( (x) + 1 ) /* @D */
#define WRAP( x ) probeName( x )
int useA( int y )
{
    if( probeName( y ) > 2 ) {
        return WRAP( y );
    }
    return 0;
}
EOF
mkp head/u.cpp <<'EOF'
template <typename F> int probeName( int a, F f ) { return f( a ); } // @D
/**
 * @see probeName( a )
 */
int run( int y )
{
    return probeName( y, [&]( int x ) {
        return x;
    } );
}
EOF
mkp head/v.cpp <<'EOF'
struct probeName { int v; }; // @D
class Foo : public probeName {
};
EOF
mkp head/w.js <<'EOF'
export function probeName(a) { // @D
  return a;
}
function suite() {
  probeName(function () {
    return 1;
  });
  probeName('y', () => {
    return 2;
  });
}
export default probeName(3);
EOF
mkp head/x.ts <<'EOF'
export function probeName(n: number) { // @D
  return (t: any, k: string) => {};
}
export class Box {
  @probeName(1) handle() {
    return 3;
  }
}
EOF
mkp head/y.rb <<'EOF'
def probeName(a) # @D
  a
end
def other(probeName)
  1
end
EOF
gp add -A; gp commit -qm base
gp checkout -qb sib
mkdir -p "$PB/sib"; cp -R "$PB/head/." "$PB/sib/"
mkp c1/m1.h <<'EOF'
#define probeName( a ) ( (a) + 1 ) // @D
EOF
mkp c1/m2.h <<'EOF'
#define probeName( a ) do { f( a ); } while( 0 ) // @D
EOF
mkp c1/d1.cpp <<'EOF'
decltype(auto) probeName( int a ) { return a; } // @D
EOF
mkp c1/d2.cpp <<'EOF'
__attribute__((noinline)) static int probeName( int a ) { return a; } // @D
EOF
mkp c1/d3.cpp <<'EOF'
#include <functional>
std::function<void()> probeName( int a ) { return [](){}; } // @D
EOF
mkp c1/d4.cpp <<'EOF'
template <typename T, typename = void> T probeName( T a ) { return a; } // @D
EOF
mkp c1/T.java <<'EOF'
public class T {
    @Test(expected = Foo.class) public void probeName() { // @D
    }
}
EOF
mkp c1/c.ts <<'EOF'
export class C {
  @HostListener('click') probeName() { // @D
  }
}
EOF
mkp c1/a.cs <<'EOF'
public class A
{
    [HttpGet("x")] public IActionResult probeName() { return null; } // @D
}
EOF
mkp c1/s.rs <<'EOF'
#[derive(Debug)] pub struct probeName { // @D
    a: i32,
}
EOF
mkp c1/e.js <<'EOF'
module.exports = function probeName(req, res) { // @D
  return req;
};
EOF
mkp c1/h.js <<'EOF'
const handler = function probeName() { // @D
  return 1;
};
EOF
# the reviewer's branch-only repro (rv C1 repro 1): names HEAD never holds, defined only on this branch
printf '#define clampBudget( x ) ( (x) > 9 ? 9 : (x) )\n' >"$PB/c1/b.h"
printf 'int use( int a ) { return clampBudget( a ); }\n' >"$PB/c1/u.c"
printf 'public class T2 {\n    @Test(timeout = 10) public void checkBudget() {\n    }\n}\n' >"$PB/c1/T2.java"
gp add -A; gp commit -qm sib; gp checkout -q main
"$BIN" "$PB" --whereis=probeName --whereis-listing=all --limit=1000 --no-cache >"$TMP/pb.all" 2>/dev/null; rcPb=$?
if [ $rcPb -ne 0 ] || ! grep -q '<whereis ' "$TMP/pb.all"; then
    no "whereis (parsed labels): the fixture produced no <whereis> root (rc $rcPb)"
else
    sed 's/<!--.*-->//' "$TMP/pb.all" | tr '<' '\n' | sed -n 's/^hit ref="\([^"]*\)".* p="\([^"]*\)" l="\([0-9]*\)" kind="\([a-z]*\)".*/\1 \2:\3 \4/p' >"$TMP/pb.kinds"
    PB_WRONG=""; PB_SPLIT=""; PB_N=0
    for f in $( git -C "$PB" ls-tree -r --name-only sib -- head c1 | grep -v '^c1/\(b\.h\|u\.c\|T2\.java\)$' ); do
        case "$f" in head/*) bp="sib/${f#head/}"; hp="$f";; *) bp="$f"; hp="";; esac
        ln=0
        while IFS= read -r line || [ -n "$line" ]; do
            ln=$((ln+1))
            case "$line" in *probeName*) ;; *) continue;; esac
            want=ref; case "$line" in *@D*) want=def;; esac
            case "$f:$line" in *.md:"# probeName") want=def;; esac   # a markdown heading is a section symbol (no room for a marker)
            bk="$( awk -v k="$bp:$ln" '$1=="sib" && $2==k {print $3}' "$TMP/pb.kinds" | head -1 )"
            PB_N=$((PB_N+1))
            [ "$bk" = "$want" ] || PB_WRONG="$PB_WRONG [$bp:$ln $bk want $want]"
            if [ -n "$hp" ]; then
                hk="$( awk -v k="$hp:$ln" '$1=="HEAD" && $2==k {print $3}' "$TMP/pb.kinds" | head -1 )"
                [ "$hk" = "$bk" ] || PB_SPLIT="$PB_SPLIT [$bp:$ln branch $bk HEAD $hk]"
            fi
        done < <( git -C "$PB" show "sib:$f" )
    done
    { [ "$PB_N" -ge 50 ] && [ -z "$PB_WRONG" ]; } \
        && ok "whereis (parsed labels): $PB_N marked lines over C, C++, ObjC, Python, TS, JS, Java, Ruby, Go, Rust, Swift, C#, Bash and Markdown, plus the 12 C1 definition shapes — every branch row says what its marker says" \
        || no "whereis (parsed labels): branch rows mislabelled (of $PB_N):$PB_WRONG"
    [ -z "$PB_SPLIT" ] \
        && ok 'whereis (parsed labels): every sib/ branch row says what HEAD'"'"'s index row says for the same bytes (the same way HEAD is labelled)' \
        || no "whereis (parsed labels): the branch parse and HEAD's index disagree on the same bytes:$PB_SPLIT"
    grep -o '<whereis [^>]*>' "$TMP/pb.all" | grep -q ' ref_labels="parsed" ' && ! grep -q '<unparsed ' "$TMP/pb.all" \
        && ok 'whereis (parsed labels): ref_labels="parsed" on an answer with branch rows, and no <unparsed> (every parse-worthy blob was read)' \
        || no 'whereis (parsed labels): ref_labels= missing, or an <unparsed> element on an answer the guard never touched'
fi
# the branch-only definitions (rv C1 repro 1): the definition is the answer, and the call beside it is not
CB="$( "$BIN" "$PB" --whereis=clampBudget --whereis-listing=all --no-cache 2>/dev/null )"
KB="$( "$BIN" "$PB" --whereis=checkBudget --whereis-listing=all --no-cache 2>/dev/null )"
{ printf '%s' "$CB" | grep -q '<whereis [^>]* on-head="0"' && printf '%s' "$CB" | grep -q '<hit ref="sib" [^>]*p="c1/b.h" l="1" kind="def"' \
  && printf '%s' "$CB" | grep -q '<hit ref="sib" [^>]*p="c1/u.c" l="1" kind="ref"' \
  && printf '%s' "$KB" | grep -q '<hit ref="sib" [^>]*p="c1/T2.java" l="2" kind="def"'; } \
    && ok 'whereis (branch-only): `#define clampBudget( x )` and `@Test(timeout = 10) public void checkBudget()` read kind="def" on the only ref holding them; the call beside the macro reads kind="ref"' \
    || { no 'whereis (branch-only): a branch-only definition lost its label, or its call site gained one'; printf '%s\n%s\n' "$CB" "$KB" | sed 's/<!--.*-->//'; }
# "One the parser cannot finish" (CHANGELOG, the UNPARSED clause): a branch .astro that opens a frontmatter fence and never
# closes it confirms nothing: its parse-worthy line reads kind="text", never def, and <unparsed blobs="1" rows="1"/> counts
# it with no next= (the guard left nothing, so there is nothing to lift). Its closed twin reads def. RED on 93aeab1d (no
# <unparsed>; the unclosed line read def).
AS="$TMP/astro"; mkdir -p "$AS"; git -C "$AS" init -q -b main >/dev/null 2>&1; git -C "$AS" config commit.gpgsign false
printf 'x\n' >"$AS/a.txt"; git -C "$AS" add -A >/dev/null 2>&1; git -C "$AS" commit -qm base >/dev/null 2>&1; git -C "$AS" checkout -qb feat >/dev/null 2>&1
printf -- '---\nfunction astroName(a) { return a; }\n---\n<div>{astroName(1)}</div>\n' >"$AS/ok.astro"
printf -- '---\nfunction astroOpen(a) { return a; }\n<div>{astroOpen(1)}</div>\n' >"$AS/p.astro"
git -C "$AS" add -A >/dev/null 2>&1; git -C "$AS" commit -qm feat >/dev/null 2>&1; git -C "$AS" checkout -q main >/dev/null 2>&1
AO="$( "$BIN" "$AS" --whereis=astroOpen --whereis-listing=all --no-cache 2>/dev/null )"; rcAo=$?
AN="$( "$BIN" "$AS" --whereis=astroName --whereis-listing=all --no-cache 2>/dev/null )"; rcAn=$?
if [ $rcAo -ne 0 ] || [ $rcAn -ne 0 ] || ! printf '%s' "$AO" | grep -q '<whereis ' || ! printf '%s' "$AN" | grep -q '<whereis '; then
    no "whereis (parser could not finish): a run produced no <whereis> root (rc $rcAo / $rcAn)"
else
    { printf '%s' "$AO" | grep -q '<unparsed blobs="1" rows="1"/>' && printf '%s' "$AO" | grep -q '<hit ref="feat" [^>]*p="p.astro" l="2" kind="text"' \
      && ! printf '%s' "$AO" | grep -q 'kind="def"' \
      && printf '%s' "$AN" | grep -q '<hit ref="feat" [^>]*p="ok.astro" l="2" kind="def"' && ! printf '%s' "$AN" | grep -q '<unparsed'; } \
        && ok 'whereis (parser could not finish): an unclosed .astro frontmatter reads kind="text" with <unparsed blobs="1" rows="1"/> (no next=); its closed twin reads def' \
        || { no 'whereis (parser could not finish): the unclosed .astro blob was labelled, or not disclosed, or the closed twin lost its def'; printf '%s\n%s\n' "$AO" "$AN" | sed 's/<!--.*-->//'; }
fi
# ref_labels= rides only an answer with another ref's row: a repo with no other ref answers as before
NR="$TMP/norefs"; mkdir -p "$NR"; git -C "$NR" init -q -b main >/dev/null 2>&1; git -C "$NR" config commit.gpgsign false
printf 'int lonelyName( int a ) { return a; }\nint z( void ) { return lonelyName( 1 ); }\n' >"$NR/x.c"
git -C "$NR" add -A >/dev/null 2>&1; git -C "$NR" commit -qm one >/dev/null 2>&1
NRO="$( "$BIN" "$NR" --whereis=lonelyName --no-cache 2>/dev/null )"; rcNr=$?
[ $rcNr -eq 0 ] && printf '%s' "$NRO" | grep -q '<whereis ' && ! printf '%s' "$NRO" | grep -q 'ref_labels' && ! printf '%s' "$NRO" | grep -q '<unparsed' \
    && ok 'whereis (parsed labels): no ref_labels= (and no reading of it) on a repo with no other ref' \
    || no 'whereis (parsed labels): ref_labels= or <unparsed> rides an answer without a branch row'
# CLI = MCP: the MCP whereis default is byte-identical to the CLI default on the parsed fixture
if command -v python3 >/dev/null 2>&1; then
    PBD="$( "$BIN" "$PB" --whereis=probeName --no-cache 2>/dev/null )"
    PBM="$( printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"whereis","arguments":{"path":"%s","symbol":"probeName"}}}\n' "$PB" \
            | "$BIN" --mcp 2>/dev/null | python3 -c 'import sys,json
for line in sys.stdin:
    line=line.strip()
    if not line: continue
    d=json.loads(line); c=d.get("result",{}).get("content")
    if c: print(c[0].get("text",""),end="")' )"
    [ -n "$PBD" ] && [ "$PBD" = "$PBM" ] \
        && ok 'whereis (parsed labels): MCP whereis serves the CLI default byte for byte (one labeller on both surfaces)' \
        || no 'whereis (parsed labels): the MCP answer differs from the CLI default on the parsed fixture'
else
    printf '  SKIP  whereis (parsed labels) MCP twin (no python3)\n'
fi

# ── 5d) the RUNAWAY GUARD on the parse batch (kWhereisParseMaxBlobs = 256) and what it leaves ─────────────────────────
# 300 distinct blobs on one branch, each a one-line definition of guardName (g.h is HEAD's own blob there: mirrored, never
# in the batch): the batch takes 256 (most rows first, then path: f000..f255), the other 44 confirm NOTHING — their parse-worthy rows read kind="text", never kind="def", and
# <unparsed blobs="44" rows="44" next="… --detail=1"> says so. --detail=1 lifts the guard: all 300 are definitions and the
# element is gone. The full legend carries the UNPARSED clause on exactly that answer and stays well-formed XML.
# u.c (HEAD's, 20 calls) gives the answer kind="ref" rows, so the default listing (defs) and listing=all are different
# pages: the next= replay arm below tells "the same question" from "the default question".
GG="$TMP/guard"; mkdir -p "$GG"; git -C "$GG" init -q -b main >/dev/null 2>&1; git -C "$GG" config commit.gpgsign false
printf 'int guardName( int a );\n' >"$GG/g.h"
i=0; : >"$GG/u.c"; while [ $i -lt 20 ]; do printf 'int use%d( void ) { return guardName( %d ); }\n' $i $i >>"$GG/u.c"; i=$((i+1)); done
git -C "$GG" add -A >/dev/null 2>&1; git -C "$GG" commit -qm base >/dev/null 2>&1
git -C "$GG" checkout -qb many >/dev/null 2>&1
i=0; while [ $i -lt 300 ]; do n=$( printf '%03d' $i ); printf 'int guardName( int a ) { return a + %d; }\n' $i >"$GG/f$n.c"; i=$((i+1)); done
git -C "$GG" add -A >/dev/null 2>&1; git -C "$GG" commit -qm many >/dev/null 2>&1; git -C "$GG" checkout -q main >/dev/null 2>&1
GA="$( "$BIN" "$GG" --whereis=guardName --whereis-listing=all --limit=1000 --no-cache 2>/dev/null )"; rcGa=$?
GD="$( "$BIN" "$GG" --whereis=guardName --whereis-listing=all --limit=1000 --detail=1 --no-cache 2>/dev/null )"; rcGd=$?
GT="$( printf '%s' "$GA" | sed 's/<!--.*-->//' | tr '<' '\n' | grep '^hit ref="many" .* p="f' | grep -c 'kind="text"' )"
GF="$( printf '%s' "$GA" | sed 's/<!--.*-->//' | tr '<' '\n' | grep '^hit ref="many" .* p="f' | grep -c 'kind="def"' )"
GTL="$( printf '%s' "$GA" | sed 's/<!--.*-->//' | tr '<' '\n' | grep '^hit ref="many" ' | grep 'kind="text"' | sed -n 's/.* p="\([^"]*\)".*/\1/p' | sort | sed -n '1p;$p' | tr '\n' ' ' )"
if [ $rcGa -ne 0 ] || [ $rcGd -ne 0 ] || ! printf '%s' "$GA" | grep -q '<whereis ' || ! printf '%s' "$GD" | grep -q '<whereis '; then
    no "whereis (guard): a run produced no <whereis> root (rc $rcGa / $rcGd)"
else
    { [ "$GT" = "44" ] && [ "$GF" = "256" ] && [ "$GTL" = "f256.c f299.c " ] \
      && printf '%s' "$GA" | grep -q '<unparsed blobs="44" rows="44" next="--whereis=guardName --whereis-listing=all --detail=1"/>'; } \
        && ok 'whereis (guard): 256 parsed (f000..f255, most rows first then path), 44 left: their rows read kind="text" (never def) and <unparsed blobs="44" rows="44" next=…--whereis-listing=all --detail=1> discloses them' \
        || { no "whereis (guard): want 256 def + 44 text rows (f256..f299) and the <unparsed> element; got def=$GF text=$GT [$GTL]"; printf '%s' "$GA" | grep -o '<unparsed[^>]*>'; }
    { [ "$( printf '%s' "$GD" | sed 's/<!--.*-->//' | tr '<' '\n' | grep '^hit ref="many" .* p="f' | grep -c 'kind="def"' )" = "300" ] \
      && ! printf '%s' "$GD" | grep -q 'kind="text"' && ! printf '%s' "$GD" | grep -q '<unparsed'; } \
        && ok 'whereis (guard): --detail=1 (the next= it names) lifts the guard: all 300 are definitions, no kind="text", no <unparsed>' \
        || no 'whereis (guard): --detail=1 did not parse every blob'
    # X1 (rule 5, recoverable via next=): the next= REPLAYS the question. Its argv, run as written, answers the same
    # listing with the guard lifted — byte for byte the explicit --whereis-listing=all --detail=1 page ($GD), not the
    # default (defs) page — and draws no "IGNORED" verb-precedence note. The default page's next= names no listing.
    GN="$( printf '%s' "$GA" | sed -n 's/.*<unparsed [^>]* next="\([^"]*\)".*/\1/p' )"
    GR="$( "$BIN" "$GG" $GN --limit=1000 --no-cache 2>"$TMP/guard.replay.err" )"; rcGr=$?
    { [ -n "$GN" ] && [ $rcGr -eq 0 ] && printf '%s' "$GR" | grep -q '<whereis ' && ! printf '%s' "$GR" | grep -q '<unparsed' \
      && [ "$GR" = "$GD" ] && ! grep -q 'IGNORED' "$TMP/guard.replay.err"; } \
        && ok "whereis (guard): the <unparsed next=> of a listing=all answer ($GN) replays it: the same listing=all page with the guard lifted" \
        || { no "whereis (guard): next='$GN' (rc $rcGr) does not replay the listing=all question with the guard lifted"; grep -o '<whereis [^>]*>' <<<"$GR"; cat "$TMP/guard.replay.err"; }
    GDN="$( "$BIN" "$GG" --whereis=guardName --no-cache 2>/dev/null | grep -o '<unparsed [^>]*>' )"
    [ "$GDN" = '<unparsed blobs="44" rows="44" next="--whereis=guardName --detail=1"/>' ] \
        && ok 'whereis (guard): the default page'"'"'s next= names no listing (the default stays the default)' \
        || no "whereis (guard): the default page's <unparsed> is '$GDN'"
    if command -v python3 >/dev/null 2>&1; then
        # The MCP `kind` ref filter has no CLI whereis spelling: next= drops it (as <refs next=> does) instead of naming
        # --stray-content=, a different verb that would take precedence over --whereis.
        GM="$( mcpq "$GG" guardName ',"kind":"man","listing":"all"' )"
        GMN="$( printf '%s' "$GM" | sed -n 's/.*<unparsed [^>]* next="\([^"]*\)".*/\1/p' )"
        GMR="$( "$BIN" "$GG" $GMN --limit=1000 --no-cache 2>"$TMP/guard.mcpreplay.err" )"; rcGmr=$?
        { printf '%s' "$GM" | grep -q '<whereis [^>]* filter="man"' && [ "$GMN" = '--whereis=guardName --whereis-listing=all --detail=1' ] \
          && [ $rcGmr -eq 0 ] && printf '%s' "$GMR" | grep -q '<whereis ' && ! printf '%s' "$GMR" | grep -q '<unparsed' \
          && ! grep -q 'IGNORED' "$TMP/guard.mcpreplay.err"; } \
            && ok 'whereis (guard): an MCP answer under kind= gives a next= with no --stray-content= (no CLI whereis ref filter), and it runs whereis with the guard lifted' \
            || { no "whereis (guard): the MCP kind= answer's next='$GMN' (rc $rcGmr) is not a whereis replay"; cat "$TMP/guard.mcpreplay.err"; }
    else
        printf '  SKIP  whereis (guard): MCP kind= next= arm (no python3)\n'
    fi
    GL="$( "$BIN" "$GG" --whereis=guardName --legend=full --no-cache 2>/dev/null )"
    GC="$( "$BIN" "$GG" --whereis=guardName --legend=compact --no-cache 2>/dev/null )"
    { printf '%s' "$GL" | grep -q 'UNPARSED: the unparsed element' && printf '%s' "$GC" | grep -q 'unparsed blobs=N' && printf '%s' "$GC" | grep -q 'unparsed rows=N' \
      && printf '%s' "$GC" | grep -q 'ref_labels=parsed' && ! printf '%s' "$GD" | grep -q 'UNPARSED'; } \
        && ok 'whereis (guard): the full legend explains <unparsed> and the compact dictionary reads blobs=/rows=/ref_labels= on the answer that carries them (and not on the --detail=1 answer)' \
        || no 'whereis (guard): a legend lacks the <unparsed> / ref_labels= readings, or carries them where the element is absent'
    if command -v xmllint >/dev/null 2>&1; then
        printf '%s' "$GL" | xmllint --noout - 2>/dev/null \
            && ok 'whereis (guard): the full-legend page with the UNPARSED clause spliced in is well-formed XML (checklist 25)' \
            || no 'whereis (guard): the full-legend page with the UNPARSED clause is malformed XML'
    else
        printf '  SKIP  whereis (guard): xmllint absent — the UNPARSED clause'"'"'s well-formedness is not checked\n'
    fi
fi

# ── 5e) every ref's tree from content-addressed tree objects (crossref.h listTreesOfRefs): ls-tree's own spelling ────
# One branch holds files whose NAMES git must quote under core.quotepath=false (a double quote, a backslash, a tab) and
# ones it must not (a space, UTF-8, a leading dash). The p= of every row equals `git ls-tree -r` for that ref, path for
# path (XML-unescaped). RED on any walk that spells a path its own way.
OD="$TMP/oddnames"; mkdir -p "$OD/d"; git -C "$OD" init -q -b main >/dev/null 2>&1; git -C "$OD" config commit.gpgsign false
printf 'int oddName( int a );\n' >"$OD/d/plain.h"; git -C "$OD" add -A >/dev/null 2>&1; git -C "$OD" commit -qm base >/dev/null 2>&1
git -C "$OD" checkout -qb odd >/dev/null 2>&1
for nm in 'q"uote.h' 'back\slash.h' "$( printf 'ta\tb.h' )" 'sp ace.h' 'caf'"$( printf '\303\251' )"'.h' -- '-lead.h'; do
    [ "$nm" = "--" ] && continue
    printf 'int oddName( int a );\n' >"$OD/d/$nm"
done
git -C "$OD" add -A >/dev/null 2>&1; git -C "$OD" commit -qm odd >/dev/null 2>&1; git -C "$OD" checkout -q main >/dev/null 2>&1
OO="$( "$BIN" "$OD" --whereis=oddName --whereis-listing=all --no-cache 2>/dev/null )"; rcOo=$?
OGOT="$( printf '%s' "$OO" | sed 's/<!--.*-->//' | tr '<' '\n' | grep '^hit ref="odd" ' | sed -n 's/.* p="\([^"]*\)" l=.*/\1/p' \
         | sed 's/&quot;/"/g; s/&apos;/'"'"'/g; s/&lt;/</g; s/&gt;/>/g; s/&amp;/\&/g' | sort )"
OWANT="$( git -c core.quotepath=false -C "$OD" ls-tree -r --name-only odd | sort )"
{ [ $rcOo -eq 0 ] && [ "$( printf '%s\n' "$OWANT" | grep -c . )" -ge 6 ] && [ "$OGOT" = "$OWANT" ]; } \
    && ok 'whereis (tree walk): every row'"'"'s p= is git ls-tree'"'"'s own spelling — quoted (", \, tab) and unquoted (space, UTF-8, leading dash) alike' \
    || { no "whereis (tree walk): p= differs from git ls-tree's spelling (rc $rcOo)"; printf 'got:\n%s\nwant:\n%s\n' "$OGOT" "$OWANT"; }

# ── 5f) train 26c (#339 x the parsed branch labels): a branch's Rails schema column reads as HEAD's index reads it ────
# HEAD's index makes a db/schema.rb column a definition (#339: captureRubyDefs, the schema recognized by content), and another
# ref's blob is parsed by the SAME extraction in its DefinitionsOnly posture (ingest_sidecap.h: the Ruby def walk runs before
# that posture's early return). So a column a branch adds reads kind="def" once its blob earns a parse (a parse-worthy hit line
# in it), as HEAD's own copy of a column does. RED if the Ruby def walk sat behind the DefinitionsOnly return (measured: the
# column row reads kind="ref"); the premise is HEAD's index labelling its own column a definition.
RS="$TMP/rbschema"; mkdir -p "$RS/db" "$RS/other"; git -C "$RS" init -q -b main >/dev/null 2>&1; git -C "$RS" config commit.gpgsign false
printf 'ActiveRecord::Schema[7.1].define(version: 2024_01_01_000000) do\n  create_table "users", force: :cascade do |t|\n    t.string "email"\n  end\nend\n' >"$RS/db/schema.rb"
printf 'ActiveRecord::Schema[7.1].define(version: 2024_01_01_000000) do\n  create_table "accounts", force: :cascade do |t|\n    t.string "nickname"\n  end\nend\n' >"$RS/other/schema.rb"
git -C "$RS" add -A >/dev/null 2>&1; git -C "$RS" commit -qm base >/dev/null 2>&1; git -C "$RS" checkout -qb feat >/dev/null 2>&1
printf 'ActiveRecord::Schema[7.1].define(version: 2024_02_01_000000) do\n  create_table "users", force: :cascade do |t|\n    t.string "email"\n    t.string "nickname"\n  end\nend\ndef nickname( x )\n  x\nend\n' >"$RS/db/schema.rb"
git -C "$RS" commit -qam feat >/dev/null 2>&1; git -C "$RS" checkout -q main >/dev/null 2>&1
RSO="$( "$BIN" "$RS" --whereis=nickname --whereis-listing=all --no-cache 2>/dev/null )"; rcRs=$?
RSHEAD="$( printf '%s' "$RSO" | grep -oE '<hit ref="HEAD" p="other/schema\.rb" l="3" kind="[a-z]+"' | head -1 )"
RSCOL="$( printf '%s' "$RSO" | grep -oE '<hit ref="feat" [^>]*p="db/schema\.rb" l="4" kind="[a-z]+"' | head -1 )"
if [ $rcRs -ne 0 ] || [ "${RSHEAD##*kind=}" != '"def"' ]; then
    no "whereis (#339 x parsed labels): premise — HEAD's index labels its own schema column a def (rc $rcRs, got: ${RSHEAD:-no row})"
elif [ "${RSCOL##*kind=}" = '"def"' ]; then
    ok 'whereis (#339 x parsed labels): a column a branch adds to db/schema.rb reads kind="def", as HEAD'"'"'s index reads its own'
else
    no "whereis (#339 x parsed labels): the branch's schema column is not a def (got: ${RSCOL:-no row})"
fi

# ── 5g) train 26c (cli-perf-068 x the tree-object walk): the ls-tree fallback lists each DISTINCT tip once ─────────────
# A root below the top of the work tree cannot use the tree-object walk (listTreesOfRefs), so the trees come from
# `git ls-tree -r`, one per distinct tip (crossref.h listDistinctTips): HEAD + b2 + b3 sit on 2 tips (b3 = b2's tip; b1, at
# HEAD's tip, is not swept), so 2 listings, not one per ref, and the same 8 rows. RED on a per-ref fallback (3 listings).
LT="$TMP/lstips"; mkdir -p "$LT/sub"; git -C "$LT" init -q -b main >/dev/null 2>&1; git -C "$LT" config commit.gpgsign false
printf 'int tipProbe( int x ) { return x; }\nint tipCaller( void ) { return tipProbe( 1 ); }\n' >"$LT/sub/a.c"; printf 'top\n' >"$LT/top.txt"
git -C "$LT" add -A >/dev/null 2>&1; git -C "$LT" commit -qm one >/dev/null 2>&1; git -C "$LT" branch b1 >/dev/null 2>&1
git -C "$LT" checkout -qb b2 >/dev/null 2>&1; printf 'int tipProbe( int x, int y ) { return x + y; }\n' >"$LT/sub/b.c"
git -C "$LT" add -A >/dev/null 2>&1; git -C "$LT" commit -qm two >/dev/null 2>&1; git -C "$LT" branch b3 >/dev/null 2>&1; git -C "$LT" checkout -q main >/dev/null 2>&1
: >"$TMP/lstips.trace"
LTO="$( GIT_TRACE="$TMP/lstips.trace" "$BIN" "$LT/sub" --whereis=tipProbe --whereis-listing=all --no-cache 2>/dev/null )"; rcLt=$?
LTN="$( grep -c 'built-in: git ls-tree' "$TMP/lstips.trace" )"
LTH="$( printf '%s' "$LTO" | grep -oE '<whereis [^>]* hits="[0-9]+"' | grep -oE 'hits="[0-9]+"' )"
LTR="$( printf '%s' "$LTO" | grep -oE '<whereis [^>]* refs_scanned="[0-9]+"' | grep -oE 'refs_scanned="[0-9]+"' )"
{ [ $rcLt -eq 0 ] && [ "$LTR" = 'refs_scanned="2"' ] && [ "$LTH" = 'hits="8"' ] && [ "$LTN" = 2 ]; } \
    && ok "whereis (ls-tree fallback): a root below the work-tree top lists each distinct tip once (2 listings for HEAD + 2 refs on 2 tips), all 8 rows" \
    || no "whereis (ls-tree fallback): want rc 0, refs_scanned=\"2\", hits=\"8\" and 2 ls-tree listings — got rc $rcLt, $LTR, $LTH, $LTN listing(s)"

# ── 5h) the t= PREVIEW (lane whereis-lean; crossref.h kWhereisTextPreviewCapBytes = 200, writeWhereisRows / writeWhereisTextCut) ──
# A row's t= is a preview of a LONG line: a line over 300 bytes (kWhereisTextWholeMaxBytes, so a cut always drops 100+
# bytes) prints its first bytes, cut on a UTF-8 boundary, plus an ellipsis — 200 bytes at most, the ellipsis included —
# and the row carries t_bytes= (the whole line's bytes); <t_cut rows= next=> counts the page's cut rows and next= replays
# THIS page with --whereis-full-text (same listing, window, rows and labels; every line whole). A page prints previews only
# when that makes it shorter than the same page whole (writeWhereisPage; the 5h-C2 arms below). Arms: a ~7 KB def line (HEAD, the defs
# page), lines of exactly 200, 201 and 300 bytes (whole), one of 301 (cut to 200), a 3-byte character straddling the kept
# prefix (cut before it), a short line (unchanged, no t_bytes=), a branch row (tip= date= beside t_bytes=), the refs and
# all listings, the MCP twin, paging (rows= counts this page), and an answer of short lines (no t_cut, no clause).
# RED on the pre-lane binary (4c38d363): every t= is the whole line and no row carries t_bytes=.
PV="$TMP/preview"; mkdir -p "$PV"; git -C "$PV" init -q -b main >/dev/null 2>&1; git -C "$PV" config commit.gpgsign false
pvRep(){ i=0; s=''; while [ $i -lt "$2" ]; do s="$s$1"; i=$((i+1)); done; printf '%s' "$s"; }
PV_LONG="int previewName( int a ) { return a$( pvRep ' + 1' 1750 ); }"                    # 7,000+ bytes, the definition
PV_200="X = previewName + $( pvRep a 182 )"                                               # 18 + 182 = exactly 200 bytes
PV_201="Y = previewName + $( pvRep b 183 )"                                               # 201 bytes
PV_300="V = previewName + $( pvRep e 282 )"                                               # 300 bytes
PV_301="W = previewName + $( pvRep f 283 )"                                               # 301 bytes
PV_EUR="Z = previewName + $( pvRep c 178 )€$( pvRep d 140 )"                             # 339 bytes, € at bytes 196-198 straddles 197
printf '%s\n' "$PV_LONG" >"$PV/p.c"
printf '%s\n%s\n%s\n%s\n%s\npreviewName( 1 )\n' "$PV_200" "$PV_201" "$PV_300" "$PV_301" "$PV_EUR" >"$PV/q.py"
printf 'int shortName( int a ) { return a; }\nint shortUse( void ) { return shortName( 1 ); }\n' >"$PV/s.c"
git -C "$PV" add -A >/dev/null 2>&1; git -C "$PV" commit -qm base >/dev/null 2>&1
git -C "$PV" checkout -qb side >/dev/null 2>&1
PV_BR="int previewName( long a ) { return a$( pvRep ' - 2' 400 ); }"
printf '%s\n' "$PV_BR" >"$PV/b.c"; git -C "$PV" add -A >/dev/null 2>&1; git -C "$PV" commit -qm side >/dev/null 2>&1
git -C "$PV" checkout -q main >/dev/null 2>&1
pvRow(){ printf '%s' "$1" | sed 's/<!--.*-->//' | tr '<' '\n' | grep "^hit ref=\"$2\" .*p=\"$3\" l=\"$4\" " | head -1; }
pvT(){ printf '%s' "$1" | sed -n 's/.* t="\(.*\)"\/>*$/\1/p' | sed 's/"\/$//'; }
pvB(){ LC_ALL=C; printf '%s' "$1" | wc -c | tr -d ' '; }
# pvSame PAGE REPLAY: "same" when the replay lists the page's rows (every attribute but t= and t_bytes=, in order, so the
# same refs, paths, lines and kind= labels) and each row's t= is whole: the length of a cut row's t_bytes=, else the page's
# own t= length; and the replay is no longer than the page plus the bytes its cuts dropped (rule 5: about the page's bytes,
# never a different, larger answer). Else the first difference. The fixtures' long lines hold no XML-escaped character.
pvSig(){ printf '%s' "$1" | sed 's/<!--.*-->//' | tr '<' '\n' | grep '^hit ' | sed -E 's/ t_bytes="[0-9]+"//; s/ t=".*//'; }
pvLen(){ printf '%s' "$1" | sed 's/<!--.*-->//' | tr '<' '\n' | grep '^hit ' \
         | LC_ALL=C awk '{ tb = "-"; if( match( $0, / t_bytes="[0-9]+"/ ) ) { tb = substr( $0, RSTART + 10, RLENGTH - 11 ) }
                           t = $0; sub( /^.* t="/, "", t ); sub( /"\/>?$/, "", t ); print tb, length( t ) }'; }
pvSame(){
    local a b
    a="$( pvSig "$1" )"; b="$( pvSig "$2" )"
    [ -n "$a" ] || { printf 'no rows on the page'; return; }
    [ "$a" = "$b" ] || { printf 'rows differ: page %s, replay %s' "$( printf '%s\n' "$a" | grep -c . )" "$( printf '%s\n' "$b" | grep -c . )"; return; }
    paste -d' ' <( pvLen "$1" ) <( pvLen "$2" ) | LC_ALL=C awk -v pb="$( pvB "$1" )" -v rb="$( pvB "$2" )" '
        { want = ( $1 == "-" ) ? $2 : $1; if( $3 != "-" || $4 != want ) { bad = bad " row " NR ": t_bytes " $1 " page " $2 " replay " $4 }
          if( $1 != "-" ) { dropped += $1 - $2 } }
        END { if( bad != "" ) { print "lines not whole:" bad } else if( rb > pb + dropped ) { print "replay " rb " B > page " pb " + dropped " dropped }
              else { print "same" } }'
}
PA="$( "$BIN" "$PV" --whereis=previewName --whereis-listing=all --no-cache 2>/dev/null )"; rcPa=$?
PD="$( "$BIN" "$PV" --whereis=previewName --no-cache 2>/dev/null )"; rcPd=$?
PR="$( "$BIN" "$PV" --whereis=previewName --whereis-listing=refs --no-cache 2>/dev/null )"; rcPr=$?
if [ $rcPa -ne 0 ] || [ $rcPd -ne 0 ] || [ $rcPr -ne 0 ] || ! printf '%s' "$PA" | grep -q '<whereis ' || ! printf '%s' "$PD" | grep -q '<whereis ' \
   || ! printf '%s' "$PR" | grep -q '<whereis '; then
    no "whereis (preview): a run produced no <whereis> root (rc $rcPa / $rcPd / $rcPr)"
else
    ELL='…'
    r="$( pvRow "$PD" HEAD p.c 1 )"; t="$( pvT "$r" )"
    { printf '%s' "$r" | grep -q "kind=\"def\" t_bytes=\"$( pvB "$PV_LONG" )\" t=" && [ "$( pvB "$t" )" -le 200 ] && [ "${t%$ELL}" != "$t" ] \
      && [ "${PV_LONG#"${t%$ELL}"}" != "$PV_LONG" ] && [ "$( pvB "$t" )" = 200 ]; } \
        && ok "whereis (preview): the $( pvB "$PV_LONG" )-byte definition line prints a 200-byte t= (its first 197 bytes + …) and t_bytes=\"$( pvB "$PV_LONG" )\" on the defs page" \
        || no "whereis (preview): the long def row is '${r:0:300}' ($( pvB "$t" ) B t=)"
    for pv in "1|$PV_200|200" "2|$PV_201|201" "3|$PV_300|300"; do
        r="$( pvRow "$PA" HEAD q.py "${pv%%|*}" )"; w="${pv#*|}"; w="${w%|*}"
        { [ "$( pvT "$r" )" = "$w" ] && [ "$( pvB "$w" )" = "${pv##*|}" ] && ! printf '%s' "$r" | grep -q 't_bytes='; } \
            && ok "whereis (preview): a line of exactly ${pv##*|} bytes prints whole, no ellipsis, no t_bytes=" \
            || no "whereis (preview): the ${pv##*|}-byte line's row is '${r:0:300}'"
    done
    r="$( pvRow "$PA" HEAD q.py 4 )"; t="$( pvT "$r" )"
    { printf '%s' "$r" | grep -q 't_bytes="301"' && [ "$( pvB "$t" )" = 200 ] && [ "$t" = "${PV_301:0:197}$ELL" ]; } \
        && ok 'whereis (preview): a 301-byte line prints its first 197 bytes + … (200 bytes, the ellipsis included) and t_bytes="301"' \
        || no "whereis (preview): the 301-byte line's row is '${r:0:300}' ($( pvB "$t" ) B)"
    r="$( pvRow "$PA" HEAD q.py 5 )"; t="$( pvT "$r" )"; pre="$( LC_ALL=C; printf '%s' "$PV_EUR" | head -c 196 )"
    { printf '%s' "$r" | grep -q "t_bytes=\"$( pvB "$PV_EUR" )\"" && [ "$t" = "$pre$ELL" ] && [ "$( pvB "$t" )" = 199 ] \
      && printf '%s' "$t" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1; } \
        && ok 'whereis (preview): a 3-byte € straddling the kept prefix is not split: the cut backs off to byte 196, + … (199 bytes, valid UTF-8)' \
        || no "whereis (preview): the straddle row is '${r:0:300}' ($( pvB "$t" ) B)"
    r="$( pvRow "$PA" HEAD q.py 6 )"
    { [ "$( pvT "$r" )" = 'previewName( 1 )' ] && ! printf '%s' "$r" | grep -q 't_bytes='; } \
        && ok 'whereis (preview): a short line prints unchanged, with no t_bytes=' \
        || no "whereis (preview): the short row is '$r'"
    r="$( pvRow "$PA" side b.c 1 )"; t="$( pvT "$r" )"
    { printf '%s' "$r" | grep -q " tip=\"[0-9a-f]\{9\}\" date=\"2026-01-01\" .*kind=\"def\" t_bytes=\"$( pvB "$PV_BR" )\" t=" && [ "$( pvB "$t" )" -le 200 ] \
      && [ "${PV_BR#"${t%$ELL}"}" != "$PV_BR" ]; } \
        && ok 'whereis (preview): a branch row (tip= date=) is cut the same way and carries t_bytes=' \
        || no "whereis (preview): the branch row is '${r:0:300}'"
    nA="$( printf '%s' "$PA" | sed 's/<!--.*-->//' | grep -o ' t_bytes="' | wc -l | tr -d ' ' )"
    # HEAD: p.c, the 301 and the € lines; side holds the same two blobs (3 more) and b.c: 7 previews on the all page.
    { [ "$nA" = 7 ] && printf '%s' "$PA" | grep -q '<t_cut rows="7" next="--whereis=previewName --whereis-listing=all --whereis-full-text"/>'; } \
        && ok 'whereis (preview): <t_cut rows="7" next=…--whereis-listing=all --whereis-full-text> counts exactly the page'"'"'s 7 t_bytes= rows' \
        || { no "whereis (preview): want 7 t_bytes= rows and their <t_cut>; got $nA"; printf '%s' "$PA" | grep -o '<t_cut[^>]*>'; }
    # (C2, review whereis-lean) the refs page's only long lines are the 301- and 339-byte ones (twice each): cutting them drops
    # 2 x (101 + 140) bytes and its disclosure (t_bytes=, <t_cut>, the clause or the readings) costs more, so the page prints
    # whole, byte-identical to its --whereis-full-text twin, under both legends. RED when every page with a long line cuts.
    PRF="$( "$BIN" "$PV" --whereis=previewName --whereis-listing=refs --whereis-full-text --no-cache 2>/dev/null )"
    PRL="$( "$BIN" "$PV" --whereis=previewName --whereis-listing=refs --legend=full --no-cache 2>/dev/null )"
    PRLF="$( "$BIN" "$PV" --whereis=previewName --whereis-listing=refs --legend=full --whereis-full-text --no-cache 2>/dev/null )"
    r="$( pvRow "$PR" HEAD q.py 4 )"
    { [ "$( pvT "$r" )" = "$PV_301" ] && ! printf '%s' "$PR" | grep -q 't_bytes=\|<t_cut' && [ -n "$PRF" ] && [ "$PR" = "$PRF" ] \
      && printf '%s' "$PRL" | grep -q '<whereis ' && [ "$PRL" = "$PRLF" ]; } \
        && ok 'whereis (preview, C2): a refs page whose only long lines are 301 and 339 bytes prints them whole: byte-identical to its full-text twin, compact and full legend' \
        || { no "whereis (preview, C2): the near-threshold refs page cut a row or differs from its full-text twin: '${r:0:200}'"; printf '%s' "$PR" | grep -o '<t_cut[^>]*>'; }
    # Rule 5 (recoverable via next=): the next= argv, run as written, is THIS page with every line whole — the same rows in
    # the same order with the same labels (pvSame), each cut row's line whole (its length is the page's t_bytes=), no t_bytes=,
    # no <t_cut>.
    PN="$( printf '%s' "$PA" | sed -n 's/.*<t_cut [^>]* next="\([^"]*\)".*/\1/p' )"
    PX="$( "$BIN" "$PV" $PN --no-cache 2>"$TMP/preview.replay.err" )"; rcPx=$?
    { [ -n "$PN" ] && [ $rcPx -eq 0 ] && printf '%s' "$PX" | grep -q '<whereis ' && ! printf '%s' "$PX" | grep -q 't_bytes=\|<t_cut' \
      && [ "$( pvT "$( pvRow "$PX" HEAD p.c 1 )" )" = "$PV_LONG" ] && [ "$( pvT "$( pvRow "$PX" side b.c 1 )" )" = "$PV_BR" ] \
      && [ "$( pvSame "$PA" "$PX" )" = same ] && ! grep -q 'IGNORED' "$TMP/preview.replay.err"; } \
        && ok "whereis (preview): the <t_cut next=> ($PN) is the same page, every line whole (the 7 KB def, the branch def), no t_bytes= and no <t_cut>" \
        || no "whereis (preview): next='$PN' (rc $rcPx) is not the same page with whole lines: $( pvSame "$PA" "$PX" )"
    P1="$( "$BIN" "$PV" --whereis=previewName --whereis-listing=all --limit=1 --offset=0 --no-cache 2>/dev/null )"
    # A paged page's next= carries its own window: --limit (and --offset when it is past 0), so the replay is that page.
    PK="$( printf '%s' "$PA" | sed 's/<!--.*-->//' | tr '<' '\n' | grep '^hit ' | grep -n ' p="b.c" ' | head -1 | cut -d: -f1 )"; PK=$(( ${PK:-1} - 1 ))
    P3="$( "$BIN" "$PV" --whereis=previewName --whereis-listing=all --limit=1 --offset=$PK --no-cache 2>/dev/null )"
    P3N="$( printf '%s' "$P3" | sed -n 's/.*<t_cut [^>]* next="\([^"]*\)".*/\1/p' )"
    P3X="$( "$BIN" "$PV" $P3N --no-cache 2>/dev/null )"
    { [ "$PK" -gt 0 ] && [ "$P3N" = "--whereis=previewName --whereis-listing=all --limit=1 --offset=$PK --whereis-full-text" ] \
      && [ "$( pvSame "$P3" "$P3X" )" = same ] && [ "$( pvT "$( pvRow "$P3X" side b.c 1 )" )" = "$PV_BR" ] \
      && [ "$( printf '%s' "$P1" | sed -n 's/.*<t_cut [^>]* next="\([^"]*\)".*/\1/p' )" = '--whereis=previewName --whereis-listing=all --limit=1 --whereis-full-text' ]; } \
        && ok "whereis (preview): a paged page's <t_cut next=> carries its window (--limit=1 --offset=$PK; offset 0 is the default) and replays that one row whole" \
        || no "whereis (preview): the paged next= is '$P3N' (offset $PK): $( pvSame "$P3" "$P3X" )"
    P5="$( "$BIN" "$PV" --whereis=previewName --whereis-listing=all --limit=1 --offset=2 --no-cache 2>/dev/null )"
    { printf '%s' "$P1" | grep -q '<t_cut rows="1" ' && ! printf '%s' "$P5" | grep -q '<t_cut\|t_bytes=\|PREVIEW: \|t_bytes=N'; } \
        && ok 'whereis (preview): paged, rows= counts this page'"'"'s cut rows; a page of short rows carries no <t_cut>, no t_bytes= and no reading' \
        || { no 'whereis (preview): the paged <t_cut rows=> or its absence is wrong'; printf '%s\n%s' "$P1" "$P5" | grep -o '<t_cut[^>]*>\|<hit [^>]*l="[0-9]*"'; }
    PS="$( "$BIN" "$PV" --whereis=shortName --whereis-listing=all --legend=full --no-cache 2>/dev/null )"; rcPs=$?
    { [ $rcPs -eq 0 ] && printf '%s' "$PS" | grep -q '<hit ' && ! printf '%s' "$PS" | grep -q 't_bytes\|<t_cut\|PREVIEW: '; } \
        && ok 'whereis (preview): an answer of short lines carries no t_bytes=, no <t_cut> and no PREVIEW clause (byte-identical to before the cap)' \
        || no "whereis (preview): the short-lines answer (rc $rcPs) carries a preview disclosure"
    PL="$( "$BIN" "$PV" --whereis=previewName --whereis-listing=all --legend=full --no-cache 2>/dev/null )"
    PC="$( "$BIN" "$PV" --whereis=previewName --whereis-listing=all --legend=compact --no-cache 2>/dev/null )"
    { printf '%s' "$PL" | grep -q 'PREVIEW: t= is the row'"'"'s trimmed source line when it fits 300 bytes; a longer line prints a preview of 200 bytes' \
      && printf '%s' "$PL" | grep -q 'its next= replays THIS page (its listing, window, rows and labels) with the whereis full text flag (MCP full_text)' \
      && printf '%s' "$PC" | grep -q 'hit t_bytes=N: t= previews an N-byte line (over 300 B): 200 B at most' \
      && printf '%s' "$PC" | grep -q 't_cut rows=N: rows of this page whose t= is a preview (each carries t_bytes=); next= replays this page' \
      && ! printf '%s' "$PX" | grep -q 'PREVIEW: \|t_bytes=N'; } \
        && ok 'whereis (preview): the full legend carries the PREVIEW clause and the compact one reads t_bytes= and t_cut rows= (300 B / 200 B, the binary'"'"'s constants), only where a row was cut' \
        || no 'whereis (preview): a legend lacks the PREVIEW clause / readings, or carries them on the uncut --detail=1 answer'
    if command -v xmllint >/dev/null 2>&1; then
        printf '%s' "$PL" | xmllint --noout - 2>/dev/null && printf '%s' "$PC" | xmllint --noout - 2>/dev/null \
            && ok 'whereis (preview): the full-legend page with the PREVIEW clause spliced in, and the compact page, are well-formed XML (checklist 25)' \
            || no 'whereis (preview): a page carrying the PREVIEW clause is malformed XML'
    else
        printf '  SKIP  whereis (preview): xmllint absent — the PREVIEW clause'"'"'s well-formedness is not checked\n'
    fi
    if command -v python3 >/dev/null 2>&1; then
        PM="$( mcpq "$PV" previewName ',"listing":"all"' )"
        { [ "$PM" = "$PA" ]; } \
            && ok 'whereis (preview): the MCP twin serves the CLI page byte for byte (t_bytes= rows and <t_cut>)' \
            || { no 'whereis (preview): the MCP whereis page differs from the CLI one'; diff <( printf '%s' "$PA" | tr '<' '\n' ) <( printf '%s' "$PM" | tr '<' '\n' ) | head -5; }
        # full_text, the MCP twin of --whereis-full-text: the same whole-line page byte for byte; false is the default page.
        PMF="$( mcpq "$PV" previewName ',"listing":"all","full_text":true' )"; PMN="$( mcpq "$PV" previewName ',"listing":"all","full_text":false' )"
        { [ -n "$PX" ] && [ "$PMF" = "$PX" ] && [ "$PMN" = "$PA" ]; } \
            && ok 'whereis (preview): MCP full_text:true serves the CLI --whereis-full-text page byte for byte; full_text:false the default page' \
            || no 'whereis (preview): MCP full_text differs from the CLI --whereis-full-text page'
        # Checklist 26: full_text is read with the other typed arguments, before the shared shape gate, so a wrong-shaped value
        # refuses -32602 and the refusal echoes what was SENT (a read inside the whereis arm would decode "yes" to false and answer).
        for arm in '"yes"|yes' '1|1' '["true"]|["true"]'; do
            val="${arm%%|*}"; echo_="${arm#*|}"
            m="$( printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"whereis","arguments":{"path":"%s","symbol":"previewName","full_text":%s}}}\n' "$PV" "$val" \
                  | "$BIN" --mcp 2>/dev/null | python3 -c 'import sys,json
for line in sys.stdin:
    line=line.strip()
    if not line: continue
    d=json.loads(line)
    if "error" in d: print("ERROR",d["error"].get("code"),d["error"].get("message",""),end="")
    elif d.get("result",{}).get("isError"): print("ISERROR","".join(x.get("text","") for x in d["result"]["content"]),end="")
    elif d.get("result",{}).get("content"): print("ANSWER",end="")' )"
            case "$m" in
                "ISERROR invalid value for field: full_text"*"got '$echo_'"*) ok "whereis (preview): MCP full_text:$val refuses (isError, SEP-1303) and echoes '$echo_'" ;;
                *) no "whereis (preview): MCP full_text:$val — want a -32602 refusal echoing '$echo_', got: ${m:-nothing}" ;;
            esac
        done
    else
        printf '  SKIP  whereis (preview): MCP twin arms (no python3)\n'
    fi
    "$BIN" "$PV" --whereis-full-text --no-cache >/dev/null 2>"$TMP/preview.lone.err"; rcLone=$?
    { [ $rcLone -ne 0 ] && grep -q -- '--whereis-full-text modifies --whereis=SYM' "$TMP/preview.lone.err"; } \
        && ok 'whereis (preview): --whereis-full-text alone refuses (rc 1) and names --whereis=SYM' \
        || no "whereis (preview): --whereis-full-text alone gave rc $rcLone: $( head -c 200 "$TMP/preview.lone.err" )"
fi

# ── 5h-C2) a page prints previews only when that makes it SHORTER (review whereis-lean C2; crossref.h writeWhereisPage) ──
# One short definition and one reference line of L bytes per symbol. The cut page pays for its disclosure (t_bytes=, <t_cut>,
# and the full PREVIEW clause or the compact readings), so a line just past 300 bytes saves less than that: the page must
# print whole, byte-identical to its --whereis-full-text twin, and a 2 KB line still cuts. For every L and listing, under
# both legends: the page is its whole twin or strictly shorter than it, it cuts under one legend exactly when it cuts under
# the other, and the default listing is the whole twin's (a cut never flips it: L=345 is review C2b, where the cut page
# used to tip the default from all to defs, fewer rows for more bytes). RED on 9f51cca7, which cut every long line.
CW="$TMP/cutwidth"; mkdir -p "$CW"; git -C "$CW" init -q -b main >/dev/null 2>&1; git -C "$CW" config commit.gpgsign false
for L in 302 345 395 501 601 701 2000; do
    printf 'int zqW%s( int a ) { return a; }\n' "$L" >"$CW/d$L.c"
    pre="int u$L( void ) { return zqW$L( 1 ); } // "
    printf '%s%s\n' "$pre" "$( pvRep r $(( L - ${#pre} )) )" >"$CW/u$L.c"
done
git -C "$CW" add -A >/dev/null 2>&1; git -C "$CW" commit -qm widths >/dev/null 2>&1
cwBad=''; cwRuns=0
for L in 302 345 395 501 601 701 2000; do
    for lst in '' --whereis-listing=all; do
        cut=''
        for leg in full compact; do
            pg="$( "$BIN" "$CW" --whereis=zqW$L $lst --legend=$leg --no-cache 2>/dev/null )"; rcG=$?
            wh="$( "$BIN" "$CW" --whereis=zqW$L $lst --legend=$leg --whereis-full-text --no-cache 2>/dev/null )"; rcW=$?
            cwRuns=$(( cwRuns + 1 ))
            { [ $rcG -eq 0 ] && [ $rcW -eq 0 ] && printf '%s' "$pg" | grep -q '<hit ' && printf '%s' "$wh" | grep -q '<hit '; } \
                || { cwBad="$cwBad [L=$L $lst $leg: rc $rcG/$rcW or no rows]"; continue; }
            c=0; printf '%s' "$pg" | grep -q 't_bytes=' && c=1
            cut="$cut$c"
            [ "$( printf '%s' "$pg" | grep -o '<whereis [^>]*>' | grep -o ' listing="[a-z]*"' )" = "$( printf '%s' "$wh" | grep -o '<whereis [^>]*>' | grep -o ' listing="[a-z]*"' )" ] \
                || cwBad="$cwBad [L=$L $lst $leg: the listing differs from the whole twin's]"
            if [ $c -eq 0 ]; then
                [ "$pg" = "$wh" ] || cwBad="$cwBad [L=$L $lst $leg: uncut but not byte-identical to the whole twin]"
            else
                [ "$( pvB "$pg" )" -lt "$( pvB "$wh" )" ] || cwBad="$cwBad [L=$L $lst $leg: cut page $( pvB "$pg" ) B >= whole $( pvB "$wh" ) B]"
            fi
            case "$L|$lst|$c" in 302\|*\|1|345\|*\|1|395\|*\|1) cwBad="$cwBad [L=$L $lst $leg: a near-threshold line was cut]" ;; 2000\|--whereis-listing=all\|0) cwBad="$cwBad [L=2000 all $leg: a 2 KB line was not cut]" ;; esac
        done
        case "$cut" in 00|11) ;; *) cwBad="$cwBad [L=$L $lst: cut under one legend only ($cut)]" ;; esac
    done
done
C2B="$( "$BIN" "$CW" --whereis=zqW345 --no-cache 2>/dev/null | grep -o '<whereis [^>]*>' )"
{ [ -z "$cwBad" ] && [ "$cwRuns" = 28 ] && printf '%s' "$C2B" | grep -q ' shown="2"' && ! printf '%s' "$C2B" | grep -q ' listing='; } \
    && ok 'whereis (preview, C2): 7 widths x 2 listings x 2 legends: each page is its whole twin or strictly shorter, cuts under both legends or neither, keeps the twin'"'"'s listing; 302/345/395 B print whole, a 2 KB line cuts; the L=345 default stays the all page (2 rows)' \
    || no "whereis (preview, C2): $cwRuns runs;$cwBad; L=345 default root: $C2B"
CWR="$( "$BIN" "$CW" --whereis=zqW2000 --whereis-listing=refs --no-cache 2>/dev/null )"
CWN="$( printf '%s' "$CWR" | sed -n 's/.*<t_cut [^>]* next="\([^"]*\)".*/\1/p' )"
CWX="$( "$BIN" "$CW" $CWN --no-cache 2>/dev/null )"
{ [ "$CWN" = '--whereis=zqW2000 --whereis-listing=refs --whereis-full-text' ] && [ "$( pvSame "$CWR" "$CWX" )" = same ]; } \
    && ok 'whereis (preview, C2): the refs listing cuts a 2 KB line and its <t_cut next=> names listing=refs and replays the row whole' \
    || no "whereis (preview, C2): the refs page's next= is '$CWN': $( pvSame "$CWR" "$CWX" )"

# ── 5h-X2) the <t_cut next=> is THE SAME PAGE, every line whole (review whereis-lean C1; crossref.h whereisFullTextNext) ──
# The guard binds (300 distinct blobs on one branch, each a 400-byte call line at column 0, parse-worthy): 256 are parsed
# (kind="ref", counted on the defs page), 44 are left and read kind="text" — listed on the defs page as cut previews. The
# replay must keep the guard (the same 44 kind="text" rows, now whole: --detail=1 lifted it, relabelled them kind="ref"
# and dropped all 44 from the defs page), the row cap and the window (a listing=all page of 60 rows replays 60, not the
# 302-row hit list; a --limit/--offset page replays that page). RED on 9f51cca7 (next= was --detail=1).
XG="$TMP/xguard"; mkdir -p "$XG"; git -C "$XG" init -q -b main >/dev/null 2>&1; git -C "$XG" config commit.gpgsign false
printf 'def zqText( a ):\n    return a\n' >"$XG/a.py"; git -C "$XG" add -A >/dev/null 2>&1; git -C "$XG" commit -qm base >/dev/null 2>&1
git -C "$XG" checkout -qb many >/dev/null 2>&1; XPAD="$( pvRep x 400 )"
i=0; while [ $i -lt 300 ]; do printf 'zqText( %s, %d )\n' "$XPAD" $i >"$XG/t$( printf '%03d' $i ).py"; i=$((i+1)); done
git -C "$XG" add -A >/dev/null 2>&1; git -C "$XG" commit -qm many >/dev/null 2>&1; git -C "$XG" checkout -q main >/dev/null 2>&1
xNext(){ printf '%s' "$1" | sed -n 's/.*<t_cut [^>]* next="\([^"]*\)".*/\1/p'; }
xKind(){ printf '%s' "$1" | sed 's/<!--.*-->//' | grep -o 'kind="text"' | wc -l | tr -d ' '; }
XD="$( "$BIN" "$XG" --whereis=zqText --no-cache 2>/dev/null )"; XDN="$( xNext "$XD" )"; XDX="$( "$BIN" "$XG" $XDN --no-cache 2>/dev/null )"
{ [ "$XDN" = '--whereis=zqText --whereis-listing=defs --whereis-full-text' ] && printf '%s' "$XD" | grep -q '<t_cut rows="44" ' \
  && [ "$( xKind "$XD" )" = 44 ] && [ "$( xKind "$XDX" )" = 44 ] && [ "$( pvSame "$XD" "$XDX" )" = same ] \
  && printf '%s' "$XDX" | grep -q '<unparsed blobs="44" rows="44" ' && ! printf '%s' "$XDX" | grep -q 't_bytes=\|<t_cut'; } \
    && ok 'whereis (full text): the guard-bound defs page cuts 44 kind="text" rows and its next= (listing=defs, full text) replays the same 44 kind="text" rows whole, the guard kept' \
    || no "whereis (full text): defs page next='$XDN', text rows $( xKind "$XD" ) -> $( xKind "$XDX" ): $( pvSame "$XD" "$XDX" )"
XA="$( "$BIN" "$XG" --whereis=zqText --whereis-listing=all --no-cache 2>/dev/null )"; XAN="$( xNext "$XA" )"; XAX="$( "$BIN" "$XG" $XAN --no-cache 2>/dev/null )"
{ [ "$XAN" = '--whereis=zqText --whereis-listing=all --whereis-full-text' ] && printf '%s' "$XA" | grep -q '<whereis [^>]* shown="60" capped="1"' \
  && [ "$( pvSig "$XAX" | grep -c . )" = 60 ] && [ "$( pvSame "$XA" "$XAX" )" = same ]; } \
    && ok "whereis (full text): a capped listing=all page (60 of 302 rows) replays the same 60 rows whole, $( pvB "$XAX" ) B for a $( pvB "$XA" ) B page (not the whole hit list)" \
    || no "whereis (full text): the listing=all page's next='$XAN' replays $( pvSig "$XAX" | grep -c . ) rows: $( pvSame "$XA" "$XAX" )"
XP="$( "$BIN" "$XG" --whereis=zqText --whereis-listing=all --limit=5 --offset=7 --no-cache 2>/dev/null )"; XPN="$( xNext "$XP" )"; XPX="$( "$BIN" "$XG" $XPN --no-cache 2>/dev/null )"
{ [ "$XPN" = '--whereis=zqText --whereis-listing=all --limit=5 --offset=7 --whereis-full-text' ] && [ "$( pvSig "$XPX" | grep -c . )" = 5 ] \
  && [ "$( pvSame "$XP" "$XPX" )" = same ]; } \
    && ok 'whereis (full text): a --limit=5 --offset=7 page replays those 5 rows whole (its next= carries the window)' \
    || no "whereis (full text): the paged next='$XPN': $( pvSame "$XP" "$XPX" )"

# ── 5h-D1) a page the MCP kind ref filter bounded DISCLOSES that its <t_cut next=> drops the filter (review whereis-lean D1) ──
# The CLI has no whereis ref filter, so the next= of a kind-filtered page replays the unfiltered listing (other rows). The
# page says so: <t_cut uncarried="FILTER">, the full PREVIEW clause names the recovery (MCP whereis with full_text:true), and
# that recovery IS the page's rows whole. An unfiltered page carries neither. RED on a4884e41 (no uncarried=, no clause).
if command -v python3 >/dev/null 2>&1; then
    git -C "$XG" checkout -qb zz >/dev/null 2>&1; XLONG="$( pvRep y 1000 )"
    i=0; while [ $i -lt 10 ]; do printf 'zqText( %s, %d )\n' "$XLONG" $i >"$XG/z$i.py"; i=$((i+1)); done
    git -C "$XG" add -A >/dev/null 2>&1; git -C "$XG" commit -qm zz >/dev/null 2>&1; git -C "$XG" checkout -q main >/dev/null 2>&1
    XF="$( mcpq "$XG" zqText ',"kind":"zz","listing":"all","legend":"full"' )"; XFN="$( xNext "$XF" )"
    XFR="$( "$BIN" "$XG" $XFN --no-cache 2>/dev/null )"; XFT="$( mcpq "$XG" zqText ',"kind":"zz","listing":"all","legend":"full","full_text":true' )"
    XU="$( mcpq "$XG" zqText ',"listing":"all","legend":"full"' )"
    { printf '%s' "$XF" | grep -q '<whereis [^>]* filter="zz"' && printf '%s' "$XF" | grep -q '<t_cut [^>]* uncarried="zz"/>' \
      && printf '%s' "$XF" | grep -q 'the CLI replay has no kind filter, so that next= lists the unfiltered refs and other rows; call MCP whereis with full_text:true to recover this page' \
      && [ "$( pvSame "$XF" "$XFR" )" != same ] && [ "$( pvSame "$XF" "$XFT" )" = same ] \
      && printf '%s' "$XU" | grep -q '<t_cut ' && ! printf '%s' "$XU" | grep -q 'uncarried\|the CLI replay has no kind filter'; } \
        && ok 'whereis (full text): a kind-filtered page discloses <t_cut uncarried="zz"> and the PREVIEW recovery (MCP full_text:true replays its rows whole; the CLI next= lists other rows); an unfiltered page carries neither' \
        || no "whereis (full text): kind-filtered page next='$XFN' uncarried=$( printf '%s' "$XF" | grep -c 'uncarried=' ), CLI replay: $( pvSame "$XF" "$XFR" ), full_text: $( pvSame "$XF" "$XFT" )"
    # Compact dialect: the uncarried= reading rides the page that carries the attribute, and only it.
    XC="$( mcpq "$XG" zqText ',"kind":"zz","listing":"all","legend":"compact"' )"; XCU="$( mcpq "$XG" zqText ',"listing":"all","legend":"compact"' )"
    { printf '%s' "$XC" | grep -q 't_cut uncarried=K: this page was bounded by the ref filter K (MCP kind); the CLI replay has no kind filter, so next= replays other rows; call MCP whereis with full_text:true to recover this page' \
      && printf '%s' "$XCU" | grep -q '<t_cut ' && ! printf '%s' "$XCU" | grep -q 'uncarried'; } \
        && ok 'whereis (full text): the compact uncarried= reading rides the kind-filtered page only' \
        || no 'whereis (full text): the compact uncarried= reading is missing on the filtered page or rides an unfiltered one'
else
    printf '  SKIP  whereis (full text): python3 absent — the MCP kind-filtered page (D1) is not checked\n'
fi

if command -v xmllint >/dev/null 2>&1; then
    if printf '%s' "$SW" | xmllint --noout - 2>/dev/null; then ok "capped stray-content still G4 clean"; else no "capped stray-content XML malformed"; fi
    if printf '%s' "$W1" | xmllint --noout - 2>/dev/null; then ok "paged whereis still G4 clean"; else no "paged whereis XML malformed"; fi
    if printf '%s' "$Q"  | xmllint --noout - 2>/dev/null; then ok "selector-note document still G4 clean"; else no "selector-note document is not well-formed"; fi
fi

[ $fail -eq 0 ] && echo "crossrefcheck: ALL PASS" || echo "crossrefcheck: FAILURES"
exit $fail
