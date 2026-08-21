#!/usr/bin/env bash
# qualitypanelcheck.sh — the contract of `--quality-panel[=PRESET]`, THE SINGLE COMMAND.
#
# WHAT THIS GATE EXISTS FOR. The panel joins SIX evidence families and ranks by the COUNT of distinct families
# a preset counts. Four properties can each be wrong while the output still looks entirely plausible, which is
# non-negotiable #1 in this repo: a ranking, a family count and a preset all read fine whether or not they are
# correct. So each is pinned against a fixture whose family set is derivable WITH A PENCIL, never read back
# out of a run.
#
#   1. THE COUNT AND THE NAMES. families= is 6 and every preset's enabled= is an exact string. A panel that
#      silently drops or renames a family still emits a well-formed, plausible report.
#   2. THE ORDERING. Rows come out most-corroborated first and by nothing else. A composite score, a secondary
#      tiebreak or a reversed comparator all produce a ranked-looking listing.
#   3. THE PRESET ARITHMETIC. A preset is a SELECTION (which families count) and a CUT (how many must agree),
#      never a weight. The three are nested by construction — removing a family from the count can only lower
#      a symbol's count — so strict ⊆ default ⊆ lenient must hold on every corpus, and BOTH `historical` and
#      `colocation` must be absent from `strict`: the commit-ladder pass (docs/EVALS.md §9.5, §9.9) measured
#      each of them below the stability cut, because each is a fixed-size worst-40 cut over a ranking whose
#      population moves. That exclusion is a measurement, and a gate that does not pin it will lose it.
#   4. UNAVAILABLE IS NOT FIRING. A family that could not be evaluated here is named, given a reason, and
#      removed from of= — never reported as a family that was measured and stayed quiet.
#
# THE FIXTURES, and why the set needs all three:
#
#   PANELC  a three-file C++ tree in a git repository, built so that ONE function fires ALL SIX families and
#           two others fire exactly two and exactly one. Every family's firing condition is hand-derived:
#             structural  6 parameters, and the parameter bar is 5
#             lexical     tally/Every/Configured/Adjustment/Value/For/Row = 7 split tokens -> naming-wordy
#             confusion   ( b ? c : ( d ? e : f ) ) -> atom-nested-ternary
#             historical  hub.cpp is the ONLY file with more than one commit, and the churn cut over three
#                         ranked files is ceil(3/10) = 1 rank, so hub.cpp's functions and no others
#             colocation  the ONLY function that resolves anything outside its own file, so the local-reasoning
#                         ranking has exactly one entry (cranked=1), its cut is 1, and it is rank 0
#             state       it writes g_counter, a file-scope mutable global, in its OWN body
#           The `2 families` and `1 family` functions live in an UNCHURNED file so the historical family
#           cannot reach them, which is what makes the cut arm exact rather than approximate.
#   RUSTONE a single-file pure-Rust tree with NO repository above it. FOUR families unavailable at once, each
#           for its own reason: confusion (the atom rules are C-family only), historical (no git), state (the
#           non-local-state lens analyses C++/ObjC/ObjC++ only) and colocation (a single file resolves nothing
#           outside itself, so its ranking is EMPTY). One reason slot cannot express four missing measurements.
#   NOFNS   a JSON-only tree: nothing with a body is indexed, so NO family measured anything and the preset's
#           cut cannot be reached at all. cut_reachable=0 is the honest way to say "this preset can emit
#           nothing here no matter what the code looks like"; an empty listing alone would read as a pass.
#
# Arms:
#   (A) the family count and the three presets' exact enabled=/cut= — the SELECTION, pinned
#   (B) historical and colocation are NOT in strict, and ARE in default and lenient (the stability findings)
#   (C) the six-family function is the TOP row of `default`, with the exact family name list
#   (D) the ORDERING: fam= is non-increasing down the whole listing, on every preset
#   (E) the CUT: lenient emits the 1-family function, default and strict do not; below_cut= accounts for it
#   (F) the denominator identity ranked + below_cut + no_family = eligible, on every preset
#   (G) the LADDER: strict ⊆ default ⊆ lenient, by emitted symbol
#   (H) a family that fired but is not counted is DISCLOSED (uncounted= and counted="0"), not dropped
#   (I) UNAVAILABLE: four families at once, four reasons, of= drops, and every ROW carries the verdict
#   (J) cut_reachable=0 when nothing was measurable, with eligible=0 and an empty listing
#   (K) a bad preset name is REFUSED, not silently replaced
#   (L) determinism + XML well-formedness on every fixture and preset
#   (M) ADDITIVITY: the flagless map is byte-identical with the flag absent
#   (N) the historical family's UNIT is the FILE, measured and then DISCLOSED in the legend
#
# WHY (N) EXISTS. The other five families are per-symbol claims: the bars, the naming rules, the atom rules,
# the outside-reading rank and the state cells are all computed from ONE symbol. `historical` is not — churn
# is mined per PATH, so every symbol in a file carries that file's churn=/hrank= verbatim, and a symbol in a
# churny file collects the family for free without any property of its own. Measured on this repository at
# the time this arm was written: 20 of the 40 default-preset rows were src/main.cpp symbols, every one of
# them reporting the identical `hrank=0 churn=47`. That is not a bug — it is the family's real unit, and the
# panel is explicitly ranked by families that must be able to DISAGREE. What was wrong was the legend, which
# said only "git change frequency" and left a reader to assume the row's own history had been measured.
# Non-negotiable #3 (honesty in output is a feature) makes that a defect in the report, not a caveat for the
# docs. So this arm asserts BOTH halves and in that order: the measurement first (rows in one file really do
# share one historical evidence string), the disclosure second (the legend says so where the reader meets
# the family). A gate that pinned only the sentence would keep passing if the family's unit ever changed.
#
#   (O) the deep x untested JOIN: an annotation, and never a seventh family
#
# WHY (O) EXISTS, and what the join is allowed to be. `deep=` (lines inside the regions that reach bar_nest)
# and "no indexed test reaches this symbol" are two facts this report already holds. Their INTERSECTION is
# where a refactor is both most needed and least safe, and a reader should not need a second verb to find it.
# But it is emphatically NOT independent evidence: it restates two things already on the row, so counting it
# as a family would be the Maintainability-Index failure this verb exists to refuse — one signal re-weighted
# and called two. The join is therefore an ANNOTATION, and this arm pins it to that role in four parts:
#   (O1) it FIRES on a deep function no test reaches
#   (O2) it does NOT fire on a deep function a test does reach — the same body, only the coverage differs
#   (O3) the two rows are otherwise IDENTICAL (same fam=, of=, fired=, and the same evidence strings) and
#        they appear in NodeId (definition) order with the annotated one SECOND. That is the "no ranking
#        change" claim in a form a gate can see: had the join been folded into the count or into a secondary
#        ordering, the two rows would differ by more than the one attribute, or would have swapped.
#   (O4) tested_scope=0 SUPPRESSES it. PANELC has no test path at all, so there "untested" is a fact about
#        what was indexed and not about the code; the annotation must then be absent from every row rather
#        than fire on all of them. Same doctrine as UNAVAILABLE above — an empty measurement is not a finding.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "qualitypanelcheck: SKIP — git not on PATH, the historical family needs a repository"; exit 0; }
echo "qualitypanelcheck: BIN=$BIN"

