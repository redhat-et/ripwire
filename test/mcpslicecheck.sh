#!/usr/bin/env bash
# mcpslicecheck.sh — gate for the MCP `slice` verb: the ARISE def-use slice served over MCP, mirroring
# the CLI --slice contract refusal-for-refusal (the mcpflagshipcheck pattern: advertise, validate, serve).
#
# RED-FIRST PROOF SHAPE: the baseline binary advertises NO `slice` tool and answers tools/call
# name="slice" with the unknown-tool refusal — so every arm asserts slice-SPECIFIC bytes (the stanza,
# a <slice> payload, a refusal sentence only this verb speaks), never a bare exit code.
#
# Arms:
#   (1)  tools/list advertises `slice` with an HONEST description (name-based, intra-procedural,
#        served languages, the @FILE:LINE seed) — and the catalog count grew to 31
#   (2)  bare inventory: symbol only -> <v> rows + vars=
#   (3)  var slice: the `var` field, and the symbol="SYM:VAR" spelling, byte-identical
#   (4)  flow: back from `out` includes stray, excludes dead (the stray/dead asymmetry over MCP)
#   (5)  depth: honored + disclosed when it cuts; out-of-band and flow-less depth refused
#   (6)  unknown flow direction refused naming back|fwd|both
#   (7)  @FILE:LINE seed: pre-pick + disclosure; a faulted seed refuses with the at-diagnosis
#   (8)  not-found and ambiguity refusals (-32602, spellings listed) — never a silent pick
#   (9)  unknown var refused listing the sliceable locals
#   (10) unserved language refused naming the served list
#   (11) determinism (x2, byte-identical payload)
#   (12) multi-root `paths` refused single-root (the kMcpSingleRootVerbs gate)
#   (13) CLI parity: the MCP payload is byte-identical to the CLI --slice on the same root
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/mcpslicecheck.sh   |   bash test/mcpslicecheck.sh path/to/ripwire

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

echo "mcpslicecheck: BIN=$BIN"

# ─── the fixture: the sliceflowcheck corpus shape (line numbers are load-bearing) ─────────────────────
REPO="$TMP/repo"
mkdir -p "$REPO/src"
cat > "$REPO/src/a.cpp" <<'EOF'
void sink( int v );

int pipeline( int seed )
{
    int mid = seed + 1;
    int out = mid * 2;
    int stray = 7;
    out += stray;
    int dead = seed - 1;
    sink( dead );
    return out;
}

int helper( int q )
{
    int r = q + 3;
    return r;
}
EOF
cat > "$REPO/src/b.cpp" <<'EOF'
int helper( int z )
{
    return z * 2;
}
EOF
# an indexed language --slice does NOT serve (bash) — arm (10)'s fuel
cat > "$REPO/tool.sh" <<'EOF'
shfunc() {
    echo hi
}
EOF

# ─── helpers: JSON-RPC over stdio; inner text (or __ERROR__:msg) of the id=2 response ────────────────
mcp_call() { printf '%s\n' "$@" | ( cd "$REPO" && "$BIN" --mcp 2>/dev/null ); }
call_slice() {   # call_slice '<json-arguments-object>' — path "." resolves against the fixture cwd
    mcp_call \
        '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
        "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"slice\",\"arguments\":$1}}" \
        | tail -1 | python3 -c '
import sys, json
r = json.load(sys.stdin)
if "error" in r:
    print("__ERROR__:" + str(r["error"].get("code")) + ":" + r["error"].get("message",""))
else:
    print(r["result"]["content"][0]["text"])
'
}

# ── (1) tools/list: advertised, honest, and the catalog count moved to 31 ───────────────────────────
LIST="$( mcp_call '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | tail -1 )"
printf '%s' "$LIST" | python3 -c '
import sys, json
r = json.load(sys.stdin)
tools = { t["name"]: t.get("description","") for t in r["result"]["tools"] }
print("COUNT:%d" % len(tools))
d = tools.get("slice","")
print("HAS:%d" % ("slice" in tools))
for probe, tag in [("NAME-BASED","namebased"),("intra-procedural","intraproc"),("Go, Java, Rust","langs"),("@FILE:LINE","atseed"),("back","flowdoc")]:
    print("%s:%d" % (tag, probe in d))
' > "$TMP/list.probe"
grep -q '^HAS:1' "$TMP/list.probe" && ok "(1) tools/list advertises 'slice'" || no "(1) 'slice' missing from tools/list"
[ "$( grep '^COUNT:' "$TMP/list.probe" | cut -d: -f2 )" = "31" ] \
    && ok "(1) the catalog advertises 31 tools" \
    || no "(1) expected 31 advertised tools, got $( grep '^COUNT:' "$TMP/list.probe" | cut -d: -f2 )"
