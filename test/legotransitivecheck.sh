#!/usr/bin/env bash
# legotransitivecheck.sh — the --lego verb's IMPLEMENTOR CLOSURE and the edges that feed it.
#
#   test/legotransitivecheck.sh [BIN]        # BIN defaults to $RIPWIRE_BIN, then build/ripwire
#
# Corpus test/legotransitivefix (in-tree, outside test/fixture):
#   py/formatters.py  BaseFormatter <- {SimpleFormatter <- {Default, Pylint, FilenameOnly}, Nothing}
#   py/diamond.py     Top <- {Left, Right} <- Bottom (both) <- Deepest; Alone <- OnlyChild (direct rows only)
#   rb/*.rb           Rake::Task <- {FileTask <- FileCreationTask, MultiTask}; Rake::DSL mixed in
#   js/*.js           Node.extend('BinOp', …) class factories; Loader defined in code AND as a docs heading
#
# (S1) the TARGETED --lego lists implementors below a direct one, each once at its shallowest depth, as
#      <impl via= depth=>; transitive=N on the <iface>; implementors= still counts the direct rows alone;
#      --limit/--offset (MCP limit/offset) page the deeper rows, a cut says has_more="1" + a next= that pages on.
#      An interface with no deeper row carries none of it (byte identity with the direct-only answer).
# (S2) every <impl> row of the TARGETED answer says where the class is: p="file:LINE" (the --uses/--callers spelling); the
#      <iface> row and the ranked --for <lego> section keep their bare p=.
# (M1) a Ruby module mixed in with include/extend (captureRubyMixinBases) is an implements edge: --lego=DSL lists TaskLib.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/legotransitivefix"
DIR="$( mktemp -d )"; trap 'rm -rf "$DIR"' EXIT
fail=0
# every verdict is an if/else: a failed write of a PASS line must never print FAIL for an arm that passed (gateexitcheck G2)
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

echo "legotransitivecheck: BIN=$BIN"
[ -x "$BIN" ] || { echo "  FAIL  no ripwire binary at $BIN"; exit 1; }

# lego SEL [extra flags…] — the answer, one tag per line, in $OUT; returns non-zero (and FAILs) when the run failed or
# printed no <lego> root, so an absence arm never reads a crashed or empty run as "not listed".
OUT=""
lego(){
    local sel="$1"; shift
    if ! "$BIN" "$FIX" --no-cache --lego="$sel" "$@" >"$DIR/out" 2>"$DIR/err"
    then
        no "--lego=$sel $* exited non-zero: $( head -3 "$DIR/err" )"; OUT=""; return 1
    fi
    OUT="$( sed 's/></>\n</g' "$DIR/out" )"
    if ! printf '%s\n' "$OUT" | grep -q '^<lego'
    then
        no "--lego=$sel $* printed no <lego> root"; return 1
    fi
    return 0
}
has(){ printf '%s\n' "$OUT" | grep -qF -- "$1"; }
count(){ printf '%s\n' "$OUT" | grep -cF -- "$1"; }
iface(){ printf '%s\n' "$OUT" | grep -m1 '^<iface'; }

echo "=== (S1) the closure: deeper implementors with via= and depth= ==="
if lego BaseFormatter
then
    for n in SimpleFormatter Nothing Default Pylint FilenameOnly
    do
        if has "<impl n=\"$n\""; then ok "--lego=BaseFormatter lists $n"; else no "--lego=BaseFormatter does not list $n: $( iface )"; fi
    done
    if printf '%s\n' "$OUT" | grep '<impl n="Default"' | grep -q 'via="SimpleFormatter" depth="2"'; then ok "Default carries via=\"SimpleFormatter\" depth=\"2\""; else no "Default row lacks via/depth: $( printf '%s\n' "$OUT" | grep '<impl n="Default"' )"; fi
    if printf '%s\n' "$OUT" | grep '<impl n="SimpleFormatter"' | grep -q 'via=\|depth='; then no "a DIRECT row carries via=/depth="; else ok "the direct rows carry neither via= nor depth="; fi
    if iface | grep -q 'implementors="2" transitive="3"'; then ok "implementors=\"2\" counts the direct rows, transitive=\"3\" the deeper ones"; else no "counts wrong: $( iface )"; fi
    if iface | grep -q 'has_more=\|transitive_shown='; then no "an uncut closure says it was cut: $( iface )"; else ok "an uncut closure carries no cut attribute"; fi
