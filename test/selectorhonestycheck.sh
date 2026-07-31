#!/usr/bin/env bash
# selectorhonestycheck.sh — PLAN_outputAudit2 §A6/§A7: the three places a SELECTOR or a LABEL claimed more
# than it measured.
#
# §A6a  --edit-check on an ambiguous name silently picked ONE of N definitions. `--edit-check=empty` reported
#       callers="283" for whichever def resolveFocus landed on, while --callers=empty said defs="3"
#       count="410". It is the "did I break a contract?" verb, and a contract is PER DEFINITION — unlike
#       --callers it cannot honestly union — so an agent that edited a different overload got
#       status="unchanged". FIX: refuse (exit 1), listing the qualified file:name spellings that pick one.
#
# §A6b  --uses=file:name narrowed the LABEL, not the answer. --uses=src/notes.h:empty and
#       --uses=src/scipoverlay.h:empty returned byte-identical 1211-row sets while --callers/--impact
#       genuinely narrowed; and on a NON-defining file --uses answered anyway, emitting external="1" ("no
#       definition in the indexed tree") in the same element as defs_of_name="3". FIX: (i) the qualifier
#       narrows role="call" sites to those RESOLVING to the chosen def (the --callers relation, read the
#       other way) — other roles carry no resolution and stay name-matched, disclosed by narrowed_roles= and
#       call_sites_of_name=; (ii) a non-defining file:name refuses like its three siblings; (iii) external="1"
#       requires defs=0 AND defs_of_name=0.
#
# §A7   --whereis' definitionShaped() was wrong in BOTH directions. It accepted only `{ } ) :` as def-line
#       terminators, so every noexcept-terminated definition — THE house style of this repo — read as
#       kind="ref" (--whereis=parseArgs: 0 def rows in 3385 hits), while `w.write( escapeXml(...) );`-shaped
#       call sites read as kind="def" (17 defs for a defs="1" symbol). FIX: (i) HEAD rows are labelled from
#       the parsed INDEX, one row per index def site (head_labels="index"); (ii) the blob-side heuristic
#       strips trailing specifiers and rejects a name nested in an argument list; (iii) the root's scan
#       denominator is refs_scanned=, not refs= (which --stray-content/--abi use for the MATCHED set).
#
# RED-FIRST: every arm below FAILS against the pre-fix binary and PASSES against the fixed one — EXCEPT the
# handful marked GUARD, which are the "must not change" half of each fix (the qualified form still answers,
# an unambiguous name is untouched, determinism, well-formedness) and pass on both by design.
#
#   test/selectorhonestycheck.sh
#   CTXPACK_BIN=build_base/ctxpack test/selectorhonestycheck.sh   # must FAIL (RED proof)

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative CTXPACK_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "selectorhonestycheck: BIN=$BIN  ROOT=$ROOT"

# ── the fixture repo: one clean git tree, so the whereis HEAD rows can be checked against the index ──────
R="$TMP/repo"; mkdir -p "$R"
g(){ git -C "$R" "$@"; }
g init -q
g config user.email a@b.c; g config user.name t; g config commit.gpgsign false

cat > "$R/core.h" <<'EOF'
#pragma once
void emit( int v );
EOF

# core.cpp, with the two §A7 shapes on purpose:
#   line 4  — a noexcept-terminated DEFINITION (the false-NEGATIVE class; the house style of this repo)
#   line 3  — a doc comment one line above it that NAMES the symbol (must not become a second "definition")
#   line 11 — the name nested in an argument list inside a one-line `{ ... }` body (the false-POSITIVE class)
cat > "$R/core.cpp" <<'EOF'
#include "core.h"

// parseArgs is the entry point; nothing bypasses it.
int parseArgs( int argc ) noexcept
{
    return argc;
}

void dispatch( int n )
{
    { emit( parseArgs( n ) ); }
}
EOF
g add -A; g commit -qm "core"

