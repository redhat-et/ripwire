#!/usr/bin/env bash
# mcpverbscheck.sh — gate for the `for` and `owners` MCP verbs, plus (§6, L4) the
# explore/pack_task/from_trace/edit_check B11-verb-parity MCP twins.
#
# Drives the MCP server via newline-delimited JSON-RPC over stdin, just like
# the existing situdiffcheck.sh gate.  Flow:
#   1. initialize
#   2. tools/list → assert `for` and `owners` appear in the tool listing
#   3. tools/call for  {path, task} → assert non-empty text result containing <sigs>
#   4. tools/call owners {path}     → assert valid owners XML (uses a synthetic git repo)
#   5. Determinism: call sequences 3 and 4 each run twice and produce byte-identical output.
#   6. L4: tools/list shows 31 verbs (`pack_task` dispatch-only, not separately advertised);
#      `explore` round-trips a pack-task-shaped bundle and is byte-identical to `pack_task`;
#      `from_trace` maps a fixture trace onto zoomfix's appMain; `edit_check` returns the
#      contract shape and refuses an unknown symbol; each of explore/pack_task/from_trace/
#      edit_check gives its own per-verb "missing required field" message (D3 convention).
#   7. @FILE:LINE line-seeds: the 9 @-capable verbs advertise the spelling in tools/list;
#      find_symbol/impact/uses resolve a seed; a faulted seed carries the shared at-diagnosis
#      (selectorrefuse.h::atSeedFaultClause) through the MCP refusal; a scan verb (mentions)
#      refuses a resolvable seed by naming the definition it resolves to.
#
# The owners call needs a real git repo with commit history so gitFileAuthors() has
# something to mine.  We reuse the same synthetic-repo construction pattern as
# ownerscheck.sh (two source files, controlled commits).
#
# The `for`/L4 calls use the zoomfix fixture corpus (the same one situdiffcheck uses) so
# we don't need to create extra fixtures.
#
# Usage:
#   test/mcpverbscheck.sh                          # uses build/ripwire
#   RIPWIRE_BIN=asan/ripwire test/mcpverbscheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.
# Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
CORPUS="$ROOT/test/zoomfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for JSON assertions"; exit 2; }

echo "mcpverbscheck: BIN=$BIN  CORPUS=$CORPUS"

# ─── helpers ─────────────────────────────────────────────────────────────────

# Send JSON-RPC messages to the MCP server; print all output lines.
mcp_call() {
    printf '%s\n' "$@" | "$BIN" --mcp 2>/dev/null
}

# ─── 1. Build a synthetic git repo for owners tests ──────────────────────────
REPO="$TMP/testrepo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email "setup@x.com"
git -C "$REPO" config user.name  "Setup"

cat >"$REPO/file1.cpp" <<'EOF'
// file1.cpp — minimal parseable C++
void hello() {}
void world() { hello(); }
EOF

cat >"$REPO/file2.cpp" <<'EOF'
// file2.cpp — another minimal parseable C++
void alpha() {}
void beta() { alpha(); }
EOF

commit_file() {
    local file="$1" name="$2" email="$3" ts="$4" msg="$5"
    git -C "$REPO" add "$file"
    GIT_AUTHOR_NAME="$name"    GIT_AUTHOR_EMAIL="$email"    GIT_AUTHOR_DATE="$ts" \
    GIT_COMMITTER_NAME="$name" GIT_COMMITTER_EMAIL="$email" GIT_COMMITTER_DATE="$ts" \
        git -C "$REPO" commit -q -m "$msg"
}

# file1.cpp: 5 recent commits by alice (recent = within last 30 days)
for i in 1 2 3 4 5; do
    echo "// alice $i" >>"$REPO/file1.cpp"
    commit_file file1.cpp "Alice" "alice@x.com" "2026-06-0${i}T12:00:00" "file1 alice $i"
done

# file2.cpp: 2 commits each from alice and bob (even split)
for i in 1 2; do
    echo "// alice f2 $i" >>"$REPO/file2.cpp"
    commit_file file2.cpp "Alice" "alice@x.com" "2026-06-1${i}T12:00:00" "file2 alice $i"
    echo "// bob f2 $i" >>"$REPO/file2.cpp"
    commit_file file2.cpp "Bob" "bob@x.com" "2026-06-1${i}T13:00:00" "file2 bob $i"
