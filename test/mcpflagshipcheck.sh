#!/usr/bin/env bash
# mcpflagshipcheck.sh — gate for the FLAGSHIP-REFLEX MCP verbs an MCP-only agent otherwise cannot reach:
#   exemplar          — the write-moment reflex (--exemplar): best-in-class instance to imitate, WITH its body.
#   quality_delta     — the before-you-call-it-done reflex (--quality-delta): only what got WORSE vs baseline.
#   quality_baseline  — pins the floor (--quality-baseline): WRITES .ctxpack_quality_baseline stamped w/ HEAD.
#   impact            — is-it-safe-to-change (--impact): transitive blast radius of a symbol.
#   uses              — every read/write/import site (--uses), not just calls.
#   path_between      — does A reach B / the flow (--path=A,B). (Named path_between: 'path' is the repo-root arg.)
#
# Drives the MCP server via newline-delimited JSON-RPC over stdin, exactly like mcpverbscheck.sh. Asserts:
#   1. tools/list advertises all 6 with NON-EMPTY descriptions (before/after count sanity).
#   2. exemplar returns a body (<exemplar ...> with def source).
#   3. quality_delta returns a baseline marker + a regressions array (0 on a CLEAN git fixture, baseline=git-HEAD),
#      and DETECTS a regression once a gnarly fn is added to the working tree.
#   4. quality_baseline WRITES the sidecar with a head-sha stamp.
#   5. impact / uses / path_between return the expected symbols on a synthetic call chain.
#   6. a bad symbol returns the standard -32602 not-found error (NOT a silent empty).
#   7. determinism: each read verb byte-identical across two MCP calls.
#
# Usage:
#   test/mcpflagshipcheck.sh
#   CTXPACK_BIN=asan/ctxpack test/mcpflagshipcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.
# Does NOT edit regression.sh or golden.xml.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for JSON assertions"; exit 2; }
command -v git     >/dev/null 2>&1 || { echo "git required for the quality fixture"; exit 2; }

echo "mcpflagshipcheck: BIN=$BIN"

# ─── helper: send JSON-RPC lines, print every output line ─────────────────────
mcp_call() { printf '%s\n' "$@" | "$BIN" --mcp 2>/dev/null; }

# extract the inner text (or __ERROR__:code) of the last (id=2) tools/call response line.
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

# ─── build a synthetic git repo: a clear call chain + committed HEAD ──────────
REPO="$TMP/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email "setup@x.com"
git -C "$REPO" config user.name  "Setup"

cat >"$REPO/chain.cpp" <<'EOF'
// chain.cpp — a deterministic call chain leaf<-mid<-top, plus a variable use-site.
int gCounter = 0;
int leaf( int x ) { return x + 1; }
int mid( int x )  { gCounter = gCounter + 1; return leaf( x ) + leaf( x ); }
int top( int x )  { return mid( x ) + gCounter; }
EOF

git -C "$REPO" add chain.cpp
GIT_AUTHOR_DATE="2026-06-01T12:00:00" GIT_COMMITTER_DATE="2026-06-01T12:00:00" \
    git -C "$REPO" commit -q -m "init chain"

# ─── 1. tools/list — all 6 flagship verbs present with non-empty descriptions ─
echo
echo "=== 1. tools/list — flagship verbs advertised with non-empty descriptions ==="

mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | tail -1 >"$TMP/list.json"

python3 -c '
import sys, json
resp = json.load(open(sys.argv[1]))
if "error" in resp:
    print("ERROR:" + json.dumps(resp["error"])); sys.exit(0)
tools = resp["result"]["tools"]
byname = { t["name"]: t.get("description","") for t in tools }
want = ["exemplar","quality_delta","quality_baseline","impact","uses","path_between"]
print("TOTAL:" + str(len(tools)))
for w in want:
    if w not in byname:                     print("MISSING:" + w)
    elif not byname[w].strip():             print("EMPTYDESC:" + w)
    elif len(byname[w].strip()) < 40:       print("THINDESC:" + w)
    else:                                   print("OK:" + w)
# also assert NO tool has an empty description (audit: label-only descriptions)
for t in tools:
    if not t.get("description","").strip(): print("ANYEMPTY:" + t["name"])
' "$TMP/list.json" >"$TMP/list.check"

TOTAL="$( grep '^TOTAL:' "$TMP/list.check" | cut -d: -f2 )"
echo "  (tools/list advertises $TOTAL tools)"
for w in exemplar quality_delta quality_baseline impact uses path_between; do
    if grep -q "^OK:$w\$" "$TMP/list.check"; then ok "tools/list: '$w' listed with a descriptive description"
    else no "tools/list: '$w' missing/empty/thin — $( grep ":$w\$" "$TMP/list.check" )"; fi