# a branch carrying a DOC that QUOTES the signature — the ref-blob side, where the lexical heuristic is the
# only thing there is (those blobs were never ingested) and its documented residual still applies.
g checkout -q -b feat-doc
cat > "$R/DOC.md" <<'EOF'
# Design

The entry point is

    int parseArgs( int argc ) noexcept

and callers must not bypass it.
EOF
g add -A; g commit -qm "doc quoting the entry point"
g checkout -q master 2>/dev/null || g checkout -q main

W="$TMP/w.xml"
"$BIN" "$R" --whereis=parseArgs --limit=200 >"$W" 2>/dev/null
tr '<' '\n' <"$W" | sed -n 's/^hit ref="\([^"]*\)".* p="\([^"]*\)" l="\([0-9]*\)" kind="\([a-z]*\)".*/\1 \4 \2:\3/p' >"$TMP/rows"
head_rows(){ sed -n 's/^HEAD //p' "$TMP/rows"; }

# ── §A7(i) the noexcept-terminated definition is a DEFINITION ───────────────────────────────────────────
head_rows | grep -q '^def core\.cpp:4$' \
    && ok '§A7: the noexcept-terminated def on HEAD reads kind="def" (was kind="ref" — the house style failed the shape test)' \
    || { no '§A7: core.cpp:4 (int parseArgs( int argc ) noexcept) is not a def row'; head_rows; }

# it must also lead its ref block: "definitions before references" only works if the def is labelled one.
[ "$( head_rows | sed -n 1p )" = "def core.cpp:4" ] \
    && ok '§A7: that def row RANKS first in HEAD/source (the ordering key reads the label)' \
    || { no "§A7: HEAD row 1 is '$( head_rows | sed -n 1p )', want 'def core.cpp:4'"; head_rows; }

# ── §A7(ii) the argument-list false positive is a REFERENCE ─────────────────────────────────────────────
head_rows | grep -q '^ref core\.cpp:11$' \
    && ok '§A7: a name nested in an argument list inside a one-line body reads kind="ref" (the 17-false-defs class)' \
    || { no '§A7: core.cpp:11 ({ emit( parseArgs( n ) ); }) is not a ref row'; head_rows; }

# the doc comment one line ABOVE the def must not become a second definition: exactly one row is promoted
# per index def site, so the whole HEAD def LIST is checkable, not just its first row.
[ "$( head_rows | grep '^def ' )" = "def core.cpp:4" ] \
    && ok '§A7: the HEAD def rows are EXACTLY the index def sites (the comment naming the symbol above it stays a ref)' \
    || { no "§A7: HEAD def rows are '$( head_rows | grep '^def ' | tr '\n' ' ' )', want exactly 'def core.cpp:4'"; head_rows; }

# ── §A7(i) head_labels= discloses WHICH mechanism labelled HEAD ─────────────────────────────────────────
grep -q 'head_labels="index"' "$W" \
    && ok '§A7: head_labels="index" — HEAD rows are the parsed answer, and say so' \
    || { no '§A7: head_labels="index" missing'; grep -o '<whereis[^>]*>' "$W"; }

# ── §A7(ii) the ref-blob side keeps its LEXICAL heuristic — and now reads the same shape correctly ──────
grep -q '^feat-doc def DOC\.md:' "$TMP/rows" \
    && ok '§A7: a branch DOC quoting the signature still reads kind="def" (the lexical residual is intact, and now handles noexcept)' \
    || { no '§A7: the feat-doc DOC.md row is not a def row (the blob-side heuristic still misreads the house style)'; cat "$TMP/rows"; }

# ── §A7(iii) the scan denominator names its noun ────────────────────────────────────────────────────────
{ grep -q 'refs_scanned="' "$W" && ! grep -q '<whereis[^>]* refs="' "$W"; } \
    && ok '§A7: the root reports refs_scanned= (the scan denominator), not refs= (which siblings use for the MATCHED set)' \
    || { no '§A7: whereis root still spells the scan denominator refs='; grep -o '<whereis[^>]*>' "$W"; }

