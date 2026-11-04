#!/usr/bin/env bash
# qualendpointcheck.sh — XF-QUALIFIED-ENDPOINTS: a qualified endpoint (`A::m`, `A.m`, `ns.fn`, `pkg.mod.fn`) names exactly
# the definition it spells on every verb that takes a symbol endpoint, and the answer SAYS so; bare names keep today's bytes.
#
# The shared resolver (graph.h resolveAllByNameQualified) already picked the qualified definition for --callers, --callees,
# --impact, --path, --expand, --connect and --edit-check (Stage 0, reports/xf-qual-endpoints.md). Two answers still read the
# BARE name back:
#   * --connect's <t defs=N> counted every definition of the bare name (`--connect=ProcessList::insert,...` printed defs="196",
#     the legend saying all were searched): a qualified terminal now reports the definitions its spelling searched;
#   * --edit-check on a scope-less grammar (TS/JS store no Symbol::scope, so the canonical id holds no owner) unioned
#     `Alpha.run` with a same-file `Beta.run`, and `ns.make` with `other.make`: defs=2 and Beta's caller listed as Alpha's.
#
# RED-FIRST (2026-11-04, main 50bc05e84): arms (a) (b) (c) (c2) (e1) (e2) (e3) FAIL; (d*) (f) (g*) (h*) PASS on main and are pins.
# Fix 1 (2026-11-04, on 45702bb9c): (d3) (d4) (e4) x2 FAIL there (folded rows, the unnarrowed preview); (a2) (a3) pin the
# file:name count (selectorIsBareName's `:` arm) and the joined() checks pin the join itself.
# Fixture test/qualendpointfix/{cpp,py,ts}: two classes sharing a method name `run`, two TS namespaces sharing `make`, two
# Python modules sharing `build`; `helper` calls Beta's run, `driver` calls Alpha's.
#
# Usage:  test/qualendpointcheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire test/qualendpointcheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/qualendpointfix"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "qualendpointcheck: BIN=$BIN  FIX=$FIX"
SCR="$( mktemp -d -t qualendpointcheck.XXXXXX )" || { echo "mktemp failed"; exit 2; }
trap 'rm -rf "$SCR"' EXIT
export HOME="$SCR"
# run LANG ARGS... : the answer of one verb, run from the fixture's own root (stdout+stderr)
run(){ local d="$1"; shift; ( cd "$FIX/$d" && "$BIN" . --no-cache "$@" 2>&1 ); }
has(){ printf '%s' "$1" | grep -qF -- "$2"; }
# joined OUT: the two terminals form one group (the legend names <unconnected> too, so the ELEMENT is matched by its radius=)
joined(){ has "$1" '<g terminals="2">' && ! has "$1" '<unconnected radius='; }

# ── (a)-(c) --connect: a qualified terminal's defs= is what its spelling searched ────────────────────────────────────────
O="$( run cpp --connect=driver,Alpha::run )"
if has "$O" '<t n="run" t="method" p="a.cpp:3" defs="2"/>'; then ok "(a) cpp --connect Alpha::run: defs=2 (its declaration + definition), not the bare name's 4"
else no "(a) cpp --connect Alpha::run terminal row"; printf '%s\n' "$O" | grep -o '<t [^>]*>' ; fi
if joined "$O"; then ok "(a) cpp --connect Alpha::run: driver and Alpha::run form one joined group"; else no "(a) cpp --connect Alpha::run: no joined group"; fi
O="$( run py --connect=driver,Alpha.run )"
if has "$O" '<t n="run" t="fn" p="pkg/mod.py:2"/>'; then ok "(b) py --connect Alpha.run: one definition searched, no defs="
else no "(b) py --connect Alpha.run terminal row"; printf '%s\n' "$O" | grep -o '<t [^>]*>' ; fi
if joined "$O"; then ok "(b) py --connect Alpha.run: driver and Alpha.run form one joined group"; else no "(b) py --connect Alpha.run: no joined group"; fi
O="$( run ts --connect=driver,ns.make )"
if has "$O" '<t n="make" t="fn" p="a.ts:3"/>'; then ok "(c) ts --connect ns.make: one definition searched, no defs="
else no "(c) ts --connect ns.make terminal row"; printf '%s\n' "$O" | grep -o '<t [^>]*>' ; fi
if joined "$O"; then ok "(c) ts --connect ns.make: driver and ns.make form one joined group"; else no "(c) ts --connect ns.make: no joined group"; fi
O="$( run py --connect=driver,pkg.mod.build )"
if has "$O" '<t n="build" t="fn" p="pkg/mod.py:9"/>'; then ok "(c2) py --connect pkg.mod.build: one definition searched, no defs="
else no "(c2) py --connect pkg.mod.build terminal row"; printf '%s\n' "$O" | grep -o '<t [^>]*>' ; fi

