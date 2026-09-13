#!/usr/bin/env bash
# compactlegendcheck.sh — the opt-in, versioned compact legend dialect (--legend=compact) on EVERY XML verb.
#
# History. The dialect shipped for --for/--grep/--regex/--slice (2026-08/09) and every other verb refused it.
# Capture-audit 2026-09-04 lens 8 measured the bill: twelve verbs spend >80% of their bytes on the legend
# (--pr-context 96%, --edit-check 92%, --at 90%, --callers 87%, …) and the canonical ten-verb edit loop pays
# 29,824 B of legend per session for ~9 KB of rows. Plan item P1 (lane L7): compact on every XML verb, the
# FULL legend byte-identical under --legend=full (the default is unchanged — §5a decision 3 keeps compact
# opt-in on the CLI this round), and an opt-in `legend:"compact"` argument on every MCP verb that answers XML.
#
# THE COMPACT CONTRACT (what every arm below asserts):
#   • the root carries schema="ripwire.<key>/v1"; the legend (= every <!-- --> comment outside CDATA) fits
#     its verb's byte pin and names every completeness attribute the document carries (counts_floor / capped / shown /
#     total / has_more / next_offset / offset / limit / *_capped / est_tokens / at / root / graph_ambiguous
#     / graph_unresolved …) — the prose moved to --help and --legend=full;
#   • the ROWS are byte-identical to the full dialect and the root's attribute-name set is the full set plus
#     `schema` — compact changes prose only, never a fact;
#   • DATA comments stay (the map header's <!-- files= … -->, pack-task's <!-- body omitted … -->, the
#     <!-- +more --> marker, --notes' counted header) — only explanatory prose is replaced;
#   • a verb whose output is not XML (--situ, --recall, --report, --html, --mermaid, JSON-native
#     --plan-lanes, the edit/write verbs) refuses --legend=compact loudly, naming the flag.
#
# UNIVERSE arm (U): the verb set is DERIVED from src/cli.h (test/flaguniverse.py) — the same derivation
# jsoncheck #8b and shapingflagcheck (F) use — so a verb added tomorrow is probed tomorrow. Each flag runs at
# defaults on a tmp git fixture; whatever answers with an XML root is an XML verb and must honor compact,
# everything else must refuse it, and each verb's prose legend fits its per-verb pin (pinFor). LOOP arm (L): the ten-verb
# loop's compact legend bill ≤ 4,900 B (was 29,824 on the ripwire tree). MCP arm (M): edit_check with legend:"compact" answers
# in ≤ 900 B on a clean tree, and five more MCP verbs' legends fit their per-verb pins.
# CONDITIONAL arm (D): an absent-at-zero or form-conditional attribute (declined_calls=, unproven_defs=, bodyless_defs=,
# the member form, the multi-root <root label=> rows, --lego's caveat=; on the map family and --impact: pr_iters=,
# pr_converged=, the map header's gauges, --around's defs=, --rank-by's rank_by=/window=; in the third sweep: --tree's
# files=, --zoom's root counts and <module children=>, churn-decay's <recent>, the map rows' lpin=/overloads=/prov=; in the
# fourth sweep: the map header's unresolved=, --impact's defs=/reaches=/importers=/shown_importers=/radius_tested=/
# radius_untested=, --communities' drill=/isolated=/isolated_*=/shown_modules=/bridges=, --community's dir=/label=/bridges=/
# partition=/modules=, --safe-delete's radius_tested=/radius_untested=; in that sweep's last pass: --communities' modules=/
# shown_bridges=/connected_singletons=/symbols=, --community's shown_bridges=, the <bridge> rows, --safe-delete's t=/defs=/
# ambiguous_callers=/dead_code_candidate=, --impact's <f lazy=>, every map-header field, the columnar format=/<cols fields=> and
# lens=; from that sweep's design review: the <s tested=> rows of --callers/--impact; in its follow-up: the <d tested=> rows of
# --pack-task --metrics and the columnar tested column; at the lane's end: the schema of a bundle answered beside a map-family
# flag, every attribute of --pack-task --metrics, and the <d r= cx= ccx= in= amp=> lens facts; from the review of #203: the schema,
# and every reading, of an answer given beside a flag whose verb lost dispatch) is DEFINED by the compact legend of
# a document that carries it, and by none that does not. STRUCTURAL arm (S): every
# conditional attribute the graphlegend.h helper family emits, the PageRank disclosure, every conditional hdr: field of
# the map header, and every absence-marked row field of the map legend, read from source, has a compact reading — so the
# next one cannot land undefined.
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/compactlegendcheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/fixture"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

# ── ONE INGEST FOR THE WHOLE GATE (2026-09-05, terminality round A lane V2) ───────────────────────────────
# Every probe below used to carry --no-cache, so this gate paid a COLD PARSE per invocation — 23 verb rows in
# the (A)/(F)/(L) arms plus two runs of every XML flag in the (U) universe sweep, and each one re-parsed the
# same six-file fixture from scratch. Measured on this machine, test/fixture, one verb: 0.09 s cold vs 0.01 s
# warm. That is the whole reason this gate's pargates budget had to go to 1200 s (pargates.py, 525ce39a),
# which registered "one ingest shared across probes" as the fix; this is it.
#
# TWO changes, and the second is what makes the first safe:
#   1. TMPDIR is redirected into this gate's own scratch dir. quality::cacheDirLadder() honours $TMPDIR, so
#      the per-root cache blobs land HERE, are private to this run, and die with the trap above. Without it a
#      warm gate would share $TMPDIR/ripwire with every other gate pargates runs beside it — and this gate's
#      (U) arm compares a verb's FULL and COMPACT payloads byte-for-byte, so a sibling gate writing a blob
#      between those two runs could move a cache-reporting row (--doctor's cache-dir bytes=) underneath it.
#      Private TMPDIR removes that coupling outright rather than accepting a flake window.
#   2. Both roots are warmed ONCE, here, before any arm asserts. Every later invocation reads that blob.
# No probe is deliberately cold: --no-cache is itself a flag in the (U) universe, so the cold path is still
# exercised — as a probe VALUE, on the one row whose contract it is, which is where it belongs.
# The restore-equivalence contract (a --cache restore == a cold parse) is what makes warm probes legitimate
# here; if it ever breaks, this gate goes red, which is the correct place for that news to arrive.
export TMPDIR="$TMP/cache"; mkdir -p "$TMPDIR"

