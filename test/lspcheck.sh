#!/usr/bin/env bash
# lspcheck.sh — gate for --lsp, the Phase 1 navigation-LSP PoC (plan + locked decisions: docs/LSP.md).
#
# The gap this closes: ripwire answered agents (MCP) and shells (the CLI map), but no editor. --lsp is the
# third front door onto the SAME warm index; this gate is the fake LSP client that proves the door opens —
# Content-Length framing in and out, the five navigation methods, the lifecycle, and the two refusals —
# without any editor in the loop.
#
# RED-FIRST PROOF SHAPE: every arm asserts response BYTES (a capability name, a location line number, a
# merged field row, a hover sentence) — never a bare exit code. The baseline binary has no --lsp at all: it
# answers "unknown flag" with an EMPTY stdout, so every framing arm fails against it. Arms (4) and (11)
# additionally pin decisions the baseline could not make: (4) fails without the D8 field-side-table merge
# (a field is not a symbol, so an outline built from symbols alone never names "sides"), and (11) fails on
# any implementation that read didChange content into its answer (D1 — saved-state only).
#
# Arms:
#   (1)  initialize: capabilities bytes — positionEncoding utf-8, all five providers, openClose sync
#   (2)  definition: the call site resolves to the def's signature line, in the right file
#   (3)  references: the name-based use-site floor (the call line) + includeDeclaration adds the def line
#   (4)  documentSymbol: defs AND the merged FIELD row (D8), nested under the struct ("children":[{"name":"sides")
#   (5)  hover: verbatim signature + CSR degrees (callers 1) + the used-at link list + the standing floor
#        sentence (D6/D7)
#   (6)  workspace/symbol exact name (D9 first tier)
#   (7)  workspace/symbol substring over names (D9 second tier)
#   (8)  didChange content is NEVER answered (D1): the post-change hover equals the pre-change hover
#   (9)  protocol shape: exactly 9 responses to the 14-message dialog (notifications answer nothing)
#   (10) pre-initialize request refused with -32002; unknown method refused with -32601
#   (11) --lsp --mcp and --lsp --listen refused — "one protocol per stdin" (D10)
#   (12) shutdown answers null, exit ends the process 0
#   (13) determinism (x2, byte-identical dialogs — the house pattern)
#   (14) hover, Ruby: a class with no call edges still lists its constant-load uses as links (the sibling
#        file's `Quota.limit` line)
#   (15) traversal (#279 review, folded in from the reviewer's adversary driver): hover, definition and
#        documentSymbol on a file URI OUTSIDE the root — absolute, `..`-escaped, through a symlink inside the root,
#        and percent-encoded `%2e%2e` — answer null or [], and no response carries a byte of the outside file
#   (16) framing: a missing, non-numeric, negative or over-cap Content-Length, and a header flood with no
#        terminator, each end the session at exit 1 with nothing on stdout and the framing refusal on stderr,
#        inside a wall-clock cap (no hang)
#   (17) workspace/symbol's 20-row cap is DISCLOSED: 25 matches answer 20 rows after a window/logMessage naming
#        "first 20 of 25"; 10 matches answer all 10 with no notice
#   (18) picker order (task C): on the copied rubyschemafix collision tree, workspace/symbol, definition and
#        hover all lead with the Method def — the tower (kindSpecificity desc, reference-language first, id asc)
#        — with the Var next, the schema column before the yaml section, byte-pinned
#   (18b) schema-column click (user GO): a call site naming a schema column alone resolves to its
#        schema.rb def (the collision tree holds it at the root, no db/ prefix); the multi-name click lands
#        on the first schema row (split, id tail) WITH the N-definitions disclosure — cross-kind columns stay
#        REACHABLE, only their order moves
#   (19) multi-def disclosure (task C): a name with N>1 defs carries ONE sentence — N definitions, counts are
#        floors, the resolver splits — in the hover markdown and in one window/logMessage ahead of every
#        definition answer; absent on single-def names, whose hover must ANSWER before the silence is credited
#   (20) Used-at parity (task C): hover Used-at for the colliding name answers every CLI --uses call row, with the
#        kLspHoverUseCap=8 tier premise pinned first — past the cap a missing link is the disclosed truncation, not a defect
#   (21) C/C++ decl/def no-regression (task C): on a tree whose HEADER sorts first — so the prototype carries the LOWER
#        crawl-order id — the single-pick --around still walks the bodyful definition (the resolveFocus refinement
#        composes with the tower sort); textDocument/definition is pinned beside it as the whole-list answer it is
#   (22) determinism x2 on the new collision dialog (house pattern)
#   (23) the known gap stays COHERENT: --around's CLI row shows the tower front AND its defs= count, so
#        edge-vs-display disagreement is visible on the row, never hidden
#   (24) a constructor never outranks its class (maintainer, #432 review): Java `public Shape() {}` inside class Shape
#        and C++ `Widget::Widget()` beside a header-first class Widget — --lego names the class and its implementor,
#        --around focuses the class row; a near-miss Java method named like ANOTHER class keeps the Method rung
#   (25) a C prototype beside its body is counted in the (19) sentence but never described as a resolver split
#   (26) the tower's tiers in ORDER: kind before language — a Python class (rung 3) sits between a Ruby method (5)
#        and a Ruby attr (1) although the leading language is Ruby (arms 18-23 are single-language and cannot see a
#        swap of the two tiers)
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/lspcheck.sh   |   bash test/lspcheck.sh path/to/ripwire

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }

WORK="$( cd "$( mktemp -d )" && pwd -P )"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/src"

# C++ fixture — line numbers below are load-bearing (the arms address them):
#   L5  int scale( int f )      -> the def signature line (0-based line 4)
#   L4  int sides = 0           -> the FIELD side-table row (D8 — absent from ing.symbols)
#   L13 s.scale( 2 )            -> the one call site (0-based line 12)
cat > "$WORK/src/geo.cpp" <<'EOF'
// lsp fixture
struct Shape
{
    int sides = 0;
    int scale( int f )
    {
        return sides * f;
    }
};

int twice( const Shape& s )
{
    return s.scale( 2 );
}
EOF

# ─── the fake LSP client: Content-Length frames in, one decoded JSON per line out ────────────────────
msg(){ printf 'Content-Length: %d\r\n\r\n%s' "${#1}" "$1"; }