done

echo
echo "=== 2. tools/list — assert 'for' and 'owners' appear ==="

LIST_OUT="$( mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | tail -1 )"

# Extract tool names from the JSON response using python3
python3 -c '
import sys, json
resp = json.loads('"'"''"'"' + sys.argv[1] + '"'"''"'"')
if "error" in resp:
    print("ERROR:" + json.dumps(resp["error"]))
    sys.exit(0)
names = [t["name"] for t in resp["result"]["tools"]]
has_for    = "for"    in names
has_owners = "owners" in names
print("FOR_OK"    if has_for    else "MISSING:for")
print("OWNERS_OK" if has_owners else "MISSING:owners")
print("NAMES:" + ",".join(names))
' "$LIST_OUT" >"$TMP/list_check"

if grep -q "FOR_OK" "$TMP/list_check"; then
    ok "tools/list: 'for' tool is listed"
else
    no "tools/list: 'for' tool is MISSING from listing"
fi

if grep -q "OWNERS_OK" "$TMP/list_check"; then
    ok "tools/list: 'owners' tool is listed"
else
    no "tools/list: 'owners' tool is MISSING from listing"
fi

echo
echo "=== 3. tools/call 'for' — task lens against zoomfix corpus ==="

FOR_MSGS=(
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}'
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"for","arguments":{"path":"'"$CORPUS"'","task":"engine scheduling run loop"}}}'
)

mcp_call "${FOR_MSGS[@]}" >"$TMP/for_a"
mcp_call "${FOR_MSGS[@]}" >"$TMP/for_b"

# Extract inner text from the tools/call response (id=2, last line)
FOR_INNER="$( tail -1 "$TMP/for_a" | python3 -c '
import sys, json
r = json.load(sys.stdin)
if "error" in r:
    print("__ERROR__:" + json.dumps(r["error"]))
else:
    print(r["result"]["content"][0]["text"])
' )"

case "$FOR_INNER" in
    __ERROR__*) no "for verb returned error: ${FOR_INNER#__ERROR__:}";;
    "")         no "for verb: inner text is empty";;
    *)          ok "for verb: returned non-empty text result";;
esac

# Assert the result contains <sigs> — the core element that packSignatures emits
if echo "$FOR_INNER" | grep -q "<sigs>"; then
    ok "for verb: result contains <sigs> element"
else
    no "for verb: result does NOT contain <sigs> — got: $( echo "$FOR_INNER" | head -c 200 )"
fi

# A3-F1 gate: <sigs> must carry an actual signature PAYLOAD — at least one <f> file bucket holding a
# <d> declaration block. The 0-budget sentinel bug emitted a bare <sigs></sigs> (rank/fanIn computed,
# then discarded by the immediate budget break), and the presence-only grep above still passed.
if echo "$FOR_INNER" | grep -q "<sigs><f " && echo "$FOR_INNER" | grep -q "<d "; then
    ok "for verb: <sigs> is NON-EMPTY (has <f>/<d> signature blocks — A3-F1)"
else
    no "for verb: <sigs> is EMPTY (no <f>/<d> payload — A3-F1 0-budget sentinel) — got: $( echo "$FOR_INNER" | head -c 200 )"
fi

# Assert the result wraps in <ctx>
# §B1.7 (2026-07-29): the ctx root now carries task=/route= attributes (verbatim task echo) — match the
# element opening, not the old bare "<ctx>" spelling.
if echo "$FOR_INNER" | grep -qE "<ctx( |>)"; then
    ok "for verb: result wrapped in <ctx>"
else
    no "for verb: result missing <ctx> wrapper"
fi

# Determinism: two runs byte-identical
diff -q "$TMP/for_a" "$TMP/for_b" >/dev/null \
    && ok "for verb: deterministic (byte-identical across two MCP calls)" \
    || no "for verb: non-deterministic response"

echo
echo "=== 4. tools/call 'owners' — bus-factor on synthetic git repo ==="

OWNERS_MSGS=(
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}'
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"owners","arguments":{"path":"'"$REPO"'"}}}'
)