run(){ "$BIN" "$FIX" "$@" 2>"$TMP/err"; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 not found — required by the universe arm"; exit 2; }

# ── the legend/payload splitter: comments OUTSIDE CDATA are legend, everything else is payload ────────────
cat > "$TMP/leg.py" <<'PY'
import sys, re
op, path = sys.argv[1], sys.argv[2]
buf = open( path, encoding = "utf-8", errors = "replace" ).read()
def split( b ):
    i = 0; n = len( b ); leg = []; pay = []
    while i < n:
        if b.startswith( "<![CDATA[", i ):
            j = b.find( "]]>", i ); j = n if j < 0 else j + 3; pay.append( b[ i:j ] ); i = j
        elif b.startswith( "<!--", i ):
            j = b.find( "-->", i ); j = n if j < 0 else j + 3; leg.append( b[ i:j ] ); i = j
        else:
            j = b.find( "<", i + 1 ); j = n if j < 0 else j; pay.append( b[ i:j ] ); i = j
    return leg, "".join( pay )
leg, pay = split( buf )
m = re.search( r"<([A-Za-z][\w:.-]*)((?:\s+[\w:.-]+=\"[^\"]*\")*)\s*/?>", pay )
if op == "bytes":      print( sum( len( x ) for x in leg ) )
elif op == "ncomments": print( len( leg ) )
elif op == "roottag":  print( m.group( 1 ) if m else "" )
elif op == "schema":
    s = re.search( r'\sschema="([^"]*)"', m.group( 2 ) ) if m else None
    print( s.group( 1 ) if s else "" )
elif op == "rootattrs":  # sorted attribute NAMES of the root, `schema` excluded
    print( " ".join( sorted( set( re.findall( r'([\w:.-]+)="', m.group( 2 ) ) ) - { "schema" } ) ) if m else "" )
elif op == "payload":  # the payload with the root's schema attribute removed — the byte-identity operand
    if m:   # est_tokens= on the root is the price of the EMITTED bytes — a smaller legend is a smaller price, not a row change
        tag = m.group( 0 ); pay = pay.replace( tag, re.sub( r'\sest_tokens="[0-9]*"', "", re.sub( r'\sschema="[^"]*"', "", tag ) ), 1 )
    sys.stdout.write( pay )
elif op == "legend":   sys.stdout.write( "".join( leg ) )
elif op == "prose":    # PROSE legend bytes: comments this document carries that the FULL document (argv[3]) does not carry
    full = open( sys.argv[3], encoding = "utf-8", errors = "replace" ).read()
    fleg, _ = split( full ); fset = set( fleg )
    print( sum( len( x ) for x in leg if x not in fset ) )
elif op == "headattrs":  # attribute names on the root and its first child (where the completeness terms are read)
    names = set( re.findall( r'([\w:.-]+)="', m.group( 2 ) ) ) if m else set()
    if m:
        rest = pay[ m.end(): ]
        c = re.match( r"\s*<([A-Za-z][\w:.-]*)((?:\s+[\w:.-]+=\"[^\"]*\")*)\s*/?>", rest )
        if c: names |= set( re.findall( r'([\w:.-]+)="', c.group( 2 ) ) )
    print( " ".join( sorted( names ) ) )
elif op == "isxml":    # an XML document: a root element (not <html>) with an attribute or a child, after optional comments
    print( "1" if m and m.group( 1 ) not in ( "html", "br" ) and re.match( r"\s*(<!--.*?-->\s*)*<[A-Za-z]", buf, re.S ) else "0" )
PY
leg(){ python3 "$TMP/leg.py" "$@"; }
# M1: a batch document carries whole SUB-ANSWERS inside CDATA, and each of those has a legend of its own.
# The splitter above calls a CDATA section payload (correct in general — CDATA is data), so a batch has to
# be flattened before the legend/payload question means anything one level down. Removing only the section
# MARKERS is exactly right here: batchText escapes any interior "]]>" as "]]]]><![CDATA[>", so the flattened
# text is the concatenation of the sub-answers verbatim, which is what the comparison wants.
# M1: a batch document carries whole SUB-ANSWERS inside CDATA, each with a legend of its own. The splitter
# above calls a CDATA section payload (correct in general — CDATA is data), so a batch has to be flattened
# before the legend/payload question means anything one level down. Removing only the section MARKERS is
# exactly right: batchText escapes any interior "]]>" as "]]]]><![CDATA[>", so the flattened text is the
# sub-answers verbatim. The two attributes normalised away are the SAME two leg.py's `payload` op normalises
# on a single document root, applied to every root here because a flattened batch has one per sub-answer:
# schema= is the compact dialect's own id, and est_tokens= prices the EMITTED bytes, so a smaller legend is
# a smaller price rather than a row change. Everything else must match byte for byte.
cat > "$TMP/unwrap.py" <<'PY'
import sys, re
t = open( sys.argv[1], encoding = "utf-8", errors = "replace" ).read()
t = t.replace( "]]]]><![CDATA[>", "]]>" ).replace( "<![CDATA[", "" ).replace( "]]>", "" )
t = re.sub( r'\sschema="[^"]*"', "", t )
t = re.sub( r'\sest_tokens="[0-9]*"', "", t )
sys.stdout.write( t )
PY
unwrapCdata(){ python3 "$TMP/unwrap.py" "$1" > "$2"; }

# ── a tmp git fixture: test/fixture's files with three commits, so the git verbs answer too ─────────────
REPO="$TMP/repo"; mkdir -p "$REPO"; cp -R "$FIX"/. "$REPO"/
( cd "$REPO" && git init -q && git config user.email "t@example.com" && git config user.name "t" \
  && git add -A && git commit -q -m "one" \
  && printf '\n// two\n' >> geometry.cpp && git commit -q -am "two" \
  && printf '\n// three\n' >> geometry.cpp && git commit -q -am "three" ) || { echo "fixture git setup failed"; exit 2; }
printf 'at distance (geometry.cpp:5)\n' > "$TMP/trace.txt"
printf 'callers: distance\nuses: distance\n' > "$TMP/batch.txt"
rrun(){ ( cd "$REPO" && "$BIN" . "$@" 2>"$TMP/rerr" ); }

# THE ONE INGEST (see the header block above): both roots parsed once, here, into this gate's private
# TMPDIR cache. Placed after the git fixture is built so the blob is keyed to the tree the arms actually
# probe. A failure to warm is NOT fatal — the arms below still answer, just cold — so this never turns a
# cache problem into a false red about the legend; the arms themselves are what report.
"$BIN" "$FIX" >/dev/null 2>&1 || true
( cd "$REPO" && "$BIN" . >/dev/null 2>&1 ) || true

echo "=== (A) the original four: default == --legend=full; schema ids; shrink; completeness attributes ==="
run --for='geometry distance' >"$TMP/for.default"
run --for='geometry distance' --legend=full >"$TMP/for.full"
run --grep=distance --grep-in=any >"$TMP/grep.default"
run --grep=distance --grep-in=any --legend=full >"$TMP/grep.full"
if diff -q "$TMP/for.default" "$TMP/for.full" >/dev/null && diff -q "$TMP/grep.default" "$TMP/grep.full" >/dev/null; then
    ok 'default == explicit --legend=full for --for and --grep'
else
    no 'explicit --legend=full changed default output'
fi
run --for='geometry distance' --legend=compact >"$TMP/for.compact"; rc_for=$?
run --grep=distance --grep-in=any --legend=compact >"$TMP/grep.compact"; rc_grep=$?
run --regex='dist.*' --legend=compact >"$TMP/regex.compact"; rc_regex=$?
if [ "$rc_for" -eq 0 ] && grep -q '<ctx[^>]* schema="ripwire.for/v1"' "$TMP/for.compact"; then
    ok '--for compact legend carries stable ripwire.for/v1 schema id'
else
    no '--for compact legend missing/refused ripwire.for/v1 schema id'
fi
if [ "$rc_grep" -eq 0 ] && [ "$rc_regex" -eq 0 ] \
    && grep -q '<grep[^>]* schema="ripwire.grep/v1"' "$TMP/grep.compact" \
    && grep -q '<grep[^>]* schema="ripwire.grep/v1"' "$TMP/regex.compact"; then
    ok '--grep/--regex compact legends share stable ripwire.grep/v1 schema id'
else
    no '--grep/--regex compact legends missing/refused ripwire.grep/v1 schema id'
fi
for_kind_bytes="$( wc -c <"$TMP/for.default" | tr -d ' ' ) $( wc -c <"$TMP/for.compact" | tr -d ' ' )"
grep_kind_bytes="$( wc -c <"$TMP/grep.default" | tr -d ' ' ) $( wc -c <"$TMP/grep.compact" | tr -d ' ' )"
if set -- $for_kind_bytes; [ "$2" -lt "$1" ]; then ok "--for compact is smaller ($2 < $1 bytes)"; else no "--for compact did not shrink ($2 >= $1 bytes)"; fi
if set -- $grep_kind_bytes; [ "$2" -lt "$1" ]; then ok "--grep compact is smaller ($2 < $1 bytes)"; else no "--grep compact did not shrink ($2 >= $1 bytes)"; fi
grep -q '<grep[^>]* complete="1"' "$TMP/grep.compact" \
    && grep -q '<grep[^>]* hits_capped="0"' "$TMP/grep.compact" \
    && grep -q '<grep[^>]* root="' "$TMP/grep.compact" \
    && ok 'compact literal keeps completeness, collection-floor and root/path facts' \
    || no 'compact literal hid completeness, collection-floor or root/path facts'
run --grep=distance --grep-in=any --limit=1 --legend=compact >"$TMP/grep.page"
if grep -q '<grep[^>]* shown="1"[^>]* capped="1"' "$TMP/grep.page" && ! grep -q '<grep[^>]* complete="1"' "$TMP/grep.page"; then
    ok 'compact paged grep keeps truncation and withholds false completeness'
else
    no 'compact paged grep lost truncation or fabricated completeness'
fi
if grep -q '<grep[^>]* hits_capped="0"' "$TMP/regex.compact" && ! grep -q '<grep[^>]* complete="1"' "$TMP/regex.compact"; then
    ok 'compact regex keeps floor disclosure and makes no completeness claim'
else
    no 'compact regex lost floor disclosure or fabricated completeness'
fi
if grep -q '<ctx[^>]* bundle="compact" bodies="0" reason="compact-route"' "$TMP/for.compact" \
    && grep -q '<sigs' "$TMP/for.compact" && grep -q '<hops[^>]* total="' "$TMP/for.compact"; then
    ok 'compact --for keeps bundle reason and listing disclosure attributes'
else
    no 'compact --for hid bundle reason or listing disclosure attributes'
fi
run --for='geometry distance' --legend=compact >"$TMP/for.compact.2"
run --grep=distance --grep-in=any --legend=compact >"$TMP/grep.compact.2"
if diff -q "$TMP/for.compact" "$TMP/for.compact.2" >/dev/null && diff -q "$TMP/grep.compact" "$TMP/grep.compact.2" >/dev/null; then
    ok 'compact legends are deterministic'
else
    no 'compact legend output is nondeterministic'
fi
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/for.compact" "$TMP/grep.compact" "$TMP/regex.compact" "$TMP/grep.page" >/dev/null 2>&1; then
        ok 'compact legend documents are well-formed XML'
    else
        no 'compact legend document is malformed XML'
    fi
fi

echo
echo "=== (R) refusal — re-pinned to P1's contract: a NON-XML verb refuses compact, naming the flag ==="
# Before P1 this arm asserted that --callers refused compact (the "for/grep/regex/slice only" sentence).
# P1 made --callers a member; the refusal contract now belongs to the verbs with nothing to compact.
for v in --situ --recall=geometry --report --mermaid --plan-lanes=2; do
    rrun $v --legend=compact >"$TMP/bad.out"; rc_bad=$?
    if [ "$rc_bad" -ne 0 ] && [ ! -s "$TMP/bad.out" ] && grep -q -- '--legend' "$TMP/rerr"; then
        ok "(R) $v --legend=compact refuses (exit $rc_bad, empty stdout, stderr names --legend)"
    else
        no "(R) $v --legend=compact: exit=$rc_bad stdout=$( wc -c <"$TMP/bad.out" | tr -d ' ' )B stderr=[$( head -c 120 "$TMP/rerr" | tr '\n' ' ' )]"
    fi
done

echo
echo "=== (U) UNIVERSE — every flag in src/cli.h: XML at defaults ⇒ compact honored; else ⇒ compact refused ==="
UNIV="$TMP/universe.tsv"
python3 "$ROOT/test/flaguniverse.py" "$ROOT/src/cli.h" > "$UNIV"
UROWS="$( grep -c . "$UNIV" )"
[ "$UROWS" -ge 190 ] && ok "(U) derived $UROWS flag rows from src/cli.h" \
                     || no "(U) only $UROWS rows derived — the scrape broke, so the sweep below asserts nothing"
# probe values on the fixture; a flag that WRITES (cache/index/notes/baseline/ack/edit/export) or serves
# (mcp/listen) or execs (run-trace) is not probed; --help/--version print usage by contract.
probeFor()
{
    case "$1" in
        --help|--version|--mcp|--listen=|--mcp-token=|--allow-remote-edits|--refetch) return 1 ;;
        --cache=|--index-out=|--pin-census=|--note-add=|--export=|--quality-baseline|--quality-ack=|--quality-ack|--ack-only=) return 1 ;;
        --replace-symbol-body=|--insert-after-symbol=|--insert-before-symbol=|--edit-payload=|--edit-plan=|--edit-target-file=|--run-trace=|--baseline|--baseline-update|--arch=|--scan-skill=|--scan-skills=|--lint-rules=) return 1 ;;
        --eval|--eval-retrieval|--eval=knownitem|--eval=*|--eval-skills|--eval-mined=|--eval-stray=|--doctor|--wrap) return 1 ;;
        --for=)            printf '%s' '--for=geometry' ;;
        --pack-task=)      printf '%s' '--pack-task=geometry' ;;
        --task=)           printf '%s' '--task=geometry' ;;
        --callers=|--callees=|--impact=|--uses=|--edit-check=|--safe-delete=|--slice=|--whereis=|--mentions=|--around=|--expand=|--owners=|--exemplar=)
                           printf '%s' "${1}distance" ;;
        --lego=|--field-affinity=|--layout=) printf '%s' "${1}Point" ;;
        --path=)           printf '%s' '--path=total_area,distance' ;;
        --connect=)        printf '%s' '--connect=total_area,distance,perimeter' ;;
        --verify=)         printf '%s' '--verify=calls(total_area,distance)' ;;
        --graph-query=)    printf '%s' '--graph-query=callers(distance)' ;;
        --affected=|--test-gate=|--situ=|--cochange=|--outline=) printf '%s' "${1}geometry.cpp" ;;
        --at=)             printf '%s' '--at=geometry.cpp:5' ;;
        --exercises=)      printf '%s' '--exercises=app.py' ;;
        --dead-code=|--doc-drift=|--scope=) printf '%s' "${1}." ;;
        --quality-delta=|--dmm=|--pr-context=|--stray-content=|--abi=) printf '%s' "${1}HEAD~1" ;;
        --merge-scout=)    printf '%s' '--merge-scout=HEAD~1,HEAD~2' ;;
        --from-trace=)     printf '%s' "--from-trace=$TMP/trace.txt" ;;
        --batch=)          printf '%s' "--batch=$TMP/batch.txt" ;;
        --plan-lint=)      printf '%s' "--plan-lint=$REPO/notes.md" ;;
        --grep=)           printf '%s' '--grep=distance' ;;
        --regex=)          printf '%s' '--regex=dist.*' ;;
        --match=)          printf '%s' '--match=(function_definition) @f' ;;
        --pattern=)        printf '%s' '--pattern=distance' ;;
        --query=)          printf '%s' '--query=distance' ;;
        --recall=)         printf '%s' '--recall=geometry' ;;
        --help-task=)      printf '%s' '--help-task=who calls distance' ;;
        --flags=)          printf '%s' '--flags=NDEBUG' ;;
        --community=)      printf '%s' '--community=0' ;;
        --order=)          printf '%s' '--order=stable' ;;
        --rank-by=)        printf '%s' '--rank-by=churn' ;;
        --format=)         printf '%s' '--format=columnar' ;;
        --color-by=)       printf '%s' '--color-by=lang' ;;
        --grep-scope=)     printf '%s' '--grep-scope=file' ;;
        --grep-in=)        printf '%s' '--grep-in=any' ;;
        --legend=)         return 1 ;;                       # the flag under test rides every probe
        --slice-flow=)     printf '%s' '--slice-flow=back' ;;
        --agent=)          printf '%s' '--agent=codex' ;;
        --quality-panel=)  printf '%s' '--quality-panel=default' ;;
        --token-budget=)   printf '%s' '--token-budget=3000' ;;
        --limit=)          printf '%s' '--limit=3' ;;
        --offset=)         printf '%s' '--offset=1' ;;
        --max-file-size=)  printf '%s' '--max-file-size=1M' ;;
        --pack-budget-bytes=) printf '%s' '--pack-budget-bytes=1000' ;;
        --since=)          printf '%s' '--since=2020-01-01' ;;
        --exclude=)        printf '%s' '--exclude=sub' ;;
        --with-profile=)   printf '%s' '--with-profile=geometry.cpp' ;;
        --flip=)           printf '%s' '--flip=NDEBUG' ;;
        --html=)           return 1 ;;                       # writes a file
        --and=|--not=)     printf '%s' "${1}area" ;;
        --brief=)          printf '%s' '--brief=geometry' ;;
        --lint-select=)    printf '%s' '--lint-select=cache-' ;;
        --lint-ignore=)    printf '%s' '--lint-ignore=naming-' ;;
        --max-tokens=)     printf '%s' '--max-tokens=500' ;;
        *=)                printf '%s' "${1}zzqq9" ;;
        *)                 printf '%s' "$1" ;;
    esac
}
# PER-VERB PINS (owner decision 2026-09-12: per-verb pins that fit honest definitions, docs/METHODOLOGY.md §9: honesty lives in
# attributes, the ceiling is a constraint). One 400 B ceiling held every verb until the fourth sweep, and three sweeps stopped on it
# with attributes still undefined. Each schema's pin is its LARGEST measured (U) probe on this gate's fixture, rounded up to the
# next multiple of 10 B, plus 10 B, so a verb whose legend grows is re-pinned in the commit that adds the bytes, with the bytes
# attributed there. A schema with no row FAILS: a new XML verb is measured and pinned, never waved through under a default.
# --for keeps its native dialect and is exempt (below).
# ONE ROW PER SCHEMA: the pin, then the largest (U) probe it was measured from. Measured 2026-09-12 in the fourth sweep's last
# pass, once every attribute the --impact, --safe-delete, --communities, --community and map-header answers print had a reading;
# re-measured the same day after that sweep's design review corrected three readings, added the present-only <s tested=> reading
# (no probe on this fixture prints one) and shortened fourteen readings without losing accuracy. Ten pins moved down.
# Re-measured at the lane's end, (D36): pack-task 327 -> 804 B (its purpose line spells the bundle's own vocabulary, and the
# <d r= cx= ccx= in=> and route= readings ride its rows) and from-trace 290 -> 445 B (the same four <d> readings); no other schema moved.
# schema                      pin  measured
PIN_TABLE='
ripwire.map/v1                   810   799
ripwire.map-diff/v1              800   789
ripwire.pack-signatures/v1       680   663
ripwire.metrics/v1               720   702
ripwire.deps/v1                  260   245
ripwire.hotspots/v1              280   264
ripwire.clones/v1                290   280
ripwire.readability/v1           240   224
ripwire.nonlocal-state/v1        360   344
ripwire.ensemble/v1              280   261
ripwire.context-ratio/v1         250   240
ripwire.quality-panel/v1         290   271
ripwire.naming-calibration/v1    220   206
ripwire.naming-consistency/v1    280   261
ripwire.comment-coherence/v1     260   241
ripwire.cochange/v1              290   271
ripwire.communities/v1           820   807
ripwire.zoom/v1                  410   394
ripwire.tree/v1                  250   238
ripwire.seams/v1                 380   365
ripwire.handoff/v1               340   325
ripwire.test-gate/v1             410   400
ripwire.field-affinity/v1        320   304
ripwire.skipped/v1               210   195
ripwire.lint/v1                  250   240
ripwire.lint-catalog/v1          140   124
ripwire.external-surface/v1      190   171
ripwire.scan-skills/v1           160   147
ripwire.owners/v1                220   207
ripwire.dead-code/v1             310   297
ripwire.quality-delta/v1         230   212
ripwire.dmm/v1                   200   189
ripwire.pr-context/v1            410   399
ripwire.stray-content/v1         190   179
ripwire.flags/v1                 170   159
ripwire.doc-drift/v1             220   205
ripwire.notes/v1                 150   135
ripwire.path/v1                  280   263
ripwire.connect/v1               410   392
ripwire.impact/v1                780   770
ripwire.mentions/v1              180   168
ripwire.affected/v1              350   339
ripwire.verify/v1                330   316
ripwire.help-task/v1             170   153
ripwire.query/v1                 630   611
ripwire.grep/v1                  360   345
ripwire.match/v1                 270   260
ripwire.lego/v1                  290   275
ripwire.exemplar/v1              250   232
ripwire.around/v1                780   760
ripwire.callers/v1               330   317
ripwire.callees/v1               380   369
ripwire.uses/v1                  290   271
ripwire.batch/v1                 160   142
ripwire.safe-delete/v1           720   708
ripwire.at/v1                    180   161
ripwire.from-trace/v1            460   445
ripwire.plan-lint/v1             170   156
ripwire.merge-scout/v1           220   208
ripwire.whereis/v1               240   223
ripwire.community/v1             730   719
ripwire.layout/v1                160   149
ripwire.pack-task/v1             880   865
ripwire.pack-top-n/v1            660   649
ripwire.expand/v1                280   265
'
pinFor()
{
    printf '%s\n' "$PIN_TABLE" | awk -v schema="$1" '$1 == schema { printf "%s", $2; exit }'
}
nXml=0; nXmlBad=0; nRefuse=0; nSkip=0; loopBytes=0; xmlVerbs=""
while IFS="$( printf '\t' )" read -r flag kind example policy; do
    [ -n "$flag" ] || continue
    case "$kind" in int) probe="${flag}3" ;; *) probe="$( probeFor "$flag" )" || { nSkip=$(( nSkip + 1 )); continue; } ;; esac
    ( cd "$REPO" && "$BIN" . "$probe" >"$TMP/u.full" 2>"$TMP/u.fullerr" </dev/null ); rcFull=$?
    isxml="$( leg isxml "$TMP/u.full" )"
    if [ "$isxml" != "1" ]; then
        # not an XML answer (a refusal, text, JSON, html): compact must refuse — or, when the default itself
        # refused, refuse for its own reason (compact must not turn a refusal into an answer)
        ( cd "$REPO" && "$BIN" . "$probe" --legend=compact >"$TMP/u.c" 2>"$TMP/u.cerr" </dev/null ); rcC=$?
        if [ "$rcC" -ne 0 ] && [ ! -s "$TMP/u.c" ]; then
            nRefuse=$(( nRefuse + 1 ))
        else
            no "(U) $probe: not XML at defaults (exit=$rcFull) yet --legend=compact exited $rcC with $( wc -c <"$TMP/u.c" | tr -d ' ' ) B on stdout"
        fi
        continue
    fi
    nXml=$(( nXml + 1 )); name="${flag%%=*}"; xmlVerbs="$xmlVerbs $name"
    ( cd "$REPO" && "$BIN" . "$probe" --legend=compact >"$TMP/u.c" 2>"$TMP/u.cerr" </dev/null ); rcC=$?
    if [ "$rcC" -ne "$rcFull" ] || [ ! -s "$TMP/u.c" ]; then
        no "(U) $probe --legend=compact: exit $rcC (full: $rcFull), $( wc -c <"$TMP/u.c" | tr -d ' ' ) B — stderr=[$( head -c 140 "$TMP/u.cerr" | tr '\n' ' ' )]"
        nXmlBad=$(( nXmlBad + 1 ))
        continue
    fi
    schema="$( leg schema "$TMP/u.c" )"
    lb="$( leg prose "$TMP/u.c" "$TMP/u.full" )"; lball="$( leg bytes "$TMP/u.c" )"; lbfull="$( leg bytes "$TMP/u.full" )"
    case "$schema" in ripwire.*/v1) ;; *) no "(U) $probe compact root has no schema=\"ripwire.<key>/v1\" (got '$schema')" ;; esac
    case "$flag" in
        --for=) [ "$lb" -lt "$lbfull" ] || no "(U) --for compact legend ($lb B) did not shrink vs full ($lbfull B)" ;;   # native dialect, data in its comments (A10) — registered follow-up
        *)      pin="$( pinFor "$schema" )"
                if [ -z "$pin" ]; then
                    no "(U) $probe answers $schema, which has no per-verb pin: measure its compact PROSE legend ($lb B here) and pin it in pinFor"
                elif [ "$lb" -gt "$pin" ]; then
                    no "(U) $probe compact PROSE legend is $lb B (> its $pin B pin for $schema; all comments $lball B, full $lbfull B): $( leg legend "$TMP/u.c" | head -c 200 )"
                fi ;;
    esac
    [ "$lball" -lt "$lbfull" ] || [ "$lbfull" -eq 0 ] || no "(U) $probe compact comments ($lball B) are not smaller than the full dialect's ($lbfull B)"
    fa="$( leg rootattrs "$TMP/u.full" )"; ca="$( leg rootattrs "$TMP/u.c" )"
    [ "$fa" = "$ca" ] || no "(U) $probe root attribute set moved under compact: full=[$fa] compact=[$ca]"
    leg payload "$TMP/u.full" >"$TMP/u.fullpay"; leg payload "$TMP/u.c" >"$TMP/u.cpay"
    # --for's NATIVE compact dialect (pre-P1) also trims doc bodies and re-stamps <sigs shown= total= capped=>
    # — a payload change this layer never makes; recorded in lane-L7.md as found-not-fixed, exempt here by name.
    # M1 RE-PIN (terminality round A, 2026-09-05): --batch joins --for as a named exemption from the
    # BYTE-IDENTICAL payload arm, and for a reason that is the opposite of --for's. This splitter calls a
    # CDATA section payload — correctly, because CDATA is data — but a batch's CDATA holds whole SUB-ANSWERS,
    # each with a legend of its own, and the compact posture now reaches them (mcpverbs.h
    # applyCompactToBatchSubs: measured on this fixture, uses+slice, 8,840 B full -> 2,282 B compact, where
    # compacting only the envelope reached 8,645 B). So the bytes that moved inside the CDATA are LEGEND at
    # one level down, and no splitter that treats CDATA atomically can say so. The property is not dropped:
    # the (B) arm below re-asserts it on the batch, comparing the sub-answers' own payloads after unwrapping.
    if [ "$flag" != "--for=" ] && [ "$flag" != "--batch=" ]; then
        cmp -s "$TMP/u.fullpay" "$TMP/u.cpay" || no "(U) $probe rows are NOT byte-identical under compact: $( cmp "$TMP/u.fullpay" "$TMP/u.cpay" 2>&1 | head -c 120 )"
    fi
    # every completeness attribute the document carries is NAMED in the compact legend: the window names
    # (one reading tool-wide) anywhere in the payload; the head-scoped ones (at= on a nonlocal-state <cell>
    # row is a LINE, limit= on a skipped <f> row is a SIZE cap) on the root + first child only
    legtxt="$( leg legend "$TMP/u.c" )"
    [ "$flag" = "--for=" ] && legtxt="$legtxt $( leg legend "$TMP/u.full" )"   # --for keeps its native legend
    for a in capped shown total has_more next_offset; do
        if grep -q " $a=\"" "$TMP/u.cpay"; then
            case "$legtxt" in *"$a="*) ;; *) no "(U) $probe compact legend does not name $a= although the document carries it" ;; esac
        fi
    done
    for a in $( leg headattrs "$TMP/u.c" ); do
        # graph_unindexed joined this list with issue #66's clause-parity fix. It is INERT on this gate's
        # corpus — the fixture copy carries no file a grammar cannot read, so the attribute never appears and
        # this row never fires. Said out loud rather than left to be re-discovered: the arm that actually
        # exercises the compact reading is test/blindspotcheck.sh (F), on a corpus built to carry one. The
        # name is listed here anyway so the enumeration matches the term table, not the fixture.
        case "$a" in counts_floor|est_tokens|at|root|graph_ambiguous|graph_unresolved|graph_unindexed|hits_capped|limit|offset|over_ceiling|tier_partial) ;; *) continue ;; esac
        case "$legtxt" in *"$a="*) ;; *) no "(U) $probe compact legend does not name $a= although the root carries it" ;; esac
    done
    if command -v xmllint >/dev/null 2>&1; then
        xmllint --noout "$TMP/u.c" >/dev/null 2>&1 || no "(U) $probe compact document is malformed XML"
    fi
done < "$UNIV"
[ "$nXml" -ge 60 ] && [ "$nXmlBad" -eq 0 ] && ok "(U) $nXml XML flags answer under --legend=compact (schema id, legend within its per-verb pin, rows byte-identical, root attrs kept):$xmlVerbs" \
                   || no "(U) $nXml XML flags probed, $nXmlBad refused compact (want ≥ 60 probed, 0 refused — rows above name them):$xmlVerbs"
[ "$nRefuse" -ge 60 ] && ok "(U) $nRefuse non-XML flags refuse --legend=compact (empty stdout, non-zero exit); $nSkip write/serve/exec flags not probed" \
                      || no "(U) only $nRefuse non-XML flags refused compact (want ≥ 60)"

echo
echo "=== (F) full stays byte-identical: default == --legend=full on the new members ==="
for v in --callers=distance --edit-check=total_area --quality-delta --impact=distance --test-gate=geometry.cpp; do
    rrun $v >"$TMP/f.def"; rrun $v --legend=full >"$TMP/f.full"
    if cmp -s "$TMP/f.def" "$TMP/f.full"; then ok "(F) $v: default == --legend=full"; else no "(F) $v: explicit --legend=full changed the default output"; fi
done

