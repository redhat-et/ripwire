#!/usr/bin/env bash
# mcphandlecheck.sh — gate for T4 (lazy bodies + stable content handles).
#
# Drives the MCP server over newline-delimited JSON-RPC (same piping as mcpverbscheck.sh) and proves the
# stable content-handle contract:
#   1. tools/list advertises the fetch_body verb.
#   2. a read verb (find_symbol) returns a `handle` on every symbol it surfaces (format sym#<16hex>@<16hex>).
#   3. fetch_body{handle} returns the EXACT def-span source (byte-compared against the source file's def line).
#   4. the handle is BYTE-IDENTICAL across two INDEPENDENT server processes (canonId + contentHash are
#      run-stable → warm==cold, process-independent).
#   5. a STALE handle (its file changed since issue) is REFUSED with no body returned.
#   6. a garbage / hand-mutated (non-existent-id) handle is REFUSED (no mis-resolve, no body).
#   6b. R2c: a bare symbol NAME is accepted where a handle is expected, disclosed via resolved_from_name.
#   6c. V3/RN1: a handle that missed only because the request omitted `path` names `path` as the cause and
#       says which root answered — instead of blaming a rename nobody made.
#   7. determinism: two find_symbol calls are byte-identical.
#   8. every response line is valid JSON.
#
# Mutation-tested: removing the handle attribute fails step 2; making fetch_body ignore contentHash fails
# step 5; accepting any hex string fails step 6.
#
# Usage:
#   test/mcphandlecheck.sh                          # uses build/ripwire
#   RIPWIRE_BIN=asan/ripwire test/mcphandlecheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success. Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for JSON assertions"; exit 2; }

echo "mcphandlecheck: BIN=$BIN"

# Work on a PRIVATE copy of the zoomfix corpus so we can mutate a file for the staleness test.
CORPUS="$TMP/corpus"
cp -R "$ROOT/test/zoomfix" "$CORPUS"

SYM="engineStepA2"                 # one-line def in core/engine.cpp of the zoomfix corpus
SRCFILE="$CORPUS/core/engine.cpp"

# Send JSON-RPC messages to a fresh MCP server process; print all output lines.
mcp_call() { printf '%s\n' "$@" | "$BIN" --mcp 2>/dev/null; }

# Extract the `handle` field of the top-level `symbol` from a find_symbol response line-stream on stdin.
handle_of_symbol() {
    tail -1 | python3 -c '
import sys, json
r = json.load(sys.stdin)
if "error" in r: print("__ERR__:" + json.dumps(r["error"])); sys.exit(0)
print(json.loads(r["result"]["content"][0]["text"])["symbol"]["handle"])
'
}

FIND_MSGS=(
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}'
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"find_symbol","arguments":{"path":"'"$CORPUS"'","symbol":"'"$SYM"'"}}}'
)

echo
echo "=== 1. tools/list — assert 'fetch_body' verb is listed ==="
LIST_OUT="$( mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | tail -1 )"
python3 -c '
import sys, json
names = [t["name"] for t in json.loads(sys.argv[1])["result"]["tools"]]
print("FETCH_OK" if "fetch_body" in names else "MISSING")
' "$LIST_OUT" > "$TMP/listchk"
grep -q FETCH_OK "$TMP/listchk" && ok "fetch_body tool is listed" || no "fetch_body tool MISSING from tools/list"

echo
echo "=== 2. find_symbol returns a well-formed handle on every surfaced symbol ==="
mcp_call "${FIND_MSGS[@]}" | tail -1 > "$TMP/find_a"
python3 -c '
import sys, json, re
r = json.load(open(sys.argv[1]))
d = json.loads(r["result"]["content"][0]["text"])
syms = [d["symbol"]] + d.get("calledBy", []) + d.get("calls", [])
missing = [s["name"] for s in syms if not s.get("handle")]
bad = [s["handle"] for s in syms if s.get("handle") and not re.fullmatch(r"sym#[0-9a-f]{16}@[0-9a-f]{16}", s["handle"])]
print("NO_HANDLE:" + ",".join(missing) if missing else "ALL_HAVE_HANDLE")
print("BAD_FORMAT:" + ",".join(bad) if bad else "FORMAT_OK")
' "$TMP/find_a" > "$TMP/hchk"
grep -q ALL_HAVE_HANDLE "$TMP/hchk" && ok "every symbol carries a handle" || no "$(grep NO_HANDLE "$TMP/hchk")"
grep -q FORMAT_OK      "$TMP/hchk" && ok "handles match sym#<16hex>@<16hex>" || no "$(grep BAD_FORMAT "$TMP/hchk")"

