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
run(){ "$BIN" "$FIX" "$@" --no-cache 2>"$TMP/err"; }

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

# ── a tmp git fixture: test/fixture's files with three commits, so the git verbs answer too ─────────────
REPO="$TMP/repo"; mkdir -p "$REPO"; cp -R "$FIX"/. "$REPO"/
( cd "$REPO" && git init -q && git config user.email "t@example.com" && git config user.name "t" \
  && git add -A && git commit -q -m "one" \
  && printf '\n// two\n' >> geometry.cpp && git commit -q -am "two" \
  && printf '\n// three\n' >> geometry.cpp && git commit -q -am "three" ) || { echo "fixture git setup failed"; exit 2; }
printf 'at distance (geometry.cpp:5)\n' > "$TMP/trace.txt"
printf 'callers: distance\nuses: distance\n' > "$TMP/batch.txt"
rrun(){ ( cd "$REPO" && "$BIN" . "$@" --no-cache 2>"$TMP/rerr" ); }

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
    ( cd "$REPO" && "$BIN" . "$probe" --no-cache >"$TMP/u.full" 2>"$TMP/u.fullerr" </dev/null ); rcFull=$?
    isxml="$( leg isxml "$TMP/u.full" )"
    if [ "$isxml" != "1" ]; then
        # not an XML answer (a refusal, text, JSON, html): compact must refuse — or, when the default itself
        # refused, refuse for its own reason (compact must not turn a refusal into an answer)
        ( cd "$REPO" && "$BIN" . "$probe" --legend=compact --no-cache >"$TMP/u.c" 2>"$TMP/u.cerr" </dev/null ); rcC=$?
        if [ "$rcC" -ne 0 ] && [ ! -s "$TMP/u.c" ]; then
            nRefuse=$(( nRefuse + 1 ))
        else
            no "(U) $probe: not XML at defaults (exit=$rcFull) yet --legend=compact exited $rcC with $( wc -c <"$TMP/u.c" | tr -d ' ' ) B on stdout"
        fi
        continue
    fi
    nXml=$(( nXml + 1 )); name="${flag%%=*}"; xmlVerbs="$xmlVerbs $name"
    ( cd "$REPO" && "$BIN" . "$probe" --legend=compact --no-cache >"$TMP/u.c" 2>"$TMP/u.cerr" </dev/null ); rcC=$?
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
    if [ "$flag" != "--for=" ]; then
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
mcp_text edit_check '{"path":".","symbol":"total_area"}' >"$TMP/m.ecf"
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

[ "$fail" -eq 0 ] && echo 'ALL PASS' || echo 'FAILURES ABOVE'
exit "$fail"