mcp_call "${OWNERS_MSGS[@]}" >"$TMP/owners_a"
mcp_call "${OWNERS_MSGS[@]}" >"$TMP/owners_b"

OWNERS_INNER="$( tail -1 "$TMP/owners_a" | python3 -c '
import sys, json
r = json.load(sys.stdin)
if "error" in r:
    print("__ERROR__:" + json.dumps(r["error"]))
else:
    print(r["result"]["content"][0]["text"])
' )"

case "$OWNERS_INNER" in
    __ERROR__*) no "owners verb returned error: ${OWNERS_INNER#__ERROR__:}";;
    "")         no "owners verb: inner text is empty";;
    *)          ok "owners verb: returned non-empty text result";;
esac

# Assert the result contains <owners — the XML tag emitted by gitFileAuthors output path
if echo "$OWNERS_INNER" | grep -q "<owners"; then
    ok "owners verb: result contains <owners> element"
else
    no "owners verb: result does NOT contain <owners> element — got: $( echo "$OWNERS_INNER" | head -c 200 )"
fi

# Assert at least one <f element (file ownership entry)
if echo "$OWNERS_INNER" | grep -q "<f "; then
    ok "owners verb: result contains at least one <f> file entry"
else
    no "owners verb: no <f> file entries found"
fi

# Determinism: two runs byte-identical
diff -q "$TMP/owners_a" "$TMP/owners_b" >/dev/null \
    && ok "owners verb: deterministic (byte-identical across two MCP calls)" \
    || no "owners verb: non-deterministic response"

echo
echo "=== 5. Existing verbs still work (regression sanity) ==="

# Quick smoke-test: `analyze` on the zoomfix corpus returns a result, not an error.
ANALYZE_OUT="$( mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"analyze","arguments":{"path":"'"$CORPUS"'"}}}' | tail -1 )"

python3 -c '
import sys, json
r = json.loads(sys.argv[1])
print("OK" if "result" in r and "error" not in r else "ERROR:" + json.dumps(r.get("error",{})))
' "$ANALYZE_OUT" >"$TMP/analyze"
[ "$( cat "$TMP/analyze" )" = "OK" ] \
    && ok "existing 'analyze' verb still works" \
    || no "existing 'analyze' verb broken: $( cat "$TMP/analyze" )"

# Unknown tool still returns -32602.
UNKNOWN_OUT="$( mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"no_such_tool","arguments":{"path":"'"$CORPUS"'"}}}' | tail -1 )"

python3 -c '
import sys, json
r = json.loads(sys.argv[1])
code = r.get("error", {}).get("code", 0)
print("OK" if code == -32602 else "GOT:" + str(code))
' "$UNKNOWN_OUT" >"$TMP/unknown"
[ "$( cat "$TMP/unknown" )" = "OK" ] \
    && ok "unknown tool still returns -32602" \
    || no "unknown tool did not return -32602: $( cat "$TMP/unknown" )"

echo
echo "=== 6. L4 — explore/pack_task/from_trace/edit_check (B11 verb parity) ==="

