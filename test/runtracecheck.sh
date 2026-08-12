#!/usr/bin/env bash
# runtracecheck.sh — gate for --run-trace="CMD" (VT-1): the exec-mode entry of the --from-trace family.
# An agent's fix loop today is three steps: run the build/test via its own shell, read the (possibly huge)
# output, paste the error into --from-trace. --run-trace collapses that to ONE call: ripwire executes CMD
# under `sh -c` (the make trust model — user privileges, inherited environment, stdin=/dev/null, NO
# sandbox), captures stdout+stderr interleaved, and on failure serves the EXISTING from-trace bundle
# (frames mapped innermost-first + the innermost in-corpus symbol's full body) PLUS a token-frugal
# <lines> view of the trace-relevant output lines. On exit 0 it emits a minimal success record and says
# plainly there is nothing to map — no bundle for a passing command.
#
# Arms, per the pre-registered contract (gate written BEFORE the code, red vs the pre-change binary):
#   (B)  failing-compile fixture: a canned clang diagnostic on stderr + exit 1 maps rank-1 to the
#        responsible symbol (badcall), serves its body, and the <lines view="relevant"> cut carries the
#        primary diagnostic; ripwire exits 4 (command failed, report served)
#   (C)  passing command: exit="0" minimal record + <lines view="tail">, NO <trace>/<sigs>/<bodies>, and
#        the legend says plainly there is nothing to map; ripwire exits 0
#   (D)  timeout: sleep under a tiny --run-timeout cap reports timed_out="1" + the cap, NEVER an empty
#        success; ripwire exits 4
#   (E)  nonexistent command: sh's own exit 127 disclosed honestly, the "not found" line surfaced
#   (F)  failure with NO mappable frames: still a full report (run record + lines), frames="0" disclosed,
#        never a refusal
#   (G)  determinism, honestly scoped: the <run> record is MEASURED (duration_ms) and declared so; with
#        duration_ms normalized, a fixed-output command yields byte-identical documents x2 — and the
#        MAPPER itself (--from-trace on the captured text) is byte-deterministic x2 unnormalized
#   (H)  exit-code disclosure: every emitted document above carries exit= or timed_out= on <run>
#   (I)  --run-trace= (empty value) refuses loudly (table machinery)
#   (J)  --run-timeout alone refuses loudly, naming both flags (modifier-alone contract)
#   (K)  G4: every surface pipes clean through xmllint, and no newline lives outside CDATA
#
# Operates on a private temp tree (never touches the real repo). No git needed.
# Usage:  test/runtracecheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/runtracecheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # make BIN absolute BEFORE we cd away
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "runtracecheck: xmllint required"; exit 2; }

WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/src" "$WORK/traces" "$WORK/out"

# ── fixture tree: one C++ file with a symbol at a KNOWN span (same shape tracecheck.sh uses) ────────────
cat > "$WORK/src/parser.cpp" <<'EOF'
struct Bar {};

int badcall() {
    Bar b;
    return b.foo();
}
EOF

# the canned clang diagnostic the failing "compile" prints — line 5 sits inside badcall's span
cat > "$WORK/traces/clang.txt" <<'EOF'
src/parser.cpp:5:14: error: no member named 'foo' in 'Bar'
    return b.foo();
       ~ ^
1 error generated.
EOF

# presence guards (§2: a gate must observe what it asserts before asserting the property)
[ -s "$WORK/src/parser.cpp" ] && [ -s "$WORK/traces/clang.txt" ] \
    && ok "(A) fixture tree + canned diagnostic exist" \
    || { no "(A) fixture missing — nothing below can assert anything"; echo "FAILURES ABOVE"; exit 1; }

# no-newline-outside-CDATA helper (G4). Strips CDATA sections, then counts surviving newlines.
newlinesOutsideCdata()
{
    python3 - "$1" <<'PY'
import re, sys
t = open( sys.argv[1], "rb" ).read().decode( "utf-8", "replace" )
t = re.sub( r"<!\[CDATA\[.*?\]\]>", "", t, flags = re.S )
print( t.count( "\n" ) )
PY
}

# ── (B) the failing "compile": canned diagnostic on stderr, exit 1 ──────────────────────────────────────
"$BIN" "$WORK" --run-trace="cat $WORK/traces/clang.txt >&2; exit 1" >"$WORK/out/fail.xml" 2>"$WORK/out/fail.err"
rcB=$?
[ "$rcB" = 4 ] && ok "(B) failing command: ripwire exits 4 (command failed, report served)" \
              || no "(B) failing command: expected exit 4, got $rcB"
grep -q '<run [^>]*exit="1"' "$WORK/out/fail.xml" \
    && ok "(B) the command's own exit code (1) is disclosed on <run>" \
    || no "(B) <run exit=\"1\"> missing — the exit code is not disclosed"
