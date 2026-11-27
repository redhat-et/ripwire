#!/usr/bin/env bash
# straynographcheck.sh — card STRAY-NO-GRAPH: --stray-content answers from the git object store, and its two modes from the
# ingest (runCrossRef: computeStrayContent takes the root and the ref filter; --abi's computeAbiCheck and --plan's
# computePlan take d.ing as well; none of the three takes d.g), so when --stray-content is the dispatch WINNER and no
# modifier reads the graph before dispatch, main skips buildGraph — the DEPS-NO-GRAPH skip (test/depsnographcheck.sh) and
# WHEREIS-NO-GRAPH's, one verb wider. RIPWIRE_STATS's `[mem] phase=graph-*` lines (src/memstats.h, printed by buildGraph)
# are the probe for "the graph was built". The fixture is a git repository generated here, never committed: two commits on
# main, a branch `lane/stranded` with a commit main never took (and a struct whose shape it changes, for --abi), and a
# branch `lane/landed` whose only commit main already holds.
#
# Arms:
#   P  positive, per shape — bare --stray-content, the =SUBSTR ref filter, --abi, --plan, and the filter that matches no
#      ref (a refusal, rc 1): the call prints no graph phase line, and its stdout and rc are byte-identical to the same call
#      with --metrics (a modifier that reads the graph, so that run still builds it). The premise is counted first: the
#      --metrics run printed graph-end once, with the rc the shape wants, and every answering shape names lane/stranded.
#   N  negative: a graph verb still builds the graph — `--callers=storeCount` prints phase=graph-end exactly once.
#   W  the winner, not the flag: `--callers=storeCount --stray-content` answers --callers (it outranks --stray-content in
#      §B11.4's table), so it must build the graph: graph-end once and --callers's bytes.
#   M  modifiers that read the graph before dispatch keep the build: `--stray-content --pin-census=FILE` prints graph-end
#      once, writes the census, and prints the bare --stray-content answer.
#   S  the warm snapshot (src/warmsnap.h), with --cache, against --callers: a graph-skipping --stray-content run never
#      leaves a graph a later run serves, and never drops one an earlier run stored. Every cached answer is the --no-cache
#      run's bytes. Each S arm checks first that its snapshot stored something, so it cannot pass vacuously.
#
# Red on a binary that builds the graph for --stray-content: every P arm (the graph phase lines are printed).
#
# Usage: bash test/straynographcheck.sh [BIN]      or   RIPWIRE_BIN=./build/ripwire bash test/straynographcheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
case "$BIN" in /*) ;; *) BIN="$PWD/$BIN" ;; esac
echo "straynographcheck: BIN=$BIN  $( "$BIN" --version 2>/dev/null | head -1 )"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ fail=1; printf '  FAIL  %s\n' "$*"; return 0; }

if ! "$BIN" --version 2>/dev/null | grep -q '^ripwire '; then   # status: a binary that cannot run prints no version line, so the grep fails it
    echo "  FAIL  $BIN does not run"; echo "FAIL straynographcheck"; exit 1
fi
command -v git >/dev/null 2>&1 || { echo "  FAIL  git is required (the fixture is a repository)"; echo "FAIL straynographcheck"; exit 1; }
# The warm snapshot lives in ripwire's cache directory; TMPDIR outranks XDG_CACHE_HOME in its ladder, so both point here.
export XDG_CACHE_HOME="$TMP/xdg" TMPDIR="$TMP/tmpdir"; mkdir -p "$XDG_CACHE_HOME" "$TMPDIR"

# ---- the fixture: main, a branch with work main never took, and a branch main already merged ----
REPO="$TMP/repo"; mkdir -p "$REPO/core" "$REPO/ui"
g(){ git -C "$REPO" -c user.name=gate -c user.email=gate@example.invalid -c commit.gpgsign=false "$@" >/dev/null 2>&1; }
g init -q -b main || g init -q
g checkout -q -B main
cat >"$REPO/core/store.h" <<'EOF'
#pragma once
#define STORE_MAX 64
struct Store { int get() const; void put( int v ); int value = 0; };
int storeCount();
EOF
cat >"$REPO/core/store.cpp" <<'EOF'
#include "store.h"
int Store::get() const { return value; }
void Store::put( int v ) { value = v < STORE_MAX ? v : STORE_MAX; }
int storeCount() { Store s; s.put( 3 ); return s.get(); }
EOF
cat >"$REPO/ui/view.cpp" <<'EOF'
#include "../core/store.h"
int drawAll() { Store s; s.put( storeCount() ); return s.get() + storeCount(); }
EOF
g add -A; g commit -q -m one
# a branch whose commit main never takes: a new function, and a field inserted ahead of `value` (an ABI shape change)
g checkout -q -b lane/stranded
printf 'int strandedFix( int x ) { return x + STORE_MAX; }\n' >>"$REPO/core/store.cpp"
sed -i.bak 's/int value = 0;/long epoch = 0; int value = 0;/' "$REPO/core/store.h"; rm -f "$REPO"/core/*.bak
g add -A; g commit -q -m stranded
# a branch whose only commit main merges, so its content is already on HEAD
g checkout -q main
g checkout -q -b lane/landed
printf 'int drawTwice() { return drawAll() * 2; }\n' >>"$REPO/ui/view.cpp"
g add -A; g commit -q -m landed
g checkout -q main
g merge -q --no-edit lane/landed
if [ "$( git -C "$REPO" branch --list 'lane/*' | wc -l | tr -d ' ' )" != 2 ] || ! git -C "$REPO" merge-base --is-ancestor lane/landed main 2>/dev/null \
   || git -C "$REPO" merge-base --is-ancestor lane/stranded main 2>/dev/null; then
    echo "  FAIL  the fixture repository was not built (want lane/landed merged into main and lane/stranded not)"; echo "FAIL straynographcheck"; exit 1
fi

# run NAME ARGS... -> $TMP/NAME.out / .err / .rc, RIPWIRE_STATS set, no cache
run(){ local name="$1"; shift; ( cd "$REPO" && RIPWIRE_STATS=1 "$BIN" "$REPO" --no-cache "$@" >"$TMP/$name.out" 2>"$TMP/$name.err" ); echo $? >"$TMP/$name.rc"; }
ends(){ grep -c '^\[mem\] phase=graph-end ' "$TMP/$1.err"; }
graphs(){ grep -c '^\[mem\] phase=graph-' "$TMP/$1.err"; }

# ---- P ----
# shape  want-rc  names-stranded(yes|no)  args...
pcase()
{
    local shape="$1" wantrc="$2" names="$3"; shift 3
    run "p_$shape" "$@"; run "pm_$shape" "$@" --metrics
    local rc; rc="$( cat "$TMP/pm_$shape.rc" )"
    if [ "$rc" != "$wantrc" ] || [ "$( ends "pm_$shape" )" -ne 1 ] \
       || { [ "$names" = yes ] && ! grep -q 'lane/stranded' "$TMP/pm_$shape.out"; }; then
        no "P[$shape]: premise: $* --metrics rc $rc (want $wantrc), graph-end x$( ends "pm_$shape" ) (want 1), names lane/stranded: $( grep -q 'lane/stranded' "$TMP/pm_$shape.out" && echo yes || echo no ) (want $names)"
    elif [ "$( graphs "p_$shape" )" -ne 0 ]; then
        no "P[$shape]: $* printed $( graphs "p_$shape" ) graph phase lines (want 0: it never reads the graph)"
    elif ! cmp -s "$TMP/p_$shape.out" "$TMP/pm_$shape.out" || ! cmp -s "$TMP/p_$shape.rc" "$TMP/pm_$shape.rc"; then
        no "P[$shape]: $* stdout or rc differs between the skipped build and the built graph ($( cmp "$TMP/p_$shape.out" "$TMP/pm_$shape.out" 2>&1 | head -1 ))"
    else
        ok "P[$shape]: $* builds no graph; stdout and rc byte-identical to the graph-built run ($( wc -c <"$TMP/p_$shape.out" | tr -d ' ' ) B, rc $rc)"
    fi
}
pcase bare    0 yes --stray-content
pcase filter  0 yes --stray-content=stranded
pcase abi     2 yes --stray-content --abi
pcase plan    0 yes --stray-content --plan
pcase nomatch 1 no  --stray-content=nosuchref
if grep -q 'lane/landed' "$TMP/p_filter.out"; then no "P[filter]: premise: --stray-content=stranded lists lane/landed"; else ok "P[filter]: premise: the ref filter narrows the sweep (no lane/landed row)"; fi

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
run win --callers=storeCount --stray-content
n="$( ends win )"
if [ "$n" -ne 1 ] || ! cmp -s "$TMP/win.out" "$TMP/callers.out"; then
    no "W: --callers --stray-content printed graph-end x$n (want 1) and $( cmp -s "$TMP/win.out" "$TMP/callers.out" && echo "answered --callers" || echo "did NOT answer --callers" )"
else
    ok "W: --callers=storeCount --stray-content builds the graph and answers --callers (the dispatch winner decides)"
fi

# ---- M ----
run pin --stray-content --pin-census="$TMP/census.tsv"
n="$( ends pin )"
if [ "$n" -ne 1 ] || [ ! -s "$TMP/census.tsv" ] || ! cmp -s "$TMP/pin.out" "$TMP/p_bare.out"; then
    no "M: --stray-content --pin-census printed graph-end x$n (want 1), the census is $( [ -s "$TMP/census.tsv" ] && echo written || echo missing ), stdout $( cmp -s "$TMP/pin.out" "$TMP/p_bare.out" && echo same || echo differs )"
else
    ok "M: --stray-content --pin-census builds the graph, writes the census, and prints the same --stray-content answer"
fi

# ---- S ----
# The fixture's files must be older than the snapshot's mtime guard, or no run stores a model or a graph and every arm
# below is vacuous.
# srun CACHE NAME ARGS... — one cached run; stdout to NAME.out, the snapshot-stats line to NAME.stats
srun(){ local cache="$1" name="$2"; shift 2; ( cd "$REPO" && RIPWIRE_SNAPSHOT_STATS=1 "$BIN" "$REPO" --cache="$cache" "$@" >"$TMP/$name.out" 2>"$TMP/$name.err" ); grep '^ripwire: snapshot-stats ' "$TMP/$name.err" >"$TMP/$name.stats" || : >"$TMP/$name.stats"; }
stat1(){ sed 's/^ripwire: snapshot-stats //' "$TMP/$1.stats"; }
sleep 2
# S1: three --stray-content runs on a cold cache store the tree and the model and no graph; --callers then builds its graph
srun "$TMP/s1.bin" s1a --stray-content; srun "$TMP/s1.bin" s1b --stray-content; srun "$TMP/s1.bin" s1c --stray-content
srun "$TMP/s1.bin" s1f --callers=storeCount; srun "$TMP/s1.bin" s1g --callers=storeCount
if ! grep -q 'model=loaded' "$TMP/s1c.stats"; then
    no "S1: VACUOUS: the third --stray-content run did not load the stored model, so nothing was stored to poison anything: $( stat1 s1c )"
elif grep -q 'graph=loaded' "$TMP/s1f.stats" || grep -q 'graph_why=ok' "$TMP/s1f.stats"; then
    no "S1: --callers after three --stray-content runs loaded a graph from their snapshot (want none stored): $( stat1 s1f )"
elif ! grep -q 'graph=loaded' "$TMP/s1g.stats"; then
    no "S1: the --callers run after it did not store its graph for the next one: $( stat1 s1g )"
elif ! cmp -s "$TMP/s1c.out" "$TMP/p_bare.out" || ! cmp -s "$TMP/s1f.out" "$TMP/callers.out" || ! cmp -s "$TMP/s1g.out" "$TMP/callers.out"; then
    no "S1: a cached run's stdout differs from the --no-cache run (stray $( cmp -s "$TMP/s1c.out" "$TMP/p_bare.out" && echo same || echo differs ), callers $( cmp -s "$TMP/s1f.out" "$TMP/callers.out" && echo same || echo differs ), callers warm $( cmp -s "$TMP/s1g.out" "$TMP/callers.out" && echo same || echo differs ))"
else
    ok "S1: --stray-content stores no graph; the next --callers builds one ($( stat1 s1f )), the one after loads it, all answers are the --no-cache bytes"
fi
# S2: a graph that --callers stored and served survives a --stray-content run in between
srun "$TMP/s2.bin" s2a --callers=storeCount; srun "$TMP/s2.bin" s2b --callers=storeCount; srun "$TMP/s2.bin" s2c --callers=storeCount
srun "$TMP/s2.bin" s2w --stray-content
srun "$TMP/s2.bin" s2d --callers=storeCount
if ! grep -q 'graph=loaded' "$TMP/s2c.stats"; then
    no "S2: VACUOUS: the primed cache never served its graph before the --stray-content run: $( stat1 s2c )"
elif ! grep -q 'graph=loaded' "$TMP/s2d.stats"; then
    no "S2: a --stray-content run between two --callers runs dropped the stored graph: $( stat1 s2d )"
elif ! cmp -s "$TMP/s2d.out" "$TMP/callers.out" || ! cmp -s "$TMP/s2w.out" "$TMP/p_bare.out"; then
    no "S2: stdout differs from the --no-cache run (--callers $( cmp -s "$TMP/s2d.out" "$TMP/callers.out" && echo same || echo differs ), --stray-content $( cmp -s "$TMP/s2w.out" "$TMP/p_bare.out" && echo same || echo differs ))"
else
    ok "S2: a stored graph survives a --stray-content run; the next --callers loads it and prints the --no-cache bytes ($( stat1 s2w ))"
fi

if [ "$fail" -eq 0 ]; then echo "PASS straynographcheck"; exit 0; fi
echo "FAIL straynographcheck"; exit 1