# ── tools/list shows 31 verbs, including the L4 three and the field-notes four ───────────────
LIST_OUT2="$( mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | tail -1 )"
l4_field() {   # l4_field <python-expr-over-`names`> — one value per call (no bash arrays; macOS bash 3.2 has no mapfile)
    python3 -c '
import sys, json
r = json.loads(sys.argv[1])
names = [t["name"] for t in r["result"]["tools"]]
print(eval(sys.argv[2]))
' "$LIST_OUT2" "$1"
}
L4_COUNT="$(  l4_field 'len(names)' )"
L4_EXPLORE="$( l4_field '"explore" in names' )"
L4_TRACE="$(  l4_field '"from_trace" in names' )"
L4_EDITCHK="$( l4_field '"edit_check" in names' )"
L4_PACKTASK="$( l4_field '"pack_task" in names' )"   # dispatch-only alias — NOT separately advertised in tools/list
L4_WHEREIS="$( l4_field '"whereis" in names' )"
L4_STRAY="$(   l4_field '"stray_content" in names' )"
L4_FLAGS="$(   l4_field '"flags" in names' )"
L4_DDRIFT="$( l4_field '"doc_drift" in names' )"
[ "$L4_COUNT" = "31" ]     && ok "tools/list shows exactly 31 verbs" || no "tools/list shows $L4_COUNT verbs, expected 31"
[ "$L4_DDRIFT" = "True" ]  && ok "tools/list includes 'doc_drift'"     || no "tools/list is missing 'doc_drift'"
[ "$L4_WHEREIS" = "True" ] && ok "tools/list includes 'whereis'"       || no "tools/list is missing 'whereis'"
[ "$L4_STRAY" = "True" ]   && ok "tools/list includes 'stray_content'" || no "tools/list is missing 'stray_content'"
[ "$L4_FLAGS" = "True" ]   && ok "tools/list includes 'flags'"         || no "tools/list is missing 'flags'"
[ "$L4_EXPLORE" = "True" ] && ok "tools/list includes 'explore'"    || no "tools/list is missing 'explore'"
[ "$L4_TRACE" = "True" ]   && ok "tools/list includes 'from_trace'" || no "tools/list is missing 'from_trace'"
[ "$L4_EDITCHK" = "True" ] && ok "tools/list includes 'edit_check'" || no "tools/list is missing 'edit_check'"
[ "$L4_PACKTASK" = "False" ] && ok "'pack_task' is NOT separately advertised in tools/list (dispatch-only alias)" \
                              || no "'pack_task' unexpectedly appears in tools/list"

# ── explore round-trip: a pack-task-shaped bundle (same shape as CLI --pack-task) ────────────────
EXPLORE_MSGS=(
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}'
# M1 RE-PIN (terminality round A, 2026-09-05): the MCP legend DEFAULT moved to compact, and the two shape
# assertions below quote the FULL document's shape — explore's `<!-- ripwire task bundle for` header comment
# and edit_check's `<edit-check sym="appMain"` root, which under compact opens `<edit-check schema="…" sym=`.
# So these two calls ask for `legend:"full"`, the posture whose shape they describe. The DEFAULT (compact)
# path is pinned per verb by compactlegendcheck (N), which asserts both that the default IS compact and that
# its payload is byte-identical to the full one — so a shape assertion on full covers the default's rows too.
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"explore","arguments":{"path":"'"$CORPUS"'","task":"engine scheduling run loop","legend":"full"}}}'
)
mcp_call "${EXPLORE_MSGS[@]}" >"$TMP/explore_a"
mcp_call "${EXPLORE_MSGS[@]}" >"$TMP/explore_b"
EXPLORE_INNER="$( tail -1 "$TMP/explore_a" | python3 -c '
import sys, json
r = json.load(sys.stdin)
print("__ERROR__:" + json.dumps(r["error"])) if "error" in r else print(r["result"]["content"][0]["text"])
' )"
case "$EXPLORE_INNER" in
    __ERROR__*) no "explore verb returned error: ${EXPLORE_INNER#__ERROR__:}";;
    "")         no "explore verb: inner text is empty";;
    *)          ok "explore verb: returned non-empty text result";;
esac
# §B1.7 (2026-07-29): same root-attribute change — the legend comment still follows the ctx open tag,
# but task=/route= attributes now sit between; assert the two meaning halves separately.
{ printf '%s' "$EXPLORE_INNER" | grep -qE '<ctx( |>)' \
  && printf '%s' "$EXPLORE_INNER" | grep -q '<!-- ripwire task bundle for' \
  && printf '%s' "$EXPLORE_INNER" | grep -q 'budget=' \
  && printf '%s' "$EXPLORE_INNER" | grep -q '<sigs>' \
  && printf '%s' "$EXPLORE_INNER" | grep -q '</ctx>'; } \
    && ok "explore verb: pack-task-shaped bundle (header/budget/<sigs>/</ctx>)" \
    || { no "explore verb: not pack-task-shaped"; printf '%s\n' "$EXPLORE_INNER" | head -c 300; echo; }
diff -q "$TMP/explore_a" "$TMP/explore_b" >/dev/null \
    && ok "explore verb: deterministic (byte-identical across two MCP calls)" \
    || no "explore verb: non-deterministic response"

