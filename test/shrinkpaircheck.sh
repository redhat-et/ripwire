#!/usr/bin/env bash
# shrinkpaircheck.sh — QD-SHRINK-PAIR: a clone row that crossed the bar only because a member SHRANK (quality.h demoteShrinkOnlyClones).
#
# WHY THIS GATE EXISTS. lane/sort-unique (2026-11-19) handed cFamilyMacroNames' sort + erase(unique) pair to a helper. Its body fell
# 135 -> 99 tokens, its LCS with jsExportsOf fell 85 -> 82, and the pair crossed the 0.8 Type-3 bar: a duplication row and a
# new-clone-of-reused-helper row, both gating, about an edit that removed code and copied none. The rule: every member existed at the
# base, some member's body has fewer tokens now, and no pair's shared LCS grew -> the row is minor, why= naming the member that shrank.
#
# WHAT THIS GATE PINS (fixture: the T5 shape, a filter-push-sort collector beside an export collector with three callers, so both
# clone kinds row; both members committed at the base, where the pair is under the bar):
#   (P1) range form: the collector shrinks (sort + erase -> a helper call) -> both rows minor, not gating, why= names it and the LCS
#   (P1w) the same edit in the working tree (auto-baseline vs HEAD) -> the same verdict and why=
#   (P1m) the MCP quality_delta row carries the same why= and does not gate
#   (P2) both members shrink, no pair's LCS grows -> minor, why= names both
#   (N1) the collector shrinks AND the other member copies one of its statements in (the LCS grew) -> GATES
#   (N2) a member the base did not hold (the shrunk old member beside a new copy) -> GATES
#   (N3) both shrink but one copies a statement in (the LCS grew) -> GATES
#   (N4) the collector cut to under half its base body -> GATES (a long base body holds most short ones as a subsequence, so its
#        base LCS saturates and cannot tell removal from a rewrite; census 11-20: textual ColorSystem::generate 1569 -> 22 tok)
#   (C)  PREMISE COUNT — every arm found both its rows (a missing row would pass a "gates"/"minor" arm vacuously)
#   (L)  a document with a shrink why= defines it (full legend) and does not print the operand or unhandled-arm sentence; one
#        without carries neither
#   (J)  determinism — two runs byte-identical
# Red-before: on a binary without the rule, P1/P1w/P1m/P2 gate (FAIL). Guard-off (the LCS test removed, a member without a base
# body skipped instead of refusing the group): N1-N3 FAIL; the cut test removed: N4 FAILS. See docs/EVALS.md "Clone shrink-only pairs".
#
# Usage:  bash test/shrinkpaircheck.sh [BIN]

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" TMPDIR="$TMP"; mkdir -p "$HOME"
fail=0; seen=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }

# The fixtures are WRITTEN HERE, never committed: they are clones on purpose, and a committed copy would sit in this repo as a clone
# group its own quality-delta reports. Variant words select optional statements: big|small (the collector's sort + erase, or the
# helper call), reserve (a reserve statement), imported (the export collector's second push), extra (an early-return block).
macros(){   # macros <variant>
    printf '#pragma once\n#include <algorithm>\n#include <string>\n#include <vector>\n#include "model.h"\nnamespace macros\n{\n'
    printf 'inline std::vector<std::string> collectMacroNames( const Index& ing )\n{\n    std::vector<std::string> names;\n'
    case $1 in *reserve*) printf '    names.reserve( ing.symbols.size() );\n';; esac
    case $1 in *huge*)
        printf '    for( const Binding& b : ing.bindings )\n    {\n        if( b.kind == BindKind::Other && b.fileId > 3 )\n        {\n'
        printf '            names.push_back( b.var + "_bound" );\n            names.push_back( b.importedName );\n        }\n    }\n'
        printf '    for( const Symbol& s : ing.symbols )\n    {\n        if( s.kind == Kind::Fn && s.name.size() > 3 && s.lang != Lang::C )\n        {\n'
        printf '            names.push_back( s.name + "_fn" );\n            names.push_back( std::string( s.name.rbegin(), s.name.rend() ) );\n        }\n    }\n'
        printf '    if( names.size() > 1000 )\n    {\n        names.resize( 1000 );\n        names.shrink_to_fit();\n    }\n';;
    esac
    printf '    for( const Symbol& s : ing.symbols )\n    {\n'
    printf '        if( s.kind == Kind::Macro && ( s.lang == Lang::Cpp || s.lang == Lang::C || s.lang == Lang::ObjC ) )\n        {\n'
    printf '            names.push_back( s.name );\n        }\n    }\n'
    case $1 in
        big*)   printf '    std::sort( names.begin(), names.end() );\n    names.erase( std::unique( names.begin(), names.end() ), names.end() );\n';;
        small*) printf '    util::sortUnique( names );\n';;
    esac
    printf '    return names;\n}\n}\n'
}
exportsof(){   # exportsof <variant>
    printf '#pragma once\n#include <algorithm>\n#include <string_view>\n#include <vector>\n#include "model.h"\nnamespace exportsof\n{\n'
    printf 'inline std::vector<std::string_view> collectExports( const Index& ing, unsigned f )\n{\n    std::vector<std::string_view> out;\n'
    case $1 in *reserve*) printf '    out.reserve( ing.bindings.size() );\n';; esac
    printf '    for( const Binding& b : ing.bindings )\n    {\n        if( b.kind == BindKind::JsExport && b.fileId == f )\n        {\n'
    printf '            out.push_back( b.var );\n'
    case $1 in *extra*) printf '            if( out.empty() || f == 0 )\n            {\n                return out;\n            }\n';; esac
    case $1 in *imported*) printf '            if( !b.importedName.empty() )\n            {\n                out.push_back( b.importedName );\n            }\n';; esac
    printf '        }\n    }\n    std::ranges::sort( out, util::svLess );\n    return out;\n}\n'
    printf 'inline int useA( const Index& i ) { return int( collectExports( i, 1 ).size() ); }\n'
    printf 'inline int useB( const Index& i ) { return int( collectExports( i, 2 ).size() ); }\n'
    printf 'inline int useC( const Index& i ) { return int( collectExports( i, 3 ).size() ); }\n}\n'
}
model(){
    printf '#pragma once\n#include <string>\n#include <vector>\nenum class Kind { Macro, Fn };\nenum class Lang { Cpp, C, ObjC };\n'
    printf 'enum class BindKind { JsExport, Other };\nstruct Symbol { Kind kind; Lang lang; std::string name; };\n'
    printf 'struct Binding { BindKind kind; unsigned fileId; std::string var; std::string importedName; };\n'
    printf 'struct Index { std::vector<Symbol> symbols; std::vector<Binding> bindings; };\n'
}
# mkrepo <name> <base macros|none> <base exports> <head macros> <head exports> <commit|tree>: the base committed, the head committed
# on top ("commit", for the range form) or left in the working tree ("tree").
mkrepo()
{
    local R="$TMP/$1"
    mkdir -p "$R/src"
    ( cd "$R" && git init -q . && git config user.email t@t && git config user.name t && git config commit.gpgsign false ) || return 1
    model >"$R/src/model.h"
    [ "$2" = none ] || macros "$2" >"$R/src/macros.h"
    exportsof "$3" >"$R/src/exportsof.h"
    ( cd "$R" && git add -A && git commit -qm base ) || return 1
    macros "$4" >"$R/src/macros.h"
    exportsof "$5" >"$R/src/exportsof.h"
    [ "$6" = tree ] || ( cd "$R" && git add -A && git commit -qm head ) || return 1
    return 0
}
# qd <repo>: the range form over the head commit, or the working-tree form when the repo's head is uncommitted
qd(){ if git -C "$TMP/$1" diff --quiet 2>/dev/null; then "$BIN" "$TMP/$1" --quality-delta=HEAD~1..HEAD --no-cache 2>/dev/null; else "$BIN" "$TMP/$1" --quality-delta --no-cache 2>/dev/null; fi; }   # status: exits 0 or 2 (gating) by design; the rows are the verdict
# rows <repo>: the two clone rows, one line each (duplication first)
rows(){ qd "$1" | tr '<' '\n' | grep -E '^r kind="(duplication|new-clone-of-reused-helper)"'; }   # status: an empty result FAILs the arm that reads it

