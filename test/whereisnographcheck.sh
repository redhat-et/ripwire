#!/usr/bin/env bash
# whereisnographcheck.sh — card WHEREIS-NO-GRAPH: --whereis answers from the ingest and the git object store alone (the
# runCrossRef arm reads d.ing, d.redactPtr and the repo's refs, never d.g), so when it is the dispatch WINNER and no modifier
# reads the graph before dispatch, main skips buildGraph — the DEPS-NO-GRAPH skip (test/depsnographcheck.sh), one verb wider.
# RIPWIRE_STATS's `[mem] phase=graph-*` lines (src/memstats.h, printed by buildGraph) are the probe for "the graph was
# built". The fixture is a git repository generated here, never committed: three commits on main (one of them deletes a
# function) and a branch that holds a function main never had.
#
# Arms:
#   P  positive, per symbol kind — class, free function, method, macro, a branch-only function (on-head="0"), a name main
#      deleted (with --with-history), an @FILE:LINE seed and a near-miss zero: `--whereis=SYM` prints no graph phase line,
#      and its stdout and rc are byte-identical to the same call with --metrics (a modifier that reads the graph, so that
#      run still builds it). The premise is counted first: the --metrics run printed graph-end once and rc 0, and every
#      kind but the zero answered hits >= 1.
#   N  negative: a graph verb still builds the graph — `--callers=storeCount` prints phase=graph-end exactly once.
#   W  the winner, not the flag: `--callers=storeCount --whereis=Store` answers --callers (it outranks --whereis in
#      §B11.4's table), so it must build the graph: graph-end once.
#   M  modifiers that read the graph before dispatch keep the build: `--whereis=Store --pin-census=FILE` prints graph-end
#      once and writes the census.
#   S  the warm snapshot (src/warmsnap.h), with --cache, against --callers (the graph verb that shares --whereis's
#      parse-cache family, so the two meet at one snapshot): a graph-skipping --whereis run never leaves a graph a later run
#      serves. (S1) three --whereis runs on a cold cache (the third loads the stored model, so something WAS stored), then
#      --callers: its graph is built, not loaded; the --callers run after that loads the graph it stored. (S2) a cache whose
#      graph --callers stored and served (graph=loaded): a --whereis in between leaves it served. Every cached answer is
#      the --no-cache run's bytes. S1's "built, not loaded" is red on a binary that builds the graph for --whereis.
#
# Usage: bash test/whereisnographcheck.sh [BIN]
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
case "$BIN" in /*) ;; *) BIN="$PWD/$BIN" ;; esac
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ fail=1; printf '  FAIL  %s\n' "$*"; return 0; }

if ! "$BIN" --version 2>/dev/null | grep -q '^ripwire '; then   # status: a binary that cannot run prints no version line, so the grep fails it
    echo "  FAIL  $BIN does not run"; echo "FAIL whereisnographcheck"; exit 1
fi
command -v git >/dev/null 2>&1 || { echo "  FAIL  git is required (the fixture is a repository)"; echo "FAIL whereisnographcheck"; exit 1; }
# The warm snapshot lives in ripwire's cache directory; TMPDIR outranks XDG_CACHE_HOME in its ladder, so both point here.
export XDG_CACHE_HOME="$TMP/xdg" TMPDIR="$TMP/tmpdir"; mkdir -p "$XDG_CACHE_HOME" "$TMPDIR"

# ---- the fixture: a git repository with a class, a free function, a method, a macro, a deleted name and a branch ----
REPO="$TMP/repo"; mkdir -p "$REPO/core" "$REPO/ui"
g(){ git -C "$REPO" -c user.name=gate -c user.email=gate@example.invalid -c commit.gpgsign=false "$@" >/dev/null 2>&1; }
g init -q -b main || g init -q
g checkout -q -B main
cat >"$REPO/core/store.h" <<'EOF'
#pragma once
#define STORE_MAX 64
struct Store { int get() const; void put( int v ); int value = 0; };
int storeCount();
int legacyTotal();
EOF
cat >"$REPO/core/store.cpp" <<'EOF'
#include "store.h"
int Store::get() const { return value; }
void Store::put( int v ) { value = v < STORE_MAX ? v : STORE_MAX; }
int storeCount() { Store s; s.put( 3 ); return s.get(); }
int legacyTotal() { return storeCount() * 2; }
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
g add -A; g commit -q -m one
# commit two: main deletes legacyTotal, so only history holds it
sed -i.bak '/legacyTotal/d' "$REPO/core/store.h" "$REPO/core/store.cpp"; rm -f "$REPO"/core/*.bak
g add -A; g commit -q -m two
# a branch with a function main never had
g checkout -q -b feature
printf 'int strandedFix( int x ) { return x + STORE_MAX; }\n' >>"$REPO/core/store.cpp"
g add -A; g commit -q -m stranded
g checkout -q main
printf 'int drawTwice() { return drawAll() * 2; }\n' >>"$REPO/ui/view.cpp"
g add -A; g commit -q -m three
if [ "$( git -C "$REPO" rev-list --count main 2>/dev/null )" != 3 ] || [ "$( git -C "$REPO" branch --list feature | wc -l | tr -d ' ' )" != 1 ]; then
    echo "  FAIL  the fixture repository was not built (want 3 commits on main and a feature branch)"; echo "FAIL whereisnographcheck"; exit 1
fi
SEEDLINE="$( grep -n 'int storeCount()' "$REPO/core/store.cpp" | cut -d: -f1 )"

# run NAME ARGS... -> $TMP/NAME.out / .err / .rc, RIPWIRE_STATS set, no cache
run(){ local name="$1"; shift; ( cd "$REPO" && RIPWIRE_STATS=1 "$BIN" "$REPO" --no-cache "$@" >"$TMP/$name.out" 2>"$TMP/$name.err" ); echo $? >"$TMP/$name.rc"; }
ends(){ grep -c '^\[mem\] phase=graph-end ' "$TMP/$1.err"; }
graphs(){ grep -c '^\[mem\] phase=graph-' "$TMP/$1.err"; }
hits(){ grep -o '<whereis [^>]*>' "$TMP/$1.out" | head -1 | sed -n 's/.* hits="\([0-9]*\)".*/\1/p'; }

