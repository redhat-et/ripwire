#!/usr/bin/env bash
# memstatscheck.sh — RIPWIRE_STATS's memory lines (src/memstats.h, card M0 MEM-STATS) and the graph side tables
# they measure (card G1, reports mem-audit-fable-1111). The fixture is GENERATED here, never committed: it is large enough
# to show an over-reserve, and a whole-repo run must not see it.
#
# Arms:
#   Q  quiet: without RIPWIRE_STATS no `[mem]` line reaches stderr, and stdout is byte-identical with and without it
#      (the readings are env-gated stderr only).
#   N  the premise: each phase line appears exactly once with --cache= (pool-join, save-cache, model, graph-tables,
#      graph-resolved, graph-end), and the tables line shows every one of its five per-kind tables NON-EMPTY on this
#      fixture (C++ typed and untyped locals, ES imports and a lexical shadow of one). It counts what it saw and fails on
#      fewer than five: a table the fixture never fills would let R pass on an empty table's four buckets.
#   B  the binding row (MEM-B1 BIND-INTERN): the bindings family line reports row_b=36, nine u32 on every ABI (three pool ids for
#      var / importedName / typeName). A std::string member back in Binding reads 96 (libc++) or 120 (libstdc++) and fails; the
#      premise (N's >= 50000 bindings, the line seen once) is counted first.
#   P  the reference row (MEM-R1a): the references family line reports row_b=64, one row per 64 B line on every ABI (four pool ids,
#      no std::string; model.h's static_assert pins it at compile time, this arm on the binary that ran). The premise (the line seen
#      once, >= 50000 references) is counted first.
#   C  the cold block (MEM-R1b): the textpool line reports the reference cold block at 20 B, five pool ids on every ABI (it was five
#      std::string, 120 B on libc++ in a 128 B malloc bucket). The premise (the line seen once, >= 1 block on this fixture) first.
#   R  reserve by kind (G1a), machine-free: each table's bucket count is at most 8 x max( size, 16 ). A table reserved for
#      every binding while it holds one kind (the pre-G1a `reserve( ing.bindings.size() )`) has 2^k buckets for ~100 K
#      bindings and fails here; a reserve by its own kind's count stays within 2.5 x of its distinct keys.
#   E  the edge table's reserve (CodeRabbit 4544551960): on a generated corpus of 4800 empty C functions (symbols, no
#      references) the resolve loop adds no edge, so the edge accumulator holds at most 8 x max( references, 16 ) buckets
#      at graph-tables. Red before: reserve( symbols ) gave 8192 buckets for 0 references. Premise: the symbols family
#      reads >= 4000 and references reads 0, counted first.
#   F  the plateau (macOS: phys_footprint): graph-tables cur_mib minus model cur_mib stays under kPlateauMib on the
#      fixture (red on the whole-family reserve: 23.8 MiB; 16.7 by kind). Linux prints the reading as INFO (glibc's RSS moves with its own thresholds; the bound is the M2's).
#      A reading printed `unavailable` is never a plateau: macOS FAILS (its reader always answers), elsewhere F is SKIP.
#   S  the save peak (macOS: phys_footprint; card C1 SAVE-STREAM): on a second, larger generated fixture (240 C++ files, a ~50 MiB
#      lean blob) the cache write lifts the lifetime peak by at most a quarter of the blob over the parse's own (save-cache peak_mib
#      minus pool-join peak_mib). Building the whole blob in one doubling std::string lifts it by 33 MiB on a 50 MiB blob (red,
#      M2 11-11); the windowed writer by 0. The parse's peak sits ~68 MiB above the pool join's cur_mib here, so that pair can not
#      bound the save on a fixture a gate can afford. The premise (the blob is at least 40 MiB, both lines seen once) is counted first.
#      Linux prints INFO.
#   U  unknown is not zero (CodeRabbit 4543019678): with RIPWIRE_TEST_MEMSTATS_UNREAD=1 (src/memstats.h's seam: every reading
#      unknown, the shape of a platform with no reader) each of the six phase lines prints cur_mib=unavailable
#      peak_mib=unavailable and none prints a number, and F's own verdict on that run is "unavailable", not a plateau. It counts
#      the phase lines it saw and FAILS on fewer than six (red before the fix: the lines printed 0.0-free numbers and the seam was
#      ignored, so a reader's 0 would have printed as 0.0 MiB).
#
# N, E and U read the graph phases, so they run --callers (a graph verb): --deps builds no graph since DEPS-NO-GRAPH
# (test/depsnographcheck.sh). Q and S read only the ingest's lines and keep --deps.
#
# Usage: bash test/memstatscheck.sh [BIN]
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
case "$BIN" in /*) ;; *) BIN="$PWD/$BIN" ;; esac
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ fail=1; printf '  FAIL  %s\n' "$*"; return 0; }
kPlateauMib=20   # M2 2026-11-11, plain build, 3 runs each: 23.8-23.9 MiB with reserve( ing.bindings.size() ), 16.6-16.8 by kind

if ! "$BIN" --version 2>/dev/null | grep -q '^ripwire '; then
    echo "  FAIL  $BIN does not run"; echo "FAIL memstatscheck"; exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
    echo "  SKIP  python3 not found (the fixture generator)"; echo "PASS memstatscheck"; exit 0
fi

# ---- the fixture: 40 C++ files x 50 functions x 25 locals (one typed, one untyped each) ~ 100 K bindings, plus a few ES
#      modules: an import, its shadow, an export ----
REPO="$TMP/repo"; mkdir -p "$REPO/cpp" "$REPO/web"
python3 - "$REPO" <<'PY'
import sys, os
root = sys.argv[1]
for f in range( 40 ):
    out = [ f"struct Widget{f} {{ void run(); int size; }};" ]
    for fn in range( 50 ):
        body = []
        for v in range( 25 ):
            body.append( f"    Widget{f} w{v}; w{v}.run(); int n{v} = {v};" )
        out.append( f"void fn_{f}_{fn}()\n{{\n" + "\n".join( body ) + "\n}" )
    open( os.path.join( root, "cpp", f"f{f}.cpp" ), "w" ).write( "\n".join( out ) + "\n" )
for m in range( 12 ):
    open( os.path.join( root, "web", f"lib{m}.js" ), "w" ).write( f"export function helper{m}() {{ return {m}; }}\n" )
    open( os.path.join( root, "web", f"use{m}.js" ), "w" ).write(
        f"import {{ helper{m} }} from './lib{m}.js';\nexport function main{m}() {{ return helper{m}(); }}\n"
        f"function inner{m}() {{ const helper{m} = 1; return helper{m}; }}\n" )
PY

# ---- Q ----
( cd "$REPO" && "$BIN" "$REPO" --no-cache --deps >"$TMP/q.out" 2>"$TMP/q.err" ); rcq=$?
( cd "$REPO" && RIPWIRE_STATS=1 "$BIN" "$REPO" --no-cache --deps >"$TMP/s.out" 2>"$TMP/s.err" ); rcs=$?
if [ "$rcq" -ne 0 ] || [ "$rcs" -ne 0 ]; then
    no "Q: --deps exited $rcq (plain) / $rcs (RIPWIRE_STATS)"
elif grep -q '^\[mem\]' "$TMP/q.err"; then
    no "Q: a [mem] line reached stderr without RIPWIRE_STATS"
elif ! cmp -s "$TMP/q.out" "$TMP/s.out"; then
    no "Q: stdout differs with RIPWIRE_STATS set"
else
    ok "Q: env-gated: no [mem] line unset, stdout byte-identical set ($( wc -c <"$TMP/q.out" | tr -d ' ' ) B)"
fi

# ---- N ----
( cd "$REPO" && RIPWIRE_STATS=1 "$BIN" "$REPO" --cache="$TMP/c.bin" --callers=fn_0_0 >/dev/null 2>"$TMP/n.err" ); rcn=$?
[ "$rcn" -eq 0 ] || no "N: the --cache= run exited $rcn"
seen=0
for phase in pool-join save-cache model graph-tables graph-resolved graph-end; do
    n="$( grep -c "^\[mem\] phase=$phase " "$TMP/n.err" )"
    if [ "$n" -eq 1 ]; then seen=$(( seen + 1 )); else no "N: phase=$phase printed $n times (want 1)"; fi
done
[ "$seen" -eq 6 ] && ok "N: six phase lines, once each"
tables="$( grep '^\[mem\] tables ' "$TMP/n.err" | head -1 )"
filled=0; total=0
for pair in $( printf '%s\n' "$tables" | tr ' ' '\n' | grep -E '^(varType|localNameSet|localShadowSpans|jsImportTargets|jsShadows)=' ); do
    total=$(( total + 1 ))
    size="${pair#*=}"; size="${size%/*}"
    [ "$size" -ge 1 ] && filled=$(( filled + 1 ))
done
if [ "$total" -ne 5 ] || [ "$filled" -ne 5 ]; then
    no "N: the tables line shows $total tables, $filled non-empty (want 5 and 5): ${tables:-<none>}"
else
    ok "N: five per-kind tables seen, all non-empty"
fi
bindings="$( grep '^\[mem\] family bindings ' "$TMP/n.err" | sed -E 's/.* size=([0-9]+) .*/\1/' )"
if [ "${bindings:-0}" -lt 50000 ]; then
    no "N: the fixture holds ${bindings:-0} bindings (want >= 50000, or R cannot tell a whole-family reserve)"
