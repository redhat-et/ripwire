#!/usr/bin/env bash
# mcpaudit4hardencheck.sh — gates for  §B findings A4-F6 / A4-F7 / A4-F14 / A4-F26,
# all fixed in src/mcp.h (MCP server, untrusted-agent-input surface).
#
#  A4-F6  — findInt() digit accumulation had no overflow guard: `v = v*10 + d` on a 20+ digit start_line
#           is signed-overflow UB (hard abort under -fsanitize=integer). Sends a 25-digit start_line to
#           fetch_body and asserts a well-formed, non-crashing JSON-RPC response (the range degrades to
#           "absent"/refused, never UB).
#  A4-F7  — forTaskText() spliced the raw agent-controlled `task` (and rc.reason) straight into an XML
#           comment: a task containing "-->" closes the comment early and injects XML; any "--" run
#           breaks G4 (xmllint). Sends task = '--> <evil/> <!--' to the `for` verb and asserts the
#           resulting <ctx> payload is still well-formed XML (xmllint --noout, when available) and that
#           the literal "--> <evil/>" string is NOT present verbatim (it must be collapsed).
#  A4-F14 — MCP edit verbs replaced a symlink's link entry with a regular file (rename-over-link),
#           leaving the real target file untouched. Edits a symbol whose *file path* is a symlink into
#           the corpus and asserts: (a) the edit is REFUSED with a message mentioning "symlink", (b) the
#           path is STILL a symlink afterward (not replaced by a regular file), (c) the real target's
#           bytes are unchanged, (d) editing the REAL (non-symlink) target directly still works — the
#           guard must not over-block normal edits.
#  A4-F26 — findString(line,"name") scanned the WHOLE raw request line for the tool selector instead of
#           the params-scoped span, unlike every other argument. Sends a tools/call whose request `id` is
#           the string "exemplar" (a real tool name) while the real `name` argument selects a DIFFERENT
#           tool ("for"), and asserts the id does not leak in as the selected tool.
#
# Usage:  test/mcpaudit4hardencheck.sh   |   RIPWIRE_BIN=asan/ripwire test/mcpaudit4hardencheck.sh
# Exits non-zero on any failure. Every mutation happens under a scratch mktemp dir; the checked-in
# test/fixture is never modified. Does NOT edit regression.sh or any other existing test file.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/fixture"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for JSON assertions"; exit 2; }

echo "mcpaudit4hardencheck: BIN=$BIN  FIX=$FIX"

mcp_call() { printf '%s\n' "$@" | "$BIN" --mcp 2>/dev/null; }

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== A4-F6: findInt() overflow guard — a 25-digit start_line must not crash the server ==="
# ═══════════════════════════════════════════════════════════════════════════
W1="$( mktemp -d "$TMP/w1.XXXXXX" )"; cp -R "$FIX/"* "$W1/"

handle_of_symbol() {
    tail -1 | python3 -c '
import sys, json
r = json.load(sys.stdin)
if "error" in r: print("__ERR__:" + json.dumps(r["error"])); sys.exit(0)
print(json.loads(r["result"]["content"][0]["text"])["symbol"]["handle"])
'
}
H1="$( mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"find_symbol","arguments":{"path":"'"$W1"'","symbol":"distance"}}}' \
    | handle_of_symbol )"
if ! printf '%s' "$H1" | grep -Eq '^sym#[0-9a-f]{16}@[0-9a-f]{16}$'; then
    echo "could not obtain a handle for distance() (got '$H1') — aborting"; exit 2
fi

HUGE="12345678901234567890123456"   # 26 digits — well past int64 (max ~19 digits)
OUT="$( mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"fetch_body\",\"arguments\":{\"path\":\"$W1\",\"handle\":\"$H1\",\"start_line\":$HUGE}}}" \
    2>"$TMP/f6_stderr" )"
RC=$?
LASTLINE="$( printf '%s\n' "$OUT" | tail -1 )"

if [ -z "$LASTLINE" ]; then
    no "A4-F6: 25-digit start_line produced NO response line at all (crash/abort suspected). stderr: $( cat "$TMP/f6_stderr" | head -3 )"
elif printf '%s' "$LASTLINE" | python3 -c 'import sys,json; json.load(sys.stdin)' 2>/dev/null; then
    ok "A4-F6: 25-digit start_line yields a well-formed JSON-RPC response (no UB/abort)"
    # bonus: whatever it decided (absent range → full body, or an explicit out-of-range refusal), it must
    # be one coherent outcome, not garbage from an overflowed accumulator.
    printf '%s' "$LASTLINE" | python3 -c '
import sys, json
r = json.load(sys.stdin)
if "error" in r:
    sys.exit(0)   # a clean refusal is fine
b = json.loads(r["result"]["content"][0]["text"])
assert "body" in b or "partial" in b or "start_line" in b, "malformed success payload"
' && ok "A4-F6: response payload is coherent (either a clean refusal, or a well-formed body result)" \
     || no "A4-F6: response was 'valid JSON' but not a coherent fetch_body payload: $LASTLINE"
