#!/usr/bin/env bash
# usesselectorcheck.sh — §P10.2 gate: --uses accepts the "file:name" selector its eight siblings
# (--callers/--callees/--impact/--around/--edit-check/--lego/--expand/--outline) already do.
#
# THE BUG (pre-fix): --uses=src/graph.h:buildGraph refused with a FALSE message ("no definition AND no
# reference site in the indexed tree" — both exist) and a constant nonsense suggestion (`srcmut_sigchange`,
# the did-you-mean fuzzy-matching the literal "src" prefix of every "src/...:name" selector).
#
# THE FIX: defs= now resolves through the SAME shared resolver (resolveAllByNameQualified) --callers/
# --expand/--path use, so a file: qualifier narrows WHICH definitions are counted. Use-site matching stays
# reference-NAME-based (r.calleeName carries no file/scope info), so it can NOT be split per-def — sites
# stays the name-wide union, and a new defs_of_name= attribute (present only with a file: qualifier)
# discloses that un-narrowed count so the gap is visible instead of silently implied. The refusal message
# for a genuinely-unresolved selector now states only what is true (no INDEXED DEFINITION matched — never
# "no reference site", which the sites scan never actually checked per-file) and the did-you-mean now
# suggests against the NAME half only.
#
# Run against this repo's own source tree (self-hosting) — the concrete symbols below (buildGraph,
# NoteIndex::empty / ScipOverlay::empty as the overloaded-name pair) are real ripwire symbols, not a fixture.
#
#   test/usesselectorcheck.sh                      # uses build/ripwire on the repo root
#   RIPWIRE_BIN=build_base/ripwire test/usesselectorcheck.sh   # must FAIL — the pre-fix binary (RED proof)

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "usesselectorcheck: BIN=$BIN  ROOT=$ROOT"

uses_elem(){ "$BIN" "$ROOT" --uses="$1" --no-cache 2>/dev/null | grep -o '<uses[^>]*>'; }
attr(){ printf '%s' "$1" | grep -o "$2=\"[0-9]*\"" | grep -o '[0-9]*'; }

# ── (a) --uses=src/graph.h:buildGraph must resolve (not refuse), narrow defs= AND the call-role sites ───
#
# §A6b UPDATE (2026-07-28): this arm used to assert count= EQUALS the bare-name count ("sites stay
# name-wide"). That was the bug, not the contract: the qualifier narrowed the LABEL and not the answer, so
# two different files' selectors returned byte-identical site sets. A call site's resolved target is
# recorded in the call graph, so the call role narrows exactly as --callers does; the roles that carry no
# resolution (read/write/import/extends) still stay name-matched, and call_sites_of_name= discloses the
# un-narrowed call total. So the assertion inverts: qualified count= must be <= the bare count.
Q_QUAL="$( uses_elem 'src/graph.h:buildGraph' )"
Q_QUAL_RC=$?
Q_BARE="$( uses_elem 'buildGraph' )"
[ -n "$Q_QUAL" ] && ok "--uses=src/graph.h:buildGraph resolves (was a false refusal pre-fix): $Q_QUAL" \
    || no "--uses=src/graph.h:buildGraph still refuses (bug not fixed)"
if [ -n "$Q_QUAL" ] && [ -n "$Q_BARE" ]; then
    CQ="$( attr "$Q_QUAL" count )"; CB="$( attr "$Q_BARE" count )"
    { [ -n "$CQ" ] && [ -n "$CB" ] && [ "$CQ" -le "$CB" ]; } \
        && ok "count= is the narrowed site set, never larger than the bare-name union: $CQ <= $CB" \
        || no "count= grew under a file: qualifier: qualified=$CQ bare=$CB"
    printf '%s' "$Q_QUAL" | grep -q 'narrowed_roles="call"' \
        && ok 'narrowed_roles="call" discloses which roles the qualifier narrowed' \
        || no "narrowed_roles= missing from a file:name selector: $Q_QUAL"
    CSN="$( attr "$Q_QUAL" call_sites_of_name )"
    [ -n "$CSN" ] && ok "call_sites_of_name= discloses the un-narrowed call total: $CSN" \
        || no "call_sites_of_name= missing from a file:name selector: $Q_QUAL"
    DQ="$( attr "$Q_QUAL" defs )"; DB="$( attr "$Q_BARE" defs )"
    [ -n "$DQ" ] && [ -n "$DB" ] && [ "$DQ" -le "$DB" ] && ok "defs= narrowed by the file qualifier: $DQ (unqualified: $DB)" \
        || no "defs= not narrowed: qualified=$DQ bare=$DB"
fi

# ── (b) an OVERLOADED name (NoteIndex::empty vs ScipOverlay::empty) — defs narrows to 1, sites stay ─────
#    the name-wide union, and the defs_of_name= disclosure attribute is present.
E_QUAL="$( uses_elem 'src/notes.h:empty' )"
E_BARE="$( uses_elem 'empty' )"
if [ -n "$E_QUAL" ] && [ -n "$E_BARE" ]; then
    EDQ="$( attr "$E_QUAL" defs )"
    [ "$EDQ" = "1" ] && ok "src/notes.h:empty narrows defs= to exactly 1 (the overload in that file)" \
        || no "src/notes.h:empty defs=$EDQ (expected exactly 1)"
    ECQ="$( attr "$E_QUAL" count )"; ECB="$( attr "$E_BARE" count )"
    { [ -n "$ECQ" ] && [ "$ECQ" -lt "$ECB" ]; } \
        && ok "src/notes.h:empty count= is a NARROWED site set, smaller than the name-wide union ($ECQ < $ECB)" \
        || no "src/notes.h:empty count=$ECQ vs unqualified empty count=$ECB — the qualifier must narrow the call sites (§A6b)"
    EDN="$( attr "$E_QUAL" defs_of_name )"
    [ -n "$EDN" ] && [ "$EDN" -gt "$EDQ" ] && ok "defs_of_name= disclosure present and larger than the narrowed defs= ($EDN > $EDQ)" \
        || no "defs_of_name= missing or not > defs= (got '${EDN:-<absent>}' vs defs=$EDQ) — overloaded-name disclosure broken"