fi

# ---- B ----
lines="$( grep -c '^\[mem\] family bindings ' "$TMP/n.err" )"
rowb="$( grep '^\[mem\] family bindings ' "$TMP/n.err" | sed -E 's/.* row_b=([0-9]+) .*/\1/' )"
if [ "$lines" -ne 1 ] || [ "${bindings:-0}" -lt 50000 ]; then
    no "B: premise: the bindings family line printed $lines times (want 1), ${bindings:-0} bindings (want >= 50000)"
elif [ "$rowb" != 36 ]; then
    no "B: a Binding row is ${rowb:-?} B (want 36: var / importedName / typeName as 4 B pool ids, model.h MEM-B1)"
else
    ok "B: a Binding row is 36 B over $bindings bindings"
fi

# ---- P ----
plines="$( grep -c '^\[mem\] family references ' "$TMP/n.err" )"
prefs="$( grep '^\[mem\] family references ' "$TMP/n.err" | sed -E 's/.* size=([0-9]+) .*/\1/' )"
prow="$( grep '^\[mem\] family references ' "$TMP/n.err" | sed -E 's/.* row_b=([0-9]+) .*/\1/' )"
if [ "$plines" -ne 1 ] || [ "${prefs:-0}" -lt 50000 ]; then
    no "P: premise: the references family line printed $plines times (want 1), ${prefs:-0} references (want >= 50000)"
