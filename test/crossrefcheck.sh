#!/usr/bin/env bash
# crossrefcheck.sh — the field-notes §1 gate for --stray-content and --whereis (src/crossref.h).
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
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
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
cmp -s "$TMP/a" "$TMP/b" && ok "stray-content determinism (byte-identical)" || no "stray-content is non-deterministic"
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

"$BIN" "$R" --whereis=computeBudget >"$TMP/w2" 2>/dev/null
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

# ── 6) refusals: bare --whereis, and a non-git root ────────────────────────────────────────────────────
"$BIN" "$R" --whereis >/dev/null 2>&1;                 [ $? -eq 1 ] && ok "bare --whereis refuses loudly (exit 1)" || no "bare --whereis did not exit 1"
mkdir -p "$TMP/plain"; printf 'int main(){return 0;}\n' > "$TMP/plain/m.cpp"
"$BIN" "$TMP/plain" --stray-content >/dev/null 2>&1;   [ $? -eq 1 ] && ok "--stray-content on a non-git root refuses loudly (exit 1)" || no "--stray-content on a non-git root did not exit 1"

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
[ $? -eq 1 ] && ok "--eval-stray refuses loudly on a missing labels file" || no "--eval-stray did not exit 1 on a missing file"

# ── 9) well-formed, minified XML (G4) ─────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    "$BIN" "$R" --stray-content 2>/dev/null | xmllint --noout - 2>/dev/null && ok "stray-content XML well-formed" || no "stray-content XML malformed"
    "$BIN" "$R" --whereis=computeBudget 2>/dev/null | xmllint --noout - 2>/dev/null && ok "whereis XML well-formed" || no "whereis XML malformed"
else
    ok "xmllint unavailable — XML well-formedness skipped"
fi
[ "$( grep -c '' "$TMP/a" )" -le 1 ] && ok "output is minified (no stray newlines)" || no "output contains newlines outside CDATA"

# ── 10) §B8.2 — THE SECOND TRUNCATION VOCABULARY IS DEFINED WHERE IT IS EMITTED ───────────────────────
# Both verbs emit a `<more X="N"/>` remainder element. It is count-accurate and deliberate, and it was
# defined NOWHERE in either payload legend, while pageview.h's own doctrine calls shown=/capped=/next_offset=
# "the ONLY paging vocabulary". A reader who meets `<more hits="12"/>` has no way to learn whether it is a
# second cap they must page past or the same fact from the other end. The legend now says which.
legend_of(){ printf '%s' "$1" | grep -oE '<!--.*?-->' | head -1; }

W1="$( "$BIN" "$R" --whereis=computeBudget --limit=1 2>/dev/null )"
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
    WEND="$( "$BIN" "$R" --whereis=computeBudget --limit=1 --offset="$W_HITS" 2>/dev/null )"
    printf '%s' "$WEND" | grep -q '<more ' \
        && no "§B8.2 whereis: a past-the-end page still emits a <more> remainder" \
        || ok "§B8.2 whereis: the <more> remainder is absent on a page with nothing left"
else
    no "§B8.2 whereis: --limit=1 produced no <more hits=> to check (fixture has too few hits)"
fi

# the stray-content sibling: force the per-ref file listing (capped at 12) past its cap on its own branch.
g checkout -q main
g checkout -qb feat-wide
i=1; while [ $i -le 15 ]; do printf 'int wideOnly%02d( int v ) { return v + %d; }\n' "$i" "$i" > "$R/wide$i.cpp"; i=$(( i + 1 )); done
g add -A; g commit -qm "15 files only this branch has"
g checkout -q main
SW="$( "$BIN" "$R" --stray-content 2>/dev/null )"
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
SR="$( "$BIN" "$R" --stray-content 2>/dev/null )"
WR="$( "$BIN" "$R" --whereis=reliefFirstContourIndex 2>/dev/null )"
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
qz(){ "$BIN" "$R" --whereis="$1" 2>/dev/null; }
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
printf '%s' "$( qz "engine.cpp:computeBudget" )" | grep -oE '<!--.*?-->' | head -1 | grep -q 'SELECTOR:' \
    && ok "§B11.2 the legend defines the selector-note element it emits" \
    || no "§B11.2 selector-note is emitted and defined nowhere in the legend"

# MCP PARITY — the MCP whereis verb never calls getIndex(), so an index-based guard could only ever have
# covered the CLI. This one lives in the shared writer; assert the MCP arm really does inherit it.
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

if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$SW" | xmllint --noout - 2>/dev/null && ok "capped stray-content still G4 clean" || no "capped stray-content XML malformed"
    printf '%s' "$W1" | xmllint --noout - 2>/dev/null && ok "paged whereis still G4 clean"        || no "paged whereis XML malformed"
    printf '%s' "$Q"  | xmllint --noout - 2>/dev/null && ok "selector-note document still G4 clean" || no "selector-note document is not well-formed"
fi

[ $fail -eq 0 ] && echo "crossrefcheck: ALL PASS" || echo "crossrefcheck: FAILURES"
exit $fail
