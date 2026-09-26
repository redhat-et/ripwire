#!/usr/bin/env bash
# astrocheck.sh — Astro (.astro) frontmatter extraction: issue #67.
#
# An .astro file is `---`-fenced frontmatter (TypeScript) plus a template no TypeScript grammar can read.
# This build parses the FRONTMATTER ONLY, via the one ts_parser_set_included_ranges call in the tree
# (src/ingest_sidecap.h), with the TypeScript grammar it already vendors — no Astro grammar, no HTML.
#
# WRITTEN RED: run with RIPWIRE_BIN pointed at any 0.6.2-or-earlier binary and arms (1)-(6) fail, because
# .astro was not in kLangTable at all and every file below was `unindexed="astro:N"`.
#
# The arms that are NOT about Astro-the-language, and why they are here anyway:
#   (7) the included range must not LEAK to the next file a worker draws. ts_parser_set_included_ranges is
#       lexer state, ts_parser_reset does not clear it, and a TSParser is reused per worker — a missed reset
#       truncates some LATER file in ANOTHER language, nondeterministically by work-stealing order. That bug
#       cannot be seen in any .astro output, so it is measured on .ts files that follow .astro files.
#   (1) pins LINE numbers, not just symbol names. tree-sitter takes row/column from TSRange::start_point;
#       a range carrying {0,0} still yields correct BYTE spans, so --expand would look right while every
#       p="file:line" lied by the fence offset. Only a line assertion catches that.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir "$TMP/cache"
export XDG_CACHE_HOME="$TMP/cache"
cp -R "$ROOT/test/astrofix" "$TMP/fix"
# THE UNTERMINATED FENCE IS BUILT HERE, NOT COMMITTED. Extracting it DISCLOSES (guardrail 3), and the
# disclosure writes a degrade trace to stderr on a plain build — so a committed copy would put that line
# on every COLD `ripwire .` of this repository and into every other gate's view of test/. w3fixlegendcheck
# asserts the stderr of --uses/--callers/--impact and went red on exactly that in CI, where the cache is
# cold; a warm local cache hides it, because a cache hit never re-parses and so never re-discloses.
# blindspotcheck.sh keeps its own fixtures out of the tree for the same reason.
printf -- '---\nconst neverClosed = 1;\n<p>unterminated fence</p>\n' > "$TMP/fix/unterminated.astro"

"$BIN" "$TMP/fix" --no-cache > "$TMP/map.xml"

python3 - "$TMP/map.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
byfile = {f.get('p'): f for f in root.iter('f')}
syms = {}
for f in root.iter('f'):
    for s in f.iter('s'):
        syms.setdefault((f.get('p'), s.get('n')), s)
names = {n for (_p, n) in syms}

# (1) frontmatter definitions land, with the right KIND — and the template's do not.
assert ('page.astro', 'pageHelper') in syms, sorted(syms)
assert syms[('page.astro', 'pageHelper')].get('t') == 'fn', syms[('page.astro', 'pageHelper')].attrib
assert ('leak.astro', 'keptFromFrontmatter') in syms, 'the frontmatter of leak.astro was not read at all'

# (2) THE TEMPLATE IS NOT PARSED. Both of these are valid TypeScript sitting in the template half; if the
# included range ever widens to the whole file they appear, and this build's disclosed blind spot is a lie.
assert 'templateLeak' not in names, 'a <script> body in the template was indexed — the range leaked'
assert 'alsoLeaked' not in names, 'a template interpolation was indexed — the range leaked'

# (3) a template-only file and an unterminated fence contribute nothing, and do not crash the run.
assert 'templateonly.astro' not in byfile, 'a file with no frontmatter produced symbols'
assert 'unterminated.astro' not in byfile, 'an unterminated fence produced symbols'
assert 'neverClosed' not in names

# (4) CRLF frontmatter is read (the fence scan must tolerate \r before the newline).
fs = [s for (p, n), s in syms.items() if p == 'crlf.astro']
assert fs, 'CRLF frontmatter was not read'
calls = {c.get('n') for s in fs for c in s.iter('c')}
assert 'astroTwice' in calls, calls
print('  PASS frontmatter definitions land; the template half is not parsed; CRLF, fenceless and unterminated files behave')
PY

