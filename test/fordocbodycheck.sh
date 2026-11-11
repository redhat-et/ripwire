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
#   (p1) cost: a doc section of ONE very long line (1.3 MB) is served in a bounded time, with and without a token budget (the scan back to a
#        line start ran once per task-word hit: hits x line length, 127 s at 2.6 MB); the time limit makes a quadratic scan red
#   (b2) also: held_bytes is exact (bytes + held_bytes == the unbudgeted block's bytes) and the block's est_tokens is the price recomputed from
#        its own bytes (markup 2.5 B per token, text 3.8), not the binary's word: the held-whole block is priced the same way (h2)
#   (q1) the relevance floor: a section holding fewer of the task's subject words than a third of them (3 at most) is left out unless it is its
#        file's top-ranked section, below_floor= counts them and every other section served holds enough; the section that holds them is served
#        (positive twin); (q2) a file's top-ranked section is served even when it holds none of them (the held-2 row mdref-02's shape)
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
# the FILE tail rows (<t p="FILE"/>, <t p="FILE" sym="NAME"/>); a SIBLING-DEMOTE pointer in <sigs> (<t p= sym= r=/>, forsiblingdemote.h)
# carries its rank r= — a demoted ranked row, not a tail row
tailrows(){ python3 -c 'import re,sys; print(" ".join(re.findall(r"<t p=\"([^\"]+)\"(?: sym=\"[^\"]*\")?/>", open(sys.argv[1]).read())[:10]))' "$1"; }

# (f1) fires
if ans "$TMP/f1.xml" "$DFX" "--for=$TASK" && python3 - "$TMP/f1.xml" <<'PY'
import re, sys
s = open( sys.argv[1], encoding="utf8" ).read()
i = s.index( "<!-- ripwire for doc_body:" ); b = s[ i: ]
assert re.search( r'<doc_body match="lexical" est_tokens="\d+" files="3" allowance="7500" bytes="\d+"', b ), "root"
secs = re.findall( r'<b t="section" p="([^"]+)" l="(\d+)" e="(\d+)" n="([^"]*)" rank="(\d+)" of="(\d+)"[^>]*><!\[CDATA\[(.*?)\]\]></b>', b, re.S )
assert secs, "no section rows"
pol = [ x for x in secs if x[0] == "docs/retries.md" and x[3] == "Retry policy" ]
assert pol and int( pol[0][1] ) >= 5 and "backs off exponentially" in pol[0][6], "the Retry policy section of docs/retries.md, from line 5, with its text"
assert any( x[0] == "docs/uploads.md" for x in secs ), "a second doc file"
assert all( int( x[4] ) <= int( x[5] ) for x in secs ), "rank <= of"
PY
then ok "(f1) fires: <doc_body>, its legend, section rows with p= l= e= n= rank= of= and the section text"; else no "(f1) fires: $( block "$TMP/f1.xml" | head -c 400 )"; fi

# (f2) the allowance cut
if [ -s "$TMP/f1.xml" ] && block "$TMP/f1.xml" | grep -q '<doc_body [^>]*next="--recall=&apos;how do the docs describe the retry policy for failed uploads&apos;" capped="1">' \
   && block "$TMP/f1.xml" | grep -q '<b t="section" p="docs/retries.md" l="[0-9]*" e="[0-9]*" n="Retry policy" rank="[0-9]*" of="[0-9]*" cut="1" range="[0-9]*-[0-9]*/[0-9]*">'
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
   && grep -q '<doc_body match="lexical" est_tokens="[0-9]*" held="budget" files="3" next="--for=&apos;how do the docs describe the retry policy for failed uploads&apos;"><f p="[^"]*"/><f p="[^"]*"/><f p="[^"]*"/></doc_body></ctx>$' "$TMP/h1.xml" \
   && ! grep -q '<b t="section"' "$TMP/h1.xml"
then ok "(h1) --token-budget below the answer holds the block: held=\"budget\", three f p= rows, next= the same call, no section text"; else no "(h1) held: $( grep -o '<doc_body.*' "$TMP/h1.xml" | head -c 300 )"; fi

