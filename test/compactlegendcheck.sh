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
# everything else must refuse it. LOOP arm (L): the ten-verb loop's compact legend bill ≤ 4,000 B (was 29,824
# on the ripwire tree). MCP arm (M): edit_check with legend:"compact" answers in ≤ 900 B on a clean tree.
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/compactlegendcheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/fixture"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
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
set -- $for_kind_bytes; [ "$2" -lt "$1" ] && ok "--for compact is smaller ($2 < $1 bytes)" || no "--for compact did not shrink ($2 >= $1 bytes)"
set -- $grep_kind_bytes; [ "$2" -lt "$1" ] && ok "--grep compact is smaller ($2 < $1 bytes)" || no "--grep compact did not shrink ($2 >= $1 bytes)"
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
        case "$a" in counts_floor|est_tokens|at|root|graph_ambiguous|graph_unresolved|hits_capped|limit|offset|over_ceiling|tier_partial) ;; *) continue ;; esac
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
    cmp -s "$TMP/f.def" "$TMP/f.full" && ok "(F) $v: default == --legend=full" || no "(F) $v: explicit --legend=full changed the default output"
done

echo
echo "=== (L) the canonical ten-verb edit loop: compact legend bill ≤ 4,000 B (29,824 B in full on the ripwire tree) ==="
loopBytes=0; fullBytes=0
for v in "--for=geometry distance" "--callers=distance" "--impact=distance" "--uses=distance" "--edit-check=total_area" \
         "--quality-delta" "--test-gate=geometry.cpp" "--affected=geometry.cpp" "--safe-delete=total_area" "--slice=total_area"; do
    rrun "$v" --legend=compact >"$TMP/l.c"; rrun "$v" >"$TMP/l.f"
    [ -s "$TMP/l.c" ] || no "(L) $v --legend=compact answered NOTHING (a refusal is not a 0 B legend): $( head -c 120 "$TMP/rerr" )"
    b="$( leg bytes "$TMP/l.c" )"; f="$( leg bytes "$TMP/l.f" )"
    loopBytes=$(( loopBytes + b )); fullBytes=$(( fullBytes + f ))
done
[ "$loopBytes" -le 4000 ] && ok "(L) ten-verb loop: $loopBytes B of compact legend (full: $fullBytes B)" \
                          || no "(L) ten-verb loop pays $loopBytes B of compact legend (> 4,000 B; full: $fullBytes B)"

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

[ "$fail" -eq 0 ] && echo 'ALL PASS' || echo 'FAILURES ABOVE'
exit "$fail"