elif [ "$prow" != 64 ]; then
    no "P: a Reference row is ${prow:-?} B (want 64: memberRoot a pool id, litAt a u32; model.h MEM-REF-SHRINK)"
else
    ok "P: a Reference row is 64 B over $prefs references"
fi

# ---- C ----
clines="$( grep -c '^\[mem\] textpool ' "$TMP/n.err" )"
cblocks="$( grep '^\[mem\] textpool ' "$TMP/n.err" | sed -E 's/.* cold blocks=([0-9]+) .*/\1/' )"
cbytes="$( grep '^\[mem\] textpool ' "$TMP/n.err" | sed -E 's/.* \(([0-9]+) B each\)$/\1/' )"
if [ "$clines" -ne 1 ] || [ "${cblocks:-0}" -lt 1 ]; then
    no "C: premise: the textpool line printed $clines times (want 1), ${cblocks:-0} cold blocks (want >= 1)"
elif [ "$cbytes" != 20 ]; then
    no "C: a reference cold block is ${cbytes:-?} B (want 20: five pool ids, model.h RefColdText)"
else
    ok "C: a reference cold block is 20 B ($cblocks blocks)"
fi

# ---- R ----
bad=0
for pair in $( printf '%s\n' "$tables" | tr ' ' '\n' | grep -E '^(varType|localNameSet|localShadowSpans|jsImportTargets|jsShadows)=' ); do
    name="${pair%%=*}"; v="${pair#*=}"; size="${v%/*}"; buckets="${v#*/}"
    floor=$size; [ "$floor" -lt 16 ] && floor=16
    if [ "$buckets" -gt $(( 8 * floor )) ]; then
        no "R: $name holds $size entries in $buckets buckets (> 8 x max( size, 16 ); bindings=$bindings)"; bad=1
    fi
done
[ "$total" -eq 5 ] && [ "$bad" -eq 0 ] && ok "R: every per-kind table within 8 x its entries ($tables)"