# (j1) / (j2) JSON
run "$DFX" "--for=$TASK" --json >"$TMP/j1.json"; j1rc=$?
if [ "$j1rc" = 0 ] && [ -s "$TMP/f1.xml" ] && python3 - "$TMP/j1.json" "$TMP/f1.xml" <<'PY'
import json, re, sys, html
d = json.load( open( sys.argv[1], encoding="utf8" ) )["doc_body"]
x = open( sys.argv[2], encoding="utf8" ).read()
xs = [ ( html.unescape( p ), int( l ), html.unescape( n ), t ) for p, l, n, t in re.findall( r'<b t="section" p="([^"]+)" l="(\d+)" e="\d+" n="([^"]*)"[^>]*><!\[CDATA\[(.*?)\]\]></b>', x, re.S ) ]
js = [ ( p["p"], p["l"], p["n"], p["text"] ) for p in d["passages"] if p["t"] == "section" ]
assert d["in_est_tokens"] is False and d["capped"] is True and d["next"].startswith( "--recall=" )
assert xs and xs == js, ( "path, line, heading and text of every section", [ x[:3] for x in xs ], [ j[:3] for j in js ] )
PY
then ok "(j1) --json: a doc_body key with the XML block's passages, capped and next="; else no "(j1) --json doc_body"; fi
# R-DEDUP (2026-11-08): the head files' tail rows no longer repeat their shown headings, so the JSON answer at 4000 fell from
# est_tokens 4070 to 3632 and the doc-body allowance cleared its floor (2 capped passages served). 3500 holds the block on both.
run "$DFX" "--for=$TASK" --json --token-budget=3500 >"$TMP/j2.json"; j2rc=$?
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
if grep -q '<doc_body match="lexical" est_tokens="[0-9]*" held="budget" files="3"' "$TMP/x2.xml" && ! grep -q '<b t="section"' "$TMP/x2.xml"; then ok "(x2) MCP budget_tokens: held"; else no "(x2) MCP held: $( grep -o '<doc_body.*' "$TMP/x2.xml" | head -c 300 )"; fi


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
FULLB=$( python3 -c 'import re,sys; m=re.search(r"<doc_body [^>]* bytes=\"(\d+)\"", open(sys.argv[1],encoding="utf8").read()); print(m.group(1) if m else 0)' "$TMP/f1.xml" )
estof(){ python3 -c 'import re,sys; m=re.search(r"est_tokens=\"(\d+)\"", open(sys.argv[1],encoding="utf8").read()); print(m.group(1) if m else 0)' "$1"; }
# invariant checker: a block that prints is priced from its own bytes (markup 2.5 B per token, text 3.8: the block's word is not trusted),
# a served one fits what the answer left of the budget, and its held_bytes are exact (bytes + held_bytes == the unbudgeted block's bytes, $3)
chk_fit(){ python3 - "$1" "$2" "${3:-0}" <<'PY'
import re, sys
s = open( sys.argv[1], encoding="utf8" ).read(); budget = int( sys.argv[2] ); full = int( sys.argv[3] )
ans = int( re.search( r'est_tokens="(\d+)"', s ).group(1) )
i = s.find( "<!-- ripwire for doc_body" )
if i >= 0:
    b = s[ i: s.index( "</doc_body>", i ) + 11 ]
    est = int( re.search( r'<doc_body match="lexical" est_tokens="(\d+)"', b ).group(1) )
    text = sum( len( t.encode() ) for t in re.findall( r'<!\[CDATA\[(.*?)\]\]></b>', b, re.S ) )
    want = round( ( len( b.encode() ) - text ) / 2.5 ) + round( text / 3.8 )
    assert abs( est - want ) <= 4 + want // 50, ( "the block price is not its bytes", est, want )
    root = re.search( r'<doc_body [^>]*>', b ).group(0)
    if ' allowance="' in root:
        assert est <= max( 0, budget - ans ), ( "block over the budget left", est, budget, ans )
        h = re.search( r' held_bytes="(\d+)"', root )
        if h and full:
            assert int( re.search( r' bytes="(\d+)"', root ).group(1) ) + int( h.group(1) ) == full, ( "held_bytes is not the bytes the budget kept out", root, full )
PY
}
nsec(){ grep -o '<b t="section"' "$1" | wc -l | tr -d ' '; }
# (b1) a budget that holds the answer and the block: served, not held
if ans "$TMP/b1.xml" "$DFX" "--for=$TASK" --token-budget=100000 && chk_fit "$TMP/b1.xml" 100000 "$FULLB" && ! grep -q '<doc_body [^>]*held="budget"' "$TMP/b1.xml" && [ "$( nsec "$TMP/b1.xml" )" -ge 3 ]; then
  ok "(b1) --token-budget=100000 serves the sections ($( nsec "$TMP/b1.xml" ) of them), no held=, the block fits what the answer left"
