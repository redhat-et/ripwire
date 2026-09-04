#!/usr/bin/env bash
# sublistcountcheck.sh — gate for H4 (capture-audit 2026-09-04, lens1 F1 / lens2 M3 / lens8 #12):
# EVERY SECONDARY ROW CLASS INSIDE A PAGED ANSWER CARRIES ITS OWN COUNT AND OBEYS THE WINDOW.
#
# The measured problem (all three lenses, independently): --grep/--regex and the MCP `grep` twin print a
# trailing <unindexed> block — the crawl's unsupported-ext/text-looking population, scanned additively —
# that had NO attributes at all, was never counted by the root's hits=/total=, and ignored --limit/--offset
# entirely. Live, pre-fix:
#
#   --regex='fnv1a\w+'          root says hits="75" shown="75" capped="0"   and emits 98 hit sites
#   --grep=DEGRADED_PATH_ALERT  root says shown="100"                       and emits 129 hit sites
#   MCP grep limit=3            ships 3 hits and 29 unindexed objects       (2,805 B for a 3-row answer)
#   --grep=e --limit=1          root says shown="1"  → 381,283 unindexed rows / 98,278,581 bytes of stdout
#
# A paged answer that says shown="1" and hands back 98 MB is not a paging bug in one verb; it is a missing
# RULE. This gate states the rule over the family rather than over the instance that was caught:
#
#   R1  a secondary row class (a container of rows that is NOT the answer's primary <f>/hit list) carries
#       its OWN count= shown= capped= — the shape --impact's <f via="import"> already uses with
#       shown_importers=/importers_capped= (arm 7 is that shape's liveness anchor);
#   R2  it obeys the SAME window the primary list obeys (--limit/--offset on the CLI, `limit`/`offset` over
#       MCP) — or declares itself unwindowed and says so with a count;
#   R3  the ROOT's hits=/total= stay the IN-INDEX population (that is what every consumer already reads)
#       and the second population is reconcilable from the root alone via unindexed_hits=, which is
#       emitted UNCONDITIONALLY — a zero there is the answer "nothing outside the index matched", not a
#       missing attribute;
#   R4  the two dialects state the same facts: whatever the CLI root names, the MCP payload carries
#       (mcpclidiffcheck.sh's LENS2 owns the general rule; arm 6 pins the sub-list's own half of it).
#
# Arms:
#   (1) COUNTED     — the default CLI answer's <unindexed> carries count/shown/capped, shown equals the
#                     rows it actually emitted, capped is exactly (shown < count), and the root's
#                     unindexed_hits= equals count.
#   (2) WINDOWED    — --limit=2 cuts the sub-list to 2 rows and says so; count= is UNCHANGED from arm (1)
#                     (a property of the search, never of the page — the §A1 rule the indexed half already
#                     keeps).
#   (3) PATHOLOGY   — the lens's own `--grep=e --limit=1`: a one-row answer must be a one-row answer.
#                     RED pre-fix at 98 MB. Also run on a hermetic sandbox (3b) so the arm still has teeth
#                     on a corpus without this repo's 152 unsupported-ext files.
#   (4) SIBLING     — --regex carries the identical shape (family, not instance).
#   (5) RECONCILE   — unindexed_hits= is on the root even at zero, the <unindexed> element stays absent at
#                     zero (absent-means-none), and the legend defines what it counts.
#   (6) MCP TWIN    — the MCP `grep` sub-list carries count/shown/capped, obeys `limit`, and the whole
#                     limit=3 payload fits in 1,500 B (lens8 #12's own P12 budget).
#   (7) PROPERTY    — derived, not enumerated: for EVERY container element in a grep-family answer that
#                     holds row children and is not the primary <f> class, assert R1+R2. A new secondary
#                     row class added later must comply or this arm reds without being edited.
#   (8) REFERENCE   — --impact's <f via="import"> still carries shown_importers=/importers_capped=, so the
#                     shape arm (1) copies is proven to exist rather than assumed.
#   (9) DETERMINISM + WELL-FORMEDNESS on every surface this gate touched.
#
# MUTATION EVIDENCE: arms (1),(2),(3),(3b),(4),(5),(6),(7) all FAIL against the pre-fix binary (the
# integration head this lane branched from) — run
#   bash test/sublistcountcheck.sh /path/to/prefix/build/ripwire
# to see it red on the shipped behaviour.
#
# Usage:
#   bash test/sublistcountcheck.sh                    # uses build/ripwire
#   bash test/sublistcountcheck.sh path/to/ripwire    # explicit binary (the mutation arm)
#   RIPWIRE_BIN=asan/ripwire bash test/sublistcountcheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for the XML/JSON assertions"; exit 2; }
echo "sublistcountcheck: BIN=$BIN  CORPUS=$ROOT"