echo
# RE-ANCHORED 2026-09-10 (--edit-check answer-safe window): 4,000 → 4,100 B, measured 4,056 (from 4,000-56).
# ONE term, on ONE verb: --edit-check now carries est_tokens= on its root (M11's priced-root rule — the whole
# point of the number is that a caller sees what an answer cost BEFORE guessing whether to page it), so its
# compact legend gains the 62-B est_tokens definition the term table already holds for every other priced
# verb. Attributed against a build of the parent commit: edit-check's compact legend 364 → 426 B, nothing
# else in the loop moved. Same rule the SIZE ceilings in test/mcpmanifestcheck.sh follow — a ceiling moves up
# only for a DECLARED attribute the contract obliges to define, in the commit that lands it, with its bytes
# attributed here, never for prose.
# RE-ANCHORED 2026-09-12 (the fourth sweep): 4,100 → 4,400 B, measured 4,392 (from 4,089). Owner decision 2026-09-12: per-verb
# pins that fit honest definitions (METHODOLOGY §9); the loop's pin is the next multiple of 100 B above its measured total.
# Attributed against a build of the parent merge: --impact 390 → 597 B (defs=/reaches=/radius_tested=/radius_untested=/
# importers= in its purpose line, shown_importers= as a term) and --safe-delete 328 → 424 B (its radius pair); nothing else
# in the loop moved.
# RE-ANCHORED 2026-09-12 (the fourth sweep's last pass): 4,400 → 4,900 B, measured 4,860 (from 4,392), by the same rule. Attributed
# against the previous lane build: --impact 597 → 777 B (its <f lazy=> importer-row reading) and --safe-delete 424 → 712 B (t=/p=,
# defs=, ambiguous_callers=, dead_code_candidate=); nothing else in the loop moved.
# RE-MEASURED 2026-09-12 (that sweep's design review): 4,849 B, the pin unchanged at 4,900. Attributed against the last-pass build:
# --impact 777 → 770 B (the shorter <f lazy=> reading) and --safe-delete 712 → 708 B (t= reads a match, dead_code_candidate= says
# outside); nothing else in the loop moved.
echo "=== (L) the canonical ten-verb edit loop: compact legend bill ≤ 4,900 B (29,824 B in full on the ripwire tree) ==="
loopBytes=0; fullBytes=0
for v in "--for=geometry distance" "--callers=distance" "--impact=distance" "--uses=distance" "--edit-check=total_area" \
         "--quality-delta" "--test-gate=geometry.cpp" "--affected=geometry.cpp" "--safe-delete=total_area" "--slice=total_area"; do
    rrun "$v" --legend=compact >"$TMP/l.c"; rrun "$v" >"$TMP/l.f"
    [ -s "$TMP/l.c" ] || no "(L) $v --legend=compact answered NOTHING (a refusal is not a 0 B legend): $( head -c 120 "$TMP/rerr" )"
    b="$( leg bytes "$TMP/l.c" )"; f="$( leg bytes "$TMP/l.f" )"
    loopBytes=$(( loopBytes + b )); fullBytes=$(( fullBytes + f ))
done
[ "$loopBytes" -le 4900 ] && ok "(L) ten-verb loop: $loopBytes B of compact legend (full: $fullBytes B)" \
                          || no "(L) ten-verb loop pays $loopBytes B of compact legend (> 4,900 B; full: $fullBytes B)"

echo
echo "=== (M) MCP: legend:\"compact\" on edit_check answers in ≤ 900 B on a clean tree; every XML verb takes the argument, within its per-verb legend pin ==="
mcp_call() { printf '%s\n' "$@" | ( cd "$REPO" && "$BIN" --mcp 2>/dev/null ); }
mcp_text() {   # mcp_text VERB '<json-arguments>' → the text payload, or __ERROR__:code:message
    mcp_call '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
             "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"$1\",\"arguments\":$2}}" \
        | tail -1 | python3 -c '
import sys, json
r = json.load( sys.stdin )
if "error" in r: print( "__ERROR__:" + str( r["error"].get( "code" ) ) + ":" + r["error"].get( "message", "" ) )
else: sys.stdout.write( r["result"]["content"][0]["text"] )
'
}
mcp_text edit_check '{"path":".","symbol":"total_area","legend":"compact"}' >"$TMP/m.ec"
mb="$( wc -c <"$TMP/m.ec" | tr -d ' ' )"
if grep -q '^__ERROR__' "$TMP/m.ec"; then
    no "(M) MCP edit_check legend:compact refused: $( head -c 160 "$TMP/m.ec" )"
elif [ "$mb" -le 900 ] && grep -q '<edit-check[^>]* schema="ripwire.edit-check/v1"' "$TMP/m.ec"; then
    ok "(M) MCP edit_check legend:compact = $mb B with the schema id (full legend alone was 5,127 B)"
else
    no "(M) MCP edit_check legend:compact = $mb B (want ≤ 900 with schema=\"ripwire.edit-check/v1\")"
fi
# M1 RE-PIN: this call is the FULL-legend reference the compact payload is compared against. It used to
# rely on the default BEING full; the default is compact now, so it asks for the posture it means. The
# assertion is unchanged and is still the one that matters — rows do not move between the two postures.
mcp_text edit_check '{"path":".","symbol":"total_area","legend":"full"}' >"$TMP/m.ecf"
leg payload "$TMP/m.ecf" >"$TMP/m.p1"; leg payload "$TMP/m.ec" >"$TMP/m.p2"
cmp -s "$TMP/m.p1" "$TMP/m.p2" && ok "(M) MCP edit_check rows are byte-identical under legend:compact" \
                              || no "(M) MCP edit_check rows moved under legend:compact"
mcp_text edit_check '{"path":".","symbol":"total_area","legend":"terse"}' >"$TMP/m.bad"
grep -q '^__ERROR__' "$TMP/m.bad" && ok "(M) MCP edit_check legend:\"terse\" is refused (closed set full|compact)" \
                                  || no "(M) MCP edit_check accepted legend:\"terse\" — an unknown value read as a default"
# Per-verb legend pins, the (U) rule on the MCP surface (the legend, never the whole answer, which edit_check's 900 B above bounds):
#   impact        780  measured 770 B; owner decision 2026-09-12: per-verb pins that fit honest definitions (METHODOLOGY §9)
#   uses          290  measured 271 B; owner decision 2026-09-12: per-verb pins that fit honest definitions (METHODOLOGY §9)
#   path_between  280  measured 263 B; owner decision 2026-09-12: per-verb pins that fit honest definitions (METHODOLOGY §9)
#   lego          260  measured 249 B; owner decision 2026-09-12: per-verb pins that fit honest definitions (METHODOLOGY §9)
#   exemplar      260  measured 243 B; owner decision 2026-09-12: per-verb pins that fit honest definitions (METHODOLOGY §9)
for pair in "impact:780:{\"path\":\".\",\"symbol\":\"distance\",\"legend\":\"compact\"}" \
            "uses:290:{\"path\":\".\",\"symbol\":\"distance\",\"legend\":\"compact\"}" \
            "path_between:280:{\"path\":\".\",\"from\":\"total_area\",\"to\":\"distance\",\"legend\":\"compact\"}" \
            "lego:260:{\"path\":\".\",\"type\":\"Point\",\"legend\":\"compact\"}" \
            "exemplar:260:{\"path\":\".\",\"kind\":\"fn\",\"task\":\"distance\",\"legend\":\"compact\"}"; do
    verb="${pair%%:*}"; rest="${pair#*:}"; mpin="${rest%%:*}"; args="${rest#*:}"
    mcp_text "$verb" "$args" >"$TMP/m.v"
    if grep -q '^__ERROR__' "$TMP/m.v"; then
        no "(M) MCP $verb legend:compact refused: $( head -c 160 "$TMP/m.v" )"
    elif [ "$( leg bytes "$TMP/m.v" )" -le "$mpin" ] && [ -n "$( leg schema "$TMP/m.v" )" ]; then
        ok "(M) MCP $verb legend:compact: $( leg bytes "$TMP/m.v" ) B legend (pin $mpin B), schema $( leg schema "$TMP/m.v" )"
    else
        no "(M) MCP $verb legend:compact: legend $( leg bytes "$TMP/m.v" ) B (pin $mpin B), schema '$( leg schema "$TMP/m.v" )'"
    fi
done

echo
echo "=== (N) MCP: the legend DEFAULT is COMPACT; legend:\"full\" restores it; rows never move (M1) ==="
# THE CONTRACT, and why the default moved (terminality round A, 2026-09-05; capture-audit §5a decision 3's
# registered follow-up #3). The compact dialect landed OPT-IN, which made it a feature an agent has to know
# about — and the ten-verb edit loop measured 32,684 B of full legend against 3,791 B of compact, i.e. the
# opt-in default was billing every MCP session ~7.2K tokens of prose it re-reads on every single call. A
# posture that is right for essentially every caller is a DEFAULT, not an argument; the argument is how you
# get the other one back. So on this surface `legend` absent means COMPACT, `legend:"full"` restores the
# historic full legend byte-for-byte, and `legend:"compact"` stays accepted (it is now a no-op spelling of
# the default, kept because it is in the wild and because refusing a request for what you already do is
# the worst kind of refusal).
#
# THE FAMILY, read from source, never listed here. The verbs are extracted from src/mcprefusal.h's
# kMcpVerbFields rows that declare a `legend` field — the same source of truth the server dispatches from —
# so a verb that JOINS the family without a call in this gate fails the arm rather than silently skipping
# it. That is the mcpforparitycheck precedent (read the cap from source, never re-type it).
#
# FOUR ASSERTIONS PER VERB, in this order, because each one catches a different way to get this wrong:
#   1. every posture ANSWERS (no refusal) — a default that refuses is not a default;
#   2. the DEFAULT is byte-identical to legend:"compact" — the flip actually happened, on this verb;
#   3. legend:"full" carries STRICTLY MORE legend bytes than the default — full is restorable, and is the
#      big one (an arm asserting only "different" would pass a flip that broke full instead of moving it);
#   4. the PAYLOAD is byte-identical between the two postures — the legend is the only thing that moved.
#      This is the whole promise of the dialect (compactlegend.h: rows untouched) restated at the default.
#
# RED, MEASURED, on the pre-flip binary: assertion 2 fails on all seventeen verbs
#   ("(N) analyze: the DEFAULT is not compact — default 1959 B of legend, compact 302 B" and sixteen more),
# because the default was `full` there. Assertions 1/3/4 are green on both binaries by construction, which
# is exactly why 2 is written separately rather than folded into a single "postures differ" check.
LEGEND_VERBS="$( sed -n 's/^[[:space:]]*{ "\([a-z_]*\)", *"[^"]*legend[^"]*" },.*/\1/p' "$ROOT/src/mcprefusal.h" )"
nArgs() {   # the call this gate makes for VERB, on the two-commit fixture repo above
    case "$1" in
        analyze)       printf '{"path":"."}' ;;
        lego)          printf '{"path":".","type":"Point"}' ;;
        owners)        printf '{"path":".","symbol":"distance"}' ;;
        batch)         printf '{"path":".","queries":["callers: distance","uses: distance"]}' ;;
        exemplar)      printf '{"path":".","kind":"fn","task":"distance"}' ;;
        impact)        printf '{"path":".","symbol":"distance"}' ;;
        uses)          printf '{"path":".","symbol":"distance"}' ;;
        path_between)  printf '{"path":".","from":"total_area","to":"distance"}' ;;
        connect)       printf '{"path":".","symbols":["total_area","distance"]}' ;;
        explore)       printf '{"path":".","task":"geometry distance"}' ;;
        from_trace)    printf '{"path":".","trace":"at distance (geometry.cpp:5)"}' ;;
        edit_check)    printf '{"path":".","symbol":"total_area"}' ;;
        whereis)       printf '{"path":".","symbol":"distance"}' ;;
        stray_content) printf '{"path":"."}' ;;
        flags)         printf '{"path":"."}' ;;
        doc_drift)     printf '{"path":"."}' ;;
        slice)         printf '{"path":".","symbol":"total_area"}' ;;   # 'distance' is ambiguous here, by design
        *)             printf '' ;;
    esac
}
withLegend() { printf '%s,"legend":"%s"}' "${1%\}}" "$2"; }
nVerbs=0
for verb in $LEGEND_VERBS; do
    nVerbs=$(( nVerbs + 1 ))
    a="$( nArgs "$verb" )"
    if [ -z "$a" ]; then
        no "(N) $verb declares legend in kMcpVerbFields but this gate has no call for it — a verb joined the family and the family arm cannot see it"
        continue
    fi
    mcp_text "$verb" "$a"                          >"$TMP/n.def"
    mcp_text "$verb" "$( withLegend "$a" compact )" >"$TMP/n.cmp"
    mcp_text "$verb" "$( withLegend "$a" full )"    >"$TMP/n.full"
    if grep -q '^__ERROR__' "$TMP/n.def" || grep -q '^__ERROR__' "$TMP/n.cmp" || grep -q '^__ERROR__' "$TMP/n.full"; then
        no "(N) $verb: a posture refused — default: $( head -c 90 "$TMP/n.def" ) | compact: $( head -c 90 "$TMP/n.cmp" ) | full: $( head -c 90 "$TMP/n.full" )"
        continue
    fi
    dLeg="$( leg bytes "$TMP/n.def" )"; cLeg="$( leg bytes "$TMP/n.cmp" )"; fLeg="$( leg bytes "$TMP/n.full" )"
    if ! cmp -s "$TMP/n.def" "$TMP/n.cmp"; then
        no "(N) $verb: the DEFAULT is not compact — default $dLeg B of legend, compact $cLeg B"
        continue
    fi
    if [ "$fLeg" -le "$cLeg" ]; then
        no "(N) $verb: legend:\"full\" carries $fLeg B against the default's $cLeg B — the full legend is not restorable"
        continue
    fi
    # M1: for batch, flatten the CDATA first — its sub-answers are documents whose legends the posture also
    # reaches (applyCompactToBatchSubs), so an atomic CDATA comparison would read a legend change as a row
    # change. Flattened, the assertion is the real one: every sub-answer's ROWS are identical too.
    nDef="$TMP/n.def"; nFull="$TMP/n.full"
    if [ "$verb" = "batch" ]; then
        unwrapCdata "$TMP/n.def" "$TMP/n.defu"; unwrapCdata "$TMP/n.full" "$TMP/n.fullu"
        nDef="$TMP/n.defu"; nFull="$TMP/n.fullu"
    fi
    leg payload "$nDef" >"$TMP/n.pd"; leg payload "$nFull" >"$TMP/n.pf"
    if ! cmp -s "$TMP/n.pd" "$TMP/n.pf"; then
        no "(N) $verb: the PAYLOAD moved between the two postures — the dialect must change the legend and nothing else"
        continue
    fi
    ok "(N) $verb: default == compact ($cLeg B legend), legend:\"full\" restores $fLeg B, payload byte-identical"
done
[ "$nVerbs" -ge 17 ] && ok "(N) the family was read from source: $nVerbs verbs declare legend" \
                     || no "(N) only $nVerbs verbs were extracted from kMcpVerbFields — the family read is broken, so every PASS above means nothing"

echo
echo "=== (D) CONDITIONAL attributes: a document that CARRIES one defines it under compact too (CLI, columnar, MCP default) ==="
# THE DEFECT CLASS (2026-09-12). Each attribute here is absent at zero or form-conditional, and its full-dialect clause
# rides ONLY a document that carries it: graphlegend.h declinedCallsLegend( bool ) / unprovenDefsLegend( bool ) and the
# callees-only bodyless_defs= clause inside callHierarchyLegendOpen( bool ), fielduses.h's kUsesFieldLegend (the member
# form), serialize.h multiRootTableLegend( bool ) (the <root label=> rows), and --lego's caveat= sentence. The compact
# layer strips that clause as prose and rebuilds definitions from kCompactCompletenessTerms, which had a row for NONE of
# them — so each reached a compact reader, and every MCP caller (whose default posture IS compact), as a number the
# document never defined. PR #169 fixed graph_unindexed= alone; #173's unproven_defs= repeated the miss, because nothing
# tied the helper family to the term table. Arm (S) below is that tie; these rows are the behaviour it stands for.
#
# EACH ROW, CONTROL FIRST: the attribute is CARRIED by both postures' payloads and DEFINED by the full legend. Without
# that a green compact assertion could be an answer that never carried the attribute, or a demand for a definition the
# tool never had. Then the compact legend must define it, read LEFT-ANCHORED (`defs=` is a suffix of unproven_defs= and
# bodyless_defs=, the trap test/decltodefcheck.sh records). A tag-qualified spec (root:label) reads only that element.
# RED on origin/main 28ee1df3: every (D1)..(D6) row FAILed (the red output is in the landing commit); (D7) is the mirror
# the fix must KEEP, so it is green on both binaries by construction and is written as its own row for that reason.
cat > "$TMP/condattr.py" <<'PY'
import re, sys
op, path, spec = sys.argv[1], sys.argv[2], sys.argv[3]
buf = open( path, encoding = "utf-8", errors = "replace" ).read()
legend, tags, header = [], [], []
i = 0; n = len( buf )
while i < n:
    if buf.startswith( "<![CDATA[", i ):
        j = buf.find( "]]>", i ); i = n if j < 0 else j + 3
    elif buf.startswith( "<!--", i ):
        # the map header (serialize.h buildStats, the one `<!-- files=` emitter) is DATA: a `#name` spec reads its fields,
        # and it is never a definition — else every header row would be "defined" by the very number it asks about
        j = buf.find( "-->", i ); j = n if j < 0 else j + 3
        ( header if buf.startswith( "<!-- files=", i ) else legend ).append( buf[ i:j ] ); i = j
    elif buf[ i ] == "<":
        j = buf.find( ">", i ); j = n if j < 0 else j + 1; tags.append( buf[ i:j ] ); i = j
    else:
        j = buf.find( "<", i ); i = n if j < 0 else j
isHdr = spec.startswith( "#" )   # `#name`: an UNQUOTED field of the map header, not an element attribute
tag, _, attr = ( "", "", spec[ 1: ] ) if isHdr else spec.rpartition( ":" )
def on( t ):   # a tag-qualified spec reads only that element: <root label=> is not <community label=>
    return not tag or re.match( r"<" + re.escape( tag ) + r"[\s/>]", t ) is not None
if isHdr:   # a header field's value is bare (files=6) or QUOTED (unindexed="f90:1,zzqa:1"): both spellings are read
    vals = [ m.group( 1 ) for h in header for m in [ re.search( r"\s" + re.escape( attr ) + r"=(\"[^\"]*\"|[^\s\"]+)", h ) ] if m ]
else:
    vals = [ m.group( 1 ) for t in tags if on( t ) for m in [ re.search( r"\s" + re.escape( attr ) + r"=\"([^\"]*)\"", t ) ] if m ]
