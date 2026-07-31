#!/usr/bin/env bash
# mcpredactcheck.sh — gate for A3-F3: the MCP server must redact credential shapes at EVERY body/doc
# emission seam, exactly like the CLI does by default. The MCP server is the HIGHEST-exposure seam —
# its output lands in a cloud LLM context by construction — yet pre-fix it served every body verbatim.
#
# The four seams (audited in AUDIT3_fable2026.md A3-F3), each planted with a DISTINCT fake AWS key
# (AKIA + 16 upper-alnum — the fixed AWS shape kRedactRules[0] matches) so a leak names its seam:
#   1. `for`            — doc comments   (packSignatures <doc> seam)     AKIADOCCOMMENT2AAAAA
#   2. `exemplar`       — def body       (packBodies CDATA seam)         AKIABODYSECRET2AAAAA
#   3. `memory_recall`  — doc full body  (writeRecall seam)              AKIAMEMONOTES2AAAAAA
#   4. `fetch_body`     — def body       (raw JSON body seam)            AKIABODYSECRET2AAAAA
#
# Asserts, for each seam: the raw key does NOT appear in the MCP response AND the deterministic
# "[REDACTED:aws-key]" marker DOES. Then re-runs the two body seams under `--mcp --no-redact` and
# asserts the keys arrive VERBATIM (the escape hatch must keep working — redaction is default-on,
# not always-on). Finally: redaction must not break response validity (every line parses as JSON)
# or determinism (two identical calls byte-identical).
#
# Usage:
#   test/mcpredactcheck.sh
#   RIPWIRE_BIN=asan/ripwire test/mcpredactcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.
# Does NOT edit regression.sh or golden.xml.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for JSON assertions"; exit 2; }

echo "mcpredactcheck: BIN=$BIN"

KEY_DOC="AKIADOCCOMMENT2AAAAA"
KEY_BODY="AKIABODYSECRET2AAAAA"
KEY_MEMO="AKIAMEMONOTES2AAAAAA"
MARKER="[REDACTED:aws-key]"

# ─── fixture: one C++ fn whose DOC COMMENT and BODY each hold a fake key, one markdown memo note ──
REPO="$TMP/repo"
mkdir -p "$REPO"

cat >"$REPO/creds.cpp" <<EOF
// uploadReport: ships the weekly metrics report to the storage bucket.
// fixture credential for the redaction gate: $KEY_DOC
int uploadReport( int rowCount )
{
    const char* accessKeyId = "$KEY_BODY";
    return rowCount + ( accessKeyId != nullptr ? 1 : 0 );
}
EOF

cat >"$REPO/NOTES.md" <<EOF
# memo: storage bucket credentials rotation

The old access key id was $KEY_MEMO — rotate it before the next weekly report upload.
EOF

# ─── helpers ──────────────────────────────────────────────────────────────────────────────────────
mcp_call()        { printf '%s\n' "$@" | "$BIN" --mcp             2>/dev/null; }
mcp_call_noredact(){ printf '%s\n' "$@" | "$BIN" --mcp --no-redact 2>/dev/null; }

# inner text (or __ERROR__:code) of the LAST response line in a capture file.
inner_of() {
    tail -1 "$1" | python3 -c '
import sys, json
r = json.load(sys.stdin)
if "error" in r:
    print("__ERROR__:" + str(r["error"].get("code")))
else:
    print(r["result"]["content"][0]["text"])
'
}

INIT='{"jsonrpc":"2.0","id":1,"method":"initialize"}'

# seam check: capture file, seam label, planted key. Asserts marker present + raw key absent in the
# INNER text (the seam payload), and raw key absent from the RAW response line too (belt-and-braces:
# a leak through a different field of the envelope is still a leak).
assert_masked() {
    local cap="$1" seam="$2" key="$3"
    local inner; inner="$( inner_of "$cap" )"
    case "$inner" in
        __ERROR__*) no "$seam: returned error ${inner#__ERROR__:} (expected a payload)"; return;;
        "")         no "$seam: inner text empty (expected a payload)"; return;;
    esac
    if printf '%s' "$inner" | grep -qF "$key"; then
        no "$seam: raw credential LEAKED verbatim ($key)"
    elif ! printf '%s' "$inner" | grep -qF "$MARKER"; then
        no "$seam: neither the raw key nor the $MARKER marker present — seam did not emit the planted text: $( printf '%s' "$inner" | head -c 200 )"
    else
        ok "$seam: credential masked ($MARKER present, raw key absent)"
    fi
    if tail -1 "$cap" | grep -qF "$key"; then
        no "$seam: raw credential leaked through the response ENVELOPE"
    else
        ok "$seam: raw key absent from the full response line"
    fi
}

# ─── 1. `for` — doc-comment seam ──────────────────────────────────────────────────────────────────
echo
echo "=== 1. for — doc comments redacted (packSignatures <doc> seam) ==="
FOR_MSGS=( "$INIT" '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"for","arguments":{"path":"'"$REPO"'","task":"upload the weekly metrics report"}}}' )
mcp_call "${FOR_MSGS[@]}" >"$TMP/for_a"
mcp_call "${FOR_MSGS[@]}" >"$TMP/for_b"
assert_masked "$TMP/for_a" "for(doc comment)" "$KEY_DOC"
diff -q "$TMP/for_a" "$TMP/for_b" >/dev/null && ok "for: deterministic with redaction active" || no "for: non-deterministic with redaction active"