done
if grep -q '^ANYEMPTY:' "$TMP/list.check"; then
    no "tools/list: some tool has an EMPTY description: $( grep '^ANYEMPTY:' "$TMP/list.check" )"
else
    ok "tools/list: no tool has an empty (label-only) description"
fi

# ─── 2. exemplar — returns a body ────────────────────────────────────────────
echo
echo "=== 2. exemplar — best-in-class instance WITH its body ==="

EX_MSGS=(
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}'
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"exemplar","arguments":{"path":"'"$REPO"'","kind":"fn"}}}'
)
mcp_call "${EX_MSGS[@]}" >"$TMP/ex_a"
mcp_call "${EX_MSGS[@]}" >"$TMP/ex_b"
EX_INNER="$( inner_of "$TMP/ex_a" )"
case "$EX_INNER" in
    __ERROR__*) no "exemplar returned error ${EX_INNER#__ERROR__:}";;
    "")         no "exemplar: inner text empty";;
    *)          ok "exemplar: returned non-empty text";;
esac
echo "$EX_INNER" | grep -q "<exemplar " && ok "exemplar: result contains <exemplar> element" || no "exemplar: no <exemplar> element"
# the body: packBodies emits a <b ...> body element (or the def source) inside <exemplar>. Assert a body tag
# is present AND that the chosen function's name appears (leaf/mid/top are the only fns).
echo "$EX_INNER" | grep -qE "leaf|mid|top" && ok "exemplar: body includes a real function name" || no "exemplar: body missing a function name"
# A3-F2 gate: the body must actually ARRIVE — a non-empty <bodies> holding a <b> CDATA block with real
# def source ("return" appears in every fixture fn). The 0-budget sentinel bug emitted a bare
# <bodies></bodies>, and the name-only grep above still passed (the name rides the <exemplar> attrs).
if echo "$EX_INNER" | grep -qE "<bodies [^>]*><b " && echo "$EX_INNER" | grep -q "CDATA" && echo "$EX_INNER" | grep -q "return"; then
    ok "exemplar: <bodies> is NON-EMPTY (<b> CDATA block with def source — A3-F2)"
else
    no "exemplar: <bodies> is EMPTY (no <b>/CDATA def source — A3-F2 0-budget sentinel) — got: $( echo "$EX_INNER" | head -c 300 )"
fi
diff -q "$TMP/ex_a" "$TMP/ex_b" >/dev/null && ok "exemplar: deterministic" || no "exemplar: non-deterministic"

# bad exemplar arg (a kind with no members: 'iface' — no interfaces in the fixture) → error, not silent empty
BAD_EX="$( mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"exemplar","arguments":{"path":"'"$REPO"'","kind":"iface"}}}' \
    | tail -1 | python3 -c 'import sys,json;r=json.load(sys.stdin);print("ERR:"+str(r["error"]["code"]) if "error" in r else "OK")' )"
[ "$BAD_EX" = "ERR:-32602" ] && ok "exemplar: no-candidate kind → -32602 (not a silent empty)" || no "exemplar: no-candidate did not error: $BAD_EX"

# ─── 3. quality_delta — baseline marker + regressions array ──────────────────
echo
echo "=== 3. quality_delta — clean tree (0 regressions vs git-HEAD), then detects a regression ==="

QD_MSGS=(
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}'
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"quality_delta","arguments":{"path":"'"$REPO"'"}}}'
)
mcp_call "${QD_MSGS[@]}" >"$TMP/qd_a"
mcp_call "${QD_MSGS[@]}" >"$TMP/qd_b"
QD_INNER="$( inner_of "$TMP/qd_a" )"
case "$QD_INNER" in
    __ERROR__*) no "quality_delta returned error ${QD_INNER#__ERROR__:}";;
    *)          ok "quality_delta: returned a result on a clean git fixture";;