# ── PANELC ────────────────────────────────────────────────────────────────────────────────────────────────
PANELC="$TMP/panelc"; mkdir -p "$PANELC"

# The colocation TARGETS: four fat definitions in their own file, so the one function that calls them has a
# non-zero outside-reading weight and every other eligible function has zero.
cat >"$PANELC/wide.h" <<'HDR'
#pragma once

inline int widenFirst( int v )
{
    int total = 0;
    for( int i = 0; i < 8; ++i )
    {
        total += v + i;
    }
    return total;
}

inline int widenSecond( int v )
{
    int total = 1;
    for( int i = 0; i < 8; ++i )
    {
        total *= ( v + i ) % 7 + 1;
    }
    return total;
}

inline int widenThird( int v )
{
    int total = 0;
    for( int i = 0; i < 8; ++i )
    {
        total -= v - i;
    }
    return total;
}

inline int widenFourth( int v )
{
    int total = 3;
    for( int i = 0; i < 8; ++i )
    {
        total ^= v + i;
    }
    return total;
}
HDR

# The SIX-family function, plus a control in the same (churned) file. The control fires `historical` because
# it shares the file — that is the family's own unit and the gate asserts the six-family row, not the control.
cat >"$PANELC/hub.cpp" <<'SRC'
#include "wide.h"

int g_counter = 0;

int tallyEveryConfiguredAdjustmentValueForRow( int alpha, int beta, int gamma, int delta, int epsilon, int zeta )
{
    g_counter = g_counter + alpha;
    int picked = ( beta ? gamma : ( delta ? epsilon : zeta ) );
    return picked + widenFirst( alpha ) + widenSecond( beta ) + widenThird( gamma ) + widenFourth( delta );
}

int plainSum( int a, int b )
{
    return a + b;
}
SRC

# The CUT fixtures, in a file that is committed ONCE so the historical family cannot reach them.
#   twoFamilyRestingConfiguredAdjustmentValue  lexical (7 tokens) + confusion (nested ternary) = exactly 2
#   oneFamilyRestingConfiguredAdjustmentValue  lexical only                                    = exactly 1
cat >"$PANELC/plain.cpp" <<'SRC'
int twoFamilyRestingConfiguredAdjustmentValue( int a, int b, int c )
{
    return ( a ? b : ( c ? a : b ) );
}

int oneFamilyRestingConfiguredAdjustmentValue( int a, int b )
{
    return a + b;
}
SRC

