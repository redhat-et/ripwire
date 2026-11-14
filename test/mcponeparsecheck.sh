#!/usr/bin/env bash
# mcponeparsecheck.sh — ONE-PARSE (MCP half): the MCP server and the CLI rich verbs share ONE parse cache blob per root.
#
# The server's ingest is the CLI rich verbs' ingest with the CLI defaults (mcpindex.h mcpCachePath), and it used to write
# a third blob of its own (`ripwire-mcp-<key>-<tag>.cache`), so a server started after a CLI `--for` parsed the whole
# tree again (envoy: 350 G instructions, about 20 s), and the reverse too. Now both read and write the rich blob.
#
#   arm 1 (premise): a CLI `--for` on a fresh cache dir parses every file (reparsed=N > 0) and writes a rich blob;
#         FAIL on zero, or arm 2 proves nothing.
#   arm 2: an MCP server started next, on the same cache dir, re-parses NOTHING (reparsed=0) — the red arm on a
#         binary whose server keeps its own blob.
#   arm 3: no MCP-only blob is left beside it (one rich blob for the root).
#   arm 4: the reverse order — an MCP server first (premise: reparsed > 0), then a CLI `--for`: reparsed=0.
#   arm 5: identity — the warm-from-CLI server's `for` answer equals a cold server's (fresh cache dir) answer byte
#         for byte, so sharing the blob changes no row.
#
# Usage: test/mcponeparsecheck.sh [BIN]
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/fixture"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for JSON assertions"; exit 2; }
echo "mcponeparsecheck: BIN=$BIN"

WORK="$TMP/work"; mkdir -p "$WORK"; cp -R "$FIX/"* "$WORK/"
TASK="how is the perimeter of a shape computed"

reparsed(){ grep -ao 'cache-stats reparsed=[0-9]*' "$1" | head -1 | sed 's/.*=//'; }
mcp_for(){   # $1 = cache dir, $2 = response file, $3 = stderr file
    printf '%s\n' \
        '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}' \
        '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"for","arguments":{"path":"'"$WORK"'","task":"'"$TASK"'"}}}' \
        | ( cd "$WORK" && TMPDIR="$1" RIPWIRE_CACHE_STATS=1 "$BIN" --mcp >"$2" 2>"$3" )
}
for_text(){ grep '"id":2' "$1" | python3 -c 'import sys,json; r=json.load(sys.stdin); print(json.dumps(r.get("result", r.get("error")), sort_keys=True))'; }

# ── arms 1-3: CLI first, then the server ─────────────────────────────────────────────────────────────
C1="$TMP/c1/"; mkdir -p "$C1"
( cd "$WORK" && TMPDIR="$C1" RIPWIRE_CACHE_STATS=1 "$BIN" "$WORK" --for="$TASK" >"$TMP/cli1.out" 2>"$TMP/cli1.err" ) || no "arm 1: the CLI --for exited $?"
r1="$( reparsed "$TMP/cli1.err" )"
rich1="$( find "$C1" -type f -name 'ripwire-*-rich*.bin' | wc -l | tr -d ' ' )"
if [ "${r1:-0}" -gt 0 ] && [ "$rich1" -ge 1 ]; then ok "arm 1: a CLI --for on a fresh cache dir parses ($r1 files) and writes a rich blob"
else no "arm 1: premise — CLI --for reparsed=${r1:-none}, rich blobs=$rich1 (want > 0 and >= 1)"; fi

mcp_for "$C1" "$TMP/m1.out" "$TMP/m1.err" || no "arm 2: ripwire --mcp exited $?"
r2="$( reparsed "$TMP/m1.err" )"
if [ "${r2:-x}" = 0 ]; then ok "arm 2: an MCP server after the CLI --for re-parses nothing (reparsed=0)"
else no "arm 2: the MCP server after a CLI --for re-parsed ${r2:-?} files — it does not read the CLI rich blob"; fi

mcpb="$( find "$C1" -type f -name 'ripwire-mcp-*' | wc -l | tr -d ' ' )"
rich2="$( find "$C1" -type f -name 'ripwire-*-rich*.bin' | wc -l | tr -d ' ' )"
if [ "$mcpb" = 0 ] && [ "$rich2" = 1 ]; then ok "arm 3: one rich blob for the root, no MCP-only blob"
else no "arm 3: $mcpb MCP-only blob(s) and $rich2 rich blob(s) — want 0 and 1"; fi

# ── arm 4: the server first, then the CLI ────────────────────────────────────────────────────────────
C2="$TMP/c2/"; mkdir -p "$C2"
mcp_for "$C2" "$TMP/m2.out" "$TMP/m2.err" || no "arm 4: ripwire --mcp exited $?"
r3="$( reparsed "$TMP/m2.err" )"
( cd "$WORK" && TMPDIR="$C2" RIPWIRE_CACHE_STATS=1 "$BIN" "$WORK" --for="$TASK" >"$TMP/cli2.out" 2>"$TMP/cli2.err" ) || no "arm 4: the CLI --for exited $?"
r4="$( reparsed "$TMP/cli2.err" )"
if [ "${r3:-0}" -gt 0 ] && [ "${r4:-x}" = 0 ]; then ok "arm 4: a CLI --for after an MCP server re-parses nothing (server parsed $r3, CLI reparsed=0)"
else no "arm 4: server-first reparsed=${r3:-none} (want > 0), CLI after it reparsed=${r4:-none} (want 0)"; fi
cmp -s "$TMP/cli1.out" "$TMP/cli2.out" && ok "arm 4: the CLI --for answer is the same cold and warm-from-server" \
    || no "arm 4: the CLI --for answer differs after the server wrote the blob"

# ── arm 5: identity against a cold server ────────────────────────────────────────────────────────────
C3="$TMP/c3/"; mkdir -p "$C3"
mcp_for "$C3" "$TMP/m3.out" "$TMP/m3.err" || no "arm 5: ripwire --mcp exited $?"
a="$( for_text "$TMP/m1.out" )"; b="$( for_text "$TMP/m3.out" )"
if [ -n "$a" ] && [ "$a" = "$b" ] && [ "${#a}" -gt 200 ]; then ok "arm 5: the warm-from-CLI server answers 'for' byte-identically to a cold server (${#a} B)"
else no "arm 5: the warm-from-CLI 'for' answer (${#a} B) differs from a cold server's (${#b} B)"; fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "FAILURES ABOVE"; exit 1; }