# demotes <label> <rows> <why substring>...: both clone rows exist, are minor, do not gate, and carry every why substring
demotes()
{
    local label="$1" rs="$2" r k w; shift 2
    for k in duplication new-clone-of-reused-helper; do
        r="$( printf '%s\n' "$rs" | grep "^r kind=\"$k\"" )"   # status: an empty r FAILs below
        [ -n "$r" ] || { no "$label: no $k row at all — the arm is vacuous"; continue; }
        seen=$(( seen + 1 ))
        case "$r" in *'sev="minor"'*) ok "$label: $k minor";; *) no "$label: $k not minor (row: $r)";; esac
        case "$r" in *'gating="1"'*) no "$label: $k still gates (row: $r)";; *) ok "$label: $k does not gate";; esac
        for w in "$@"; do
            case "$r" in *"$w"*) ok "$label: $k why= has \"$w\"";; *) no "$label: $k why= lacks \"$w\" (row: $r)";; esac
        done
    done
}
# gates <label> <rows>: both clone rows exist and gate, with no shrink why=
gates()
{
    local label="$1" rs="$2" r k
    for k in duplication new-clone-of-reused-helper; do
        r="$( printf '%s\n' "$rs" | grep "^r kind=\"$k\"" )"   # status: an empty r FAILs below
        [ -n "$r" ] || { no "$label: no $k row at all — the negative proves nothing"; continue; }
        seen=$(( seen + 1 ))
        case "$r" in *'gating="1"'*) ok "$label: $k gates";; *) no "$label: $k stopped gating (row: $r)";; esac
        case "$r" in *'crossed the bar'*) no "$label: $k carries a shrink why= (row: $r)";; *) ok "$label: $k no shrink why=";; esac
    done
}

echo "── positives"
mkrepo p1 big imported small imported commit || { echo "git fixture setup failed"; exit 2; }
P1="$( rows p1 )"
demotes "(P1) the collector hands sort+erase to a helper (range)" "$P1" "pair crossed the bar because collectMacroNames shrank " "; shared code did not grow (LCS "
mkrepo p1w big imported small imported tree || { echo "git fixture setup failed"; exit 2; }
P1W="$( rows p1w )"
demotes "(P1w) the same edit in the working tree" "$P1W" "pair crossed the bar because collectMacroNames shrank "
why1="$( printf '%s\n' "$P1" | grep -o 'why="[^"]*"' | head -1 )"; why1w="$( printf '%s\n' "$P1W" | grep -o 'why="[^"]*"' | head -1 )"
if [ -n "$why1" ] && [ "$why1" = "$why1w" ]; then ok "(P1w) why= equals the range form's: $why1"; else no "(P1w) why= differs: range '${why1:-<none>}' tree '${why1w:-<none>}'"; fi
mkrepo p2 big importedextra small imported commit || { echo "git fixture setup failed"; exit 2; }
demotes "(P2) both members shrink, no LCS grows" "$( rows p2 )" "collectExports shrank " " and collectMacroNames shrank "

echo "── (P1m) MCP"
if command -v python3 >/dev/null 2>&1; then
    MC="$( printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
        '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"quality_delta","arguments":{"path":"'"$TMP/p1w"'"}}}' \
        | "$BIN" --mcp 2>/dev/null | tail -1 )"   # status: the probe below reads the reply; an empty one prints BROKEN
    V="$( printf '%s' "$MC" | python3 -c '
import json, sys
try:
    d = json.loads(sys.stdin.read())
    d = json.loads(d["result"]["content"][0]["text"])