esac
echo "$QD_INNER" | python3 -c '
import sys, json
r = json.load(sys.stdin)
assert "baseline" in r, "no baseline marker"
assert r["baseline"] == "git-HEAD", "expected baseline=git-HEAD on a clean fixture, got " + repr(r["baseline"])
# §B6 M5: the MCP payload now mirrors the CLI keys exactly — `regressions` is the INTEGER count and `r`
# is the array (it used to be the reverse here, so a script written against either surface misread the
# other). The assertion follows the CLI vocabulary; both halves are still checked.
assert isinstance(r.get("regressions"), int), "regressions is not an integer count (CLI vocabulary)"
assert isinstance(r.get("r"), list), "r is not an array"
assert r["regressions"] == 0 and len(r["r"]) == 0, "expected 0 regressions on a clean tree, got " + str(r["regressions"])
print("CLEAN_OK")
' >"$TMP/qd.clean" 2>"$TMP/qd.err" \
    && ok "quality_delta: clean tree → baseline=git-HEAD, regressions=[] (empty array)" \
    || no "quality_delta clean-tree shape: $( cat "$TMP/qd.err" )"
diff -q "$TMP/qd_a" "$TMP/qd_b" >/dev/null && ok "quality_delta: deterministic (clean tree)" || no "quality_delta: non-deterministic"

# now introduce a gnarly (high-complexity, deeply-nested) function in the WORKING TREE (uncommitted) → the
# delta vs HEAD must become non-empty (the exit-2-equivalent).
cat >>"$REPO/chain.cpp" <<'EOF'
int gnarly( int a ) {
  int r = 0;
  for( int i = 0; i < a; ++i ) { if( i%2 ) { if( i%3 ) { r += i; } else { r -= i; } } else { while( r > 100 ) { r -= 10; if( r < 0 ) break; } } }
  return r;
}
EOF
QD2="$( mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"quality_delta","arguments":{"path":"'"$REPO"'"}}}' \
    | tail -1 )"
echo "$( echo "$QD2" | python3 -c 'import sys,json;print(json.load(sys.stdin)["result"]["content"][0]["text"])' )" | python3 -c '
import sys, json
r = json.load(sys.stdin)
assert r["regressions"] > 0 and len(r["r"]) > 0, "expected regressions after adding a gnarly fn, got 0"
kinds = { x["kind"] for x in r["r"] }
assert "complexity" in kinds, "expected a complexity regression, got " + str(kinds)
print("REGRESSION_OK")
' >/dev/null 2>"$TMP/qd2.err" \
    && ok "quality_delta: detects the added-gnarly-fn regression (non-empty array; complexity)" \
    || no "quality_delta regression detection: $( cat "$TMP/qd2.err" )"

# ─── 4. quality_baseline — WRITES the sidecar with a head-sha stamp ──────────
echo
echo "=== 4. quality_baseline — writes .ctxpack_quality_baseline stamped with HEAD ==="

rm -f "$REPO/.ctxpack_quality_baseline"
QB="$( mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"quality_baseline","arguments":{"path":"'"$REPO"'"}}}' \
    | tail -1 )"
QB_INNER="$( echo "$QB" | python3 -c 'import sys,json;r=json.load(sys.stdin);print(r["result"]["content"][0]["text"] if "result" in r else "__ERROR__")' )"
case "$QB_INNER" in
    __ERROR__) no "quality_baseline returned an error";;
    *)         ok "quality_baseline: returned a result";;
esac
[ -f "$REPO/.ctxpack_quality_baseline" ] && ok "quality_baseline: wrote the .ctxpack_quality_baseline sidecar" || no "quality_baseline: sidecar NOT written"
# the sidecar carries a 'head <sha>' record; the HEAD of the fixture is a real 40-hex sha.
HEAD_SHA="$( git -C "$REPO" rev-parse HEAD )"
grep -q "head $HEAD_SHA" "$REPO/.ctxpack_quality_baseline" && ok "quality_baseline: sidecar stamped with the current HEAD sha" || no "quality_baseline: sidecar not stamped with HEAD ($HEAD_SHA)"
echo "$QB_INNER" | grep -q "$HEAD_SHA" && ok "quality_baseline: result JSON reports the head_sha" || no "quality_baseline: result JSON missing head_sha"

# after pinning, quality_delta must prefer the sidecar (baseline=sidecar). The gnarly fn is now BASELINED
# (it is in the working tree the sidecar snapshotted), so regressions return to 0 — confirms sidecar precedence.
QD3="$( mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"quality_delta","arguments":{"path":"'"$REPO"'"}}}' \
    | tail -1 | python3 -c 'import sys,json;print(json.load(sys.stdin)["result"]["content"][0]["text"])' )"
echo "$QD3" | python3 -c 'import sys,json;r=json.load(sys.stdin);print("SIDECAR_OK" if r["baseline"]=="sidecar" else "GOT:"+r["baseline"])' | grep -q SIDECAR_OK \
    && ok "quality_delta: honors the pinned sidecar (baseline=sidecar) after quality_baseline" \
    || no "quality_delta did not switch to the sidecar baseline"