# presence guard: a bundle must exist before rank-1 identity means anything
grep -q '<trace ' "$WORK/out/fail.xml" \
    && ok "(B) the from-trace bundle (<trace>) is served on failure" \
    || no "(B) no <trace> block — the failure did not reach the mapper"
grep -q '<frame rank="1" n="badcall"' "$WORK/out/fail.xml" \
    && ok "(B) rank 1 = badcall (the diagnostic's responsible symbol)" \
    || no "(B) rank-1 frame is not badcall"
grep -q '<bodies' "$WORK/out/fail.xml" \
    && ok "(B) the innermost in-corpus symbol's body is served" \
    || no "(B) no <bodies> section in the failure bundle"
grep -q '<lines view="relevant"' "$WORK/out/fail.xml" \
    && ok "(B) the token-frugal <lines view=\"relevant\"> cut is present" \
    || no "(B) no <lines view=\"relevant\"> block"
grep -q "no member named" "$WORK/out/fail.xml" \
    && ok "(B) the compiler's primary diagnostic line survives the cut" \
    || no "(B) the primary diagnostic did not survive into <lines>"
grep -q 'timeout_s="' "$WORK/out/fail.xml" \
    && ok "(B) the timeout cap is disclosed in the document" \
    || no "(B) timeout_s= missing from the failure document"

# ── (C) the passing command: minimal record, NO bundle ─────────────────────────────────────────────────
"$BIN" "$WORK" --run-trace="echo alpha; echo beta" >"$WORK/out/pass.xml" 2>"$WORK/out/pass.err"
rcC=$?
[ "$rcC" = 0 ] && ok "(C) passing command: ripwire exits 0" \
              || no "(C) passing command: expected exit 0, got $rcC"
grep -q '<run [^>]*exit="0"' "$WORK/out/pass.xml" \
    && ok "(C) exit=\"0\" disclosed on the success record" \
    || no "(C) success record does not disclose exit=\"0\""
if grep -q '<trace \|<sigs\|<bodies' "$WORK/out/pass.xml"; then
    no "(C) a passing command must NOT be served a trace bundle"
else
    ok "(C) no bundle on success (nothing failed, nothing to map)"
fi
grep -qi 'nothing to map' "$WORK/out/pass.xml" \
    && ok "(C) the document says plainly there is nothing to map" \
    || no "(C) missing the plain 'nothing to map' statement"
grep -q '<lines view="tail"' "$WORK/out/pass.xml" && grep -q 'beta' "$WORK/out/pass.xml" \
    && ok "(C) the disclosed tail carries the output's last lines" \
    || no "(C) <lines view=\"tail\"> with the last output lines missing"

# ── (D) timeout: a tiny cap, a long sleep — TIMEOUT reported honestly ──────────────────────────────────
"$BIN" "$WORK" --run-trace="sleep 30" --run-timeout=1 >"$WORK/out/tmo.xml" 2>"$WORK/out/tmo.err"
rcD=$?
[ "$rcD" = 4 ] && ok "(D) timed-out command: ripwire exits 4" \
              || no "(D) timed-out command: expected exit 4, got $rcD"
grep -q 'timed_out="1"' "$WORK/out/tmo.xml" \
    && ok "(D) timed_out=\"1\" disclosed (never an empty success)" \
    || no "(D) timeout not disclosed as timed_out=\"1\""
grep -q 'timeout_s="1"' "$WORK/out/tmo.xml" \
    && ok "(D) the overridden cap (timeout_s=\"1\") is disclosed" \
    || no "(D) the cap in force is not disclosed"
grep -q 'exit="0"' "$WORK/out/tmo.xml" \
    && no "(D) a timed-out run must not carry exit=\"0\"" \
    || ok "(D) no false exit=\"0\" on the timed-out record"

# ── (E) nonexistent command: sh's 127 disclosed, the shell's own line surfaced ─────────────────────────
"$BIN" "$WORK" --run-trace="rw_no_such_cmd_x9" >"$WORK/out/miss.xml" 2>"$WORK/out/miss.err"
rcE=$?
[ "$rcE" = 4 ] && ok "(E) nonexistent command: ripwire exits 4 (the failure is the command's)" \
              || no "(E) nonexistent command: expected exit 4, got $rcE"
grep -q '<run [^>]*exit="127"' "$WORK/out/miss.xml" \
    && ok "(E) sh's exit 127 disclosed honestly" \
    || no "(E) exit=\"127\" missing from the record"
grep -q 'not found' "$WORK/out/miss.xml" \
    && ok "(E) the shell's 'not found' line is surfaced in <lines>" \
    || no "(E) the 'not found' diagnostic did not surface"

# ── (F) failure with no mappable frames: a full report, never a refusal ────────────────────────────────
"$BIN" "$WORK" --run-trace="echo plain failure with no frames; exit 3" >"$WORK/out/bare.xml" 2>"$WORK/out/bare.err"
rcF=$?
[ "$rcF" = 4 ] && ok "(F) frameless failure: ripwire exits 4 with a report" \
              || no "(F) frameless failure: expected exit 4, got $rcF"
