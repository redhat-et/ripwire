#!/usr/bin/env bash
# editpayloadbinarycheck.sh — A1: a payload carrying a NUL byte is REFUSED on every edit route, and the
# "not found" a dropped file used to produce now says why.
#
# THE BUG THIS GATE PINS. The edit engine wrote payload bytes verbatim with no text check. A payload with a
# NUL byte therefore applied cleanly: receipt `"applied":"replace_symbol_body"`, exit 0, no warning. On the
# NEXT run the file tripped ingest's own binary sniff, left the index, and took its whole symbol table with
# it — so every later edit to ANY symbol in that file refused with a bare `symbol 'X' not found`, a false
# statement about a tree that still contains X. One silent write, and the file is invisible from then on.
#
# FOUR ARMS, one per route into the engine plus the disclosure:
#   1. CLI  (--edit-payload)          — refuses, names the flag, file byte-identical.
#   2. plan (--edit-plan --dry-run)   — refuses in PREFLIGHT, naming the offending payload path.
#   3. MCP  (replace_symbol_body)     — refuses; this is the arm the CLI check can never reach, because the
#                                       CLI refuses first. Without it the engine-level floor is ungated.
#   4. disclosure — a --edit-target-file hint naming an indexed-but-never-parsed file no longer answers with
#      only "not found" + nearest names; it says the file contributes no symbols, and which file.
#
# Every arm asserts the corpus is byte-identical afterwards: a refusal that writes is not a refusal.
#
# Usage: test/editpayloadbinarycheck.sh [BIN]
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }

echo "editpayloadbinarycheck: BIN=$BIN"

hashcorpus(){ ( cd "$1" && find . -type f -print | LC_ALL=C sort | xargs shasum -a 256 ) | shasum -a 256; }

mkdir -p "$TMP/template"
cat >"$TMP/template/a.py" <<'PY'
def alpha( x ):
    return x + 1


def beta( x ):
    return alpha( x ) * 2
PY

# the payload: valid-looking Python with one NUL byte inside the sniff window.
python3 -c 'open("'"$TMP"'/nulpay","wb").write(b"def alpha( x ):\n    return \x00 99\n")'

echo
echo "=== 1. CLI: --edit-payload with a NUL byte is refused ==="
W1="$TMP/cli"; cp -R "$TMP/template" "$W1"; B1="$( hashcorpus "$W1" )"
if "$BIN" "$W1" --replace-symbol-body=alpha --edit-payload="$TMP/nulpay" >"$TMP/c.out" 2>"$TMP/c.err"; then
    no "CLI accepted a NUL-byte payload"
else
    ok "CLI refuses a NUL-byte payload (non-zero exit)"
fi
grep -q 'NUL byte' "$TMP/c.err" \
    && ok "CLI refusal names the NUL byte" \
    || no "CLI refusal does not name the NUL byte: $( head -1 "$TMP/c.err" )"
grep -q -- '--edit-payload' "$TMP/c.err" \
    && ok "CLI refusal names the flag the bytes arrived through" \
    || no "CLI refusal does not name --edit-payload"
grep -q 'drop it from the index' "$TMP/c.err" \
    && ok "CLI refusal states the consequence (the file would leave the index)" \
    || no "CLI refusal does not state the consequence"
[ "$B1" = "$( hashcorpus "$W1" )" ] \
    && ok "CLI refusal leaves the corpus byte-identical" \
    || no "CLI refusal modified the corpus"

echo
echo "=== 2. edit plan: a NUL-byte payload is refused in preflight ==="
W2="$TMP/plan"; cp -R "$TMP/template" "$W2"
mkdir -p "$TMP/plans"; cp "$TMP/nulpay" "$TMP/plans/nulpay"
cat >"$TMP/plans/p.json" <<'JSON'
{"version":1,"edits":[{"op":"replace_symbol_body","target":"alpha","payload":"nulpay"}]}
JSON
B2="$( hashcorpus "$W2" )"
if "$BIN" "$W2" --edit-plan="$TMP/plans/p.json" --apply >"$TMP/p.out" 2>"$TMP/p.err"; then
    no "edit plan applied a NUL-byte payload"
else
    ok "edit plan refuses a NUL-byte payload (non-zero exit)"
