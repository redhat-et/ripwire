#!/usr/bin/env bash
# fordocbodycheck.sh — FOR-DOC-BODY (src/fordocbody.h): a prose --for task whose first file-tail <t> rows hold 2+ doc files carries
# the top-ranked sections of the first 3 doc files the answer shows, in <doc_body> just before </ctx>; the answer before it is unchanged.
#
# ARMS (fixtures built at runtime: docfx = 45 code files + 34 doc files; onedoc = 44 code files + 1 doc in the tail's first rows)
#   (f1) fires: <doc_body> with its own legend, a b t="section" per served section (p= l= e= n= rank= of=), the section text inside it
#   (f2) the runaway allowance: a section larger than the allowance is cut="1", the root says capped="1", dropped= and next= the recall call
#   (f3) answer minus block == the RIPWIRE_NO_FOR_DOC_BODY=1 answer, byte for byte; the switched-off answer has no block
#   (f4) the answer is well formed XML and the block's comment holds no double hyphen; the block is the last element before </ctx>
#   (f5) a task that does not ask for doc text prints its tail code rows first: the rule reads the t files in rank order, so it fires
#   (n1) positive twin, code only: the same prose task on the fixture's code alone never fires
#   (n2) positive twin, one doc: a prose task on a repo with ONE doc file (row 5 of the tail) never fires;
#        (n2b) the same repo with a second doc in the first 10 tail rows fires (the threshold, not the repo, decides)
#   (n3) a code-cued task (snake_case word, a backtick span, a dotted call, camelCase) never fires on the doc fixture
#   (h1) --token-budget holds the block: held="budget", f p= per file, next= the same --for call, no section text
#   (j1) --json carries a "doc_body" key with the same passages (valid JSON); (j2) --json under a token budget: held
#   (x1) MCP `for`: the block with its legend and section rows (its own rows pick its files); (x2) MCP budget_tokens: held
#   (m1) the honesty marker: the legend holds the decoy sentence (a lexical match, not a verified answer) and the root says match="lexical"
#        in XML, --json (also "pick") and MCP; (m2) the root prices the block alone: est_tokens= (XML), "est_tokens" (JSON)
#   (r1) rank order is pinned: in every file the ranks are distinct and <= of=, and the Retry policy section of docs/retries.md is rank 1
#   (b1) a budget that fits the answer AND the block serves the sections (no held=); (b2) a budget between serves what fits and holds the
#        rest: held="budget" held_bytes=, f p= why="budget", est_tokens of the block <= the budget left after the answer; (b3) --max-tokens
#        with --detail the same; (b4) --json and (b5) MCP budget_tokens the same; (b6) a budget the answer already spent holds the block whole
#   (s1) a section the allowance cannot take whole is not dropped: skip-and-try-next, and the first that does not fit is an excerpt
#        around the task's words (cut="1" range=S-E/N), the allowance mostly used
#   (s4) the cue-list claim: handle_upload_3, MAX_RETRIES, __init__, HTTPServer and getX read as prose and fire, as the legend says
#   (e1) hostile doc text (]]> C0 bytes, an XML-shaped heading, a long line, an ampersand path): XML well formed, JSON strict-valid
#   (z1) a binary that crashes or prints nothing turns every positive arm red (each run's rc and </ctx> are checked)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "fordocbodycheck: BIN=$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
unset RIPWIRE_NO_FOR_DOC_BODY