grep -q '<run [^>]*exit="3"' "$WORK/out/bare.xml" \
    && ok "(F) exit=\"3\" disclosed" \
    || no "(F) exit=\"3\" missing"
grep -q 'frames="0"' "$WORK/out/bare.xml" \
    && ok "(F) frames=\"0\" disclosed — no mappable frames is stated, not hidden" \
    || no "(F) frames=\"0\" disclosure missing"
grep -q 'plain failure with no frames' "$WORK/out/bare.xml" \
    && ok "(F) the captured lines still reach the reader" \
    || no "(F) the captured output vanished from the frameless report"

# ── (G) determinism, honestly scoped ───────────────────────────────────────────────────────────────────
"$BIN" "$WORK" --run-trace="cat $WORK/traces/clang.txt >&2; exit 1" >"$WORK/out/fail2.xml" 2>/dev/null
sed -E 's/duration_ms="[0-9]+"/duration_ms="X"/' "$WORK/out/fail.xml"  >"$WORK/out/norm1"
sed -E 's/duration_ms="[0-9]+"/duration_ms="X"/' "$WORK/out/fail2.xml" >"$WORK/out/norm2"
if diff -q "$WORK/out/norm1" "$WORK/out/norm2" >/dev/null; then
    ok "(G) fixed-output command x2: byte-identical once the MEASURED duration_ms is normalized"
else
    no "(G) two runs of a fixed-output command differ beyond duration_ms"
fi
grep -q 'duration_ms=' "$WORK/out/fail.xml" \
    && ok "(G) duration_ms present (the measured half of the record)" \
    || no "(G) duration_ms missing from <run>"
grep -qi 'measured' "$WORK/out/fail.xml" \
    && ok "(G) the document declares which part is measured vs deterministic" \
    || no "(G) no measured-vs-deterministic declaration in the legend"
# the mapper itself: the SAME captured text through --from-trace is byte-deterministic, unnormalized
"$BIN" "$WORK" --from-trace="$WORK/traces/clang.txt" >"$WORK/out/map1" 2>/dev/null
"$BIN" "$WORK" --from-trace="$WORK/traces/clang.txt" >"$WORK/out/map2" 2>/dev/null
if [ -s "$WORK/out/map1" ] && diff -q "$WORK/out/map1" "$WORK/out/map2" >/dev/null; then
    ok "(G) the mapping of a fixed trace text is byte-deterministic x2"
else
    no "(G) --from-trace on the captured text is not byte-deterministic"
fi

# ── (H) exit-code disclosure on EVERY document ─────────────────────────────────────────────────────────
for doc in fail pass tmo miss bare; do
    if grep -q '<run [^>]*\(exit="[0-9]*"\|timed_out="1"\)' "$WORK/out/$doc.xml"; then
        ok "(H) $doc.xml discloses the command's exit (or timeout)"
    else
        no "(H) $doc.xml has no exit/timeout disclosure on <run>"
    fi
done

# ── (I) empty value refuses loudly ─────────────────────────────────────────────────────────────────────
"$BIN" "$WORK" --run-trace= >"$WORK/out/empty.out" 2>"$WORK/out/empty.err"
rcI=$?
if [ "$rcI" != 0 ] && [ ! -s "$WORK/out/empty.out" ] && grep -q 'run-trace' "$WORK/out/empty.err"; then
    ok "(I) --run-trace= refuses loudly (exit $rcI, flag named, stdout empty)"
else
    no "(I) --run-trace= did not refuse loudly (exit $rcI)"
fi

# ── (J) the modifier alone refuses loudly, naming both flags ───────────────────────────────────────────
"$BIN" "$WORK" --run-timeout=5 >"$WORK/out/alone.out" 2>"$WORK/out/alone.err"
rcJ=$?
if [ "$rcJ" != 0 ] && grep -q 'run-timeout' "$WORK/out/alone.err" && grep -q 'run-trace' "$WORK/out/alone.err"; then
    ok "(J) --run-timeout alone refuses loudly and names both flags"
else
    no "(J) --run-timeout alone did not refuse naming both flags (exit $rcJ)"
fi

# ── (K) G4 on every surface: xmllint-clean, no newline outside CDATA ───────────────────────────────────
for doc in fail pass tmo miss bare; do
    if xmllint --noout "$WORK/out/$doc.xml" 2>/dev/null; then
        ok "(K) $doc.xml is well-formed XML"
    else
        no "(K) $doc.xml fails xmllint"
    fi
    NL="$( newlinesOutsideCdata "$WORK/out/$doc.xml" )"
    if [ "${NL:-1}" = 0 ]; then
        ok "(K) $doc.xml carries no newline outside CDATA"
    else
        no "(K) $doc.xml has ${NL:-?} newlines outside CDATA"
    fi
done

echo
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