# (c2) stays unjoined on purpose: Python's module-attribute call `mod.build(2)` has no edge yet (PY-MOD-CALL-SITES).
# (a2) a file:name terminal counts the definitions in THAT file (fixture tsfile: a.ts holds Alpha.run + Beta.run, b.ts one run)
O="$( run tsfile --connect=driver,a.ts:run )"
if has "$O" '<t n="run" t="method" p="a.ts:1" defs="2"/>' && joined "$O"; then ok "(a2) ts --connect a.ts:run: defs=2 (a.ts's two run defs), not the bare name's 3"
else no "(a2) ts --connect a.ts:run terminal row"; printf '%s\n' "$O" | grep -o '<t [^>]*>' ; fi
O="$( run tsfile --connect=driver,run )"
if has "$O" 'p="a.ts:1" defs="3"/>'; then ok "(a3) ts --connect bare run: defs=3 (both files), unlike a.ts:run's 2"
else no "(a3) ts --connect bare run terminal row"; printf '%s\n' "$O" | grep -o '<t [^>]*>' ; fi

# ── (d) bare-name pins: today's bytes ──────────────────────────────────────────────────────────────────────────────────
O="$( run cpp --connect=driver,run )"
if has "$O" '<t n="run" t="method" p="a.cpp:3" defs="4"/>'; then ok "(d1) cpp --connect bare run keeps defs=4"; else no "(d1) cpp bare run terminal row moved"; fi
O="$( run ts --connect=driver,make )"
if has "$O" 'ambiguous_terminal="make"' && has "$O" '<t n="make" t="fn" p="a.ts:3" defs="2"/>'; then ok "(d2) ts --connect bare make keeps defs=2 + ambiguous_terminal"; else no "(d2) ts bare make terminal row moved"; fi

# (d3)/(d4) fix 1 (NIT-1): spellings that pick ONE definition share one <t> row, which prints the WIDEST count they searched
O="$( run ts --connect=driver,run,Alpha.run )"
if has "$O" '<t n="run" t="method" p="a.ts:1" defs="2"/>'; then ok "(d3) ts --connect=driver,run,Alpha.run: the folded row keeps the bare name's defs=2"
else no "(d3) ts folded bare+qualified row"; printf '%s\n' "$O" | grep -o '<t [^>]*>' ; fi
O="$( run ts --connect=driver,Alpha.run,a.ts:run )"
if has "$O" '<t n="run" t="method" p="a.ts:1" defs="2"/>'; then ok "(d4) ts --connect=driver,Alpha.run,a.ts:run: the folded row prints the wider defs=2"
else no "(d4) ts folded qualified+file row"; printf '%s\n' "$O" | grep -o '<t [^>]*>' ; fi

# ── (e) --edit-check on a scope-less grammar: the qualified contract only ──────────────────────────────────────────────
O="$( run ts --edit-check=Alpha.run )"
if has "$O" 'defs="1" callers="1"' && has "$O" '<c n="driver" p="a.ts:6"/>' && ! has "$O" '<c n="helper"'; then ok "(e1) ts --edit-check Alpha.run: Alpha's contract, driver only"
else no "(e1) ts --edit-check Alpha.run unioned Beta.run"; printf '%s\n' "$O" | grep -o '<edit-check [^>]*>'; fi
O="$( run ts --edit-check=Beta.run )"
if has "$O" 'defs="1" callers="1"' && has "$O" '<c n="helper" p="a.ts:5"/>' && ! has "$O" '<c n="driver"'; then ok "(e2) ts --edit-check Beta.run: Beta's contract, helper only"
else no "(e2) ts --edit-check Beta.run unioned Alpha.run"; printf '%s\n' "$O" | grep -o '<edit-check [^>]*>'; fi
O="$( run ts --edit-check=ns.make )"
if has "$O" 'defs="1" callers="1"' && ! has "$O" 'p="a.ts:4"'; then ok "(e3) ts --edit-check ns.make: ns's make only"
else no "(e3) ts --edit-check ns.make unioned other.make"; printf '%s\n' "$O" | grep -o '<edit-check [^>]*>'; fi
# (e4) fix 1 (SF-1): the PREVIEW narrows like the answer it predicts — CLI --dry-run, then the MCP edit_check + new_body twin
printf 'run(x: number): number { return x + 3; }' > "$SCR/pay.ts"
O="$( run ts --edit-check=Alpha.run --edit-payload="$SCR/pay.ts" --dry-run )"
if has "$O" 'preview="1"' && has "$O" 'defs="1" callers="1"' && has "$O" '<c n="driver" p="a.ts:6"/>' && ! has "$O" '<c n="helper"'; then ok "(e4) ts --edit-check Alpha.run --dry-run: the preview answers Alpha's contract, driver only"
else no "(e4) ts --edit-check Alpha.run --dry-run unioned Beta.run"; printf '%s\n' "$O" | grep -o '<edit-check [^>]*>'; fi
O="$( cd "$FIX/ts" && python3 - "$BIN" "$SCR/pay.ts" <<'PYEOF' 2>&1
import json, subprocess, sys
req = { "jsonrpc": "2.0", "id": 1, "method": "tools/call",
        "params": { "name": "edit_check", "arguments": { "path": ".", "symbol": "Alpha.run", "new_body": open( sys.argv[2] ).read() } } }