else no "(b1) a budget that fits must serve: $( grep -o '<doc_body[^>]*>' "$TMP/b1.xml" | head -c 300 )"; fi
# (b2) a budget between: the answer first, what fits served, the rest held and named; every budget keeps the fit invariant
partial=0; full=0; allfit=1
for B in 5000 5400 5800 6200 6600 7000 7600 8400; do
  if ans "$TMP/b2.xml" "$DFX" "--for=$TASK" --token-budget=$B && [ "$FULLB" -gt 0 ] && chk_fit "$TMP/b2.xml" $B "$FULLB"; then
    if grep -q '<doc_body match="lexical" est_tokens="[0-9]*" files="3" allowance="[0-9]*" bytes="[0-9]*" held="budget" held_bytes="[1-9][0-9]*"' "$TMP/b2.xml" && [ "$( nsec "$TMP/b2.xml" )" -ge 1 ] \
       && grep -q ' next="--for=&apos;' "$TMP/b2.xml"; then partial=1; fi
    grep -q '<doc_body match="lexical" est_tokens' "$TMP/b2.xml" && ! grep -q '<doc_body [^>]*held="budget"' "$TMP/b2.xml" && full=1
  else allfit=0; fi
done
if [ "$partial" = 1 ] && [ "$allfit" = 1 ]; then ok "(b2) a budget between serves what fits and holds the rest (held=\"budget\" held_bytes= next=); the block never exceeds the budget left"; else no "(b2) partial serve under a budget (partial=$partial allfit=$allfit)"; fi
# (b3) --max-tokens with --detail is a budget too: served when it holds the answer + block, held whole when the answer alone spends it
if ans "$TMP/b3a.xml" "$DFX" "--for=$TASK" --max-tokens=100000 --detail=1 && grep -q '<doc_body match="lexical" est_tokens' "$TMP/b3a.xml" && ! grep -q '<doc_body [^>]*held="budget"' "$TMP/b3a.xml" && [ "$( nsec "$TMP/b3a.xml" )" -ge 1 ] \
   && ans "$TMP/b3b.xml" "$DFX" "--for=$TASK" --max-tokens=300 --detail=1 && grep -q '<doc_body match="lexical" est_tokens="[0-9]*" held="budget" files="3"' "$TMP/b3b.xml" && [ "$( nsec "$TMP/b3b.xml" )" = 0 ]
then ok "(b3) --max-tokens --detail: 100000 serves the sections, 300 holds the block whole"; else no "(b3) max-tokens with detail"; fi
# (b4) --json: the same rules; (b5) MCP budget_tokens
run "$DFX" "--for=$TASK" --json --token-budget=100000 >"$TMP/b4.json"; b4rc=$?
if [ "$b4rc" = 0 ] && python3 - "$TMP/b4.json" <<'PY'
import json, sys
d = json.load( open( sys.argv[1], encoding="utf8" ) ); b = d["doc_body"]
assert "held" not in b and b["match"] == "lexical" and len( b["passages"] ) >= 3 and b["est_tokens"] <= d["budget_tokens"] - d["est_tokens"], b.keys()
PY
then ok "(b4) --json --token-budget=100000 serves the passages, priced within the budget left"; else no "(b4) --json under a big budget"; fi
pj=0; fj=0
for B in 5000 5200 5400 5600 6200 6800 7400 8200; do
  run "$DFX" "--for=$TASK" --json --token-budget=$B >"$TMP/b4p.json"; b4prc=$?
  [ "$b4prc" = 0 ] || fj=1   # a crashed run is red, whatever the other budgets did
  python3 - "$TMP/b4p.json" $B "$FULLB" <<'PY'
import json, sys
d = json.load( open( sys.argv[1], encoding="utf8" ) ); b = d["doc_body"]; B = int( sys.argv[2] ); full = int( sys.argv[3] )
if "passages" in b:
    assert b["est_tokens"] <= max( 0, B - d["est_tokens"] ), "block over the budget left"
    if "held_bytes" in b:
        assert b["bytes"] + b["held_bytes"] == full, ( "held_bytes is not the bytes the budget kept out", b["bytes"], b["held_bytes"], full )
sys.exit( 0 if ( b.get( "held" ) == "budget" and b.get( "passages" ) and b["held_bytes"] > 0 and b["next"].startswith( "--for=" ) ) else 3 )
PY
  case $? in 0) pj=1 ;; 3) ;; *) fj=1 ;; esac   # 0 = a partial serve, 3 = a valid block that is not one; an invalid response (a failed invariant, bad JSON) is red