# ─── 2. exemplar — def-body seam ──────────────────────────────────────────────────────────────────
echo
echo "=== 2. exemplar — def body redacted (packBodies CDATA seam) ==="
EX_MSGS=( "$INIT" '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"exemplar","arguments":{"path":"'"$REPO"'","kind":"fn"}}}' )
mcp_call "${EX_MSGS[@]}" >"$TMP/ex_a"
assert_masked "$TMP/ex_a" "exemplar(body)" "$KEY_BODY"

# ─── 3. memory_recall — doc-body seam ─────────────────────────────────────────────────────────────
echo
echo "=== 3. memory_recall — recalled note redacted (writeRecall seam) ==="
RC_MSGS=( "$INIT" '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"memory_recall","arguments":{"path":"'"$REPO"'","task":"storage bucket credentials rotation memo"}}}' )
mcp_call "${RC_MSGS[@]}" >"$TMP/rc_a"
assert_masked "$TMP/rc_a" "memory_recall(note body)" "$KEY_MEMO"

# ─── 4. fetch_body — handle-addressed body seam ───────────────────────────────────────────────────
echo
echo "=== 4. fetch_body — handle-addressed body redacted (raw JSON seam) ==="
mcp_call "$INIT" '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"find_symbol","arguments":{"path":"'"$REPO"'","symbol":"uploadReport"}}}' >"$TMP/fs_a"
HANDLE="$( tail -1 "$TMP/fs_a" | python3 -c '
import sys, json
r = json.load(sys.stdin)
if "error" in r: print(""); sys.exit(0)
print(json.loads(r["result"]["content"][0]["text"])["symbol"]["handle"])
' )"
if [ -z "$HANDLE" ]; then
    no "fetch_body: could not obtain a handle from find_symbol"
else
    ok "fetch_body: obtained handle $HANDLE"
    FB_MSGS=( "$INIT" '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"fetch_body","arguments":{"path":"'"$REPO"'","handle":"'"$HANDLE"'"}}}' )
    mcp_call "${FB_MSGS[@]}" >"$TMP/fb_a"
    mcp_call "${FB_MSGS[@]}" >"$TMP/fb_b"
    assert_masked "$TMP/fb_a" "fetch_body(body)" "$KEY_BODY"
    diff -q "$TMP/fb_a" "$TMP/fb_b" >/dev/null && ok "fetch_body: deterministic with redaction active" || no "fetch_body: non-deterministic with redaction active"
fi

# ─── 5. --no-redact escape hatch — keys arrive VERBATIM ───────────────────────────────────────────
echo
echo "=== 5. --mcp --no-redact — the escape hatch serves bodies verbatim ==="
mcp_call_noredact "${EX_MSGS[@]}" >"$TMP/ex_raw"
EX_RAW_INNER="$( inner_of "$TMP/ex_raw" )"
printf '%s' "$EX_RAW_INNER" | grep -qF "$KEY_BODY" \
    && ok "exemplar --no-redact: body verbatim (raw key present)" \
    || no "exemplar --no-redact: raw key MISSING (redaction is always-on, not default-on): $( printf '%s' "$EX_RAW_INNER" | head -c 200 )"

if [ -n "$HANDLE" ]; then
    mcp_call_noredact "${FB_MSGS[@]}" >"$TMP/fb_raw"
    FB_RAW_INNER="$( inner_of "$TMP/fb_raw" )"
    printf '%s' "$FB_RAW_INNER" | grep -qF "$KEY_BODY" \
        && ok "fetch_body --no-redact: body verbatim (raw key present)" \
        || no "fetch_body --no-redact: raw key MISSING (redaction is always-on, not default-on)"
fi

mcp_call_noredact "${RC_MSGS[@]}" >"$TMP/rc_raw"
printf '%s' "$( inner_of "$TMP/rc_raw" )" | grep -qF "$KEY_MEMO" \
    && ok "memory_recall --no-redact: note verbatim (raw key present)" \
    || no "memory_recall --no-redact: raw key MISSING (redaction is always-on, not default-on)"

# ─── 6. protocol hygiene — every response line is valid JSON (redaction never corrupts the wire) ──
echo
echo "=== 6. every response line valid JSON with redaction active ==="
JSONBAD=0
for f in "$TMP/for_a" "$TMP/ex_a" "$TMP/rc_a" "$TMP/fb_a"; do
    [ -f "$f" ] || continue
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        printf '%s' "$line" | python3 -c 'import sys,json;json.load(sys.stdin)' 2>/dev/null || JSONBAD=1
    done <"$f"
done
[ "$JSONBAD" -eq 0 ] && ok "all redacted response lines parse as JSON" || no "a redacted response line is NOT valid JSON"

# ─── Summary ──────────────────────────────────────────────────────────────────────────────────────
echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
