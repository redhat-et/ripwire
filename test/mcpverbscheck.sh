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
#   6. L4: tools/list shows 33 verbs (`pack_task` dispatch-only, not separately advertised);
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
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
CORPUS="$ROOT/test/zoomfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
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

# A3-F1 gate: <sigs> must carry an actual signature PAYLOAD — at least one <d> declaration row. The 0-budget
# sentinel bug emitted a bare <sigs></sigs> (rank/fanIn computed, then discarded by the immediate budget
# break), and the presence-only grep above still passed. RE-PINNED 2026-09-05 (terminality round A, lane R,
# P7): the lens <sigs> is FLAT — <d … p="FILE" … r=N> rows in rank order, no <f p=> wrapper — so the payload
# is the first <d> row directly inside <sigs> (test/forrankordercheck.sh).
if echo "$FOR_INNER" | grep -qE "<sigs[^>]*><d [^>]* p=\"" ; then
    ok "for verb: <sigs> is NON-EMPTY (has <d … p=> signature rows — A3-F1)"
else
    no "for verb: <sigs> is EMPTY (no <d> payload — A3-F1 0-budget sentinel) — got: $( echo "$FOR_INNER" | head -c 200 )"
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

# ── tools/list shows 33 verbs, including the L4 three and the field-notes four ───────────────
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
if [ "$L4_COUNT" = "33" ]; then ok "tools/list shows exactly 33 verbs"; else no "tools/list shows $L4_COUNT verbs, expected 33"; fi
if [ "$L4_DDRIFT" = "True" ]; then ok "tools/list includes 'doc_drift'"; else no "tools/list is missing 'doc_drift'"; fi
if [ "$L4_WHEREIS" = "True" ]; then ok "tools/list includes 'whereis'"; else no "tools/list is missing 'whereis'"; fi
if [ "$L4_STRAY" = "True" ]; then ok "tools/list includes 'stray_content'"; else no "tools/list is missing 'stray_content'"; fi
if [ "$L4_FLAGS" = "True" ]; then ok "tools/list includes 'flags'"; else no "tools/list is missing 'flags'"; fi
if [ "$L4_EXPLORE" = "True" ]; then ok "tools/list includes 'explore'"; else no "tools/list is missing 'explore'"; fi
if [ "$L4_TRACE" = "True" ]; then ok "tools/list includes 'from_trace'"; else no "tools/list is missing 'from_trace'"; fi
if [ "$L4_EDITCHK" = "True" ]; then ok "tools/list includes 'edit_check'"; else no "tools/list is missing 'edit_check'"; fi
[ "$L4_PACKTASK" = "False" ] && ok "'pack_task' is NOT separately advertised in tools/list (dispatch-only alias)" \
                              || no "'pack_task' unexpectedly appears in tools/list"

# ── (6b) THE EXACT ADVERTISED ROSTER — a constant-count swap must not slip a verb in ─────────────
# WHY THIS ARM. The L4_COUNT==31 assertion above fails closed on a verb ADDED; the per-name checks pin
# the L4/field-notes verbs individually. Neither catches a RENAME or SWAP that keeps the count at 31 and
# touches a verb no arm names (analyze, grep, the edit trio, …) — CONTRIBUTING §2 shape 7 ("true but
# narrower"): "same count + these names present" is strictly weaker than "the roster is EXACTLY this set".
# A verb that reaches a subprocess (a hypothetical run_trace MCP twin of the CLI-only --run-trace) could
# replace an unnamed read verb at count 31 with every arm above still green. Pinning the FULL sorted
# roster reddens on ANY add/remove/rename until a human updates this list — the point being that a new
# MCP verb, above all one that reaches an exec, is signed for, never a silent drift.
# The set is the ADVERTISED roster (kMcpVerbTable, mcp.h); pack_task stays out (dispatch-only alias,
# already asserted absent above). Sorted so the diff reads name-by-name.
EXPECTED_VERBS="affected
analyze
batch
cochange
connect
doc_drift
edit_check
exemplar
explore
fetch_body
find_referencing_symbols
find_symbol
flags
for
from_trace
grep
impact
insert_after_symbol
insert_before_symbol
lego
memory_recall
mentions
owners
path_between
quality_baseline
quality_delta
rank_by
replace_symbol_body
situational_awareness
slice
stray_content
uses
whereis"

