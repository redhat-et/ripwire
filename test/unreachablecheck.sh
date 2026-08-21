#!/usr/bin/env bash
# unreachablecheck.sh — gate for the built-in "unreachable-code" lint rule (joern-lite CFG sketch).
# A pure-syntactic intra-block check: code after an unconditional exit (return/break/continue/throw,
# +Python raise) in the SAME block is dead. Asserts:
#   1. determinism — --lint run twice is byte-identical
#   2. fires on the MUST-flag cases (return/throw/break in C++, return/raise in Python)
#   3. the enclosing symbol + line are correct
#   4. does NOT fire on the false-positive traps (if-guarded return, last return, goto, comment)
#   5. xmllint-clean output
#   6. golden-neutral — the default map (no --lint) is byte-identical to test/golden.xml
#   7. mutation-tested — flip the if-guard `return` into a same-block terminator and prove the
#      false-positive guard would then fire (i.e. the guard is doing real work, not passing vacuously)
#
#   RIPWIRE_BIN=build/ripwire bash test/unreachablecheck.sh
#   RIPWIRE_BIN=asan/ripwire  bash test/unreachablecheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
CORPUS="$ROOT/test/unreachablefix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ]    || { echo "no ripwire binary at $BIN — build first"; exit 2; }
[ -d "$CORPUS" ] || { echo "no test/unreachablefix dir — fixture missing"; exit 2; }

echo "unreachablecheck: BIN=$BIN  CORPUS=$CORPUS"
cd "$ROOT"   # so paths in the XML are repo-relative (matches golden.xml + fixture line refs)

# Run against the repo-relative corpus path so p="…" attrs are repo-relative (stable across machines).
CORPUS_REL="test/unreachablefix"

# 1. determinism — the raw minified XML must be byte-identical run-to-run.
"$BIN" "$CORPUS_REL" --lint --no-cache >"$TMP/raw1" 2>/dev/null
"$BIN" "$CORPUS_REL" --lint --no-cache >"$TMP/raw2" 2>/dev/null
diff -q "$TMP/raw1" "$TMP/raw2" >/dev/null && ok "deterministic (byte-identical run-to-run)" \
    || { no "non-deterministic output"; diff "$TMP/raw1" "$TMP/raw2" | head -8; }

# The map XML is single-line/minified — pretty-print so per-finding greps see one <f …> per line.
xmllint --format "$TMP/raw1" >"$TMP/out1" 2>/dev/null || cp "$TMP/raw1" "$TMP/out1"
OUT="$TMP/out1"

# 2. the rule fires
grep -q 'rule="unreachable-code"' "$OUT" && ok "rule fires (rule=\"unreachable-code\")" || no "rule NOT found in output"

# exactly 5 MUST-flag findings (C++: return/throw/break; Python: return/raise)
CNT="$( grep -o 'rule="unreachable-code"' "$OUT" | wc -l | tr -d ' ' )"
[ "$CNT" = "5" ] && ok "fires on exactly 5 dead statements (got $CNT)" || no "expected 5 findings, got $CNT"

# 3. enclosing symbol + line correct for each MUST-flag case
grep -q 'p="dead.cpp:8" in="afterReturn"'  "$OUT" && ok "flags stmt after return (afterReturn, dead.cpp:8)"      || no "afterReturn dead stmt NOT flagged at line 8"
grep -q 'p="dead.cpp:25" in="afterThrow"'  "$OUT" && ok "flags stmt after throw (afterThrow, dead.cpp:25)"        || no "afterThrow dead stmt NOT flagged at line 25"
grep -q 'p="dead.cpp:34" in="afterBreak"'  "$OUT" && ok "flags stmt after break (afterBreak, dead.cpp:34)"        || no "afterBreak dead stmt NOT flagged at line 34"
grep -q 'p="dead.py:7" in="after_return"'  "$OUT" && ok "flags stmt after return (Python after_return, dead.py:7)" || no "Python after_return dead stmt NOT flagged at line 7"
grep -q 'p="dead.py:13" in="after_raise"'  "$OUT" && ok "flags stmt after raise (Python after_raise, dead.py:13)"  || no "Python after_raise dead stmt NOT flagged at line 13"

# 4. FALSE-POSITIVE GUARDS — these must NEVER appear as unreachable-code findings.
# grab only the unreachable-code finding lines, then assert the trap symbols are absent.
grep 'rule="unreachable-code"' "$OUT" >"$TMP/urf" || true
gp(){ grep -q "$1" "$TMP/urf"; }
gp 'in="guardedReturn"'      && no "FALSE POSITIVE: guardedReturn (if-guarded return) flagged"          || ok "if-guarded return NOT flagged (guardedReturn)"
gp 'in="lastReturn"'         && no "FALSE POSITIVE: lastReturn (return is last stmt) flagged"           || ok "trailing return NOT flagged (lastReturn)"
gp 'in="withGoto"'           && no "FALSE POSITIVE: withGoto (goto excluded) flagged"                   || ok "goto excluded — withGoto NOT flagged"
gp 'in="commentAfterReturn"' && no "FALSE POSITIVE: commentAfterReturn (comment isn't code) flagged"    || ok "comment after return NOT flagged (commentAfterReturn)"
gp 'in="guarded_return"'     && no "FALSE POSITIVE: Python guarded_return flagged"                      || ok "Python if-guarded return NOT flagged (guarded_return)"
gp 'in="last_return"'        && no "FALSE POSITIVE: Python last_return flagged"                         || ok "Python trailing return NOT flagged (last_return)"

# 5. xmllint-clean
"$BIN" "$CORPUS_REL" --lint --no-cache 2>/dev/null | xmllint --noout - 2>/dev/null \
    && ok "xmllint clean" || no "xmllint reported malformed XML"

# 6. golden-neutral — the DEFAULT map (no --lint) must be byte-identical to golden.xml
if [ -f "$ROOT/test/golden.xml" ]; then
    "$BIN" test/fixture --no-cache 2>/dev/null | diff -q - "$ROOT/test/golden.xml" >/dev/null \
        && ok "golden-neutral: default map byte-identical to test/golden.xml" \
        || no "default map drifted from golden.xml — unreachable-code leaked into the default map"
else
    ok "golden.xml absent — default-map neutral check skipped"
fi

# 7. MUTATION TEST — prove the false-positive guard is load-bearing.
# guardedReturn currently has its `return -1;` INSIDE an if-branch (reachable sibling below).
# Rewrite it so the return sits directly in the function block, ABOVE a statement — then the
# now-dead statement MUST be flagged. If the mutant is NOT flagged, our block-scan is inert.
if [ "$fail" = "0" ]; then
    MUT="$TMP/mutant"; mkdir -p "$MUT"
    cat >"$MUT/m.cpp" <<'EOF'
int guardedReturn( int x )
{
    return -1;
    int reachable = x * 2;
    return reachable;
}
EOF
    "$BIN" "$MUT" --lint --no-cache 2>/dev/null | xmllint --format - 2>/dev/null >"$TMP/mout" || true
    grep 'rule="unreachable-code"' "$TMP/mout" | grep -q 'in="guardedReturn"' \
        && ok "mutation test: moving return out of the if-branch makes the dead stmt flag (guard is active)" \
        || no "mutation test: same-block dead stmt NOT flagged — the block scan is inert"
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