decodeFrames(){ python3 - "$1" <<'PY'
import sys
data = open( sys.argv[ 1 ], "rb" ).read()
i = 0
while i < len( data ):
    j = data.find( b"\r\n\r\n", i )
    if j == -1: sys.exit( "unterminated frame at %d" % i )
    cl = None
    for ln in data[ i : j ].decode().split( "\r\n" ):
        if ln.lower().startswith( "content-length:" ): cl = int( ln.split( ":", 1 )[ 1 ] )
    if cl is None: sys.exit( "frame without Content-Length" )
    body = data[ j + 4 : j + 4 + cl ]
    if len( body ) != cl: sys.exit( "short body" )
    print( body.decode() )
    i = j + 4 + cl
PY
}

uriInit="file://$WORK"
uriGeo="file://$WORK/src/geo.cpp"

# The main dialog: 14 messages, 9 answers (notifications answer nothing — arm (9)).
{
  msg "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"rootUri\":\"$uriInit\",\"capabilities\":{}}}"
  msg "{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":{}}"
  msg "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"$uriGeo\",\"languageId\":\"cpp\",\"version\":1,\"text\":\"\"}}}"
  msg "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/definition\",\"params\":{\"textDocument\":{\"uri\":\"$uriGeo\"},\"position\":{\"line\":12,\"character\":15}}}"
  msg "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"textDocument/references\",\"params\":{\"textDocument\":{\"uri\":\"$uriGeo\"},\"position\":{\"line\":12,\"character\":15},\"context\":{\"includeDeclaration\":true}}}"
  msg "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"textDocument/documentSymbol\",\"params\":{\"textDocument\":{\"uri\":\"$uriGeo\"}}}"
  msg "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"textDocument/hover\",\"params\":{\"textDocument\":{\"uri\":\"$uriGeo\"},\"position\":{\"line\":4,\"character\":10}}}"
  msg "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"workspace/symbol\",\"params\":{\"query\":\"scale\"}}"
  msg "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"workspace/symbol\",\"params\":{\"query\":\"sha\"}}"
  msg "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didChange\",\"params\":{\"textDocument\":{\"uri\":\"$uriGeo\",\"version\":2},\"contentChanges\":[{\"text\":\"ZZZ never re-parsed in Phase 1 ZZZ\"}]}}"
  msg "{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"textDocument/hover\",\"params\":{\"textDocument\":{\"uri\":\"$uriGeo\"},\"position\":{\"line\":4,\"character\":10}}}"
  msg "{\"jsonrpc\":\"2.0\",\"id\":99,\"method\":\"shutdown\"}"
  msg "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didClose\",\"params\":{\"textDocument\":{\"uri\":\"$uriGeo\"}}}"
  msg "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}"
} > "$WORK/dialog"

"$BIN" --lsp < "$WORK/dialog" > "$WORK/raw" 2>"$WORK/err"; RC=$?
decodeFrames "$WORK/raw" > "$WORK/resp" 2>"$WORK/decode.err"; DRC=$?
[ "$DRC" = 0 ] || { no "framing decode failed"; cat "$WORK/decode.err"; }

R(){ grep "\"id\":$1," "$WORK/resp"; }

# ── (1) initialize capabilities ──────────────────────────────────────────────────────────────────────
R1="$( R 1 )"
printf '%s' "$R1" | grep -q '"positionEncoding":"utf-8"' \
    && printf '%s' "$R1" | grep -q '"definitionProvider":true' \
    && printf '%s' "$R1" | grep -q '"referencesProvider":true' \
    && printf '%s' "$R1" | grep -q '"documentSymbolProvider":true' \
    && printf '%s' "$R1" | grep -q '"workspaceSymbolProvider":true' \
    && printf '%s' "$R1" | grep -q '"hoverProvider":true' \
    && printf '%s' "$R1" | grep -q '"openClose":true' \
    && ok "(1) initialize: utf-8 positions, five providers, openClose sync" \
    || { no "(1) initialize capabilities missing bytes"; printf '%s\n' "$R1" | head -c 400; }

# ── (2) definition: the call site at (12,15) resolves scale to its signature line (0-based 4) ────────
R2="$( R 2 )"
printf '%s' "$R2" | grep -q '"uri":"file://.*geo.cpp"' \
    && printf '%s' "$R2" | grep -q '"line":4' \
    && ok "(2) definition: the call resolves to the def's line, in the indexed file" \
    || { no "(2) definition location wrong"; printf '%s\n' "$R2" | head -c 400; }

# ── (3) references: floor site (the call line 12) + declaration (the def line 4) ──────────────────────
R3="$( R 3 )"
printf '%s' "$R3" | grep -q '"line":12' \
    && printf '%s' "$R3" | grep -q '"line":4' \
    && ok "(3) references: the name-matched use-site plus includeDeclaration's def" \
    || { no "(3) references missing a site"; printf '%s\n' "$R3" | head -c 400; }

# ── (4) documentSymbol: defs AND the merged field, nested under the struct (D8) ───────────────────────
R4="$( R 4 )"
printf '%s' "$R4" | grep -q '"name":"Shape"' \
    && printf '%s' "$R4" | grep -q '"name":"scale"' \
    && printf '%s' "$R4" | grep -q '"children":\[{"name":"sides"' \
    && printf '%s' "$R4" | grep -q '"kind":8' \
    && ok "(4) documentSymbol: field row merged (children open with sides, kind 8)" \
    || { no "(4) documentSymbol missing the merged field or nesting"; printf '%s\n' "$R4" | head -c 400; }

# ── (5) hover: verbatim signature + degrees + used-at links + the floor sentence ─────────────────────
R5="$( R 5 )"
printf '%s' "$R5" | grep -q 'int scale( int f )' \
    && printf '%s' "$R5" | grep -q 'callers 1' \
    && printf '%s' "$R5" | grep -q '\*\*Used at\*\*' \
    && printf '%s' "$R5" | grep -q '#L13' \
    && printf '%s' "$R5" | grep -q 'floors, not totals' \
    && ok "(5) hover: verbatim signature, CSR callers=1, the call line as a #L13 used-at link, the standing floor sentence" \
    || { no "(5) hover gist incomplete"; printf '%s\n' "$R5" | head -c 400; }

# ── (6/7) workspace/symbol: exact, then substring over names ─────────────────────────────────────────
R6="$( R 6 )"
printf '%s' "$R6" | grep -q '"name":"scale"' \
    && ok "(6) workspace/symbol: exact name hit" \
    || { no "(6) workspace/symbol exact miss"; printf '%s\n' "$R6" | head -c 300; }