# ── fixtures ───────────────────────────────────────────────────────────────────────────────────────────────────────
DFX="$TMP/docfx"; mkdir -p "$DFX/src" "$DFX/docs"
for i in $( seq 1 45 ); do printf 'def handle_upload_%s(path):\n    """Upload one file and retry."""\n    return path\n' "$i" >"$DFX/src/mod$i.py"; done
{
  printf '# Retries\n\nUploads that fail are retried.\n\n## Retry policy\n\n'
  printf 'The retry policy backs off exponentially: the first retry waits one second, and each later retry doubles the wait.\n'
  for i in $( seq 1 160 ); do printf 'Attempt %s of the retry policy waits for the backoff before the upload starts again.\n' "$i"; done
  printf '\n## Giving up\n\nAfter the last attempt the job stops.\n'
} >"$DFX/docs/retries.md"
printf '# Uploads\n\n## Upload limits\n\nAn upload may be at most one gigabyte.\n\n## Retry on failure\n\nFailed uploads follow the retry policy described in retries.\n' >"$DFX/docs/uploads.md"
printf '# Logging\n\n## Log levels\n\nRetry attempts are logged at the warning level.\n' >"$DFX/docs/logging.md"
printf '# Demo\n\nA demo uploader. See the docs for the retry policy.\n' >"$DFX/README.md"
for i in $( seq 1 30 ); do printf '# Guide %s\n\n## Retry policy for uploads in area %s\n\nUploads in area %s retry with backoff.\n' "$i" "$i" "$i" >"$DFX/docs/guide$i.md"; done
CFX="$TMP/codefx"; mkdir -p "$CFX"; cp -R "$DFX/src" "$CFX/"
OFX="$TMP/onedoc"; mkdir -p "$OFX/src" "$OFX/docs"
for i in $( seq 1 44 ); do printf 'def retry_policy_for_failed_uploads_%s(path):\n    """The retry policy for failed uploads."""\n    return path\n' "$i" >"$OFX/src/m$i.py"; done
printf '# Retries\n\n## Retry policy\n\nThe retry policy backs off exponentially.\n' >"$OFX/docs/retries.md"
TFX="$TMP/twodoc"; cp -R "$OFX" "$TFX"; cp "$DFX/docs/uploads.md" "$TFX/docs/"

TASK="how do the docs describe the retry policy for failed uploads"
run(){ local fx="$1"; shift; ( cd "$fx" || exit 1; "$BIN" "$fx" --no-cache "$@" 2>/dev/null </dev/null ); }
# an answer: rc 0 and a closed root, else the arm is red (z1)
ans(){ local out="$1" fx="$2"; shift 2; run "$fx" "$@" >"$out"; local rc=$?; [ "$rc" = 0 ] && [ -s "$out" ] && grep -q '</ctx>$' "$out"; }
block(){ python3 -c 'import sys; s=open(sys.argv[1],encoding="utf8").read(); i=s.find("<!-- ripwire for doc_body"); j=s.find("</doc_body>",i); print(s[i:j+11].replace("\n"," ") if i>=0 and j>=0 else "")' "$1"; }
tailrows(){ python3 -c 'import re,sys; print(" ".join(re.findall(r"<t p=\"([^\"]+)\"", open(sys.argv[1]).read())[:10]))' "$1"; }

# (f1) fires
if ans "$TMP/f1.xml" "$DFX" "--for=$TASK" && python3 - "$TMP/f1.xml" <<'PY'
import re, sys
s = open( sys.argv[1], encoding="utf8" ).read()
i = s.index( "<!-- ripwire for doc_body:" ); b = s[ i: ]
assert re.search( r'<doc_body match="lexical" est_tokens="\d+" files="3" allowance="7500" bytes="\d+"', b ), "root"
secs = re.findall( r'<b t="section" p="([^"]+)" l="(\d+)" e="(\d+)" n="([^"]*)" rank="(\d+)" of="(\d+)"[^>]*><!\[CDATA\[(.*?)\]\]></b>', b, re.S )
assert secs, "no section rows"
pol = [ x for x in secs if x[0] == "docs/retries.md" and x[3] == "Retry policy" ]
assert pol and pol[0][1] == "5" and "backs off exponentially" in pol[0][6], "the Retry policy section of docs/retries.md, line 5, with its text"
assert any( x[0] == "docs/uploads.md" for x in secs ), "a second doc file"
assert all( int( x[4] ) <= int( x[5] ) for x in secs ), "rank <= of"
PY
then ok "(f1) fires: <doc_body>, its legend, section rows with p= l= e= n= rank= of= and the section text"; else no "(f1) fires: $( block "$TMP/f1.xml" | head -c 400 )"; fi

