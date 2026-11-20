#!/usr/bin/env bash
# memceilingcheck.sh — the memory guard's allocator line (src/memceiling.h; ON by default since lane M2, owner 2026-11-18).
# On 2026-11-18 a run over llvm-project grew ~5 GB/s inside buildGraph's resolve loop, where the phase-boundary readings see
# nothing, and reached 149.7 GB. The line reads the footprint at operator new and REFUSES the run (one stderr line, exit 5,
# nothing on stdout) instead of answering from a partial run. Its ceiling is the guard's hard limit (65% of RAM,
# --max-memory, RIPWIRE_MAX_MEMORY) unless RIPWIRE_MEM_BUDGET_MB names one for this line alone; RIPWIRE_MEM_BUDGET_MB=0 is off.
#
# Arms (the tree is this repo's own src/: its footprint passes 64 MiB, 142 MiB measured 2026-11-18 on macOS):
#   R  explicit refusal: RIPWIRE_MEM_BUDGET_MB=64 exits 5, prints NOTHING on stdout, and its stderr is exactly one line naming
#      the variable, the footprint, the request, the phase, "answers nothing" and "exit 5".
#   K  one knob: with no RIPWIRE_MEM_BUDGET_MB the ceiling IS the guard's limit — --max-memory=64M and RIPWIRE_MAX_MEMORY=64M
#      each refuse the same way, and the line names the knob that set it.
#   S  on by default: RIPWIRE_STATS's `[mem] ceiling` line reads armed_mib > 0 unset, 0 under RIPWIRE_MEM_BUDGET_MB=0, and the
#      explicit value under RIPWIRE_MEM_BUDGET_MB=1000000; the default run took at least one reading.
#   C  control: unset (default on, the 65% limit far above this run) the run exits 0 with a non-empty map.
#   D  byte-identical when the ceiling is not hit: the default map, --json, and a --for answer print the SAME stdout and stderr
#      bytes and rc with the line on by default, OFF (=0), and armed far above the need (1000000).
#   E  the post-write suspension (owner ruling 101): E1 an edit verb is still refused BEFORE it writes (exit 5, not the
#      exit 1 of a resolved-but-missing symbol), E2 every edit receipt names what the ceiling did — suspended when armed,
#      "not armed" when off, so neither surface's receipt can imply a ceiling-checked post-check — E3 the suspension is
#      constructible in exactly one file and no flag or environment path reaches its depth counter.
#   V  a typo is refused, never obeyed or ignored: '12x' and '10' (under the 64 MiB floor) exit 1 with nothing on stdout and a
#      stderr line naming RIPWIRE_MEM_BUDGET_MB.
#   M  the server survives: --mcp under RIPWIRE_MEM_BUDGET_MB=64 does not arm (its refusal would end the process), says so
#      once, and answers initialize + tools/list; under the default it says nothing about the ceiling.
# A build that does not replace operator new (sanitizer, RIPWIRE_ALLOC_COUNT) cannot arm the line: R, K and S are SKIP there,
# and R must say "is NOT armed" instead of refusing silently or answering silently. D still runs there, with rc and stdout
# strict and stderr allowed to carry exactly that ONE diagnostic line on its explicitly-armed arm — see D.
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
unset RIPWIRE_MEM_BUDGET_MB RIPWIRE_MAX_MEMORY RIPWIRE_STATS
TREE="$ROOT/src"
TAIL=' — the run stopped there and answers nothing \(any output already printed above is cut, not complete\); exit 5\. Raise the limit \(--max-memory, RIPWIRE_MAX_MEMORY, or RIPWIRE_MEM_BUDGET_MB for this line alone\), or set RIPWIRE_MEM_BUDGET_MB=0 to run without the ceiling$'
shapeFor(){ printf '^ripwire: refused by the memory ceiling \\(%s\\): the footprint was [0-9]+ MiB and the next allocation \\([0-9]+ MiB\\) would pass it, after phase [a-z-]+%s' "$1" "$TAIL"; }
# refused NAME LABEL_REGEX ERRFILE OUTFILE RC
refused(){
    local lines; lines="$( grep -c '' "$3" )"
    if [ "$5" -ne 5 ]; then
        no "$1: exited $5 (want 5, the memory refusal); stderr: $( head -c 300 "$3" )"
    elif [ -s "$4" ]; then
        no "$1: the refused run printed $( wc -c < "$4" | tr -d ' ' ) bytes on stdout (want none: no answer from a partial run)"
    elif [ "$lines" -ne 1 ] || ! grep -Eq "$( shapeFor "$2" )" "$3"; then
        no "$1: stderr is $lines line(s), not the one refusal line: $( head -c 400 "$3" )"
    else
        ok "$1: refused with exit 5, nothing on stdout, one line: $( sed -E 's/ — the run.*//' "$3" )"
    fi
}