# ---- E ----
EREPO="$TMP/erepo"; mkdir -p "$EREPO"
python3 - "$EREPO" <<'PY'
import sys, os
for f in range( 8 ):
    open( os.path.join( sys.argv[1], f"t{f}.c" ), "w" ).write( "".join( f"void f{f}_{i}(void) {{}}\n" for i in range( 600 ) ) )
PY
( cd "$EREPO" && RIPWIRE_STATS=1 "$BIN" "$EREPO" --no-cache --callers=f0_0 >/dev/null 2>"$TMP/e.err" ) || no "E: the --callers run exited non-zero"
esyms="$( grep '^\[mem\] family symbols ' "$TMP/e.err" | sed -E 's/.* size=([0-9]+) .*/\1/' )"
erefs="$( grep '^\[mem\] family references ' "$TMP/e.err" | sed -E 's/.* size=([0-9]+) .*/\1/' )"
eacc="$( grep '^\[mem\] tables ' "$TMP/e.err" | tr ' ' '\n' | sed -n 's/^acc=[0-9]*\///p' | head -1 )"
if [ "${esyms:-0}" -lt 4000 ] || [ "${erefs:-x}" != "0" ] || [ -z "$eacc" ]; then
    no "E: premise: symbols=${esyms:-?} references=${erefs:-?} acc buckets=${eacc:-?} (want >= 4000, 0, a reading)"
else
    ok "E: premise: $esyms symbols, 0 references"
    if [ "$eacc" -le 128 ]; then ok "E: the edge accumulator reserves $eacc buckets for 0 references (<= 8 x 16)"
    else no "E: the edge accumulator reserves $eacc buckets for $esyms symbols and 0 references (> 8 x 16: reserved by symbols)"; fi
fi

# ---- F ----
# plateau ERRFILE -> "ok <plateau> <model>" | "unavailable" (either reading printed `unavailable`) | "missing" (no such lines)
plateau(){
    local model built
    model="$( grep '^\[mem\] phase=model ' "$1" | sed -E 's/.* cur_mib=([^ ]+) .*/\1/' )"
    built="$( grep '^\[mem\] phase=graph-tables ' "$1" | sed -E 's/.* cur_mib=([^ ]+) .*/\1/' )"
    if [ -z "$model" ] || [ -z "$built" ]; then echo missing
    elif [ "$model" = unavailable ] || [ "$built" = unavailable ]; then echo unavailable
    else echo "ok $( awk -v a="$built" -v b="$model" 'BEGIN{ printf "%.1f", a - b }' ) $model"; fi
}
v="$( plateau "$TMP/n.err" )"
case "$v" in
    missing) no "F: no model / graph-tables reading" ;;
    unavailable)
        if [ "$( uname -s )" = Darwin ]; then no "F: the footprint reads unavailable on macOS (os::mem_footprint)"
        else echo "  SKIP  F: the footprint reads unavailable on this platform: no plateau"; fi ;;
    *)
        set -- $v; plateau="$2"; model="$3"
        case "$( uname -s )" in
            Darwin)
                if awk -v p="$plateau" -v k="$kPlateauMib" 'BEGIN{ exit !( p <= k ) }'; then
                    ok "F: tables plateau $plateau MiB over the model ($model MiB) <= $kPlateauMib"
                else
                    no "F: tables plateau $plateau MiB over the model ($model MiB) > $kPlateauMib"
                fi ;;
            *) echo "  INFO  F: tables plateau $plateau MiB over the model ($model MiB); bound is macOS-only" ;;
        esac ;;
esac

# ---- S ----
REPO2="$TMP/repo2"; mkdir -p "$REPO2/cpp"
python3 - "$REPO2" <<'PY2'
import sys, os
root = sys.argv[1]
for f in range( 240 ):
    out = [ f"struct Widget{f} {{ void run(); int size; }};" ]
    for fn in range( 50 ):
        body = [ f"    Widget{f} w{v}; w{v}.run(); int n{v} = {v};" for v in range( 25 ) ]
        out.append( f"void fn_{f}_{fn}()\n{{\n" + "\n".join( body ) + "\n}" )
    open( os.path.join( root, "cpp", f"f{f}.cpp" ), "w" ).write( "\n".join( out ) + "\n" )