# (f2) the allowance cut
if [ -s "$TMP/f1.xml" ] && block "$TMP/f1.xml" | grep -q '<doc_body [^>]*next="--recall=&apos;how do the docs describe the retry policy for failed uploads&apos;" capped="1">' \
   && block "$TMP/f1.xml" | grep -q '<b t="section" p="docs/retries.md" l="5" e="[0-9]*" n="Retry policy" rank="[0-9]*" of="[0-9]*" cut="1" range="[0-9]*-[0-9]*/[0-9]*">'
then ok "(f2) a section over the allowance is cut=\"1\"; the root says capped=\"1\" and next= the recall call"; else no "(f2) allowance: $( block "$TMP/f1.xml" | grep -o '<doc_body [^>]*>' )"; fi

# (f3) additivity against the switched-off answer
RIPWIRE_NO_FOR_DOC_BODY=1 ans "$TMP/f3.xml" "$DFX" "--for=$TASK"; f3rc=$?
if [ "$f3rc" = 0 ] && [ -s "$TMP/f1.xml" ] && ! grep -q 'doc_body' "$TMP/f3.xml" && python3 - "$TMP/f1.xml" "$TMP/f3.xml" <<'PY'
import sys
a = open( sys.argv[1], encoding="utf8" ).read(); b = open( sys.argv[2], encoding="utf8" ).read()
i = a.index( "<!-- ripwire for doc_body:" ); j = a.index( "</doc_body>" ) + len( "</doc_body>" )
assert a[ :i ] + a[ j: ] == b
PY
then ok "(f3) the answer minus the block is byte-identical to the RIPWIRE_NO_FOR_DOC_BODY=1 answer"; else no "(f3) the answer before/after the block moved"; fi

# (f4) well formed; no double hyphen in the comment; last before </ctx>
if [ -s "$TMP/f1.xml" ] && python3 - "$TMP/f1.xml" <<'PY' 2>/dev/null
import sys, xml.dom.minidom as M
s = open( sys.argv[1], encoding="utf8" ).read()
M.parseString( s )
i = s.index( "<!-- ripwire for doc_body:" )
assert "--" not in s[ i + 4: s.index( "-->", i ) ]
assert s.endswith( "</doc_body></ctx>" )
PY
then ok "(f4) well formed XML; the comment holds no double hyphen; the block closes right before </ctx>"; else no "(f4) well-formedness or placement"; fi

# (f5) a code-first tail (a task that does not ask for doc text prints its code t rows first): the trigger reads the t files in rank order
if ans "$TMP/f5.xml" "$DFX" "--for=what is the retry policy for failed uploads" && grep -q 'code files first' "$TMP/f5.xml" \
   && ! tailrows "$TMP/f5.xml" | grep -q '\.md' && grep -q '<doc_body match="lexical" est_tokens="[0-9]*" files="3" allowance="7500"' "$TMP/f5.xml"
then ok "(f5) a code-first tail with no doc in its first 10 printed rows still fires (the rule reads rank order)"; else no "(f5) code-first tail: $( tailrows "$TMP/f5.xml" )"; fi

# (n1) code only
if ans "$TMP/n1.xml" "$CFX" "--for=$TASK" && ! grep -q 'doc_body' "$TMP/n1.xml"; then ok "(n1) code-only repo, prose task: silent"; else no "(n1) code only must be silent (or the run failed)"; fi

# (n2) one doc in the tail's first rows: silent; (n2b) a second doc there: fires
if ans "$TMP/n2.xml" "$OFX" "--for=$TASK" && tailrows "$TMP/n2.xml" | grep -q 'docs/retries.md' && ! grep -q 'doc_body' "$TMP/n2.xml"
then ok "(n2) one doc file, inside the first 10 t rows ($( tailrows "$TMP/n2.xml" | tr ' ' '\n' | grep -n 'docs/' | cut -d: -f1 | tr '\n' ' ')): silent"
else no "(n2) one doc file must be silent and sit in the tail's first rows: $( tailrows "$TMP/n2.xml" )"; fi
if ans "$TMP/n2b.xml" "$TFX" "--for=$TASK" && grep -q '<doc_body [^>]*files="2"' "$TMP/n2b.xml"; then ok "(n2b) the same repo with two docs in the first t rows fires (files=\"2\")"; else no "(n2b) two docs must fire"; fi