H="$( mcp_call "${FIND_MSGS[@]}" | handle_of_symbol )"
# Hard gate: every later step depends on H being a REAL handle. A missing/garbage H (e.g. the handle
# attribute was removed) must FAIL loudly here, never let a later step spuriously "pass" on a broken H.
if ! printf '%s' "$H" | grep -Eq '^sym#[0-9a-f]{16}@[0-9a-f]{16}$'; then
    no "could not obtain a valid handle (got: '$H') — aborting handle-dependent checks"
    echo; echo "SOME CHECKS FAILED"; exit 1
fi
ok "obtained handle: $H"

echo
echo "=== 3. fetch_body{handle} returns the EXACT def-span source ==="
mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"fetch_body","arguments":{"path":"'"$CORPUS"'","handle":"'"$H"'"}}}' \
    | tail -1 > "$TMP/fetch_a"
python3 -c '
import sys, json
r = json.load(open(sys.argv[1]))
if "error" in r: print("__ERR__:" + json.dumps(r["error"])); sys.exit(0)
b = json.loads(r["result"]["content"][0]["text"])
open(sys.argv[2], "w").write(b["body"])
print("BYTES:" + str(b["bytes"]))
' "$TMP/fetch_a" "$TMP/body_got" > "$TMP/fetchmeta" 2>&1
if grep -q __ERR__ "$TMP/fetchmeta"; then
    no "fetch_body returned an error: $(cat "$TMP/fetchmeta")"
else
    grep -F "int ${SYM}(" "$SRCFILE" | head -1 > "$TMP/body_truth"
    if [ "$(cat "$TMP/body_got")" = "$(cat "$TMP/body_truth")" ]; then
        ok "fetch_body body byte-matches the source def span"
    else
        no "fetch_body body != source span"
        echo "    got:   $(cat "$TMP/body_got")"
        echo "    truth: $(cat "$TMP/body_truth")"
    fi
fi

echo
echo "=== 4. handle is byte-identical across TWO independent server processes ==="
H1="$( mcp_call "${FIND_MSGS[@]}" | handle_of_symbol )"
H2="$( mcp_call "${FIND_MSGS[@]}" | handle_of_symbol )"
[ "$H1" = "$H2" ] && ok "handle stable across two processes ($H1)" || no "handle differs across processes: $H1 vs $H2"

echo
echo "=== 5. STALE handle is REFUSED (file changed since issue), no body returned ==="
printf '// mutation to change file bytes for the staleness test\n' >> "$SRCFILE"
mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"fetch_body","arguments":{"path":"'"$CORPUS"'","handle":"'"$H"'"}}}' \
    | tail -1 > "$TMP/stale"
python3 -c '
import sys, json
r = json.load(open(sys.argv[1]))
has_result = "result" in r
code = r.get("error", {}).get("code")
msg  = r.get("error", {}).get("message", "")
print("STALE_REFUSED" if (not has_result and code == -32602 and "stale" in msg) else "STALE_SERVED:" + json.dumps(r)[:200])
' "$TMP/stale" > "$TMP/stalechk"
grep -q STALE_REFUSED "$TMP/stalechk" && ok "stale handle refused with -32602 'stale', no body" || no "stale handle NOT refused: $(cat "$TMP/stalechk")"

echo
echo "=== 6. garbage / mutated handle is REFUSED ==="
mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"fetch_body","arguments":{"path":"'"$CORPUS"'","handle":"not-a-handle"}}}' \
    | tail -1 > "$TMP/garbage"
python3 -c '
import sys, json
r = json.load(open(sys.argv[1]))
print("GARBAGE_REFUSED" if ("result" not in r and r.get("error",{}).get("code")==-32602) else "GARBAGE_SERVED")
' "$TMP/garbage" > "$TMP/gchk"
grep -q GARBAGE_REFUSED "$TMP/gchk" && ok "garbage handle refused" || no "garbage handle NOT refused"

# well-formed but non-existent id: flip the first id hex nibble deterministically → resolves to nothing.
MUT="$( python3 -c '
import sys
h=sys.argv[1]
c=h[4]; nc="0" if c!="0" else "1"
print(h[:4]+nc+h[5:])
' "$H" )"
mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"fetch_body","arguments":{"path":"'"$CORPUS"'","handle":"'"$MUT"'"}}}' \
    | tail -1 > "$TMP/mut"