g="git -C $PANELC -c user.email=gate@example.invalid -c user.name=gate -c commit.gpgsign=false"
$g init -q . >/dev/null 2>&1
$g add -A >/dev/null 2>&1
$g commit -q -m init >/dev/null 2>&1
printf '\n// bump 1\n' >>"$PANELC/hub.cpp"; $g commit -q -am bump1 >/dev/null 2>&1
printf '// bump 2\n'   >>"$PANELC/hub.cpp"; $g commit -q -am bump2 >/dev/null 2>&1
if [ "$( $g rev-list --count HEAD 2>/dev/null )" != "3" ]; then
    echo "qualitypanelcheck: SKIP — could not build a 3-commit git fixture in this environment"
    exit 0
fi

# ── RUSTONE + NOFNS ───────────────────────────────────────────────────────────────────────────────────────
RUSTONE="$TMP/rustone"; mkdir -p "$RUSTONE"
cat >"$RUSTONE/lib.rs" <<'RS'
pub fn compute_the_final_aggregated_result_value_for_each_row( a: i32, b: i32, c: i32, d: i32, e: i32, f: i32 ) -> i32
{
    let picked = if a != 0 { b } else if c != 0 { d } else { e };
    picked + f
}

pub fn scale_by_two( a: i32 ) -> i32
{
    a * 2
}
RS

NOFNS="$TMP/nofns"; mkdir -p "$NOFNS"
printf '{ "alpha": 1, "beta": { "gamma": 2 } }\n' >"$NOFNS/one.json"
printf '{ "delta": 3 }\n'                          >"$NOFNS/two.json"

# ── DEEPJ — the join fixture for arm (O) ──────────────────────────────────────────────────────────────────
# TWO functions with BYTE-IDENTICAL bodies, so every family sees exactly the same code twice: same ccx, same
# loc, same nest, same humps/deep, same parameter count, same three-token name shape. One of them is called
# from a test path and the other is called by nothing. The rows they produce must therefore be identical in
# every respect EXCEPT the join annotation — which is the whole claim: the join reports a pair of facts the
# report already contains and adds no evidence, no family and no ordering.
DEEPJ="$TMP/deepj"; mkdir -p "$DEEPJ/src" "$DEEPJ/test"
cat >"$DEEPJ/src/deep.cpp" <<'SRC'
int deepTestedRoutine( int a, int b )
{
    int total = 0;
    for( int i = 0; i < a; ++i )
    {
        if( b > i )
        {
            while( total < b )
            {
                if( ( total % 2 ) == 0 )
                {
                    total += 1;
                }
                else
                {
                    total += 2;
                }
            }
        }
    }
    return total;
}

int deepUntestedRoutine( int a, int b )
{
    int total = 0;
    for( int i = 0; i < a; ++i )
    {
        if( b > i )
        {
            while( total < b )
            {
                if( ( total % 2 ) == 0 )
                {
                    total += 1;
                }
                else
                {
                    total += 2;
                }
            }
        }
    }
    return total;
}
SRC
cat >"$DEEPJ/test/deep_test.cpp" <<'SRC'
int deepTestedRoutine( int a, int b );

int runDeepCase( void )
{
    return deepTestedRoutine( 3, 4 );
}
SRC

panel(){ "$BIN" "$1" --quality-panel="$2" --limit=500 --no-cache 2>/dev/null; }
rootElem(){ grep -o '<quality_panel [^>]*>' "$1" | head -1; }
rootAttr(){ rootElem "$1" | grep -o " $2=\"[^\"]*\"" | head -1 | sed "s/^ $2=\"//; s/\"$//"; }
famSeq(){ grep -o '<s [^>]*>' "$1" | grep -o 'fam="[0-9]*"' | sed 's/[^0-9]//g'; }
symKeys(){ grep -o '<s [^>]*>' "$1" | sed 's/.* n="\([^"]*\)".*/\1/' | sort; }

for p in strict default lenient; do
    panel "$PANELC"  "$p" >"$TMP/panelc.$p"
    panel "$RUSTONE" "$p" >"$TMP/rustone.$p"
    panel "$NOFNS"   "$p" >"$TMP/nofns.$p"
done
for f in panelc.default rustone.default nofns.default; do
    if [ ! -s "$TMP/$f" ] || ! grep -q '<quality_panel ' "$TMP/$f"; then
        no "(setup) --quality-panel produced no report on $f — the rest of this gate would assert nothing"
        head -c 400 "$TMP/$f"; printf '\n'
    fi
done
[ "$fail" -eq 0 ] || { echo "qualitypanelcheck: FAIL"; exit 1; }