# ---- R ----
RIPWIRE_MEM_BUDGET_MB=64 "$BIN" "$TREE" --no-cache >"$TMP/r.out" 2>"$TMP/r.err"; rcr=$?
hooked=1
if grep -q 'RIPWIRE_MEM_BUDGET_MB is NOT armed (this build does not replace operator new' "$TMP/r.err"; then
    hooked=0
    if [ "$rcr" -eq 0 ]; then
        skip "R: this build cannot arm the ceiling, and says so on stderr (rc 0): $( head -c 160 "$TMP/r.err" )"
    else
        no "R: the unarmable build exited $rcr"
    fi
else
    refused "R" 'RIPWIRE_MEM_BUDGET_MB=64' "$TMP/r.err" "$TMP/r.out" "$rcr"
fi

# ---- K ----
if [ "$hooked" -eq 1 ]; then
    "$BIN" "$TREE" --no-cache --max-memory=64M >"$TMP/k1.out" 2>"$TMP/k1.err"; rck=$?
    refused "K --max-memory=64M" '--max-memory=64M' "$TMP/k1.err" "$TMP/k1.out" "$rck"
    RIPWIRE_MAX_MEMORY=64M "$BIN" "$TREE" --no-cache >"$TMP/k2.out" 2>"$TMP/k2.err"; rck=$?
    refused "K RIPWIRE_MAX_MEMORY=64M" 'RIPWIRE_MAX_MEMORY=64M' "$TMP/k2.err" "$TMP/k2.out" "$rck"
else
    skip "K: this build cannot arm the ceiling"
fi

# ---- S ----
armedMib(){ grep -E '^\[mem\] ceiling armed_mib=' "$1" | head -1 | sed -E 's/.*armed_mib=([0-9]+).*/\1/'; }
readingsOf(){ grep -E '^\[mem\] ceiling ' "$1" | head -1 | sed -E 's/.* readings=([0-9]+).*/\1/'; }
if [ "$hooked" -eq 1 ]; then
    RIPWIRE_STATS=1 "$BIN" "$TREE" --no-cache >/dev/null 2>"$TMP/s0.err"
    RIPWIRE_STATS=1 RIPWIRE_MEM_BUDGET_MB=0 "$BIN" "$TREE" --no-cache >/dev/null 2>"$TMP/s1.err"
    RIPWIRE_STATS=1 RIPWIRE_MEM_BUDGET_MB=1000000 "$BIN" "$TREE" --no-cache >/dev/null 2>"$TMP/s2.err"
    a0="$( armedMib "$TMP/s0.err" )"; a1="$( armedMib "$TMP/s1.err" )"; a2="$( armedMib "$TMP/s2.err" )"; r0="$( readingsOf "$TMP/s0.err" )"
    if [ "${a0:-0}" -gt 0 ] && [ "$a1" = 0 ] && [ "$a2" = 1000000 ] && [ "${r0:-0}" -ge 1 ]; then
        ok "S: on by default (armed_mib=$a0, $r0 readings on this run), off at RIPWIRE_MEM_BUDGET_MB=0, explicit 1000000 honoured"
    else
        no "S: armed_mib unset='${a0:-?}' (want > 0) =0:'${a1:-?}' (want 0) =1000000:'${a2:-?}'; default readings='${r0:-?}' (want >= 1)"
    fi
