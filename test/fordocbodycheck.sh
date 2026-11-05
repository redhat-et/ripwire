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
assert re.search( r'<doc_body files="3" allowance="7500" bytes="\d+"', b ), "root"
secs = re.findall( r'<b t="section" p="([^"]+)" l="(\d+)" e="(\d+)" n="([^"]*)" rank="(\d+)" of="(\d+)"[^>]*><!\[CDATA\[(.*?)\]\]></b>', b, re.S )
assert secs, "no section rows"
pol = [ x for x in secs if x[0] == "docs/retries.md" and x[3] == "Retry policy" ]
assert pol and pol[0][1] == "5" and "backs off exponentially" in pol[0][6], "the Retry policy section of docs/retries.md, line 5, with its text"
assert any( x[0] == "docs/uploads.md" for x in secs ), "a second doc file"
assert all( int( x[4] ) <= int( x[5] ) for x in secs ), "rank <= of"
PY
then ok "(f1) fires: <doc_body>, its legend, section rows with p= l= e= n= rank= of= and the section text"; else no "(f1) fires: $( block "$TMP/f1.xml" | head -c 400 )"; fi

# (f2) the allowance cut
if [ -s "$TMP/f1.xml" ] && block "$TMP/f1.xml" | grep -q '<doc_body [^>]*dropped="[0-9]*" capped="1" next="--recall=&apos;how do the docs describe the retry policy for failed uploads&apos;">' \
   && block "$TMP/f1.xml" | grep -q '<b t="section" p="docs/retries.md" l="5" e="[0-9]*" n="Retry policy" rank="[0-9]*" of="[0-9]*" cut="1">'
then ok "(f2) a section over the allowance is cut=\"1\"; the root says dropped=, capped=\"1\" and next= the recall call"; else no "(f2) allowance: $( block "$TMP/f1.xml" | grep -o '<doc_body [^>]*>' )"; fi

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
   && ! tailrows "$TMP/f5.xml" | grep -q '\.md' && grep -q '<doc_body files="3" allowance="7500"' "$TMP/f5.xml"
then ok "(f5) a code-first tail with no doc in its first 10 printed rows still fires (the rule reads rank order)"; else no "(f5) code-first tail: $( tailrows "$TMP/f5.xml" )"; fi

# (n1) code only
if ans "$TMP/n1.xml" "$CFX" "--for=$TASK" && ! grep -q 'doc_body' "$TMP/n1.xml"; then ok "(n1) code-only repo, prose task: silent"; else no "(n1) code only must be silent (or the run failed)"; fi

# (n2) one doc in the tail's first rows: silent; (n2b) a second doc there: fires
if ans "$TMP/n2.xml" "$OFX" "--for=$TASK" && tailrows "$TMP/n2.xml" | grep -q 'docs/retries.md' && ! grep -q 'doc_body' "$TMP/n2.xml"
then ok "(n2) one doc file, inside the first 10 t rows ($( tailrows "$TMP/n2.xml" | tr ' ' '\n' | grep -n 'docs/' | cut -d: -f1 | tr '\n' ' ')): silent"
else no "(n2) one doc file must be silent and sit in the tail's first rows: $( tailrows "$TMP/n2.xml" )"; fi
if ans "$TMP/n2b.xml" "$TFX" "--for=$TASK" && grep -q '<doc_body files="2"' "$TMP/n2b.xml"; then ok "(n2b) the same repo with two docs in the first t rows fires (files=\"2\")"; else no "(n2b) two docs must fire"; fi

# (n3) code-cued tasks
for q in "how do the docs describe handle_upload retries" 'how do the docs describe `retry` for failed uploads' "how do the docs describe uploader.retry( for failed uploads" "how do the docs describe retryPolicy for failed uploads"; do
    if ans "$TMP/n3.xml" "$DFX" "--for=$q" && ! grep -q 'doc_body' "$TMP/n3.xml"; then ok "(n3) code-cued task silent: $q"; else no "(n3) code-cued task must be silent: $q"; fi
done

# (h1) token budget: held
if ans "$TMP/h1.xml" "$DFX" "--for=$TASK" --token-budget=4000 \
   && grep -q '<doc_body held="budget" files="3" next="--for=&apos;how do the docs describe the retry policy for failed uploads&apos;"><f p="[^"]*"/><f p="[^"]*"/><f p="[^"]*"/></doc_body></ctx>$' "$TMP/h1.xml" \
   && ! grep -q '<b t="section"' "$TMP/h1.xml"
then ok "(h1) --token-budget holds the block: held=\"budget\", three f p= rows, next= the same call, no section text"; else no "(h1) held: $( grep -o '<doc_body.*' "$TMP/h1.xml" | head -c 300 )"; fi

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
if [ "$j2rc" = 0 ] && python3 -c 'import json,sys; d=json.load(open(sys.argv[1]))["doc_body"]; assert d["held"]=="budget" and "passages" not in d and len(d["files"])==3' "$TMP/j2.json" 2>/dev/null
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
if grep -q '<!-- ripwire for doc_body: ' "$TMP/x1.xml" && grep -q '<doc_body files="3" allowance="7500" bytes="[0-9]*"' "$TMP/x1.xml" \
   && grep -q '<b t="section" p="docs/[a-z]*\.md" l="[0-9]*" e="[0-9]*" n="[^"]*" rank="[0-9]*" of="[0-9]*"' "$TMP/x1.xml" && grep -q '</doc_body></ctx>$' "$TMP/x1.xml"
then ok "(x1) MCP for: the block, its legend and section rows, last before </ctx>"; else no "(x1) MCP: $( grep -o '<doc_body[^>]*>' "$TMP/x1.xml" | head -c 300 )"; fi
mcp ',"budget_tokens":4000' >"$TMP/x2.xml"
if grep -q '<doc_body held="budget" files="3"' "$TMP/x2.xml" && ! grep -q '<b t="section"' "$TMP/x2.xml"; then ok "(x2) MCP budget_tokens: held"; else no "(x2) MCP held: $( grep -o '<doc_body.*' "$TMP/x2.xml" | head -c 300 )"; fi

[ "$fail" = 0 ] && echo "fordocbodycheck: PASS" || echo "fordocbodycheck: FAIL"
exit "$fail"