leg = " ".join( legend )
if op == "carries":    print( 1 if vals else 0 )
elif op == "value":    print( vals[ 0 ] if vals else "" )
elif op == "defines":  print( 1 if re.search( r"(?<![A-Za-z0-9_])" + re.escape( attr ) + "=", leg ) else 0 )
elif op == "mentions": print( 1 if spec in leg else 0 )   # a literal needle anywhere in the legend
PY
ca(){ python3 "$TMP/condattr.py" "$@"; }
# condArm ID LABEL FULL COMPACT SPEC… — the control, then the compact definition, one verdict row per document. A spec written
# `!el:attr` skips the FULL-legend control and only that: the full dialect names the attribute as row vocabulary or not at
# all (the fourth sweep's --impact defs=, --communities' isolated_*=/shown_modules=/bridges=, --community's dir=/label=/
# bridges=), so the compact reading is the one definition a reader gets and the row asserts exactly that. Whether the full
# legend should define them too is test/legendcoveragecheck.sh's question, not this arm's.
condArm()
{
    local id="$1" label="$2" full="$3" comp="$4" spec attr bad=0 got="" needFull
    shift 4
    for spec in "$@"; do
        needFull=1
        case "$spec" in '!'*) needFull=0; spec="${spec#!}" ;; esac
        attr="${spec#*:}"; attr="${attr#\#}"
        if [ "$( ca carries "$full" "$spec" )" != 1 ] || [ "$( ca carries "$comp" "$spec" )" != 1 ]; then
            no "($id) $label: control broken — the answer does not carry $attr= in both postures, so its definition row would be vacuous: $( head -c 160 "$comp" )"
            bad=1; continue
        fi
        if [ "$needFull" -eq 1 ] && [ "$( ca defines "$full" "$attr" )" != 1 ]; then
            no "($id) $label: control broken — the FULL legend does not define $attr= either, so this row asserts nothing compact-specific"
            bad=1; continue
        fi
        if [ "$( ca defines "$comp" "$attr" )" != 1 ]; then
            no "($id) $label: $attr=\"$( ca value "$comp" "$spec" )\" is carried but the compact legend never defines it: $( leg legend "$comp" | head -c 260 )"
            bad=1; continue
        fi
        got="$got $attr="
    done
    [ "$bad" -eq 0 ] && ok "($id) $label: carried, and defined by the compact legend:$got"
    return 0
}
cdRun(){ local out="$1" dir="$2"; shift 2; ( cd "$dir" && "$BIN" . "$@" >"$out" 2>"$TMP/derr" </dev/null ); }
# condPair ID LABEL DIR "ARGS" SPEC… — one answer in both postures (ARGS word-split on purpose: no spaces in any of them)
condPair(){ local id="$1" label="$2" dir="$3" args="$4"; shift 4; cdRun "$TMP/d.full" "$dir" $args; cdRun "$TMP/d.comp" "$dir" $args --legend=compact; condArm "$id" "$label" "$TMP/d.full" "$TMP/d.comp" "$@"; }

# H1's own corpus (test/decltodefcheck.sh arm A): a/Store.h declares a putObject whose one same-named body is b::Store's,
# in a file that never includes a/Store.h — so a/Store.h:putObject is a bodyless declaration with one unproven candidate.
H1="$TMP/h1"; mkdir -p "$H1/a" "$H1/b"
printf '#pragma once\nnamespace a {\nclass Store {\npublic:\n    int putObject(int x);\n};\n}\n' >"$H1/a/Store.h"
printf '#pragma once\nnamespace b {\nclass Store {\npublic:\n    int putObject(int x);\n};\n}\n' >"$H1/b/Store.h"
printf '#include "Store.h"\nnamespace b {\nint Store::putObject(int x)\n{\n    return x + 1;\n}\n}\nint callB(int x)\n{\n    b::Store s;\n    return s.putObject(x);\n}\n' >"$H1/b/Store.cpp"
# --lego's caveat= rides a NAMED interface in a language whose method contract is not read (only C++/ObjC are).
LEGOJ="$TMP/legojava"; mkdir -p "$LEGOJ"
printf 'interface Shape {\n    double area();\n}\n' >"$LEGOJ/Shape.java"
printf 'class Circle implements Shape {\n    public double area() { return 3.0; }\n}\n' >"$LEGOJ/Circle.java"
DECL="$ROOT/test/declinefix"; FIELDS="$ROOT/test/fieldusesfix"
for d in "$DECL" "$FIELDS"; do [ -d "$d" ] || no "(D) fixture missing: $d — every row reading it would be vacuous"; done

condPair D1 "--callers=a/Store.h:putObject" "$H1" "--callers=a/Store.h:putObject" unproven_defs
condPair D2 "--callees=a/Store.h:putObject" "$H1" "--callees=a/Store.h:putObject" bodyless_defs unproven_defs
condPair D2 "--callees=a/Store.h:putObject --format=columnar" "$H1" "--callees=a/Store.h:putObject --format=columnar" bodyless_defs unproven_defs
condPair D3 "--callers=java/alpha/Alpha.java:jbody" "$DECL" "--callers=java/alpha/Alpha.java:jbody" declined_calls
condPair D3 "--callees=javaDeclined" "$DECL" "--callees=javaDeclined" declined_calls
condPair D3 "--impact=java/alpha/Alpha.java:jbody" "$DECL" "--impact=java/alpha/Alpha.java:jbody" declined_calls
condPair D3 "--impact=java/alpha/Alpha.java:jbody --format=columnar" "$DECL" "--impact=java/alpha/Alpha.java:jbody --format=columnar" declined_calls
mcp_text impact "{\"path\":\"$DECL\",\"symbol\":\"java/alpha/Alpha.java:jbody\",\"legend\":\"full\"}" >"$TMP/d.full"
mcp_text impact "{\"path\":\"$DECL\",\"symbol\":\"java/alpha/Alpha.java:jbody\"}" >"$TMP/d.comp"
condArm D3 "MCP impact at its DEFAULT posture (compact) vs legend:\"full\"" "$TMP/d.full" "$TMP/d.comp" declined_calls
condPair D4 "--uses=Counter.count (the member form)" "$FIELDS" "--uses=Counter.count" member pinned amb_sites owners_of_name u:owner_candidates
"$BIN" "$FIX" "$H1" --callers=distance >"$TMP/d.full" 2>/dev/null </dev/null
"$BIN" "$FIX" "$H1" --callers=distance --legend=compact >"$TMP/d.comp" 2>/dev/null </dev/null
condArm D5 "two roots, --callers=distance (the <root label= p=> table)" "$TMP/d.full" "$TMP/d.comp" root:label
condPair D6 "--lego=Shape (Java: no method contract read)" "$LEGOJ" "--lego=Shape" iface:caveat iface:methods

# ── THE MAP FAMILY AND --impact (2026-09-12, the second sweep of the class) ──────────────────────────────────────────
# (D1)..(D6) closed the navigation verbs. The ranked documents carried the same defect in three more shapes, each
# established by running 34a97f66 (carried, compact legend silent — the red rows are in the landing commit):
#   • THE PAGERANK DISCLOSURE (prconverge.h). Its clause rides as the map's own `<!-- pr_iters=` comment and inside the
#     verb legend of --impact and the ranked reports, prose either way — so pr_iters= reached every compact PageRank root
#     undefined (--impact is an (L) loop verb), and pr_converged="0" with it on the one document whose order is an
#     unfinished computation. That exit is unreachable by any INPUT at the shipped ceiling (test/prconvergecheck.sh
#     derives the bound), so (D9) arms it the way that gate does: RIPWIRE_TEST_PR_MAXITERS lowers the ceiling in every
#     build flavour, and --no-cache keeps the truncated ranking out of this gate's warm blob.
#   • THE MAP HEADER. `<!-- files=… -->` is DATA and compact keeps it, while the `<!-- hdr:` clauses (and the absent-if-0
#     half of `<!-- ripwire v1`) that define its gauges are prose and go — declined=17 or over_ceiling=1 stayed on the
#     page with no reading. A `#name` spec reads such a field; the data comment is never counted as its definition.
#   • FORM-CONDITIONAL MAP ROOTS: --around's defs= (only when the seed name has >1 def), --rank-by's rank_by=, churn's
#     window=. Each name is a DIFFERENT quoted attribute on other verbs (defs= on --callers, window= on --hotspots), so the
#     `r:` spec reads the map root alone, as the reading must.
IGN="$TMP/ignored"; mkdir -p "$IGN/gen"; cp -R "$FIX"/. "$IGN"/
printf 'def hidden():\n    return 1\n' >"$IGN/hidden.py"; printf 'def g():\n    return 1\n' >"$IGN/gen/g.py"; printf 'hidden.py\ngen/\n' >"$IGN/.gitignore"
( cd "$IGN" && git init -q && git config user.email "t@example.com" && git config user.name "t" && git add -A && git commit -q -m one ) >/dev/null 2>&1 \
    || no "(D10) the .gitignore fixture's git setup failed — its ignored_files=/ignored_dirs= row would be vacuous"
MHOT="$TMP/maphot"; MLEAK="$TMP/mapleak"; LPIN="$ROOT/test/lpinfix"; mkdir -p "$MHOT" "$MLEAK"
cp "$ROOT"/test/extentfix/{leak.cpp,head.c,orphan.cpp,plain.cpp} "$MHOT/" 2>/dev/null || no "(D10) fixture missing: test/extentfix"
cp "$ROOT"/test/macroreparsefix/{leak_anon.cpp,leak_plain.cpp,leak_lambda.cpp,leak_c.c,leak_objc.m,leak_cuda.cu,leak_partial.cpp} "$MLEAK/" 2>/dev/null \
    || no "(D10) fixture missing: test/macroreparsefix"
[ -d "$LPIN" ] || no "(D10) fixture missing: $LPIN — its locality_pinned= row would be vacuous"

condPair D8 "the flagless map" "$FIX" "" pr_iters
condPair D8 "--impact=distance (an (L) loop verb)" "$FIX" "--impact=distance" pr_iters
condPair D8 "--communities (a ranked report root)" "$FIX" "--communities" pr_iters
mcp_text impact "{\"path\":\"$FIX\",\"symbol\":\"distance\",\"legend\":\"full\"}" >"$TMP/d.full"
mcp_text impact "{\"path\":\"$FIX\",\"symbol\":\"distance\"}" >"$TMP/d.comp"
condArm D8 "MCP impact at its DEFAULT posture (compact) vs legend:\"full\"" "$TMP/d.full" "$TMP/d.comp" pr_iters
export RIPWIRE_TEST_PR_MAXITERS=2
condPair D9 "the flagless map under a lowered PageRank ceiling" "$FIX" "--no-cache" pr_converged pr_iters
condPair D9 "--impact=distance under a lowered PageRank ceiling" "$FIX" "--impact=distance --no-cache" pr_converged pr_iters
unset RIPWIRE_TEST_PR_MAXITERS
condPair D10 "the map over test/declinefix" "$DECL" "" "#declined" "#external"
condPair D10 "the map over test/lpinfix" "$LPIN" "" "#locality_pinned"
condPair D10 "the map over test/extentfix" "$MHOT" "" "#extent_suspect_syms"
condPair D10 "the map over test/macroreparsefix" "$MLEAK" "" "#macro_blanked_files"
condPair D10 "the map over a git tree whose .gitignore cuts a file and a subtree" "$IGN" "" "#ignored_files" "#ignored_dirs"
condPair D10 "--max-tokens=50 (the fit_bytes form)" "$FIX" "--max-tokens=50" "#max_tokens" "#fit_bytes" "#over_ceiling"
condPair D10 "--order=stable (est_tokens= rides the trailing header alone)" "$FIX" "--order=stable" "#est_tokens"
condPair D11 "--around=distance (the seed name has two defs)" "$FIX" "--around=distance" r:defs
condPair D11 "--rank-by=hub (a HITS order)" "$FIX" "--rank-by=hub" r:rank_by
condPair D11 "--rank-by=churn (a git-weighted PageRank)" "$REPO" "--rank-by=churn" r:rank_by r:window pr_iters