# ── (A) the family COUNT and the three presets' exact SELECTION ────────────────────────────────────────────
ALL="structural,lexical,confusion,historical,colocation,state"
STABLE="structural,lexical,confusion,state"
checkPreset(){  # checkPreset <preset> <expected enabled> <expected enabled_n> <expected cut>
    local p="$1" wantE="$2" wantN="$3" wantK="$4" f="$TMP/panelc.$1"
    local gotP gotE gotN gotK gotF
    gotP="$( rootAttr "$f" preset )"; gotE="$( rootAttr "$f" enabled )"
    gotN="$( rootAttr "$f" enabled_n )"; gotK="$( rootAttr "$f" cut )"
    gotF="$( rootAttr "$f" families )"
    if [ "$gotP" = "$p" ] && [ "$gotE" = "$wantE" ] && [ "$gotN" = "$wantN" ] && [ "$gotK" = "$wantK" ] && [ "$gotF" = "6" ]; then
        ok "(A) $p selects exactly [$wantE] with cut=$wantK out of families=6"
    else
        no "(A) $p must report preset=\"$p\" families=\"6\" enabled=\"$wantE\" enabled_n=\"$wantN\" cut=\"$wantK\"; got preset=\"$gotP\" families=\"$gotF\" enabled=\"$gotE\" enabled_n=\"$gotN\" cut=\"$gotK\""
    fi
}
checkPreset lenient "$ALL"    6 1
checkPreset default "$ALL"    6 2
checkPreset strict  "$STABLE" 4 2

# ── (B) historical is out of the GATING preset, and in the reporting ones ─────────────────────────────────
strictEnabled="$( rootAttr "$TMP/panelc.strict" enabled )"
case ",$strictEnabled," in
    *,historical,*) no "(B) strict COUNTS historical. docs/EVALS.md §9.5 measured its flagged set at endpoint Jaccard 0.426–0.546 across commit ladders — on gameA 40% of the symbols it flagged in June were unflagged in July on code that had not changed. A preset described as gate-shaped must not depend on it." ;;
    *)              ok "(B) strict excludes historical" ;;
esac
case ",$strictEnabled," in
    *,colocation,*) no "(B) strict COUNTS colocation. §9.9's ladder measured it at 0.732 mean consecutive / 0.222 endpoint Jaccard on the ctxpack ladder — WORSE than historical, and for the same mechanical reason: a fixed-size worst-40 cut over a ranking whose population moves. Assuming a new family inherited the others' stability instead of measuring it is exactly the error that finding exists to prevent." ;;
    *)              ok "(B) strict excludes colocation — the second exclusion, and it was found by running the ladder rather than assuming" ;;
esac
for p in default lenient; do
    en="$( rootAttr "$TMP/panelc.$p" enabled )"
    for fam in historical colocation; do
        case ",$en," in
            *,"$fam",*) ok "(B) $p keeps $fam — a moving window is a feature in a reporting preset" ;;
            *)          no "(B) $p dropped $fam; only the gating preset excludes it, or the family is unreachable everywhere" ;;
        esac
    done
done

# ── (C) the SIX-family function is the top row of `default`, by exact name list ────────────────────────────
top="$( grep -o '<s [^>]*>' "$TMP/panelc.default" | head -1 )"
case "$top" in
    *'n="tallyEveryConfiguredAdjustmentValueForRow"'*'fam="6"'*'fired="'"$ALL"'"'*)
        ok "(C) the hand-built six-family function is the TOP row with fired=\"$ALL\"" ;;
    *)  no "(C) the top row of the default preset must be tallyEveryConfiguredAdjustmentValueForRow with fam=\"6\" and fired=\"$ALL\"; got: $top" ;;
esac
# The evidence must ACCOUNT for the count — a row may not claim a family with no <e> child behind it.
sixRow="$( tr '<' '\n' <"$TMP/panelc.default" | sed -n '/^s .*tallyEveryConfigured/,/^\/s/p' )"
for fam in structural lexical confusion historical colocation state; do
    if printf '%s' "$sixRow" | grep -q "^e f=\"$fam\" counted=\"1\" why=\"[^\"]"; then
        ok "(C) the six-family row carries non-empty evidence for $fam"
    else
        no "(C) the six-family row claims $fam with no evidence behind it — fam= must never exceed what the <e> children account for"
    fi
done
if printf '%s' "$sixRow" | grep -q 'e f="colocation" counted="1" why="crank=0"'; then
    ok "(C) colocation evidence is crank=0 — the only function resolving anything outside its own file"
else
    no "(C) the six-family row must carry colocation evidence crank=0 (cranked=1 on this fixture, so its cut is one rank)"
fi
cranked="$( rootAttr "$TMP/panelc.default" cranked )"
if [ "$cranked" = "1" ]; then
    ok "(C) cranked=\"1\" — the colocation denominator is exactly the one function with outside reading"
else
    no "(C) cranked= should be 1 on this fixture (one function resolves outside its own file); got \"$cranked\""
fi

# ── (D) the ORDERING is by family count and nothing else ──────────────────────────────────────────────────
for p in strict default lenient; do
    if famSeq "$TMP/panelc.$p" | awk 'NR>1 && $1>prev { bad=1 } { prev=$1 } END { exit bad?1:0 }'; then
        ok "(D) $p emits rows in non-increasing fam= order"
    else
        no "(D) $p emitted a row with a HIGHER family count after a lower one — the listing is not ranked by corroboration"
        famSeq "$TMP/panelc.$p" | tr '\n' ' ' | sed 's/^/        /'; printf '\n'
    fi
done

