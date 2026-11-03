#!/usr/bin/env bash
# forroutecheck.sh — FOR-ROUTE-DECLINED (src/forgraphverb.h, lexical.h parseGraphSubject): a --for task spelled as a graph
# question (`path from A to B`, `callers of X`, `common callers of A and B`) appends that verb's default answer inside
# <graph_verb endpoints="subject" verb=… *_span=…> just before </ctx>; the endpoints come from the task's words, so the
# block says so. A description ("serialising a dict", "spawning ripgrep") never fires, even when its plain words are
# symbol names; an endpoint no resolver finds appends nothing; a non-graph task appends nothing.
#   (p1) path form: the --path answer for the two named symbols, reachable="1", once, right before </ctx>, well-formed
#   (p2) the qualifier tail is cut (to_span= stops before "for"), and `main` is the one plain word that is an endpoint
#   (c1) callers form: the --callers answer (both callers listed); (c2) the qualifier tail "with ..." is cut
#   (v1)/(v2) the block's verb answer is byte-identical to the bare --path= / --callers= call (default caps, compact legend);
#        v1 under RIPWIRE_NO_HOP_BODY=1 (the pre-PATH-HOP-BODY premise). (v1b) hop bodies on: identical but for a middle hop body
#        whose text the --for answer already carries outside the block (src/hopbody.h; not printed twice)
#   (m1) common-callers form: the --connect answer for both names
#   (t1) an unresolved last-first candidate falls through to the next one, and tried="2" says so
#   (n1) "path from X to serialising a dict" does NOT fire, though `dict` is a symbol here
#   (n2) "path from X to spawning ripgrep" does NOT fire, though `spawning` and `ripgrep` are symbols here
#   (n3) an endpoint no resolver finds: no block, and nothing on stdout says not found
#   (n4) a task that is not a graph question: no block
#   (j1) --json carries no block (one document per dialect)
#   (x1) MCP `for`: the same <graph_verb …> opening tag and the same path answer element
# FIX ROUND 1 (review B1/S1-S5, mutants):
#   (n5)(n6)(n7)(c3) a span ends at a sentence stop, a comma or a clause word: a LATER clause's symbol never becomes an endpoint
#   (n5b) a `*` token is never an endpoint (a glob --path the task did not write)
#   (t1) unresolved= names the spelling that failed; (s4a)(s4b)(s4c) `dict()`, «guillemets», full-width ？ endpoints are read
#   (x2) the MCP callers block carries its JSON as CDATA with dialect="json" (no &quot;); (b1a)(b2) a token budget holds the verb back (held="budget")
#   (n8) `e.g.` is prose, never a candidate; (h3) MCP name_test_hops
#   (h1)(h2) a path hop matched by name alone into a test file says so (name_test_hops=); the same hop into a source file does not
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "forroutecheck: BIN=$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
FX="$TMP/fx"; mkdir -p "$FX"
cat > "$FX/flow.c" <<'C'
void leaf_sink( void ) {}
void mid_hop( void ) { leaf_sink(); }
void startEntry( void ) { mid_hop(); }
void other_caller( void ) { leaf_sink(); }
void dict( void ) {}
void spawning( void ) {}
void ripgrep( void ) {}
int main( void ) { startEntry(); other_caller(); dict(); spawning(); ripgrep(); return 0; }
C
run(){ ( cd "$FX" || exit 1; "$BIN" "$FX" --no-cache "$@" 2>/dev/null ); }
# block facts: count, verb=, spans, tried=, whether it closes right before </ctx> as the document's end, and the verb element
facts(){ python3 - "$1" <<'PY'
import re, sys
s = open( sys.argv[1], encoding="utf8", errors="replace" ).read()
n = s.count( '<graph_verb ' )
m = re.search( r'<graph_verb ([^>]*)>', s )
a = m.group( 1 ) if m else ''
g = lambda k: ( re.search( r'\b' + k + r'="([^"]*)"', a ) or [None, '-'] )[1]
tail = s.endswith( '</graph_verb></ctx>' )
leg = re.search( r'<!-- ripwire for graph_verb:(.*?)-->', s, re.S )
legdash = '--' in leg.group( 1 ) if leg else False
print( f"n={n} endpoints={g('endpoints')} verb={g('verb')} from={g('from_span')} to={g('to_span')} of={g('of_span')} and={g('and_span')} tried={g('tried')} tail={int(tail)} legdash={int(legdash)}" )
PY
}
attr(){ python3 - "$1" "$2" <<'PY'
import re, sys
s = open( sys.argv[1], encoding="utf8", errors="replace" ).read()
m = re.search( r'<graph_verb ([^>]*)>', s )
r = re.search( r'\b' + sys.argv[2] + r'="([^"]*)"', m.group( 1 ) ) if m else None
print( r.group( 1 ) if r else '-' )
PY
}
xmlok(){ if command -v xmllint >/dev/null 2>&1; then xmllint --noout "$1" 2>/dev/null; else return 0; fi; }