LIVE_VERBS_SORTED="$( l4_field 'chr(10).join(sorted(names))' )"
EXPECTED_SORTED="$( printf '%s\n' "$EXPECTED_VERBS" | sort )"

if [ "$LIVE_VERBS_SORTED" = "$EXPECTED_SORTED" ]; then
    ok "(6b) advertised roster matches the pinned set exactly ($L4_COUNT verbs; no unpinned add/rename/swap)"
else
    no "(6b) advertised roster DRIFTED from the pinned set — a verb was added, removed, or renamed; review it (a subprocess-reaching verb must never join silently), then update EXPECTED_VERBS consciously:"
    diff <(printf '%s\n' "$EXPECTED_SORTED") <(printf '%s\n' "$LIVE_VERBS_SORTED") | sed 's/^/      /'
fi

# ── (6c) LIVENESS of (6b) + the named shell-exec tripwire (CONTRIBUTING §2: prove the arm can fail) ─
# (6b) is only as live as its ability to SEE a new verb. Prove it on a mutated copy of the live list:
# inject a synthetic run_trace and assert the SAME comparison reddens. Guards shape 3 (empty==empty) if
# a future edit ever broke the extraction. Computed here, run every time — never a fixture of the server.
MUT_LIVE="$( printf '%s\nrun_trace\n' "$LIVE_VERBS_SORTED" | sort )"
if [ "$MUT_LIVE" != "$EXPECTED_SORTED" ]; then
    ok "(6c) mutation control: a synthetic 'run_trace' verb is correctly seen as roster drift"
else
    no "(6c) mutation control VACUOUS: injecting 'run_trace' did not disturb the comparison — (6b) cannot fail"
fi
# The invariant, named for the reader who greps for it: no shell/exec-shaped verb is advertised.
if printf '%s\n' "$LIVE_VERBS_SORTED" | grep -qxE 'run_trace|run|shell|exec'; then
    no "(6c) an MCP verb named like a shell/exec entry point is advertised — --run-trace must stay CLI-only (runtracecheck.sh)"
else
    ok "(6c) no shell/exec-shaped verb advertised (MCP surface reaches no subprocess exec; --run-trace stays CLI-only)"
fi

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

# ─── (8) the ADVERTISED verb count in prose — derived here, never remembered ──────────────────────
# L4 above asserts tools/list shows exactly $L4_COUNT verbs. That number is also PRINTED, in prose, on
# three shipped surfaces — README.md, skills/ripwire-mcp/SKILL.md and the showcase deck generator —
# and until now not one of them was compared against the server that defines it. All three said 30
# while tools/list served 31, because the count was transcribed by hand at each site and the gate that
# knew the truth never looked at any of them.
#
# This arm is the derive-then-compare discipline the rest of the suite uses (test/manifestcheck.sh's
# gate-count arm, test/readmedriftcheck.sh's lineage arm, test/deckclaimcheck.sh's slide-count arm),
# pointed at the number this gate is already holding: the LIVE tools/list length. Nothing is pinned —
# add a verb and every site is expected to move with it.
#
# SCAN + REQUIRE, one declared list: a site may not state a count that disagrees, and must state one.
# A claim deleted is a claim drifted — deleting the sentence is the cheapest way out of a red, and it
# leaves a reader with no count at all rather than a wrong one, which is not an improvement.
verbCountSites=( "README.md" "skills/ripwire-mcp/SKILL.md" "present/deck5_ripwire_build.js" )
# The digits must start a WORD. Without the left boundary this matched "B11 verbs" — the internal
# label for a verb-parity workstream in skills/ripwire-mcp/SKILL.md — and reported a fabricated
# 11-vs-31 disagreement. A scan arm that invents reds is worse than one that misses: it teaches the
# next maintainer to skim past this gate's output.
verbClaimRe='(^|[^0-9A-Za-z])[0-9]+ (MCP )?verbs'

