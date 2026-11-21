#!/usr/bin/env bash
# namewalkcheck.sh — the two name-keyed walks a C++ map runs enter each name once (lane M1, 2026-11-18).
#
# The incident: a plain map of llvm-project grew resident memory at ~5 GB/s (2.2 GB -> 17 GB in 3 s; one process
# reached 149.7 GB) inside buildClassIdentity -> addRealInheritance -> isNamesakeBaseEdge -> derivesFromName: a depth-12
# breadth-first search over the NAME-keyed chaUp table with no visited set. Every level appended every base of every
# frontier name, duplicates included, so where class names fan out (the same `Impl` / `Base` name defined in many files,
# each with its own bases) the frontier grew as the PRODUCT of the fan-outs. With that bounded, the same map climbed again
# (~60 MB/s, killed past 12 GB) in graph.h's element-of-alias walk: a depth-8 recursion over the NAME-keyed
# typeAliasTargets table, again with no visited set, pushing one element type per PATH. Both now keep a visited set (each
# name enters once, at its shortest distance, so "reached within N steps" is unchanged), and the class walk is memoised
# per outer class name for addRealInheritance's loop (resolve.h NamesakeWalk).
#
# FX (the class walk): 12 layers of 6 class names; every name is defined in 6 files, each definition deriving from ONE
# name of the next layer, so chaUp merges each name to 6 bases. Classes nested in `Outer` (whose bases are layer 1)
# derive from a bare `Iterator` that only OTHER classes nest, so every probe asks "does Outer derive from OtherK?" and the
# answer is no: the walk runs all 12 levels. Unvisited, one probe pushes 6 + 6^2 + ... + 6^12 ~ 2.6e9 names (~40 GB
# of string_views); visited, the 72 layer names.
# FXA (the alias walk): `Root` aliases 16 names, and 6 levels of 16 alias names each alias (one definition per file, 16
# files) the 16 names of the next level; the 7th level's names alias `std::vector<Elem>`. One `m[ 0 ].size()` on a
# `Root m;` reads Root's element types. Unvisited, that is 16^8 ~ 4.3e9 pushes; visited, 112 names and 256 element reads.
#
#   (A) BOUND — the binary finishes FX and FXA under a 1 GiB RSS ceiling (a watchdog polls RSS and kills past it) with
#       well-formed maps. The fixed runs need tens of MB; an unfixed one passes the ceiling in about a second.
#   (B) COUNT — the deterministic counters (RIPWIRE_STATS=1 prints one `[mem]` stderr line per walk) equal the exact
#       values the fixtures imply. FX: probes=35 (4 Walkers x 5 nested `Iterator`s, all "no", plus 3 Peers x 5: every
#       candidate is asked, the "yes" — Mid's — included), walks=2 (one per distinct outer name: Outer, and Outer2 in the
#       TRUE arm), pushes=74 (72 layer names, plus Mid and Base2), namesake=3. FXA: calls=1 pushes=112 elements=256
#       depth_cut=0. A push count is the visited-set bound: removing a set makes it ~1e9 and (A) kills the run first;
#       probes/calls > 0 prove each walk is REACHED, so (A) cannot pass vacuously.
#   (C) TRUE ARM — three classes nested in `Outer2` (which derives from `Mid`) derive from a bare `Iterator` that `Mid`
#       nests: by C++ lookup that names Mid::Iterator, a namesake edge. namesake=3 proves the memo answers "derives"
#       exactly where the walk did.
#   (P) ORDER — the counters are a function of the fixture's CONTENT, not of which file holds which line (the
#       determinism contract covers RIPWIRE_STATS too; CodeRabbit on #693). FXP is FX with outer2.cpp renamed to sort
#       FIRST, so Mid::Iterator is the first candidate in node-id order, not the last: a walk that stopped at the first
#       "yes" asked 23 there, not 35. FXR1/FXR2: `Root` aliases `Plain` and `Ptr` (a std::shared_ptr) in two files,
#       swapped between the two; a `->` through Root visits Root, Plain and Ptr (visits=3) — a walk that stopped
#       mid-level visited 2 when Ptr's file came first. FXW1/FXW2: `Plain* recv;` and `Ptr recv;` in two files, swapped;
#       a name-only `recv->size()` admits both, and each is tested (calls=2) — skipping the test once opaque gave 1.
#   (T) DEPTH CUT — elementTexts stops at kMaxAliasDepth (8 alias steps) and DISCLOSEs a queued alias it left unread
#       (depth_cut= counts the walks cut). FXD: `Root` -> C1 -> ... -> C9 = std::vector<Elem>, so C8's record is
#       unread: depth_cut=1, elements=0. FXN: the chain ends at C8, a struct (no alias records): nothing is left unread,
#       depth_cut=0.
#   (E) SAMPLING — the watchdog itself: a `ps` that fails, or answers empty, while the child still runs is a SAMPLING
#       failure (KILLED=3: the child is killed and reaped and the arm FAILS), never a finish and never the ceiling kill
#       (KILLED=1) the control arm needs. Run with a `ps` shim on PATH; a child that exits normally while the shim
#       fails still finishes (KILLED=0, rc=0).
#   (D) CONTROL (RIPWIRE_NAMEWALK_CONTROL_BIN=<a binary without the fix>) — the control binary on FX and on FXA is
#       KILLED past the same ceiling, which proves each fixture is its blow-up shape; and on FXS (FX's shape at 2 names
#       x 5 layers) and FXAS (FXA's at 3 names x 3 levels), small enough for the unfixed walks, the default map is
#       byte-identical between the control and this binary. Without the variable the control arm is reported as not
#       run; (A) and (B) still gate on their own.
#
#   bash test/namewalkcheck.sh [path/to/ripwire]

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
CONTROL="${RIPWIRE_NAMEWALK_CONTROL_BIN:-}"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
TMP="$( cd "$TMP" && pwd -P )"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "namewalkcheck: BIN=$BIN"