run --for="path from startEntry to leaf_sink" >"$TMP/p1.xml"
f="$( facts "$TMP/p1.xml" )"
if [ "$f" = "n=1 endpoints=subject verb=--path=startEntry,leaf_sink from=startEntry to=leaf_sink of=- and=- tried=- tail=1 legdash=0" ] \
   && grep -q '<path [^>]*from="startEntry" to="leaf_sink"[^>]* reachable="1" hops="2"' "$TMP/p1.xml" && xmlok "$TMP/p1.xml"
then ok "(p1) path form: one <graph_verb endpoints=\"subject\"> with the --path answer (reachable=1 hops=2) right before </ctx>, well-formed"
else no "(p1) path form: $f"; fi

run --for="path from main to leaf_sink for a script file" >"$TMP/p2.xml"
f="$( facts "$TMP/p2.xml" )"
case "$f" in *"verb=--path=main,leaf_sink from=main to=leaf_sink of=- "*) ok "(p2) the qualifier tail is cut and \`main\` is an endpoint: $f";; *) no "(p2) $f";; esac

run --for="who are the callers of leaf_sink" >"$TMP/c1.xml"
f="$( facts "$TMP/c1.xml" )"
if [ "${f%% tried=*}" = "n=1 endpoints=subject verb=--callers=leaf_sink from=- to=- of=leaf_sink and=-" ] \
   && grep -q '<callers [^>]*of="leaf_sink"' "$TMP/c1.xml" && grep -q 'n="mid_hop"' "$TMP/c1.xml" && grep -q 'n="other_caller"' "$TMP/c1.xml"
then ok "(c1) callers form: the --callers answer for leaf_sink, both callers listed"
else no "(c1) callers form: $f"; fi

run --for="callers of leaf_sink with the local backend" >"$TMP/c2.xml"
f="$( facts "$TMP/c2.xml" )"
case "$f" in *" of=leaf_sink and=- "*) ok "(c2) the \"with ...\" tail is cut: of_span=leaf_sink";; *) no "(c2) $f";; esac