# (n3) code-cued tasks
for q in "how do the docs describe handle_upload retries" 'how do the docs describe `retry` for failed uploads' "how do the docs describe uploader.retry( for failed uploads" "how do the docs describe retryPolicy for failed uploads"; do
    if ans "$TMP/n3.xml" "$DFX" "--for=$q" && ! grep -q 'doc_body' "$TMP/n3.xml"; then ok "(n3) code-cued task silent: $q"; else no "(n3) code-cued task must be silent: $q"; fi
done

# (h1) token budget: held
if ans "$TMP/h1.xml" "$DFX" "--for=$TASK" --token-budget=4000 \
   && grep -q '<doc_body match="lexical" held="budget" files="3" next="--for=&apos;how do the docs describe the retry policy for failed uploads&apos;"><f p="[^"]*"/><f p="[^"]*"/><f p="[^"]*"/></doc_body></ctx>$' "$TMP/h1.xml" \
   && ! grep -q '<b t="section"' "$TMP/h1.xml"
then ok "(h1) --token-budget below the answer holds the block: held=\"budget\", three f p= rows, next= the same call, no section text"; else no "(h1) held: $( grep -o '<doc_body.*' "$TMP/h1.xml" | head -c 300 )"; fi

# (j1) / (j2) JSON
run "$DFX" "--for=$TASK" --json >"$TMP/j1.json"; j1rc=$?
if [ "$j1rc" = 0 ] && [ -s "$TMP/f1.xml" ] && python3 - "$TMP/j1.json" "$TMP/f1.xml" <<'PY'
import json, re, sys, html
d = json.load( open( sys.argv[1], encoding="utf8" ) )["doc_body"]
x = open( sys.argv[2], encoding="utf8" ).read()
xs = [ ( html.unescape( p ), int( l ), html.unescape( n ) ) for p, l, n in re.findall( r'<b t="section" p="([^"]+)" l="(\d+)" e="\d+" n="([^"]*)"', x ) ]
js = [ ( p["p"], p["l"], p["n"] ) for p in d["passages"] if p["t"] == "section" ]
assert d["in_est_tokens"] is False and d["capped"] is True and d["next"].startswith( "--recall=" )
assert xs == js, ( xs, js )
PY
then ok "(j1) --json: a doc_body key with the XML block's passages, capped and next="; else no "(j1) --json doc_body"; fi
run "$DFX" "--for=$TASK" --json --token-budget=4000 >"$TMP/j2.json"; j2rc=$?
if [ "$j2rc" = 0 ] && python3 -c 'import json,sys; d=json.load(open(sys.argv[1]))["doc_body"]; assert d["held"]=="budget" and d["match"]=="lexical" and "passages" not in d and len(d["files"])==3' "$TMP/j2.json" 2>/dev/null
then ok "(j2) --json under a token budget: held, files named, no passages"; else no "(j2) --json held"; fi

# (x1) / (x2) MCP
mcp(){ local args="$1"; printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"for","arguments":{"path":"%s","task":"%s"%s}}}\n' "$DFX" "$TASK" "$args" \
  | ( cd "$DFX" || exit 1; "$BIN" --mcp 2>/dev/null ) | python3 -c '
import json, sys
for line in sys.stdin:
    d = json.loads( line )
    if d.get( "id" ) == 1:
        print( d["result"]["content"][0]["text"], end="" )
'; }
mcp "" >"$TMP/x1.xml"
# the MCP answer prints its own rows (no inline bodies), so its first doc files may differ: the element's shape is what is shared
if grep -q '<!-- ripwire for doc_body: ' "$TMP/x1.xml" && grep -q '<doc_body match="lexical" est_tokens="[0-9]*" files="3" allowance="7500" bytes="[0-9]*"' "$TMP/x1.xml" \
   && grep -q '<b t="section" p="docs/[a-z]*\.md" l="[0-9]*" e="[0-9]*" n="[^"]*" rank="[0-9]*" of="[0-9]*"' "$TMP/x1.xml" && grep -q '</doc_body></ctx>$' "$TMP/x1.xml"