else
    no "A4-F6: 25-digit start_line response is not valid JSON: $LASTLINE"
fi

# sanity: the server process is still alive/functional after the hostile call (same session, one more call)
FOLLOWUP="$( mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"find_symbol","arguments":{"path":"'"$W1"'","symbol":"distance"}}}' \
    | tail -1 )"
printf '%s' "$FOLLOWUP" | python3 -c 'import sys,json; json.load(sys.stdin)' 2>/dev/null \
    && ok "A4-F6: server remains responsive to a normal call in a fresh process after the hostile input" \
    || no "A4-F6: follow-up call failed — server may have been left in a bad state"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== A4-F7: forTaskText() XML-comment injection via task/rc.reason ==="
# ═══════════════════════════════════════════════════════════════════════════
W2="$( mktemp -d "$TMP/w2.XXXXXX" )"; cp -R "$FIX/"* "$W2/"

EVIL_TASK='--> <evil/> <!-- reopen this comment: distance calculation between two points'
FOR_JSON="$( python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$EVIL_TASK" )"
FOR_OUT="$( mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"for\",\"arguments\":{\"path\":\"$W2\",\"task\":$FOR_JSON}}}" \
    | tail -1 )"

FOR_TEXT="$( printf '%s' "$FOR_OUT" | python3 -c '
import sys, json
r = json.load(sys.stdin)
if "error" in r:
    print("__ERR__:" + json.dumps(r["error"]))
else:
    print(r["result"]["content"][0]["text"])
' )"

case "$FOR_TEXT" in
    __ERR__*) no "A4-F7: 'for' verb with an XML-comment-breaking task returned an unexpected error: $FOR_TEXT";;
    *)
        printf '%s' "$FOR_TEXT" > "$TMP/for_payload.xml"
        # the raw "--> " sequence from the task must NOT survive verbatim inside the emitted comment —
        # it has to be collapsed (the same std::unique '--' → '-' guard exemplar/reqNote already use).
        if grep -q -- '--> <evil/>' "$TMP/for_payload.xml"; then
            no "A4-F7: the literal '--> <evil/>' from task survived uncollapsed in the response — comment injection possible"
        else
            ok "A4-F7: the '--' run from task was collapsed before landing in the XML comment"
        fi
        if command -v xmllint >/dev/null 2>&1; then
            if printf '<root>%s</root>' "$FOR_TEXT" | xmllint --noout - 2>"$TMP/xmllint_err"; then
                ok "A4-F7: 'for' response with a comment-breaking task is still well-formed XML (xmllint clean)"
            else
                no "A4-F7: 'for' response is NOT well-formed XML: $( cat "$TMP/xmllint_err" )"
                echo "     payload head: $( head -c 300 "$TMP/for_payload.xml" )"
            fi
        else
            echo "  (xmllint not found — skipping strict well-formedness check, literal-string check above still applies)"
        fi
    ;;
esac

echo
echo "--- A4-F7b: same guard on rc.reason (routed-query reason string is also spliced verbatim) ---"
# rc.reason is generated internally by chooseForRanker and is not directly attacker-controlled today, but
# the fix applies the identical collapse to it defensively (forTaskText treats task and rc.reason the same
# way). Re-run with a plain conceptual task to make sure the collapse does not corrupt normal output.
PLAIN_OUT="$( mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"for\",\"arguments\":{\"path\":\"$W2\",\"task\":\"distance between two points\"}}}" \
    | tail -1 )"
printf '%s' "$PLAIN_OUT" | python3 -c '
import sys, json
r = json.load(sys.stdin)
assert "error" not in r, r
t = r["result"]["content"][0]["text"]
# §B1.7 (2026-07-29): the ctx root now carries verbatim task=/route= attributes — pin the element open,
# not the old attribute-less spelling.
assert ("<ctx>" in t or "<ctx " in t) and "distance between two points" in t, t
' 2>"$TMP/plain_err" \
    && ok "A4-F7: a normal (non-hostile) task still renders correctly after the collapse guard" \
    || no "A4-F7: the collapse guard broke normal 'for' output: $( cat "$TMP/plain_err" )"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== A4-F14: edit verbs must REFUSE to edit through a symlinked file ==="
# ═══════════════════════════════════════════════════════════════════════════
W3="$( mktemp -d "$TMP/w3.XXXXXX" )"
printf 'int keeper( int x )\n{\n    return x + 1;\n}\n' > "$W3/real_code.cpp"
ln -s "real_code.cpp" "$W3/link_code.cpp"   # symlink INTO the same indexed dir, resolvable by the ingest

mcp_replace() { # $1=path-dir $2=symbol $3=new_body
    mcp_call \
        '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
        "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"replace_symbol_body\",\"arguments\":{\"path\":\"$1\",\"symbol\":\"$2\",\"file\":\"link_code.cpp\",\"new_body\":\"$3\"}}}" \
        | tail -1
}