scanVerbCounts() { sed 's/\*//g' "$1" | grep -noE "$verbClaimRe" || true; }
verbClaimNum()  { printf '%s' "$1" | sed -E 's/^[0-9]+://' | grep -oE '[0-9]+ (MCP )?verbs' | grep -oE '^[0-9]+'; }

if [ -z "${L4_COUNT:-}" ] || ! [ "$L4_COUNT" -gt 0 ] 2>/dev/null; then
    no "(8) no live tools/list verb count to compare prose against (L4_COUNT='${L4_COUNT:-}') — this arm would be vacuous"
else
    for site in "${verbCountSites[@]}"; do
        sitePath="$ROOT/$site"
        [ -f "$sitePath" ] || { no "(8) $site is missing — a surface that states the verb count must exist to be checked"; continue; }
        claims="$( scanVerbCounts "$sitePath" )"
        if [ -z "$claims" ]; then
            no "(8) $site states no '<N> verbs' count — the claim was deleted or reworded, which is a drift, not a fix"
            continue
        fi
        while IFS= read -r claim; do
            [ -z "$claim" ] && continue
            claimLine="${claim%%:*}"
            claimNum="$( verbClaimNum "$claim" )"
            if [ "$claimNum" = "$L4_COUNT" ]; then
                ok "(8) $site:$claimLine states $claimNum verbs, matching the live tools/list"
            else
                no "(8) $site:$claimLine states $claimNum verbs, but tools/list serves $L4_COUNT"
            fi
        done <<EOF
$claims
EOF
    done

    # MUTATION CONTROL. Every site agreeing proves only that numbers were read; prove a wrong one is
    # still seen. The deck is the mutated site deliberately — it is the surface whose stale 30 shipped
    # into a public PDF, and the one this arm was added for.
    mutDeck="$ROOT/present/deck5_ripwire_build.js"
    if [ -f "$mutDeck" ]; then
        mutOut="$TMP/mcpverbcount_bad.js"
        wrongVerbs=$(( L4_COUNT + 4 ))
        sed -E "s/${L4_COUNT} (MCP )?verbs/${wrongVerbs} \1verbs/g" "$mutDeck" > "$mutOut"
        mutNum="$( verbClaimNum "$( scanVerbCounts "$mutOut" | head -1 )" )"
        if [ -z "$mutNum" ]; then
            no "(8) mutation control: could not re-extract a verb count from the mutated deck copy at all"
        elif [ "$mutNum" = "$L4_COUNT" ]; then
            no "(8) mutation control: the injected wrong count did not take ($mutNum still equals the live $L4_COUNT) — the control is vacuous"
        else
            ok "(8) mutation control: a fabricated deck verb count ($mutNum) is correctly seen as disagreeing with tools/list ($L4_COUNT)"
        fi
    fi
fi

# ── (6d) EXPLORE PAGING PARITY (upstream issue #294, corrected scope) ────────────────────────────
# Measured 2026-09-19: MCP `for` serves the bounded widening page today (limit=5 → <files … quintet …
# next=…>); MCP `explore` REFUSES limit outright ("unknown field: 'limit' — explore accepts: path, paths,
# task, budget_tokens, partition, legend, no_route"). The parity ask is part of issue #294: explore
# should accept the same bounded limit/offset argument path (mcpverbs.h:327-333) for serves it uses.
# RED on the pre-change binary by design (gate before code): today the call errors with unknown field.
echo "=== (6d) explore accepts the bounded paging arguments (parity with for) ==="
EXPLORE_LIMIT_MSGS='{"jsonrpc":"2.0","id":1,"method":"initialize"}
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"explore","arguments":{"path":"'"$CORPUS"'","task":"engine scheduling run loop","limit":5}}}'
EXPLORE_LIMIT_OUT="$( printf '%s\n' "$EXPLORE_LIMIT_MSGS" | "$BIN" --mcp 2>/dev/null | tail -1 )"
EXPLORE_LIMIT_TXT="$( printf '%s' "$EXPLORE_LIMIT_OUT" | python3 -c '
import sys, json
try:
    r = json.loads( sys.stdin.read() )
