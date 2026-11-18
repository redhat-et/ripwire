#!/usr/bin/env bash
# memceilingcheck.sh — the allocator-level memory ceiling (src/memceiling.h, lane M2 prototype, DEFAULT OFF), armed by
# RIPWIRE_MEM_BUDGET_MB. On 2026-11-18 a run over llvm-project grew ~5 GB/s inside buildGraph's resolve loop, where the
# phase-boundary memory guard reads nothing, and reached 149.7 GB. The ceiling reads the footprint at operator new and
# REFUSES the run (one stderr line, exit 5, nothing on stdout) instead of answering from a partial run.
#
# Arms:
#   R  refusal shape: RIPWIRE_MEM_BUDGET_MB=64 (the floor) over this repo's own src/ — a run whose footprint passes 64 MiB
#      on the dev machine (142 MiB measured 2026-11-18, macOS) — exits 5, prints NOTHING on stdout, and its stderr is exactly
#      one line naming the variable, the footprint, the request, the phase, "answers nothing" and "exit 5". A build that does
#      not replace operator new (Linux: largealloc.cpp is macOS-only) cannot arm it: R is SKIP there, and the run must say
#      "is NOT armed" instead of refusing silently or answering silently.
#   C  control, no budget: the same run unset exits 0 with a non-empty map — so R's refusal is the ceiling, not the tree.
#   D  determinism: armed far above the run's need (1,000,000 MiB) the run prints the SAME stdout and stderr bytes as unset.
#   V  a typo is refused, never obeyed or ignored: '12x' and '10' (under the 64 MiB floor) each exit 1 with nothing on stdout
#      and a stderr line naming RIPWIRE_MEM_BUDGET_MB.
#   M  the server survives: --mcp with RIPWIRE_MEM_BUDGET_MB=64 does not arm (its refusal would end the process), says so
#      once on stderr, and answers initialize + tools/list, exit 0.
#
# Usage: bash test/memceilingcheck.sh [BIN]
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
case "$BIN" in /*) ;; *) BIN="$PWD/$BIN" ;; esac
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ fail=1; printf '  FAIL  %s\n' "$*"; return 0; }
skip(){ printf '  SKIP  %s\n' "$*"; return 0; }

if ! "$BIN" --version 2>/dev/null | grep -q '^ripwire '; then
    echo "  FAIL  $BIN does not run"; echo "FAIL memceilingcheck"; exit 1
fi
unset RIPWIRE_MEM_BUDGET_MB
TREE="$ROOT/src"

# ---- R ----
RIPWIRE_MEM_BUDGET_MB=64 "$BIN" "$TREE" --no-cache >"$TMP/r.out" 2>"$TMP/r.err"; rcr=$?
lines="$( grep -c '' "$TMP/r.err" )"
shape='^ripwire: refused by the memory ceiling \(RIPWIRE_MEM_BUDGET_MB=64\): the footprint was [0-9]+ MiB and the next allocation \([0-9]+ MiB\) would pass it, after phase [a-z-]+ — the run stopped there and answers nothing .*; exit 5\. Raise RIPWIRE_MEM_BUDGET_MB, or unset it to run without the ceiling$'
if grep -q 'RIPWIRE_MEM_BUDGET_MB is NOT armed (this build does not replace operator new' "$TMP/r.err"; then
    if [ "$rcr" -eq 0 ]; then
        skip "R: this build cannot arm the ceiling, and says so on stderr (rc 0): $( head -c 160 "$TMP/r.err" )"
    else
        no "R: the unarmable build exited $rcr"
    fi
elif [ "$rcr" -ne 5 ]; then
    no "R: RIPWIRE_MEM_BUDGET_MB=64 exited $rcr (want 5, the memory refusal); stderr: $( head -c 300 "$TMP/r.err" )"
elif [ -s "$TMP/r.out" ]; then
    no "R: the refused run printed $( wc -c < "$TMP/r.out" ) bytes on stdout (want none: no answer from a partial run)"
elif [ "$lines" -ne 1 ] || ! grep -Eq "$shape" "$TMP/r.err"; then
    no "R: stderr is $lines line(s), not the one refusal line: $( head -c 400 "$TMP/r.err" )"
else
    ok "R: refused with exit 5, nothing on stdout, one line: $( sed -E 's/ — the run.*//' "$TMP/r.err" )"