then ok "(x1) MCP for: the block, its legend and section rows, last before </ctx>"; else no "(x1) MCP: $( grep -o '<doc_body[^>]*>' "$TMP/x1.xml" | head -c 300 )"; fi
mcp ',"budget_tokens":4000' >"$TMP/x2.xml"
if grep -q '<doc_body match="lexical" held="budget" files="3"' "$TMP/x2.xml" && ! grep -q '<b t="section"' "$TMP/x2.xml"; then ok "(x2) MCP budget_tokens: held"; else no "(x2) MCP held: $( grep -o '<doc_body.*' "$TMP/x2.xml" | head -c 300 )"; fi


# ── honesty marker, price, rank order ─────────────────────────────────────────────────────────────────────────────
# (m1) the decoy disclosure is pinned in every dialect: the legend sentence, match="lexical" on the root, "pick"/"match" in JSON
mcp "" >"$TMP/m1.xml" 2>/dev/null
SENT="It is a lexical match, not a verified answer: a section that shares the task's words and answers another question can rank first"
if [ -s "$TMP/f1.xml" ] && [ -s "$TMP/j1.json" ] && grep -q "$SENT" "$TMP/f1.xml" && grep -q '<doc_body match="lexical" ' "$TMP/f1.xml" \
   && grep -q "$SENT" "$TMP/m1.xml" && grep -q '<doc_body match="lexical" ' "$TMP/m1.xml" \
   && python3 -c 'import json,sys; d=json.load(open(sys.argv[1]))["doc_body"]; assert d["match"]=="lexical" and "a lexical match, not a verified answer" in d["pick"]' "$TMP/j1.json" 2>/dev/null
then ok "(m1) the lexical-match sentence is in the XML and MCP legend and the JSON pick; match=\"lexical\" on every root"; else no "(m1) honesty marker missing"; fi

# (m2) the root prices the block alone: markup at the markup rate, section text at the body rate (within a few tokens)
if [ -s "$TMP/f1.xml" ] && python3 - "$TMP/f1.xml" <<'PY'
import re, sys
s = open( sys.argv[1], encoding="utf8" ).read()
i = s.index( "<!-- ripwire for doc_body:" ); b = s[ i: s.index( "</doc_body>", i ) + 11 ]
est = int( re.search( r'<doc_body match="lexical" est_tokens="(\d+)"', b ).group(1) )
text = sum( len( t.encode() ) for t in re.findall( r'<!\[CDATA\[(.*?)\]\]></b>', b, re.S ) )
want = round( ( len( b.encode() ) - text ) / 2.5 ) + round( text / 3.8 )
assert abs( est - want ) <= 4 + want // 50, ( est, want )
assert est > 500
PY
then ok "(m2) the block root carries est_tokens= pricing the block alone (markup 2.5 B per token, text 3.8)"; else no "(m2) block price"; fi

# (r1) rank order is pinned
if [ -s "$TMP/f1.xml" ] && python3 - "$TMP/f1.xml" <<'PY'
import re, sys, collections
s = open( sys.argv[1], encoding="utf8" ).read()
rows = re.findall( r'<b t="section" p="([^"]+)" l="\d+" e="\d+" n="([^"]*)" rank="(\d+)" of="(\d+)"', s )
by = collections.defaultdict( list )
for p, n, r, of in rows:
    by[p].append( ( n, int( r ), int( of ) ) )
for p, v in by.items():
    ranks = [ r for _, r, _ in v ]
    assert len( set( ranks ) ) == len( ranks ) and all( 1 <= r <= of for _, r, of in v ), ( p, v )
top = [ r for n, r, of in by["docs/retries.md"] if n == "Retry policy" ]
assert top == [1], top
PY
then ok "(r1) per file the ranks are distinct and within of=; the Retry policy section of docs/retries.md is rank 1"; else no "(r1) rank order"; fi