done
if [ "$pj" = 1 ] && [ "$fj" = 0 ]; then ok "(b4b) --json under a middle budget: passages served and held=\"budget\" held_bytes= next="; else no "(b4b) --json partial serve"; fi
mcp ',"budget_tokens":100000' >"$TMP/b5.xml"
if grep -q '<doc_body match="lexical" est_tokens' "$TMP/b5.xml" && ! grep -q '<doc_body [^>]*held="budget"' "$TMP/b5.xml" && [ "$( nsec "$TMP/b5.xml" )" -ge 1 ] && chk_fit "$TMP/b5.xml" 100000 "$FULLB"
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
FULLH=$( python3 -c 'import re,sys; m=re.search(r"<doc_body [^>]* bytes=\"(\d+)\"", open(sys.argv[1],encoding="utf8").read()); print(m.group(1) if m else 0)' "$TMP/e1.xml" )
for B in 5000 5200 5400 5600 5800; do
  if ans "$TMP/b2f.xml" "$HFX" "--for=$TASK" --token-budget=$B && [ "$FULLH" -gt 0 ] && chk_fit "$TMP/b2f.xml" $B "$FULLH" && grep -q '<f p="docs/[^"]*" why="budget" held="[1-9][0-9]*"/>' "$TMP/b2f.xml" \
     && grep -q '<doc_body [^>]*held="budget" held_bytes=' "$TMP/b2f.xml"; then bf=1; fi
done
if [ "$bf" = 1 ]; then ok "(b2f) the sections a budget kept out of a file are named: f p= why=\"budget\" held=N"; else no "(b2f) held sections not named"; fi

# (h2) the held-whole block states its price: est_tokens= on the root in XML (h1, x2, b3b), "est_tokens" in JSON (j2), each recomputed from the bytes
if ans "$TMP/h2x.xml" "$DFX" "--for=$TASK" --token-budget=4000 && chk_fit "$TMP/h2x.xml" 4000 && grep -q '<doc_body match="lexical" est_tokens="[1-9][0-9]*" held="budget"' "$TMP/h2x.xml" \
   && python3 - "$TMP/j2.json" <<'PY'
import json, sys
raw = open( sys.argv[1], encoding="utf8" ).read()
d = json.loads( raw )["doc_body"]
i = raw.index( '"doc_body"' ); n = len( raw[ i: raw.rindex( "}" ) ].encode() )
want = round( n / 2.5 )
assert d["held"] == "budget" and abs( d["est_tokens"] - want ) <= want * 0.15 + 4, ( d["est_tokens"], want )
PY
then ok "(h2) the held-whole block carries est_tokens, XML and JSON, matching its own bytes"; else no "(h2) held-whole block price"; fi

# (q1) the relevance floor: DFX picks README.md, docs/uploads.md and docs/retries.md; the task's subject words are retry, policy, failed, uploads (need 2)
if [ -s "$TMP/f1.xml" ] && python3 - "$TMP/f1.xml" <<'PY'
import re, sys
s = open( sys.argv[1], encoding="utf8" ).read()
b = s[ s.index( "<!-- ripwire for doc_body:" ): ]
root = re.search( r'<doc_body [^>]*>', b ).group(0)
assert int( re.search( r' below_floor="(\d+)"', root ).group(1) ) >= 1, root
rows = re.findall( r'<b t="section" p="([^"]+)"[^>]* n="([^"]*)" rank="(\d+)"[^>]*><!\[CDATA\[(.*?)\]\]></b>', b, re.S )
assert rows
for p, n, r, t in rows:
    words = set( re.findall( r"[a-z]+", ( n + " " + t ).lower() ) )
    assert r == "1" or len( words & { "retry", "policy", "failed", "uploads" } ) >= 2, ( "a served section holds too few subject words", p, n )
assert ( "docs/uploads.md", "Retry on failure" ) in [ ( p, n ) for p, n, r, t in rows ], "the on-subject section is still served"
assert "Upload limits" not in [ n for p, n, r, t in rows ], "the section with no subject word is left out (it is not rank 1)"
PY
then ok "(q1) the floor leaves out the sections with too few of the task's subject words (below_floor= counts them), serves the one that holds them"; else no "(q1) relevance floor"; fi
# (q2) a file's top-ranked section is kept even when it holds fewer subject words than the floor: README.md's one section holds only "retry"
HOFF="$TMP/halfoff"; cp -R "$DFX" "$HOFF"; printf '# Demo\n\nA demo uploader. See the docs for the retry.\n' >"$HOFF/README.md"
if ans "$TMP/q2.xml" "$HOFF" "--for=$TASK" && grep -q '<b t="section" p="README.md"[^>]* n="Demo" rank="1" of="1"' "$TMP/q2.xml" && grep -q ' below_floor="[1-9]' "$TMP/q2.xml" \
   && ! grep -q 'why="floor"' "$TMP/q2.xml"
