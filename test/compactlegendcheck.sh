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
#   • the root carries schema="ripwire.<key>/v1"; the legend (= every <!-- --> comment outside CDATA) is
#     ≤ 400 B and names every completeness attribute the document carries (counts_floor / capped / shown /
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
# everything else must refuse it. LOOP arm (L): the ten-verb loop's compact legend bill ≤ 4,100 B (was 29,824
# on the ripwire tree). MCP arm (M): edit_check with legend:"compact" answers in ≤ 900 B on a clean tree.
# CONDITIONAL arm (D): an absent-at-zero or form-conditional attribute (declined_calls=, unproven_defs=, bodyless_defs=,
# the member form, the multi-root <root label=> rows, --lego's caveat=; on the map family and --impact: pr_iters=,
# pr_converged=, the map header's gauges, --around's defs=, --rank-by's rank_by=/window=; in the third sweep: --tree's
# files=, --zoom's root counts and <module children=>, churn-decay's <recent>, the map rows' lpin=/overloads=/prov=) is
# DEFINED by the compact legend of a document that carries it, and by none that does not. STRUCTURAL arm (S): every
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
        *)      [ "$lb" -le 400 ] || no "(U) $probe compact PROSE legend is $lb B (> 400 B; all comments $lball B, full $lbfull B): $( leg legend "$TMP/u.c" | head -c 200 )" ;;
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
[ "$nXml" -ge 60 ] && [ "$nXmlBad" -eq 0 ] && ok "(U) $nXml XML flags answer under --legend=compact (schema id, ≤400 B legend, rows byte-identical, root attrs kept):$xmlVerbs" \
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
echo "=== (L) the canonical ten-verb edit loop: compact legend bill ≤ 4,100 B (29,824 B in full on the ripwire tree) ==="
loopBytes=0; fullBytes=0
for v in "--for=geometry distance" "--callers=distance" "--impact=distance" "--uses=distance" "--edit-check=total_area" \
         "--quality-delta" "--test-gate=geometry.cpp" "--affected=geometry.cpp" "--safe-delete=total_area" "--slice=total_area"; do
    rrun "$v" --legend=compact >"$TMP/l.c"; rrun "$v" >"$TMP/l.f"
    [ -s "$TMP/l.c" ] || no "(L) $v --legend=compact answered NOTHING (a refusal is not a 0 B legend): $( head -c 120 "$TMP/rerr" )"
    b="$( leg bytes "$TMP/l.c" )"; f="$( leg bytes "$TMP/l.f" )"
    loopBytes=$(( loopBytes + b )); fullBytes=$(( fullBytes + f ))
done
[ "$loopBytes" -le 4100 ] && ok "(L) ten-verb loop: $loopBytes B of compact legend (full: $fullBytes B)" \
                          || no "(L) ten-verb loop pays $loopBytes B of compact legend (> 4,100 B; full: $fullBytes B)"

echo
echo "=== (M) MCP: legend:\"compact\" on edit_check answers in ≤ 900 B on a clean tree; every XML verb takes the argument ==="
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
for pair in "impact:{\"path\":\".\",\"symbol\":\"distance\",\"legend\":\"compact\"}" \
            "uses:{\"path\":\".\",\"symbol\":\"distance\",\"legend\":\"compact\"}" \
            "path_between:{\"path\":\".\",\"from\":\"total_area\",\"to\":\"distance\",\"legend\":\"compact\"}" \
            "lego:{\"path\":\".\",\"type\":\"Point\",\"legend\":\"compact\"}" \
            "exemplar:{\"path\":\".\",\"kind\":\"fn\",\"task\":\"distance\",\"legend\":\"compact\"}"; do
    verb="${pair%%:*}"; args="${pair#*:}"
    mcp_text "$verb" "$args" >"$TMP/m.v"
    if grep -q '^__ERROR__' "$TMP/m.v"; then
        no "(M) MCP $verb legend:compact refused: $( head -c 160 "$TMP/m.v" )"
    elif [ "$( leg bytes "$TMP/m.v" )" -le 400 ] && [ -n "$( leg schema "$TMP/m.v" )" ]; then
        ok "(M) MCP $verb legend:compact: $( leg bytes "$TMP/m.v" ) B legend, schema $( leg schema "$TMP/m.v" )"
    else
        no "(M) MCP $verb legend:compact: legend $( leg bytes "$TMP/m.v" ) B, schema '$( leg schema "$TMP/m.v" )'"
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
if isHdr:
    vals = [ m.group( 1 ) for h in header for m in [ re.search( r"\s" + re.escape( attr ) + r"=([^\s\"]+)", h ) ] if m ]
else:
    vals = [ m.group( 1 ) for t in tags if on( t ) for m in [ re.search( r"\s" + re.escape( attr ) + r"=\"([^\"]*)\"", t ) ] if m ]
leg = " ".join( legend )
if op == "carries":    print( 1 if vals else 0 )
elif op == "value":    print( vals[ 0 ] if vals else "" )
elif op == "defines":  print( 1 if re.search( r"(?<![A-Za-z0-9_])" + re.escape( attr ) + "=", leg ) else 0 )
elif op == "mentions": print( 1 if spec in leg else 0 )   # a literal needle anywhere in the legend
PY
ca(){ python3 "$TMP/condattr.py" "$@"; }
# condArm ID LABEL FULL COMPACT SPEC… — the control, then the compact definition, one verdict row per document
condArm()
{
    local id="$1" label="$2" full="$3" comp="$4" spec attr bad=0 got=""
    shift 4
    for spec in "$@"; do
        attr="${spec#*:}"; attr="${attr#\#}"
        if [ "$( ca carries "$full" "$spec" )" != 1 ] || [ "$( ca carries "$comp" "$spec" )" != 1 ]; then
            no "($id) $label: control broken — the answer does not carry $attr= in both postures, so its definition row would be vacuous: $( head -c 160 "$comp" )"
            bad=1; continue
        fi
        if [ "$( ca defines "$full" "$attr" )" != 1 ]; then
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
        if [ "$( ca defines "$TMP/d12.c" "$attr" )" = 1 ] && [ "$( ca carries "$TMP/d12.c" "$spec" )" != 1 ]; then
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
# NOT FIXED, stopped on the (U) 400 B pin: --communities' drill= and isolated=. Its compact prose is 385 B on this gate's
# repo; the shortest honest pair ("drill= takes an id=; isolated= edgeless symbols") costs 49 B (434 B), and even
# "drill=/isolated=: id= verb/edgeless" costs 37 B (422 B). No ceiling is raised for it.
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
# --rank-by's rank_by=/window=) — (D10)/(D11) guard those. And BY CONSTRUCTION not the always-on header field unresolved=
# (no absent-if-0 marker), which the reader prints as INFO on every run because it is STILL undefined under compact: its
# shortest reading, "unresolved=: resolver gauge", costs 29 B on every map and puts two (U) probes over the 400 B ceiling
# (--max-tokens=3 379 -> 408, --rank-by=churn 376 -> 405 over their measured legends). No ceiling is raised for it.
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
print( "INFO|outside that population by construction (unconditional on every map, no absent-if-0 marker): %s — still undefined under compact, see the arm's comment" % " ".join( a + "=" for a in sorted( always ) ) )
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