else
    skip "S: this build cannot arm the ceiling"
fi

# ---- C ----
"$BIN" "$TREE" --no-cache >"$TMP/c.out" 2>"$TMP/c.err"; rcc=$?
if [ "$rcc" -eq 0 ] && [ -s "$TMP/c.out" ]; then
    ok "C: default (the guard's limit), the same run answers (rc 0, $( wc -c < "$TMP/c.out" | tr -d ' ' ) B)"
else
    no "C: default, the run exited $rcc with $( wc -c < "$TMP/c.out" | tr -d ' ' ) B on stdout"
fi

# ---- D ----
# On a build that CANNOT arm the line, an EXPLICIT RIPWIRE_MEM_BUDGET_MB is answered with the "is NOT armed" diagnostic,
# by design (R asserts exactly that) — so `=1000000` has one line on stderr the default run does not, and requiring
# byte-identical stderr there would fail the gate for the product behaving correctly. Hooked builds keep the strict
# comparison; an unhooked one allows that ONE line and nothing else, by filtering it out and comparing the rest byte for
# byte. rc and stdout stay strict in both cases.
derrsame(){ # ON-err ARM-err ARM  ->  "identical" | "diagnostic-only" | "DIFFERS"
    if cmp -s "$1" "$2"; then printf identical; return 0; fi
    if [ "$hooked" -eq 0 ] && [ "$3" != 0 ] \
       && [ "$( grep -c 'RIPWIRE_MEM_BUDGET_MB is NOT armed (this build does not replace operator new' "$2" )" -eq 1 ] \
       && grep -v 'RIPWIRE_MEM_BUDGET_MB is NOT armed' "$2" | cmp -s - "$1"; then
        printf diagnostic-only; return 0
    fi
    printf DIFFERS
}
dsame=0; dtotal=0; ddiag=0
for form in map json for; do
    case "$form" in
        map)  set -- "$TREE" --no-cache ;;
        json) set -- "$TREE" --no-cache --json ;;
        for)  set -- "$TREE" --no-cache --for="memory guard hard limit refusal" ;;
    esac
    "$BIN" "$@" >"$TMP/d.$form.on.out" 2>"$TMP/d.$form.on.err"; rcon=$?
    for arm in 0 1000000; do
        dtotal=$(( dtotal + 1 ))
        RIPWIRE_MEM_BUDGET_MB="$arm" "$BIN" "$@" >"$TMP/d.$form.$arm.out" 2>"$TMP/d.$form.$arm.err"; rca=$?
        derr="$( derrsame "$TMP/d.$form.on.err" "$TMP/d.$form.$arm.err" "$arm" )"
        if [ "$rca" -eq "$rcon" ] && [ -s "$TMP/d.$form.on.out" ] && cmp -s "$TMP/d.$form.on.out" "$TMP/d.$form.$arm.out" && [ "$derr" != DIFFERS ]; then
            dsame=$(( dsame + 1 ))
            [ "$derr" = diagnostic-only ] && ddiag=$(( ddiag + 1 ))
        else
            no "D: $form, default vs RIPWIRE_MEM_BUDGET_MB=$arm: rc $rcon/$rca, stdout $( cmp -s "$TMP/d.$form.on.out" "$TMP/d.$form.$arm.out" && echo same || echo DIFFERS ), stderr $derr"
        fi
    done
done
[ "$dsame" -eq "$dtotal" ] && ok "D: map, --json and --for print byte-identical stdout and rc with the line on by default, off (=0) and armed at 1000000, and byte-identical stderr ($dsame/$dtotal pairs$( [ "$ddiag" -gt 0 ] && printf ', %s of them with only this unarmable build'"'"'s one "is NOT armed" line allowed' "$ddiag" ))"