# ── pack_task is the SAME handler as explore (dispatch-only alias) — byte-identical inner text ──
# M1: same posture as the explore call above, so the two operands are comparable — and the alias
# resolution of `legend` itself (declaredFieldsFor resolves pack_task to explore's row) is now part
# of what this arm proves: an alias that lost the argument would answer compact against explore's full.
PACKTASK_INNER="$( mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"pack_task","arguments":{"path":"'"$CORPUS"'","task":"engine scheduling run loop","legend":"full"}}}' \
    | tail -1 | python3 -c '
import sys, json
r = json.load(sys.stdin)
print("__ERROR__:" + json.dumps(r["error"])) if "error" in r else print(r["result"]["content"][0]["text"])
' )"
[ "$PACKTASK_INNER" = "$EXPLORE_INNER" ] \
    && ok "pack_task dispatches identically to explore (same handler)" \
    || { no "pack_task diverged from explore's output"; }

# ── from_trace round-trip: a synthetic trace pointing at zoomfix's appMain (app.cpp:9) ──────────
FROMTRACE_OUT="$( python3 - "$CORPUS" <<'PYEOF' | "$BIN" --mcp 2>/dev/null | tail -1
import json, sys
root = sys.argv[1]
trace = "Traceback (most recent call last):\n  File \"app.cpp\", line 9, in appMain\n    schedRun()\n"
print(json.dumps({"jsonrpc":"2.0","id":1,"method":"initialize"}))
print(json.dumps({"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"from_trace","arguments":{"path":root,"trace":trace}}}))
PYEOF
)"
FROMTRACE_INNER="$( printf '%s' "$FROMTRACE_OUT" | python3 -c '
import sys, json
r = json.loads(sys.stdin.read())
print("__ERROR__:" + json.dumps(r["error"])) if "error" in r else print(r["result"]["content"][0]["text"])
' )"
case "$FROMTRACE_INNER" in
    __ERROR__*) no "from_trace verb returned error: ${FROMTRACE_INNER#__ERROR__:}";;
    *)          ok "from_trace verb: returned non-empty text result";;
esac
{ printf '%s' "$FROMTRACE_INNER" | grep -q '<trace src=' \
  && printf '%s' "$FROMTRACE_INNER" | grep -q 'n="appMain"' \
  && printf '%s' "$FROMTRACE_INNER" | grep -q 'in_corpus="1"'; } \
    && ok "from_trace verb: mapped the fixture trace onto appMain (innermost frame)" \
    || { no "from_trace verb: did not map onto appMain"; printf '%s\n' "$FROMTRACE_INNER" | head -c 300; echo; }

# ── edit_check round-trip: the contract shape (status= + callers=) ──────────────────────────────
EDITCHECK_OUT="$( mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"edit_check","arguments":{"path":"'"$CORPUS"'","symbol":"appMain","legend":"full"}}}' | tail -1 )"   # M1: see the re-pin note above
EDITCHECK_INNER="$( printf '%s' "$EDITCHECK_OUT" | python3 -c '
import sys, json
r = json.loads(sys.stdin.read())
print("__ERROR__:" + json.dumps(r["error"])) if "error" in r else print(r["result"]["content"][0]["text"])
' )"
case "$EDITCHECK_INNER" in
    __ERROR__*) no "edit_check verb returned error: ${EDITCHECK_INNER#__ERROR__:}";;
    *)          ok "edit_check verb: returned non-empty text result";;
esac
{ printf '%s' "$EDITCHECK_INNER" | grep -q '<edit-check sym="appMain"' \
  && printf '%s' "$EDITCHECK_INNER" | grep -qE 'status="(unchanged|new-symbol|contract-change)"' \
  && printf '%s' "$EDITCHECK_INNER" | grep -q 'callers="'; } \
    && ok "edit_check verb: contract shape (sym/status/callers)" \
    || { no "edit_check verb: wrong shape"; printf '%s\n' "$EDITCHECK_INNER" | head -c 300; echo; }