fi

# ---- C ----
"$BIN" "$TREE" --no-cache >"$TMP/c.out" 2>"$TMP/c.err"; rcc=$?
if [ "$rcc" -eq 0 ] && [ -s "$TMP/c.out" ]; then
    ok "C: unset, the same run answers (rc 0, $( wc -c < "$TMP/c.out" | tr -d ' ' ) B)"
else
    no "C: unset, the run exited $rcc with $( wc -c < "$TMP/c.out" | tr -d ' ' ) B on stdout"
fi

# ---- D ----
RIPWIRE_MEM_BUDGET_MB=1000000 "$BIN" "$TREE" --no-cache >"$TMP/d.out" 2>"$TMP/d.err"; rcd=$?
if [ "$rcd" -eq "$rcc" ] && cmp -s "$TMP/c.out" "$TMP/d.out" && cmp -s "$TMP/c.err" "$TMP/d.err"; then
    ok "D: armed far above the need, stdout and stderr are byte-identical to unset (rc $rcd)"
else
    no "D: armed at 1000000 MiB: rc $rcd vs $rcc, stdout $( cmp -s "$TMP/c.out" "$TMP/d.out" && echo same || echo DIFFERS ), stderr $( cmp -s "$TMP/c.err" "$TMP/d.err" && echo same || echo DIFFERS )"
fi

# ---- V ----
for bad in 12x 10; do
    RIPWIRE_MEM_BUDGET_MB="$bad" "$BIN" "$TREE" --no-cache >"$TMP/v.out" 2>"$TMP/v.err"; rcv=$?
    if [ "$rcv" -eq 1 ] && [ ! -s "$TMP/v.out" ] && grep -q "^ripwire: RIPWIRE_MEM_BUDGET_MB needs a whole number of MiB, at least 64 — got '$bad'" "$TMP/v.err"; then
        ok "V: RIPWIRE_MEM_BUDGET_MB='$bad' is refused (exit 1, named on stderr, nothing on stdout)"
    else
        no "V: RIPWIRE_MEM_BUDGET_MB='$bad': rc $rcv, $( wc -c < "$TMP/v.out" | tr -d ' ' ) B stdout, stderr: $( head -c 300 "$TMP/v.err" )"
    fi
done

# ---- M ----
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"memceilingcheck","version":"0"}}}' \
              '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
    | ( cd "$TMP" && RIPWIRE_MEM_BUDGET_MB=64 "$BIN" --mcp "$TREE" >"$TMP/m.out" 2>"$TMP/m.err" ); rcm=$?
nnot="$( grep -c 'RIPWIRE_MEM_BUDGET_MB is NOT armed' "$TMP/m.err" )"
if [ "$rcm" -eq 0 ] && [ "$nnot" -eq 1 ] && grep -q '"id":2' "$TMP/m.out" && grep -q '"tools"' "$TMP/m.out"; then
    ok "M: --mcp under RIPWIRE_MEM_BUDGET_MB=64 does not arm, says so once, and answers initialize + tools/list (rc 0)"
else
    no "M: --mcp: rc $rcm, 'NOT armed' x$nnot, tools/list answered: $( grep -c '"tools"' "$TMP/m.out" ); stderr: $( head -c 300 "$TMP/m.err" )"
fi

if [ "$fail" -eq 0 ]; then echo "PASS memceilingcheck"; exit 0; fi
echo "FAIL memceilingcheck"; exit 1