# The one reader for a grep answer's sub-list facts: prints
#   <root unindexed_hits> <sub count> <sub shown> <sub capped> <rows actually emitted inside the sub-list>
# with "-" for any attribute the answer did not carry, so a missing attribute reads as a value rather
# than crashing the arm. Deliberately regex-free on the row side: the rows are counted by an XML walk, so
# a folded/collapsed row shape cannot fool it.
sublist_facts() {
    python3 - "$1" <<'PY'
import sys, xml.etree.ElementTree as ET
raw = open( sys.argv[1], "rb" ).read()
root = ET.fromstring( raw )
sub  = root.find( "unindexed" )
def a( el, name ):
    if el is None: return "-"
    return el.attrib.get( name, "-" )
rows = 0 if sub is None else len( sub.findall( ".//hit" ) )
print( a( root, "unindexed_hits" ), a( sub, "count" ), a( sub, "shown" ), a( sub, "capped" ), rows )
PY
}

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (1) the sub-list carries its own count/shown/capped ==="
# ═══════════════════════════════════════════════════════════════════════════
"$BIN" "$ROOT" --grep=DEGRADED_PATH_ALERT >"$TMP/d.xml" 2>/dev/null
read -r d_root d_count d_shown d_capped d_rows <<<"$( sublist_facts "$TMP/d.xml" )"
if [ "$d_count" != "-" ] && [ "$d_shown" != "-" ] && [ "$d_capped" != "-" ]; then
    ok "(1a) <unindexed> carries count=$d_count shown=$d_shown capped=$d_capped"
else
    no "(1a) <unindexed> carries no count/shown/capped of its own (count=$d_count shown=$d_shown capped=$d_capped) — the sub-list is uncounted"
fi
[ "$d_shown" = "$d_rows" ] \
    && ok "(1b) shown=$d_shown equals the rows the sub-list actually emitted" \
    || no "(1b) shown=$d_shown but $d_rows rows were emitted inside <unindexed>"
if [ "$d_count" != "-" ] && [ "$d_shown" != "-" ]; then
    want_capped=0; [ "$d_shown" -lt "$d_count" ] 2>/dev/null && want_capped=1
    [ "$d_capped" = "$want_capped" ] \
        && ok "(1c) capped=$d_capped is exactly (shown < count)" \
        || no "(1c) capped=$d_capped but shown=$d_shown count=$d_count says it should be $want_capped"
fi
if [ "$d_root" != "-" ] && [ "$d_root" = "$d_count" ]; then
    ok "(1d) the root's unindexed_hits=$d_root reconciles with the sub-list's count=$d_count"
else
    no "(1d) root unindexed_hits=$d_root does not match the sub-list count=$d_count — the two populations cannot be reconciled"
fi

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (2) the sub-list obeys the window, and its count does not move with the page ==="
# ═══════════════════════════════════════════════════════════════════════════
"$BIN" "$ROOT" --grep=DEGRADED_PATH_ALERT --limit=2 >"$TMP/d2.xml" 2>/dev/null
read -r w_root w_count w_shown w_capped w_rows <<<"$( sublist_facts "$TMP/d2.xml" )"
[ "$w_rows" -le 2 ] 2>/dev/null \
    && ok "(2a) --limit=2 cut the sub-list to $w_rows row(s)" \
    || no "(2a) --limit=2 and the sub-list still emitted $w_rows rows — the window does not reach it"
[ "$w_shown" = "$w_rows" ] \
    && ok "(2b) the windowed sub-list's shown=$w_shown matches its emitted rows" \
    || no "(2b) windowed sub-list says shown=$w_shown, emitted $w_rows"