# ── budgets ───────────────────────────────────────────────────────────────────────────────────────────────────────
estof(){ python3 -c 'import re,sys; m=re.search(r"est_tokens=\"(\d+)\"", open(sys.argv[1],encoding="utf8").read()); print(m.group(1) if m else 0)' "$1"; }
# invariant checker: the block (when served) prices at most the budget left after the answer
chk_fit(){ python3 - "$1" "$2" <<'PY'
import re, sys
s = open( sys.argv[1], encoding="utf8" ).read(); budget = int( sys.argv[2] )
ans = int( re.search( r'est_tokens="(\d+)"', s ).group(1) )
m = re.search( r'<doc_body match="lexical" est_tokens="(\d+)"', s )
if m:
    assert int( m.group(1) ) <= max( 0, budget - ans ), ( "block over the budget left", m.group(1), budget, ans )
PY
}
nsec(){ grep -o '<b t="section"' "$1" | wc -l | tr -d ' '; }
# (b1) a budget that holds the answer and the block: served, not held
if ans "$TMP/b1.xml" "$DFX" "--for=$TASK" --token-budget=100000 && chk_fit "$TMP/b1.xml" 100000 && ! grep -q '<doc_body [^>]*held="budget"' "$TMP/b1.xml" && [ "$( nsec "$TMP/b1.xml" )" -ge 3 ]; then
  ok "(b1) --token-budget=100000 serves the sections ($( nsec "$TMP/b1.xml" ) of them), no held=, the block fits what the answer left"
else no "(b1) a budget that fits must serve: $( grep -o '<doc_body[^>]*>' "$TMP/b1.xml" | head -c 300 )"; fi
# (b2) a budget between: the answer first, what fits served, the rest held and named; every budget keeps the fit invariant
partial=0; full=0; allfit=1
for B in 5000 5400 5800 6200 6600 7000 7600 8400; do
  if ans "$TMP/b2.xml" "$DFX" "--for=$TASK" --token-budget=$B && chk_fit "$TMP/b2.xml" $B; then
    if grep -q '<doc_body match="lexical" est_tokens="[0-9]*" files="3" allowance="[0-9]*" bytes="[0-9]*" held="budget" held_bytes="[1-9][0-9]*"' "$TMP/b2.xml" && [ "$( nsec "$TMP/b2.xml" )" -ge 1 ] \
       && grep -q ' next="--for=&apos;' "$TMP/b2.xml"; then partial=1; fi
    grep -q '<doc_body match="lexical" est_tokens' "$TMP/b2.xml" && ! grep -q '<doc_body [^>]*held="budget"' "$TMP/b2.xml" && full=1
  else allfit=0; fi
done
if [ "$partial" = 1 ] && [ "$allfit" = 1 ]; then ok "(b2) a budget between serves what fits and holds the rest (held=\"budget\" held_bytes= next=); the block never exceeds the budget left"; else no "(b2) partial serve under a budget (partial=$partial allfit=$allfit)"; fi
# (b3) --max-tokens with --detail is a budget too: served when it holds the answer + block, held whole when the answer alone spends it
if ans "$TMP/b3a.xml" "$DFX" "--for=$TASK" --max-tokens=100000 --detail=1 && grep -q '<doc_body match="lexical" est_tokens' "$TMP/b3a.xml" && ! grep -q '<doc_body [^>]*held="budget"' "$TMP/b3a.xml" && [ "$( nsec "$TMP/b3a.xml" )" -ge 1 ] \
   && ans "$TMP/b3b.xml" "$DFX" "--for=$TASK" --max-tokens=300 --detail=1 && grep -q '<doc_body match="lexical" held="budget" files="3"' "$TMP/b3b.xml" && [ "$( nsec "$TMP/b3b.xml" )" = 0 ]
then ok "(b3) --max-tokens --detail: 100000 serves the sections, 300 holds the block whole"; else no "(b3) max-tokens with detail"; fi
# (b4) --json: the same rules; (b5) MCP budget_tokens
run "$DFX" "--for=$TASK" --json --token-budget=100000 >"$TMP/b4.json"; b4rc=$?
if [ "$b4rc" = 0 ] && python3 - "$TMP/b4.json" <<'PY'
import json, sys
d = json.load( open( sys.argv[1], encoding="utf8" ) ); b = d["doc_body"]
assert "held" not in b and b["match"] == "lexical" and len( b["passages"] ) >= 3 and b["est_tokens"] <= d["budget_tokens"] - d["est_tokens"], b.keys()
PY
then ok "(b4) --json --token-budget=100000 serves the passages, priced within the budget left"; else no "(b4) --json under a big budget"; fi
pj=0; fj=1
for B in 5000 5600 6200 6800 7400 8200; do
  run "$DFX" "--for=$TASK" --json --token-budget=$B >"$TMP/b4p.json"
  python3 - "$TMP/b4p.json" $B <<'PY' && pj=1