# (5) THE ISSUE'S OWN CASE: a .ts service whose only callers live in .astro frontmatter, and the LINES.
"$BIN" "$TMP/fix" --no-cache --uses=astroSquare > "$TMP/uses.xml"
"$BIN" "$TMP/fix" --no-cache --callers=svc.ts:astroSquare > "$TMP/callers.xml"
"$BIN" "$TMP/fix" --no-cache --callers=decoy/svc.ts:astroSquare > "$TMP/decoy.xml"
python3 - "$TMP/uses.xml" "$TMP/callers.xml" "$TMP/decoy.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
uses = ET.parse(sys.argv[1]).getroot()
sites = {(u.get('p'), u.get('role'), u.get('in_id')) for u in uses.iter('u')}
# The frontmatter's TOP-LEVEL call is module-scope code: since issue #60 it is owned by <file-scope>.
assert ('page.astro:3', 'call', '<file-scope>') in sites, sorted(sites)
# ...and the call inside a named frontmatter function is owned by that function. Both LINES are absolute
# against the whole .astro file, which is what pins TSRange::start_point.
assert ('page.astro:4', 'call', 'pageHelper') in sites, sorted(sites)

callers = ET.parse(sys.argv[2]).getroot()
rows = {(s.get('t'), s.get('n'), s.get('p')) for s in callers.iter('s')}
assert ('modscope', '<file-scope>', 'page.astro:1') in rows, sorted(rows)
assert ('fn', 'pageHelper', 'page.astro:4') in rows, sorted(rows)

# (6) THE DECOY. decoy/svc.ts exports the same name from the same basename in the wrong directory.
# page.astro imports "./svc", so the fixture root's svc.ts owns every edge and the decoy owns none.
decoy = ET.parse(sys.argv[3]).getroot()
assert decoy.get('count') == '0', ('the decoy won an edge', decoy.attrib)
print('  PASS an .astro frontmatter call reaches a .ts service (--uses and --callers), on absolute lines, and the decoy wins nothing')
PY

# (6b) CRLF LINES. A CRLF frontmatter is where an off-by-one in the row count would surface first, so the
# CRLF file's call site is pinned by LINE and not merely by "it resolved".
"$BIN" "$TMP/fix" --no-cache --uses=astroTwice > "$TMP/crlfuses.xml"
python3 - "$TMP/crlfuses.xml" <<'CRLFPY'
import sys, xml.etree.ElementTree as ET
sites = {(u.get('p'), u.get('in_id')) for u in ET.parse(sys.argv[1]).getroot().iter('u')}
assert ('crlf.astro:3', '<file-scope>') in sites, ('CRLF frontmatter reported the wrong line', sorted(sites))
print('  PASS a CRLF frontmatter call reports its absolute line (crlf.astro:3)')
CRLFPY

# (6c) AN UNTERMINATED FENCE IS DISCLOSED, NOT DROPPED. A template-only .astro is ordinary Astro and says
# nothing; a file that opens `---` and never closes it has frontmatter we can see the start of and cannot
# extract, and a silent zero there is what guardrail 3 refuses. It rides extract-partial into --skipped.
"$BIN" "$TMP/fix" --no-cache --skipped > "$TMP/skipped.xml"
python3 - "$TMP/skipped.xml" <<'SKIPPY'
import sys, xml.etree.ElementTree as ET
doc = ET.parse(sys.argv[1]).getroot()
# --skipped is emitted inside a <ctx> wrapper; find the element that owns the counters.
root = doc if doc.tag == 'skipped' else doc.find('.//skipped')
assert root is not None, 'no <skipped> element in the document'
rows = {(f.get('p'), f.get('why')) for f in root.iter('f')}
assert ('unterminated.astro', 'extract-partial') in rows, ('an unterminated .astro fence was dropped with no disclosure', sorted(rows))
assert int(root.get('extract_partial') or 0) >= 1, root.attrib
# ...and the ORDINARY shapes must NOT be disclosed, or the signal means nothing.
for quiet in ('templateonly.astro', 'page.astro', 'leak.astro', 'crlf.astro'):
    assert not [q for (q, w) in rows if q == quiet], f'{quiet} was disclosed as a shortfall; only the unterminated fence should be'