R7="$( R 7 )"
printf '%s' "$R7" | grep -q '"name":"Shape"' \
    && ok "(7) workspace/symbol: substring tier finds Shape from 'sha'" \
    || { no "(7) workspace/symbol substring miss"; printf '%s\n' "$R7" | head -c 300; }

# ── (8) didChange content is NEVER answered (D1: saved-state only) ───────────────────────────────────
R8="$( R 8 )"
printf '%s' "$R8" | grep -q 'int scale( int f )' \
    && ! printf '%s' "$R8" | grep -q 'ZZZ' \
    && [ "$( printf '%s' "$R5" | sed 's/"id":[0-9]*//' )" = "$( printf '%s' "$R8" | sed 's/"id":[0-9]*//' )" ] \
    && ok "(8) post-didChange hover answers from disk, byte-equal to the pre-change one (D1)" \
    || { no "(8) didChange content leaked into the answer, or the hover moved"; printf '%s\n' "$R8" | head -c 300; }

# ── (9) protocol shape: 14 dialog messages, exactly 9 responses ──────────────────────────────────────
NRESP="$( grep -c . "$WORK/resp" 2>/dev/null || echo 0 )"
[ "$NRESP" = 9 ] \
    && ok "(9) exactly 9 responses to the 14-message dialog (notifications answered nothing)" \
    || { no "(9) response count wrong: got $NRESP, expected 9"; cat "$WORK/resp"; }

# ── (10) lifecycle refusals: pre-init request, unknown method ────────────────────────────────────────
{
  msg "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"textDocument/definition\",\"params\":{\"textDocument\":{\"uri\":\"$uriGeo\"},\"position\":{\"line\":12,\"character\":15}}}"
  msg "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}"
} > "$WORK/d2"
"$BIN" --lsp < "$WORK/d2" > "$WORK/raw2" 2>/dev/null
decodeFrames "$WORK/raw2" | grep -q '"code":-32002' \
    && ok "(10) pre-initialize request refused with -32002" \
    || { no "(10) pre-initialize not refused"; }
{
  msg "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"rootUri\":\"$uriInit\",\"capabilities\":{}}}"
  msg "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"foo/bar\"}"
  msg "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}"
} > "$WORK/d3"
"$BIN" --lsp < "$WORK/d3" > "$WORK/raw3" 2>/dev/null
decodeFrames "$WORK/raw3" | grep -q '"code":-32601' \
    && ok "(10) unknown method refused with -32601" \
    || { no "(10) unknown method not refused"; }

# ── (11) D10 refusals: --lsp beside the MCP transports ───────────────────────────────────────────────
E11="$( "$BIN" --lsp --mcp </dev/null 2>&1 >/dev/null )"; RC11=$?
[ "$RC11" = 1 ] && printf '%s' "$E11" | grep -q 'one protocol per stdin' \
    && ok "(11) --lsp --mcp refused, exit 1, the stdin sentence" \
    || { no "(11) --lsp --mcp not refused (exit $RC11)"; printf '%s\n' "$E11"; }
E11b="$( "$BIN" --lsp --listen=127.0.0.1:8765 </dev/null 2>&1 >/dev/null )"; RC11b=$?
[ "$RC11b" = 1 ] && printf '%s' "$E11b" | grep -q 'one protocol per stdin' \
    && ok "(11) --lsp --listen refused too" \
    || { no "(11) --lsp --listen not refused (exit $RC11b)"; printf '%s\n' "$E11b"; }

# ── (12) shutdown answered null and exit ended the session 0 ─────────────────────────────────────────
R99="$( R 99 )"
printf '%s' "$R99" | grep -q '"id":99,"result":null' \
    && [ "$RC" = 0 ] \
    && ok "(12) shutdown → null, exit → clean end (rc 0)" \
    || { no "(12) shutdown/exit wrong (rc $RC)"; printf '%s\n' "$R99" | head -c 200; }

# ── (13) determinism: two identical dialogs byte-identical ───────────────────────────────────────────
"$BIN" --lsp < "$WORK/dialog" > "$WORK/rawA" 2>/dev/null
"$BIN" --lsp < "$WORK/dialog" > "$WORK/rawB" 2>/dev/null
[ -s "$WORK/rawA" ] && cmp -s "$WORK/rawA" "$WORK/rawB" \
    && ok "(13) determinism: two dialogs byte-identical" \
    || { no "(13) dialogs differ (or empty)"; ls -l "$WORK/rawA" "$WORK/rawB"; }


# ── (14) hover: the Ruby constant floor — a class named only by another file's load directive ────────
mkdir -p "$WORK/rb"
cat > "$WORK/rb/ledger.rb" <<'EOF'
class Ledger
  def compute
    Quota.limit
  end
end
EOF
cat > "$WORK/rb/quota.rb" <<'EOF'
class Quota
  def self.limit
    100
  end

  def audit
    Ledger.new
  end
end
EOF
uriQuota="file://$WORK/rb/quota.rb"
{
  msg "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"rootUri\":\"$uriInit\",\"capabilities\":{}}}"
  msg "{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":{}}"
  msg "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"$uriQuota\",\"languageId\":\"ruby\",\"version\":1,\"text\":\"\"}}}"
  msg "{\"jsonrpc\":\"2.0\",\"id\":20,\"method\":\"textDocument/hover\",\"params\":{\"textDocument\":{\"uri\":\"$uriQuota\"},\"position\":{\"line\":0,\"character\":7}}}"
  msg "{\"jsonrpc\":\"2.0\",\"id\":99,\"method\":\"shutdown\"}"
  msg "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}"
} > "$WORK/d4"
"$BIN" --lsp < "$WORK/d4" > "$WORK/raw4" 2>/dev/null
decodeFrames "$WORK/raw4" | grep '"id":20,' > "$WORK/r20"
grep -q '\*\*Referenced at\*\*' "$WORK/r20" \
    && grep -q 'ledger\.rb:3' "$WORK/r20" \
    && grep -q '#L3' "$WORK/r20" \
    && ok "(14) hover: the Ruby constant tier links Quota's use in the sibling file (ledger.rb:3)" \
    || { no "(14) hover Ruby constant tier missing"; head -c 400 "$WORK/r20"; }