if [ "$w_count" != "-" ] && [ "$w_count" = "$d_count" ]; then
    ok "(2c) count=$w_count is a property of the search, unchanged by the page"
else
    no "(2c) the sub-list count moved with the page (or was never stated): $d_count unpaged vs $w_count at --limit=2"
fi
[ "$w_capped" = "1" ] \
    && ok "(2d) a cut sub-list says capped=1" \
    || no "(2d) the sub-list was cut to $w_rows of $w_count and did not say capped=1 (capped=$w_capped)"

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (3) the pathology: a one-row answer is a one-row answer ==="
# ═══════════════════════════════════════════════════════════════════════════
# lens1 F1's own repro. Pre-fix this writes 98,278,581 bytes for shown="1"; the ceiling below is two
# orders of magnitude under that and still ~20x the legend, so it can never pass by accident.
"$BIN" "$ROOT" --grep=e --limit=1 >"$TMP/e1.xml" 2>/dev/null
e_bytes="$( wc -c <"$TMP/e1.xml" | tr -d ' ' )"
read -r e_root e_count e_shown e_capped e_rows <<<"$( sublist_facts "$TMP/e1.xml" )"
[ "$e_bytes" -le 200000 ] 2>/dev/null \
    && ok "(3a) --grep=e --limit=1 answers in $e_bytes bytes" \
    || no "(3a) --grep=e --limit=1 wrote $e_bytes bytes for a one-row answer (ceiling 200000)"
[ "$e_rows" -le 1 ] 2>/dev/null \
    && ok "(3b) the sub-list honoured --limit=1 ($e_rows row)" \
    || no "(3b) --limit=1 and the sub-list emitted $e_rows rows"

# (3c) the same property on a HERMETIC corpus, so this arm keeps its teeth on a tree that happens to hold
# no unsupported-ext files of its own.
SB="$TMP/sandbox"; mkdir -p "$SB/queries"
cat >"$SB/main.c" <<'EOF'
int sublistHost( void ) { return SUBLISTTOKEN_hit; }
EOF
python3 - "$SB" <<'PY'
import os, sys
d = sys.argv[1]
# .scm has no grammar in the index — the crawl's unsupported-ext/text-looking class, exactly the
# population the <unindexed> block scans. 400 hits in one file: far past any sane page.
with open( os.path.join( d, "queries", "tags.scm" ), "w" ) as fh:
    for i in range( 400 ):
        fh.write( "; SUBLISTTOKEN_hit line %d\n" % i )
PY
"$BIN" "$SB" --no-cache --grep=SUBLISTTOKEN_hit --limit=3 >"$TMP/sb.xml" 2>/dev/null
read -r s_root s_count s_shown s_capped s_rows <<<"$( sublist_facts "$TMP/sb.xml" )"
if [ "$s_count" = "400" ] && [ "$s_rows" -le 3 ] 2>/dev/null && [ "$s_shown" = "$s_rows" ] && [ "$s_capped" = "1" ]; then
    ok "(3c) hermetic: 400 unindexed hits, --limit=3 serves $s_rows and discloses count=400 capped=1"
else
    no "(3c) hermetic sandbox: expected count=400 rows<=3 shown==rows capped=1, got count=$s_count shown=$s_shown capped=$s_capped rows=$s_rows"
    grep -o '<unindexed[^>]*>' "$TMP/sb.xml" | head -1
fi

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (4) the sibling verb: --regex carries the identical shape ==="
# ═══════════════════════════════════════════════════════════════════════════
"$BIN" "$ROOT" --regex='fnv1a\w+' >"$TMP/r.xml" 2>/dev/null
read -r r_root r_count r_shown r_capped r_rows <<<"$( sublist_facts "$TMP/r.xml" )"
if [ "$r_count" != "-" ] && [ "$r_shown" = "$r_rows" ] && [ "$r_root" = "$r_count" ]; then
    ok "(4) --regex's sub-list is counted, windowed and reconcilable (count=$r_count shown=$r_shown)"
else
    no "(4) --regex's sub-list broke the family shape: unindexed_hits=$r_root count=$r_count shown=$r_shown rows=$r_rows"
    grep -o '<grep [^>]*>' "$TMP/r.xml" | head -1