# ---- P ----
# kind  selector  extra-args  want-hits(>=1 | 0)
pcase()
{
    local kind="$1" sel="$2" want="$3"; shift 3
    run "p_$kind" --whereis="$sel" "$@"; run "pm_$kind" --whereis="$sel" "$@" --metrics
    local h; h="$( hits "pm_$kind" )"
    if [ "$( cat "$TMP/pm_$kind.rc" )" != 0 ] || [ "$( ends "pm_$kind" )" -ne 1 ] || [ -z "$h" ] \
       || { [ "$want" = hit ] && [ "$h" -lt 1 ]; } || { [ "$want" = zero ] && [ "$h" -ne 0 ]; }; then
        no "P[$kind]: premise: --whereis=$sel --metrics rc $( cat "$TMP/pm_$kind.rc" ), graph-end x$( ends "pm_$kind" ) (want 1), hits=${h:-none} (want $want)"
    elif [ "$( graphs "p_$kind" )" -ne 0 ]; then
        no "P[$kind]: --whereis=$sel printed $( graphs "p_$kind" ) graph phase lines (want 0: it never reads the graph)"
    elif ! cmp -s "$TMP/p_$kind.out" "$TMP/pm_$kind.out" || [ "$( cat "$TMP/p_$kind.rc" )" != "$( cat "$TMP/pm_$kind.rc" )" ]; then
        no "P[$kind]: --whereis=$sel stdout or rc differs between the skipped build and the built graph ($( cmp "$TMP/p_$kind.out" "$TMP/pm_$kind.out" 2>&1 | head -1 ))"
    else
        ok "P[$kind]: --whereis=$sel builds no graph; stdout byte-identical to the graph-built run ($( wc -c <"$TMP/p_$kind.out" | tr -d ' ' ) B, hits=$h)"
    fi
}
pcase class    Store        hit
pcase function storeCount   hit
pcase method   render       hit
pcase macro    STORE_MAX    hit
pcase branch   strandedFix  hit
if grep -q 'on-head="0"' "$TMP/p_branch.out"; then ok "P[branch]: premise: strandedFix lives on the branch only (on-head=\"0\")"; else no "P[branch]: premise: strandedFix is not reported off-HEAD"; fi
pcase history  legacyTotal  any  --with-history
if grep -q '<fate sym="legacyTotal" v="removed"' "$TMP/p_history.out"; then ok "P[history]: premise: the history lane names the commit that removed legacyTotal"; else no "P[history]: premise: no <fate v=\"removed\"> for legacyTotal"; fi
pcase seed     "@core/store.cpp:$SEEDLINE" hit
pcase zero     storeCountt  zero

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
run win --callers=storeCount --whereis=Store
n="$( ends win )"
if [ "$n" -ne 1 ] || ! cmp -s "$TMP/win.out" "$TMP/callers.out"; then
    no "W: --callers --whereis printed graph-end x$n (want 1) and $( cmp -s "$TMP/win.out" "$TMP/callers.out" && echo "answered --callers" || echo "did NOT answer --callers" )"
else
    ok "W: --callers=storeCount --whereis=Store builds the graph and answers --callers (the dispatch winner decides)"
fi

