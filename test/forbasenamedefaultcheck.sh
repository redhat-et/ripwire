#!/usr/bin/env bash
# forbasenamedefaultcheck.sh — the code lens (--for, --pack-task, MCP `for`) scores a symbol's FILE BASENAME as a BM25F field
# by default (lane LP1, 2026-11-21; src/lexical.h kForBasenameFieldW).
#
# WHY. A commit message or an issue names a file, a module or a package more often than a function: "lib/theme.githelpers:
# remove dead code", "restorer: reject trees …", "JTokenReader hangs …". The basename field (LB-3 arm B, src/lexical.h pass
# 1.6) already existed behind RIPWIRE_BASENAME_W and shipped at 0. Two peer tools win GA1 DEV cells on exactly this signal —
# codebase-memory-mcp indexes every node's file path and qualified name at the SAME BM25 weight as its name, graphify seeds
# its traversal from file nodes whose label matches a query word — and LP1 measured w=2 on GA1 DEV n=89 at 0 tasks down.
#
# Arms ([P] red on the train tip 36a95d732, where the default is 0; [G] hold on both binaries):
#   B1 [P] default: a JS file whose basename is the ONLY carrier of two query words (cache_store.js; symbols put/take) ranks a
#          symbol in the top 3 of --format=candidates; every other query word sits in NOISE files that outscore it without the field
#   B2 [G] control: RIPWIRE_BASENAME_W=0 — the same target is absent from the top 3 (the field, not ambient rank, did the work)
#   B3 [P] language-neutral: a Go file whose basename is its only "restorer" (internal/restorer/restorer.go) scores > 0 on it
#   B4 [G] B3's control at RIPWIRE_BASENAME_W=0: it scores 0
#   B5 [P] the MCP `for` verb ranks the same way (CLI/MCP parity: both front doors pass the one constant)
#   B6 [G] B5's control: the MCP server under RIPWIRE_BASENAME_W=0 does not surface the target at r=1..3
#   B7 [P] --pack-task (shares computeLensRanking) surfaces the target's file
#   X1 [G] determinism: two default runs are byte-identical
#
# Usage:  bash test/forbasenamedefaultcheck.sh [BIN]   — BIN is $1, else RIPWIRE_BIN, else build/ripwire.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
unset RIPWIRE_BASENAME_W RIPWIRE_PATHTOK_W RIPWIRE_QSTEM
export RIPWIRE_NO_ROWLINES=1
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d "${TMPDIR:-/tmp}/forbasename.XXXXXX" )"
trap 'rm -rf "$TMP"' EXIT
FAIL=0
ok(){ printf '  PASS  %s\n' "$*" || { FAIL=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; FAIL=1; }
echo "forbasenamedefaultcheck: BIN=$BIN"

# ── fixture: one JS target, one Go target, and noise carrying every NON-basename query word ─────────────────────────────
R="$TMP/corpus"
mkdir -p "$R/store" "$R/lib" "$R/internal/restorer" "$R/internal/walker" "$R/home"
cat > "$R/store/cache_store.js" <<'EOF'
function put( key, value ) { table[key] = value; }
function take( key ) { return table[key]; }
module.exports = { put, take };
EOF
cat > "$R/lib/modules.js" <<'EOF'
// modules helpers: keep results kept cleanly for modules
function listModules( modules ) { return modules.filter( m => m.live ); }
function cleanlyKept( results ) { return results.kept; }
function keptResults( results ) { return results; }
module.exports = { listModules, cleanlyKept, keptResults };
EOF
cat > "$R/lib/results.js" <<'EOF'
// results kept cleanly across modules
function resultsOf( modules ) { return modules.map( m => m.result ); }
function keepResults( results ) { return results.slice(); }
module.exports = { resultsOf, keepResults };
EOF
cat > "$R/internal/restorer/restorer.go" <<'EOF'
package restorer

func traverseInner( dir string, visit func( string ) error ) error { return visit( dir ) }
func applyMeta( path string ) error { return nil }
EOF
# Go noise: three symbols, ONE query word each, mentioned once in the BODY, so the arms below are not about out-ranking a
# planted majority: B3/B4 pin that the basename word reaches the SCORE at all (a Go symbol none of whose own text says
# "restorer"), language-neutrally; B1 is the ranking arm
cat > "$R/internal/walker/walker.go" <<'EOF'
package walker

func firstPass( c cfg ) bool { return c.reject }
func secondPass( c cfg ) bool { return c.duplicate }
func thirdPass( c cfg ) bool { return c.names }
EOF

Q_JS="cache store modules cleanly"
Q_GO="restorer: reject duplicate names"
cli(){ ( cd "$R" && HOME="$R/home" TMPDIR="$R/home/" "$@" </dev/null 2>/dev/null ); }
top3(){ tr '<' '\n' < "$1" | grep -E '^cand r="[123]" ' | grep -c "$2"; }

cli "$BIN" "$R" --no-cache --for="$Q_JS" --format=candidates > "$TMP/js_on.xml"
cli env RIPWIRE_BASENAME_W=0 "$BIN" "$R" --no-cache --for="$Q_JS" --format=candidates > "$TMP/js_off.xml"
cli "$BIN" "$R" --no-cache --for="$Q_GO" --format=candidates > "$TMP/go_on.xml"
cli env RIPWIRE_BASENAME_W=0 "$BIN" "$R" --no-cache --for="$Q_GO" --format=candidates > "$TMP/go_off.xml"
for f in js_on js_off go_on go_off; do
    grep -q '<cand ' "$TMP/$f.xml" || no "premise: $f.xml has no <cand> rows (the arms below would be vacuous)"
done

echo "=== B: the CLI code lens scores the basename by default ==="
[ "$( top3 "$TMP/js_on.xml" 'p="store/cache_store.js"' )" -ge 1 ] \
    && ok "B1 default: cache_store.js ranks top-3 for '$Q_JS'" || no "B1 default: cache_store.js absent from top-3 for '$Q_JS'"
[ "$( top3 "$TMP/js_off.xml" 'p="store/cache_store.js"' )" -eq 0 ] \
    && ok "B2 control (BASENAME_W=0): cache_store.js stays out of the top-3" || no "B2 control: cache_store.js top-3 with the field off (the arm proves nothing)"
# the s= of restorer.go's best candidate row (0 when it is listed at zero, -1 when it is not listed)
gos(){ python3 -c '
import re, sys
best = -1.0
for m in re.finditer( r"<cand [^>]*>", open( sys.argv[1] ).read() ):
    if " p=\"internal/restorer/restorer.go\"" in m.group( 0 ):
        best = max( best, float( re.search( r" s=\"([^\"]*)\"", m.group( 0 ) ).group( 1 ) ) )
print( "pos" if best > 0 else "zero" )' "$1"; }
[ "$( gos "$TMP/go_on.xml" )" = pos ] \
    && ok "B3 default (Go): restorer.go's symbols score > 0 on the basename word alone" || no "B3 default (Go): restorer.go scores 0 (the basename is not a field)"
[ "$( gos "$TMP/go_off.xml" )" = zero ] \
    && ok "B4 control (Go, BASENAME_W=0): restorer.go scores 0" || no "B4 control (Go): restorer.go scores > 0 with the field off (B3 proves nothing)"

echo "=== B5/B6: MCP for, the same constant ==="
mcpfor(){   # ENVPREFIX… -- : the MCP `for` answer text for Q_JS, or @@NOANSWER
    ( cd "$R" && HOME="$R/home" TMPDIR="$R/home/" "$@" python3 - "$BIN" "$R" "$Q_JS" <<'X'
import json, subprocess, sys
b, repo, q = sys.argv[1:4]
req = json.dumps( { "jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": { "name": "for", "arguments": { "path": repo, "task": q } } } ) + "\n"
p = subprocess.run( [ b, "--mcp" ], input=req.encode(), capture_output=True, timeout=300, cwd=repo )
out = ""
for l in p.stdout.decode( "utf8", "replace" ).splitlines():
    try:
        d = json.loads( l )
    except Exception:
        continue
    if d.get( "id" ) == 1 and "result" in d:
        out = "".join( x.get( "text", "" ) for x in d["result"]["content"] )
print( out if ( p.returncode == 0 and out ) else "@@NOANSWER" )
X
    )
}
# the p= of the ranked rows r=1..3 (element or line form), one per line
ranked3(){ python3 -c '
import re, sys
t = sys.stdin.read()
for m in re.finditer( r"<d [^>]*>", t ):
    r = re.search( r" r=\"(\d+)\"", m.group( 0 ) ); p = re.search( r" p=\"([^\"]*)\"", m.group( 0 ) )
    if r and p and int( r.group( 1 ) ) <= 3: print( p.group( 1 ) )
'; }
mcpfor env > "$TMP/mcp_on.txt"
mcpfor env RIPWIRE_BASENAME_W=0 > "$TMP/mcp_off.txt"
if grep -q '@@NOANSWER' "$TMP/mcp_on.txt" || grep -q '@@NOANSWER' "$TMP/mcp_off.txt"; then
    no "B5/B6 premise: the MCP for verb gave no answer"
else
    ranked3 < "$TMP/mcp_on.txt" | grep -qx 'store/cache_store.js' \
        && ok "B5 MCP for: cache_store.js at r=1..3" || no "B5 MCP for: cache_store.js not at r=1..3 (CLI/MCP parity broken)"
    ranked3 < "$TMP/mcp_off.txt" | grep -qx 'store/cache_store.js' \
        && no "B6 MCP control: cache_store.js at r=1..3 with the field off (B5 proves nothing)" || ok "B6 MCP control (BASENAME_W=0): not at r=1..3"
fi

echo "=== B7: --pack-task shares the ranking ==="
cli "$BIN" "$R" --no-cache --pack-task="$Q_JS" > "$TMP/pack_on.xml"
cli env RIPWIRE_BASENAME_W=0 "$BIN" "$R" --no-cache --pack-task="$Q_JS" > "$TMP/pack_off.xml"
if grep -q 'store/cache_store.js' "$TMP/pack_on.xml"; then ok "B7 --pack-task names cache_store.js"; else no "B7 --pack-task does not name cache_store.js"; fi
if grep -q 'store/cache_store.js' "$TMP/pack_off.xml"; then echo "  note  B7 control: the field-off pack also names it (informational, not an arm)"; fi

echo "=== X: determinism ==="
cli "$BIN" "$R" --no-cache --for="$Q_GO" > "$TMP/x1.xml"
cli "$BIN" "$R" --no-cache --for="$Q_GO" > "$TMP/x2.xml"
[ -s "$TMP/x1.xml" ] && cmp -s "$TMP/x1.xml" "$TMP/x2.xml" && ok "X1 two default --for runs are byte-identical" || no "X1 nondeterministic or empty --for answer"

if [ "$FAIL" -ne 0 ]; then echo "forbasenamedefaultcheck: FAIL"; exit 1; fi
echo "forbasenamedefaultcheck: PASS"
