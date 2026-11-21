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
#       values the fixtures imply. FX: probes=35 (4 Walkers x 5 nested `Iterator`s, all "no", plus 3 Peers x 5, the
#       fifth — Mid's, last in id order — the "yes" that stops any_of), walks=2 (one per distinct outer name: Outer, and
#       Outer2 in the TRUE arm), pushes=74 (72 layer names, plus Mid and Base2), namesake=3. FXA: calls=1 pushes=112
#       elements=256. A push count is the visited-set bound: removing a set makes it ~1e9 and (A) kills the run first;
#       probes/calls > 0 prove each walk is REACHED, so (A) cannot pass vacuously.
#   (C) TRUE ARM — three classes nested in `Outer2` (which derives from `Mid`) derive from a bare `Iterator` that `Mid`
#       nests: by C++ lookup that names Mid::Iterator, a namesake edge. namesake=3 proves the memo answers "derives"
#       exactly where the walk did.
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

# capped OUT ERR cmd... — run under the RSS ceiling; sets RC, PEAK_KB, KILLED (0 finished, 1 past the ceiling, 2 wall)
capped(){
    local out="$1" err="$2" pid rss st t0
    shift 2
    "$@" >"$out" 2>"$err" &
    pid=$!
    PEAK_KB=0; KILLED=0; t0=$SECONDS
    while kill -0 "$pid" 2>/dev/null; do
        st="$( ps -o stat= -p "$pid" 2>/dev/null )"
        case "$st" in Z*|'') break ;; esac
        rss="$( ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ' )"; rss="${rss:-0}"
        [ "$rss" -gt "$PEAK_KB" ] && PEAK_KB="$rss"
        if [ "$rss" -gt "$CEIL_KB" ]; then kill -9 "$pid" 2>/dev/null; KILLED=1; break; fi
        if [ $(( SECONDS - t0 )) -gt "$WALL_S" ]; then kill -9 "$pid" 2>/dev/null; KILLED=2; break; fi
        sleep 0.05
    done
    wait "$pid" 2>/dev/null; RC=$?
}

FX="$TMP/fx"; gen "$FX" 6 12
FXS="$TMP/fxs"; gen "$FXS" 2 5
FXA="$TMP/fxa"; gena "$FXA" 16 7
FXAS="$TMP/fxas"; gena "$FXAS" 3 3

# ── (A) BOUND + (B) COUNT + (C) TRUE ARM ────────────────────────────────────────────────────────────────────────
# arm NAME DIR FILES COUNTER WANT
arm(){
    local name="$1" dir="$2" files="$3" counter="$4" want="$5" line
    capped "$TMP/$name.xml" "$TMP/$name.err" env RIPWIRE_STATS=1 "$BIN" "$dir" --no-cache
    if [ "$KILLED" -eq 0 ] && [ "$RC" -eq 0 ]; then
        ok "(A) $name map finished under the 1 GiB ceiling (rc=0, peak ${PEAK_KB} KB)"
    else
        no "(A) $name map did not finish under the ceiling: rc=$RC killed=$KILLED peak=${PEAK_KB} KB — a walk is unbounded again"
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
arm FXA "$FXA" 18 alias_walk '[mem] alias_walk calls=1 pushes=112 elements=256'
line="$( grep -F '[mem] arrow_walk ' "$TMP/FXA.err" )"; want='[mem] arrow_walk calls=1 visits=113'
if [ "$line" = "$want" ]; then ok "(B) FXA counter is exact: $line"; else no "(B) FXA counter: want '$want', got '${line:-<no arrow_walk line>}'"; fi

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
            no "(D) control binary was not killed on $name (rc=$RC killed=$KILLED peak=${PEAK_KB} KB): $name no longer separates"
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