CEIL_KB=$(( 1024 * 1024 ))   # 1 GiB: ~20x the fixed run, ~1/40 of what one unfixed probe needs
WALL_S=120                   # a backstop only; the verdicts below never read time

# gen DIR NAMES LAYERS — the fan-out fixture (see header)
gen(){
    local dir="$1" names="$2" layers="$3" d i k f bases
    mkdir -p "$dir"
    for f in $( seq 0 $(( names - 1 )) ); do
        : >"$dir/layers$f.cpp"
    done
    for d in $( seq 1 "$layers" ); do
        for i in $( seq 0 $(( names - 1 )) ); do
            for f in $( seq 0 $(( names - 1 )) ); do
                if [ "$d" -lt "$layers" ]; then
                    printf 'struct L%d_%d : L%d_%d { int v%d; };\n' "$d" "$i" $(( d + 1 )) "$f" "$f" >>"$dir/layers$f.cpp"
                else
                    printf 'struct L%d_%d { int v%d; };\n' "$d" "$i" "$f" >>"$dir/layers$f.cpp"
                fi
            done
        done
    done
    bases=""
    for i in $( seq 0 $(( names - 1 )) ); do
        bases="$bases${bases:+, }L1_$i"
    done
    {
        printf 'struct Outer : %s\n{\n' "$bases"
        for k in 0 1 2 3; do
            printf '    struct Walker%d : Iterator { int w; };\n' "$k"
        done
        printf '};\n'
    } >"$dir/outer.cpp"
    for k in 0 1 2 3; do
        printf 'struct Other%d\n{\n    struct Iterator { int o; };\n};\n' "$k" >"$dir/other$k.cpp"
    done
    # the TRUE arm: Outer2 derives from Mid, which nests the Iterator its classes name
    {
        printf 'struct Base2 { int b; };\n'
        printf 'struct Mid : Base2\n{\n    struct Iterator { int m; };\n};\n'
        printf 'struct Outer2 : Mid\n{\n'
        for k in 0 1 2; do
            printf '    struct Peer%d : Iterator { int p; };\n' "$k"
        done
        printf '};\n'
    } >"$dir/outer2.cpp"
}