# ── (15) traversal: a URI outside the root answers nothing, and never the outside file's bytes ─────────────
SECRET="$( mktemp -d )"; trap 'rm -rf "$WORK" "$SECRET"' EXIT
printf 'int leakMarkerFn() { return 42; } // LSP-TRAVERSAL-SECRET\n' > "$SECRET/secret.cpp"
ln -s "$SECRET" "$WORK/src/escape_link" 2>/dev/null
up=""; for _ in $( seq 1 24 ); do up="$up../"; done
enc=""; for _ in $( seq 1 24 ); do enc="$enc%2e%2e/"; done
i=10
{
  msg "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"rootUri\":\"$uriInit\",\"capabilities\":{}}}"
  for u in "file://$SECRET/secret.cpp" "file://$WORK/src/$up${SECRET#/}/secret.cpp" "file://$WORK/src/escape_link/secret.cpp" "file://$WORK/src/$enc${SECRET#/}/secret.cpp"; do
    msg "{\"jsonrpc\":\"2.0\",\"id\":$i,\"method\":\"textDocument/hover\",\"params\":{\"textDocument\":{\"uri\":\"$u\"},\"position\":{\"line\":0,\"character\":6}}}"
    msg "{\"jsonrpc\":\"2.0\",\"id\":$(( i + 1 )),\"method\":\"textDocument/definition\",\"params\":{\"textDocument\":{\"uri\":\"$u\"},\"position\":{\"line\":0,\"character\":6}}}"
    msg "{\"jsonrpc\":\"2.0\",\"id\":$(( i + 2 )),\"method\":\"textDocument/documentSymbol\",\"params\":{\"textDocument\":{\"uri\":\"$u\"}}}"
    i=$(( i + 3 ))
  done
  msg "{\"jsonrpc\":\"2.0\",\"id\":99,\"method\":\"shutdown\"}"
  msg "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}"
} > "$WORK/d15"
"$BIN" --lsp < "$WORK/d15" > "$WORK/raw15" 2>/dev/null; RC15=$?
decodeFrames "$WORK/raw15" > "$WORK/r15" 2>/dev/null
n15="$( grep -c '"id":\(1[0-9]\|2[01]\),' "$WORK/r15" )"
empty15="$( grep '"id":\(1[0-9]\|2[01]\),' "$WORK/r15" | grep -c '"result":\(null\|\[\]\)}' )"
if grep -q 'LSP-TRAVERSAL-SECRET\|leakMarkerFn' "$WORK/raw15"; then
    no "(15) traversal: a response carried the outside file's bytes"
elif [ "$RC15" = 0 ] && [ "$n15" = 12 ] && [ "$empty15" = 12 ]; then
    ok "(15) traversal: absolute, ..-escaped, symlinked and %2e%2e URIs outside the root answer null/[] (12 of 12), rc 0, no outside bytes"
else
    no "(15) traversal: rc=$RC15, $n15 responses, $empty15 empty (want 0 / 12 / 12)"; head -c 600 "$WORK/r15"
fi

# ── (16) framing refusals: bounded, silent on stdout, named on stderr ───────────────────────────────────────
CAPRUN="$ROOT/test/lib/caprun.py"
f16=""
printf 'Foo: bar\r\n\r\n{}' > "$WORK/f_missing"
printf 'Content-Length: abc\r\n\r\n{}' > "$WORK/f_nonnum"
printf 'Content-Length: -5\r\n\r\n{}' > "$WORK/f_negative"
{ printf 'Content-Length: 40000000\r\n\r\n'; head -c 1000 /dev/zero | tr '\0' x; } > "$WORK/f_overcap"
{ printf 'X-Pad: '; head -c 70000 /dev/zero | tr '\0' a; } > "$WORK/f_flood"
for case in missing nonnum negative overcap flood; do
    res="$( python3 "$CAPRUN" 10 --stdin "$WORK/f_$case" --stdout "$WORK/o_$case" --stderr "$WORK/e_$case" -- "$BIN" --lsp )"
    if [ "$res" = "${res#rc=1 }" ] || [ -s "$WORK/o_$case" ] || ! grep -q 'malformed Content-Length framing' "$WORK/e_$case"; then
        f16="$f16 $case[$res stdout=$( wc -c < "$WORK/o_$case" | tr -d ' ' )B]"
    fi
done
[ -z "$f16" ] && ok "(16) framing: missing / non-numeric / negative / over-cap Content-Length and a header flood each exit 1 within 10 s, stdout empty, the refusal named" \
             || no "(16) framing refusal wrong for:$f16"

# ── (17) workspace/symbol discloses its 20-row cap ──────────────────────────────────────────────────────────
W17="$( mktemp -d )"
for k in $( seq 0 24 ); do printf 'int capfn%02d() { return %d; }\n' "$k" "$k"; done > "$W17/caps.cpp"
{
  msg "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"rootUri\":\"file://$W17\",\"capabilities\":{}}}"
  msg "{\"jsonrpc\":\"2.0\",\"id\":30,\"method\":\"workspace/symbol\",\"params\":{\"query\":\"capfn\"}}"
  msg "{\"jsonrpc\":\"2.0\",\"id\":31,\"method\":\"workspace/symbol\",\"params\":{\"query\":\"capfn1\"}}"
  msg "{\"jsonrpc\":\"2.0\",\"id\":99,\"method\":\"shutdown\"}"
  msg "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}"
} > "$WORK/d17"
"$BIN" --lsp < "$WORK/d17" > "$WORK/raw17" 2>/dev/null
decodeFrames "$WORK/raw17" > "$WORK/r17" 2>/dev/null
rm -rf "$W17"
rows30="$( grep '"id":30,' "$WORK/r17" | grep -o '"name":"capfn' | wc -l | tr -d ' ' )"
rows31="$( grep '"id":31,' "$WORK/r17" | grep -o '"name":"capfn' | wc -l | tr -d ' ' )"
notices="$( grep -c '"method":"window/logMessage"' "$WORK/r17" )"
noticeLine="$( grep -n '"method":"window/logMessage"' "$WORK/r17" | cut -d: -f1 )"; resp30Line="$( grep -n '"id":30,' "$WORK/r17" | cut -d: -f1 )"
[ "$rows30" = 20 ] && [ "$rows31" = 10 ] && [ "$notices" = 1 ] \
    && grep -q 'shows the first 20 of 25 matches for .capfn.' "$WORK/r17" \
    && [ -n "$noticeLine" ] && [ "$noticeLine" -lt "$resp30Line" ] \
    && ok "(17) workspace/symbol: 25 matches → 20 rows after one window/logMessage 'first 20 of 25'; 10 matches (capfn10-19) → 10 rows, no notice" \
    || { no "(17) cap disclosure wrong: rows30=$rows30 rows31=$rows31 notices=$notices"; head -c 500 "$WORK/r17"; }