import json, sys
d = json.load( open( sys.argv[1], encoding="utf8" ) ); b = d["doc_body"]; B = int( sys.argv[2] )
if "passages" in b:
    assert b["est_tokens"] <= max( 0, B - d["est_tokens"] ), "block over the budget left"
sys.exit( 0 if ( b.get( "held" ) == "budget" and b.get( "passages" ) and b["held_bytes"] > 0 and b["next"].startswith( "--for=" ) ) else 3 )
PY
done
[ "$pj" = 1 ] && ok "(b4b) --json under a middle budget: passages served and held=\"budget\" held_bytes= next=" || no "(b4b) --json partial serve"
mcp ',"budget_tokens":100000' >"$TMP/b5.xml"
if grep -q '<doc_body match="lexical" est_tokens' "$TMP/b5.xml" && ! grep -q '<doc_body [^>]*held="budget"' "$TMP/b5.xml" && [ "$( nsec "$TMP/b5.xml" )" -ge 1 ] && chk_fit "$TMP/b5.xml" 100000
then ok "(b5) MCP budget_tokens=100000 serves the sections"; else no "(b5) MCP big budget: $( grep -o '<doc_body[^>]*>' "$TMP/b5.xml" | head -c 300 )"; fi

# ── (s1) skip a misfit; an oversized section is an excerpt around the task's words ───────────────────────────────
LFX="$TMP/llfx"; cp -R "$DFX" "$LFX"
python3 - "$LFX" <<'PY'
import sys
r = sys.argv[1]
filler = "lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor "
big = filler * 600 + "here the retry policy for failed uploads is described in one sentence " + filler * 600
open( r + "/docs/a.md", "w" ).write( "# Notes\n\n## Backoff schedule\n\nThe backoff schedule doubles the wait on every retry policy for failed uploads.\n\n## Everything else\n\n" + big + "\n" )
PY
if ans "$TMP/s1.xml" "$LFX" "--for=$TASK" && python3 - "$TMP/s1.xml" <<'PY'
import re, sys
s = open( sys.argv[1], encoding="utf8" ).read()
b = s[ s.index( "<!-- ripwire for doc_body:" ): ]
root = re.search( r'<doc_body [^>]*>', b ).group(0)
assert int( re.search( r'bytes="(\d+)"', root ).group(1) ) >= 5000, ( "most of the allowance is used", root )
big = re.search( r'<b t="section" p="docs/a.md"[^>]*n="Everything else"[^>]*cut="1" range="(\d+)-(\d+)/(\d+)"[^>]*><!\[CDATA\[(.*?)\]\]></b>', b, re.S )
assert big, "the oversized section is an excerpt, not dropped"
lo, hi, n, text = int( big.group(1) ), int( big.group(2) ), int( big.group(3) ), big.group(4)
assert lo > 1000 and hi < n and hi > lo and "retry policy for failed uploads is described" in text, ( lo, hi, n )
assert hi - lo > 4000, "the excerpt takes the unspent allowance"
assert 'n="Backoff schedule"' in b, "the small section is still served"
PY
then ok "(s1) a section over the allowance is a cut=\"1\" range= excerpt around the task's words, the small one is served too, most of the allowance used"; else no "(s1) oversized section: $( block "$TMP/s1.xml" | grep -o '<doc_body [^>]*>' )"; fi