# ---- E: the post-write suspension (owner ruling 101) ----
# The line must NOT refuse after an edit verb has committed a file: the edit would be applied with no receipt and
# a retry could insert twice. These arms assert the three properties the ruling named, in the order a reader
# should doubt them: that the suspension cannot be reached from outside, that it did not cost the PRE-write
# checks their arming, and that the receipt says the check ran without the ceiling.
#
# E1 is the one that could silently rot: it asserts the pre-write refusal by its EXIT CODE, against a tree big
# enough to cross 64 MiB while resolving. The target symbol deliberately does not exist, so even a completely
# broken ceiling cannot write anything here — and the distinction being asserted is exit 5 (refused before
# resolution, i.e. before any write) rather than exit 1 (resolved, and not found).
mkdir -p "$TMP/fix"
cat >"$TMP/fix/a.cpp" <<'CPP'
int ceilingAlpha( int x )
{
    return x + 1;
}
CPP
printf '// marker' >"$TMP/payload"

if [ "$hooked" -eq 1 ]; then
    cp -R "$ROOT/src" "$TMP/bigedit"
    RIPWIRE_MEM_BUDGET_MB=64 "$BIN" "$TMP/bigedit" --insert-after-symbol=noSuchSymbolForThisGate \
        --edit-payload="$TMP/payload" >"$TMP/e1.out" 2>"$TMP/e1.err"; rce1=$?
    if [ "$rce1" -eq 5 ] && [ ! -s "$TMP/e1.out" ] && grep -q 'refused by the memory ceiling' "$TMP/e1.err"; then
        ok "E1: an edit verb is still refused BEFORE it writes (exit 5, nothing on stdout) — the suspension did not disarm the pre-write path"
    else
        no "E1: edit under RIPWIRE_MEM_BUDGET_MB=64: rc $rce1 (want 5), $( wc -c < "$TMP/e1.out" | tr -d ' ' ) B stdout, stderr: $( head -c 200 "$TMP/e1.err" )"
    fi

    # E2: a real edit succeeds and the receipt says what the ceiling did — ALWAYS, in both states, because
    # receiptpostcheck (13) requires the MCP and CLI receipts to carry the same keys and --mcp never arms the
    # line. Armed far above the need it reports the suspension; disarmed (=0) it reports "not armed".
    cp -R "$TMP/fix" "$TMP/e2on"
    RIPWIRE_MEM_BUDGET_MB=1000000 "$BIN" "$TMP/e2on" --insert-after-symbol=ceilingAlpha \
        --edit-payload="$TMP/payload" >"$TMP/e2on.out" 2>"$TMP/e2on.err"; rce2=$?
    cp -R "$TMP/fix" "$TMP/e2off"
    RIPWIRE_MEM_BUDGET_MB=0 "$BIN" "$TMP/e2off" --insert-after-symbol=ceilingAlpha \
        --edit-payload="$TMP/payload" >"$TMP/e2off.out" 2>"$TMP/e2off.err"; rce2off=$?
    if [ "$rce2" -eq 0 ] && [ "$rce2off" -eq 0 ] \
       && grep -q '"memory_ceiling":"suspended for this check' "$TMP/e2on.out" \
       && grep -q 'retry could insert twice' "$TMP/e2on.out" \
       && grep -q '"memory_ceiling":"not armed for this run' "$TMP/e2off.out"; then
        ok "E2: the receipt names what the ceiling did in BOTH states — suspended when armed, 'not armed' at =0 (rc 0/0), so neither surface's receipt can imply a checked post-check"
    else
        no "E2: armed rc $rce2 (want 0) suspended-clause=$( grep -c '\"memory_ceiling\":\"suspended' "$TMP/e2on.out" ) (want 1); off rc $rce2off not-armed-clause=$( grep -c '\"memory_ceiling\":\"not armed' "$TMP/e2off.out" ) (want 1)"
    fi