# ── (E) the CUT admits and excludes exactly what the arithmetic says ──────────────────────────────────────
one=oneFamilyRestingConfiguredAdjustmentValue
two=twoFamilyRestingConfiguredAdjustmentValue
if grep -q "n=\"$one\"" "$TMP/panelc.lenient"; then
    ok "(E) the 1-family function appears under lenient (cut 1)"
else
    no "(E) lenient (cut 1) must emit the 1-family function $one"
fi
for p in default strict; do
    if grep -q "n=\"$one\"" "$TMP/panelc.$p"; then
        no "(E) $p (cut 2) emitted the 1-family function $one — the cut is not being applied"
    else
        ok "(E) $p (cut 2) excludes the 1-family function"
    fi
    if grep -q "n=\"$two\"" "$TMP/panelc.$p"; then
        ok "(E) $p (cut 2) keeps the 2-family function"
    else
        no "(E) $p (cut 2) dropped the 2-family function $two — the cut is one too tight"
    fi
done
if [ "$( rootAttr "$TMP/panelc.lenient" below_cut )" = "0" ]; then
    ok "(E) lenient reports below_cut=\"0\" — nothing can be below a cut of 1"
else
    no "(E) lenient must report below_cut=\"0\"; got \"$( rootAttr "$TMP/panelc.lenient" below_cut )\""
fi

# ── (F) the denominator identity, on every preset and every fixture ───────────────────────────────────────
for fx in panelc rustone nofns; do
    for p in strict default lenient; do
        f="$TMP/$fx.$p"
        e="$( rootAttr "$f" eligible )"; r="$( rootAttr "$f" ranked )"
        b="$( rootAttr "$f" below_cut )"; n="$( rootAttr "$f" no_family )"
        if [ "$(( r + b + n ))" = "$e" ]; then
            ok "(F) $fx/$p: ranked($r) + below_cut($b) + no_family($n) = eligible($e)"
        else
            no "(F) $fx/$p: ranked($r) + below_cut($b) + no_family($n) != eligible($e) — a symbol is being double counted or lost"
        fi
    done
done

# ── (G) the LADDER: strict ⊆ default ⊆ lenient ────────────────────────────────────────────────────────────
symKeys "$TMP/panelc.strict"  >"$TMP/k.strict"
symKeys "$TMP/panelc.default" >"$TMP/k.default"
symKeys "$TMP/panelc.lenient" >"$TMP/k.lenient"
subset(){ [ -z "$( comm -23 "$1" "$2" )" ]; }
if subset "$TMP/k.strict" "$TMP/k.default"; then
    ok "(G) strict ⊆ default"
else
    no "(G) strict emitted a symbol default does not — removing a family from the count can only LOWER a symbol's count, so the presets must nest"
    comm -23 "$TMP/k.strict" "$TMP/k.default" | sed 's/^/        /'
fi
if subset "$TMP/k.default" "$TMP/k.lenient"; then
    ok "(G) default ⊆ lenient"
else
    no "(G) default emitted a symbol lenient does not — the presets must nest"
    comm -23 "$TMP/k.default" "$TMP/k.lenient" | sed 's/^/        /'
fi

# ── (H) a family that fired but is not counted is DISCLOSED, never dropped ────────────────────────────────
strictTop="$( grep -o '<s [^>]*>' "$TMP/panelc.strict" | grep 'tallyEveryConfigured' | head -1 )"
case "$strictTop" in
    *'fam="4"'*'uncounted="historical,colocation"'*)
        ok "(H) under strict the six-family row reads fam=\"4\" with uncounted=\"historical,colocation\" — the dropped families are named, not hidden" ;;
    *)  no "(H) under strict the six-family row must read fam=\"4\" and uncounted=\"historical,colocation\"; got: $strictTop" ;;
esac
strictRow="$( tr '<' '\n' <"$TMP/panelc.strict" | sed -n '/^s .*tallyEveryConfigured/,/^\/s/p' )"
for fam in historical colocation; do
    if printf '%s' "$strictRow" | grep -q "e f=\"$fam\" counted=\"0\""; then
        ok "(H) the $fam evidence is still shown with counted=\"0\", so the preset's effect is visible in the row"
    else
        no "(H) strict dropped the $fam <e> child entirely — the reader cannot see what the preset excluded"
    fi
done

# ── (I) UNAVAILABLE: four families at once, four reasons, of= drops, every row carries it ─────────────────
un="$( rootAttr "$TMP/rustone.default" unavailable )"
why="$( rootAttr "$TMP/rustone.default" unavailable_why )"
for fam in confusion historical colocation state; do
    case ",$un," in
        *,"$fam",*) ok "(I) single-file non-git Rust reports $fam UNAVAILABLE" ;;
        *)          no "(I) $fam must be UNAVAILABLE on a single-file non-git Rust corpus — it could not be evaluated on one row of this report, and reporting that as a silent non-firing makes a clean bill of health out of a measurement that never happened. unavailable=\"$un\"" ;;
    esac
    case "$why" in
        *"$fam: "*) ok "(I) unavailable_why= carries a reason for $fam" ;;
        *)          no "(I) unavailable_why= has no reason for $fam — one reason slot cannot express four missing measurements. unavailable_why=\"$why\"" ;;
    esac