except Exception as e: print("BROKEN %s" % e); raise SystemExit
rs = [r for r in d.get("r", []) if r.get("kind") == "duplication"]
print("ROWS %d GATING %d WHY %s" % (len(rs), sum(1 for r in rs if r.get("gating") is True), rs[0].get("why", "-").replace(" ", "_") if rs else "-"))' )"
    case "$V" in
        "ROWS 1 GATING 0 WHY pair_crossed_the_bar_because_collectMacroNames_shrank_"*) ok "(P1m) MCP: one duplication row, not gating, the shrink why=";;
        *) no "(P1m) MCP: $V";;
    esac
else
    echo "  SKIP  (P1m) MCP row check (python3 not installed)"
fi

echo "── negatives"
mkrepo n1 bigreserve imported smallreserve importedreserve commit || { echo "git fixture setup failed"; exit 2; }
gates "(N1) the collector shrinks, the other member copies its reserve statement in" "$( rows n1 )"
mkrepo n2 none importedextra small imported commit || { echo "git fixture setup failed"; exit 2; }
gates "(N2) a new copy beside a shrunk old member" "$( rows n2 )"
mkrepo n3 bigreserve importedextra smallreserve importedreserve commit || { echo "git fixture setup failed"; exit 2; }
gates "(N3) both shrink, one copies a statement in" "$( rows n3 )"
mkrepo n4 bighuge imported small imported commit || { echo "git fixture setup failed"; exit 2; }
gates "(N4) the collector cut to under half its body (a rewrite: its base LCS saturates)" "$( rows n4 )"

echo "── (C) premise count"
if [ "$seen" -eq 14 ]; then ok "(C) all 14 rows of the 7 arms found"; else no "(C) $seen of 14 rows found"; fi

echo "── (L) legend"
FULL="$( "$BIN" "$TMP/p1" --quality-delta=HEAD~1..HEAD --no-cache --legend=full 2>/dev/null )"   # status: exits 0 or 2 by design; the legend text is the verdict
case "$FULL" in *'crossed the bar because X shrank'*) ok "(L) a shrink why= document defines it";; *) no "(L) a shrink why= document never defines it";; esac
case "$FULL" in *'operate on DIFFERENT DATA'*) no "(L) a shrink why= document prints the operand sentence";; *) ok "(L) a shrink why= document carries no operand sentence";; esac
# why= is one Regression field shared by clone, tangle and unhandled-arm rows (train ge2 compose): a clone why= must not pull in
# the unhandled-arm sentence (CodeRabbit #714 verbs_quality.h:1983; red on fdce7c59e, whose test was "any row has why=")
UA_ROWS="$( printf '%s' "$FULL" | grep -c 'unhandled-arm"' )"   # status: grep -c counts; 0 is the premise, not a failure
case "$FULL" in
    *'unhandled-arm: a classifier'*) no "(L) a shrink why= document with $UA_ROWS unhandled-arm rows prints the unhandled-arm sentence";;
    *)                               if [ "$UA_ROWS" -eq 0 ] && printf '%s' "$FULL" | grep -q ' why="'; then ok "(L) a clone why= document carries no unhandled-arm sentence"; else no "(L) premise: want a why= row and 0 unhandled-arm rows (got $UA_ROWS)"; fi;;
esac
FULL1="$( "$BIN" "$TMP/n1" --quality-delta=HEAD~1..HEAD --no-cache --legend=full 2>/dev/null )"   # status: exits 0 or 2 by design; the legend text is the verdict
case "$FULL1" in *'crossed the bar because X shrank'*) no "(L) a document without a shrink why= pays for the sentence";; *) ok "(L) a document without a shrink why= carries no shrink sentence";; esac

echo "── (J) determinism"
qd p1 >"$TMP/a"; qd p1 >"$TMP/b"   # status: exits 0 or 2 by design; the byte compare below is the verdict
if cmp -s "$TMP/a" "$TMP/b"; then ok "(J) two runs byte-identical"; else no "(J) two runs differ"; fi

echo
[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAILURES"; exit 1