fi
"$BIN" "$ROOT" --regex='fnv1a\w+' --limit=1 >"$TMP/r1.xml" 2>/dev/null
read -r r1_root r1_count r1_shown r1_capped r1_rows <<<"$( sublist_facts "$TMP/r1.xml" )"
[ "$r1_rows" -le 1 ] 2>/dev/null \
    && ok "(4b) --regex --limit=1 windows the sub-list too" \
    || no "(4b) --regex --limit=1 still emitted $r1_rows sub-list rows"

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (5) reconciliation from the root alone, and absent-means-none ==="
# ═══════════════════════════════════════════════════════════════════════════
"$BIN" "$ROOT/test/fixture" --no-cache --grep=int >"$TMP/fx.xml" 2>/dev/null
grep -q 'unindexed_hits="0"' "$TMP/fx.xml" \
    && ok "(5a) unindexed_hits=\"0\" is stated even when nothing outside the index matched" \
    || { no "(5a) unindexed_hits= is missing on a corpus with no unindexed hits — a zero must be an answer, not an absence"; grep -o '<grep [^>]*>' "$TMP/fx.xml" | head -1; }
grep -q '<unindexed' "$TMP/fx.xml" \
    && no "(5b) an empty <unindexed> element was emitted (absent-means-none is the convention)" \
    || ok "(5b) no <unindexed> element when there is nothing to list"
python3 - "$TMP/d.xml" <<'PY' >"$TMP/legend.res" 2>&1
import sys, re
t = open( sys.argv[1] ).read()
legend = " ".join( re.findall( r"<!--(.*?)-->", t, re.S ) ).lower()
missing = [ k for k in ( "unindexed_hits", "in-index" ) if k not in legend ]
print( "OK" if not missing else "the legend never defines " + ",".join( missing ) )
PY
[ "$( cat "$TMP/legend.res" )" = "OK" ] \
    && ok "(5c) the legend says unindexed_hits= is the second population and hits= is in-index" \
    || no "(5c) $( cat "$TMP/legend.res" )"

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (6) the MCP twin: same facts, same window, and a payload an agent can afford ==="
# ═══════════════════════════════════════════════════════════════════════════
mcp_grep() {
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
        '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"grep","arguments":'"$1"'}}' \
        | "$BIN" --mcp 2>/dev/null | tail -1 | python3 -c '
import sys, json
r = json.load( sys.stdin )
print( "__ERROR__:" + r["error"].get( "message", "" ) if "error" in r else r["result"]["content"][0]["text"] )
'
}
mcp_grep '{"path":"'"$ROOT"'","pattern":"DEGRADED_PATH_ALERT","limit":3}' >"$TMP/m3.json"
python3 - "$TMP/m3.json" <<'PY' >"$TMP/m3.res" 2>&1
import sys, json
raw = open( sys.argv[1] ).read()
if raw.startswith( "__ERROR__" ): print( "PROBE_BROKEN: " + raw ); raise SystemExit
j = json.loads( raw )
u = j.get( "unindexed" )
problems = []
if u is None:
    problems.append( "no unindexed key at all" )
elif isinstance( u, list ):
    problems.append( "unindexed is still a bare array of %d rows — it carries no count/shown/capped" % len( u ) )
else:
    for k in ( "count", "shown", "capped", "rows" ):
        if k not in u: problems.append( "unindexed is missing " + k )
    rows = u.get( "rows", [] )
    if len( rows ) > 3: problems.append( "unindexed shipped %d rows at limit=3" % len( rows ) )
    if u.get( "shown" ) != len( rows ): problems.append( "shown=%r but %d rows" % ( u.get( "shown" ), len( rows ) ) )
    if u.get( "capped" ) != ( u.get( "shown", 0 ) < u.get( "count", 0 ) ): problems.append( "capped disagrees with shown<count" )
if "unindexed_hits" not in j: problems.append( "the payload states no unindexed_hits" )
elif u is not None and isinstance( u, dict ) and j["unindexed_hits"] != u.get( "count" ):
    problems.append( "unindexed_hits=%r != unindexed.count=%r" % ( j["unindexed_hits"], u.get( "count" ) ) )