done
for fam in structural lexical; do
    case ",$un," in
        *,"$fam",*) no "(I) $fam must stay AVAILABLE on Rust — an over-broad coverage rule that takes it out with the others is a new lie in the same place" ;;
        *)          ok "(I) $fam stays available on Rust" ;;
    esac
done
rows="$( grep -o '<s ' "$TMP/rustone.default" | wc -l | tr -d ' ' )"
badOf="$( grep -o '<s [^>]*>' "$TMP/rustone.default" | grep -cv 'of="2"' )"
if [ "$rows" -ge 1 ] && [ "$badOf" -eq 0 ]; then
    ok "(I) all $rows Rust row(s) report of=\"2\" — six families minus the four that could not be evaluated"
else
    no "(I) every Rust row must report of=\"2\" ($badOf of $rows do not); a row that counts an unevaluable family in its denominator claims it was considered"
    grep -o '<s [^>]*>' "$TMP/rustone.default" | head -3 | sed 's/^/        /'
fi
strictOf="$( grep -o '<s [^>]*>' "$TMP/rustone.strict" | grep -cv 'of="2"' )"
if [ "$strictOf" -eq 0 ]; then
    ok "(I) strict on Rust also reports of=\"2\" — enabled_n=4 minus the two enabled families that were unavailable"
else
    no "(I) strict on Rust must report of=\"2\" (4 enabled minus confusion/state); $strictOf row(s) disagree"
fi
if [ "$( rootAttr "$TMP/panelc.default" unavailable )" = "" ]; then
    ok "(I) the C++ fixture reports an EMPTY unavailable= — the verdict tracks the corpus, it is not a constant"
else
    no "(I) the C++ fixture reports unavailable=\"$( rootAttr "$TMP/panelc.default" unavailable )\"; a rule that marks families unavailable everywhere is not a measurement"
fi

# ── (J) cut_reachable=0 when nothing could be measured ────────────────────────────────────────────────────
if [ "$( rootAttr "$TMP/nofns.default" eligible )" = "0" ] && [ "$( rootAttr "$TMP/nofns.default" cut_reachable )" = "0" ]; then
    ok "(J) a corpus with no function bodies reports eligible=\"0\" cut_reachable=\"0\" — the preset can emit nothing here whatever the code looks like"
else
    no "(J) the JSON-only corpus must report eligible=\"0\" and cut_reachable=\"0\"; got eligible=\"$( rootAttr "$TMP/nofns.default" eligible )\" cut_reachable=\"$( rootAttr "$TMP/nofns.default" cut_reachable )\""
fi
if [ "$( grep -o '<s ' "$TMP/nofns.default" | wc -l | tr -d ' ' )" = "0" ]; then
    ok "(J) and it emits no rows"
else
    no "(J) the JSON-only corpus emitted rows with no eligible function"
fi
if [ "$( rootAttr "$TMP/panelc.default" cut_reachable )" = "1" ]; then
    ok "(J) the C++ fixture reports cut_reachable=\"1\" — the flag is a measurement, not a constant"
else
    no "(J) the C++ fixture must report cut_reachable=\"1\""
fi

# ── (K) a bad preset is REFUSED ───────────────────────────────────────────────────────────────────────────
if "$BIN" "$PANELC" --quality-panel=bogus --no-cache >"$TMP/bogus.out" 2>"$TMP/bogus.err"; then
    no "(K) --quality-panel=bogus exited 0 — an unknown preset must be refused, never degraded to default, because a preset IS the selection and substituting one answers a different question under the label the caller typed"
else
    if grep -q 'strict|default|lenient' "$TMP/bogus.err"; then
        ok "(K) an unknown preset is refused, with the supported list"
    else
        no "(K) the refusal does not name the supported presets"
        sed 's/^/        /' "$TMP/bogus.err"
    fi
fi

# ── (L) determinism + well-formedness ─────────────────────────────────────────────────────────────────────
for pair in "panelc:$PANELC" "rustone:$RUSTONE" "nofns:$NOFNS"; do
    fx="${pair%%:*}"; d="${pair#*:}"
    for p in strict default lenient; do
        panel "$d" "$p" >"$TMP/$fx.$p.again"
        if cmp -s "$TMP/$fx.$p" "$TMP/$fx.$p.again"; then
            ok "(L) $fx/$p is byte-identical across two --no-cache runs"
        else
            no "(L) $fx/$p is not deterministic across two identical runs"
        fi
        if command -v xmllint >/dev/null 2>&1; then
            if xmllint --noout "$TMP/$fx.$p" 2>"$TMP/$fx.$p.lint"; then
                ok "(L) $fx/$p parses as XML"
            else
                no "(L) $fx/$p emitted a document xmllint rejects"
                sed 's/^/        /' "$TMP/$fx.$p.lint"
            fi
        fi
    done
