#!/usr/bin/env bash
# test/swiftcheck.sh — S6-B gate: Swift mutating-keyword purity
#
# Verifies that ripwire sets pure="1" on non-mutating struct methods and
# does NOT set it on mutating methods.
#
# Usage:
#   bash test/swiftcheck.sh
#   RIPWIRE_BIN=build/ripwire bash test/swiftcheck.sh
#
# Exits 0 on ALL PASS, 1 on any failure.

set -uo pipefail

BIN="${1:-${RIPWIRE_BIN:-build/ripwire}}"
FIXTURE="test/swiftfix"
PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$(( PASS + 1 )); }
fail() { echo "FAIL: $1"; FAIL=$(( FAIL + 1 )); }

# Run ripwire with --pack-signatures so the <sigs> block is emitted,
# which is where pure="1" appears on each <d> element.
OUTPUT="$( "$BIN" "$FIXTURE" --pack-signatures 2>&1 )"

# Normalise whitespace: replace "> followed by <" with newline so each
# element boundary is its own line — makes single-element grep reliable.
LINES="$( echo "$OUTPUT" | tr -d '\n' | sed 's/></>\n</g' )"

# ---- assertions ----

# 1. pure="1" attribute appears somewhere in the output at all.
if echo "$LINES" | grep -qF 'pure="1"'; then
    pass 'pure="1" attribute is present in output'
else
    fail 'pure="1" attribute is missing from output entirely'
fi

# 2. The <d> element for value() carries pure="1".
#    Structure: <d l="N" pure="1"><doc>…</doc>func value() -> Int</d>
#    After splitting on ><, each <d…> tag appears on its own line followed
#    by the doc and sig text. We look for a <d tag with pure="1" AND
#    "func value" anywhere in the same <d…>…</d> span.
#    Strategy: use Python for robust XML inspection on the single-line blob.
CHECK_PURE_FUNC() {
    local func_sig="$1"
    python3 -c "
import sys, re
output = sys.stdin.read()
# Find every <d ...>...</d> block
for m in re.finditer(r'<d ([^>]*)>(.*?)</d>', output):
    attrs, body = m.group(1), m.group(2)
    # strip inner tags like <doc>…</doc>
    text = re.sub(r'<[^>]+>.*?</[^>]+>', '', body, flags=re.DOTALL)
    text = re.sub(r'&gt;', '>', text)
    text = re.sub(r'&lt;', '<', text)
    text = re.sub(r'&amp;', '&', text)
    text = re.sub(r'&quot;', '\"', text)
    if '$func_sig' in text:
        sys.exit(0 if 'pure=\"1\"' in attrs else 1)
sys.exit(1)
" <<< "$OUTPUT"
}

if CHECK_PURE_FUNC "func value()"; then
    pass 'func value() carries pure="1"'
else
    fail 'func value() does NOT carry pure="1"'
fi

# 3. doubled() signature is marked pure="1"
if CHECK_PURE_FUNC "func doubled()"; then
    pass 'func doubled() carries pure="1"'
else
    fail 'func doubled() does NOT carry pure="1"'
fi

# 4. mutating func increment() must NOT carry pure="1".
CHECK_NOT_PURE_FUNC() {
    local func_sig="$1"
    python3 -c "
import sys, re
output = sys.stdin.read()
for m in re.finditer(r'<d ([^>]*)>(.*?)</d>', output):
    attrs, body = m.group(1), m.group(2)
    text = re.sub(r'<[^>]+>.*?</[^>]+>', '', body, flags=re.DOTALL)
    text = re.sub(r'&gt;', '>', text)
    text = re.sub(r'&lt;', '<', text)
    text = re.sub(r'&amp;', '&', text)
    text = re.sub(r'&quot;', '\"', text)
    if '$func_sig' in text:
        # pure=\"1\" must NOT be present
        sys.exit(1 if 'pure=\"1\"' in attrs else 0)
sys.exit(0)
" <<< "$OUTPUT"
}

if CHECK_NOT_PURE_FUNC "mutating func increment()"; then
    pass 'mutating func increment() correctly lacks pure="1"'
else
    fail 'mutating func increment() incorrectly has pure="1"'
fi

# 5. mutating func reset() must NOT carry pure="1"
if CHECK_NOT_PURE_FUNC "mutating func reset()"; then
    pass 'mutating func reset() correctly lacks pure="1"'
else
    fail 'mutating func reset() incorrectly has pure="1"'
fi

# 6. struct Counter appears in the output (sanity check that the fixture is being parsed)
if echo "$OUTPUT" | grep -qF 'struct Counter'; then
    pass 'struct Counter appears in output (fixture parsed correctly)'
else
    fail 'struct Counter missing from output (fixture not parsed?)'
fi

# 7. determinism: two consecutive runs must be byte-identical
OUT_A="$( "$BIN" "$FIXTURE" --pack-signatures 2>&1 )"
OUT_B="$( "$BIN" "$FIXTURE" --pack-signatures 2>&1 )"
if [ "$OUT_A" = "$OUT_B" ]; then
    pass 'output is byte-identical across two runs (determinism)'
else
    fail 'output differs between runs (non-deterministic)'
fi

# ---- summary ----
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME FAILED"
    exit 1
fi