print( "OK" if not problems else "; ".join( problems ) )
print( "BYTES", len( raw ) )
PY
m3_verdict="$( head -1 "$TMP/m3.res" )"
m3_bytes="$( grep '^BYTES' "$TMP/m3.res" | awk '{print $2}' )"
[ "$m3_verdict" = "OK" ] \
    && ok "(6a) the MCP sub-list carries count/shown/capped and honours limit" \
    || no "(6a) $m3_verdict"
[ -n "$m3_bytes" ] && [ "$m3_bytes" -le 1500 ] 2>/dev/null \
    && ok "(6b) the MCP limit=3 payload is $m3_bytes bytes (P12 budget 1500)" \
    || no "(6b) the MCP limit=3 payload is ${m3_bytes:-?} bytes — over the 1500-byte P12 budget"

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (7) the PROPERTY, derived from the answer rather than enumerated ==="
# ═══════════════════════════════════════════════════════════════════════════
# For every container under a grep-family root that holds row children and is NOT the primary <f> class,
# assert R1 (its own count/shown/capped) and R2 (it obeyed the window). A secondary row class added later
# has to comply or this arm reds with nobody editing it.
for probe in "--grep=DEGRADED_PATH_ALERT" "--regex=fnv1a\\w+"; do
    "$BIN" "$ROOT" "$probe" --limit=2 >"$TMP/p.xml" 2>/dev/null
    python3 - "$TMP/p.xml" 2 <<'PY' >"$TMP/p.res" 2>&1
import sys, xml.etree.ElementTree as ET
root  = ET.fromstring( open( sys.argv[1], "rb" ).read() )
limit = int( sys.argv[2] )
problems = []
for child in root:
    if child.tag in ( "f", "enc", "suggest" ):
        continue                                  # the primary row class and the two annotation classes
    rows = child.findall( ".//hit" ) + child.findall( ".//f" )
    if not rows:
        continue                                  # not a row container
    for attr in ( "count", "shown", "capped" ):
        if attr not in child.attrib:
            problems.append( "<%s> holds rows and carries no %s=" % ( child.tag, attr ) )
    emitted = len( child.findall( ".//hit" ) )
    if emitted > limit:
        problems.append( "<%s> emitted %d rows under limit=%d" % ( child.tag, emitted, limit ) )
print( "OK" if not problems else "; ".join( problems ) )
PY
    [ "$( cat "$TMP/p.res" )" = "OK" ] \
        && ok "(7) $probe: every secondary row container is counted and windowed" \
        || no "(7) $probe: $( cat "$TMP/p.res" )"
done

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (8) the reference shape --impact's importer list already uses ==="
# ═══════════════════════════════════════════════════════════════════════════
"$BIN" "$ROOT" --impact=pageDisclosure --limit=5 >"$TMP/imp.xml" 2>/dev/null
if grep -q 'shown_importers="' "$TMP/imp.xml" && grep -q 'importers_capped="' "$TMP/imp.xml"; then
    ok "(8) --impact still discloses shown_importers=/importers_capped= — the shape arm (1) copies exists"
else
    no "(8) --impact no longer carries shown_importers=/importers_capped=; the reference shape this gate cites has moved — re-anchor it"
fi

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (9) determinism + well-formedness on every surface touched ==="
# ═══════════════════════════════════════════════════════════════════════════
"$BIN" "$ROOT" --grep=DEGRADED_PATH_ALERT --limit=2 >"$TMP/det2.xml" 2>/dev/null
diff -q "$TMP/d2.xml" "$TMP/det2.xml" >/dev/null \
    && ok "(9a) the windowed grep answer is byte-identical across runs" \
    || no "(9a) the windowed grep answer is not deterministic"
if command -v xmllint >/dev/null 2>&1; then
    xml_bad=0
    for f in "$TMP/d.xml" "$TMP/d2.xml" "$TMP/r.xml" "$TMP/sb.xml" "$TMP/fx.xml"; do
        xmllint --noout "$f" >/dev/null 2>&1 || { xml_bad=1; no "(9b) $f is not well-formed XML"; }
    done
    [ "$xml_bad" = "0" ] && ok "(9b) every emitted surface passes xmllint"
else
    ok "(9b) xmllint unavailable — well-formedness arm skipped"
fi

echo
[ "$fail" = "0" ] && { echo "ALL PASS"; exit 0; } || { echo "FAILURES ABOVE"; exit 1; }