print('  PASS an unterminated `---` fence is disclosed as extract-partial, and ordinary .astro files are not')
SKIPPY

# (6d) BLANK LINES BEFORE THE OPENING FENCE. Astro's compiler (@astrojs/compiler 4.0.0, checked with parse()
# and transform()) accepts blank and whitespace-only lines before the opening `---`. Before this arm such a
# file was read as template-only: no symbols, no edges, and nothing disclosed. WRITTEN RED against 8a5e205a.
# Every skipped row moves the frontmatter down, so the call sites are pinned by LINE, which is where a
# start_point that forgot the skipped rows would show.
mkdir -p "$TMP/lead"
cp "$ROOT/test/astrofix/svc.ts" "$TMP/lead/svc.ts"
printf -- '\n\n---\nimport { astroSquare } from "./svc";\nfunction leadHelper( n: number ): number { return astroSquare( n ); }\n---\n<p>{leadHelper( 2 )}</p>\n' > "$TMP/lead/lead.astro"
printf -- '\r\n  \r\n---\r\nimport { astroSquare } from "./svc";\r\nfunction crlfLeadHelper( n: number ): number { return astroSquare( n ); }\r\n---\r\n<p>{crlfLeadHelper( 2 )}</p>\r\n' > "$TMP/lead/leadcrlf.astro"
"$BIN" "$TMP/lead" --no-cache --uses=astroSquare > "$TMP/leaduses.xml"
"$BIN" "$TMP/lead" --no-cache --skipped > "$TMP/leadskipped.xml"
python3 - "$TMP/leaduses.xml" "$TMP/leadskipped.xml" <<'LEADPY'
import sys, xml.etree.ElementTree as ET
sites = {(u.get('p'), u.get('in_id')) for u in ET.parse(sys.argv[1]).getroot().iter('u')}
for want in (('lead.astro:5', 'leadHelper'), ('leadcrlf.astro:5', 'crlfLeadHelper')):
    assert want in sites, (f'{want[1]} was not read at {want[0]}: frontmatter behind blank lines', sorted(sites))
doc = ET.parse(sys.argv[2]).getroot()
root = doc if doc.tag == 'skipped' else doc.find('.//skipped')
disclosed = sorted(f.get('p') for f in root.iter('f') if f.get('p', '').endswith('.astro')) if root is not None else []
assert not disclosed, ('a well-formed .astro was disclosed as a shortfall', disclosed)
print('  PASS frontmatter behind blank lines is read, on absolute lines, with nothing disclosed')
LEADPY

# (7) THE RESET. Interleave .astro files with .ts files whose marker sits at the END: a leaked included
# range would truncate the .ts lex and the marker would vanish. Built here, not committed — 80 files would
# join every other gate's view of test/.
#
# THE FILE SIZES ARE LOAD-BEARING, and this arm was VACUOUS without them. The cold parse pool hands
# work out LONGEST-FILE-FIRST (ingest_parsepool.h's parseOrder stable_sort, fileByteSize[a] > [b]), so
# if the .ts files are the larger ones EVERY .ts is drawn before the first .astro and no worker ever
# performs the .astro -> .ts transition this arm exists to test. Proven: with the range reset deleted,
# the earlier small-.astro fixture still reported 40/40. Each .astro is therefore padded — in its
# TEMPLATE, which keeps the included range tiny while the FILE is large — to sort ahead of every .ts.
mkdir -p "$TMP/reset"
for i in $(seq -w 1 40); do
    { printf -- '---\nconst a%s = 1;\n---\n' "$i"
      for j in $(seq 1 120); do printf '<p>template padding line %s, outside the frontmatter range</p>\n' "$j"; done
    } > "$TMP/reset/p$i.astro"
    { printf '// padding: a leaked range would truncate this file before its marker\n'
      for j in $(seq 1 60); do printf '// filler line %s\n' "$j"; done
      printf 'export function tailMarker%s(): number { return 1; }\n' "$i"
    } > "$TMP/reset/m$i.ts"