# ── (s4) the legend's cue-list claim ──────────────────────────────────────────────────────────────────────────────
D4="$TMP/d4"; cp -R "$DFX" "$D4"; rm "$D4"/src/*.py; for i in $( seq 1 45 ); do printf 'def work_%s(path):\n    return path\n' "$i" >"$D4/src/m$i.py"; done
s4=1
for q in handle_upload_3 MAX_RETRIES __init__ HTTPServer getX; do
  if ans "$TMP/s4.xml" "$D4" "--for=how do the docs describe the retry policy of $q for failed uploads" && grep -q '<doc_body match="lexical"' "$TMP/s4.xml"; then :; else s4=0; echo "    (s4) did not fire: $q"; fi
done
if [ "$s4" = 1 ] && grep -q 'so handle_upload_3, MAX_RETRIES, __init__, HTTPServer and getX read as prose' "$TMP/s4.xml"; then ok "(s4) the five code-shaped words the legend names read as prose and fire, as the legend says"; else no "(s4) cue-list claim"; fi

# ── (e1) hostile doc text ─────────────────────────────────────────────────────────────────────────────────────────
HFX="$TMP/hostile"; cp -R "$DFX" "$HFX"
python3 - "$HFX" <<'PY'
import os, sys
r = sys.argv[1]
os.rename( r + "/docs/retries.md", r + "/docs/retries&more.md" )
w = open( r + "/docs/retries&more.md", "ab" )
w.write( "\n## Retry policy <b>&amp; \"q\" -- ]]> x\n\nThe retry policy has ]]> inside, control \x01\x02\x1b\x0b bytes, an <tag attr=\"v\"> and & ampersands.\n\n".encode( "latin-1" ) + b"\xff bad utf8\n\n## Long retry notes\n\n" + b"retry policy backoff wait " * 3000 + b"\n" )
w.close()
PY
if ans "$TMP/e1.xml" "$HFX" "--for=$TASK" && grep -q '<doc_body match="lexical"' "$TMP/e1.xml" && python3 - "$TMP/e1.xml" <<'PY'
import re, sys, xml.dom.minidom as M
s = open( sys.argv[1], encoding="utf8", errors="strict" ).read()
M.parseString( s )
assert not re.search( "[\x00-\x08\x0b\x0c\x0e-\x1f]", s ), "a C0 control byte reached the output"
assert "]]]]><![CDATA[>" in s, "the CDATA terminator inside the text is split"
assert 'n="Retry policy &lt;b&gt;&amp;amp; &quot;q&quot; -- ]]&gt; x"' in s, "the hostile heading is served, escaped"
assert 'p="docs/retries&amp;more.md"' in s, "the ampersand path is escaped"
PY
then ok "(e1) hostile doc text (]]>, C0 bytes, markup in a heading, a long line, an ampersand path): the XML parses and holds no control byte"; else no "(e1) hostile XML"; fi
run "$HFX" "--for=$TASK" --json >"$TMP/e1.json"; e1rc=$?
if [ "$e1rc" = 0 ] && python3 - "$TMP/e1.json" <<'PY'
import json, re, sys
raw = open( sys.argv[1], encoding="utf8" ).read()
d = json.loads( raw, strict=True )["doc_body"]
assert any( p.get( "n" ) == 'Retry policy <b>&amp; "q" -- ]]> x' for p in d["passages"] ), "the hostile heading is served"
PY
then ok "(e1j) hostile doc text: --json parses strictly and serves the hostile section"; else no "(e1j) hostile JSON"; fi


# (b2f) a budget that leaves room for only part of a file names the held sections: f p= why="budget" held=N (the hostile fixture has 5 sections in one file)
bf=0
for B in 5000 5200 5400 5600 5800; do
  if ans "$TMP/b2f.xml" "$HFX" "--for=$TASK" --token-budget=$B && chk_fit "$TMP/b2f.xml" $B && grep -q '<f p="docs/[^"]*" why="budget" held="[1-9][0-9]*"/>' "$TMP/b2f.xml" \
     && grep -q '<doc_body [^>]*held="budget" held_bytes=' "$TMP/b2f.xml"; then bf=1; fi
done
[ "$bf" = 1 ] && ok "(b2f) the sections a budget kept out of a file are named: f p= why=\"budget\" held=N" || no "(b2f) held sections not named"

[ "$fail" = 0 ] && echo "fordocbodycheck: PASS" || echo "fordocbodycheck: FAIL"
exit "$fail"