# gena DIR NAMES LEVELS — the alias fan-out fixture (see header)
gena(){
    local dir="$1" names="$2" levels="$3" d i f
    mkdir -p "$dir"
    for f in $( seq 0 $(( names - 1 )) ); do
        {
            printf '#include <vector>\n'
            printf 'typedef A1_%d Root;\n' "$f"
            for d in $( seq 1 "$levels" ); do
                for i in $( seq 0 $(( names - 1 )) ); do
                    if [ "$d" -lt "$levels" ]; then
                        printf 'typedef A%d_%d A%d_%d;\n' $(( d + 1 )) "$f" "$d" "$i"
                    else
                        printf 'typedef std::vector<Elem> A%d_%d;\n' "$d" "$i"
                    fi
                done
            done
        } >"$dir/alias$f.cpp"
    done
    printf 'struct Elem { int size() const { return 1; } };\n' >"$dir/elem.cpp"
    printf 'int use()\n{\n    Root m;\n    return m[ 0 ].size();\n}\n' >"$dir/use.cpp"
    printf 'int useArrow( Root* p )\n{\n    return p->size();\n}\n' >>"$dir/use.cpp"
}

# capped OUT ERR cmd... — run under the RSS ceiling; sets RC, PEAK_KB, KILLED (0 finished, 1 past the ceiling, 2 wall,
# 3 the RSS sample failed while the child ran — the ceiling was not enforced, so the run is stopped and the arm fails)
capped(){
    local out="$1" err="$2" pid rss st t0
    shift 2
    "$@" >"$out" 2>"$err" &
    pid=$!
    PEAK_KB=0; KILLED=0; t0=$SECONDS
    while kill -0 "$pid" 2>/dev/null; do
        st="$( ps -o stat= -p "$pid" 2>/dev/null )" || st=''
        case "$st" in Z*) break ;; esac
        rss="$( ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ' )" || rss=''
        if [ -z "$st" ] || ! [ "$rss" -ge 0 ] 2>/dev/null; then
            # an empty or failed sample: either the child exited between kill -0 and ps (then it is gone and kill -0 now
            # fails), or ps failed with the child still running — a run the watchdog cannot see, so it is not let finish
            kill -0 "$pid" 2>/dev/null || break
            kill -9 "$pid" 2>/dev/null; KILLED=3; break
        fi
        [ "$rss" -gt "$PEAK_KB" ] && PEAK_KB="$rss"
        if [ "$rss" -gt "$CEIL_KB" ]; then kill -9 "$pid" 2>/dev/null; KILLED=1; break; fi
        if [ $(( SECONDS - t0 )) -gt "$WALL_S" ]; then kill -9 "$pid" 2>/dev/null; KILLED=2; break; fi
        sleep 0.05
    done
    wait "$pid" 2>/dev/null; RC=$?
}
killedWhy(){ case "$1" in 0) echo finished ;; 1) echo "killed past the ceiling" ;; 2) echo "killed at the wall backstop" ;; 3) echo "RSS SAMPLING FAILED (ps), killed — the ceiling was not enforced" ;; *) echo "killed=$1" ;; esac; }

# genchain DIR STEPS TAIL — Root -> C1 -> ... -> C<STEPS>; TAIL=alias makes C<STEPS> alias std::vector<Elem>, TAIL=struct
# makes it a struct (no alias records)
genchain(){
    local dir="$1" steps="$2" tail="$3" k
    mkdir -p "$dir"
    {
        printf '#include <vector>\n'
        if [ "$tail" = alias ]; then printf 'typedef std::vector<Elem> C%d;\n' "$steps"; else printf 'struct C%d { int c; };\n' "$steps"; fi
        for k in $( seq $(( steps - 1 )) -1 1 ); do
            printf 'typedef C%d C%d;\n' $(( k + 1 )) "$k"
        done
        printf 'typedef C1 Root;\n'
    } >"$dir/chain.cpp"
    printf 'struct Elem { int size() const { return 1; } };\n' >"$dir/elem.cpp"
    printf 'int use()\n{\n    Root m;\n    return m[ 0 ].size();\n}\n' >"$dir/use.cpp"
}

# genperm DIR KIND FIRST SECOND — two one-line files a.cpp (FIRST) and b.cpp (SECOND) beside the shared types and the call
genperm(){
    local dir="$1" kind="$2"
    mkdir -p "$dir"
    printf '#include <memory>\nstruct X { int size() const { return 1; } };\ntypedef std::shared_ptr<X> Ptr;\nstruct Plain { int size() const { return 2; } };\n' >"$dir/types.cpp"
    printf '%s\n' "$3" >"$dir/a.cpp"
    printf '%s\n' "$4" >"$dir/b.cpp"
    if [ "$kind" = alias ]; then
        printf 'int useArrow( Root* p )\n{\n    return p->size();\n}\n' >"$dir/use.cpp"
    else
        printf 'int g()\n{\n    return recv->size();\n}\n' >"$dir/use.cpp"
    fi
}