# determinism + well-formedness of the changed verb
"$BIN" "$R" --whereis=parseArgs --limit=200 >"$TMP/w2.xml" 2>/dev/null
cmp -s "$W" "$TMP/w2.xml" && ok "GUARD §A7: whereis is byte-identical run-to-run" || no "§A7: whereis is non-deterministic"
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$W" 2>/dev/null && ok "GUARD §A7: whereis XML well-formed" || no "§A7: whereis XML malformed"
fi

# ── §A6a: an ambiguous --edit-check REFUSES and hands back the spellings ────────────────────────────────
# `helper` is defined in two files of the fixture — two definition SITES, two contracts.
mkdir -p "$R/one" "$R/two"
printf '#pragma once\ninline int helper( int q ) noexcept { return q; }\n'        > "$R/one/h.h"
printf '#pragma once\ninline int helper( int q, int r ) noexcept { return q + r; }\n' > "$R/two/h.h"
# …and one caller of each, so `helper` HAS use-sites: the §A6b arms below are about a selector whose SITES
# are non-empty while its defs= are not — the exact shape that made --uses answer where its siblings refuse.
# Each caller includes exactly one of the two headers, so the call graph resolves each site to ONE def and
# the narrowing has something real to narrow (a call to a name with no include path to any def resolves to
# nothing at all, which would make the arms below vacuous).
printf '#include "one/h.h"\nint useOne( int q ) { return helper( q ); }\n' > "$R/useone.cpp"
printf '#include "two/h.h"\nint useTwo( int q ) { return helper( q, q ); }\n' > "$R/usetwo.cpp"
g add -A; g commit -qm "two helpers + their callers"

EC_OUT="$( "$BIN" "$R" --edit-check=helper --no-cache 2>"$TMP/ecerr" )"; EC_RC=$?
[ "$EC_RC" -eq 1 ] \
    && ok "§A6a: an ambiguous bare name refuses (exit 1) instead of answering about one of N contracts" \
    || { no "§A6a: --edit-check=helper exited $EC_RC (want 1)"; printf '%s\n' "$EC_OUT" | head -c 400; }
grep -q 'ambiguous' "$TMP/ecerr" \
    && ok "§A6a: the refusal says the name is ambiguous" || { no "§A6a: refusal does not say 'ambiguous'"; cat "$TMP/ecerr"; }
grep -q 'edit-check' "$TMP/ecerr" \
    && ok "§A6a: the refusal names the flag" || { no "§A6a: refusal does not name --edit-check"; cat "$TMP/ecerr"; }
{ grep -q 'one/h.h:helper' "$TMP/ecerr" && grep -q 'two/h.h:helper' "$TMP/ecerr"; } \
    && ok "§A6a: the refusal LISTS both qualified file:name spellings" || { no "§A6a: refusal does not list both spellings"; cat "$TMP/ecerr"; }
grep -q -- '--edit-check=.*h\.h:helper' "$TMP/ecerr" \
    && ok "§A6a: the refusal gives one spelling as a ready-to-run example" || { no "§A6a: refusal has no runnable example"; cat "$TMP/ecerr"; }

# the qualified form still WORKS, and answers about that file's contract only.
ECQ="$( "$BIN" "$R" --edit-check=one/h.h:helper --no-cache 2>/dev/null )"; ECQ_RC=$?
{ [ "$ECQ_RC" -eq 0 ] && printf '%s' "$ECQ" | grep -q '<edit-check sym="helper"'; } \
    && ok "GUARD §A6a: the qualified file:name form proceeds (exit 0) exactly as before" \
    || { no "§A6a: --edit-check=one/h.h:helper failed (exit $ECQ_RC)"; printf '%s\n' "$ECQ" | head -c 400; }