except Exception:
    print( "PARSE_ERROR" ); sys.exit(0)
if "error" in r:
    print( "MCPError:" + str( r["error"].get("message", "") )[:80] ); sys.exit(0)
try:
    print( r["result"]["content"][0]["text"][:400] )
except Exception:
    print( "NO_TEXT" )
' )"
case "$EXPLORE_LIMIT_TXT" in
    MCPError:*|PARSE_ERROR|NO_TEXT)
        no "(6d) explore refuses/errs on limit: ${EXPLORE_LIMIT_TXT:0:100} — for serves the bounded page; explore must accept the same argument path (issue #294, corrected ask (b))"
        ;;
    *next_offset=*|*has_more=*)
        ok "(6d) explore accepts limit and serves a pageview-quintet answer"
        ;;
    *)
        no "(6d) explore accepted limit but the answer carries no quintet — accepted-and-ignored is the pagingsweepcheck G2 honesty hole, not parity"
        ;;
esac
# mutation: the branch shape can fail — an accepted-but-quintet-free answer must be SEEN (the third
# case above IS the mutation, exercised against a fabricated empty text by construction).
MUT_TXT="ok no-quintet"
case "$MUT_TXT" in
    *next_offset=*|*has_more=*) no "(6d) mutation VACUOUS: bare text matched the quintet branch" ;;
    *) ok "(6d) mutation: accepted-but-quintet-free falls to the honest red branch" ;;
esac

# ── (6e)/(6f) MCP BUDGETED-BUNDLE CANDIDATE PAGE (issue #294 follow-up: the twins) ────────────────
# The CLI --for/--pack-task serve the candidate page under budget+window (PR #3, merged). The MCP twins
# must not diverge. Measured 2026-09-23 on this binary, before this arm's implementation:
#   * MCP `for` {budget_tokens, limit} REFUSES ("limit/offset select the file page, which has no token
#     budget to shape against") — honest, but no page.
#   * MCP `explore` {budget_tokens, limit} serves the BUDGETLESS FILE PAGE with budget_tokens silently
#     ignored — the accept-and-ignore class (the exact hole W3FIX M4 closed for budget_aliases).
# Both arms demand the SAME contract the CLI serves: the <sigs>-rooted candidate page with the pageview
# quintet, tier=, and est_tokens within the stated budget. RED until the twins land.
for_twins_budget_page()
{
    local verb="$1"
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
         '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"'"$verb"'","arguments":{"path":"'"$CORPUS"'","task":"engine scheduling run loop","budget_tokens":600,"limit":3}}}' \
        | "$BIN" --mcp 2>/dev/null | tail -1 | python3 -c '
import sys, json
try:    r = json.loads( sys.stdin.read() )
except Exception: print( "PARSE_ERROR" ); sys.exit(0)
if "error" in r: print( "MCPError:" + str( r["error"].get("message","") )[:90] ); sys.exit(0)
try:    t = r["result"]["content"][0]["text"]
except Exception: print( "NO_TEXT" ); sys.exit(0)
print( t.lstrip() )   # the FULL text: over_ceiling sits past byte 400 (#362 review round, arm fix)
'
}
for verb in for explore; do
    OUT="$( for_twins_budget_page "$verb" )"
    case "$OUT" in
        "<sigs "*)
            Q=0; for k in shown= total= capped= has_more= next_offset= tier= budget_tokens= est_tokens=; do
                case "$OUT" in *"$k"*) ;; *) Q=1 ;; esac
            done
            # #294 review (mcpverbscheck arm hardening): the page must BUDGET-HONEST — est_tokens
            # numeric and within the stated budget_tokens (or the page discloses over_ceiling="1",
            # the pathological-task case). Parsed, not substring-matched.
            BUD_OK=0
            echo "$OUT" | python3 -c '