inner(){ python3 -c '
import re, sys
s = open( sys.argv[1], encoding="utf8", errors="replace" ).read()
m = re.search( r"<graph_verb [^>]*>(.*)</graph_verb></ctx>$", s, re.S )
sys.stdout.write( m.group( 1 ) if m else "NO-BLOCK" )' "$1"; }
# (v1) under the PATH-HOP-BODY A/B handle (src/hopbody.h), so its premise is the pre-lane one: the block's bytes ARE the bare call's.
# With hop bodies on, (v1b) below states the one by-design difference.
RIPWIRE_NO_HOP_BODY=1 run --for="path from startEntry to leaf_sink" >"$TMP/p1off.xml"
for arm in "v1|p1off|--path=startEntry,leaf_sink" "v2|c1|--callers=leaf_sink"
do
    id="${arm%%|*}"; rest="${arm#*|}"; src="${rest%%|*}"; flag="${rest#*|}"
    if [ "$id" = v1 ]; then RIPWIRE_NO_HOP_BODY=1 run "$flag" >"$TMP/$id.bare"; else run "$flag" >"$TMP/$id.bare"; fi
    inner "$TMP/$src.xml" >"$TMP/$id.inner"
    if [ -s "$TMP/$id.bare" ] && cmp -s "$TMP/$id.bare" "$TMP/$id.inner"
    then ok "($id) the block's verb answer is byte-identical to the bare $flag call (same default caps, same compact legend)"
    else no "($id) the block's verb answer differs from the bare $flag call ($( wc -c <"$TMP/$id.inner" ) vs $( wc -c <"$TMP/$id.bare" ) B)"; fi
done

# (v1b) PATH-HOP-BODY, hop bodies on: the block is the bare call, except that a middle hop body whose text the --for answer
# already carries (outside the block) is not printed twice — then the bare call's <bodies of="hops"> and its legend reading are the
# whole difference. A middle hop the answer does not carry stays in the block byte for byte.
run --path=startEntry,leaf_sink >"$TMP/v1b.bare"; inner "$TMP/p1.xml" >"$TMP/v1b.inner"
if python3 - "$TMP/v1b.bare" "$TMP/v1b.inner" "$TMP/p1.xml" <<'PY'
import re, sys
bare, inner, full = (open(f, encoding="utf8", errors="replace").read() for f in sys.argv[1:4])
if bare == inner: sys.exit(0)
el = re.search(r'<bodies of="hops".*?</bodies>', bare, re.S)
if not el or '<bodies of="hops"' in inner: sys.exit(1)
outside = full.split("<graph_verb ", 1)[0]
held = all(re.search(r'<b [^>]*p="%s"' % re.escape(m.group(1)), outside) for m in re.finditer(r'<b [^>]*p="([^"]*)"', el.group(0)))
nolegend = lambda t: re.sub(r'<!--.*?-->', '', t, flags=re.S)   # its present-only readings (bodies of=, the window) go with it; (v1) pins the legend
sys.exit(0 if held and nolegend(bare.replace(el.group(0), "")) == nolegend(inner) else 1)
PY
then ok "(v1b) hop bodies on: the block is the bare --path call, less only a middle hop body the answer already carries"
else no "(v1b) hop bodies on: the block differs from the bare --path call beyond the already-carried middle hop body"; fi

run --for="common callers of mid_hop and other_caller" >"$TMP/m1.xml"
f="$( facts "$TMP/m1.xml" )"
if [ "${f%% tried=*}" = "n=1 endpoints=subject verb=--connect=mid_hop,other_caller from=- to=- of=mid_hop and=other_caller" ] && grep -q '<connect ' "$TMP/m1.xml"
then ok "(m1) common-callers form: the --connect answer for both names"
else no "(m1) common-callers form: $f"; fi

run --for="path from startEntry to leaf_sink notReal_xq" >"$TMP/t1.xml"
f="$( facts "$TMP/t1.xml" )"
case "$f" in *"verb=--path=startEntry,leaf_sink "*"tried=2 "*) ok "(t1) the unresolved last-first candidate falls through, tried=2: $f";; *) no "(t1) $f";; esac
u="$( attr "$TMP/t1.xml" unresolved )"
if [ "$u" = "notReal_xq" ] && xmlok "$TMP/t1.xml"; then ok "(t1b) unresolved= names the spelling that failed (legend clause rides; well-formed)"; else no "(t1b) unresolved=[$u]"; fi

for arm in "n1|path from startEntry to serialising a dict" "n2|path from startEntry to spawning ripgrep" \
           "n3|path from startEntry to notReal_xq" "n4|how does startEntry reach leaf_sink"
do
    id="${arm%%|*}"; q="${arm#*|}"
    run --for="$q" >"$TMP/$id.xml"
    if [ -s "$TMP/$id.xml" ] && ! grep -q 'graph_verb' "$TMP/$id.xml" && ! grep -qi 'not found' "$TMP/$id.xml"
    then ok "($id) no block for \"$q\""
    else no "($id) a block (or a refusal) for \"$q\": $( facts "$TMP/$id.xml" )"; fi
done

# B1: a later clause's symbol never binds (each is a task whose LAST code-like word names a real symbol in another clause)
for arm in "n5|path from startEntry to leaf_sink. Afterwards summarise other_caller|--path=startEntry,leaf_sink|from_span=startEntry|to_span=leaf_sink." \
           "n7|path from startEntry to leaf_sink and then other_caller|--path=startEntry,leaf_sink|from_span=startEntry|to_span=leaf_sink" \
           "c3|callers of leaf_sink, mid_hop and other_caller|--callers=leaf_sink|of_span=leaf_sink,|-" \
           "s4a|callers of \`dict()\`|--callers=dict|of_span=\`dict()\`|-" \
           "s4b|callers of «leaf_sink»|--callers=leaf_sink|of_span=«leaf_sink»|-" \
           "s4c|callers of leaf_sink？ nothing else|--callers=leaf_sink|of_span=leaf_sink|-"
do
    IFS='|' read -r id q want sp1 sp2 <<<"$arm"
    run --for="$q" >"$TMP/$id.xml"
    v="$( attr "$TMP/$id.xml" verb )"; a1="$( attr "$TMP/$id.xml" "${sp1%%=*}" )"; a2="-"
    [ "$sp2" != "-" ] && a2="$( attr "$TMP/$id.xml" "${sp2%%=*}" )"
    if [ "$v" = "$want" ] && [ "$a1" = "${sp1#*=}" ] && { [ "$sp2" = "-" ] || [ "$a2" = "${sp2#*=}" ]; } && [ "$( grep -c '<graph_verb ' "$TMP/$id.xml" )" = 1 ]
    then ok "($id) \"$q\" -> $v ($sp1)"
    else no "($id) \"$q\": verb=[$v] want=[$want] span1=[$a1] span2=[$a2]"; fi