done
# the premise the arm depends on: every .astro really is larger than every .ts, so the size-descending
# work order really does put an .astro before a .ts inside one worker.
_minAstro=$( for f in "$TMP"/reset/*.astro; do wc -c < "$f"; done | sort -n | head -1 )
_maxTs=$(    for f in "$TMP"/reset/*.ts;    do wc -c < "$f"; done | sort -n | tail -1 )
if [ "$_minAstro" -le "$_maxTs" ]; then
    printf '  FAIL  reset fixture premise broken: smallest .astro (%s B) is not larger than largest .ts (%s B),\n' "$_minAstro" "$_maxTs"
    printf '        so the longest-file-first work order never draws a .ts after an .astro and the arm is vacuous\n'
    exit 1
fi
"$BIN" "$TMP/reset" --no-cache > "$TMP/reset.xml"
python3 - "$TMP/reset.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
names = {s.get('n') for s in ET.parse(sys.argv[1]).getroot().iter('s')}
missing = [f'tailMarker{i:02d}' for i in range(1, 41) if f'tailMarker{i:02d}' not in names]
assert not missing, f'{len(missing)} .ts tail markers vanished — an included range leaked past its .astro file: {missing[:5]}'
print('  PASS the frontmatter range does not leak to the next file a parse worker draws (40/40 .ts markers survive)')
PY

# (8) determinism and the cache round trip: three CACHED runs against the --no-cache baseline.
for n in a b c; do "$BIN" "$TMP/fix" > "$TMP/$n.xml"; done
cmp "$TMP/map.xml" "$TMP/a.xml"
cmp "$TMP/a.xml" "$TMP/b.xml"
cmp "$TMP/b.xml" "$TMP/c.xml"
echo '  PASS cold/warm determinism (three cached runs equal the uncached baseline)'

# (9) well-formedness, and a relative crawl root resolving identically to an absolute one.
xmllint --noout "$TMP/map.xml"
( cd "$TMP" && "$BIN" ./fix --no-cache > "$TMP/rel.xml" )
python3 - "$TMP/map.xml" "$TMP/rel.xml" <<'PY'
import sys, re
def body(p):
    s = open(p).read()
    s = s[s.rindex('-->') + 3:]
    # root= and est_tokens= are BOTH expected to move: est_tokens prices the emitted document, and the
    # document carries the root string, so a longer absolute root legitimately costs more. Verified on
    # test/dartfix with the stock 0.6.2 binary — this is not an Astro behaviour. Everything else — every
    # symbol, span, rank and edge — must be byte-identical.
    s = re.sub(r' root="[^"]*"', '', s)
    return re.sub(r' est_tokens="[^"]*"', '', s)
assert body(sys.argv[1]) == body(sys.argv[2]), 'a relative crawl root resolved differently from an absolute one'
print('  PASS output is well-formed XML, and a relative root resolves identically to an absolute one')
PY

# (10) the mutation control: break the call site and the edge must go, while the definition stays.
python3 - "$TMP/fix/page.astro" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert 'const doubled = astroSquare( 4 );' in s
p.write_text(s.replace('const doubled = astroSquare( 4 );', 'const doubled = missingSquare( 4 );'))
PY
"$BIN" "$TMP/fix" --no-cache --callers=svc.ts:astroSquare > "$TMP/mut.xml"
python3 - "$TMP/mut.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
r = ET.parse(sys.argv[1]).getroot()
rows = {(s.get('n'), s.get('p')) for s in r.iter('s')}
assert ('<file-scope>', 'page.astro:1') not in rows, 'the mutated frontmatter call still owns an edge'
assert ('pageHelper', 'page.astro:4') in rows, ('the untouched call lost its edge too', sorted(rows))
print('  PASS a mutated frontmatter call site drops exactly its own edge')
PY

# (11) the header no longer hides these files behind unindexed=.
python3 - "$TMP/map.xml" <<'PY'
import sys, re
s = open(sys.argv[1]).read()
m = re.search(r'unindexed="([^"]*)"', s)
assert not (m and 'astro' in m.group(1)), f'.astro is still disclosed as unindexed: {m.group(0)}'
print('  PASS .astro no longer appears in the map header\'s unindexed= roll-up')
PY
