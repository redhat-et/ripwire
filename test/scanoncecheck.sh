#!/usr/bin/env bash
# scanoncecheck.sh — FOR-SCAN-ONCE: one --for call reads the corpus ONCE for all the literal scans its literal block makes.
#
# THE COST (reports/ml-stage0-1113 § FOR-SCAN-ONCE). Half of the measured --for calls made two or more literal grepCollect()
# scans, and every scan read every indexed file: envoy's message task read its 11,036 files 8 times, one read per message
# try. search.h GrepScanBatch now reads the corpus once for the asked pattern and every pattern the block expects
# (forliteral.h forLiteralScanPlan, the table walk's kept anchors), and serves the later asks from what that read collected.
#
# THE ARMS (counts read off the RIPWIRE_STATS line `[scan] for literal_asks=A corpus_reads=R expected_unasked=U`):
#   P1  PREMISE — the message task really makes several literal scans: literal_asks >= 3. FAILS on fewer (a call that asks
#       once proves nothing about how often it reads).
#   R1  that call reads the corpus once: corpus_reads == 1 (main read it once per ask).
#   P2/R2  the table walk: a backticked anchor asked by the candidate loop and again by the walk (asks >= 2), one read.
#   I1  IDENTITY (non-NDEBUG): each task's answer (stdout + stderr + rc) equals RIPWIRE_FAULT_SCAN_UNBATCHED=1, which serves no
#       ask from the batch (every ask reads alone, the old path); the arm counts the tasks compared and FAILS on zero.
#   I2  the --grep verb never opens a batch: no [scan] line.
#   D   determinism: two batched calls are byte-identical.
#
# Usage:  bash test/scanoncecheck.sh [BIN]   |   RIPWIRE_BIN=build/ripwire bash test/scanoncecheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "scanoncecheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
FIX="$TMP/fix"; mkdir -p "$FIX/app" "$FIX/internal/lang" "$FIX/internal/funcs" "$TMP/home"
export HOME="$TMP/home"
cat > "$FIX/app/cfg.py" <<'PY'
def chain(n):
    raise ValueError("terminal {} must be the last filter in a chain".format(n))
PY
cat > "$FIX/internal/lang/functions.go" <<'GO'
package lang

func (s *Scope) Functions() map[string]Function {
	baseFunctions := map[string]Function{
		"abspath":  funcs.AbsPathFunc,
		"basename": funcs.BaseNameFunc,
	}
	return baseFunctions
}
GO
cat > "$FIX/internal/funcs/path.go" <<'GO'
package funcs

var AbsPathFunc = Function{}
var BaseNameFunc = Function{}
GO

MSG='--for=terminal foo must be the last filter in a chain error'
TBL='--for=add a new function; use `abspath` as the model'

# run TAG ARGS... : stdout, stderr and rc of one call into $TMP/TAG.{out,err,rc}
run(){ local tag="$1"; shift; ( cd "$FIX" || exit 1; "$BIN" "$FIX" --no-cache "$@" </dev/null >"$TMP/$tag.out" 2>"$TMP/$tag.err" ); echo $? >"$TMP/$tag.rc"; }
count(){ grep -m1 '^\[scan\] for ' "$TMP/$1.err" | grep -oE "$2=[0-9]+" | cut -d= -f2; }

RIPWIRE_STATS=1 run msg "$MSG"
asks="$( count msg literal_asks )"; reads="$( count msg corpus_reads )"
if [ "${asks:-0}" -ge 3 ]; then ok "P1 the message task asks ${asks} literal scans"; else no "P1 premise: the message task asked '${asks:-none}' scans (want >= 3): $( head -c 300 "$TMP/msg.err" )"; fi
if [ "${reads:-x}" = 1 ]; then ok "R1 the ${asks:-?} asks read the corpus once"; else no "R1 corpus_reads='${reads:-none}' for ${asks:-?} asks (want 1)"; fi
if grep -q 's="must be the last filter in a chain" shape="message"' "$TMP/msg.out"; then ok "P1b the batched answer still finds the fragment"; else no "P1b no message <lit> in the batched answer"; fi

RIPWIRE_STATS=1 run tbl "$TBL"
asks="$( count tbl literal_asks )"; reads="$( count tbl corpus_reads )"
if [ "${asks:-0}" -ge 2 ]; then ok "P2 the table task asks ${asks} literal scans"; else no "P2 premise: the table task asked '${asks:-none}' scans (want >= 2)"; fi
if [ "${reads:-x}" = 1 ]; then ok "R2 the table task's asks read the corpus once"; else no "R2 corpus_reads='${reads:-none}' for ${asks:-?} asks (want 1)"; fi
if grep -q 's="abspath" shape="table"' "$TMP/tbl.out"; then ok "P2b the batched table answer still prints the row"; else no "P2b no table <lit> in the batched answer"; fi

# I1: the batch moves no byte — against the unbatched path, where the binary carries fault switches
RIPWIRE_FAULT_SCAN_UNBATCHED=1 RIPWIRE_STATS=1 run probe "$MSG"
if [ "$( count probe literal_asks )" = 0 ]; then
    compared=0
    for t in msg tbl; do
        task="$MSG"; [ "$t" = tbl ] && task="$TBL"
        run "$t.b" "$task"
        RIPWIRE_FAULT_SCAN_UNBATCHED=1 run "$t.u" "$task"
        if cmp -s "$TMP/$t.b.out" "$TMP/$t.u.out" && cmp -s "$TMP/$t.b.err" "$TMP/$t.u.err" && cmp -s "$TMP/$t.b.rc" "$TMP/$t.u.rc"; then
            compared=$(( compared + 1 ))
        else
            no "I1 $t: the batched answer differs from the unbatched one: $( diff "$TMP/$t.b.out" "$TMP/$t.u.out" | head -5 )"
        fi
    done
    if [ "$compared" -eq 2 ]; then ok "I1 stdout + stderr + rc equal the unbatched path on $compared tasks"; else no "I1 compared $compared of 2 tasks"; fi
else
    printf '  INFO  I1 this binary compiles fault switches out (NDEBUG); the identity arm runs on the plain-flavour leg\n'
fi

RIPWIRE_STATS=1 run grep --grep=filter
if ! grep -q '^\[scan\]' "$TMP/grep.err" && [ "$( cat "$TMP/grep.rc" )" = 0 ]; then ok "I2 --grep opens no batch"; else no "I2 --grep: rc=$( cat "$TMP/grep.rc" ) $( grep '^\[scan\]' "$TMP/grep.err" )"; fi

run d1 "$MSG"; run d2 "$MSG"
if cmp -s "$TMP/d1.out" "$TMP/d2.out" && cmp -s "$TMP/d1.err" "$TMP/d2.err"; then ok "D two batched calls are byte-identical"; else no "D the batched answer is not deterministic"; fi

[ "$fail" = 0 ] && echo "scanoncecheck: PASS" || echo "scanoncecheck: FAIL"
exit "$fail"