done

# ── (M) ADDITIVITY: the flagless map does not move ────────────────────────────────────────────────────────
"$BIN" "$PANELC" --no-cache >"$TMP/map.a" 2>/dev/null
"$BIN" "$PANELC" --no-cache >"$TMP/map.b" 2>/dev/null
if cmp -s "$TMP/map.a" "$TMP/map.b" && [ -s "$TMP/map.a" ]; then
    ok "(M) the flagless map is unchanged and deterministic beside the new verb"
else
    no "(M) the flagless map moved — every flag in this tool is purely additive"
fi

# ── (N) the historical family is FILE-level evidence, measured then disclosed ─────────────────────────────
# (N1) THE MEASUREMENT. hub.cpp holds two eligible functions and is the only churned file, so under `lenient`
# both are rows and both fire historical. If the family were a per-symbol claim their evidence could differ;
# it cannot, because there is one churn number per path. awk over the split document, never a grep for a
# string the assertion itself supplies — the point is to read back what the binary actually emitted.
tr '<' '\n' <"$TMP/panelc.lenient" >"$TMP/panelc.lenient.lines"
awk '
    /^s p="/           { inhub = ( $0 ~ /p="[^"]*hub\.cpp:/ ) }
    inhub && /^e f="historical"/ {
        if( match( $0, /why="[^"]*"/ ) ) { print substr( $0, RSTART + 5, RLENGTH - 6 ) }
    }
' "$TMP/panelc.lenient.lines" >"$TMP/hub.historical"
hubRows="$( wc -l <"$TMP/hub.historical" | tr -d ' ' )"
hubDistinct="$( sort -u "$TMP/hub.historical" | wc -l | tr -d ' ' )"
if [ "$hubRows" -ge 2 ] && [ "$hubDistinct" = "1" ]; then
    ok "(N1) all $hubRows hub.cpp rows carry the IDENTICAL historical evidence ($( head -1 "$TMP/hub.historical" )) — the family's unit is the file, and a symbol inherits it"
else
    no "(N1) expected >=2 hub.cpp rows sharing ONE historical evidence string; got $hubRows row(s), $hubDistinct distinct. Either the fixture stopped producing two churned rows (the arm then asserts nothing) or the family's unit changed, which the legend below still describes as file level"
    sed 's/^/        /' "$TMP/hub.historical"
fi
# The control: the family is not file-level by accident of a one-file corpus. plain.cpp is committed once,
# so its rows must NOT fire historical at all — otherwise (N1) would hold for a family that fired everywhere.
if awk '
    /^s p="/ { inplain = ( $0 ~ /p="[^"]*plain\.cpp:/ ) }
    inplain && /^e f="historical"/ { found = 1 }
    END { exit( found ? 1 : 0 ) }
' "$TMP/panelc.lenient.lines"; then
    ok "(N1) the once-committed file fires historical on NO row — (N1) pins a shared value, not a constant one"
else
    no "(N1) plain.cpp fired historical; the churn cut reached the unchurned file, so (N1)'s shared value proves nothing"
fi
# (N2) THE DISCLOSURE. The legend a reader meets FIRST must say the unit out loud, next to the family name.
# Both legends carry the claim: the panel's own, and --ensemble's, which is where the four calibrated
# families are described and where the same sentence used to stop at "git change frequency".
legendOf(){ sed 's/-->/-->\n/g' "$1" | sed -n '1,/-->/p'; }   # the LEADING comment block only
"$BIN" "$PANELC" --ensemble --no-cache >"$TMP/panelc.ensemble" 2>/dev/null
for pair in "quality-panel:$TMP/panelc.default" "ensemble:$TMP/panelc.ensemble"; do
    verb="${pair%%:*}"; doc="${pair#*:}"
    legendOf "$doc" >"$TMP/legend.$verb"
    if grep -q 'historical (git change frequency, measured PER FILE' "$TMP/legend.$verb"; then
        ok "(N2) the $verb legend names the historical family's UNIT where the family is introduced"
    else
        no "(N2) the $verb legend describes historical without saying the measurement is PER FILE. Every symbol in a file shares one churn=/hrank=, so a row in a churny file collects this family with no property of its own; a legend that says only 'git change frequency' invites a reader to count it as per-symbol evidence in a report whose whole premise is families that can disagree"
    fi
    if grep -q 'inherited by the row' "$TMP/legend.$verb"; then
        ok "(N2) and spells out the consequence — the row INHERITS the file's evidence"
    else
        no "(N2) the $verb legend states the unit but not what follows from it: a reader needs to know the row inherited this family rather than earned it"
    fi
done

# ── (O) the deep x untested JOIN — an annotation, not a family ────────────────────────────────────────────
panel "$DEEPJ" lenient >"$TMP/deepj.lenient"
tr '<' '\n' <"$TMP/deepj.lenient" >"$TMP/deepj.lines"
# One line per emitted row: "<name> <TAB> <the whole start tag>". awk, not a chain of greps, so the tag is
# read back exactly as emitted rather than reconstructed from the assertion's own expectations.
awk '
    /^s p="/ {
        tag = $0
        sub( />$/, "", tag )
        nm = tag
        sub( /^.* n="/, "", nm ); sub( /".*$/, "", nm )
        printf "%s\t%s\n", nm, tag
    }
' "$TMP/deepj.lines" >"$TMP/deepj.rows"
rowTag(){ awk -F'\t' -v want="$1" '$1 == want { print $2; exit }' "$TMP/deepj.rows"; }
testedTag="$( rowTag deepTestedRoutine )"
untestedTag="$( rowTag deepUntestedRoutine )"
if [ -n "$testedTag" ] && [ -n "$untestedTag" ]; then
    ok "(O) both twin functions are rows — the join fixture asserts something"
else
    no "(O) the deep fixture did not emit both twins as rows (tested=[$testedTag] untested=[$untestedTag]); the rest of (O) would assert nothing"
    sed 's/^/        /' "$TMP/deepj.rows"
fi
tScope="$( rootAttr "$TMP/deepj.lenient" tested_scope )"
if [ -n "$tScope" ] && [ "$tScope" != "0" ]; then
    ok "(O) tested_scope=\"$tScope\" — an indexed test reaches something here, so 'untested' is a claim about the code"
else
    no "(O) the deep fixture must report a non-zero tested_scope= (its test/ file calls one of the twins); got \"$tScope\". Without it the join is suppressed by design and (O1) below cannot fire"
fi
# (O1)/(O2) — the annotation fires on exactly one of two identical bodies, and it is the uncovered one.
case "$untestedTag" in
    *'join="deep+untested"'*) ok "(O1) the deep function no test reaches carries join=\"deep+untested\"" ;;
    *)                        no "(O1) the deep, uncovered twin carries no join= annotation — the one pair the panel is supposed to point at: $untestedTag" ;;