printf '%s' "$ECQ" | grep -q 'p="[^"]*one/h.h:2"' \
    && ok "GUARD §A6a: the qualified answer is about the definition that was NAMED" \
    || { no "§A6a: qualified answer points elsewhere"; printf '%s' "$ECQ" | grep -o '<edit-check[^>]*>'; }

# an UNAMBIGUOUS bare name is untouched (this fix must not turn every symbol into a refusal).
ECU_RC=0; "$BIN" "$R" --edit-check=dispatch --no-cache >/dev/null 2>&1 || ECU_RC=$?
[ "$ECU_RC" -eq 0 ] && ok "GUARD §A6a: an unambiguous bare name still answers (exit 0)" || no "§A6a: --edit-check=dispatch exited $ECU_RC (want 0)"

# ── §A6b(ii): a file: qualifier naming a file with NO such def REFUSES, like its three siblings ─────────
U_RC=0; "$BIN" "$R" --uses=core.h:helper --no-cache >"$TMP/uout" 2>"$TMP/uerr" || U_RC=$?
[ "$U_RC" -eq 1 ] \
    && ok "§A6b: --uses on a NON-defining file:name refuses (exit 1), as --callers/--impact/--edit-check do" \
    || { no "§A6b: --uses=core.h:helper exited $U_RC (want 1)"; head -c 300 "$TMP/uout"; }
# §B4.2 PIN UPDATE (PLAN_outputAudit3_2026-07-29.md). These two arms used to run on --uses ALONE, and the
# first of them pinned the bare "symbol not found" wording as the shared house form — which is exactly the
# asymmetry the audit found: --uses had grown the honest message (the real problem + the files that DO
# define the name + a runnable retry) while --edit-check/--callers/--callees/--impact/--around/--lego said
# only "symbol not found" about a symbol that plainly exists. Pinning --uses alone meant the gate could not
# see the other five, so it certified the asymmetry instead of the promise. The message now lives in
# src/selectorrefuse.h and every arm calls it, so the loop below runs on ALL SIX and asserts the two MEANING
# halves — names-the-defining-file, gives-a-runnable-retry — never a sentence, so a later rewording that
# keeps both facts stays green and one that drops either does not.
for arm in uses callers callees impact around lego edit-check; do
    "$BIN" "$R" --$arm=core.h:helper --no-cache >/dev/null 2>"$TMP/aerr" || true
    grep -q 'not found' "$TMP/aerr" \
        && ok "§A6b/§B4.2 (--$arm): the refusal keeps the shared 'not found' prefix an agent greps for" \
        || { no "§A6b/§B4.2 (--$arm): refusal wording diverges"; cat "$TMP/aerr"; }
    { grep -q 'one/h\.h' "$TMP/aerr" && grep -q 'two/h\.h' "$TMP/aerr"; } \
        && ok "§B4.2 (--$arm): the refusal NAMES the files that DO define the name (half 1)" \
        || { no "§B4.2 (--$arm): refusal does not name the defining files"; cat "$TMP/aerr"; }
    ARETRY="$( grep -oE -- "--$arm=[^ )]+" "$TMP/aerr" | tail -1 )"
    if [ -z "$ARETRY" ]; then
        no "§B4.2 (--$arm): refusal offers no runnable retry (half 2) — $( cat "$TMP/aerr" )"
    else
        ARRC=0; "$BIN" "$R" "$ARETRY" --no-cache >/dev/null 2>&1 || ARRC=$?
        [ "$ARRC" -eq 0 ] \
            && ok "§B4.2 (--$arm): the offered retry '$ARETRY' RUNS as printed (half 2)" \
            || no "§B4.2 (--$arm): the offered retry '$ARETRY' exited $ARRC — the example is not runnable"
    fi
done

# ── §A6b(iii): external="1" is impossible while defs_of_name= is non-zero ───────────────────────────────
grep -q 'external="1"' "$TMP/uout" \
    && { no "§A6b: a non-defining qualifier still claims external=\"1\""; head -c 300 "$TMP/uout"; } \
    || ok '§A6b: no external="1" claim from a non-defining file: qualifier (it refuses instead)'