import re, sys
t = sys.stdin.read()
m = re.search( r"budget_tokens=\"(\d+)\"", t )
e = re.search( r"est_tokens=\"(\d+)\"", t )
over = re.search( r"over_ceiling=\"1\"", t )
ok = m and e and ( int( e.group( 1 ) ) <= int( m.group( 1 ) ) or over )
sys.exit( 0 if ok else 1 )
' && BUD_OK=1
            if [ "$Q" = 0 ] && [ "$BUD_OK" = 1 ]; then
                ok "(6e) MCP $verb {budget_tokens, limit} serves the candidate page (quintet + tier + est_tokens within budget_tokens)"
            else
                no "(6e) MCP $verb served a <sigs page but the quintet or the budget honesty is incomplete (est_tokens<=budget_tokens or over_ceiling): ${OUT:0:120}"
            fi ;;
        "<files "*)
            no "(6e) MCP $verb {budget_tokens, limit} served the BUDGETLESS FILE PAGE with budget_tokens ignored — accept-and-ignore; the budgeted window must serve the candidate page" ;;
        MCPError:*|PARSE_ERROR|NO_TEXT)
            no "(6e) MCP $verb {budget_tokens, limit}: ${OUT:0:110} — the CLI serves the candidate page; the twin must not diverge" ;;
        *)
            no "(6e) MCP $verb {budget_tokens, limit}: unrecognized answer shape: ${OUT:0:110}" ;;
    esac
done
# mutation: the branch shape can fail — a bare <files page must be SEEN as the ignore hole (the case
# above IS the mutation, exercised against the live pre-change binary by explore's current behavior).
MUT_SHAPE="<files task="x" shown="3""
case "$MUT_SHAPE" in
    "<files "*) ok "(6e) mutation: a <files answer under budget+window IS detected as the ignore hole" ;;
    *)         no "(6e) mutation VACUOUS: the <files branch cannot fire" ;;
esac

# ─── Summary ──────────────────────────────────────────────────────────────────
echo "=== 8. cut-fix E — MCP owners/mentions disclose their surface-only default cut ==="
# `owners` (40 <f> rows) and `mentions` (100 files) are capped on this surface alone — the CLI twins print every row —
# and both cut with discloseCap=false, so a cut answer said nothing. RED on 9936ba4e (no shown=/capped= on the cut);
# GREEN: the cut carries shown=/capped="1"/total=/next_offset=, offset= continues it, an uncut answer adds no bytes.
CR="$TMP/cutrepo"; mkdir -p "$CR/docs"
git -C "$CR" init -q
for i in $( seq -w 1 45 ); do printf 'int cutfn%s( int x ) { return x + 1; }\n' "$i" >"$CR/f$i.c"; done
for i in $( seq -w 1 105 ); do printf '# note %s\n\nSee `cutfn01` here.\n' "$i" >"$CR/docs/n$i.md"; done
printf '# solo\n\nOnly `cutfn02` is named here.\n' >"$CR/docs/solo.md"   # the uncut mentions answer has one real row
( cd "$CR" && git add -A && GIT_AUTHOR_NAME=A GIT_AUTHOR_EMAIL=a@x.com GIT_COMMITTER_NAME=A GIT_COMMITTER_EMAIL=a@x.com \
    GIT_AUTHOR_DATE=2026-06-01T12:00:00 GIT_COMMITTER_DATE=2026-06-01T12:00:00 git commit -q -m one )
for i in $( seq -w 1 45 ); do printf '// b\n' >>"$CR/f$i.c"; done
( cd "$CR" && git add -A && GIT_AUTHOR_NAME=B GIT_AUTHOR_EMAIL=b@x.com GIT_COMMITTER_NAME=B GIT_COMMITTER_EMAIL=b@x.com \
    GIT_AUTHOR_DATE=2026-06-02T12:00:00 GIT_COMMITTER_DATE=2026-06-02T12:00:00 git commit -q -m two )
cut_text(){ mcp_call '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"'"$1"'","arguments":'"$2"'}}' | tail -1 \
    | python3 -c 'import sys, json; r = json.load(sys.stdin); print(r["result"]["content"][0]["text"] if "result" in r else "__ERROR__")'; }