else
    no "could not read --uses=src/notes.h:empty or --uses=empty output"
fi
# the unqualified form must NOT carry defs_of_name= (only a file: qualifier discloses it)
printf '%s' "$E_BARE" | grep -q 'defs_of_name=' && no "unqualified --uses=empty wrongly carries defs_of_name=" \
    || ok "unqualified --uses=empty carries no defs_of_name= (disclosure is qualifier-only)"

# ── (c) a genuinely-unknown file:name selector refuses honestly — no false 'no reference site' claim, ───
#    and the suggestion is a real name, not the constant srcmut_sigchange bug.
OUT="$( "$BIN" "$ROOT" --uses='src/graph.h:nosuchfn' --no-cache 2>"$TMP/err" )"; RC=$?
[ "$RC" -eq 1 ] && ok "--uses=src/graph.h:nosuchfn refuses (exit 1)" || no "--uses=src/graph.h:nosuchfn exit $RC (expected 1)"
grep -qi 'no reference site' "$TMP/err" && no "refusal still falsely claims 'no reference site': $( cat "$TMP/err" )" \
    || ok "refusal does not claim 'no reference site' (states only what defs.empty() proves)"
grep -q 'srcmut_sigchange' "$TMP/err" && no "the constant nonsense suggestion (srcmut_sigchange) is back: $( cat "$TMP/err" )" \
    || ok "suggestion is not the constant srcmut_sigchange bug"
# §P12.1: didYouMean() now does true bounded edit distance and honestly omits a suggestion when nothing in
# the corpus is within a few edits, instead of the old shared-prefix*4-lenDelta score that always forced
# SOME guess (pre-fix this fixture got "did you mean 'norm_rel'?" — an unrelated name, exactly the
# fabricated-confidence class the plan's §P0.5/§P5 findings call out). "nosuchfn" is not a plausible
# near-miss of anything in this corpus, so a suggestion is no longer guaranteed here — the load-bearing
# assertion is the line above (never the constant srcmut_sigchange bug). A positive "does suggest a real
# near-miss" case for the file:name selector lives in didyoumeancheck.sh's §P12.1 section
# (src/graph.h:buildGrap -> buildGraph).

# ── (d) plain name and canonical-id forms stay byte-identical to pre-fix (only file:name changed) ───────
#    NoteIndex::empty's canonical id ("path::scope::name") — a scoped method, so it actually carries "::"
#    (a scope-less free function's canonical id degrades to its bare name and can't test this branch).
#    The id is looked up live via --expand (it embeds the corpus path exactly as invoked — "." vs an
#    absolute ROOT produce different id= strings — so it must never be hardcoded).
CANON_ID="$( "$BIN" "$ROOT" --expand='src/notes.h:empty' --no-cache 2>/dev/null | grep -o 'id="[^"]*NoteIndex::empty"' | head -1 | sed 's/^id="//;s/"$//' )"
[ -n "$CANON_ID" ] || { no "could not look up NoteIndex::empty's canonical id via --expand"; CANON_ID="./src/notes.h::NoteIndex::empty"; }
BARE_A="$( uses_elem 'buildGraph' )"
BARE_B="$( uses_elem 'buildGraph' )"
[ "$BARE_A" = "$BARE_B" ] && ok "bare-name form is stable/reproducible: $BARE_A" || no "bare-name form not reproducible"
CANON_A="$( uses_elem "$CANON_ID" )"
[ -n "$CANON_A" ] && ok "canonical-id form still resolves: $CANON_A" || no "canonical-id form stopped resolving: $CANON_ID"
# canonical id was never a use-site match key (r.calleeName is never a full canonical id) — that stays true,
# so count="0" here is the documented, unchanged behaviour, not a regression from this fix.
[ -n "$CANON_A" ] && { [ "$( attr "$CANON_A" count )" = "0" ] && ok "canonical-id site-matching unchanged (count=0, as before this fix)" \
    || no "canonical-id count changed (was always 0 pre-fix): $( attr "$CANON_A" count )"; }

# ── (e) determinism — the new file:name path is deterministic run-to-run ─────────────────────────────────
"$BIN" "$ROOT" --uses='src/graph.h:buildGraph' --no-cache >"$TMP/d1" 2>/dev/null
"$BIN" "$ROOT" --uses='src/graph.h:buildGraph' --no-cache >"$TMP/d2" 2>/dev/null
diff -q "$TMP/d1" "$TMP/d2" >/dev/null && ok "determinism (file:name selector, byte-identical run-to-run)" \
    || no "file:name selector is non-deterministic"

# ── xml well-formed ────────────────────────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    "$BIN" "$ROOT" --uses='src/graph.h:buildGraph' --no-cache 2>/dev/null | xmllint --noout - \
        && ok "--uses=file:name xml well-formed" || no "--uses=file:name xml malformed"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