done
for arm in "n6|callers of plain and how mid_hop works" "n5b|path from startEntry to leaf_*"
do
    id="${arm%%|*}"; q="${arm#*|}"
    run --for="$q" >"$TMP/$id.xml"
    if [ -s "$TMP/$id.xml" ] && ! grep -q 'graph_verb' "$TMP/$id.xml"
    then ok "($id) no block for \"$q\""
    else no "($id) a block for \"$q\": $( facts "$TMP/$id.xml" )"; fi
done

# `e.g.` is prose: it never becomes a (failing) first candidate, so tried= stays absent
run --for="callers of leaf_sink e.g. the mock" >"$TMP/n8.xml"
if [ "$( attr "$TMP/n8.xml" verb )" = "--callers=leaf_sink" ] && [ "$( attr "$TMP/n8.xml" tried )" = "-" ]
then ok "(n8) \"e.g.\" is prose: --callers=leaf_sink with no tried="
else no "(n8) verb=[$( attr "$TMP/n8.xml" verb )] tried=[$( attr "$TMP/n8.xml" tried )] unresolved=[$( attr "$TMP/n8.xml" unresolved )]"; fi

# S2: a token budget holds the verb back: the self-closed tag names it, verb= is the call, no verb body
for arm in "b1a|--token-budget=4100"
do
    id="${arm%%|*}"; fl="${arm#*|}"
    run --for="path from startEntry to leaf_sink" "$fl" >"$TMP/$id.xml"
    if [ "$( attr "$TMP/$id.xml" held )" = "budget" ] && [ "$( attr "$TMP/$id.xml" verb )" = "--path=startEntry,leaf_sink" ] \
       && grep -q '<graph_verb [^>]*/></ctx>$' "$TMP/$id.xml" && ! grep -q '<path ' "$TMP/$id.xml" && xmlok "$TMP/$id.xml"
    then ok "($id) $fl: held=\"budget\", verb= names the call, no verb body, well-formed"
    else no "($id) $fl: held=[$( attr "$TMP/$id.xml" held )] $( facts "$TMP/$id.xml" )"; fi
done
mcp_call(){ printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"for","arguments":{"path":"%s","task":"%s"%s}}}\n' "$FX" "$1" "${2:-}" \
           | ( cd "$FX" || exit 1; "$BIN" --mcp 2>/dev/null ) | python3 -c '
import sys, json
for line in sys.stdin:
    try: d = json.loads( line )
    except Exception: continue
    c = d.get( "result", {} ).get( "content" )
    if c: print( c[0].get( "text", "" ), end="" )'; }
mcp_call "path from startEntry to leaf_sink" ',"budget_tokens":4100' >"$TMP/b2.xml"
if [ "$( attr "$TMP/b2.xml" held )" = "budget" ] && grep -q '<graph_verb [^>]*/></ctx>$' "$TMP/b2.xml" && ! grep -q '<path ' "$TMP/b2.xml"
then ok "(b2) MCP budget_tokens: the same held=\"budget\" tag, no verb body"
else no "(b2) MCP budget_tokens: held=[$( attr "$TMP/b2.xml" held )]"; fi

# S1: the MCP callers block is JSON in CDATA (not XML-escaped), dialect="json"
mcp_call "callers of leaf_sink" >"$TMP/x2.xml"
python3 - "$TMP/x2.xml" <<'PY'
import re, sys, json
s = open( sys.argv[1], encoding="utf8" ).read()
m = re.search( r'<graph_verb ([^>]*dialect="json"[^>]*)>(<!\[CDATA\[.*\]\]>)</graph_verb></ctx>$', s, re.S )
if not m or "&quot;" in s[ s.index( "<graph_verb" ): ]: sys.exit( 1 )
body = m.group( 2 )[ 9:-3 ].replace( "]]]]><![CDATA[>", "]]>" )
json.loads( body )
PY
x2rc=$?
if [ "$x2rc" = 0 ] && xmlok "$TMP/x2.xml"
then ok "(x2) MCP callers: dialect=\"json\", CDATA body parses as JSON, no &quot;, well-formed"
else no "(x2) MCP callers block is not CDATA JSON: $( grep -o '<graph_verb [^>]*>' "$TMP/x2.xml" | head -c 300 )"; fi