# (D12) THE MIRROR for those readings — present-only, on documents chosen for what they LACK, and each lack is asserted
# before it is relied on: --query=distance is a lexical order (no pr_iters=), --rank-by=hub a HITS order (rank_by= with no
# pr_iters= or window=), --around=total_area a seed with one def (no defs=), --impact=distance the loop verb with no map
# header at all, and the flagless map none of the header gauges this fixture never produces. Green on 34a97f66 by
# construction, like (D7); its failing state is shown in the landing commit on a legend with a reading spliced in.
[ "$( rrun --query=distance --legend=compact | grep -c ' pr_iters="' )" = 0 ] \
    || no "(D12) control: --query=distance now carries pr_iters=, so it no longer proves the pr_iters= reading is present-only"
rrun --rank-by=hub --legend=compact >"$TMP/d12.hub"
[ "$( ca carries "$TMP/d12.hub" r:rank_by )" = 1 ] && [ "$( ca carries "$TMP/d12.hub" r:window )" != 1 ] \
    || no "(D12) control: --rank-by=hub no longer carries rank_by= without window=, so its mirror row proves nothing"
[ "$( rrun --around=total_area --legend=compact | grep -c '<r [^>]* defs="' )" = 0 ] \
    || no "(D12) control: --around=total_area now carries defs=, so it no longer proves the defs= reading is present-only"
d12bad=0; d12n=0
for v in "" "--query=distance" "--rank-by=hub" "--around=total_area" "--impact=distance"; do
    rrun $v --legend=compact >"$TMP/d12.c"
    if [ ! -s "$TMP/d12.c" ]; then
        no "(D12) ${v:-the flagless map} --legend=compact answered nothing — its mirror row would be vacuous"; d12bad=1; continue
    fi
    d12n=$(( d12n + 1 ))
    for spec in pr_iters pr_converged "#declined" "#external" "#locality_pinned" "#extent_suspect_syms" "#macro_blanked_files" \
                "#ignored_files" "#ignored_dirs" "#max_tokens" "#fit_bytes" "#over_ceiling" r:defs r:rank_by r:window; do
        attr="${spec#*:}"; attr="${attr#\#}"
        # Since the fourth sweep (2026-09-12) --impact's purpose line reads its OWN defs=, so the map root's defs= reading is
        # found by its opener rather than its attribute name, the way (D17)/(D23) find theirs.
        if [ "$spec" = r:defs ]; then isRead="$( ca mentions "$TMP/d12.c" "the lowest-id one was walked" )"; else isRead="$( ca defines "$TMP/d12.c" "$attr" )"; fi
        if [ "$isRead" = 1 ] && [ "$( ca carries "$TMP/d12.c" "$spec" )" != 1 ]; then
            no "(D12) ${v:-the flagless map}: the compact legend defines $attr= but the document carries no $spec — a reading of a field that is not there"
            d12bad=1
        fi
    done
done
[ "$d12bad" -eq 0 ] && [ "$d12n" -eq 5 ] && ok "(D12) mirror: no map-family reading prints on $d12n answers that lack its field (lexical, HITS, one-def seed, --impact, the plain map)"

# (D7) THE MIRROR — present-only. A reading printed on a document WITHOUT its attribute is the opposite false claim, and
# these single-root answers are the (L) loop's own shapes. --communities is the row that proves the <root label=>
# reading is ELEMENT-qualified: it carries label= on every <community> row, a different attribute under the same name.
rrun --communities --legend=compact >"$TMP/d7.comm"
[ "$( ca carries "$TMP/d7.comm" community:label )" = 1 ] \
    || no "(D7) control: --communities carries no <community label=> any more, so the element-qualification row proves nothing"
d7bad=0; d7n=0
for v in "--callers=distance" "--callees=distance" "--impact=distance" "--uses=distance" "--lego=Point" "--communities"; do
    rrun "$v" --legend=compact >"$TMP/d7.c"
    if [ ! -s "$TMP/d7.c" ]; then
        no "(D7) $v --legend=compact answered nothing — its mirror row would be vacuous"; d7bad=1; continue
    fi
    d7n=$(( d7n + 1 ))
    for pair in "unproven_defs=|unproven_defs" "bodyless_defs=|bodyless_defs" "declined_calls=|declined_calls" "member=|member" "<root label=|root:label" "caveat=|caveat" \
                "pr_converged=|pr_converged"; do
        needle="${pair%%|*}"; spec="${pair#*|}"
        if [ "$( ca mentions "$TMP/d7.c" "$needle" )" = 1 ] && [ "$( ca carries "$TMP/d7.c" "$spec" )" != 1 ]; then
            no "(D7) $v: the compact legend spells '$needle' but the document carries no ${spec#*:}= — a definition of an attribute that is not there"
            d7bad=1
        fi
    done
done
[ "$d7bad" -eq 0 ] && [ "$d7n" -eq 6 ] && ok "(D7) mirror: no conditional reading prints on $d7n single-root answers that lack its attribute (incl. --communities' <community label=>)"

# ── THE THIRD SWEEP (2026-09-12): the verbs #185's last agent listed but did not fix, each RUN before any reading landed ──
# (D13) UNCONDITIONAL root vocabulary that the full legend defines and the compact document did not: --tree's files= (the
# indexed corpus, beside the files_unlisted= its purpose already named), and --zoom's symbols=/isolated=/top_modules= (the
# identity its full legend says reconciles exactly) and levels_shown=. They ride EVERY answer of their root, so each reading
# lives in that root's purpose line, where files_unlisted= and levels= already were: present exactly when the root is.
# (D14)..(D16) CONDITIONAL fields, each a present-only term: --zoom's <module children=> (only a module AT the levels_shown=
# cut, so the row lowers the cut to 1 on test/chafix, a two-level hierarchy), rank_by=churn-decay's <recent n= of=> file rows
# with <rc age_d= w=> (single-root only), and the map's absent-when-default row fields lpin=, overloads=, prov= (defined only
# inside the always-on `<!-- ripwire v1` legend). test/declinefix and test/lpinfix are (D10)'s own corpora: their maps
# carried those fields undefined while the (D10) rows passed on the header gauges alone.
# RED on 3c89ac0b: all 12 specs below FAILed, for example
#   FAIL (D13) --zoom (its root's counts): symbols="14" is carried but the compact legend never defines it
#   FAIL (D14) --zoom --zoom-levels=1 over test/chafix (modules AT the depth cut): children="2" is carried but the compact legend never defines it
#   FAIL (D15) --rank-by=churn-decay (the <recent> file rows): of="6" is carried but the compact legend never defines it
#   FAIL (D16) the map over test/declinefix (merged overloads, split edges): prov="split" is carried but the compact legend never defines it
# Stopped here on the (U) 400 B pin, and defined in the fourth sweep (D20) below once the owner raised the pins to fit honest
# definitions: --communities' drill= and isolated=.
condPair D13 "--tree (files= on its root)" "$FIX" "--tree" tree:files
condPair D13 "--zoom (its root's counts)" "$FIX" "--zoom" zoom:symbols zoom:isolated zoom:top_modules zoom:levels_shown
[ -d "$ROOT/test/chafix" ] || no "(D14) fixture missing: test/chafix — its children= row would be vacuous"
condPair D14 "--zoom --zoom-levels=1 over test/chafix (modules AT the depth cut)" "$ROOT/test/chafix" "--zoom --zoom-levels=1" module:children
condPair D15 "--rank-by=churn-decay (the <recent> file rows)" "$REPO" "--rank-by=churn-decay" recent:of rc:age_d rc:w
condPair D16 "the map over test/declinefix (merged overloads, split edges)" "$DECL" "" s:overloads c:prov
condPair D16 "the map over test/lpinfix (a locality-pinned call)" "$LPIN" "" s:lpin

# (D17) THE MIRROR for those readings, on answers chosen for what they LACK, each lack asserted before it is relied on:
# --around=distance carries of= on its <r> root (the seed) and no <recent>; --rank-by=churn is the sibling ranker with no
# <recent>; --zoom on this fixture has ONE level, so no module sits at a cut; the flagless map here has no merged overload,
# split edge or pinned call; and --communities carries isolated=/symbols= on ITS root, which must not pull in --zoom's
# identity. The needles are the readings' own openers, so a reading printed on the wrong document is caught however its
# NAME is spelled elsewhere in that legend (of= is a word of --around's own purpose line). Green on 3c89ac0b by
# construction, like (D7)/(D12). Its failing state: with a reading spliced into four real compact legends from the fix
# (<recent n= of=> into --around, children= into --zoom, prov= into the map, --zoom's identity into --communities), this
# check fired on all four, and on none of the unspliced four (landing commit).
[ "$( rrun --around=distance --legend=compact | grep -c '<r [^>]* of="' )" -ge 1 ] \
    || no "(D17) control: --around=distance carries no <r of=> any more, so it no longer proves the <recent of=> reading is element-qualified"
[ "$( rrun --zoom --legend=compact | grep -c ' children="' )" = 0 ] \
    || no "(D17) control: --zoom on this fixture now carries children=, so it no longer proves the children= reading is present-only"
d17bad=0; d17n=0
for v in "--around=distance" "--rank-by=churn" "--zoom" "" "--communities"; do
    rrun $v --legend=compact >"$TMP/d17.c"
    if [ ! -s "$TMP/d17.c" ]; then
        no "(D17) ${v:-the flagless map} --legend=compact answered nothing — its mirror row would be vacuous"; d17bad=1; continue
    fi
    d17n=$(( d17n + 1 ))
    for pair in "children=K:@module:children" "<recent n= of=>@recent:of" "lpin=K:@lpin" "overloads=N:@overloads" "prov=scip@c:prov" \
                "symbols= = isolated=@zoom:top_modules" "of files= indexed@tree:files"; do
        needle="${pair%%@*}"; spec="${pair#*@}"
        if [ "$( ca mentions "$TMP/d17.c" "$needle" )" = 1 ] && [ "$( ca carries "$TMP/d17.c" "$spec" )" != 1 ]; then
            no "(D17) ${v:-the flagless map}: the compact legend spells '$needle' but the document carries no ${spec#*:}= — a reading of a field that is not there"
            d17bad=1
        fi
    done
done
[ "$d17bad" -eq 0 ] && [ "$d17n" -eq 5 ] && ok "(D17) mirror: no third-sweep reading prints on $d17n answers that lack its field (--around's <r of=>, churn, a one-level zoom, the plain map, --communities' isolated=/symbols=)"

# ── THE FOURTH SWEEP (2026-09-12): the vocabulary the earlier sweeps stopped on at the byte pins ─────────────────────────
# Owner decision 2026-09-12: per-verb pins that fit honest definitions (docs/METHODOLOGY.md §9 — honesty lives in attributes,
# the ceiling is a constraint). Each attribute below rides EVERY answer of its document, and was defined by prose if at all:
#   (D18) the map header's unresolved= (serialize.h buildStats writes it unconditionally; the always-on legend's
#         hdr:unresolved= clause defines it), read from the header ALONE: --from-trace's <trace unresolved=> is a frame count;
#   (D19) --impact's defs=, reaches=, importers=, shown_importers=, radius_tested=, radius_untested= on the XML form, the
#         columnar form (which omits shown_importers= and names the omission in lens=) and the MCP default;
#   (D20) --communities' drill=, isolated= and its isolated_decl=/isolated_header=/isolated_source=/isolated_doc= split,
#         shown_modules=, bridges= (<zoom isolated=> and <seams bridges=> count other things);
#   (D21) --community=ID's dir=, label=, bridges=, partition=, modules= (<communities modules=/bridges=>, <seams modules=> are
#         other roots' attributes);
#   (D22) --safe-delete's radius_tested=/radius_untested=, which partition impact_reaches= where --impact's partition reaches=.
# A `!` spec is one the FULL legend does not define either (condArm's comment): --impact's defs=, the isolated_* split,
# shown_modules=, --communities' bridges= (its full legend spells bridge=), --community's dir=/label=/bridges=.
condPair D18 "the flagless map (unresolved= on its header)" "$FIX" "" "#unresolved"
condPair D18 "--max-tokens=50 (the header beside a fit-cut root)" "$FIX" "--max-tokens=50" "#unresolved"
condPair D19 "--impact=distance" "$FIX" "--impact=distance" '!impact:defs' impact:reaches impact:importers impact:shown_importers impact:radius_tested impact:radius_untested
condPair D19 "--impact=distance --format=columnar" "$FIX" "--impact=distance --format=columnar" '!impact:defs' impact:reaches impact:importers impact:radius_tested impact:radius_untested
mcp_text impact "{\"path\":\"$FIX\",\"symbol\":\"distance\",\"legend\":\"full\"}" >"$TMP/d.full"
mcp_text impact "{\"path\":\"$FIX\",\"symbol\":\"distance\"}" >"$TMP/d.comp"
condArm D19 "MCP impact at its DEFAULT posture (compact) vs legend:\"full\"" "$TMP/d.full" "$TMP/d.comp" '!impact:defs' impact:reaches impact:importers impact:shown_importers impact:radius_tested impact:radius_untested
condPair D20 "--communities (its root's counts)" "$FIX" "--communities" communities:drill communities:isolated '!communities:isolated_decl' '!communities:isolated_header' \
    '!communities:isolated_source' '!communities:isolated_doc' '!communities:shown_modules' '!communities:bridges'
condPair D21 "--community=0 (its root's counts and names)" "$FIX" "--community=0" community:partition community:modules '!community:dir' '!community:label' '!community:bridges'
condPair D22 "--safe-delete=total_area (its root's radius partition)" "$FIX" "--safe-delete=total_area" safe-delete:radius_tested safe-delete:radius_untested

# (D23) THE MIRROR, on answers chosen for what they LACK, each lack asserted before it is relied on. The needles are the
# readings' own openers, so a reading printed on the wrong document is caught however its NAME is spelled there: --from-trace
# carries <trace unresolved=> and no map header; the columnar --impact carries no shown_importers= (the one present-only term
# here); --safe-delete carries radius_tested= over impact_reaches= and no <impact>; --zoom carries an isolated= of its own;
# --seams carries modules=/bridges= of its own; --community=0 carries its own bridges= and no drill=; --communities carries its
# own bridges= and no partition=; the plain map carries none of these roots.
rrun --from-trace="$TMP/trace.txt" --legend=compact >"$TMP/d23.trace"
[ "$( ca carries "$TMP/d23.trace" trace:unresolved )" = 1 ] && [ "$( ca carries "$TMP/d23.trace" "#unresolved" )" != 1 ] \
    || no "(D23) control: --from-trace no longer carries <trace unresolved=> without a map header, so it proves nothing about the header-only read"
rrun --impact=distance --format=columnar --legend=compact >"$TMP/d23.col"
[ "$( ca carries "$TMP/d23.col" impact:reaches )" = 1 ] && [ "$( ca carries "$TMP/d23.col" impact:shown_importers )" != 1 ] \
    || no "(D23) control: the columnar --impact no longer carries reaches= without shown_importers=, so it proves nothing about that term being present-only"
rrun --safe-delete=total_area --legend=compact >"$TMP/d23.sd"
[ "$( ca carries "$TMP/d23.sd" safe-delete:radius_tested )" = 1 ] && [ "$( ca carries "$TMP/d23.sd" impact:reaches )" != 1 ] \
    || no "(D23) control: --safe-delete carries no radius_tested= (or now an <impact reaches=>), so it no longer proves the two partitions read apart"
rrun --zoom --legend=compact >"$TMP/d23.zoom"
[ "$( ca carries "$TMP/d23.zoom" zoom:isolated )" = 1 ] \
    || no "(D23) control: --zoom carries no isolated= any more, so it no longer proves the communities reading is element-qualified"
rrun --seams --legend=compact >"$TMP/d23.seams"
[ "$( ca carries "$TMP/d23.seams" seams:modules )" = 1 ] && [ "$( ca carries "$TMP/d23.seams" seams:bridges )" = 1 ] \
    || no "(D23) control: --seams carries no modules=/bridges= any more, so it no longer proves the module readings are element-qualified"
rrun --community=0 --legend=compact >"$TMP/d23.one"
[ "$( ca carries "$TMP/d23.one" community:bridges )" = 1 ] && [ "$( ca carries "$TMP/d23.one" communities:drill )" != 1 ] \
    || no "(D23) control: --community=0 no longer carries its bridges= without a drill=, so it proves nothing about the two roots reading apart"
d23bad=0; d23n=0
for v in "--from-trace=$TMP/trace.txt" "--impact=distance --format=columnar" "--safe-delete=total_area" "--impact=distance" "--zoom" "--seams" \
         "--communities" "--community=0" ""; do
    rrun $v --legend=compact >"$TMP/d23.c"
    if [ ! -s "$TMP/d23.c" ]; then
        no "(D23) ${v:-the flagless map} --legend=compact answered nothing — its mirror row would be vacuous"; d23bad=1; continue
    fi
    d23n=$(( d23n + 1 ))
    for pair in "unresolved= calls with in-tree evidence@#unresolved" "reaches= their transitive callers@impact:reaches" "shown_importers=:@impact:shown_importers" \
                "non-tests of impact_reaches=@safe-delete:radius_tested" "drill= the verb taking@communities:drill" \
                "isolated= symbols with no call edge@communities:isolated" "bridges= community pairs@communities:bridges" \
                "partition= module count@community:partition" "bridges= modules a call edge joins@community:bridges" "label= dir::name@community:label"; do
        needle="${pair%%@*}"; spec="${pair#*@}"
        if [ "$( ca mentions "$TMP/d23.c" "$needle" )" = 1 ] && [ "$( ca carries "$TMP/d23.c" "$spec" )" != 1 ]; then
            no "(D23) ${v:-the flagless map}: the compact legend spells '$needle' but the document carries no $spec — a reading of a field that is not there"
            d23bad=1
        fi
    done
done
[ "$d23bad" -eq 0 ] && [ "$d23n" -eq 9 ] && ok "(D23) mirror: no fourth-sweep reading prints on $d23n answers that lack its field (--from-trace, the columnar --impact, --safe-delete, --impact, --zoom, --seams, --communities, --community=0, the plain map)"

# ── THE FOURTH SWEEP, LAST PASS (2026-09-12): every attribute the four answers and the map header print ─────────────────────
# (D18)..(D23) closed what the earlier sweeps had named. This pass LISTED every attribute the compact --impact, --safe-delete,
# --communities, --community=ID and map-header documents emit, on test/fixture and on corpora that reach their conditional
# rows, and found these still undefined (each RUN before any reading landed):
#   (D24) --communities' modules=, shown_bridges=, connected_singletons=, symbols= and --community's shown_bridges=: EVERY answer
#         of the root carries them, so they read in the purpose lines;
#   (D25) the <bridge> rows: --communities' a=/b=/from_label=/to_label=/edges= and --community's to=/to_label=/edges=. Only an
#         answer with a cross-module call edge prints one (test/chafix does; test/fixture does not), so each is a present-only
#         term read on <bridge> alone;
#   (D26) --safe-delete's t=, defs=, ambiguous_callers=, dead_code_candidate= (its root p= reads in t='s clause; it is not a red
#         spec because <c n= p=> already spells the name);
#   (D27) --impact's <f lazy=> importer rows, present-only on <f>: the columnar form prints no <f> row;
#   (D28) the map header: the always-on files=/symbols=/edges=/shown=/ambiguous=/order=, and the conditional roots=, changed=,
#         skipped_oversize=, unindexed=/unindexed_exts=, escaped_root=, precise=. The full map legend defines none but shown=
#         (serialize.h buildUnindexedAttr records why it cannot: tokenbudgetcheck arm #3 leaves that floor seven bytes); a
#         compact legend replaces MORE prose than it adds, which (U) asserts on every probe, so here the readings fit;
#   (D29) the columnar form's format=/<cols fields=> (<cols n=> reads in the same term, and is not a red spec because the
#         purpose line's <s n=> already spells the name) and lens=, which --order=stable's <r> carries too.
# A `#name` header value may be QUOTED (unindexed="zzqa:1,…"), so condattr.py reads both spellings.
OVR="$TMP/oversize"; mkdir -p "$OVR"; cp -R "$FIX"/. "$OVR"/; head -c 5000 /dev/zero | tr '\0' 'a' >"$OVR/huge.py"
UNX="$TMP/unindexed"; mkdir -p "$UNX"; printf 'x = 1\n' >"$UNX/a.py"
for e in zzqa zzqb zzqc zzqd zzqe zzqf zzqg; do printf 'text\n' >"$UNX/a.$e"; done
ESC="$TMP/escape"; mkdir -p "$ESC/inner" "$ESC/outside"; cp -R "$FIX"/. "$ESC/inner"/
printf 'def far():\n    return 2\n' >"$ESC/outside/far.py"; ln -s ../outside/far.py "$ESC/inner/far.py"
CHA="$ROOT/test/chafix"; SCIPF="$ROOT/test/scipfix"
for d in "$CHA" "$SCIPF"; do [ -d "$d" ] || no "(D25/D28) fixture missing: $d — every row reading it would be vacuous"; done

condPair D24 "--communities (the rest of its root's counts)" "$FIX" "--communities" \
    '!communities:modules' '!communities:shown_bridges' '!communities:connected_singletons' '!communities:symbols'
condPair D24 "--community=0 (its bridge listing's width)" "$FIX" "--community=0" '!community:shown_bridges'
cdRun "$TMP/d25.cm" "$CHA" --communities
chaModule="$( grep -o '<bridge a="[0-9]*"' "$TMP/d25.cm" | head -1 | grep -o '[0-9][0-9]*' )"
[ -n "$chaModule" ] || no "(D25) control: --communities over test/chafix prints no <bridge> row any more, so both rows below are vacuous"
condPair D25 "--communities over test/chafix (a cross-module <bridge> row)" "$CHA" "--communities" \
    '!bridge:a' '!bridge:b' '!bridge:from_label' '!bridge:to_label' '!bridge:edges'
condPair D25 "--community=${chaModule:-0} over test/chafix (its peer <bridge> row)" "$CHA" "--community=${chaModule:-0}" '!bridge:to' '!bridge:to_label' '!bridge:edges'
condPair D26 "--safe-delete=total_area (the rest of its root)" "$FIX" "--safe-delete=total_area" \
    safe-delete:t safe-delete:defs safe-delete:ambiguous_callers safe-delete:dead_code_candidate
condPair D27 "--impact=distance (<f lazy=> importer rows)" "$FIX" "--impact=distance" f:lazy
mcp_text impact "{\"path\":\"$FIX\",\"symbol\":\"distance\",\"legend\":\"full\"}" >"$TMP/d.full"
mcp_text impact "{\"path\":\"$FIX\",\"symbol\":\"distance\"}" >"$TMP/d.comp"
condArm D27 "MCP impact at its DEFAULT posture (compact) vs legend:\"full\"" "$TMP/d.full" "$TMP/d.comp" f:lazy
condPair D28 "the flagless map (its always-on header)" "$FIX" "" '!#files' '!#symbols' '!#edges' '#shown' '!#ambiguous' '!#order'
"$BIN" "$FIX" "$H1" >"$TMP/d.full" 2>/dev/null </dev/null
"$BIN" "$FIX" "$H1" --legend=compact >"$TMP/d.comp" 2>/dev/null </dev/null
condArm D28 "two roots, the flagless map (roots= on its header)" "$TMP/d.full" "$TMP/d.comp" '!#roots'
condPair D28 "--map-diff (changed= on its header)" "$REPO" "--map-diff" '!#changed'
condPair D28 "--max-file-size=1K over a tree with a 5 KB file" "$OVR" "--max-file-size=1K" '!#skipped_oversize'
condPair D28 "a tree of seven extensions no grammar reads" "$UNX" "" '!#unindexed' '!#unindexed_exts'
condPair D28 "a tree whose symlink leads out of the root" "$ESC/inner" "" '!#escaped_root'
condPair D28 "test/scipfix under --scip (precise= on its header)" "$SCIPF" "--scip=index.scip --exclude=make_index.py --no-cache" '!#precise'
condPair D29 "--impact=distance --format=columnar" "$FIX" "--impact=distance --format=columnar" cols:fields impact:format '!impact:lens'
condPair D29 "--order=stable (lens= on the map root)" "$FIX" "--order=stable" '!r:lens'

# (D30) THE MIRROR, on answers chosen for what they LACK, each lack asserted before it is relied on: --from-trace carries a
# <trace format=> of its own (the trace's dialect) and no <cols>; --communities and --community=0 over test/fixture print no
# <bridge> row; the columnar --impact prints no <f> row; --impact=distance carries no map header and no lens=; the flagless
# map carries none of the conditional header fields. The needles are the readings' own openers, as in (D23).
rrun --from-trace="$TMP/trace.txt" --legend=compact >"$TMP/d30.trace"
[ "$( ca carries "$TMP/d30.trace" trace:format )" = 1 ] && [ "$( ca carries "$TMP/d30.trace" cols:fields )" != 1 ] \
    || no "(D30) control: --from-trace no longer carries <trace format=> without <cols>, so it proves nothing about the columnar reading's element"
rrun --communities --legend=compact >"$TMP/d30.cm"
[ "$( ca carries "$TMP/d30.cm" communities:bridges )" = 1 ] && [ "$( ca carries "$TMP/d30.cm" bridge:edges )" != 1 ] \
    || no "(D30) control: --communities over the fixture now prints a <bridge> row, so it no longer proves the bridge readings are present-only"
rrun --impact=distance --format=columnar --legend=compact >"$TMP/d30.col"
[ "$( ca carries "$TMP/d30.col" impact:importers )" = 1 ] && [ "$( ca carries "$TMP/d30.col" f:lazy )" != 1 ] \
    || no "(D30) control: the columnar --impact now prints an <f lazy=> row, so it no longer proves that reading is present-only"
rrun --impact=distance --legend=compact >"$TMP/d30.imp"
[ "$( ca carries "$TMP/d30.imp" f:lazy )" = 1 ] && [ "$( ca carries "$TMP/d30.imp" "#files" )" != 1 ] && [ "$( ca carries "$TMP/d30.imp" lens )" != 1 ] \
    || no "(D30) control: --impact=distance no longer carries <f lazy=> without a map header or lens=, so it proves nothing about the header-only and head readings"
d30bad=0; d30n=0
for v in "--from-trace=$TMP/trace.txt" "--communities" "--community=0" "--impact=distance --format=columnar" "--impact=distance" ""; do
    rrun $v --legend=compact >"$TMP/d30.c"
    if [ ! -s "$TMP/d30.c" ]; then
        no "(D30) ${v:-the flagless map} --legend=compact answered nothing — its mirror row would be vacuous"; d30bad=1; continue
    fi
    d30n=$(( d30n + 1 ))
    for pair in "<f lazy=1>:@f:lazy" "<bridge a= b=>:@bridge:a" "from_label=/to_label=:@bridge:from_label" "<bridge to= to_label=>:@bridge:to" \
                "<bridge edges=>:@bridge:edges" "files=/symbols=:@#files" "roots=N:@#roots" "changed=K:@#changed" "skipped_oversize=K:@#skipped_oversize" \
                "unindexed=ext:N:@#unindexed" "unindexed_exts=E:@#unindexed_exts" "escaped_root=K:@#escaped_root" "precise=K:@#precise" \
                "format=columnar:@cols:fields" "lens=:@lens"; do
        needle="${pair%%@*}"; spec="${pair#*@}"
        if [ "$( ca mentions "$TMP/d30.c" "$needle" )" = 1 ] && [ "$( ca carries "$TMP/d30.c" "$spec" )" != 1 ]; then
            no "(D30) ${v:-the flagless map}: the compact legend spells '$needle' but the document carries no $spec — a reading of a field that is not there"
            d30bad=1
        fi
    done
done
[ "$d30bad" -eq 0 ] && [ "$d30n" -eq 6 ] && ok "(D30) mirror: no last-pass reading prints on $d30n answers that lack its field (--from-trace, --communities, --community=0, the columnar --impact, --impact, the plain map)"

# ── THE TESTED ROW LENS (2026-09-12, the design review of the fourth sweep) ──────────────────────────────────────────────────
# (D31) <s tested="1"> rows. --callers/--callees and --impact (verbs_navigate.h), the MCP impact twin (mcpverbs.h) and the map's
# own rows (serialize.h, over computeQMetrics' tested[] column) print tested="1" on a row graph.h isTestedByReach accepts: an
# indexed test transitively reaches it and it is not itself a test symbol; never a literal 0. The full legend defines it
# (graphlegend.h kTestedRowLegend) and the compact layer stripped that clause with nothing to put back. No row above could see
# it: test/fixture holds no test, so every probe here printed radius_tested="0" and no tested row, while --impact=
# svector::push_back on this repo printed four. The corpus below is the smallest that prints one: test_lib.py's test_run calls
# run, which calls helper. The reading is ELEMENT-qualified on <s>: flipimpact.h's <h tested=> prints 0 as well as 1, and
# <exemplar tested=> is another root's attribute.
# RED on the fourth sweep's last-pass build (the uncommitted lane over b7c55908, plain and ASan alike): all three rows FAILed and
# nothing else did, for example
#   FAIL (D31) --callers=helper over a tree with a test (its caller run is tested): tested="1" is carried but the compact legend never defines it
#   FAIL (D31) MCP impact over a tree with a test, at its DEFAULT posture (compact) vs legend:"full": tested="1" is carried but the compact legend never defines it
TESTED="$TMP/testedrows"; mkdir -p "$TESTED/src"
printf 'def helper():\n    return 1\n\n\ndef run():\n    return helper()\n' >"$TESTED/src/lib.py"
printf 'from src.lib import run\n\n\ndef test_run():\n    assert run() == 1\n' >"$TESTED/test_lib.py"
condPair D31 "--callers=helper over a tree with a test (its caller run is tested)" "$TESTED" "--callers=helper" s:tested
condPair D31 "--impact=helper over a tree with a test (run, in its reach set, is tested)" "$TESTED" "--impact=helper" s:tested
mcp_text impact "{\"path\":\"$TESTED\",\"symbol\":\"helper\",\"legend\":\"full\"}" >"$TMP/d.full"
mcp_text impact "{\"path\":\"$TESTED\",\"symbol\":\"helper\"}" >"$TMP/d.comp"
condArm D31 "MCP impact over a tree with a test, at its DEFAULT posture (compact) vs legend:\"full\"" "$TMP/d.full" "$TMP/d.comp" s:tested

# (D32) THE MIRROR, on answers chosen for what they LACK, each lack asserted before it is relied on: --callers=run over the same
# corpus lists one caller, test_run, which is a test symbol, so it carries hop_tested= and no tested row; --safe-delete=helper
# carries radius_tested= and lists <c> rows; test/fixture's --callers, --impact and flagless map carry no tested row at all. The
# needle is the reading's own opener, as in (D23)/(D30). Green on the red build by construction, like (D7). Shown able to fail:
# with the reading spliced into the legend of --callers=run over this corpus, the row's check read the needle as spelled and no
# <s tested=> row as carried, which is its FAIL.
cdRun "$TMP/d32.run" "$TESTED" --callers=run --legend=compact
[ "$( ca carries "$TMP/d32.run" callers:hop_tested )" = 1 ] && [ "$( ca carries "$TMP/d32.run" s:tested )" != 1 ] \
    || no "(D32) control: --callers=run over the tested corpus no longer carries hop_tested= without a tested row, so it proves nothing about the row reading being present-only"
d32bad=0; d32n=0
for v in "$TESTED@--callers=run" "$TESTED@--safe-delete=helper" "$REPO@--callers=distance" "$REPO@--impact=distance" "$REPO@"; do
    dir="${v%%@*}"; args="${v#*@}"
    cdRun "$TMP/d32.c" "$dir" $args --legend=compact
    if [ ! -s "$TMP/d32.c" ]; then
        no "(D32) ${args:-the flagless map} --legend=compact answered nothing — its mirror row would be vacuous"; d32bad=1; continue
    fi
    d32n=$(( d32n + 1 ))
    if [ "$( ca mentions "$TMP/d32.c" "<s tested=1>:" )" = 1 ] && [ "$( ca carries "$TMP/d32.c" s:tested )" != 1 ]; then
        no "(D32) ${args:-the flagless map}: the compact legend spells '<s tested=1>:' but the document carries no <s tested=> row — a reading of a field that is not there"
        d32bad=1
    fi
done
[ "$d32bad" -eq 0 ] && [ "$d32n" -eq 5 ] && ok "(D32) mirror: the tested row reading prints on none of $d32n answers that lack an <s tested=> row (a test-only caller list, --safe-delete's radius, the fixture's --callers/--impact, the plain map)"

# ── THE TESTED LENS ON <d> ROWS AND IN THE COLUMNAR FORM (2026-09-12, the follow-up to (D31)/(D32)) ──────────────────────────────
# (D31)'s reading is ELEMENT-qualified on <s>, and two more forms print the same lens with no reading. Each was run, and read
# against its emitter, before any reading landed:
#   (D33) <d tested="1"> signature rows. serialize.h's two signature-row writers print it from computeQMetrics' tested[] column,
#         which graph.h isTestedByReach fills: the <s> rows' predicate, an indexed test transitively reaches that symbol and it
#         is not itself a test. Never a literal 0. main.cpp computes that column only under --metrics, --for or --exemplar, so a
#         plain --pack-task prints no tested= at all; --pack-task --metrics does (it compacted under the pack-signatures
#         schema until (D36) had the hint read the root's family first). Its FULL legend never names
#         tested= either (a `!` spec). condArm's left-anchored tested= would also be satisfied by (D31)'s <s tested=1> reading
#         on an answer printing both forms, so the row asserts the <d> reading's own opener too.
#   (D34) the columnar form's tested column. --callers/--callees/--impact --format=columnar always pass the test-reach lens
#         (verbs_navigate.h), so fields= names tested and <tested> holds one DENSE value per row (columnar.h
#         emitColumnarTestedColumn): 1 where isTestedByReach holds, 0 on every other row, a test row included. Unlike the <s>
#         attribute it prints 0, so the reading rides the COLUMN rather than a 1: over test/fixture, which holds no test,
#         --callers=distance carries <tested>0,0</tested>, and a reading keyed to a 1 would leave those zeros undefined. The
#         full legend's only tested sentence is kTestedRowLegend's attribute reading ("never 0"), so no full control is taken.
# RED on e45bd3ab (plain and ASan alike): all six (D33)/(D34) checks FAILed and nothing else did ((D35) is green by construction),
# for example
#   FAIL (D33) --pack-task=helper --metrics over a tree with a test (its <d> rows helper and run are tested): tested="1" is carried but the compact legend never defines it
#   FAIL (D34) --callers=distance --format=columnar over test/fixture (...): fields="path,name,line,kind,tested" and <tested>0,0</tested> are carried but the compact legend never reads the column
condPair D33 "--pack-task=helper --metrics over a tree with a test (its <d> rows helper and run are tested)" "$TESTED" "--pack-task=helper --metrics" '!d:tested'
if [ "$( ca carries "$TMP/d.comp" d:tested )" = 1 ] && [ "$( ca mentions "$TMP/d.comp" "<d tested=1>:" )" = 1 ]; then
    ok "(D33) --pack-task=helper --metrics: the reading is the <d> row's own ('<d tested=1>:')"
else
    no "(D33) --pack-task=helper --metrics: <d tested=> carried=$( ca carries "$TMP/d.comp" d:tested ), but the compact legend does not spell the <d> row reading '<d tested=1>:': $( leg legend "$TMP/d.comp" | head -c 260 )"
fi
COLTESTED="<tested> column:"
namesTested(){ case ",$1," in *,tested,*) return 0 ;; esac; return 1; }
# colTestedRow ID LABEL DIR "ARGS" — one columnar answer in both postures: the control (fields= names tested in both), then the
# compact legend must spell the column's reading.
colTestedRow()
{
    local id="$1" label="$2" dir="$3" args="$4" col
    cdRun "$TMP/d.full" "$dir" $args; cdRun "$TMP/d.comp" "$dir" $args --legend=compact
    col="$( grep -o '<tested>[^<]*</tested>' "$TMP/d.comp" | head -1 )"
    if ! namesTested "$( ca value "$TMP/d.full" cols:fields )" || ! namesTested "$( ca value "$TMP/d.comp" cols:fields )"; then
        no "($id) $label: control broken — <cols fields=> does not name tested in both postures, so its reading row would be vacuous: $( head -c 160 "$TMP/d.comp" )"
    elif [ "$( ca mentions "$TMP/d.comp" "$COLTESTED" )" != 1 ]; then
        no "($id) $label: fields=\"$( ca value "$TMP/d.comp" cols:fields )\" and $col are carried but the compact legend never reads the column: $( leg legend "$TMP/d.comp" | head -c 260 )"
    else
        ok "($id) $label: fields= names tested ($col), and the compact legend reads the column"
    fi
    return 0
}
colTestedRow D34 "--callers=helper --format=columnar over a tree with a test" "$TESTED" "--callers=helper --format=columnar"
colTestedRow D34 "--callees=run --format=columnar over a tree with a test" "$TESTED" "--callees=run --format=columnar"
colTestedRow D34 "--impact=helper --format=columnar over a tree with a test (test_run, a test row, reads 0)" "$TESTED" "--impact=helper --format=columnar"
colTestedRow D34 "--callers=distance --format=columnar over test/fixture (no test: the column still rides, every value 0)" "$REPO" "--callers=distance --format=columnar"

# (D35) THE MIRROR, on answers chosen for what they LACK, each lack asserted before it is relied on: --pack-task=helper over the
# tested corpus prints <d> rows with no tested= (no --metrics, so no column was computed); --pack-task=geometry --metrics over
# test/fixture prints <d amp=> rows and no tested= (no test reaches them); --uses=helper --format=columnar has a fields= that does
# not name tested; --callers=helper carries <s tested=> rows and neither a <d> row nor <cols>; --pack-task=helper --metrics carries
# <d tested=> and no <s tested=> row, which also keeps (D31)'s reading on <s>. The needles are the readings' own openers, as in
# (D32). Green on the red build by construction, like (D7). Shown able to fail: with each reading spliced into the compact legend
# of a real answer that lacks its field (the column reading into --uses=helper --format=columnar, the <d> reading into
# --pack-task=helper, (D31)'s <s> reading into --pack-task=helper --metrics), its check here fired on all three spliced answers
# and on none of the three unspliced ones. The column check is the one a dropped valueItem trips: without it the fields= term
# reads every <cols fields=>, --uses' included.
cdRun "$TMP/d35.pt" "$TESTED" --pack-task=helper --legend=compact
[ "$( ca carries "$TMP/d35.pt" d:l )" = 1 ] && [ "$( ca carries "$TMP/d35.pt" d:tested )" != 1 ] \
    || no "(D35) control: --pack-task=helper over the tested corpus no longer prints <d> rows without tested=, so it proves nothing about the <d> reading being present-only"
cdRun "$TMP/d35.uses" "$TESTED" --uses=helper --format=columnar --legend=compact
{ [ "$( ca carries "$TMP/d35.uses" cols:fields )" = 1 ] && ! namesTested "$( ca value "$TMP/d35.uses" cols:fields )"; } \
    || no "(D35) control: --uses=helper --format=columnar no longer carries a fields= without tested, so it proves nothing about the column reading riding the column"
cdRun "$TMP/d35.ptm" "$TESTED" --pack-task=helper --metrics --legend=compact
[ "$( ca carries "$TMP/d35.ptm" d:tested )" = 1 ] && [ "$( ca carries "$TMP/d35.ptm" s:tested )" != 1 ] \
    || no "(D35) control: --pack-task=helper --metrics no longer carries <d tested=> without an <s tested=> row, so it proves nothing about the two row readings reading apart"
d35bad=0; d35n=0
for v in "$TESTED@--pack-task=helper" "$REPO@--pack-task=geometry --metrics" "$TESTED@--uses=helper --format=columnar" "$TESTED@--callers=helper" \
         "$TESTED@--pack-task=helper --metrics"; do
    dir="${v%%@*}"; args="${v#*@}"
    cdRun "$TMP/d35.c" "$dir" $args --legend=compact
    if [ ! -s "$TMP/d35.c" ]; then
        no "(D35) $args --legend=compact answered nothing — its mirror row would be vacuous"; d35bad=1; continue
    fi
    d35n=$(( d35n + 1 ))
    for pair in "<d tested=1>:@d:tested" "<s tested=1>:@s:tested"; do
        needle="${pair%%@*}"; spec="${pair#*@}"
        if [ "$( ca mentions "$TMP/d35.c" "$needle" )" = 1 ] && [ "$( ca carries "$TMP/d35.c" "$spec" )" != 1 ]; then
            no "(D35) $args: the compact legend spells '$needle' but the document carries no <${spec%%:*} tested=> row — a reading of a field that is not there"
            d35bad=1
        fi
    done
    if [ "$( ca mentions "$TMP/d35.c" "$COLTESTED" )" = 1 ] && ! namesTested "$( ca value "$TMP/d35.c" cols:fields )"; then
        no "(D35) $args: the compact legend spells '$COLTESTED' but no <cols fields=> names tested — a reading of a column that is not there"
        d35bad=1
    fi
done
[ "$d35bad" -eq 0 ] && [ "$d35n" -eq 5 ] && ok "(D35) mirror: neither new tested reading, nor (D31)'s, prints on $d35n answers that lack its field (<d> rows with no column computed, <d> rows over a tree with no test, a columnar fields= without tested, <s tested=> rows alone, <d tested=> rows alone)"

# ── THE HINT READS THE ROOT, AND THE BUNDLE'S OWN VOCABULARY (2026-09-12, found at the end of the lane) ──────────────────────────────
# (D36) main.cpp's compactLegendHint derived ONE key from the flags in ONE order: map-diff, metrics, around, query, then the bundle
# verbs. A key names a spec only under its own root (<r> for those four, <ctx> for the rest), and a key from the other family took
# that root's FIRST spec, pack-signatures. --pack-task --metrics is a pack-task bundle whose rows --metrics shapes, and it compacted
# as pack-signatures; so did --from-trace --metrics and --pack-task beside --around. No single flag order is right, because verb
# precedence interleaves the families (each pair run, its stderr read): --pack-task and --from-trace answer over --around, while
# --around answers over --expand and --pack-signatures, whose bundles it never renders. So the ROOT picks the family and the flags
# pick the key within it, in the old order; the around-over-expand row is the neighbour a flag reorder would break.
# Under the right schema the bundle still carried attributes no compact reading named: task=, route=, its <d>/<b>/<s>/<c>/<test>
# row vocabulary, of_top=, rel=, shared=, run=, and the lens facts serialize.h sigRowHead writes on every <d> row of a ranked bundle,
# r= cx= ccx= in= (amp= too under --metrics). The full legend's "Row keys" clause defines most of them and is prose, so the layer
# stripped it. schemaRow reads the schema. allAttrsRow reads EVERY attribute name the compact answer carries, and each must be
# spelled NAME= in that legend; the <d> and route= readings must also be their own openers, as in (D33). --from-trace carries the
# same four <d> facts, and its full legend defines them.
# RED on 036c827d (plain): eleven (D36) checks FAILed and nothing else did (the around-over-expand row and (D37) are green by
# construction), for example
#   FAIL (D36) --pack-task=helper --metrics (a pack-task bundle; --metrics shapes its rows) compacts under 'ripwire.pack-signatures/v1', not ripwire.pack-task/v1
#   FAIL (D36) --pack-task=helper --metrics over a tree with a test: carried, and spelled NAME= nowhere in the compact legend: amp budget_tokens ccx cx in of_top r rel route run t task
#   FAIL (D36) MCP explore over a tree with a test, at its DEFAULT posture (compact): carried, and spelled NAME= nowhere in the compact legend: ccx cx in l n of_top r rel route run t task
schemaRow()
{
    local id="$1" label="$2" dir="$3" args="$4" want="$5" got
    cdRun "$TMP/d36.s" "$dir" $args --legend=compact
    got="$( leg schema "$TMP/d36.s" )"
    if [ "$got" = "$want" ]; then
        ok "($id) $label compacts under $want"
    else
        no "($id) $label compacts under '$got', not $want"
    fi
    return 0
}
schemaRow D36 "--pack-task=helper --metrics (a pack-task bundle; --metrics shapes its rows)" "$TESTED" "--pack-task=helper --metrics" "ripwire.pack-task/v1"
schemaRow D36 "--from-trace --metrics (a from-trace bundle)" "$REPO" "--from-trace=$TMP/trace.txt --metrics" "ripwire.from-trace/v1"
schemaRow D36 "--pack-task=geometry --around=distance (--pack-task answers)" "$REPO" "--pack-task=geometry --around=distance" "ripwire.pack-task/v1"
schemaRow D36 "--around=distance --expand=distance (--around answers; the neighbour a flag reorder breaks)" "$REPO" "--around=distance --expand=distance" "ripwire.around/v1"
cat > "$TMP/allattrs.py" <<'PY'
import re, sys
buf = open( sys.argv[1], encoding = "utf-8", errors = "replace" ).read()
legend, tags = [], []
i = 0; n = len( buf )
while i < n:
    if buf.startswith( "<![CDATA[", i ):
        j = buf.find( "]]>", i ); i = n if j < 0 else j + 3
    elif buf.startswith( "<!--", i ):
        j = buf.find( "-->", i ); j = n if j < 0 else j + 3; legend.append( buf[ i:j ] ); i = j
    elif buf[ i ] == "<":
        j = buf.find( ">", i ); j = n if j < 0 else j + 1; tags.append( buf[ i:j ] ); i = j
    else:
        j = buf.find( "<", i ); i = n if j < 0 else j
leg = " ".join( legend )
names = sorted( { a for t in tags for a in re.findall( r'\s([\w:.-]+)="', t ) } - { "schema" } )
print( len( names ), " ".join( a for a in names if not re.search( r"(?<![A-Za-z0-9_])" + re.escape( a ) + "=", leg ) ) )
PY
# allAttrsRow ID LABEL FILE — every attribute name the compact document carries (schema= is the dialect's own id) is spelled NAME=
# in its compact legend.
allAttrsRow()
{
    local id="$1" label="$2" file="$3" count missing
    read -r count missing <<<"$( python3 "$TMP/allattrs.py" "$file" )"
    if [ "${count:-0}" -lt 12 ]; then
        no "($id) $label: control broken — ${count:-0} attribute names carried, too few for this row to read a bundle: $( head -c 160 "$file" )"
    elif [ -n "$missing" ]; then
        no "($id) $label: carried, and spelled NAME= nowhere in the compact legend: $missing — $( leg legend "$file" | head -c 260 )"
    else
        ok "($id) $label: all $count attribute names it carries are defined by its compact legend"
    fi
    return 0
}
cdRun "$TMP/d36.a" "$TESTED" --pack-task=helper --metrics --legend=compact
allAttrsRow D36 "--pack-task=helper --metrics over a tree with a test" "$TMP/d36.a"
d36miss=""
for opener in "<d r=N>:" "<d cx= ccx=>:" "<d in=N>:" "<d amp=N>:" "route=:"; do
    [ "$( ca mentions "$TMP/d36.a" "$opener" )" = 1 ] || d36miss="$d36miss '$opener'"
done
if [ -z "$d36miss" ]; then
    ok "(D36) --pack-task=helper --metrics: the <d> lens facts and route= read under their own openers"
else
    no "(D36) --pack-task=helper --metrics: the compact legend does not spell the reading(s)$d36miss: $( leg legend "$TMP/d36.a" | head -c 260 )"
fi
cdRun "$TMP/d36.b" "$REPO" --pack-task=geometry --metrics --legend=compact
allAttrsRow D36 "--pack-task=geometry --metrics over the fixture" "$TMP/d36.b"
mcp_text explore "{\"path\":\"$TESTED\",\"task\":\"helper\"}" >"$TMP/d36.c"
allAttrsRow D36 "MCP explore over a tree with a test, at its DEFAULT posture (compact)" "$TMP/d36.c"
condPair D36 "--from-trace (its <d> rows carry the lens facts)" "$REPO" "--from-trace=$TMP/trace.txt" d:r d:cx d:ccx d:in

# (D37) THE MIRROR, on answers chosen for what they LACK, each lack asserted before it is relied on: --pack-task=helper without
# --metrics prints <d> rows carrying r=/cx=/ccx=/in= and no amp=; --pack-signatures prints <d> rows with none of the four (no lens
# rank, no metrics); MCP explore with no_route prints <ctx task=> and no route=. The needles are the readings' own openers, as in
# (D35). Green on the red build by construction, like (D7).
cdRun "$TMP/d37.pt" "$TESTED" --pack-task=helper --legend=compact
cdRun "$TMP/d37.ps" "$REPO" --pack-signatures --legend=compact
mcp_text explore "{\"path\":\"$TESTED\",\"task\":\"helper\",\"no_route\":true}" >"$TMP/d37.nr"
{ [ "$( ca carries "$TMP/d37.pt" d:ccx )" = 1 ] && [ "$( ca carries "$TMP/d37.pt" d:amp )" != 1 ]; } \
    || no "(D37) control: --pack-task=helper no longer prints <d ccx=> rows without amp=, so it proves nothing about the amp= reading being present-only"
{ [ "$( ca carries "$TMP/d37.ps" d:l )" = 1 ] && [ "$( ca carries "$TMP/d37.ps" d:r )" != 1 ] && [ "$( ca carries "$TMP/d37.ps" d:ccx )" != 1 ] \
    && [ "$( ca carries "$TMP/d37.ps" d:in )" != 1 ]; } \
    || no "(D37) control: --pack-signatures no longer prints <d> rows without r=/ccx=/in=, so it proves nothing about those readings being present-only"
{ [ "$( ca carries "$TMP/d37.nr" ctx:task )" = 1 ] && [ "$( ca carries "$TMP/d37.nr" ctx:route )" != 1 ]; } \
    || no "(D37) control: MCP explore with no_route no longer prints <ctx task=> without route=, so it proves nothing about the route= reading being present-only"
d37bad=0; d37n=0
for v in "--pack-task=helper|d37.pt" "--pack-signatures|d37.ps" "MCP explore no_route|d37.nr"; do
    label="${v%%|*}"; f="$TMP/${v#*|}"
    if [ ! -s "$f" ] || grep -q '^__ERROR__' "$f"; then
        no "(D37) $label answered nothing — its mirror row would be vacuous"; d37bad=1; continue
    fi
    d37n=$(( d37n + 1 ))
    for pair in "<d r=N>:@d:r" "<d cx= ccx=>:@d:ccx" "<d in=N>:@d:in" "<d amp=N>:@d:amp" "route=:@ctx:route"; do
        needle="${pair%%@*}"; spec="${pair#*@}"
        if [ "$( ca mentions "$f" "$needle" )" = 1 ] && [ "$( ca carries "$f" "$spec" )" != 1 ]; then
            no "(D37) $label: the compact legend spells '$needle' but the document carries no <${spec%%:*} ${spec#*:}=> — a reading of a field that is not there"
            d37bad=1
        fi
    done
done
[ "$d37bad" -eq 0 ] && [ "$d37n" -eq 3 ] && ok "(D37) mirror: no <d> lens-fact or route= reading prints on $d37n answers that lack its field (<d> rows without amp=, <d> rows without the lens facts, a bundle not routed)"

# ── THE KEY NAMES THE VERB THAT ANSWERED (2026-09-12, CodeRabbit on #203) ──────────────────────────────────────────────────────────
# (D38) (D36) took the FAMILY from the root and kept each family's flag order for the key, and that order disagreed with dispatch
# inside both families: the bundle hint read --expand before --pack-task, the map hint --around before --query. --pack-task=geometry
# --expand=distance prints the byte-identical document --pack-task=geometry prints, and compacted under ripwire.expand/v1, reading
# sibs=/sibs_total=/sibs_capped=/inc= that nothing in it carries; --query=distance --around=distance prints --query's lexical map and
# compacted under ripwire.around/v1, reading of=/depth=/fanout= off a map with no seed. The same order lent the losing flag's schema on
# every other pair below (each run, its stderr's precedence line read, its full answer compared with the winner's alone): --pack-task
# beside --skipped/--notes/--lego, --from-trace beside --expand/--notes/--skipped, --notes beside --skipped, and --query and --around
# beside --map-diff, whose changed= only the default map's non-query arm writes. main.cpp now reads the key off the answer: a verb
# with a mark of its own (map-diff's header changed=, the metrics block, around's root of=, <skipped>/<notes>/<lego> as the first
# child, pack-task's root budget_tokens=, from-trace's root task=) names its key only when the document carries that mark, and a flag
# with none (--query, the default map's bundle modifiers) is read only after every marked verb was ruled out.
# dispatchRow asserts, per pair: the controls (the pair's FULL answer is byte-identical to the winner's alone, and the winner alone
# compacts under WANT), the schema, and that every NAME= reading the pair's compact legend spells is carried by the document (a tag
# attribute or a map-header field) or printed by the winner's own compact legend over that same document (its conditional
# vocabulary: pack-task's purpose line reads id=/run=/shared=, absent on this fixture, and (D36)/(D37) own those). schemaRow pins the
# pairs whose verbs render into ONE answer, where the old order stays the tie-break and must not move: --metrics beside --around,
# --map-diff beside --metrics, --expand beside --pack-signatures.
# RED on 3a55f52d (plain): twenty-two (D38) checks FAILed, both checks of every dispatchRow, and nothing else did (the three
# schemaRow tie-break rows are green by construction), for example
#   FAIL (D38) --pack-task=geometry --expand=distance (...) compacts under 'ripwire.expand/v1', not ripwire.pack-task/v1 — the schema of a flag whose verb did not answer
#   FAIL (D38) --pack-task=geometry --expand=distance (...): its compact legend reads inc= sibs= sibs_capped= sibs_total= — carried by no attribute or header field of the document, and printed by no compact legend of --pack-task=geometry alone
#   FAIL (D38) --query=distance --around=distance (...): its compact legend reads depth= fanout= of= — carried by no attribute or header field of the document, and printed by no compact legend of --query=distance alone
#   FAIL (D38) --notes --skipped compacts under 'ripwire.skipped/v1', not ripwire.notes/v1 — the schema of a flag whose verb did not answer
cat > "$TMP/unread.py" <<'PY'
import re, sys
buf = open( sys.argv[1], encoding = "utf-8", errors = "replace" ).read()
legend, tags, header = "", [], ""
i = 0; n = len( buf )
while i < n:
    if buf.startswith( "<![CDATA[", i ):
        j = buf.find( "]]>", i ); i = n if j < 0 else j + 3
    elif buf.startswith( "<!--", i ):
        j = buf.find( "-->", i ); j = n if j < 0 else j + 3; c = buf[ i:j ]; i = j
        if "/v1:" in c: legend += c
        elif c.startswith( "<!-- files=" ) and not header: header = c
    elif buf[ i ] == "<":
        j = buf.find( ">", i ); j = n if j < 0 else j + 1; tags.append( buf[ i:j ] ); i = j
    else:
        j = buf.find( "<", i ); i = n if j < 0 else j
carried = { a for t in tags for a in re.findall( r'\s([\w:.-]+)="', t ) } | set( re.findall( r'\s(\w+)=', header ) )
print( " ".join( sorted( set( re.findall( r'(?<![A-Za-z0-9_])([A-Za-z_]\w*)=', legend ) ) - carried ) ) )
PY
# dispatchRow ID LABEL DIR "PAIR ARGS" "WINNER ARGS" WANT — the pair compacts as the verb that answered it, reading nothing that verb's
# own compact legend would not.
dispatchRow()
{
    local id="$1" label="$2" dir="$3" pair="$4" winner="$5" want="$6" own extra r
    cdRun "$TMP/d38.pf" "$dir" $pair;   cdRun "$TMP/d38.pc" "$dir" $pair --legend=compact
    cdRun "$TMP/d38.wf" "$dir" $winner; cdRun "$TMP/d38.wc" "$dir" $winner --legend=compact
    if [ ! -s "$TMP/d38.pf" ] || ! cmp -s "$TMP/d38.pf" "$TMP/d38.wf"; then
        no "($id) $label: control broken — its full answer is not byte-identical to $winner alone, so the row cannot say which verb answered: $( head -c 160 "$TMP/d38.pf" )"
        return 0
    fi
    if [ "$( leg schema "$TMP/d38.wc" )" != "$want" ]; then
        no "($id) $label: control broken — $winner alone compacts under '$( leg schema "$TMP/d38.wc" )', not $want"
        return 0
    fi
    if [ "$( leg schema "$TMP/d38.pc" )" = "$want" ]; then
        ok "($id) $label compacts under $want, the verb that answered"
    else
        no "($id) $label compacts under '$( leg schema "$TMP/d38.pc" )', not $want — the schema of a flag whose verb did not answer"
    fi
    own=" $( python3 "$TMP/unread.py" "$TMP/d38.wc" ) "; extra=""
    for r in $( python3 "$TMP/unread.py" "$TMP/d38.pc" ); do
        case "$own" in *" $r "*) ;; *) extra="$extra $r=" ;; esac
    done
    if [ -z "$extra" ]; then
        ok "($id) $label: every reading its compact legend spells is carried by the document or printed by $winner's own"
    else
        no "($id) $label: its compact legend reads$extra — carried by no attribute or header field of the document, and printed by no compact legend of $winner alone"
    fi
    return 0
}
dispatchRow D38 "--pack-task=geometry --expand=distance (--pack-task answers; the default map's --expand never renders)" "$REPO" "--pack-task=geometry --expand=distance" "--pack-task=geometry" "ripwire.pack-task/v1"
dispatchRow D38 "--query=distance --around=distance (--query answers, ahead of --around)" "$REPO" "--query=distance --around=distance" "--query=distance" "ripwire.query/v1"
dispatchRow D38 "--pack-task=geometry --skipped" "$REPO" "--pack-task=geometry --skipped" "--pack-task=geometry" "ripwire.pack-task/v1"
dispatchRow D38 "--pack-task=geometry --notes" "$REPO" "--pack-task=geometry --notes" "--pack-task=geometry" "ripwire.pack-task/v1"
dispatchRow D38 "--pack-task=geometry --lego=Point" "$REPO" "--pack-task=geometry --lego=Point" "--pack-task=geometry" "ripwire.pack-task/v1"
dispatchRow D38 "--from-trace --expand=distance" "$REPO" "--from-trace=$TMP/trace.txt --expand=distance" "--from-trace=$TMP/trace.txt" "ripwire.from-trace/v1"
dispatchRow D38 "--from-trace --notes" "$REPO" "--from-trace=$TMP/trace.txt --notes" "--from-trace=$TMP/trace.txt" "ripwire.from-trace/v1"
dispatchRow D38 "--from-trace --skipped" "$REPO" "--from-trace=$TMP/trace.txt --skipped" "--from-trace=$TMP/trace.txt" "ripwire.from-trace/v1"
dispatchRow D38 "--notes --skipped" "$REPO" "--notes --skipped" "--notes" "ripwire.notes/v1"
dispatchRow D38 "--query=distance --map-diff (the query arm answers; map-diff's arm never runs)" "$REPO" "--query=distance --map-diff" "--query=distance" "ripwire.query/v1"
dispatchRow D38 "--around=distance --map-diff" "$REPO" "--around=distance --map-diff" "--around=distance" "ripwire.around/v1"
schemaRow D38 "--metrics --around=distance (both render into --around's answer; the tie-break keeps metrics)" "$REPO" "--metrics --around=distance" "ripwire.metrics/v1"
schemaRow D38 "--map-diff --metrics (both render into the map-diff answer)" "$REPO" "--map-diff --metrics" "ripwire.map-diff/v1"
schemaRow D38 "--pack-signatures --expand=distance (both render into the default map's bundle)" "$REPO" "--pack-signatures --expand=distance" "ripwire.expand/v1"
# Every MARKED verb alone keeps its own schema, so a mark its own answer never carries is red on its own row rather than hidden in a
# pair (dispatchRow's controls hold pack-task, query, from-trace, notes and around). The first cut of this fix read <lego>, <skipped>
# and <notes> from the whole head span, which starts with the legend comments those verbs put before their first child, and all
# three compacted as pack-signatures while only the --notes control noticed.
schemaRow D38 "--map-diff alone (its mark: the header's changed=)" "$REPO" "--map-diff" "ripwire.map-diff/v1"
schemaRow D38 "--metrics alone (its mark: the metrics legend block)" "$REPO" "--metrics" "ripwire.metrics/v1"
schemaRow D38 "--skipped alone (its mark: <skipped> first, after its legend comments)" "$REPO" "--skipped" "ripwire.skipped/v1"
schemaRow D38 "--lego=Point alone (its mark: <lego> first, after its legend comments)" "$REPO" "--lego=Point" "ripwire.lego/v1"
# The default map's --token-budget gate replaces an over-budget answer with <r withheld="1"/>, which carries no verb's mark. A
# byte-identity sweep of 854 probes against 3a55f52d caught the second cut of this fix compacting both answers below as
# ripwire.map/v1; the arm that answered is the flag's, so on that stub alone the flags keep their old order.
schemaRow D38 "--map-diff --token-budget=1 (the budget gate withholds the map: no mark, the flag decides)" "$REPO" "--map-diff --token-budget=1" "ripwire.map-diff/v1"
schemaRow D38 "--metrics --token-budget=1 (withheld the same way)" "$REPO" "--metrics --token-budget=1" "ripwire.metrics/v1"

echo
echo "=== (S) STRUCTURAL: every conditional attribute the graphlegend.h family, the PageRank disclosure, the map header and the map's rows emit has a compact reading ==="
# The (D) rows prove today's members; this row keeps the NEXT one from landing undefined. The population is READ FROM
# SOURCE, never listed here, from the places a conditional attribute is spelled:
#   1. every `countAttrXmlOrEmpty( "NAME"` call, tree-wide — the one absent-at-zero spelling graphlegend.h mandates;
#   2. every legend constant graphlegend.h selects CONDITIONALLY — named in exactly one arm of a `?:` (a clause against
#      "", or the callees-only half of callHierarchyLegendOpen) — reduced to the attribute its text opens with, the
#      house form ("declined_calls=K (absent when 0) …", "callees-only: bodyless_defs= …");
#   3. (2026-09-12) the PageRank disclosure's XML spelling in src/prconverge.h, and every map-HEADER field src/serialize.h
#      defines as `hdr:NAME=` in a clause charged only to a map that carries it, or marked absent-if-0 inside the
#      always-on `<!-- ripwire v1` legend. pr_iters=/pr_converged= need a row that reads the head; a header field needs a
#      row that reads the kept `<!-- files=` comment (MapHeaderRead::Only/Also), because a head-only row never sees an
#      unquoted field — and a header-ONLY row is not coverage for a (1)/(2) name, which is a quoted attribute.
#   4. (2026-09-12, the third sweep) every UNPREFIXED row field of that same always-on `<!-- ripwire v1` legend whose clause
#      carries an absence marker (`absent-if-N`, `absent=`): lpin= and overloads= on <s>, prov= on <c>. Its row must READ
#      THE PAYLOAD (wholeDoc, or an onTag element): a head-only row never sees an <s>/<c> below the first child, and a
#      header-only row reads the `<!-- files=` comment alone.
# Each (1)/(2) name must have a kCompactCompletenessTerms row, a paging-window name, or the *_capped rule (all read from
# src/compactlegend.h). The one other way to be defined is a full clause the compact layer KEEPS because it is not
# prose-prefixed — --skipped's `<!-- why=…` health comments — and that is never taken on trust: each such name is run
# live here and must be carried AND defined by the compact document, or the row fails.
# WHAT IT DOES NOT SEE, said so the arm is not read as wider than it is (CONTRIBUTING §2 shape 7): a clause made
# conditional at its CALL SITE rather than inside graphlegend.h (fielduses.h's member form, serialize.h's multi-root
# table, --lego's caveat=) — rows (D4)/(D5)/(D6) are what guard those; nor a map-family clause not spelled `hdr:`
# (kMaxTokensFitLegend's max_tokens=/fit_bytes=/over_ceiling=, est_tokens= under order=stable, --around's defs=,
# --rank-by's rank_by=/window=) — (D10)/(D11) guard those. The always-on header field unresolved= (no absent-if-0 marker)
# was printed here as INFO, still undefined under compact, until the fourth sweep (2026-09-12, owner decision: raise the pins
# to fit honest definitions): population 3 now requires a header reading for EVERY hdr: field of that legend, marked or
# not, and (D18) shows the reading live. Shown able to fail: this reader run over 27fc151d's src/compactlegend.h (no row)
# FAILed on unresolved= and on nothing else. The sweep's design review folded unresolved= into the always-on files= clause, so an
# UNMARKED field may read inside that one row; a marked field still needs a row of its own. Shown able to fail on the fold: with
# unresolved= deleted from that clause, this reader FAILed on unresolved= and on nothing else.
# RED on origin/main 28ee1df3: bodyless_defs=, declined_calls= and unproven_defs= FAILed. Shown able to fail on the fix
# too: with the declined_calls row deleted from kCompactCompletenessTerms this arm went red on that name (landing commit).
# RED on 34a97f66 for population 3: pr_iters=, pr_converged= and all seven hdr: fields FAILed. Shown able to fail on the
# fix: deleting the declined row, making pr_iters header-only, or dropping ignored_dirs' header read each went red on
# exactly that name, and on nothing else (landing commit).
# Population 4 does NOT see unconditional root vocabulary (--tree's files=, --zoom's symbols=/isolated=/top_modules=/
# levels_shown=), nor a conditional element whose clause is not a marked field of that legend (--zoom's children=,
# churn-decay's <recent>): (D13)..(D15) guard those. RED on 3c89ac0b: lpin=, overloads= and prov= FAILed. Shown able to fail
# on the fix: deleting the prov row, making overloads head-only, or making lpin header-only each went red on exactly that
# name, and on nothing else (landing commit).
cat > "$TMP/struct.py" <<'PY'
import os, re, sys
root = sys.argv[1]
def lex( text ):
    # comments dropped; every string/char literal replaced by a numbered placeholder whose body is kept in lits
    out, lits = [], []
    i = 0; n = len( text )
    while i < n:
        if text.startswith( "//", i ):
            j = text.find( "\n", i ); i = n if j < 0 else j
        elif text.startswith( "/*", i ):
            j = text.find( "*/", i + 2 ); i = n if j < 0 else j + 2
        elif text[ i ] in "\"'":
            q = text[ i ]; j = i + 1
            while j < n and text[ j ] != q:
                j += 2 if text[ j ] == "\\" else 1
            if q == '"':
                out.append( '"S%d"' % len( lits ) ); lits.append( text[ i + 1:j ] )
            else:
                out.append( "'?'" )
            i = j + 1
        else:
            out.append( text[ i ] ); i += 1
    return "".join( out ), lits
def arms( code, q ):
    # the two arms of the ternary whose '?' is at q: up to the first depth-0 ':' that is not '::', then to its end
    depth = 0; i = q + 1; n = len( code ); mid = -1
    while i < n:
        c = code[ i ]
        if code.startswith( "::", i ):
            i += 2; continue
        if c in "([{":
            depth += 1
        elif c in ")]}":
            if depth == 0:
                break
            depth -= 1
        elif depth == 0 and ( c == ";" or ( c == "," and mid >= 0 ) ):
            break
        elif depth == 0 and c == ":" and mid < 0:
            mid = i
        i += 1
    return ( code[ q + 1:mid ], code[ mid + 1:i ] ) if mid >= 0 else None
def opens( body ):
    m = re.search( r"(?<![A-Za-z0-9_])([a-z][a-z0-9_]*)=", body )
    return m.group( 1 ) if m else None

code, lits = lex( open( os.path.join( root, "src", "graphlegend.h" ), encoding = "utf-8" ).read() )
consts = {}
for m in re.finditer( r"\b(k[A-Z]\w*)\s*=\s*((?:\"S\d+\"\s*)+);", code ):
    consts[ m.group( 1 ) ] = "".join( lits[ int( k ) ] for k in re.findall( r"\"S(\d+)\"", m.group( 2 ) ) )
pop = {}
for q in [ m.start() for m in re.finditer( r"\?", code ) ]:
    both = arms( code, q )
    if both is None:
        continue
    a, b = ( set( re.findall( r"\bk[A-Z]\w*", x ) ) for x in both )
    for k in sorted( a ^ b ):
        if k in consts and opens( consts[ k ] ):
            pop.setdefault( opens( consts[ k ] ), "graphlegend.h selects %s conditionally" % k )
for dirpath, dirnames, files in os.walk( os.path.join( root, "src" ) ):
    dirnames.sort()
    for f in sorted( files ):
        if f.endswith( ( ".h", ".cpp" ) ):
            p = os.path.join( dirpath, f )
            for m in re.finditer( r"countAttrXmlOrEmpty\(\s*\"([a-z][a-z0-9_]*)\"", open( p, encoding = "utf-8", errors = "replace" ).read() ):
                pop.setdefault( m.group( 1 ), "countAttrXmlOrEmpty in %s" % os.path.relpath( p, root ) )

ccode, clits = lex( open( os.path.join( root, "src", "compactlegend.h" ), encoding = "utf-8" ).read() )
def table( name ):
    m = re.search( r"\b" + name + r"\s*\[\s*\]\s*=\s*\{(.*?)\};", ccode, re.S )
    return m.group( 1 ) if m else ""
terms  = set( clits[ int( k ) ] for k in re.findall( r"\{\s*\"S(\d+)\"\s*,", table( "kCompactCompletenessTerms" ) ) )
paging = set( clits[ int( k ) ] for t in ( "kCompactPagingAttrs", "kCompactPagingHeadAttrs" ) for k in re.findall( r"\"S(\d+)\"", table( t ) ) )
# A row that reads the map header ALONE (MapHeaderRead::Only) defines an unquoted header field, never a quoted attribute:
# extent_suspect_syms= and macro_blanked_files= are --skipped attributes too, and their live check below must still run.
rows      = table( "kCompactCompletenessTerms" )
hdrTerms  = set( clits[ int( k ) ] for k in re.findall( r"\{\s*\"S(\d+)\"\s*,(?:[^{}]|\{\})*?MapHeaderRead::(?:Only|Also)", rows ) )
onlyHdr   = set( clits[ int( k ) ] for k in re.findall( r"\{\s*\"S(\d+)\"\s*,(?:[^{}]|\{\})*?MapHeaderRead::Only", rows ) )
headTerms = terms - onlyHdr
# presence guards: a reader that broke returns an empty set, and an empty population agrees with any table
if not { "counts_floor", "graph_unindexed", "root" } <= terms or not { "shown", "limit" } <= paging:
    print( "FAIL|the term/paging tables read from src/compactlegend.h are incomplete (terms=%d paging=%d) — the reader broke, so no row here means anything" % ( len( terms ), len( paging ) ) )
    sys.exit( 0 )
if not { "graph_unindexed", "declined_calls", "unproven_defs", "bodyless_defs", "extent_suspect_files" } <= set( pop ):
    print( "FAIL|the helper-family population read from src/ lacks a known member (got: %s) — the reader broke" % " ".join( sorted( pop ) ) )
    sys.exit( 0 )
covered = []
for attr in sorted( pop ):
    if attr in headTerms or attr in paging or attr.endswith( "_capped" ):
        covered.append( attr + "=" )
    else:
        print( "LIVE|%s|%s" % ( attr, pop[ attr ] ) )
print( "PASS|%d of %d helper-family conditional attributes have a compact reading in the term table: %s" % ( len( covered ), len( pop ), " ".join( covered ) ) )

# 3. THE MAP FAMILY (2026-09-12). Two more places a ranked document spells a field whose clause compact strips, both read
#    from source: the PageRank disclosure's XML spelling in src/prconverge.h (` pr_iters="`, ` pr_converged="0"`, on every
#    PageRank-ordered root), and every map-HEADER field src/serialize.h defines as `hdr:NAME=` CONDITIONALLY — in a clause
#    charged only to a map that carries it, or marked absent-if-0 inside the always-on `<!-- ripwire v1` legend. A header
#    field needs a row that READS the map header (MapHeaderRead::Only/Also); a row that reads only the head never sees
#    an unquoted field of a comment, and one that reads the header alone does not cover a quoted root attribute above.
pcode, plits = lex( open( os.path.join( root, "src", "prconverge.h" ), encoding = "utf-8" ).read() )
prs = sorted( set( m.group( 1 ) for s in plits for m in [ re.match( r' ([a-z][a-z0-9_]*)=\\"', s ) ] if m ) )
scode, slits = lex( open( os.path.join( root, "src", "serialize.h" ), encoding = "utf-8" ).read() )
hdr, always = {}, set()
for s in slits:
    for m in re.finditer( r"hdr:([a-z][a-z0-9_]*)=", s ):
        clause = re.split( r" (?:hdr|r):| -->", s[ m.end(): ] )[ 0 ]
        if s.startswith( "<!-- ripwire v1" ) and "absent-if-0" not in clause:
            always.add( m.group( 1 ) )
        else:
            hdr.setdefault( m.group( 1 ), "serialize.h defines hdr:%s= conditionally" % m.group( 1 ) )
if not { "pr_iters", "pr_converged" } <= set( prs ) or not { "declined", "ignored_files", "extent_suspect_syms" } <= set( hdr ) or "unresolved" not in always:
    print( "FAIL|the map-family population read from src/prconverge.h and src/serialize.h lacks a known member (pr: %s; hdr: %s; always-on: %s) — the reader broke" % ( " ".join( prs ), " ".join( sorted( hdr ) ), " ".join( sorted( always ) ) ) )
    sys.exit( 0 )
mapCovered = []
for attr in prs:
    if attr in headTerms:
        mapCovered.append( attr + "=" )
    else:
        print( "FAIL|%s= (prconverge.h spells it on every PageRank-ordered root) has NO kCompactCompletenessTerms row that reads the head — every compact ranked answer carries it undefined" % attr )
for attr in sorted( hdr ):
    if attr in hdrTerms:
        mapCovered.append( "hdr:" + attr + "=" )
    else:
        print( "FAIL|%s= (%s) has no kCompactCompletenessTerms row that reads the map header — a compact map keeps the field and drops its clause" % ( attr, hdr[ attr ] ) )
if len( mapCovered ) == len( prs ) + len( hdr ):
    print( "PASS|map family: %d of %d PageRank attributes and conditional map-header fields have a compact reading: %s" % ( len( mapCovered ), len( prs ) + len( hdr ), " ".join( mapCovered ) ) )

# 4. THE MAP'S ROW FIELDS (2026-09-12, the third sweep): every UNPREFIXED field of the always-on `<!-- ripwire v1` legend
#    whose clause carries an absence marker (`absent-if-N`, `absent=`) — lpin= and overloads= on <s>, prov= on <c>. That
#    legend is prose under compact, and a row field rides deep in the payload, so its term must READ the payload (wholeDoc,
#    or an onTag element): a head-only row never sees an <s>/<c> below the first child, and a header row sees `<!-- files=`.
nextField = re.compile( r"(?<= )(?:hdr:|r:)?[a-z][a-z0-9_]*=| -->" )
rowPop = {}
for s in slits:
    if not s.startswith( "<!-- ripwire v1" ):
        continue
    for m in re.finditer( r"(?<= )([a-z][a-z0-9_]*)=", s ):
        nxt    = nextField.search( s, m.end() )
        clause = s[ m.end():( nxt.start() if nxt else len( s ) ) ]
        if "absent-if-" in clause or "absent=" in clause:
            rowPop.setdefault( m.group( 1 ), "serialize.h's always-on map legend marks %s= absent at its default" % m.group( 1 ) )
rowTerms = set( clits[ int( k ) ] for k in re.findall( r"\{\s*\"S(\d+)\"\s*,\s*\"S\d+\"\s*,\s*true\b", rows ) )
if not { "lpin", "overloads", "prov" } <= set( rowPop ):
    print( "FAIL|the map row-field population read from src/serialize.h lacks a known member (got: %s) — the reader broke" % " ".join( sorted( rowPop ) ) )
else:
    rowCovered = []
    for attr in sorted( rowPop ):
        if attr in rowTerms:
            rowCovered.append( attr + "=" )
        else:
            print( "FAIL|%s= (%s) has no kCompactCompletenessTerms row that reads the payload (wholeDoc or onTag) — a compact map carrying it leaves it undefined" % ( attr, rowPop[ attr ] ) )
    if len( rowCovered ) == len( rowPop ):
        print( "PASS|map rows: %d of %d absence-marked row fields of the always-on legend have a payload-reading compact term: %s" % ( len( rowCovered ), len( rowPop ), " ".join( rowCovered ) ) )
# The always-on header fields (no absent-if-0 marker) ride EVERY map header, so each needs a header reading as much as a
# conditional one does (the fourth sweep, 2026-09-12: unresolved=). Since that sweep's design review the reading may sit inside
# the always-on header clause, the `files` row (MapHeaderRead::Only): buildStats writes files= into every header, so a field
# spelled there is read exactly when the header is. A CONDITIONAL field never qualifies that way (the population above wants a
# row of its own), so a field that gains an absence marker leaves this set and fails there until it is split back out.
hdrClause = None
for m in re.finditer( r"\{\s*\"S(\d+)\"\s*,\s*\"S(\d+)\"(?:[^{}]|\{\})*?MapHeaderRead::Only", rows ):
    if clits[ int( m.group( 1 ) ) ] == "files":
        hdrClause = clits[ int( m.group( 2 ) ) ]
if hdrClause is None:
    print( "FAIL|no always-on map-header row (attr files, MapHeaderRead::Only) was read from src/compactlegend.h — the reader broke, so the always-on row below means nothing" )
    hdrClause = ""
inClause = lambda a: re.search( r"(?<![A-Za-z0-9_])" + re.escape( a ) + r"=", hdrClause ) is not None
alwaysCovered = [ "hdr:" + a + "=" + ( "" if a in hdrTerms else " (in the files= clause)" ) for a in sorted( always ) if a in hdrTerms or inClause( a ) ]
for attr in sorted( always ):
    if attr not in hdrTerms and not inClause( attr ):
        print( "FAIL|%s= (serialize.h's always-on map legend defines hdr:%s= with no absence marker, so EVERY map header carries it) has no compact reading that reads the map header, neither a row of its own nor a clause of the always-on files= row — every compact map carries it undefined" % ( attr, attr ) )
if len( alwaysCovered ) == len( always ):
    print( "PASS|map header, always-on: %d of %d unconditional header fields have a compact reading: %s" % ( len( alwaysCovered ), len( always ), " ".join( alwaysCovered ) ) )
PY
python3 "$TMP/struct.py" "$ROOT" >"$TMP/s.rows" 2>"$TMP/s.err" || no "(S) the source reader crashed: $( head -c 300 "$TMP/s.err" )"
[ -s "$TMP/s.rows" ] || no "(S) the source reader printed no rows — the structural arm would be vacuous"
XHOT="$TMP/xhot"; XLEAK="$TMP/xleak"; mkdir -p "$XHOT" "$XLEAK"
for f in leak.cpp head.c orphan.cpp plain.cpp; do cp "$ROOT/test/extentfix/$f" "$XHOT/" 2>/dev/null || no "(S) fixture missing: test/extentfix/$f"; done
for f in leak_anon.cpp leak_plain.cpp leak_lambda.cpp leak_c.c leak_objc.m leak_cuda.cu leak_partial.cpp; do
    cp "$ROOT/test/macroreparsefix/$f" "$XLEAK/" 2>/dev/null || no "(S) fixture missing: test/macroreparsefix/$f"
done
"$BIN" "$XHOT"  --skipped --legend=compact >"$TMP/s.hot"  2>/dev/null </dev/null
"$BIN" "$XLEAK" --skipped --legend=compact >"$TMP/s.leak" 2>/dev/null </dev/null
liveDoc(){ case "$1" in extent_suspect_files|extent_suspect_syms) printf '%s' "$TMP/s.hot" ;; macro_blanked_files|macro_blanked) printf '%s' "$TMP/s.leak" ;; *) printf '' ;; esac; }
while IFS='|' read -r kind name where <&3; do
    case "$kind" in
        PASS) ok "(S) $name" ;;
        FAIL) no "(S) $name" ;;
        INFO) printf '  INFO  (S) %s\n' "$name" ;;
        LIVE)
            doc="$( liveDoc "$name" )"
            if [ -z "$doc" ]; then
                no "(S) $name= ($where) has NO kCompactCompletenessTerms row — under --legend=compact it reaches the reader undefined"
            elif [ "$( ca carries "$doc" "$name" )" = 1 ] && [ "$( ca defines "$doc" "$name" )" = 1 ]; then
                ok "(S) $name= ($where) needs no term: its --skipped clause is a comment compact KEEPS, verified live (carried and defined)"
            else
                no "(S) $name= ($where) has no term, and its live --skipped compact document does not carry and define it (carried=$( ca carries "$doc" "$name" ) defined=$( ca defines "$doc" "$name" ))"
            fi ;;
        *) no "(S) unreadable row from the source reader: $kind|$name|$where" ;;
    esac
done 3<"$TMP/s.rows"

[ "$fail" -eq 0 ] && echo 'ALL PASS' || echo 'FAILURES ABOVE'
exit "$fail"