# unknown symbol → -32602 naming it
EDITCHECK_UNKNOWN="$( mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"edit_check","arguments":{"path":"'"$CORPUS"'","symbol":"noSuchSymbolXYZ"}}}' | tail -1 )"
python3 -c '
import sys, json
r = json.loads(sys.argv[1])
msg = r.get("error", {}).get("message", "")
print("OK" if r.get("error",{}).get("code")==-32602 and "noSuchSymbolXYZ" in msg else "GOT:" + json.dumps(r))
' "$EDITCHECK_UNKNOWN" >"$TMP/editcheck_unknown"
[ "$( cat "$TMP/editcheck_unknown" )" = "OK" ] \
    && ok "edit_check: unknown symbol -> -32602 naming it" \
    || no "edit_check: unknown symbol did not refuse correctly: $( cat "$TMP/editcheck_unknown" )"

# ── missing-arg gives the per-verb message (D3 convention) ──────────────────────────────────────
check_missing_arg() {
    local verb="$1" argsJson="$2" wantSubstr="$3"
    local out
    out="$( mcp_call \
        '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
        '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"'"$verb"'","arguments":'"$argsJson"'}}' | tail -1 )"
    python3 -c '
import sys, json
r = json.loads(sys.argv[1])
msg = r.get("error", {}).get("message", "")
print("OK" if r.get("error",{}).get("code")==-32602 and sys.argv[2] in msg else "GOT:" + json.dumps(r))
' "$out" "$wantSubstr" >"$TMP/missing_$verb"
    [ "$( cat "$TMP/missing_$verb" )" = "OK" ] \
        && ok "$verb: missing-arg gives 'missing required field: $wantSubstr'" \
        || no "$verb: missing-arg message wrong: $( cat "$TMP/missing_$verb" )"
}
check_missing_arg "explore"    '{"path":"'"$CORPUS"'"}' "task"
check_missing_arg "pack_task"  '{"path":"'"$CORPUS"'"}' "task"
check_missing_arg "from_trace" '{"path":"'"$CORPUS"'"}' "trace"
check_missing_arg "edit_check" '{"path":"'"$CORPUS"'"}' "symbol"

# ─── 7. @FILE:LINE line-seeds on the MCP surface (the CLI contract of test/atcheck.sh, mirrored) ─────
#
# The resolver family (resolveFocus / resolveAllByNameQualified) accepts @FILE:LINE, so the MCP verbs on
# those resolvers must (a) ADVERTISE the spelling in tools/list — an undiscoverable selector does not
# exist for an MCP agent — (b) resolve it, and (c) refuse a faulted seed with the SAME at-diagnosis the
# CLI speaks (selectorrefuse.h::atSeedFaultClause), never a bare "symbol not found" or a false
# external="1". The NAME-matching scan verbs (mentions/owners) REBIND a resolvable seed to the innermost
# enclosing definition and answer with a sym disclosure (7f/7g) — the 2026-08-30 decision round replaced
# their pass-the-name-yourself refusal with the one-step-smart-defaults answer. Fixture: the atcheck
# geo.cpp corpus (line 12 = inside Frame::shift, line 2 = top-level blank, i.e. a no-coverer fault),
# plus notes.md + one git commit as scan-verb fuel.

echo
echo "=== 7. @FILE:LINE line-seeds — advertised, resolved, and diagnosed on refusal ==="

ATFIX="$TMP/atfix"
mkdir -p "$ATFIX/src"
cat >"$ATFIX/src/geo.cpp" <<'EOF'
// geometry fixture

namespace geo
{

struct Frame
{
    int origin = 0;

    int shift( int d )
    {
        int moved = origin + d;
        moved = moved * 2;
        return moved;
    }
};

}   // namespace geo

int standalone( int a )
{
    return a + 1;
}

int useAll()
{
    geo::Frame f;
    return f.shift( 2 ) + standalone( 3 );
}
EOF

# mention fuel for the scan-verb rebind arms (7f/7g): a doc that names `shift` in a backtick, and one
# commit of git history so `owners` has authorship to mine.
cat >"$ATFIX/notes.md" <<'EOF'
# Geometry notes

The `shift` helper doubles the shifted origin.
EOF
git -C "$ATFIX" init -q
git -C "$ATFIX" -c user.name=atfix -c user.email=atfix@example.invalid add -A >/dev/null 2>&1
git -C "$ATFIX" -c user.name=atfix -c user.email=atfix@example.invalid commit -qm seed >/dev/null 2>&1