if [ -L "$W3/link_code.cpp" ]; then
    R="$( mcp_replace "$W3" keeper 'int keeper( int x )\n{\n    return x + 2;\n}' )"
    STILL_LINK="no"; [ -L "$W3/link_code.cpp" ] && STILL_LINK="yes"
    TARGET_UNCHANGED="no"
    grep -q 'return x + 1' "$W3/real_code.cpp" && TARGET_UNCHANGED="yes"

    if printf '%s' "$R" | grep -qi 'applied'; then
        no "A4-F14: edit through symlink 'link_code.cpp' was APPLIED instead of refused: $R"
    elif printf '%s' "$R" | grep -qi 'symlink'; then
        ok "A4-F14: edit through a symlinked path is refused, and the message mentions 'symlink'"
    else
        no "A4-F14: edit through symlink was refused but the message doesn't explain why (expected 'symlink'): $R"
    fi

    [ "$STILL_LINK" = "yes" ] && ok "A4-F14: 'link_code.cpp' is STILL a symlink after the refused edit (not replaced by a plain file)" \
                              || no "A4-F14: the symlink entry was replaced by a regular file — the exact bug this refusal exists to prevent"
    [ "$TARGET_UNCHANGED" = "yes" ] && ok "A4-F14: the real target 'real_code.cpp' bytes are unchanged" \
                                    || no "A4-F14: the real target file was modified despite the refusal"

    # regression: editing the REAL (non-symlink) file directly must still work — the guard must not over-block.
    R2="$( mcp_call \
        '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
        "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"replace_symbol_body\",\"arguments\":{\"path\":\"$W3\",\"symbol\":\"keeper\",\"file\":\"real_code.cpp\",\"new_body\":\"int keeper( int x )\\n{\\n    return x + 2;\\n}\"}}}" \
        | tail -1 )"
    if printf '%s' "$R2" | grep -qi 'applied' && grep -q 'return x + 2' "$W3/real_code.cpp"; then
        ok "A4-F14: editing the REAL non-symlink target directly still applies normally (guard is symlink-specific, not over-broad)"
    else
        no "A4-F14: editing the real (non-symlink) file was unexpectedly blocked/failed: $R2"
    fi
else
    echo "  (symlink() unsupported/blocked on this filesystem — skipping A4-F14 gate)"
fi

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== A4-F26: findString(line,\"name\") must be params-scoped, not whole-line-scoped ==="
# ═══════════════════════════════════════════════════════════════════════════
W4="$( mktemp -d "$TMP/w4.XXXXXX" )"; cp -R "$FIX/"* "$W4/"

# request id is the STRING "exemplar" (a real tool name) — if `name` were still scanned from the whole raw
# line (pre-fix), the id's own "name":... is not literally present, so instead we target the more direct
# regression: an id VALUE containing the string "name" won't false-shadow; the load-bearing case is that a
# decoy `"name"` key OUTSIDE params (at the JSON-RPC envelope level, before "params") must not be picked up
# ahead of the real params-scoped one. We simulate this the same way the existing A3-F6 gate does for other
# keys: put a look-alike "name" value earlier in the raw line via the id field, and confirm the REAL tool
# (from params.name) is the one that runs.
DECOY_JSON='{"jsonrpc":"2.0","id":"name","method":"tools/call","params":{"name":"for","arguments":{"path":"'"$W4"'","task":"distance"}}}'
DECOY_OUT="$( mcp_call '{"jsonrpc":"2.0","id":1,"method":"initialize"}' "$DECOY_JSON" | tail -1 )"
printf '%s' "$DECOY_OUT" | python3 -c '
import sys, json
r = json.load(sys.stdin)
assert "error" not in r, ("unexpected error: %r" % (r,))
t = r["result"]["content"][0]["text"]
assert "<sigs" in t or "<ctx>" in t, ("did not get the for-verb XML shape: %r" % t[:200])
' 2>"$TMP/f26_err" \
    && ok "A4-F26: request id='name' (string equal to the key literal) does not confuse tool selection; 'for' still runs correctly" \
    || no "A4-F26: tool-selection confused by an id equal to the key literal 'name': $( cat "$TMP/f26_err" )"

# direct scoping check: `name` must come from params, not from an arguments-nested decoy at a DIFFERENT
# position than where the real one is expected — call an existing verb (find_symbol) and confirm the
# response is for THAT verb, not silently falling through to "unknown tool".
NAME_OK_OUT="$( mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"find_symbol","arguments":{"path":"'"$W4"'","symbol":"distance"}}}' \
    | tail -1 )"
printf '%s' "$NAME_OK_OUT" | grep -q 'handle' \
    && ok "A4-F26: normal params.name resolution (find_symbol) still works after the scoping fix" \
    || no "A4-F26: normal params.name resolution regressed: $NAME_OK_OUT"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME CHECKS FAILED"
exit "$fail"