# ── (18) picker order: the tower sorts every multi-def answer, byte-pinned on the collision fixture ───
cp -r "$ROOT/test/rubyschemafix" "$WORK/collide"
uriColl="file://$WORK/collide"
uriCA="file://$WORK/collide/consumer_ambiguous.rb"
{
  msg "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"rootUri\":\"$uriColl\",\"capabilities\":{}}}"
  msg "{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":{}}"
  msg "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"$uriCA\",\"languageId\":\"ruby\",\"version\":1,\"text\":\"\"}}}"
  msg "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file://$WORK/collide/all_four.rb\",\"languageId\":\"ruby\",\"version\":1,\"text\":\"\"}}}"
  msg "{\"jsonrpc\":\"2.0\",\"id\":40,\"method\":\"workspace/symbol\",\"params\":{\"query\":\"name\"}}"
  msg "{\"jsonrpc\":\"2.0\",\"id\":41,\"method\":\"textDocument/definition\",\"params\":{\"textDocument\":{\"uri\":\"$uriCA\"},\"position\":{\"line\":7,\"character\":10}}}"
  msg "{\"jsonrpc\":\"2.0\",\"id\":42,\"method\":\"textDocument/hover\",\"params\":{\"textDocument\":{\"uri\":\"$uriCA\"},\"position\":{\"line\":7,\"character\":10}}}"
  msg "{\"jsonrpc\":\"2.0\",\"id\":43,\"method\":\"textDocument/hover\",\"params\":{\"textDocument\":{\"uri\":\"file://$WORK/collide/all_four.rb\"},\"position\":{\"line\":9,\"character\":8}}}"
  msg "{\"jsonrpc\":\"2.0\",\"id\":99,\"method\":\"shutdown\"}"
  msg "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}"
} > "$WORK/d18"
"$BIN" --lsp < "$WORK/d18" > "$WORK/raw18" 2>/dev/null
decodeFrames "$WORK/raw18" > "$WORK/r18" 2>/dev/null
head40="$( grep '"id":40,' "$WORK/r18" )"; head41="$( grep '"id":41,' "$WORK/r18" )"; R42="$( grep '"id":42,' "$WORK/r18" )"; R43="$( grep '"id":43,' "$WORK/r18" )"
p_m="$( printf '%s' "$head40" | grep -bo 'all_four.rb","range":{"start":{"line":9' | cut -d: -f1 | head -1 )"
p_v="$( printf '%s' "$head40" | grep -bo 'all_four.rb","range":{"start":{"line":7' | cut -d: -f1 | head -1 )"
p_c="$( printf '%s' "$head40" | grep -bo 'schema.rb","range":{"start":{"line":14' | cut -d: -f1 | head -1 )"
p_y="$( printf '%s' "$head40" | grep -bo 'spike_names.yml","range":{"start":{"line":3' | cut -d: -f1 | head -1 )"
# The def-front clause pins the FIRST row by OFFSET, like the ws/symbol rows above: a Location row is ~130 bytes, so the
# old "first 260 bytes contain a "line":9 field" window also matched the SECOND row — a Var-first order still printed PASS.
q_m="$( printf '%s' "$head41" | grep -bo 'all_four.rb","range":{"start":{"line":9' | cut -d: -f1 | head -1 )"
q_v="$( printf '%s' "$head41" | grep -bo 'all_four.rb","range":{"start":{"line":7' | cut -d: -f1 | head -1 )"
# The hover-front clause is pinned by offset the same way. lspAppendHoverDefs renders up to kLspHoverDefCap=8 of the 19 defs,
# so the old membership grep matched the Method block wherever it sat: on the pre-tower binary it is the SECOND block of the
# hover (a Var leads it) and that clause still printed PASS. The FIRST def block is the one a reader reads first, so the
# Method block's offset must EQUAL the offset of the first "**<kind>** `" marker, not merely exist somewhere in the answer.
h_first="$( printf '%s' "$R43" | grep -bo '\*\*[a-z]*\*\* `' | cut -d: -f1 | head -1 )"
h_m="$( printf '%s' "$R43" | grep -bo '\*\*method\*\* `AllFour::name`' | cut -d: -f1 | head -1 )"
[ -n "$p_m" ] && [ -n "$p_v" ] && [ -n "$p_c" ] && [ -n "$p_y" ] \
    && [ "$p_m" -lt "$p_v" ] && [ "$p_v" -lt "$p_c" ] && [ "$p_c" -lt "$p_y" ] \
    && [ -n "$q_m" ] && [ -n "$q_v" ] && [ "$q_m" -lt "$q_v" ] \
    && [ -n "$h_first" ] && [ -n "$h_m" ] && [ "$h_m" = "$h_first" ] \
    && ok "(18) picker order: Method before Var before column-Section before yaml-Section on ws/symbol, def-front and hover-front" \
    || { no "(18) tower order wrong: m=$p_m v=$p_v c=$p_c y=$p_y d_m=$q_m d_v=$q_v h_m=$h_m h_first=$h_first"; printf '%s\n' "$head40" | head -c 400; printf '%s\n' "$head41" | head -c 240; }

# ── (19) the ONE multi-def disclosure sentence, hover + definition logMessage, absent on single-def ───
printf '%s' "$R42" | grep -q '19 definitions for .name. — counts are floors; a call may bind to any one of them' \
    && ok "(19) hover discloses the def count + may-bind sentence on the colliding name" \
    || { no "(19) hover disclosure missing"; printf '%s\n' "$R42" | head -c 400; }
n19="$( grep -c 'window/logMessage.*19 definitions for .name. — counts are floors; a call may bind to any one of them' "$WORK/r18" )"
l41="$( grep -n '"id":41,' "$WORK/r18" | cut -d: -f1 )"; l19="$( grep -n 'window/logMessage.*19 definitions' "$WORK/r18" | head -1 | cut -d: -f1 )"
[ "$n19" = 1 ] && [ -n "$l19" ] && [ -n "$l41" ] && [ "$l19" -lt "$l41" ] \
    && ok "(19) the definition answer carries ONE window/logMessage disclosure AHEAD of it" \
    || { no "(19) definition logMessage wrong: n=$n19 noticeLine=$l19 respLine=$l41"; }
# Premise (fix round 4): credit the silence only to an ANSWERING hover. When the id-5 row was absent (dialog
# truncated, decodeFrames threw) or its result null (lspHover regressed), the old bare `grep -q` failed and the ||
# branch printed PASS — the one clause of the round that could not tell "no disclosure, because the name has one
# def" from "no answer at all". R 5 reads $WORK/resp, the geometry dialog: the single-def tree this control is about.
if ! printf '%s' "$R5" | grep -q '"result":{'; then
    no "(19) premise broken — the id-5 hover did not answer (row absent or result null), so its silence proves nothing: $( printf '%s' "$R5" | head -c 160 )"
elif printf '%s' "$R5" | grep -q 'definitions for .scale.'; then
    no "(19) single-def name carries a multi-def disclosure"
else
    ok "(19) scale (single def) carries no disclosure (premise held: the id-5 hover answered)"
fi

# ── (20) Used-at parity: hover answers every CLI --uses call row for the colliding name ────────────────
UR="$( cd "$WORK/collide" && "$BIN" --uses=name . 2>/dev/null | grep -oE '<u role="call" p="[^"]+"' | sed 's/.*p="//; s/"$//' | sort -u )"
n_ur="$( printf '%s\n' "$UR" | grep -c . )"
# Premise (fix round 4): the hover's Used-at tier is capped at kLspHoverUseCap=8 (src/lsp.h:65, applied by
# lspAppendSiteTier at src/lsp.h:912, which discloses a cut as "_+N more_"); the CLI --uses list is NOT capped, so
# "every CLI row appears in the hover" is a server promise only while the rows fit the tier. Pin that before the
# loop: widen the fixture past 8 and a correct, properly disclosed truncation used to read as a parity failure.
if [ -z "$UR" ]; then
    no "(20) premise broken — the CLI --uses answer carries no call rows to compare"
elif [ "$n_ur" -gt 8 ]; then
    no "(20) premise broken — $n_ur CLI --uses rows exceed the hover tier's kLspHoverUseCap=8; parity is only promised within the cap"
else
    miss=""
    for row in $UR; do
        site="${row%:*}"; ln="${row##*:}"
        printf '%s' "$R42" | grep -qF "$site#L$ln" || miss="$miss $row"
    done
    [ -z "$miss" ] \
        && ok "(20) Used-at parity within the cap: all $n_ur CLI --uses call rows (<= kLspHoverUseCap=8) appear as hover links" \
        || { no "(20) parity missing rows:$miss (rows seen: $( echo $UR | tr ' ' ',' ))"; }
fi

# ── (18b) schema-column click: definition on a column use-site lands on schema.rb, unique and split ───
cat > "$WORK/collide/click_single.rb" <<'EOF'
# C task arm 18b: consumer of the UNIQUE column event_id -> schema.rb line 29 (0-based 28)
Spike::IdRenamed.new.event_id
EOF
cat > "$WORK/collide/click_split.rb" <<'EOF'
# C task arm 18b: consumer of a COLUMN-ONLY repeated name (timestamps, no code def) -> schema row first
Spike::ColumnYaml.new.created_at
EOF
{
  msg "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"rootUri\":\"$uriColl\",\"capabilities\":{}}}"
  msg "{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":{}}"
  msg "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file://$WORK/collide/click_single.rb\",\"languageId\":\"ruby\",\"version\":1,\"text\":\"\"}}}"
  msg "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file://$WORK/collide/click_split.rb\",\"languageId\":\"ruby\",\"version\":1,\"text\":\"\"}}}"
  msg "{\"jsonrpc\":\"2.0\",\"id\":44,\"method\":\"textDocument/definition\",\"params\":{\"textDocument\":{\"uri\":\"file://$WORK/collide/click_single.rb\"},\"position\":{\"line\":1,\"character\":25}}}"
  msg "{\"jsonrpc\":\"2.0\",\"id\":45,\"method\":\"textDocument/definition\",\"params\":{\"textDocument\":{\"uri\":\"file://$WORK/collide/click_split.rb\"},\"position\":{\"line\":1,\"character\":25}}}"
  msg "{\"jsonrpc\":\"2.0\",\"id\":46,\"method\":\"textDocument/hover\",\"params\":{\"textDocument\":{\"uri\":\"file://$WORK/collide/click_split.rb\"},\"position\":{\"line\":1,\"character\":25}}}"
  msg "{\"jsonrpc\":\"2.0\",\"id\":99,\"method\":\"shutdown\"}"
  msg "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}"
} > "$WORK/d18b"
"$BIN" --lsp < "$WORK/d18b" > "$WORK/raw18b" 2>/dev/null
decodeFrames "$WORK/raw18b" > "$WORK/r18b" 2>/dev/null
head44="$( grep '"id":44,' "$WORK/r18b" | head -1 )"; head45="$( grep '"id":45,' "$WORK/r18b" | head -1 )"; R46="$( grep '"id":46,' "$WORK/r18b" )"
# Both clauses pin the FIRST Location row by offset, like arm (18)'s def-front sibling. The old 340-byte window spanned the
# WHOLE id-45 answer (two ~130-byte rows plus a 35-byte prefix = ~300 bytes), so it proved the schema.rb:75 row was PRESENT,
# never that it led: with the t.timestamps-minted row ahead of it the needle still fell inside the window and printed PASS.
# r1_4x is the start of the answer's first row, r2_4x the start of its second (empty when the answer holds one row); the
# needle must lie inside the first row, and for the split name ahead of the other schema row.
r1_44="$( printf '%s' "$head44" | grep -bo '{"uri":"' | cut -d: -f1 | head -1 )"; r2_44="$( printf '%s' "$head44" | grep -bo '},{"uri":"' | cut -d: -f1 | head -1 )"
r1_45="$( printf '%s' "$head45" | grep -bo '{"uri":"' | cut -d: -f1 | head -1 )"; r2_45="$( printf '%s' "$head45" | grep -bo '},{"uri":"' | cut -d: -f1 | head -1 )"
o28="$( printf '%s' "$head44" | grep -bo 'schema\.rb","range":{"start":{"line":28' | cut -d: -f1 | head -1 )"
o75="$( printf '%s' "$head45" | grep -bo 'schema\.rb","range":{"start":{"line":75' | cut -d: -f1 | head -1 )"
o82="$( printf '%s' "$head45" | grep -bo 'schema\.rb","range":{"start":{"line":82' | cut -d: -f1 | head -1 )"
[ -n "$o28" ] && [ -n "$r1_44" ] && [ "$o28" -ge "$r1_44" ] && { [ -z "$r2_44" ] || [ "$o28" -lt "$r2_44" ]; } \
    && [ -n "$o75" ] && [ -n "$r1_45" ] && [ -n "$r2_45" ] && [ "$o75" -ge "$r1_45" ] && [ "$o75" -lt "$r2_45" ] \
    && [ -n "$o82" ] && [ "$o75" -lt "$o82" ] \
    && printf '%s' "$R46" | grep -q 'definitions for .created_at.' \
    && ok "(18b) column clicks land on schema.rb — unique event_id -> its row; column-only created_at -> schema first with the N-definitions disclosure" \
    || { no "(18b) schema-column click wrong: e44 needle=$o28 in[$r1_44,${r2_44:-end}] | s45 needle=$o75 in[$r1_45,${r2_45:-end}] other=$o82"; printf '%s\n' "$head44" | head -c 240; printf '%s\n' "$head45" | head -c 240; }

# ── (21) C/C++ decl/def: the LOWER-id header prototype yields to the bodyful def on the SINGLE-PICK verb ─────
# WHY THE FIXTURE IS NAMED quad.h + z_quad.cpp: ids follow SORTED crawl order, and "quad.h" sorts before
# "z_quad.cpp", so the bodyless prototype carries the LOWER NodeId and the tower's id-ASC tie leads with it. That is
# the only order in which resolveFocus's same-scope body preference (graph.h) decides the answer: delete the yield and
# the focus stays quad.h's declaration, which carries no call or extends edges — the walk would then name the
# declaration's own row and never reach use_quad. textDocument/definition cannot show that pick at all (lsp.h
# lspDefinition answers the WHOLE def list via resolveAllByName), so it is pinned here beside the pick, as the
# no-regression answer it actually is, and the pick itself is read off a single-pick verb.
mkdir -p "$WORK/cppdd"
cat > "$WORK/cppdd/quad.h" <<'EOF'
// decl/def fixture — the HEADER sorts FIRST, so this prototype carries the lower crawl-order id
int quad( int f );
EOF
cat > "$WORK/cppdd/z_quad.cpp" <<'EOF'
int quad( int f )
{
    return f * 4;
}

int use_quad()
{
    return quad( 2 );
}
EOF
uriCpp="file://$WORK/cppdd"
{
  msg "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"rootUri\":\"$uriCpp\",\"capabilities\":{}}}"
  msg "{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":{}}"
  msg "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file://$WORK/cppdd/z_quad.cpp\",\"languageId\":\"cpp\",\"version\":1,\"text\":\"\"}}}"
  msg "{\"jsonrpc\":\"2.0\",\"id\":50,\"method\":\"textDocument/definition\",\"params\":{\"textDocument\":{\"uri\":\"file://$WORK/cppdd/z_quad.cpp\"},\"position\":{\"line\":7,\"character\":11}}}"
  msg "{\"jsonrpc\":\"2.0\",\"id\":99,\"method\":\"shutdown\"}"
  msg "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}"
} > "$WORK/d21"
"$BIN" --lsp < "$WORK/d21" > "$WORK/raw21" 2>/dev/null
decodeFrames "$WORK/raw21" > "$WORK/r21" 2>/dev/null
resp50="$( grep '"id":50,' "$WORK/r21" | head -1 )"
# the whole-list answer: BOTH definitions are named, the body among them (the list is not a pick — do not read order here)
printf '%s' "$resp50" | grep -qF "\"uri\":\"file://$WORK/cppdd/quad.h\",\"range\":{\"start\":{\"line\":1" \
    && printf '%s' "$resp50" | grep -qF "\"uri\":\"file://$WORK/cppdd/z_quad.cpp\",\"range\":{\"start\":{\"line\":0" \
    || { no "(21) the def list no longer names both the prototype (quad.h:2) and the body (z_quad.cpp:1)"; printf '%s\n' "$resp50" | head -c 300; }
ar21="$( cd "$WORK/cppdd" && "$BIN" --around=quad . 2>/dev/null )"
printf '%s' "$ar21" | grep -q '<r [^>]*defs="2"' \
    || no "(21) premise broken — --around=quad's root carries no defs=\"2\", so the name has no pick for the refinement to make: $( printf '%s' "$ar21" | grep -m1 -o '<r [^>]*>' | head -c 160 )"
w21="$( printf '%s' "$ar21" | grep -cF '<f p="z_quad.cpp"><s t="fn" n="quad"' )"
c21="$( printf '%s' "$ar21" | grep -cF '<s t="fn" n="use_quad"' )"
n21="$( printf '%s' "$ar21" | grep -cF '<f p="quad.h">' )"
[ "$w21" = 1 ] && [ "$c21" = 1 ] && [ "$n21" = 0 ] \
    && ok "(21) single-pick decl/def refinement composes with the sort: --around walks the bodyful .cpp def and reaches its caller, never the lower-id header prototype" \
    || { no "(21) the pick did not move to the body — the same-scope yield is what does that here (bodyRow=$w21 caller=$c21 declRow=$n21)"; printf '%s\n' "$ar21" | grep -o '<r [^>]*>\|<f p="[^"]*">' | head -4; }

# ── (23) known-gap coherence: the CLI row shows the tower front AND its defs= count ───────────────────
c23="$( cd "$WORK/collide" && "$BIN" --around=name . 2>/dev/null | grep -m1 -o '<s t="method" n="name" sc="AllFour"' )"
d23="$( cd "$WORK/collide" && "$BIN" --around=name . 2>/dev/null | grep -m1 -o 'defs="[0-9]*"' )"
[ -n "$c23" ] && [ "$d23" = 'defs="19"' ] \
    && ok "(23) --around names the tower front (t=method AllFour::name) while disclosing defs=\"19\" — the edge-vs-display gap is visible on the row" \
    || { no "(23) known-gap coherence broken: focus='$c23' count='$d23'"; }

# ── (24) a constructor never outranks its class ──────────────────────────────────────────────────────
mkdir -p "$WORK/ctorj" "$WORK/ctorc"
cat > "$WORK/ctorj/Shape.java" <<'EOF'
public class Shape {
  public Shape() {}
  public void area() {}
}
class Sq extends Shape { public void area() {} }
class Maker { public Sq Sq() { return null; } }
EOF
cat > "$WORK/ctorc/a_widget.h" <<'EOF'
class Widget {
public:
    Widget();
    virtual void draw() = 0;
};
EOF
cat > "$WORK/ctorc/widget.cpp" <<'EOF'
#include "a_widget.h"
Widget::Widget() {}
class Button : public Widget { public: void draw() override {} };
EOF
lj24="$( cd "$WORK/ctorj" && "$BIN" --lego=Shape . 2>/dev/null )"
aj24="$( cd "$WORK/ctorj" && "$BIN" --around=Shape . 2>/dev/null )"
lc24="$( cd "$WORK/ctorc" && "$BIN" --lego=Widget . 2>/dev/null )"
ac24="$( cd "$WORK/ctorc" && "$BIN" --around=Widget . 2>/dev/null )"
nm24="$( cd "$WORK/ctorj" && "$BIN" --around=Sq . 2>/dev/null )"
printf '%s' "$lj24" | grep -q '<iface n="Shape" [^>]*defs="2" implementors="1"' && printf '%s' "$lj24" | grep -qF '<impl n="Sq"' \
    && ok "(24) Java: --lego=Shape answers the class (implementors=1, Sq), not its constructor" \
    || { no "(24) Java --lego=Shape lost the class to its constructor"; printf '%s' "$lj24" | grep -o '<iface [^>]*>' | head -1; }
printf '%s' "$aj24" | grep -qF '<s t="cls" n="Shape"' \
    && ok "(24) Java: --around=Shape focuses the class row" \
    || { no "(24) Java --around=Shape focus is not the class"; printf '%s' "$aj24" | grep -o '<s [^>]*>' | head -1; }
printf '%s' "$lc24" | grep -q '<iface n="Widget" p="a_widget.h" [^>]*implementors="1"' && printf '%s' "$lc24" | grep -qF '<impl n="Button"' \
    && ok "(24) C++: --lego=Widget answers the header class (implementors=1, Button), not the out-of-line Widget::Widget()" \
    || { no "(24) C++ --lego=Widget lost the class to its constructor"; printf '%s' "$lc24" | grep -o '<iface [^>]*>' | head -1; }
printf '%s' "$ac24" | grep -qF '<f p="a_widget.h"><s t="cls" n="Widget"' \
    && ok "(24) C++: --around=Widget focuses the class row in a_widget.h" \
    || { no "(24) C++ --around=Widget focus is not the class"; printf '%s' "$ac24" | grep -o '<f p="[^"]*"><s [^>]*>' | head -1; }
printf '%s' "$nm24" | grep -qF '<f p="Shape.java"><s t="method" n="Sq"' \
    && ok "(24) near-miss: Maker.Sq(), a method named like ANOTHER class, keeps the Method rung (not a constructor)" \
    || { no "(24) near-miss: the constructor rung swallowed a method that merely shares a class's name"; printf '%s' "$nm24" | grep -o '<s [^>]*>' | head -1; }

# ── (25) a prototype beside its body is COUNTED, never called a split ──────────────────────────────
# The graph binds helper(2) to the body alone (no amb=), so the sentence may count the prototype but must not say the
# resolver split the call: "a call may bind to any one of them" is the claim the mechanism supports.
mkdir -p "$WORK/protodef"
printf 'int helper(int x);\n' > "$WORK/protodef/h.h"
printf '#include "h.h"\nint helper(int x) { return x + 1; }\nint top(void) { return helper(2); }\n' > "$WORK/protodef/h.c"
uriPD="file://$WORK/protodef/h.c"
{
  msg "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"rootUri\":\"file://$WORK/protodef\",\"capabilities\":{}}}"
  msg "{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":{}}"
  msg "{\"jsonrpc\":\"2.0\",\"id\":51,\"method\":\"textDocument/definition\",\"params\":{\"textDocument\":{\"uri\":\"$uriPD\"},\"position\":{\"line\":2,\"character\":25}}}"
  msg "{\"jsonrpc\":\"2.0\",\"id\":52,\"method\":\"textDocument/hover\",\"params\":{\"textDocument\":{\"uri\":\"$uriPD\"},\"position\":{\"line\":2,\"character\":25}}}"
  msg "{\"jsonrpc\":\"2.0\",\"id\":99,\"method\":\"shutdown\"}"
  msg "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}"
} > "$WORK/d25"
( cd "$WORK/protodef" && "$BIN" --lsp < "$WORK/d25" > "$WORK/raw25" 2>/dev/null )
decodeFrames "$WORK/raw25" > "$WORK/r25" 2>/dev/null
h25="$( grep '"id":52,' "$WORK/r25" )"
n25="$( grep -c 'window/logMessage.*2 definitions for .helper.' "$WORK/r25" )"
printf '%s' "$h25" | grep -q '2 definitions for .helper.' && [ "$n25" = 1 ] \
    || no "(25) premise broken — the prototype+body pair no longer reads as 2 definitions (hover/logMessage=$n25)"
grep -q 'splits over' "$WORK/r25" \
    && no "(25) the disclosure says the resolver SPLIT a call it bound to the body alone" \
    || ok "(25) prototype+body: counted as 2 definitions, no split claimed (the call binds to the body)"

# ── (26) kind tier before language tier ──────────────────────────────────────────────────────────────
mkdir -p "$WORK/mixlang"
printf 'class AllFour\n  attr_reader :name\nend\n' > "$WORK/mixlang/a.rb"
printf 'class name:\n    pass\n' > "$WORK/mixlang/b.py"
printf 'class Other\n  def name\n    1\n  end\nend\nOther.new.name\n' > "$WORK/mixlang/c.rb"
o26="$( cd "$WORK/mixlang" && "$BIN" --impact=name . 2>/dev/null | grep -o '<def ix="[0-9]*" t="[a-z]*"[^>]*p="[^"]*"' | tr '\n' ' ' )"
case "$o26" in
    *'ix="1" t="method" sc="Other" p="c.rb:2"'*'ix="2" t="cls" sc="name" p="b.py:1"'*'ix="3" t="var" sc="AllFour" p="a.rb:2"'*)
        ok "(26) kind before language: Ruby method, then the Python class, then the Ruby attr" ;;
    *)  no "(26) tier order wrong (a language-first comparator puts the Ruby attr ahead of the Python class): $o26" ;;
esac

# ── (22) determinism x2 on the collision dialog (house pattern) ───────────────────────────────────────
"$BIN" --lsp < "$WORK/d18" > "$WORK/raw22a" 2>/dev/null
"$BIN" --lsp < "$WORK/d18" > "$WORK/raw22b" 2>/dev/null
cmp -s "$WORK/raw22a" "$WORK/raw22b" && [ -s "$WORK/raw22a" ] \
    && ok "(22) collision dialog byte-identical across two runs" \
    || { no "(22) collision dialogs differ"; ls -l "$WORK/raw22a" "$WORK/raw22b"; }

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