# ---- M ----
run pin --whereis=Store --pin-census="$TMP/census.tsv"
n="$( ends pin )"
if [ "$n" -ne 1 ] || [ ! -s "$TMP/census.tsv" ] || ! cmp -s "$TMP/pin.out" "$TMP/p_class.out"; then
    no "M: --whereis --pin-census printed graph-end x$n (want 1), the census is $( [ -s "$TMP/census.tsv" ] && echo written || echo missing ), stdout $( cmp -s "$TMP/pin.out" "$TMP/p_class.out" && echo same || echo differs )"
else
    ok "M: --whereis --pin-census builds the graph, writes the census, and prints the same --whereis answer"
fi

# ---- S ----
# --whereis and --callers share one parse-cache family (one blob, one snapshot); --for is the other family, so it would
# re-parse and never meet a --whereis snapshot. The fixture's files must be older than the snapshot's mtime guard, or
# no run stores a model or a graph and every arm below is vacuous.
# srun CACHE NAME ARGS... — one cached run; stdout to NAME.out, the snapshot-stats line to NAME.stats
srun(){ local cache="$1" name="$2"; shift 2; ( cd "$REPO" && RIPWIRE_SNAPSHOT_STATS=1 "$BIN" "$REPO" --cache="$cache" "$@" >"$TMP/$name.out" 2>"$TMP/$name.err" ); grep '^ripwire: snapshot-stats ' "$TMP/$name.err" >"$TMP/$name.stats" || : >"$TMP/$name.stats"; }
stat1(){ sed 's/^ripwire: snapshot-stats //' "$TMP/$1.stats"; }
sleep 2
# S1: three --whereis runs on a cold cache store the tree and the model and no graph; --callers then builds its graph
srun "$TMP/s1.bin" s1a --whereis=Store; srun "$TMP/s1.bin" s1b --whereis=Store; srun "$TMP/s1.bin" s1c --whereis=Store
srun "$TMP/s1.bin" s1f --callers=storeCount; srun "$TMP/s1.bin" s1g --callers=storeCount
if ! grep -q 'model=loaded' "$TMP/s1c.stats"; then
    no "S1: VACUOUS: the third --whereis run did not load the stored model, so nothing was stored to poison anything: $( stat1 s1c )"
elif grep -q 'graph=loaded' "$TMP/s1f.stats" || grep -q 'graph_why=ok' "$TMP/s1f.stats"; then
    no "S1: --callers after three --whereis runs loaded a graph from their snapshot (want none stored): $( stat1 s1f )"
elif ! grep -q 'graph=loaded' "$TMP/s1g.stats"; then
    no "S1: the --callers run after it did not store its graph for the next one: $( stat1 s1g )"
elif ! cmp -s "$TMP/s1c.out" "$TMP/p_class.out" || ! cmp -s "$TMP/s1f.out" "$TMP/callers.out" || ! cmp -s "$TMP/s1g.out" "$TMP/callers.out"; then
    no "S1: a cached run's stdout differs from the --no-cache run (whereis $( cmp -s "$TMP/s1c.out" "$TMP/p_class.out" && echo same || echo differs ), callers $( cmp -s "$TMP/s1f.out" "$TMP/callers.out" && echo same || echo differs ), callers warm $( cmp -s "$TMP/s1g.out" "$TMP/callers.out" && echo same || echo differs ))"
else
    ok "S1: --whereis stores no graph; the next --callers builds one ($( stat1 s1f )), the one after loads it, all three answers are the --no-cache bytes"
fi
# S2: a graph that --callers stored and served survives a --whereis run in between
srun "$TMP/s2.bin" s2a --callers=storeCount; srun "$TMP/s2.bin" s2b --callers=storeCount; srun "$TMP/s2.bin" s2c --callers=storeCount
srun "$TMP/s2.bin" s2w --whereis=Store
srun "$TMP/s2.bin" s2d --callers=storeCount
if ! grep -q 'graph=loaded' "$TMP/s2c.stats"; then
    no "S2: VACUOUS: the primed cache never served its graph before the --whereis run: $( stat1 s2c )"
elif ! grep -q 'graph=loaded' "$TMP/s2d.stats"; then
    no "S2: a --whereis run between two --callers runs dropped the stored graph: $( stat1 s2d )"
elif ! cmp -s "$TMP/s2d.out" "$TMP/callers.out" || ! cmp -s "$TMP/s2w.out" "$TMP/p_class.out"; then
    no "S2: stdout differs from the --no-cache run (--callers $( cmp -s "$TMP/s2d.out" "$TMP/callers.out" && echo same || echo differs ), --whereis $( cmp -s "$TMP/s2w.out" "$TMP/p_class.out" && echo same || echo differs ))"
else
    ok "S2: a stored graph survives a --whereis run; the next --callers loads it and prints the --no-cache bytes ($( stat1 s2w ))"
fi

if [ "$fail" -eq 0 ]; then echo "PASS whereisnographcheck"; exit 0; fi
echo "FAIL whereisnographcheck"; exit 1