OW="$( cut_text owners '{"path":"'"$CR"'"}' )"
OWROOT="$( printf '%s' "$OW" | grep -o '<owners [^>]*>' | head -1 )"
case "$OWROOT" in
    *' shown="40" capped="1" total="45" has_more="1" next_offset="40"'*) ok "owners: the 40-row cut discloses shown=40 capped=1 total=45 next_offset=40" ;;
    *) no "owners: the 40-row cut is silent: $OWROOT" ;;
esac
OW2="$( cut_text owners '{"path":"'"$CR"'","offset":40}' )"
OW2N="$( printf '%s' "$OW2" | grep -o '<f p="' | wc -l | tr -d ' ' )"
if [ "$OW2N" = 5 ]; then ok "owners: offset=40 serves the other 5 rows"; else no "owners: offset=40 served $OW2N rows (want 5)"; fi
# The uncut arms first prove the answer IS the expected one: an error (cut_text prints __ERROR__) or an empty answer
# also lacks shown=, so "no shown=" alone would pass on a verb that failed.
OW3="$( cut_text owners '{"path":"'"$CR"'","symbol":"cutfn01"}' )"
OW3ROOT="$( printf '%s' "$OW3" | grep -o '<owners [^>]*>' | head -1 )"
OW3ROWS="$( printf '%s' "$OW3" | grep -o '<f p="[^"]*"' | tr '\n' ' ' )"
if [ -z "$OW3ROOT" ] || [ "$OW3ROWS" != '<f p="f01.c" ' ]; then
    no "owners: the uncut answer is not the one f01.c row: root [$OW3ROOT] rows [$OW3ROWS] ($( printf '%s' "$OW3" | head -c 120 ))"
elif printf '%s' "$OW3ROOT" | grep -q ' shown='; then
    no "owners: an uncut answer gained shown="
else
    ok "owners: an uncut answer (the one f01.c row) is unchanged (no shown=)"
fi
MN="$( cut_text mentions '{"path":"'"$CR"'","symbol":"cutfn01"}' )"
printf '%s' "$MN" | python3 -c '
import sys, json
d = json.loads( sys.stdin.read() )
ok = d.get( "shown" ) == 100 and d.get( "capped" ) is True and d.get( "total" ) == 105 and d.get( "next_offset" ) == 100 and len( d[ "files" ] ) == 100
sys.exit( 0 if ok else 1 )' && ok "mentions: the 100-file cut discloses shown=100 capped=true total=105 next_offset=100" \
    || no "mentions: the 100-file cut is silent: $( printf '%s' "$MN" | head -c 200 )"
MN2="$( cut_text mentions '{"path":"'"$CR"'","symbol":"cutfn01","offset":100}' )"
if printf '%s' "$MN2" | python3 -c 'import sys, json; sys.exit( 0 if len( json.loads( sys.stdin.read() )[ "files" ] ) == 5 else 1 )'; then
    ok "mentions: offset=100 serves the other 5 files"
else
    no "mentions: offset=100 did not serve the other 5 files"
fi
MN3="$( cut_text mentions '{"path":"'"$CR"'","symbol":"cutfn02"}' )"
if MN3V="$( printf '%s' "$MN3" | python3 -c '
import sys, json
try:
    d = json.loads( sys.stdin.read() )
except ValueError:
    print( "not JSON (an MCP error reads __ERROR__)" ); sys.exit( 1 )
files = [ f.get( "file" ) for f in d.get( "files", [] ) ]
if d.get( "symbol" ) != "cutfn02" or files != [ "docs/solo.md" ]:
    print( "want the one docs/solo.md row, got symbol=%r files=%r" % ( d.get( "symbol" ), files ) ); sys.exit( 1 )
if "shown" in d:
    print( "an uncut answer gained \"shown\"" ); sys.exit( 1 )
print( "the one docs/solo.md row, no \"shown\"" )' )"; then
    ok "mentions: an uncut answer is unchanged: $MN3V"
else
    no "mentions: uncut answer: $MN3V"
fi

echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