rm -f "$REPO/.ctxpack_quality_baseline"

# ─── 5. impact / uses / path_between — expected symbols on the call chain ────
echo
echo "=== 5. impact / uses / path_between — the leaf<-mid<-top call chain ==="

# impact(leaf): mid and top both transitively reach leaf.
IMP_MSGS=(
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}'
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"impact","arguments":{"path":"'"$REPO"'","symbol":"leaf"}}}'
)
mcp_call "${IMP_MSGS[@]}" >"$TMP/imp_a"
mcp_call "${IMP_MSGS[@]}" >"$TMP/imp_b"
IMP_INNER="$( inner_of "$TMP/imp_a" )"
echo "$IMP_INNER" | grep -q "<impact " && ok "impact: result contains <impact> element" || no "impact: no <impact> element"
echo "$IMP_INNER" | grep -q 'n="mid"' && echo "$IMP_INNER" | grep -q 'n="top"' \
    && ok "impact(leaf): blast radius includes mid AND top (transitive)" \
    || no "impact(leaf): missing mid/top in blast radius — got: $( echo "$IMP_INNER" | head -c 200 )"
diff -q "$TMP/imp_a" "$TMP/imp_b" >/dev/null && ok "impact: deterministic" || no "impact: non-deterministic"

# uses(gCounter): a read AND a write site (mid writes it, top reads it).
USE_MSGS=(
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}'
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"uses","arguments":{"path":"'"$REPO"'","symbol":"gCounter"}}}'
)
mcp_call "${USE_MSGS[@]}" >"$TMP/use_a"
mcp_call "${USE_MSGS[@]}" >"$TMP/use_b"
USE_INNER="$( inner_of "$TMP/use_a" )"
echo "$USE_INNER" | grep -q "<uses " && ok "uses: result contains <uses> element" || no "uses: no <uses> element"
echo "$USE_INNER" | grep -q '<u ' && ok "uses(gCounter): at least one <u> use-site" || no "uses(gCounter): no use-sites — got: $( echo "$USE_INNER" | head -c 200 )"
diff -q "$TMP/use_a" "$TMP/use_b" >/dev/null && ok "uses: deterministic" || no "uses: non-deterministic"

# path_between(top,leaf): top -> mid -> leaf reaches, hops>=1.
PB_MSGS=(
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}'
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"path_between","arguments":{"path":"'"$REPO"'","from":"top","to":"leaf"}}}'
)
mcp_call "${PB_MSGS[@]}" >"$TMP/pb_a"
mcp_call "${PB_MSGS[@]}" >"$TMP/pb_b"
PB_INNER="$( inner_of "$TMP/pb_a" )"
echo "$PB_INNER" | grep -q '<path ' && ok "path_between: result contains <path> element" || no "path_between: no <path> element"
echo "$PB_INNER" | grep -q 'reachable="1"' && ok "path_between(top->leaf): reachable=1" || no "path_between(top->leaf): not reachable — got: $( echo "$PB_INNER" | head -c 200 )"
diff -q "$TMP/pb_a" "$TMP/pb_b" >/dev/null && ok "path_between: deterministic" || no "path_between: non-deterministic"

# ─── 6. bad symbol → standard -32602 not-found (never a silent empty) ────────
echo
echo "=== 6. bad symbol → standard -32602 not-found error (not a silent empty) ==="

err_code() {
    tail -1 "$1" | python3 -c 'import sys,json;r=json.load(sys.stdin);print(r["error"]["code"] if "error" in r else "NO_ERROR")'
}

mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"impact","arguments":{"path":"'"$REPO"'","symbol":"zzz_no_such"}}}' >"$TMP/imp_bad"
[ "$( err_code "$TMP/imp_bad" )" = "-32602" ] && ok "impact(bad symbol): -32602 not-found" || no "impact(bad symbol): expected -32602, got $( err_code "$TMP/imp_bad" )"

mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"path_between","arguments":{"path":"'"$REPO"'","from":"zzz_no_such","to":"leaf"}}}' >"$TMP/pb_bad"
[ "$( err_code "$TMP/pb_bad" )" = "-32602" ] && ok "path_between(bad endpoint): -32602 not-found" || no "path_between(bad endpoint): expected -32602, got $( err_code "$TMP/pb_bad" )"

# ─── Summary ─────────────────────────────────────────────────────────────────
echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