for t in namebased intraproc langs atseed flowdoc; do
    grep -q "^$t:1" "$TMP/list.probe" && ok "(1) description carries the '$t' honesty clause" \
                                      || no "(1) description misses the '$t' clause"
done

# ── (2) bare inventory ──────────────────────────────────────────────────────────────────────────────
INV="$( call_slice '{"path":".","symbol":"pipeline"}' )"
printf '%s' "$INV" | grep -q 'vars="5"' && printf '%s' "$INV" | grep -q '<v n="mid"' \
    && ok "(2) bare symbol serves the sliceable-locals inventory (vars=\"5\")" \
    || { no "(2) expected the inventory with vars=\"5\" and a mid row"; printf '%s\n' "$INV" | head -c 400; echo; }

# ── (3) var slice: the var field, and the SYM:VAR spelling, byte-identical ──────────────────────────
V1="$( call_slice '{"path":".","symbol":"pipeline","var":"out"}' )"
V2="$( call_slice '{"path":".","symbol":"pipeline:out"}' )"
printf '%s' "$V1" | grep -q 'var="out"' && printf '%s' "$V1" | grep -q '<s l="8" k="both"' \
    && ok "(3) var slice serves out's def-use rows (the += line k=\"both\")" \
    || { no "(3) expected var=\"out\" rows"; printf '%s\n' "$V1" | head -c 400; echo; }
[ -n "$V1" ] && [ "$V1" = "$V2" ] \
    && ok "(3) the var field and the SYM:VAR spelling answer byte-identically" \
    || no "(3) var-field and SYM:VAR answers differ"

# ── (4) flow over MCP: the stray/dead asymmetry ─────────────────────────────────────────────────────
FB="$( call_slice '{"path":".","symbol":"pipeline","var":"out","flow":"back"}' )"
printf '%s' "$FB" | grep -q 'flow="back"' && printf '%s' "$FB" | grep -q 'v="stray"' \
    && ok "(4) flow=back carries the flow attributes and pulls stray in" \
    || { no "(4) expected flow=\"back\" with a v=\"stray\" row"; printf '%s\n' "$FB" | head -c 400; echo; }
printf '%s' "$FB" | grep -q 'v="dead"' \
    && no "(4) dead must NOT be in the backward slice of out" \
    || ok "(4) dead stays out backward — reachability, not proximity"

# ── (5) depth: honored + disclosed; refused out of band or without flow ─────────────────────────────
FD="$( call_slice '{"path":".","symbol":"pipeline","var":"seed","flow":"fwd","depth":2}' )"
printf '%s' "$FD" | grep -q 'depth="2"' && printf '%s' "$FD" | grep -q 'flow_truncated="1"' \
    && ok "(5) depth=2 echoed and the cut disclosed (flow_truncated=\"1\")" \
    || { no "(5) expected depth=\"2\" flow_truncated=\"1\""; printf '%s\n' "$FD" | head -c 400; echo; }
E5a="$( call_slice '{"path":".","symbol":"pipeline","var":"out","flow":"fwd","depth":33}' )"
printf '%s' "$E5a" | grep -q '^__ERROR__' && printf '%s' "$E5a" | grep -q '1\.\.32' \
    && ok "(5) depth=33 refused naming the 1..32 band" \
    || { no "(5) expected the band refusal for depth=33"; printf '%s\n' "$E5a"; }
E5b="$( call_slice '{"path":".","symbol":"pipeline","var":"out","depth":4}' )"
printf '%s' "$E5b" | grep -q '^__ERROR__' && printf '%s' "$E5b" | grep -qi 'flow' \
    && ok "(5) depth without flow refused — there is nothing to bound" \
    || { no "(5) expected the depth-without-flow refusal"; printf '%s\n' "$E5b"; }

# ── (6) unknown flow direction ──────────────────────────────────────────────────────────────────────
E6="$( call_slice '{"path":".","symbol":"pipeline","var":"out","flow":"diagonal"}' )"
printf '%s' "$E6" | grep -q '^__ERROR__' && printf '%s' "$E6" | grep -q 'back|fwd|both' \
    && ok "(6) unknown direction refused, values named (back|fwd|both)" \
    || { no "(6) expected the direction refusal"; printf '%s\n' "$E6"; }

# ── (7) the @FILE:LINE seed: pre-pick + disclosure; faults diagnosed ────────────────────────────────
S7="$( call_slice '{"path":".","symbol":"@src/a.cpp:7"}' )"
printf '%s' "$S7" | grep -q 'var="stray"' && printf '%s' "$S7" | grep -q 'var_from="seed"' \
    && printf '%s' "$S7" | grep -q 'seed="src/a.cpp:7"' \
    && ok "(7) @src/a.cpp:7 pre-picks stray with the seed disclosure" \
    || { no "(7) expected var=\"stray\" var_from=\"seed\" seed=\"src/a.cpp:7\""; printf '%s\n' "$S7" | head -c 400; echo; }