python3 -c '
import sys, json
r = json.load(open(sys.argv[1]))
print("MUT_REFUSED" if ("result" not in r and r.get("error",{}).get("code")==-32602) else "MUT_SERVED:" + json.dumps(r)[:160])
' "$TMP/mut" > "$TMP/mchk"
grep -q MUT_REFUSED "$TMP/mchk" && ok "mutated (non-existent id) handle refused, no body" || no "mutated handle NOT refused: $(cat "$TMP/mchk")"

echo
echo "=== 6b. R2c (the 2026-08-12 usage mine): a bare symbol NAME is accepted where a handle is expected ==="
# fetch_body's strict handle parse stays (steps 5/6 above are untouched contracts), but a string that is
# not even handle-SHAPED is now tried as a symbol name through the same lookup path find_symbol uses
# (resolveAllByNameQualified, lowest-id pick), DISCLOSED via resolved_from_name + the REAL handle in the
# result — so the one-shot answer also teaches the handle for next time. A "sym#..."-prefixed string is
# NEVER treated as a name (a corrupt real handle must keep the malformed refusal — step 6's guard).

# (6b-1) [red] the bare name serves the same body a real handle serves, and disclosure rides the result
mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"fetch_body","arguments":{"path":"'"$CORPUS"'","handle":"engineStepA2"}}}' \
    | tail -1 > "$TMP/byname"
python3 -c '
import sys, json
r = json.load(open(sys.argv[1]))
if "result" not in r: print("NAME_REFUSED:" + r.get("error",{}).get("message","")[:160]); sys.exit(0)
j = json.loads(r["result"]["content"][0]["text"])
okBody   = "engineStepA1() + engineStepA1()" in j.get("body","")
okHandle = str(j.get("handle","")).startswith("sym#")
okDisc   = j.get("resolved_from_name") == "engineStepA2"
print("NAME_OK" if (okBody and okHandle and okDisc) else "NAME_BAD:body=%s handle=%s disc=%s" % (okBody, okHandle, j.get("resolved_from_name")))
' "$TMP/byname" > "$TMP/bynamechk"
grep -q NAME_OK "$TMP/bynamechk" \
    && ok "(6b-1) [red] bare name serves the def body + the REAL handle + resolved_from_name disclosure" \
    || no "(6b-1) [red] $(cat "$TMP/bynamechk")"

# (6b-2) [red] an unknown bare name refuses with a did-you-mean + the find_symbol pointer (one-shot recovery)
mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"fetch_body","arguments":{"path":"'"$CORPUS"'","handle":"engineStepA2x"}}}' \
    | tail -1 > "$TMP/badname"
python3 -c '
import sys, json
r = json.load(open(sys.argv[1]))
m = r.get("error",{}).get("message","")
okCode = "result" not in r and r.get("error",{}).get("code") == -32602
print("BADNAME_OK" if (okCode and "did you mean" in m and "engineStepA2" in m and "find_symbol" in m) else "BADNAME_BAD:" + m[:200])
' "$TMP/badname" > "$TMP/badnamechk"
grep -q BADNAME_OK "$TMP/badnamechk" \
    && ok "(6b-2) [red] unknown bare name refused WITH did-you-mean + find_symbol pointer" \
    || no "(6b-2) [red] $(cat "$TMP/badnamechk")"

# (6b-3) guard: a "sym#"-prefixed corrupt handle keeps the malformed-handle refusal (never a name lookup)
mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"fetch_body","arguments":{"path":"'"$CORPUS"'","handle":"sym#garbage"}}}' \
    | tail -1 > "$TMP/symgarb"
python3 -c '
import sys, json
r = json.load(open(sys.argv[1]))
m = r.get("error",{}).get("message","")
print("GUARD_OK" if ("result" not in r and "malformed handle" in m) else "GUARD_BAD:" + m[:160])
' "$TMP/symgarb" > "$TMP/symgarbchk"
grep -q GUARD_OK "$TMP/symgarbchk" \
    && ok "(6b-3) 'sym#'-prefixed garbage keeps the malformed-handle refusal (no name fallback)" \
    || no "(6b-3) $(cat "$TMP/symgarbchk")"

# (6b-4) [red] same-named defs in DIFFERENT files: serve the lowest-id pick, DISCLOSE the others
#         (name_defs + other_defs with file:line + each one's handle — the honest sibling of step 2b'\''s
#         overload note, for the name path). A second def is planted in the PRIVATE corpus copy.
printf 'int dupTwinFn( int x ) { return x + 1; }\n'  > "$CORPUS/core/twin_a.cpp"
printf 'int dupTwinFn( int x ) { return x + 2; }\n'  > "$CORPUS/util/twin_b.cpp"
mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"fetch_body","arguments":{"path":"'"$CORPUS"'","handle":"dupTwinFn"}}}' \
    | tail -1 > "$TMP/dupname"