then ok "(q2) a file's top-ranked section is served although it holds one subject word (the floor spares it); other files still lose theirs"; else no "(q2) rank-1 exemption: $( grep -o '<b t=[^>]*>' "$TMP/q2.xml" | head -c 400 )"; fi

# ── CodeRabbit round on #561 (arms c1-c10) ───────────────────────────────────────────────────────────────────────
# (c1) recentring never gives up a task word the winning window held. docs/a.md: a cluster of task words, then "uploads" 0.9 of a window later;
#      the centroid sits near the cluster, and the window centred on it ended before "uploads". The probe (the word right behind the cluster)
#      measures the window the run gets, so the arm needs no knowledge of the allowance.
RCX="$TMP/recenter"; cp -R "$DFX" "$RCX"
mkrc(){ python3 - "$RCX" "$1" <<'PY'
import sys
r, gap = sys.argv[1], int( sys.argv[2] )   # bytes of filler between the task-word cluster and the lone "uploads"
f = "quartz mica basalt shale granite "
total = len( f ) * 1800
pad = f * ( gap // len( f ) )
body = f * 100 + "retry policy failed retry policy failed. " + pad + "uploads. "
body += ( f * 1800 )[ :total - len( body ) ]   # the same length for every gap: the same allowance share
open( r + "/docs/a.md", "w" ).write( "# Notes\n\n## Backoff schedule\n\nThe backoff schedule doubles the wait on every retry policy for failed uploads.\n\n## Everything else\n\n" + body + "\n" )
PY
}
rcread(){ python3 -c '
import re, sys
s = open( sys.argv[1], encoding="utf8" ).read()
m = re.search( r"<b t=\"section\" p=\"docs/a.md\"[^>]*n=\"Everything else\"[^>]*range=\"(\d+)-(\d+)/\d+\"[^>]*><!\[CDATA\[(.*?)\]\]></b>", s, re.S )
print( ( int( m.group(2) ) - int( m.group(1) ), int( "retry policy failed" in m.group(3) and "uploads." in m.group(3) ) ) if m else "0 0" ) ' "$1" | tr -d '(),'; }
mkrc 1; c1L=0; c1p=0
if ans "$TMP/c1p.xml" "$RCX" "--for=$TASK"; then read -r c1L c1p <<<"$( rcread "$TMP/c1p.xml" )"; fi
mkrc $(( c1L * 9 / 10 ))
if [ "${c1L:-0}" -gt 1000 ] && [ "$c1p" = 1 ] && ans "$TMP/c1.xml" "$RCX" "--for=$TASK"; then read -r c1L2 c1ok <<<"$( rcread "$TMP/c1.xml" )"; else c1ok=0; fi
if [ "$c1ok" = 1 ]; then ok "(c1) the excerpt keeps every task word the winning window held (cluster + a word 0.9 of a window away; window $c1L B; probe positive twin)"; else no "(c1) recentring dropped a task word: probe window=$c1L probe-ok=$c1p"; fi

# (c2) a credential in a section heading is redacted in n= (XML and JSON), as in the section text; --no-redact leaves it (positive twin: the section is served)
TOK="ghp_""a1B2c3D4e5F6g7H8i9J0k1L2m3N4o5P6q7R8"
SEC="$TMP/secret"; cp -R "$DFX" "$SEC"
printf '\n## Retry policy token %s\n\nThe retry policy for failed uploads signs each request with this token.\n' "$TOK" >>"$SEC/docs/retries.md"
c2ok=1
ans "$TMP/c2.xml" "$SEC" "--for=$TASK" && ans "$TMP/c2n.xml" "$SEC" "--for=$TASK" --no-redact && run "$SEC" "--for=$TASK" --json >"$TMP/c2.json" || c2ok=0
python3 - "$TMP/c2.xml" "$TMP/c2n.xml" "$TMP/c2.json" "$TOK" <<'PY' || c2ok=0
import html, json, re, sys
x, xn, j = [ open( a, encoding="utf8" ).read() for a in sys.argv[1:4] ]; tok = sys.argv[4]
def heads( s ): return [ html.unescape( n ) for n in re.findall( r'<b t="section" [^>]*n="([^"]*)"', s[ s.index( "<!-- ripwire for doc_body:" ): ] ) if "token" in n ]
assert heads( xn ) == [ "Retry policy token " + tok ], ( "--no-redact: the section is served with its heading", heads( xn ) )
assert len( heads( x ) ) == 1 and tok not in x[ x.index( "<!-- ripwire for doc_body:" ): ] and "[REDACTED:github-token]" in heads( x )[0], ( "XML heading", heads( x ) )
js = [ p for p in json.loads( j )["doc_body"]["passages"] if "token" in p.get( "n", "" ) ]
assert len( js ) == 1 and tok not in js[0]["n"] and "[REDACTED:github-token]" in js[0]["n"], ( "JSON heading", js )
PY
if [ "$c2ok" = 1 ]; then ok "(c2) a credential in a served section's heading is redacted in n= in XML and JSON; --no-redact leaves it"; else no "(c2) heading redaction"; fi

# (c3) a block held whole prints no section text, so the run's redaction summary does not count the secrets its preparation read: the held
#      run reports fewer than the served run (positive twin), by the section's one secret
tally(){ local fx="$1"; shift; ( cd "$fx" || exit 1; "$BIN" "$fx" --no-cache "$@" 2>&1 >/dev/null </dev/null | grep -o 'redacted [0-9]* secret' | grep -o '[0-9]*' ); }
c3full=$( tally "$SEC" "--for=$TASK" ); c3held=""; c3any=0
for B in 4200 4300 4400; do   # the answer leaves a little room, the block does not fit it: held whole, but its sections were read
  if ans "$TMP/c3.xml" "$SEC" "--for=$TASK" --token-budget=$B && grep -q '<doc_body match="lexical" est_tokens="[0-9]*" held="budget" files="3" next=' "$TMP/c3.xml" && ! grep -q '<b t="section"' "$TMP/c3.xml"; then
    c3any=1; c3held=$( tally "$SEC" "--for=$TASK" --token-budget=$B )
    [ -n "$c3full" ] && [ -n "$c3held" ] && [ "$c3held" -lt "$c3full" ] || { c3any=0; break; }
  fi
done
if [ "$c3any" = 1 ]; then ok "(c3) a block held whole does not count the redactions of text it never prints (served run: $c3full, held run: $c3held)"; else no "(c3) held-whole redaction tally: served=${c3full:-?} held=${c3held:-?}"; fi

# (c4)/(c5) accounting under a budget, against the unbudgeted block: every on-subject section is served or counted in dropped= (also for a file
#      the allowance did not reach), and held= / held_bytes= are read off the sections by identity (file, rank), not off counts
acct(){ python3 - "$@" <<'PY'
import html, re, sys
def parse( path ):
    s = open( path, encoding="utf8" ).read()
    b = s[ s.index( "<!-- ripwire for doc_body" ): ]
    root = re.search( r'<doc_body [^>]*>', b ).group(0)
    secs = { ( html.unescape( p ), int( r ) ): len( t.encode() ) for p, r, t in re.findall( r'<b t="(?:section|doc)" p="([^"]+)"[^>]* rank="(\d+)"[^>]*><!\[CDATA\[(.*?)\]\]></b>', b, re.S ) }
    num = lambda k: int( ( re.search( r' %s="(\d+)"' % k, root ) or [ 0, 0 ] )[1] )
    held = { html.unescape( p ): int( h ) for p, h in re.findall( r'<f p="([^"]+)" why="budget" held="(\d+)"/>', b ) }
    return secs, num( "dropped" ), num( "held_bytes" ), held, "held=\"budget\"" in root
full = parse( sys.argv[1] )
units = len( full[0] ) + full[1]
served = False
for path in sys.argv[2:]:
    secs, dropped, heldBytes, held, isHeld = parse( path )
    if not secs: continue
    served = True
    assert len( secs ) + dropped == units, ( "every on-subject section is served or dropped=", path, len( secs ), dropped, units )
    missing = [ k for k in full[0] if k not in secs ]
    want = sum( full[0][k] for k in missing ) + sum( max( 0, v - secs[k] ) for k, v in full[0].items() if k in secs )
    assert heldBytes == want, ( "held_bytes is the text of the sections the budget kept out, by identity", path, heldBytes, want )
    for p in { k[0] for k in missing }:
        assert held.get( p, 0 ) == sum( 1 for k in missing if k[0] == p ), ( "held= names the sections of the file the budget kept out", path, p, held )
assert served, "no budget served a partial block"
PY
}
c4files=""
for B in 5000 5200 5400 5600 5800 6000 6400 6800 7200; do ans "$TMP/c4_$B.xml" "$DFX" "--for=$TASK" --token-budget=$B && c4files="$c4files $TMP/c4_$B.xml"; done
if ans "$TMP/c4full.xml" "$DFX" "--for=$TASK" --token-budget=100000 && [ -n "$c4files" ] && acct "$TMP/c4full.xml" $c4files; then ok "(c4/c5) under every budget in the sweep: sections served + dropped= == the unbudgeted block's; held= and held_bytes= read off the sections by identity"; else no "(c4/c5) budget accounting"; acct "$TMP/c4full.xml" $c4files 2>&1 | tail -1; fi

# (c6) only a doc file the answer shows is served: a code-first tail under a token budget ends before its doc rows, though the doc files lead the
#      rank order that fires the block. The files the block names are each a printed <t>/<d> row (XML and --json); the unbudgeted twin names them.
T6="what is the retry policy for failed uploads"
shownpaths(){ python3 - "$@" <<'PY'
import json, re, sys
kind, path = sys.argv[1], sys.argv[2]
s = open( path, encoding="utf8" ).read()
if kind == "xml":
    i = s.find( "<!-- ripwire for doc_body" ); head = s[ :i ] if i >= 0 else s
    shown = set( re.findall( r'<[td] [^>]*p="([^"]+)"', head ) ); named = set( re.findall( r'<[fb] [^>]*p="([^"]+)"', s[ i: ] ) ) if i >= 0 else set()
else:
    d = json.loads( s ); shown = set( d["tail"]["files"] ) | { x["p"] for x in d["sigs"] }; named = set( d["doc_body"]["files"] ) if "doc_body" in d else set()
print( len( named ), len( named - shown ) )
PY
}
if ans "$TMP/c6a.xml" "$TFX" "--for=$T6" && ans "$TMP/c6b.xml" "$TFX" "--for=$T6" --token-budget=3500 && run "$TFX" "--for=$T6" --json >"$TMP/c6a.json" && run "$TFX" "--for=$T6" --json --token-budget=3500 >"$TMP/c6b.json"; then
  read -r xn0 xu0 <<<"$( shownpaths xml "$TMP/c6a.xml" )"; read -r xn1 xu1 <<<"$( shownpaths xml "$TMP/c6b.xml" )"
  read -r jn0 ju0 <<<"$( shownpaths json "$TMP/c6a.json" )"; read -r jn1 ju1 <<<"$( shownpaths json "$TMP/c6b.json" )"
  if [ "$xn0" = 2 ] && [ "$xu0" = 0 ] && [ "$jn0" = 2 ] && [ "$ju0" = 0 ] && [ "${xu1:-9}" = 0 ] && [ "${ju1:-9}" = 0 ] && ! tailrows "$TMP/c6b.xml" | grep -q 'docs/'; then
    ok "(c6) unbudgeted: both doc files named (XML, JSON); under --token-budget=3500 the tail ends before its doc rows and the block names no doc file the answer does not print ($xn1 XML, $jn1 JSON named)"
  else no "(c6) emitted-tail rule: xml $xn0/$xu0 -> $xn1/$xu1, json $jn0/$ju0 -> $jn1/$ju1"; fi
else no "(c6) a run failed"; fi

# (c7) --signatures-only carries no doc text: neither dialect prints the block (positive twin: the same task without the flag fires)
c7ok=1
{ ans "$TMP/c7.xml" "$DFX" "--for=$TASK" --signatures-only && ! grep -q 'doc_body' "$TMP/c7.xml"; } || c7ok=0
run "$DFX" "--for=$TASK" --signatures-only --json >"$TMP/c7.json"; { [ -s "$TMP/c7.json" ] && ! grep -q 'doc_body' "$TMP/c7.json"; } || c7ok=0
{ grep -q '<doc_body match="lexical"' "$TMP/f1.xml" && python3 -c 'import json,sys; assert "doc_body" in json.load(open(sys.argv[1]))' "$TMP/j1.json"; } || c7ok=0
if [ "$c7ok" = 1 ]; then ok "(c7) --signatures-only: no <doc_body> and no \"doc_body\" key (the same task without it fires in both)"; else no "(c7) --signatures-only"; fi

# (c8) a multi-root run serves the block in XML as it does in JSON: the same passages (root-prefixed p=), in the same order
MRX="$TMP/multiroot"; mkdir -p "$MRX/a" "$MRX/b"; cp -R "$DFX/src" "$MRX/a/"; cp -R "$DFX/docs" "$DFX/README.md" "$MRX/b/"
mr(){ ( cd "$MRX" || exit 1; "$BIN" a b --no-cache "$@" 2>/dev/null </dev/null ); }
mr "--for=$TASK" >"$TMP/c8.xml"; c8x=$?; mr "--for=$TASK" --json >"$TMP/c8.json"; c8j=$?
if [ "$c8x" = 0 ] && [ "$c8j" = 0 ] && python3 - "$TMP/c8.xml" "$TMP/c8.json" <<'PY'
import html, json, re, sys
x = open( sys.argv[1], encoding="utf8" ).read(); d = json.load( open( sys.argv[2], encoding="utf8" ) )["doc_body"]
xs = [ ( html.unescape( p ), html.unescape( n ) ) for p, n in re.findall( r'<b t="section" p="([^"]+)"[^>]* n="([^"]*)"', x ) ]
js = [ ( p["p"], p["n"] ) for p in d["passages"] if p["t"] == "section" ]
assert xs and xs == js and all( p.startswith( "b/" ) for p, n in xs ), ( xs, js )
PY
then ok "(c8) two roots: the XML block serves the passages the JSON key does, with root-prefixed p="; else no "(c8) multi-root XML/JSON parity"; fi

# (c9) both ceilings bind: --token-budget=9000 with --max-tokens=5000 --detail=1 serves the block into the smaller; the block never exceeds
#      what 5000 leaves after the answer (positive twin: --token-budget alone serves sections)
if ans "$TMP/c9.xml" "$DFX" "--for=$TASK" --token-budget=9000 --max-tokens=5000 --detail=1 && ans "$TMP/c9t.xml" "$DFX" "--for=$TASK" --token-budget=9000 && [ "$( nsec "$TMP/c9t.xml" )" -ge 3 ] && python3 - "$TMP/c9.xml" <<'PY'
import re, sys
s = open( sys.argv[1], encoding="utf8" ).read()
ans = int( re.search( r'^<ctx [^>]*est_tokens="(\d+)"', s ).group(1) )
blk = int( re.search( r'<doc_body match="lexical" est_tokens="(\d+)"', s ).group(1) )
assert blk <= max( 0, 5000 - ans ), ( "the block is over what the smaller ceiling leaves", ans, blk )
PY
then ok "(c9) --token-budget=9000 with --max-tokens=5000 --detail=1: the block fits what 5000 leaves after the answer"; else no "(c9) both ceilings"; fi

# (c10) the --json block prices exactly the bytes it prints: its own est_tokens key counted once (14 + digits bytes), markup 2.5 B per token, text 3.8
if [ -s "$TMP/j1.json" ] && python3 - "$TMP/j1.json" <<'PY'
import json, sys
raw = open( sys.argv[1], encoding="utf8" ).read()
d = json.loads( raw )["doc_body"]
blk = raw[ raw.index( '"doc_body"' ): raw.rindex( "}" ) ].encode()
txt = sum( len( p["text"].encode() ) for p in d["passages"] )
want = round( ( len( blk ) - txt ) / 2.5 ) + round( txt / 3.8 )
assert abs( d["est_tokens"] - want ) <= 1, ( d["est_tokens"], want )
PY
then ok "(c10) the --json block's est_tokens is its own bytes priced once (the key is not counted twice)"; else no "(c10) --json block price"; fi

# (p1) cost: a doc section of ONE 1.3 MB line is served in a bounded time, with and without a token budget
PFX="$TMP/longline"; cp -R "$DFX" "$PFX"
python3 - "$PFX" <<'PY'
import sys
open( sys.argv[1] + "/docs/retries.md", "ab" ).write( b"\n## Long retry notes\n\n" + b"retry policy backoff wait " * 50000 + b"\n" )
PY
timed(){ python3 - "$BIN" "$PFX" "$@" <<'PY'
import subprocess, sys, time
binp, fx, args = sys.argv[1], sys.argv[2], sys.argv[3:]
t = time.time()
try:
    p = subprocess.run( [ binp, fx, "--no-cache" ] + args, cwd=fx, stdin=subprocess.DEVNULL, capture_output=True, timeout=25 )
except subprocess.TimeoutExpired:
    print( "TIMEOUT after 25 s" ); sys.exit( 1 )
out = p.stdout.decode( "utf8", "replace" )
ok = p.returncode == 0 and out.endswith( "</ctx>" ) and "<doc_body match=\"lexical\" est_tokens" in out and 'n="Long retry notes"' in out
print( "%.1f s rc=%d block=%s" % ( time.time() - t, p.returncode, ok ) ); sys.exit( 0 if ok else 2 )
PY
}
if p1a=$( timed "--for=$TASK" ) && p1b=$( timed "--for=$TASK" --token-budget=7000 ); then ok "(p1) a 1.3 MB one-line section is served in bounded time: $p1a; under --token-budget=7000: $p1b"; else no "(p1) long-line section: ${p1a:-} ${p1b:-}"; fi

[ "$fail" = 0 ] && echo "fordocbodycheck: PASS" || echo "fordocbodycheck: FAIL"
exit "$fail"