for sel in one/h.h:helper two/h.h:helper; do
    E="$( "$BIN" "$R" --uses="$sel" --no-cache 2>/dev/null | grep -o '<uses[^>]*>' )"
    case "$E" in
        *'external="1"'*) no "§A6b: --uses=$sel claims external=\"1\" beside defs_of_name= — $E" ;;
        *)                ok "§A6b: --uses=$sel makes no external= claim it cannot support" ;;
    esac
done

# ── §A6b(i): the qualifier narrows the ANSWER — two defining files, two DIFFERENT site sets ────────────
# Compare the ROWS, never the whole document: the root element always differs (of= echoes the selector), and
# comparing documents would let the pre-fix binary "pass" on a difference that is pure label.
use_rows(){ "$BIN" "$R" --uses="$1" --no-cache 2>/dev/null | tr '<' '\n' | sed -n 's/^u role=/role=/p'; }
use_rows one/h.h:helper >"$TMP/u1"
use_rows two/h.h:helper >"$TMP/u2"
{ [ -s "$TMP/u1" ] && ! cmp -s "$TMP/u1" "$TMP/u2"; } \
    && ok "§A6b: two defining files return DIFFERENT use-site ROWS (the qualifier narrows the answer, not the label)" \
    || { no "§A6b: the two defining files return identical site rows (the qualifier narrows nothing)"; cat "$TMP/u1"; }

# ── §A6b(i) on the live repo: role="call" rows agree with --callers=file:name, exactly ──────────────────
# Set-level, never a pinned line number: the DISTINCT enclosing symbols of the narrowed call rows must be
# the caller set --callers reports for the same selector. Pre-fix the rows were the name-wide union, which
# on this tree is 293 callers' worth of rows vs 1224 name-matched call sites.
if [ -e "$ROOT/.git" ]; then
    SEL="src/notes.h:empty"
    NCALLERS="$( "$BIN" "$ROOT" --callers="$SEL" --no-cache 2>/dev/null | grep -o 'count="[0-9]*"' | head -1 | tr -dc '0-9' )"
    NIN="$( "$BIN" "$ROOT" --uses="$SEL" --no-cache 2>/dev/null | tr '<' '\n' | grep 'role="call"' | grep -o 'in_id="[^"]*"' | sort -u | wc -l | tr -d ' ' )"
    if [ -n "$NCALLERS" ] && [ "$NCALLERS" -gt 0 ]; then
        [ "$NIN" = "$NCALLERS" ] \
            && ok "§A6b: --uses=$SEL role=\"call\" rows have exactly the --callers=$SEL enclosing symbols ($NIN)" \
            || no "§A6b: $NIN distinct enclosing symbols on call rows vs --callers count=$NCALLERS — the two narrowings disagree"
    else
        ok "§A6b: live-repo caller arm skipped (no callers resolved for $SEL in this checkout)"
    fi

    # and the two overloads' ROWS must not be identical (the finding's own repro: 1211 identical rows)
    live_rows(){ "$BIN" "$ROOT" --uses="$1" --no-cache 2>/dev/null | tr '<' '\n' | sed -n 's/^u role=/role=/p'; }
    live_rows src/notes.h:empty       >"$TMP/l1"
    live_rows src/scipoverlay.h:empty >"$TMP/l2"
    if [ -s "$TMP/l1" ] && [ -s "$TMP/l2" ]; then
        cmp -s "$TMP/l1" "$TMP/l2" \
            && no "§A6b: src/notes.h:empty and src/scipoverlay.h:empty still return identical use-site rows (the finding's repro)" \
            || ok "§A6b: the two overloads' use-site rows differ (the finding's repro is closed)"
    else
        ok "§A6b: live-repo overload arm skipped (symbols absent from this checkout)"
    fi
else
    ok "§A6b: live-repo arms skipped (repo root is not a git tree)"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
