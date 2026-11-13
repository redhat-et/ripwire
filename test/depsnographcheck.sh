#!/usr/bin/env bash
# depsnographcheck.sh — card DEPS-NO-GRAPH: --deps and --arch answer from the ingest alone (runArchViews reads d.ing, never
# d.g), so when one of them is the dispatch WINNER and no modifier reads the graph before dispatch, main skips buildGraph.
# RIPWIRE_STATS's `[mem] phase=graph-end` line (src/memstats.h, printed once at buildGraph's end) is the probe for "the graph
# was built". The fixture is generated here, never committed.
#
# Arms:
#   P  positive: `--deps` and `--arch=RULES` print no graph phase line, and their stdout is byte-identical to the same verb
#      with --metrics (a modifier that reads the graph, so that run still builds it): the skip changes no answer byte.
#      The premise (the --metrics run printed graph-end once, the --deps answer names >= 2 files) is counted first.
#   N  negative: a graph verb still builds the graph — `--callers=SYM` prints phase=graph-end exactly once. FAILS on 0.
#   W  the winner, not the flag (audit risk iii): `--lego=TYPE --deps` answers --lego (it outranks --deps in §B11.4's table),
#      so it must build the graph: graph-end once. FAILS on 0.
#   M  modifiers that read the graph before dispatch keep the build: `--deps --pin-census=FILE` prints graph-end once and
#      writes the census.
#   G  the grep prefetch path is untouched: `--grep=LITERAL` still answers rc 0 with a hit (the worker joins inside the
#      same lambda the skip sits in).
#
# Usage: bash test/depsnographcheck.sh [BIN]
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
case "$BIN" in /*) ;; *) BIN="$PWD/$BIN" ;; esac
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ fail=1; printf '  FAIL  %s\n' "$*"; return 0; }

if ! "$BIN" --version 2>/dev/null | grep -q '^ripwire '; then
    echo "  FAIL  $BIN does not run"; echo "FAIL depsnographcheck"; exit 1
fi

# ---- the fixture: a small C++ tree with includes across two layers and calls between them ----
REPO="$TMP/repo"; mkdir -p "$REPO/core" "$REPO/ui"
cat >"$REPO/core/store.h" <<'EOF'
#pragma once
struct Store { int get() const; void put( int v ); int value = 0; };
int storeCount();
EOF
cat >"$REPO/core/store.cpp" <<'EOF'
#include "store.h"
int Store::get() const { return value; }
void Store::put( int v ) { value = v; }
int storeCount() { Store s; s.put( 3 ); return s.get(); }
EOF
cat >"$REPO/ui/view.h" <<'EOF'
#pragma once
#include "../core/store.h"
struct View { Store store; int render(); };
EOF
cat >"$REPO/ui/view.cpp" <<'EOF'
#include "view.h"
int View::render() { store.put( storeCount() ); return store.get(); }
int drawAll() { View v; return v.render() + storeCount(); }
EOF
cat >"$REPO/core/leak.cpp" <<'EOF'
#include "../ui/view.h"
int coreUsesUi() { return drawAll(); }
EOF
cat >"$TMP/rules.arch" <<'EOF'
deny path core/.* -> ui/.*
EOF

# run NAME ARGS... -> $TMP/NAME.out / .err / .rc, RIPWIRE_STATS set, no cache
run(){ local name="$1"; shift; ( cd "$REPO" && RIPWIRE_STATS=1 "$BIN" "$REPO" --no-cache "$@" >"$TMP/$name.out" 2>"$TMP/$name.err" ); echo $? >"$TMP/$name.rc"; }
ends(){ grep -c '^\[mem\] phase=graph-end ' "$TMP/$1.err"; }
graphs(){ grep -c '^\[mem\] phase=graph-' "$TMP/$1.err"; }

# ---- P ----
run deps --deps; run depsm --deps --metrics
nfiles="$( grep -o '<f ' "$TMP/deps.out" | wc -l | tr -d ' ' )"
if [ "$( cat "$TMP/deps.rc" )" != 0 ] || [ "$( cat "$TMP/depsm.rc" )" != 0 ] || [ "$( ends depsm )" -ne 1 ] || [ "${nfiles:-0}" -lt 2 ]; then
    no "P: premise: --deps rc $( cat "$TMP/deps.rc" ), --deps --metrics rc $( cat "$TMP/depsm.rc" ) with graph-end x$( ends depsm ) (want 1), $nfiles file rows (want >= 2)"
elif [ "$( graphs deps )" -ne 0 ]; then
    no "P: --deps printed $( graphs deps ) graph phase lines (want 0: it never reads the graph)"
elif ! cmp -s "$TMP/deps.out" "$TMP/depsm.out"; then
    no "P: --deps stdout differs between the skipped build and the built graph (--metrics)"
else
    ok "P: --deps builds no graph; stdout byte-identical to the graph-built run ($( wc -c <"$TMP/deps.out" | tr -d ' ' ) B, $nfiles file rows)"
fi
run arch --arch="$TMP/rules.arch"; run archm --arch="$TMP/rules.arch" --metrics
nviol="$( grep -o 'violations="[0-9]*"' "$TMP/arch.out" | head -1 )"
if [ "$( ends archm )" -ne 1 ] || [ "$nviol" = 'violations="0"' ] || [ -z "$nviol" ]; then
    no "P: premise: --arch --metrics graph-end x$( ends archm ) (want 1), ${nviol:-no violations attribute} (want >= 1: core/leak.cpp -> ui)"
elif [ "$( graphs arch )" -ne 0 ]; then
    no "P: --arch printed $( graphs arch ) graph phase lines (want 0)"
elif ! cmp -s "$TMP/arch.out" "$TMP/archm.out" || [ "$( cat "$TMP/arch.rc" )" != "$( cat "$TMP/archm.rc" )" ]; then
    no "P: --arch stdout or rc differs between the skipped build and the built graph (rc $( cat "$TMP/arch.rc" ) vs $( cat "$TMP/archm.rc" ))"
else
    ok "P: --arch builds no graph; stdout and rc $( cat "$TMP/arch.rc" ) byte-identical to the graph-built run ($nviol)"
fi

# ---- N ----
run callers --callers=storeCount
n="$( ends callers )"
if [ "$n" -ne 1 ]; then
    no "N: --callers printed graph-end x$n (want 1: a graph verb must build the graph)"
elif ! grep -q 'drawAll' "$TMP/callers.out"; then
    no "N: --callers=storeCount does not name drawAll"
else
    ok "N: --callers builds the graph (graph-end x1) and names drawAll"
fi

# ---- W ----
run lego --lego=Store --deps
n="$( ends lego )"
if [ "$n" -ne 1 ]; then
    no "W: --lego --deps printed graph-end x$n (want 1: --lego outranks --deps and reads the graph)"
else
    ok "W: --lego=Store --deps builds the graph (the dispatch winner decides, not the --deps flag)"
fi

# ---- M ----
run pin --deps --pin-census="$TMP/census.tsv"
n="$( ends pin )"
if [ "$n" -ne 1 ] || [ ! -s "$TMP/census.tsv" ]; then
    no "M: --deps --pin-census printed graph-end x$n (want 1) and the census is $( [ -s "$TMP/census.tsv" ] && echo written || echo missing )"
else
    ok "M: --deps --pin-census builds the graph and writes the census"
fi

# ---- G ----
run grep --grep=storeCount
if [ "$( cat "$TMP/grep.rc" )" != 0 ] || ! grep -q 'storeCount' "$TMP/grep.out"; then
    no "G: --grep=storeCount rc $( cat "$TMP/grep.rc" ), hit $( grep -c storeCount "$TMP/grep.out" )"
else
    ok "G: --grep answers through the prefetch worker (rc 0, a hit)"
fi

if [ "$fail" -eq 0 ]; then echo "PASS depsnographcheck"; exit 0; fi
echo "FAIL depsnographcheck"; exit 1