esac
case "$testedTag" in
    *join=*) no "(O2) the deep twin a test DOES reach carries a join= annotation; the join then says nothing about coverage and is just a second name for deep=: $testedTag" ;;
    *)       ok "(O2) the covered twin carries no annotation — the annotation tracks coverage, not depth alone" ;;
esac
# (O3) — the rows are otherwise identical, and in definition order. Strip the two attributes that must differ
# (p= and n=) and the annotation itself; what remains must match byte for byte.
strip(){ printf '%s' "$1" | sed 's/ p="[^"]*"//; s/ n="[^"]*"//; s/ join="[^"]*"//'; }
if [ "$( strip "$testedTag" )" = "$( strip "$untestedTag" )" ] && [ -n "$testedTag" ]; then
    ok "(O3) the two rows are identical once p=, n= and the annotation are removed — the join adds no evidence and moves no count"
else
    no "(O3) the twin rows differ by more than the join annotation, so the join is not purely additive:"
    printf '        tested  : %s\n' "$( strip "$testedTag" )"
    printf '        untested: %s\n' "$( strip "$untestedTag" )"
fi
order="$( awk -F'\t' '$1 == "deepTestedRoutine" || $1 == "deepUntestedRoutine" { print $1 }' "$TMP/deepj.rows" | tr '\n' ' ' )"
if [ "$order" = "deepTestedRoutine deepUntestedRoutine " ]; then
    ok "(O3) and they come out in definition order, annotated one SECOND — the annotation is not a secondary sort key"
else
    no "(O3) the twins must appear in NodeId (definition) order 'deepTestedRoutine deepUntestedRoutine'; got '$order'. A join that reorders rows changes which rows survive the limit= window, which is a ranking change wearing an annotation's clothes"
fi
# (O4) — no indexed test anywhere: the annotation is suppressed, not fired on everything.
panelScope="$( rootAttr "$TMP/panelc.lenient" tested_scope )"
if [ "$panelScope" = "0" ]; then
    ok "(O4) the test-less fixture reports tested_scope=\"0\" — the join's denominator is measured per corpus"
else
    no "(O4) PANELC has no test path, so tested_scope= must be \"0\"; got \"$panelScope\""
fi
if grep -q 'join="' "$TMP/panelc.lenient"; then
    no "(O4) a corpus where no indexed test reaches anything still emitted join= annotations. Every deep row would carry one, which reports the absence of an indexed test suite as a property of each function"
else
    ok "(O4) and emits the annotation on no row at all"
fi
# The legend must define what the reader just met, and say what it is NOT.
legendOf "$TMP/deepj.lenient" >"$TMP/legend.join"
for token in 'join=' 'tested_scope=' 'deep_untested='; do
    if grep -q "$token" "$TMP/legend.join"; then
        ok "(O) the legend defines $token"
    else
        no "(O) the legend does not define $token — a marker a reader meets on the first screen with no definition where they meet it is the exact class test/legendcoveragecheck.sh exists for"
    fi
done

if [ "$fail" -eq 0 ]; then
    echo "qualitypanelcheck: PASS"
    exit 0
fi
echo "qualitypanelcheck: FAIL"
exit 1