FX="$TMP/fx"; gen "$FX" 6 12
FXS="$TMP/fxs"; gen "$FXS" 2 5
FXA="$TMP/fxa"; gena "$FXA" 16 7
FXAS="$TMP/fxas"; gena "$FXAS" 3 3
FXP="$TMP/fxp"; cp -R "$FX" "$FXP"; mv "$FXP/outer2.cpp" "$FXP/a_outer2.cpp"   # the "yes" candidate's file sorts first
FXD="$TMP/fxd"; genchain "$FXD" 9 alias
FXN="$TMP/fxn"; genchain "$FXN" 8 struct
genperm "$TMP/fxr1" alias 'typedef Plain Root;' 'typedef Ptr Root;'
genperm "$TMP/fxr2" alias 'typedef Ptr Root;' 'typedef Plain Root;'
genperm "$TMP/fxw1" written 'Plain* recv;' 'Ptr recv;'
genperm "$TMP/fxw2" written 'Ptr recv;' 'Plain* recv;'

# ── (A) BOUND + (B) COUNT + (C) TRUE ARM ────────────────────────────────────────────────────────────────────────
# arm NAME DIR FILES COUNTER WANT
arm(){
    local name="$1" dir="$2" files="$3" counter="$4" want="$5" line
    capped "$TMP/$name.xml" "$TMP/$name.err" env RIPWIRE_STATS=1 "$BIN" "$dir" --no-cache
    if [ "$KILLED" -eq 0 ] && [ "$RC" -eq 0 ]; then
        ok "(A) $name map finished under the 1 GiB ceiling (rc=0, peak ${PEAK_KB} KB)"
    else
        no "(A) $name map did not finish under the ceiling: rc=$RC, $( killedWhy "$KILLED" ), peak=${PEAK_KB} KB"
    fi
    if grep -q "files=$files " "$TMP/$name.xml" 2>/dev/null && grep -q '<r schema="ripwire.map/v1"' "$TMP/$name.xml" \
        && { ! command -v xmllint >/dev/null || xmllint --noout "$TMP/$name.xml" 2>/dev/null; }; then
        ok "(A) $name map is well-formed and indexes all $files fixture files"
    else
        no "(A) $name map is empty or malformed ($( head -c 200 "$TMP/$name.xml" ))"
    fi
    line="$( grep -F "[mem] $counter " "$TMP/$name.err" )"
    if [ "$line" = "$want" ]; then
        ok "(B) $name counter is exact: $line"
    else
        no "(B) $name counter: want '$want', got '${line:-<no $counter line>}'"
    fi
}
arm FX  "$FX"  12 cha_walk   '[mem] cha_walk probes=35 walks=2 pushes=74 namesake=3'
arm FXA "$FXA" 18 alias_walk '[mem] alias_walk calls=1 pushes=112 elements=256 depth_cut=0'
# exact NAME ERRFILE COUNTER WANT — one more counter line from a run arm() already made
exact(){
    local line
    line="$( grep -F "[mem] $3 " "$2" )"
    if [ "$line" = "$4" ]; then ok "$1 counter is exact: $line"; else no "$1 counter: want '$4', got '${line:-<no $3 line>}'"; fi
}
exact "(B) FXA" "$TMP/FXA.err" arrow_walk '[mem] arrow_walk calls=1 visits=113'

# ── (P) ORDER + (T) DEPTH CUT ───────────────────────────────────────────────────────────────────────────────────
arm FXP  "$FXP"       12 cha_walk   '[mem] cha_walk probes=35 walks=2 pushes=74 namesake=3'
arm FXR1 "$TMP/fxr1"  4  arrow_walk '[mem] arrow_walk calls=1 visits=3'
arm FXR2 "$TMP/fxr2"  4  arrow_walk '[mem] arrow_walk calls=1 visits=3'
arm FXW1 "$TMP/fxw1"  4  arrow_walk '[mem] arrow_walk calls=2 visits=2'
arm FXW2 "$TMP/fxw2"  4  arrow_walk '[mem] arrow_walk calls=2 visits=2'
arm FXD  "$FXD"       3  alias_walk '[mem] alias_walk calls=1 pushes=8 elements=0 depth_cut=1'
arm FXN  "$FXN"       3  alias_walk '[mem] alias_walk calls=1 pushes=8 elements=0 depth_cut=0'