fi
if lego Top
then
    if [ "$( count '<impl n="Bottom"' )" = 1 ]; then ok "a diamond lists Bottom once"; else no "Bottom listed $( count '<impl n="Bottom"' ) times"; fi
    if printf '%s\n' "$OUT" | grep '<impl n="Bottom"' | grep -q 'via="Left" depth="2"'; then ok "…at its shallowest depth, via the first parent in id order (Left)"; else no "Bottom row: $( printf '%s\n' "$OUT" | grep '<impl n="Bottom"' )"; fi
    if printf '%s\n' "$OUT" | grep '<impl n="Deepest"' | grep -q 'via="Bottom" depth="3"'; then ok "Deepest is depth 3 via Bottom"; else no "Deepest row: $( printf '%s\n' "$OUT" | grep '<impl n="Deepest"' )"; fi
    if iface | grep -q 'implementors="2" transitive="2"'; then ok "Top: implementors=\"2\" transitive=\"2\""; else no "Top counts: $( iface )"; fi
fi
if lego Alone
then
    if iface | grep -q 'transitive="'; then no "an interface with direct rows only carries transitive: $( iface )"; else ok "an interface with direct rows only carries no transitive attribute"; fi
    if [ "$( count ' via="' )" = 0 ]; then ok "…and no via= row"; else no "Alone has via= rows"; fi
fi
if lego OnlyChild
then
    if iface | grep -q 'implementors="0"' && ! has 'transitive="'; then ok "a leaf class answers implementors=\"0\" with no closure attribute"; else no "leaf: $( iface )"; fi
fi

echo "=== (S2) every TARGETED impl row carries its definition's line ==="
if lego BaseFormatter
then
    if has '<impl n="SimpleFormatter" p="py/formatters.py:7"/>'; then ok "a direct row: p=\"py/formatters.py:7\" (the class line)"; else no "direct row: $( printf '%s\n' "$OUT" | grep '<impl n="SimpleFormatter"' )"; fi
    if has '<impl n="Pylint" p="py/formatters.py:15" via='; then ok "a deeper row: p=\"py/formatters.py:15\""; else no "deeper row: $( printf '%s\n' "$OUT" | grep '<impl n="Pylint"' )"; fi
    if iface | grep -q 'p="py/formatters.py"'; then ok "the <iface> row keeps its bare p= (unchanged)"; else no "iface p= changed: $( iface )"; fi
fi
# the ranked --for <lego> section is NOT the targeted answer: its rows keep the bare p= (byte identity outside the verb)
if "$BIN" "$FIX" --no-cache --for="formatter base class" --sections=lego,compose >"$DIR/for" 2>"$DIR/err"
then
    if grep -q '<impl n="[A-Za-z]*" p="[^"]*"' "$DIR/for"; then
        if grep -q '<impl n="[A-Za-z]*" p="[^"]*:[0-9]' "$DIR/for"; then no "a --for <lego> row gained :LINE"; else ok "--for <lego> rows keep p=\"file\""; fi
    else
        no "--for printed no <impl> row to check: $( head -c 300 "$DIR/for" )"
    fi
else
    no "--for exited non-zero: $( head -2 "$DIR/err" )"
fi

echo "=== (S1) the page: --limit/--offset window the deeper rows; next= pages on ==="
if lego BaseFormatter --limit=2
then
    I="$( iface )"
    if printf '%s' "$I" | grep -q 'transitive="3" transitive_shown="2" has_more="1"'; then ok "a cut page says transitive_shown=\"2\" has_more=\"1\""; else no "cut page: $I"; fi
    N="$( printf '%s' "$I" | sed -n 's/.* next="\([^"]*\)".*/\1/p' )"
    if [ "$N" = "--lego=py/formatters.py:BaseFormatter --limit=2 --offset=2" ]; then ok "next= replays the verb on the iface's file:name with the next offset"; else no "next= is '$N'"; fi
    if has '<impl n="SimpleFormatter"' && has '<impl n="Nothing"'; then ok "the direct rows ride every page"; else no "a direct row is missing from the page"; fi
    if [ "$( count ' via="' )" = 2 ]; then ok "two deeper rows on the page"; else no "deeper rows on page 1: $( count ' via="' )"; fi
fi
# replay the next= exactly as printed (its value is shell-safe by construction: nextFlag quotes what a shell would split)
N2="${N:---lego=py/formatters.py:BaseFormatter --limit=2 --offset=2}"
# shellcheck disable=SC2086
if lego ${N2#--lego=}
then
    I="$( iface )"
    if printf '%s' "$I" | grep -q 'transitive_shown="1" transitive_offset="2"'; then ok "page 2: transitive_shown=\"1\" transitive_offset=\"2\""; else no "page 2: $I"; fi
    if printf '%s' "$I" | grep -q 'has_more'; then no "the last page says has_more: $I"; else ok "the last page carries no has_more"; fi
    if has '<impl n="FilenameOnly"' && ! has '<impl n="Default"'; then ok "page 2 holds the third deeper row only"; else no "page 2 rows wrong"; fi
fi
if "$BIN" "$FIX" --no-cache --lego=BaseFormatter --limit=abc >/dev/null 2>"$DIR/err"
then
    no "--limit=abc beside --lego was accepted"
else
    if grep -q -- '--limit' "$DIR/err"; then ok "--limit=abc beside --lego is refused naming the flag"; else no "refusal text: $( head -2 "$DIR/err" )"; fi
fi
if "$BIN" "$FIX" --no-cache --lego=BaseFormatter --max-tokens=50 >"$DIR/out" 2>"$DIR/err"
then
    if grep -q 'not read by --lego' "$DIR/err" && grep -q 'transitive="3"' "$DIR/out"; then ok "--max-tokens without a page is still the not-read notice, full answer"; else no "--max-tokens notice changed: $( head -2 "$DIR/err" )"; fi
else
    no "--lego --max-tokens (no page) now refuses: $( head -2 "$DIR/err" )"
fi

echo "=== (S1) MCP lego pages the same way ==="
mcp(){ printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"lego\",\"arguments\":{\"path\":\"$FIX\",\"type\":\"BaseFormatter\"$1}}}" | "$BIN" --mcp 2>/dev/null; }
M="$( mcp ',"limit":2' )"
if printf '%s' "$M" | grep -q 'transitive_shown=\\"2\\" has_more=\\"1\\"'; then ok "MCP limit:2 cuts the deeper rows the same way"; else no "MCP limit:2: $( printf '%s' "$M" | head -c 300 )"; fi
M="$( mcp '' )"
if printf '%s' "$M" | grep -q 'transitive=\\"3\\"' && ! printf '%s' "$M" | grep -q 'has_more'; then ok "MCP without a window: the whole closure"; else no "MCP default: $( printf '%s' "$M" | head -c 300 )"; fi
M="$( mcp ',"offset":-1' )"
if printf '%s' "$M" | grep -q '"error"'; then ok "MCP offset:-1 is refused"; else no "MCP offset:-1 accepted: $( printf '%s' "$M" | head -c 300 )"; fi

echo "=== (M1) a Ruby module mixed in is an implements edge: include / extend ==="
if lego DSL
then
    if has '<impl n="TaskLib" p="rb/tasklib.rb:2"/>'; then ok "--lego=DSL lists TaskLib (include Rake::DSL) at rb/tasklib.rb:2"; else no "--lego=DSL: no TaskLib row: $( iface )"; fi
    if has '<impl n="MakefileLoader"'; then ok "--lego=DSL lists MakefileLoader"; else no "--lego=DSL: no MakefileLoader"; fi
    if has '<impl n="Singleton"'; then ok "--lego=DSL lists Singleton (extend Rake::DSL)"; else no "--lego=DSL: no Singleton (extend)"; fi
    if iface | grep -q 'implementors="3"'; then ok "implementors=\"3\": the top-level self.extend adds no row"; else no "DSL count: $( iface )"; fi
    if iface | grep -q 'implementors_floor'; then no "the bound include still reads as an unbound floor: $( iface )"; else ok "no implementors_floor once the include binds"; fi
fi
if lego Helpers
then
    if iface | grep -q 'implementors="0"'; then ok "an include inside a method body is no edge (Helpers lists nobody)"; else no "Helpers: $( iface )"; fi
fi
if lego Ping
then
    if [ "$( count '<impl n="Pong"' )" = 1 ] && [ "$( count '<impl n="Pinged"' )" = 1 ] && ! has '<impl n="Ping"'; then ok "a module cycle (Ping <-> Pong) lists each type once and never the interface itself"; else no "Ping cycle rows: $( printf '%s\n' "$OUT" | grep '^<impl' | tr '\n' ' ' )"; fi
fi
if lego Pong
then
    if printf '%s\n' "$OUT" | grep '<impl n="Pinged"' | grep -q 'via="Ping" depth="2"'; then ok "--lego=Pong reaches Pinged through Ping (depth 2)"; else no "Pong closure: $( printf '%s\n' "$OUT" | grep '^<impl' | tr '\n' ' ' )"; fi
fi

echo "=== well-formed ==="
if command -v xmllint >/dev/null 2>&1
then
    for a in "--lego=BaseFormatter" "--lego=BaseFormatter --legend=full" "--lego=BaseFormatter --limit=1 --legend=full" "--lego=Top --legend=full"
    do
        # shellcheck disable=SC2086
        if "$BIN" "$FIX" --no-cache $a 2>/dev/null | xmllint --noout - 2>/dev/null; then ok "xml well-formed: $a"; else no "xml malformed: $a"; fi
    done
else
    echo "  SKIP  xmllint absent"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