S7b="$( call_slice '{"path":".","symbol":"@src/a.cpp:5"}' )"
printf '%s' "$S7b" | grep -q 'seed_vars="2"' && printf '%s' "$S7b" | grep -q '<v n="mid"[^>]*seed="1"' \
    && ok "(7) a two-candidate seed line serves the marked inventory (seed_vars=\"2\")" \
    || { no "(7) expected the candidate-marked inventory"; printf '%s\n' "$S7b" | head -c 400; echo; }
E7="$( call_slice '{"path":".","symbol":"@src/a.cpp:999"}' )"
printf '%s' "$E7" | grep -q '^__ERROR__' && printf '%s' "$E7" | grep -q 'has only' \
    && ok "(7) a seed past EOF refuses with the shared at-diagnosis" \
    || { no "(7) expected the line-out-of-range diagnosis"; printf '%s\n' "$E7"; }

# ── (8) not-found and ambiguity — never a silent pick ───────────────────────────────────────────────
E8a="$( call_slice '{"path":".","symbol":"nosuchsym"}' )"
printf '%s' "$E8a" | grep -q '^__ERROR__:-32602' \
    && ok "(8) unknown symbol refuses -32602" \
    || { no "(8) expected -32602 for an unknown symbol"; printf '%s\n' "$E8a"; }
E8b="$( call_slice '{"path":".","symbol":"helper"}' )"
printf '%s' "$E8b" | grep -q '^__ERROR__' && printf '%s' "$E8b" | grep -q 'a.cpp' && printf '%s' "$E8b" | grep -q 'b.cpp' \
    && ok "(8) a 2-definition symbol refuses listing the spellings that pick one" \
    || { no "(8) expected the ambiguity refusal naming both files"; printf '%s\n' "$E8b"; }

# ── (9) unknown var lists the sliceable locals ──────────────────────────────────────────────────────
E9="$( call_slice '{"path":".","symbol":"pipeline","var":"nosuchvar"}' )"
printf '%s' "$E9" | grep -q '^__ERROR__' && printf '%s' "$E9" | grep -q 'stray' \
    && ok "(9) unknown var refused, sliceable locals listed" \
    || { no "(9) expected the locals-listing refusal"; printf '%s\n' "$E9"; }

# ── (10) unserved language refuses naming the served list ───────────────────────────────────────────
E10="$( call_slice '{"path":".","symbol":"shfunc"}' )"
printf '%s' "$E10" | grep -q '^__ERROR__' && printf '%s' "$E10" | grep -q 'not served' \
    && ok "(10) an unserved language refuses loudly, never an empty success" \
    || { no "(10) expected the served-language refusal for a bash symbol"; printf '%s\n' "$E10"; }

# ── (11) determinism ────────────────────────────────────────────────────────────────────────────────
D1="$( call_slice '{"path":".","symbol":"pipeline","var":"out","flow":"both"}' )"
D2="$( call_slice '{"path":".","symbol":"pipeline","var":"out","flow":"both"}' )"
[ -n "$D1" ] && [ "$D1" = "$D2" ] \
    && ok "(11) determinism: repeated MCP slice calls byte-identical" \
    || no "(11) determinism: repeated calls differ or emitted nothing"

# ── (12) multi-root workspace refused single-root ───────────────────────────────────────────────────
mkdir -p "$TMP/r2"; cp "$REPO/src/b.cpp" "$TMP/r2/b.cpp"
E12="$( mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"slice\",\"arguments\":{\"paths\":[\".\",\"$TMP/r2\"],\"symbol\":\"pipeline\"}}}" \
    | tail -1 )"
printf '%s' "$E12" | grep -q 'single' && printf '%s' "$E12" | grep -q 'error' \
    && ok "(12) a paths workspace refuses: slice is single-root (per-root re-parse)" \
    || { no "(12) expected the single-root refusal on a 2-root workspace"; printf '%s\n' "$E12" | head -c 300; echo; }

# ── (13) CLI parity: same root, same spec, byte-identical payload ───────────────────────────────────
CLI="$( cd "$REPO" && "$BIN" . --slice=pipeline:out --no-cache 2>/dev/null )"
[ -n "$V1" ] && [ "$V1" = "$CLI" ] \
    && ok "(13) the MCP payload is byte-identical to the CLI --slice on the same root" \
    || no "(13) MCP and CLI slice payloads differ on the same root/spec"

[ "$fail" = 0 ] && printf 'ALL PASS\n' || printf 'FAILURES ABOVE\n'
exit "$fail"