# S5: a by-name hop into a test file is disclosed; the same hop into a source file is not
mkdir -p "$FX/ts/src" "$FX/ts/tests"
cat > "$FX/ts/src/real.ts" <<'TS'
export function endOne() {}
export function endTwo() {}
export function startOne(thing: any) { thing.make(); }
export function startTwo(thing: any) { thing.build(); }
export class Real { build() { endTwo(); } }
TS
cat > "$FX/ts/tests/fake.test.ts" <<'TS'
import { endOne } from "../src/real";
export class Fake { make() { endOne(); } }
TS
run --for="path from startOne to endOne" >"$TMP/h1.xml"
if [ "$( attr "$TMP/h1.xml" name_test_hops )" = "1" ] && grep -q 'via="name"' "$TMP/h1.xml" && xmlok "$TMP/h1.xml"
then ok "(h1) a by-name hop into tests/fake.test.ts: name_test_hops=1"
else no "(h1) name_test_hops=[$( attr "$TMP/h1.xml" name_test_hops )] $( facts "$TMP/h1.xml" )"; fi
mcp_call "path from startOne to endOne" >"$TMP/h3.xml"
if [ "$( attr "$TMP/h3.xml" name_test_hops )" = "1" ]; then ok "(h3) MCP for: the same name_test_hops=1"; else no "(h3) MCP name_test_hops=[$( attr "$TMP/h3.xml" name_test_hops )]"; fi
# CR 4396503866 (train 40): the CLI block reads name_test_hops= off the verb's rows under EVERY legend, as the MCP twin does
run --for="path from startOne to endOne" --legend=full >"$TMP/h4.xml"
if [ "$( attr "$TMP/h4.xml" name_test_hops )" = "1" ] && grep -q 'via="name"' "$TMP/h4.xml" && xmlok "$TMP/h4.xml"
then ok "(h4) --legend=full: the same by-name hop into a test file still says name_test_hops=1"
else no "(h4) --legend=full name_test_hops=[$( attr "$TMP/h4.xml" name_test_hops )] $( facts "$TMP/h4.xml" )"; fi
run --for="path from startTwo to endTwo" >"$TMP/h2.xml"
if [ "$( attr "$TMP/h2.xml" name_test_hops )" = "-" ] && grep -q 'via="name"' "$TMP/h2.xml" && grep -q '<graph_verb ' "$TMP/h2.xml"
then ok "(h2) the same shape through a source file: no name_test_hops"
else no "(h2) name_test_hops=[$( attr "$TMP/h2.xml" name_test_hops )] $( facts "$TMP/h2.xml" )"; fi

run --for="path from startEntry to leaf_sink" --json >"$TMP/j1.json"
if [ -s "$TMP/j1.json" ] && ! grep -q 'graph_verb' "$TMP/j1.json"; then ok "(j1) --json carries no block"; else no "(j1) --json has a block or is empty"; fi

mcp_for(){ printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"for","arguments":{"path":"%s","task":"%s"}}}\n' "$FX" "$1" \
           | ( cd "$FX" || exit 1; "$BIN" --mcp 2>/dev/null ) | python3 -c '
import sys, json
for line in sys.stdin:
    try: d = json.loads( line )
    except Exception: continue
    c = d.get( "result", {} ).get( "content" )
    if c: print( c[0].get( "text", "" ), end="" )'; }
mcp_for "path from startEntry to leaf_sink" >"$TMP/x1.xml"
cli_tag="$( grep -o '<graph_verb [^>]*>' "$TMP/p1.xml" )"; mcp_tag="$( grep -o '<graph_verb [^>]*>' "$TMP/x1.xml" )"
if [ -n "$cli_tag" ] && [ "$cli_tag" = "$mcp_tag" ] && grep -q '<path [^>]*from="startEntry" to="leaf_sink"[^>]* reachable="1" hops="2"' "$TMP/x1.xml" \
   && [ "$( facts "$TMP/x1.xml" | sed 's/.* tail=/tail=/' )" = "tail=1 legdash=0" ]
then ok "(x1) MCP for: the same <graph_verb> tag and the path answer, before </ctx>"
else no "(x1) MCP for: cli=[$cli_tag] mcp=[$mcp_tag] $( facts "$TMP/x1.xml" )"; fi

[ "$fail" -eq 0 ] && echo "forroutecheck: PASS" || echo "forroutecheck: FAIL"
exit "$fail"