p = subprocess.run( [ sys.argv[1], "--mcp" ], input = json.dumps( req ) + "\n", capture_output = True, text = True )
for line in p.stdout.splitlines():
    try:
        d = json.loads( line )
    except ValueError:
        continue
    for c in d.get( "result", {} ).get( "content", [] ):
        sys.stdout.write( c.get( "text", "" ) )
PYEOF
)"
if has "$O" 'preview="1"' && has "$O" 'defs="1" callers="1"' && has "$O" '<c n="driver" p="a.ts:6"/>' && ! has "$O" '<c n="helper"'; then ok "(e4) MCP edit_check symbol=Alpha.run new_body: Alpha's contract, driver only"
else no "(e4) MCP edit_check Alpha.run + new_body unioned Beta.run"; printf '%s\n' "$O" | grep -o '<edit-check [^>]*>' | head -2; fi
O="$( run ts --edit-check=run )"
if has "$O" 'defs="2" callers="2"'; then ok "(f) ts --edit-check bare run keeps today's union (defs=2 callers=2)"; else no "(f) ts bare --edit-check=run moved"; fi

# ── (g) resolution pins: every endpoint verb resolves each spelling to exactly the qualified def ───────────────────────
for c in "cpp Alpha::run a.cpp:3 driver" "cpp Beta::run a.cpp:4 helper" "py Alpha.run pkg/mod.py:2 driver" "py Beta.run pkg/mod.py:6 helper" \
         "ts Alpha.run a.ts:1 driver" "ts Beta.run a.ts:2 helper" "ts ns.make a.ts:3 driver"; do
    set -- $c; d=$1; s=$2; p=$3; caller=$4
    O="$( run "$d" --callers="$s" )"
    if has "$O" "n=\"$caller\"" && [ "$( printf '%s' "$O" | grep -o '<s t="[^>]*>' | wc -l | tr -d ' ' )" = 1 ]; then ok "(g) $d --callers=$s: $caller only"
    else no "(g) $d --callers=$s"; printf '%s\n' "$O" | grep -o '<s [^>]*>'; fi
    O="$( run "$d" --path=driver,"$s" )"
    if has "$O" "to_p=\"$p\"" && has "$O" 'reachable="1"'; then ok "(g) $d --path=driver,$s ends at $p"; else no "(g) $d --path=driver,$s"; fi
    O="$( run "$d" --impact="$s" )"
    if has "$O" "n=\"$caller\""; then ok "(g) $d --impact=$s reaches $caller"; else no "(g) $d --impact=$s"; fi
done
O="$( run py --path=driver,pkg.mod.build )"
if has "$O" 'to_p="pkg/mod.py:9"'; then ok "(g) py --path pkg.mod.build ends at pkg/mod.py:9"; else no "(g) py --path pkg.mod.build"; fi

# ── (h) an unknown qualifier is refused on every verb, never read as the bare name ─────────────────────────────────────
for c in "cpp Gamma::run" "py Gamma.run" "ts Gamma.run"; do
    set -- $c; d=$1; s=$2
    for v in "--callers=$s" "--path=driver,$s" "--connect=driver,$s" "--edit-check=$s" "--impact=$s"; do
        O="$( run "$d" "$v" )"; rc=$?
        if has "$O" 'not found' && [ "$rc" -ne 0 ] && ! has "$O" 'p="a.'; then ok "(h) $d $v refused (rc=$rc)"
        else no "(h) $d $v did not refuse (rc=$rc)"; printf '%s\n' "$O" | tail -2; fi
    done
done
exit $fail