# ── (E) SAMPLING ────────────────────────────────────────────────────────────────────────────────────────────────
mkdir -p "$TMP/psfail" "$TMP/psempty" "$TMP/psslow"
printf '#!/bin/sh\nexit 1\n' >"$TMP/psfail/ps"
printf '#!/bin/sh\nexit 0\n' >"$TMP/psempty/ps"
printf '#!/bin/sh\nsleep 1\nexit 1\n' >"$TMP/psslow/ps"
chmod +x "$TMP/psfail/ps" "$TMP/psempty/ps" "$TMP/psslow/ps"
for shim in psfail psempty; do
    t0=$SECONDS
    PATH="$TMP/$shim:$PATH" capped "$TMP/e_$shim.out" "$TMP/e_$shim.err" sleep 30
    if [ "$KILLED" -eq 3 ] && [ $(( SECONDS - t0 )) -lt 20 ] && ! kill -0 "$!" 2>/dev/null; then
        ok "(E) a $shim sample on a running child is a sampling failure: $( killedWhy "$KILLED" ) (rc=$RC), not a finish or a ceiling kill"
    else
        no "(E) a $shim sample on a running child: want KILLED=3 within 20 s, got $( killedWhy "$KILLED" ) after $(( SECONDS - t0 )) s"
    fi
done
PATH="$TMP/psslow:$PATH" capped "$TMP/e_slow.out" "$TMP/e_slow.err" sleep 0.1
if [ "$KILLED" -eq 0 ] && [ "$RC" -eq 0 ]; then
    ok "(E) a child that exits normally while ps fails still finishes (rc=0, $( killedWhy "$KILLED" ))"
else
    no "(E) a child that exited normally while ps failed: want finished rc=0, got rc=$RC, $( killedWhy "$KILLED" )"
fi

# ── (D) CONTROL ─────────────────────────────────────────────────────────────────────────────────────────────────
if [ -n "$CONTROL" ]; then
    [ -x "$CONTROL" ] || { no "(D) RIPWIRE_NAMEWALK_CONTROL_BIN=$CONTROL is not executable"; CONTROL=""; }
fi
if [ -n "$CONTROL" ]; then
    for pair in "FX:$FX" "FXA:$FXA"; do
        name="${pair%%:*}"; dir="${pair#*:}"
        capped "$TMP/c$name.xml" "$TMP/c$name.err" "$CONTROL" "$dir" --no-cache
        if [ "$KILLED" -eq 1 ]; then
            ok "(D) control binary is KILLED past the 1 GiB ceiling on $name (peak ${PEAK_KB} KB): $name is the blow-up shape"
        else
            no "(D) control binary was not killed past the ceiling on $name (rc=$RC, $( killedWhy "$KILLED" ), peak=${PEAK_KB} KB): $name no longer separates"
        fi
    done
    for pair in "FXS:$FXS" "FXAS:$FXAS"; do
        name="${pair%%:*}"; dir="${pair#*:}"
        capped "$TMP/s_ctl$name.xml" "$TMP/s_ctl$name.err" "$CONTROL" "$dir" --no-cache; ctl_killed=$KILLED ctl_rc=$RC
        capped "$TMP/s_bin$name.xml" "$TMP/s_bin$name.err" "$BIN" "$dir" --no-cache; bin_killed=$KILLED bin_rc=$RC
        if [ "$ctl_killed$bin_killed$ctl_rc$bin_rc" = "0000" ] && [ -s "$TMP/s_bin$name.xml" ] && cmp -s "$TMP/s_ctl$name.xml" "$TMP/s_bin$name.xml"; then
            ok "(D) $name default map is byte-identical between the control and this binary ($( wc -c <"$TMP/s_bin$name.xml" | tr -d ' ' ) B)"
        else
            no "(D) $name maps differ or failed (control rc=$ctl_rc killed=$ctl_killed, bin rc=$bin_rc killed=$bin_killed)"
        fi
    done
else
    echo "  NOTE  (D) control arm not run: set RIPWIRE_NAMEWALK_CONTROL_BIN to a binary without the fix"
fi

[ "$fail" -eq 0 ] && echo "namewalkcheck: PASS" || echo "namewalkcheck: FAIL"
exit "$fail"