python3 -c '
import sys, json
r = json.load(open(sys.argv[1]))
if "result" not in r: print("DUP_REFUSED:" + r.get("error",{}).get("message","")[:160]); sys.exit(0)
j = json.loads(r["result"]["content"][0]["text"])
others = j.get("other_defs", [])
okN    = j.get("name_defs") == 2
okO    = len(others) == 1 and str(others[0].get("handle","")).startswith("sym#") and "twin_" in others[0].get("file","")
print("DUP_OK" if (okN and okO) else "DUP_BAD:name_defs=%s others=%s" % (j.get("name_defs"), json.dumps(others)[:160]))
' "$TMP/dupname" > "$TMP/dupchk"
grep -q DUP_OK "$TMP/dupchk" \
    && ok "(6b-4) [red] same-named defs: lowest-id pick served, name_defs + other_defs disclosed" \
    || no "(6b-4) [red] $(cat "$TMP/dupchk")"

# (6b-5) determinism: the by-name fetch is byte-identical across two server processes. Two FRESH calls
#         (6b-4 planted the twin files, so the pre-plant capture from 6b-1 is a different corpus state —
#         comparing against it would measure the plant, not the tool).
for d in det_n1 det_n2; do
    mcp_call \
        '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
        '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"fetch_body","arguments":{"path":"'"$CORPUS"'","handle":"engineStepA2"}}}' \
        | tail -1 > "$TMP/$d"
done
diff -q "$TMP/det_n1" "$TMP/det_n2" >/dev/null \
    && ok "(6b-5) by-name fetch byte-identical across processes" \
    || no "(6b-5) by-name fetch differs across processes"

echo
echo "=== 6c. RN1: a handle that failed only because the request omitted \`path\` says SO ==="
# THE FINDING (lightrag recon RN1, 2026-08-15): a handle minted by find_symbol{path:A} and then handed to
# fetch_body WITHOUT `path` resolves against whatever root the SERVER supplied for the omitted field (the
# R2a launch cwd, or a startup/pinned root) — a DIFFERENT index, in which the handle's stable id does not
# exist. The refusal blamed STALENESS: "may have been renamed or removed; call a read verb to refresh".
# That sends the caller to re-read a symbol that is fine, and it cost two dead-end round trips before the
# real cause — an omitted argument — was even a hypothesis.
#
# Handles stay path-qualified: an UNSCOPED free function's stable id is only unique within its file, so
# the path is load-bearing and the handle FORMAT does not change (steps 4/5/6 are the contracts a format
# change would break). What changes is the SENTENCE. When the root was not the caller's, the refusal names
# `path` as the recoverable cause and says which root actually answered, instead of asserting a rename
# nobody made. When the caller DID name the tree, the rename/removal sentence is still the true one —
# 6c-2 is that guard, because a clause pasted onto every refusal explains nothing.
ELSEWHERE="$( cd "$TMP" && mkdir -p elsewhere && cd elsewhere && pwd -P )"
printf 'int unrelatedLeaf( void ) { return 0; }\n' > "$ELSEWHERE/unrelated.c"

# The REALPATH of the corpus, because that is what the server assumes for an omitted `path` (the launch
# cwd, canonicalized). On macOS $TMPDIR is a /var -> /private/var symlink, so minting the handle against
# the un-canonicalized spelling and fetching it against the canonical one is a THIRD spelling of this same
# bug (two names for one directory index to two different file paths, so the path-qualified handle misses).
# 6c-3's job is the no-false-refusal guard, so it holds the spelling constant and varies only the argument.
CORPUS_REAL="$( cd "$CORPUS" && pwd -P )"

# A FRESH handle: step 5 mutated the source file and 6b-4 planted twins, so H (minted at step 2) is now
# STALE against the corpus — and a stale handle refuses for a different, already-correct reason. Minting
# here keeps 6c about the missing-argument cause and nothing else.
H3="$( mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"find_symbol","arguments":{"path":"'"$CORPUS_REAL"'","symbol":"'"$SYM"'"}}}' \
    | handle_of_symbol )"
if ! printf '%s' "$H3" | grep -Eq '^sym#[0-9a-f]{16}@[0-9a-f]{16}$'; then
    no "(6c) could not mint a fresh handle (got: '$H3') — skipping the omitted-path arms"