# (7a) tools/list: every @-capable verb's description teaches the spelling
python3 -c '
import sys, json
resp = json.loads(sys.argv[1])
tools = { t["name"]: json.dumps(t) for t in resp["result"]["tools"] }
want = [ "find_symbol", "find_referencing_symbols", "impact", "uses", "edit_check",
         "path_between", "connect", "lego", "fetch_body",
         "mentions", "owners", "replace_symbol_body", "insert_before_symbol", "insert_after_symbol" ]
missing = [ v for v in want if "@FILE:LINE" not in tools.get(v, "") ]
print("OK" if not missing else "MISSING:" + ",".join(missing))
' "$LIST_OUT" >"$TMP/at_list"
[ "$( cat "$TMP/at_list" )" = "OK" ] \
    && ok "@seed (7a): all 14 @-capable verbs advertise @FILE:LINE in tools/list" \
    || no "@seed (7a): verbs not advertising @FILE:LINE: $( cat "$TMP/at_list" )"

at_call() {
    mcp_call \
        '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
        '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"'"$1"'","arguments":'"$2"'}}' | tail -1
}

# (7b) find_symbol resolves the seed to the innermost enclosing definition
AT_FS="$( at_call find_symbol '{"path":"'"$ATFIX"'","symbol":"@src/geo.cpp:12"}' )"
python3 -c '
import sys, json
r = json.loads(sys.argv[1])
txt = r.get("result",{}).get("content",[{}])[0].get("text","")
body = json.loads(txt) if txt else {}
print("OK" if body.get("symbol",{}).get("name") == "shift" else "GOT:" + txt[:200])
' "$AT_FS" >"$TMP/at_fs"
[ "$( cat "$TMP/at_fs" )" = "OK" ] \
    && ok "@seed (7b): find_symbol @src/geo.cpp:12 resolves to shift" \
    || no "@seed (7b): find_symbol did not resolve the seed: $( cat "$TMP/at_fs" )"

# (7c) impact takes the seed's blast radius (useAll reaches shift)
AT_IM="$( at_call impact '{"path":"'"$ATFIX"'","symbol":"@src/geo.cpp:12"}' )"
python3 -c '
import sys, json
r = json.loads(sys.argv[1])
txt = r.get("result",{}).get("content",[{}])[0].get("text","")
print("OK" if "useAll" in txt and "error" not in r else "GOT:" + txt[:200] + json.dumps(r.get("error",{})))
' "$AT_IM" >"$TMP/at_im"
[ "$( cat "$TMP/at_im" )" = "OK" ] \
    && ok "@seed (7c): impact @src/geo.cpp:12 reaches useAll" \
    || no "@seed (7c): impact did not serve the seed: $( cat "$TMP/at_im" )"

# (7d) uses serves the RESOLVED definition's sites — never a false external="1" count="0"
AT_US="$( at_call uses '{"path":"'"$ATFIX"'","symbol":"@src/geo.cpp:12"}' )"
python3 -c '
import sys, json
r = json.loads(sys.argv[1])
txt = r.get("result",{}).get("content",[{}])[0].get("text","")
print("OK" if "in_id=\"useAll\"" in txt and "external=\"0\"" in txt else "GOT:" + txt[:300])
' "$AT_US" >"$TMP/at_us"
[ "$( cat "$TMP/at_us" )" = "OK" ] \
    && ok "@seed (7d): uses @src/geo.cpp:12 serves shift's call site, external=0" \
    || no "@seed (7d): uses lost the seed's sites: $( cat "$TMP/at_us" )"

# (7e) a FAULTED seed refuses with the shared at-diagnosis, on a resolver verb and on uses
AT_BADFS="$( at_call find_symbol '{"path":"'"$ATFIX"'","symbol":"@src/geo.cpp:2"}' )"
python3 -c '
import sys, json
r = json.loads(sys.argv[1])
msg = r.get("error",{}).get("message","")
print("OK" if r.get("error",{}).get("code")==-32602 and "no indexed symbol spans line 2" in msg else "GOT:" + json.dumps(r)[:300])
' "$AT_BADFS" >"$TMP/at_badfs"
[ "$( cat "$TMP/at_badfs" )" = "OK" ] \
    && ok "@seed (7e): find_symbol faulted seed -> -32602 carrying the at-diagnosis" \
    || no "@seed (7e): find_symbol faulted-seed refusal wrong: $( cat "$TMP/at_badfs" )"