else
    skip "E1/E2: this build cannot arm the ceiling, so there is nothing to suspend"
fi

# E3: STRUCTURAL, and it runs on every build — the ruling's first constraint is that nothing a caller can type
# switches the ceiling off, so the suspension must be constructible in exactly one place, and that place must be
# the post-write funnel. A new construction site, or any argument/environment path into the depth counter, fails.
e3sites="$( grep -rln 'memceiling::Suspension' "$ROOT/src" | LC_ALL=C sort | tr '\n' ' ' )"
e3knob="$( grep -rl 'suspendDepth' "$ROOT/src" | grep -vE 'memceiling\.h$' | tr '\n' ' ' )"
if [ "$e3sites" = "$ROOT/src/mcpedit.h " ] && [ -z "$e3knob" ]; then
    ok "E3: the suspension is constructed in exactly one file (src/mcpedit.h, the post-write funnel) and no flag or environment path reaches its depth counter"
else
    no "E3: construction sites={$e3sites} (want src/mcpedit.h alone); files touching suspendDepth outside memceiling.h={$e3knob} (want none)"
fi

# ---- V ----
for bad in 12x 10; do
    RIPWIRE_MEM_BUDGET_MB="$bad" "$BIN" "$TREE" --no-cache >"$TMP/v.out" 2>"$TMP/v.err"; rcv=$?
    if [ "$rcv" -eq 1 ] && [ ! -s "$TMP/v.out" ] && grep -q "^ripwire: RIPWIRE_MEM_BUDGET_MB needs 0 (off) or a whole number of MiB, at least 64 — got '$bad'" "$TMP/v.err"; then
        ok "V: RIPWIRE_MEM_BUDGET_MB='$bad' is refused (exit 1, named on stderr, nothing on stdout)"
    else
        no "V: RIPWIRE_MEM_BUDGET_MB='$bad': rc $rcv, $( wc -c < "$TMP/v.out" | tr -d ' ' ) B stdout, stderr: $( head -c 300 "$TMP/v.err" )"
    fi
done

# ---- M ----
mcp(){ # outfile errfile env...
    local o="$1" e="$2"; shift 2
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"memceilingcheck","version":"0"}}}' \
                  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
        | ( cd "$TMP" && env "$@" "$BIN" --mcp "$TREE" >"$o" 2>"$e" )
}
mcp "$TMP/m.out" "$TMP/m.err" RIPWIRE_MEM_BUDGET_MB=64; rcm=$?
mcp "$TMP/m0.out" "$TMP/m0.err" X=1; rcm0=$?
nnot="$( grep -c 'RIPWIRE_MEM_BUDGET_MB is NOT armed' "$TMP/m.err" )"; nnot0="$( grep -c 'RIPWIRE_MEM_BUDGET_MB' "$TMP/m0.err" )"
if [ "$rcm" -eq 0 ] && [ "$rcm0" -eq 0 ] && [ "$nnot" -eq 1 ] && [ "$nnot0" -eq 0 ] && grep -q '"id":2' "$TMP/m.out" && grep -q '"tools"' "$TMP/m.out" && grep -q '"tools"' "$TMP/m0.out"; then
    ok "M: --mcp under RIPWIRE_MEM_BUDGET_MB=64 does not arm, says so once, and answers initialize + tools/list (rc 0); the default says nothing"
else
    no "M: --mcp: rc $rcm/$rcm0, 'NOT armed' x$nnot (explicit) x$nnot0 (default), tools/list answered: $( grep -c '"tools"' "$TMP/m.out" ); stderr: $( head -c 300 "$TMP/m.err" )"
fi

if [ "$fail" -eq 0 ]; then echo "PASS memceilingcheck"; exit 0; fi
echo "FAIL memceilingcheck"; exit 1