PY2
( cd "$REPO2" && RIPWIRE_STATS=1 "$BIN" "$REPO2" --cache="$TMP/s.bin" --deps >/dev/null 2>"$TMP/s2.err" ); rcs2=$?
blob=$( wc -c <"$TMP/s.bin" 2>/dev/null | tr -d ' ' ); blob=${blob:-0}
njoin="$( grep -c '^\[mem\] phase=pool-join ' "$TMP/s2.err" )"; nsave="$( grep -c '^\[mem\] phase=save-cache ' "$TMP/s2.err" )"
joinpk="$( grep '^\[mem\] phase=pool-join ' "$TMP/s2.err" | sed -E 's/.* peak_mib=([^ ]+)$/\1/' )"
savepk="$( grep '^\[mem\] phase=save-cache ' "$TMP/s2.err" | sed -E 's/.* peak_mib=([^ ]+)$/\1/' )"
rm -f "$TMP/s.bin"
if [ "$rcs2" -ne 0 ] || [ "$njoin" -ne 1 ] || [ "$nsave" -ne 1 ] || [ "$blob" -lt $(( 40 * 1048576 )) ]; then
    no "S: premise: rc=$rcs2, pool-join x$njoin, save-cache x$nsave (want 1 each), blob $blob B (want >= 40 MiB)"
elif [ "$joinpk" = unavailable ] || [ "$savepk" = unavailable ]; then
    if [ "$( uname -s )" = Darwin ]; then no "S: the footprint reads unavailable on macOS"; else echo "  SKIP  S: the footprint reads unavailable on this platform"; fi
else
    rise="$( awk -v a="$savepk" -v b="$joinpk" 'BEGIN{ printf "%.1f", a - b }' )"
    cap="$( awk -v n="$blob" 'BEGIN{ printf "%.1f", n / 1048576 / 4 }' )"
    case "$( uname -s )" in
        Darwin)
            if awk -v r="$rise" -v c="$cap" 'BEGIN{ exit !( r <= c ) }'; then
                ok "S: the cache write lifts the peak $rise MiB over the parse's $joinpk (<= $cap: a quarter of the $(( blob / 1048576 )) MiB blob)"
            else
                no "S: the cache write lifts the peak $rise MiB over the parse's $joinpk (> $cap: a quarter of the $(( blob / 1048576 )) MiB blob; the blob is built in memory?)"
            fi ;;
        *) echo "  INFO  S: the cache write lifts the peak $rise MiB over the parse's $joinpk; blob $(( blob / 1048576 )) MiB; bound is macOS-only" ;;
    esac
fi

# ---- U ----
( cd "$REPO" && RIPWIRE_STATS=1 RIPWIRE_TEST_MEMSTATS_UNREAD=1 "$BIN" "$REPO" --cache="$TMP/u.bin" --callers=fn_0_0 >/dev/null 2>"$TMP/u.err" ); rcu=$?
nphase="$( grep -c '^\[mem\] phase=' "$TMP/u.err" )"
nunread="$( grep -cE '^\[mem\] phase=[a-z-]+ cur_mib=unavailable peak_mib=unavailable$' "$TMP/u.err" )"
nnum="$( grep -cE '^\[mem\] phase=.* (cur|peak)_mib=[0-9]' "$TMP/u.err" )"
uv="$( plateau "$TMP/u.err" )"
if [ "$rcu" -ne 0 ]; then
    no "U: the seam run exited $rcu"
elif [ "$nphase" -lt 6 ]; then
    no "U: the seam run printed $nphase phase lines (want >= 6: the premise)"
elif [ "$nunread" -ne "$nphase" ] || [ "$nnum" -ne 0 ]; then
    no "U: $nunread of $nphase phase lines read unavailable, $nnum carry a number: $( grep '^\[mem\] phase=' "$TMP/u.err" | head -1 )"
elif [ "$uv" != unavailable ]; then
    no "U: F's verdict on the unknown readings is '$uv' (want unavailable, never a plateau)"
else
    ok "U: unknown readings print unavailable on all $nphase phase lines, and F reads no plateau from them"
fi

if [ "$fail" -eq 0 ]; then echo "PASS memstatscheck"; exit 0; fi
echo "FAIL memstatscheck"; exit 1