else

# (6c-1) [red] handle + NO path, from a server whose assumed root is a DIFFERENT tree
printf '%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"fetch_body","arguments":{"handle":"'"$H3"'"}}}' \
    | ( cd "$ELSEWHERE" && "$BIN" --mcp 2>/dev/null ) | tail -1 > "$TMP/nopath"
python3 -c '
import sys, json
r = json.load(open(sys.argv[1]))
if "result" in r: print("SERVED_ANYWAY"); sys.exit(0)
m   = r.get("error", {}).get("message", "")
low = m.lower()
problems = []
if r.get("error", {}).get("code") != -32602: problems.append("wrong error code")
if "path" not in low:                        problems.append("the refusal never names the `path` argument")
if sys.argv[2] not in m:                     problems.append("the refusal never says which root answered")
print("NOPATH_OK" if not problems else "NOPATH_BAD:" + "; ".join(problems) + " || " + m[:220])
' "$TMP/nopath" "$ELSEWHERE" > "$TMP/nopathchk"
grep -q NOPATH_OK "$TMP/nopathchk" \
    && ok "(6c-1) [red] omitted-path handle failure names \`path\` and the root that answered" \
    || no "(6c-1) [red] $(cat "$TMP/nopathchk")"

# (6c-2) guard: when the CALLER named the tree, a genuinely unresolvable handle keeps the rename/removal
#        sentence — the missing-argument clause must not be pasted onto a refusal it does not explain.
printf '%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"fetch_body","arguments":{"path":"'"$ELSEWHERE"'","handle":"'"$H3"'"}}}' \
    | ( cd "$ELSEWHERE" && "$BIN" --mcp 2>/dev/null ) | tail -1 > "$TMP/withpath"
python3 -c '
import sys, json
r = json.load(open(sys.argv[1]))
if "result" in r: print("SERVED_ANYWAY"); sys.exit(0)
m = r.get("error", {}).get("message", "")
okRename = "renamed or removed" in m
okNoNag  = "did not name a tree" not in m.lower()
print("WITHPATH_OK" if (okRename and okNoNag) else "WITHPATH_BAD:" + m[:220])
' "$TMP/withpath" > "$TMP/withpathchk"
grep -q WITHPATH_OK "$TMP/withpathchk" \
    && ok "(6c-2) an explicit path keeps the rename/removal sentence (no false missing-argument clause)" \
    || no "(6c-2) $(cat "$TMP/withpathchk")"

# (6c-3) guard: an omitted path whose assumed root DOES contain the symbol still serves the body — the
#        clause is a refusal refinement, never a new refusal.
printf '%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"fetch_body","arguments":{"handle":"'"$H3"'"}}}' \
    | ( cd "$CORPUS_REAL" && "$BIN" --mcp 2>/dev/null ) | tail -1 > "$TMP/nopath_ok"
python3 -c '
import sys, json
r = json.load(open(sys.argv[1]))
print("SERVE_OK" if "result" in r else "SERVE_BAD:" + r.get("error",{}).get("message","")[:160])
' "$TMP/nopath_ok" > "$TMP/nopathokchk"
grep -q SERVE_OK "$TMP/nopathokchk" \
    && ok "(6c-3) an omitted path that DOES resolve still serves the body" \
    || no "(6c-3) $(cat "$TMP/nopathokchk")"

fi

echo
echo "=== 7. determinism: two find_symbol calls byte-identical ==="
mcp_call "${FIND_MSGS[@]}" > "$TMP/det_a"
mcp_call "${FIND_MSGS[@]}" > "$TMP/det_b"
diff -q "$TMP/det_a" "$TMP/det_b" >/dev/null && ok "find_symbol deterministic (byte-identical)" || no "find_symbol non-deterministic"

echo
echo "=== 8. every response line is valid JSON ==="
mcp_call "${FIND_MSGS[@]}" > "$TMP/json_lines"
python3 -c '
import sys, json
bad = 0
for i, ln in enumerate(open(sys.argv[1]), 1):
    ln = ln.strip()
    if not ln: continue
    try: json.loads(ln)
    except Exception as e: print("LINE", i, "INVALID:", e); bad += 1
print("JSON_OK" if bad == 0 else "JSON_BAD:" + str(bad))
' "$TMP/json_lines" > "$TMP/jchk"
grep -q JSON_OK "$TMP/jchk" && ok "all response lines are valid JSON" || no "$(grep -v JSON_OK "$TMP/jchk")"

echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