fi
grep -q 'NUL byte' "$TMP/p.err" \
    && ok "plan refusal names the NUL byte" \
    || no "plan refusal does not name the NUL byte: $( head -1 "$TMP/p.err" )"
grep -q 'nulpay' "$TMP/p.err" \
    && ok "plan refusal names the offending payload path" \
    || no "plan refusal does not name the payload path"
[ "$B2" = "$( hashcorpus "$W2" )" ] \
    && ok "plan refusal leaves the corpus byte-identical" \
    || no "plan refusal modified the corpus"

echo
echo "=== 3. MCP: the engine-level floor the CLI arm can never reach ==="
# The CLI refuses before runEditVerb is called, so only an MCP client exercises the engine's own guard.
# A JSON \u0000 escape is the MCP-side spelling of the same byte.
W3="$TMP/mcp"; cp -R "$TMP/template" "$W3"; B3="$( hashcorpus "$W3" )"
python3 - "$W3" >"$TMP/m.req" <<'PY'
import json, sys
w = sys.argv[1]
print(json.dumps({"jsonrpc":"2.0","id":1,"method":"initialize"}))
print(json.dumps({"jsonrpc":"2.0","id":2,"method":"tools/call","params":{
    "name":"replace_symbol_body",
    "arguments":{"path":w,"symbol":"alpha","new_body":"def alpha( x ):\n    return " + chr(0) + " 99\n"}}}))
PY
"$BIN" --mcp <"$TMP/m.req" >"$TMP/m.out" 2>/dev/null
python3 - "$TMP/m.out" >"$TMP/m.verdict" <<'PY'
import json, sys
last = [l for l in open(sys.argv[1], encoding="utf-8") if l.strip()][-1]
r = json.loads(last)
msg = r["error"]["message"] if "error" in r else r.get("result", {}).get("content", [{}])[0].get("text", "")
print(("REFUSED " if "error" in r else "ACCEPTED ") + msg.replace("\n", " "))
PY
grep -q '^REFUSED' "$TMP/m.verdict" \
    && ok "MCP replace_symbol_body refuses a NUL-byte new_body" \
    || no "MCP accepted a NUL-byte new_body: $( head -c 200 "$TMP/m.verdict" )"
grep -q 'NUL byte' "$TMP/m.verdict" \
    && ok "MCP refusal names the NUL byte" \
    || no "MCP refusal does not name the NUL byte"
[ "$B3" = "$( hashcorpus "$W3" )" ] \
    && ok "MCP refusal leaves the corpus byte-identical" \
    || no "MCP refusal modified the corpus"

echo
echo "=== 4. disclosure: a hint naming an indexed-but-never-parsed file says so ==="
W4="$TMP/unmeasured"; cp -R "$TMP/template" "$W4"
python3 -c 'open("'"$W4"'/opaque.py","wb").write(b"def zeta():\n    return \x00\n")'
printf 'def zeta():\n    return 1\n' >"$TMP/goodpay"
"$BIN" "$W4" --replace-symbol-body=zeta --edit-target-file=opaque.py --edit-payload="$TMP/goodpay" \
    >"$TMP/u.out" 2>"$TMP/u.err" && no "edit into a never-parsed file unexpectedly succeeded"
grep -q 'never parsed' "$TMP/u.err" \
    && ok "not-found refusal discloses that the hinted file was never parsed" \
    || no "not-found refusal hides the never-parsed cause: $( head -1 "$TMP/u.err" )"
# the file must be named INSIDE the disclosure clause, not merely echoed back as the hint the caller typed.
grep -q 'resolves:.*opaque\.py' "$TMP/u.err" \
    && ok "disclosure names the file it is talking about" \
    || no "disclosure does not name the file inside its own clause"

# a hint naming a MEASURED file must keep the plain not-found wording — the note is for the real cause only.
"$BIN" "$W4" --replace-symbol-body=nosuchname --edit-target-file=a.py --edit-payload="$TMP/goodpay" \
    >"$TMP/u2.out" 2>"$TMP/u2.err"
grep -q 'never parsed' "$TMP/u2.err" \
    && no "a measured file wrongly gets the never-parsed note" \
    || ok "a measured file keeps the plain not-found wording"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