AT_BADUS="$( at_call uses '{"path":"'"$ATFIX"'","symbol":"@src/geo.cpp:2"}' )"
python3 -c '
import sys, json
r = json.loads(sys.argv[1])
msg = r.get("error",{}).get("message","")
print("OK" if "no indexed symbol spans line 2" in msg else "GOT:" + json.dumps(r)[:300])
' "$AT_BADUS" >"$TMP/at_badus"
[ "$( cat "$TMP/at_badus" )" = "OK" ] \
    && ok "@seed (7e): uses faulted seed refuses with the at-diagnosis (never external=1)" \
    || no "@seed (7e): uses faulted-seed refusal wrong: $( cat "$TMP/at_badus" )"

# (7f) a NAME-matching scan verb (mentions) REBINDS a resolvable seed to the innermost enclosing
# definition and ANSWERS, disclosing the rebound name as "sym" (one-step-smart-defaults: the answer
# itself, never a re-run hint) — "symbol" keeps echoing the seed as typed
AT_MEN="$( at_call mentions '{"path":"'"$ATFIX"'","symbol":"@src/geo.cpp:12"}' )"
python3 -c '
import sys, json
r = json.loads(sys.argv[1])
txt = r.get("result",{}).get("content",[{}])[0].get("text","")
body = json.loads(txt) if txt.startswith("{") else {}
okv = body.get("sym") == "shift" and body.get("symbol") == "@src/geo.cpp:12" and body.get("docs") == 1
print("OK" if okv else "GOT:" + json.dumps(r)[:300])
' "$AT_MEN" >"$TMP/at_men"
[ "$( cat "$TMP/at_men" )" = "OK" ] \
    && ok "@seed (7f): mentions rebinds the seed to shift, discloses sym, and serves the doc" \
    || no "@seed (7f): mentions did not rebind+answer the resolvable seed: $( cat "$TMP/at_men" )"

# (7g) owners: the same rebind — of= echoes the seed, sym= names the rebound definition, and the
# analysed file is the SEED's own (files="1"), never a lowest-id same-named def in another file
AT_OWN="$( at_call owners '{"path":"'"$ATFIX"'","symbol":"@src/geo.cpp:12"}' )"
python3 -c '
import sys, json
r = json.loads(sys.argv[1])
txt = r.get("result",{}).get("content",[{}])[0].get("text","")
okv = "of=\"@src/geo.cpp:12\"" in txt and "sym=\"shift\"" in txt and "files=\"1\"" in txt
print("OK" if okv else "GOT:" + (txt[:300] if txt else json.dumps(r)[:300]))
' "$AT_OWN" >"$TMP/at_own"
[ "$( cat "$TMP/at_own" )" = "OK" ] \
    && ok "@seed (7g): owners rebinds the seed, discloses sym=, and analyses the seed's file" \
    || no "@seed (7g): owners did not rebind+answer the resolvable seed: $( cat "$TMP/at_own" )"

# (7h) a FAULTED seed on a scan verb still refuses with the shared at-diagnosis — rebinding is for
# resolvable seeds only, a fault is never guessed around
AT_MENBAD="$( at_call mentions '{"path":"'"$ATFIX"'","symbol":"@src/geo.cpp:2"}' )"
python3 -c '
import sys, json
r = json.loads(sys.argv[1])
msg = r.get("error",{}).get("message","")
print("OK" if "no indexed symbol spans line 2" in msg else "GOT:" + json.dumps(r)[:300])
' "$AT_MENBAD" >"$TMP/at_menbad"
[ "$( cat "$TMP/at_menbad" )" = "OK" ] \
    && ok "@seed (7h): mentions faulted seed refuses with the at-diagnosis" \
    || no "@seed (7h): mentions faulted-seed refusal wrong: $( cat "$TMP/at_menbad" )"

# ─── Summary ──────────────────────────────────────────────────────────────────
echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
