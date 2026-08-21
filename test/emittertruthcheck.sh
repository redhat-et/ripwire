#!/usr/bin/env bash
# emittertruthcheck.sh — the gate for the r27-emitters lane ( items 1, 2, 8,
# 10, 14). Every check here pins a behavior that USED to lie to the caller: a truncated list with no marker,
# a refusal that shipped a payload anyway, a "not reachable" that was reachable, and an "unknown flag" that
# was really an unknown value.
#
# Asserts:
#   P2.1  silent truncation — total=/shown=/capped= (the --communities / --graph-query vocabulary):
#           --impact             reaches= is the TRUE radius, shown= the printed slice, capped="1" when cut
#           --match              hits=/shown=/capped= + hits_capped= (hits= is a FLOOR at the engine limit)
#           --grep               hits=/shown=/capped= + hits_capped= (collection-budget floor)
#           --seams              seam_pairs=/shown=/capped=, and per-<seam> untested=/shown=/capped=
#           --external-surface   names=/shown=/capped=
#           the UNtruncated case reports capped="0" and shown==total (no false alarm)
#           --impact --json and --format=columnar carry the same shown=/capped= as the XML
#   P2.2  --top-k=0 = "payload only": `--top-k=0 --expand=X` EMITS THE BODY (it used to emit zero bytes),
#         is strictly smaller than the default ride-along run, stays xmllint-clean, and --top-k=0 with no
#         payload verb is refused with exit 1 (never a zero-byte success)
#   P2.8  error-path hygiene: --expand/--outline on a missing symbol exit 1 with ZERO bytes on stdout (the
#         22 KB unrelated-map payload is gone); --uses on a name with no def AND no reference site exits 1
#         with a did-you-mean, while a genuine EXTERNAL symbol (no def, real reference sites) still exits 0
#         with external="1" — the documented feature is preserved
#   P2.10 --path echoes the def it actually bound (from_p=/to_p=) and how many it could have (from_defs=/
#         to_defs=), reaches the RIGHT def when a name has many (the old lowest-NodeId bind reported
#         reachable="0" for a path that exists), and prints hint="… --connect=A,B …" on a real dead end
#   P2.14 --rank-by=BOGUS / --format=BOGUS name the unknown VALUE and list the supported set (they used to
#         claim the FLAG did not exist); every supported value still parses
#   G4    every changed emitter stays xmllint-clean
#   G5    the DEFAULT map (`ripwire <dir>`, no flags) is byte-identical across two runs and gained no
#         attribute from this lane — flags stayed additive
#
# Usage:
#   test/emittertruthcheck.sh
#   RIPWIRE_BIN=asan/ripwire test/emittertruthcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

# attribute reader: attr <file> <name>  ->  the first value of name="…"
attr(){ sed -n "s/.*[[:space:]]$2=\"\([^\"]*\)\".*/\1/p" "$1" | head -1; }
has(){ grep -q "$2" "$1"; }

# ---------------------------------------------------------------------------------------------------
# a corpus with a KNOWN, large blast radius so the 40-row --impact cap is guaranteed to engage, plus a
# same-name-in-two-files pair so the --path multi-def bind is exercised deterministically.
# ---------------------------------------------------------------------------------------------------
SRC="$TMP/corpus"
mkdir -p "$SRC/lib" "$SRC/app"

cat > "$SRC/lib/core.c" <<'EOF'
int leaf( int x ) { return x + 1; }
EOF

# 60 distinct callers of leaf() → reaches=60 > the 40-row cap. They live in app/ so the same 60 edges are
# also one app→lib SEAM with far more than the 5 example edges a <seam> prints — that is the --seams cut.
{
  echo 'int leaf( int x );'
  i=0
  while [ "$i" -lt 60 ]; do
    printf 'int caller_%02d( int x ) { return leaf( x ); }\n' "$i"
    i=$(( i + 1 ))
  done
} > "$SRC/app/callers.c"

# a call to a name this corpus never DEFINES — the genuine external-dependency case that --uses'
# external="1" and --external-surface both exist to report.
cat > "$SRC/app/ext.c" <<'EOF'
int shout( void )  { return zz_undefined_helper( 1 ); }
int shout2( void ) { return zz_undefined_beta( 2 ); }
int shout3( void ) { return zz_undefined_gamma( 3 ); }
int shout4( void ) { return zz_undefined_delta( 4 ); }
EOF

# two defs of entry(): the one in lib/ sorts first by path (lower NodeId) and is a DEAD END; the one in
# app/ genuinely reaches deep(). The old lowest-id bind picked lib/ and answered reachable="0".
cat > "$SRC/lib/entry_stub.c" <<'EOF'
int entry( void ) { return 0; }
EOF

cat > "$SRC/app/main.c" <<'EOF'
int deep( int x ) { return x * 2; }
int middle( int x ) { return deep( x ); }
int entry( void ) { return middle( 7 ); }
int orphan( void ) { return 3; }
EOF

echo "== P2.1 silent truncation: --impact =="
"$BIN" "$SRC" --impact=leaf > "$TMP/impact.xml" 2>/dev/null
rch="$( attr "$TMP/impact.xml" reaches )"; shw="$( attr "$TMP/impact.xml" shown )"; cap="$( attr "$TMP/impact.xml" capped )"
rows="$( grep -o '<s ' "$TMP/impact.xml" | wc -l | tr -d ' ' )"
[ "$rch" = "60" ]                 && ok "--impact reaches=60 (true blast radius)"        || no "--impact reaches='$rch' (want 60)"
[ "$shw" = "40" ]                 && ok "--impact shown=40 (printed slice)"              || no "--impact shown='$shw' (want 40)"
[ "$cap" = "1" ]                  && ok "--impact capped=1 on a truncated listing"       || no "--impact capped='$cap' (want 1)"
[ "$rows" = "$shw" ]              && ok "--impact shown= equals the row count ($rows)"   || no "--impact shown='$shw' but printed $rows rows"

"$BIN" "$SRC" --impact=middle > "$TMP/impact_small.xml" 2>/dev/null
srch="$( attr "$TMP/impact_small.xml" reaches )"; sshw="$( attr "$TMP/impact_small.xml" shown )"; scap="$( attr "$TMP/impact_small.xml" capped )"
[ "$scap" = "0" ] && [ "$srch" = "$sshw" ] && ok "--impact capped=0 + shown==reaches when nothing was cut" \
                                           || no "--impact untruncated: reaches='$srch' shown='$sshw' capped='$scap'"

"$BIN" "$SRC" --impact=leaf --json > "$TMP/impact.json" 2>/dev/null
# The JSON page disclosure is pageDisclosure's seven-key vocabulary now, so
# `capped` is a JSON BOOLEAN (true/false) rather than the 0/1 the hand-rolled pair emitted — the XML attribute
# keeps "0"/"1", the JSON sibling spells the same fact the way JSON spells booleans, and both are ALWAYS
# present rather than inferable from a missing key.
has "$TMP/impact.json" '"shown":40'     && ok "--impact --json carries shown"     || no "--impact --json lost shown"
has "$TMP/impact.json" '"capped":true'  && ok "--impact --json carries capped"    || no "--impact --json lost capped"

"$BIN" "$SRC" --impact=leaf --format=columnar > "$TMP/impact.col" 2>/dev/null
has "$TMP/impact.col" 'shown="40"'   && ok "--impact --format=columnar carries shown"  || no "--impact columnar lost shown"
has "$TMP/impact.col" 'capped="1"'   && ok "--impact --format=columnar carries capped" || no "--impact columnar lost capped"

echo "== P2.1 silent truncation: --match / --grep / --seams / --external-surface =="
"$BIN" "$SRC" --match='(call_expression function: (identifier) @f)' --pack-top-n=5 > "$TMP/match.xml" 2>/dev/null
mh="$( attr "$TMP/match.xml" hits )"; ms="$( attr "$TMP/match.xml" shown )"; mc="$( attr "$TMP/match.xml" capped )"
mrows="$( grep -o '<m ' "$TMP/match.xml" | wc -l | tr -d ' ' )"
[ -n "$mh" ] && [ "$ms" = "5" ] && [ "$mc" = "1" ] && [ "$mrows" = "5" ] \
    && ok "--match hits=$mh shown=5 capped=1 over 5 rows" || no "--match hits='$mh' shown='$ms' capped='$mc' rows=$mrows"
has "$TMP/match.xml" 'hits_capped='  && ok "--match reports hits_capped (hits= floor vs total)" || no "--match has no hits_capped"

"$BIN" "$SRC" --grep=leaf --pack-top-n=4 > "$TMP/grep.xml" 2>/dev/null
gh="$( attr "$TMP/grep.xml" hits )"; gs="$( attr "$TMP/grep.xml" shown )"; gc="$( attr "$TMP/grep.xml" capped )"
grows="$( grep -o '<hit ' "$TMP/grep.xml" | wc -l | tr -d ' ' )"
[ "$gs" = "4" ] && [ "$gc" = "1" ] && [ "$grows" = "4" ] \
    && ok "--grep hits=$gh shown=4 capped=1 over 4 rows" || no "--grep hits='$gh' shown='$gs' capped='$gc' rows=$grows"
has "$TMP/grep.xml" 'hits_capped='   && ok "--grep reports hits_capped (collection-budget floor)" || no "--grep has no hits_capped"

"$BIN" "$SRC" --seams > "$TMP/seams.xml" 2>/dev/null
has "$TMP/seams.xml" 'seam_pairs='        && ok "--seams reports seam_pairs (total)"        || no "--seams has no seam_pairs"
# §P8 vocabulary: the root said shown_seam_pairs= AND capped= — the noun-prefixed spelling and the bare one
# in a single element. The root has ONE listing, so it is the bare pair now (src/pageview.h, THE TRUNCATION
# VOCABULARY, rule 1); the noun prefix is reserved for elements carrying SEVERAL independent listings.
grep -q '<seams [^>]*seam_pairs="[0-9]*" shown="[0-9]*" capped="[01]"' "$TMP/seams.xml" \
    && ok "--seams root carries seam_pairs=/shown=/capped= (one convention, not two)" \
    || no "--seams root does not carry the bare seam_pairs=/shown=/capped= triple"
has "$TMP/seams.xml" 'shown_seam_pairs=' \
    && no "--seams still emits shown_seam_pairs= (the noun-prefixed form was retired)" \
    || ok "--seams no longer emits shown_seam_pairs= beside a bare capped="
grep -q '<seam [^>]*untested="[0-9]*" shown="[0-9]*" capped="[01]"' "$TMP/seams.xml" \
    && ok "--seams per-<seam> carries untested=/shown=/capped=" || no "--seams <seam> row lacks shown=/capped="

"$BIN" "$SRC" --external-surface --pack-top-n=2 > "$TMP/ext.xml" 2>/dev/null
en="$( attr "$TMP/ext.xml" names )"; es="$( attr "$TMP/ext.xml" shown )"; ec="$( attr "$TMP/ext.xml" capped )"
[ "$es" = "2" ] && [ "$ec" = "1" ] && ok "--external-surface names=$en shown=2 capped=1" \
                                   || no "--external-surface names='$en' shown='$es' capped='$ec'"

echo "== P2.2 --top-k=0 emits the requested payload, not zero bytes =="
"$BIN" "$SRC" --top-k=0 --expand=middle > "$TMP/tk0.xml" 2>/dev/null; tk0rc=$?
"$BIN" "$SRC" --expand=middle           > "$TMP/tkd.xml" 2>/dev/null
n0="$( wc -c < "$TMP/tk0.xml" | tr -d ' ' )"; nd="$( wc -c < "$TMP/tkd.xml" | tr -d ' ' )"
[ "$tk0rc" = "0" ]        && ok "--top-k=0 --expand exits 0"                            || no "--top-k=0 --expand exit=$tk0rc"
[ "$n0" -gt 0 ]           && ok "--top-k=0 --expand emits $n0 bytes (was 0 — the body vanished)" || no "--top-k=0 --expand emitted 0 bytes"
has "$TMP/tk0.xml" 'middle' && ok "--top-k=0 --expand contains the requested body"      || no "--top-k=0 --expand has no body"
[ "$n0" -lt "$nd" ]       && ok "--top-k=0 ($n0 B) < default ride-along run ($nd B)"    || no "--top-k=0 $n0 B not smaller than $nd B"
grep -q '<r ' "$TMP/tk0.xml" && no "--top-k=0 still emitted the ranked map" || ok "--top-k=0 emitted NO ranked map"

# --token-budget must still gate on what was ACTUALLY emitted: serialize() normally folds the body tokens
# into est_tokens, and with the map suppressed it never runs — the budget would otherwise pass on 0 no
# matter how large the payload.
"$BIN" "$SRC" --top-k=0 --expand=middle --token-budget=1 > /dev/null 2>&1; tbrc=$?
[ "$tbrc" = "3" ] && ok "--top-k=0 still honors --token-budget (exit 3 on overrun)" \
                  || no "--top-k=0 --token-budget=1 exit=$tbrc (want 3 — budget went blind)"
"$BIN" "$SRC" --top-k=0 --expand=middle --token-budget=100000 > /dev/null 2>&1; tbrc2=$?
[ "$tbrc2" = "0" ] && ok "--top-k=0 under a generous --token-budget exits 0" || no "--top-k=0 generous budget exit=$tbrc2"

"$BIN" "$SRC" --top-k=0 > "$TMP/tk0alone.xml" 2>/dev/null; alonerc=$?
na="$( wc -c < "$TMP/tk0alone.xml" | tr -d ' ' )"
[ "$alonerc" != "0" ] && [ "$na" = "0" ] && ok "--top-k=0 with no payload verb: exit $alonerc, 0 bytes" \
                                         || no "--top-k=0 alone: exit=$alonerc bytes=$na (want non-zero exit, 0 bytes)"

echo "== P2.8 a refusal ships no payload =="
# §P12.1: didYouMean() now does true bounded edit distance and honestly omits a suggestion when nothing in
# the corpus is within a few edits (the old shared-prefix*4-lenDelta score always forced SOME guess, however
# nonsensical). "NoSuchSymbolZZZ" was never meant to be a plausible near-miss — it existed only to exercise
# the missing-symbol exit/payload path — so it no longer reliably carries a "did you mean" and testing that
# would be pinning the old bug, not a contract. Switched to "entryy", a genuine 1-edit typo of this
# fixture's real "entry" symbol, so the did-you-mean assertions test the actual (fixed) behavior.
"$BIN" "$SRC" --expand=entryy > "$TMP/exmiss.out" 2>"$TMP/exmiss.err"; exrc=$?
nx="$( wc -c < "$TMP/exmiss.out" | tr -d ' ' )"
[ "$exrc" = "1" ] && ok "--expand=MISSING exits 1"                     || no "--expand=MISSING exit=$exrc (want 1)"
[ "$nx" = "0" ]   && ok "--expand=MISSING writes 0 bytes to stdout"    || no "--expand=MISSING wrote $nx bytes of payload"
has "$TMP/exmiss.err" 'did you mean' && ok "--expand=MISSING keeps its did-you-mean" || no "--expand=MISSING lost did-you-mean"

"$BIN" "$SRC" --outline=entryy > "$TMP/olmiss.out" 2>/dev/null; olrc=$?
no_="$( wc -c < "$TMP/olmiss.out" | tr -d ' ' )"
[ "$olrc" = "1" ] && [ "$no_" = "0" ] && ok "--outline=MISSING exits 1 with 0 bytes" \
                                      || no "--outline=MISSING exit=$olrc bytes=$no_"

"$BIN" "$SRC" --uses=entryy > "$TMP/usmiss.out" 2>"$TMP/usmiss.err"; usrc=$?
nu="$( wc -c < "$TMP/usmiss.out" | tr -d ' ' )"
[ "$usrc" = "1" ] && ok "--uses=MISSING exits 1 like its six siblings"  || no "--uses=MISSING exit=$usrc (want 1)"
[ "$nu" = "0" ]   && ok "--uses=MISSING writes 0 bytes"                 || no "--uses=MISSING wrote $nu bytes"
has "$TMP/usmiss.err" 'did you mean' && ok "--uses=MISSING offers a did-you-mean" || no "--uses=MISSING has no did-you-mean"

# the DOCUMENTED external case must survive: zz_undefined_helper is CALLED in app/ext.c but defined nowhere.
"$BIN" "$SRC" --uses=zz_undefined_helper > "$TMP/usext.out" 2>/dev/null; usextrc=$?
uext="$( attr "$TMP/usext.out" external )"; ucnt="$( attr "$TMP/usext.out" count )"
[ "$usextrc" = "0" ] && ok "--uses on a genuine external symbol still exits 0" || no "--uses external exit=$usextrc"
[ "$uext" = "1" ] && [ "${ucnt:-0}" -gt 0 ] && ok "--uses external=\"1\" count=$ucnt preserved (def-less but referenced)" \
                                            || no "--uses external='$uext' count='$ucnt' — the documented feature broke"

echo "== P2.10 --path: which def, and a pivot on a dead end =="
"$BIN" "$SRC" --path=entry,deep > "$TMP/path.xml" 2>/dev/null
pr="$( attr "$TMP/path.xml" reachable )"; pfd="$( attr "$TMP/path.xml" from_defs )"; pfp="$( attr "$TMP/path.xml" from_p )"
[ "$pfd" = "2" ] && ok "--path from_defs=2 makes the ambiguity visible"   || no "--path from_defs='$pfd' (want 2)"
[ -n "$pfp" ]    && ok "--path echoes the bound def from_p=$pfp"          || no "--path has no from_p"
[ "$pr" = "1" ]  && ok "--path finds the path through the RIGHT def (was reachable=0)" || no "--path reachable='$pr' (want 1)"
has "$TMP/path.xml" 'to_p='      && ok "--path echoes to_p"       || no "--path has no to_p"
has "$TMP/path.xml" 'to_defs='   && ok "--path echoes to_defs"    || no "--path has no to_defs"

"$BIN" "$SRC" --path=orphan,leaf > "$TMP/dead.xml" 2>/dev/null
dr="$( attr "$TMP/dead.xml" reachable )"
[ "$dr" = "0" ] && ok "--path reports reachable=0 on a genuine dead end"  || no "--path dead end reachable='$dr'"
has "$TMP/dead.xml" 'hint='          && ok "--path dead end carries a hint="       || no "--path dead end has no hint="
has "$TMP/dead.xml" 'connect=orphan,leaf' && ok "--path hint names --connect=A,B"  || no "--path hint does not name --connect=A,B"
grep -q 'hint=' "$TMP/path.xml" && no "--path emits a hint on a REACHABLE path (should not)" || ok "--path emits no hint when reachable"

echo "== P2.14 an unknown VALUE is not an unknown FLAG =="
"$BIN" "$SRC" --rank-by=bogus > /dev/null 2>"$TMP/rb.err"; rbrc=$?
[ "$rbrc" != "0" ] && ok "--rank-by=bogus exits non-zero ($rbrc)"                     || no "--rank-by=bogus exit=0"
has "$TMP/rb.err" "unknown value 'bogus'" && ok "--rank-by names the unknown VALUE"   || no "--rank-by still blames the flag: $( cat "$TMP/rb.err" )"
has "$TMP/rb.err" 'pagerank'              && ok "--rank-by lists the supported set"   || no "--rank-by lists no supported values"
grep -q "unknown flag" "$TMP/rb.err" && no "--rank-by still says 'unknown flag'" || ok "--rank-by no longer says 'unknown flag'"

"$BIN" "$SRC" --format=bogus > /dev/null 2>"$TMP/fm.err"; fmrc=$?
[ "$fmrc" != "0" ] && ok "--format=bogus exits non-zero ($fmrc)"                      || no "--format=bogus exit=0"
has "$TMP/fm.err" "unknown value 'bogus'" && ok "--format names the unknown VALUE"    || no "--format still blames the flag: $( cat "$TMP/fm.err" )"
has "$TMP/fm.err" 'columnar'              && ok "--format lists the supported set"    || no "--format lists no supported values"

# §P6.7 (2026-07-28 output audit): the error text's advertised value set must equal the set that ACTUALLY
# WORKS — this is the deckcheck fabrication class, in the binary's own error string, where deckcheck cannot
# see it. Extract the "(supported: a|b|c)" list from the live error text itself (not a hardcoded copy of it)
# and assert every one of those values actually parses with exit 0.
fmsupported="$( grep -oE '\(supported: [^)]+\)' "$TMP/fm.err" | sed -E 's/\(supported: //; s/\)//' )"
[ -n "$fmsupported" ] && ok "--format error names a supported set to reconcile against" || no "--format error has no (supported: …) list to reconcile"
IFS='|' read -r -a fmvalues <<< "$fmsupported"
# Each value is exercised on a verb it is DEFINED for.: columnar/rows on the bare map
# used to exit 0 by ignoring the flag, so testing them there proved the accept-and-ignore bug rather than the
# feature; they now refuse there, and the honest probe is the flat-list verb they actually re-serialize —
# exactly the shape `candidates` (a --for/--query-only value) has always needed.
fmprobe(){ # $1 = --format value → the verb that value is defined for
    case "$1" in
        candidates)    printf '%s' "--query=leaf" ;;
        columnar|rows) printf '%s' "--callers=leaf" ;;
        *)             printf '%s' "--top-k=2" ;;
    esac
}
for v in "${fmvalues[@]}"; do
    "$BIN" "$SRC" "$( fmprobe "$v" )" "--format=$v" > /dev/null 2>&1 \
        && ok "--format=$v (as advertised in the error text) actually works" \
        || no "--format=$v is advertised in the error text but does not work"
done

# The other half of the same reconciliation: every value the error string advertises must also be documented
# in --help — a real, working value that --help omits is exactly the fabrication class deckcheck exists to
# catch, just in text deckcheck cannot see (the binary's own --help/error strings, not a doc file).
helptext="$( "$BIN" --help 2>&1 )"
# collect every value --help actually advertises after "--format=" (e.g. "--format=xml|columnar|rows" and
# the standalone "--format=candidates" line), then check each error-advertised value is among them — not a
# bare substring match, which "rows"/"xml" would false-match against unrelated English prose elsewhere in
# --help (e.g. "New-symbol rows are still PRINTED").
helpvalues="$( echo "$helptext" | grep -oE -- '--format=[a-zA-Z|]+' | sed -E 's/--format=//' | tr '|' '\n' | sort -u )"
for v in "${fmvalues[@]}"; do
    echo "$helpvalues" | grep -qxF -- "$v" \
        && ok "--help documents --format=$v (matches the error text's advertised set)" \
        || no "--help does NOT document --format=$v, but the error text advertises it as supported"
done

# every documented value still parses
for v in pagerank authority hub rrf churn; do
    "$BIN" "$SRC" "--rank-by=$v" --top-k=2 > /dev/null 2>&1 \
        && ok "--rank-by=$v still accepted" || no "--rank-by=$v regressed"
done
for v in xml columnar rows; do
    "$BIN" "$SRC" "$( fmprobe "$v" )" "--format=$v" > /dev/null 2>&1 \
        && ok "--format=$v still accepted" || no "--format=$v regressed"
done
"$BIN" "$SRC" --query=leaf --format=candidates > /dev/null 2>&1 \
    && ok "--format=candidates still accepted" || no "--format=candidates regressed"
# §A5b, the other direction: a value that is real on ITS verb must REFUSE on a verb it cannot re-serialize,
# instead of exiting 0 unchanged. (--format=xml is the default shape, so it stays legal everywhere.)
for v in columnar rows; do
    "$BIN" "$SRC" --hotspots "--format=$v" > /dev/null 2>&1 \
        && no "--format=$v on --hotspots exits 0 — accepted and silently ignored" \
        || ok "--format=$v refuses on a verb with no flat row list (§A5b)"
done

echo "== G4 xmllint on every changed emitter =="
xmlok(){
    "$BIN" "$SRC" "$@" > "$TMP/g4.xml" 2>/dev/null
    if xmllint --noout "$TMP/g4.xml" 2>/dev/null; then ok "xmllint clean: $*"; else no "xmllint FAILED: $*"; fi
}
if command -v xmllint > /dev/null 2>&1; then
    xmlok --impact=leaf
    xmlok --seams
    xmlok --external-surface
    xmlok --path=entry,deep
    xmlok --path=orphan,leaf
    xmlok --grep=leaf
    xmlok --match='(call_expression function: (identifier) @f)'
    xmlok --top-k=0 --expand=middle
else
    echo "  SKIP  xmllint unavailable"
fi

echo "== MCP/CLI parity: the agent-facing surface must not keep the old lie =="
# The MCP `impact` and `path` verbs are SEPARATE emitters (mcpverbs.h), so a CLI-only fix would leave the
# surface most agents actually use still reporting 40-of-N with no marker and reachable="0" for a path that
# exists. Both verbs now carry the same attributes as the CLI.
if command -v python3 > /dev/null 2>&1; then
    mcp_text(){
        printf '%s\n%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' "$1" | "$BIN" --mcp 2>/dev/null | tail -1 |
        python3 -c 'import sys,json; r=json.load(sys.stdin); print("" if "error" in r else r["result"]["content"][0]["text"])'
    }
    mcp_text '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"impact","arguments":{"path":"'"$SRC"'","symbol":"leaf"}}}' > "$TMP/mcp_impact.xml"
    mi_r="$( attr "$TMP/mcp_impact.xml" reaches )"; mi_s="$( attr "$TMP/mcp_impact.xml" shown )"; mi_c="$( attr "$TMP/mcp_impact.xml" capped )"
    [ "$mi_r" = "60" ] && [ "$mi_s" = "40" ] && [ "$mi_c" = "1" ] \
        && ok "MCP impact carries reaches=60 shown=40 capped=1 (CLI parity)" \
        || no "MCP impact reaches='$mi_r' shown='$mi_s' capped='$mi_c'"

    mcp_text '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"path_between","arguments":{"path":"'"$SRC"'","from":"entry","to":"deep"}}}' > "$TMP/mcp_path.xml"
    mp_r="$( attr "$TMP/mcp_path.xml" reachable )"; mp_d="$( attr "$TMP/mcp_path.xml" from_defs )"
    [ "$mp_r" = "1" ] && ok "MCP path resolves through the RIGHT def (reachable=1)" || no "MCP path reachable='$mp_r'"
    [ "$mp_d" = "2" ] && ok "MCP path echoes from_defs=2"                           || no "MCP path from_defs='$mp_d'"
    has "$TMP/mcp_path.xml" 'from_p=' && ok "MCP path echoes from_p"                || no "MCP path has no from_p"

    mcp_text '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"path_between","arguments":{"path":"'"$SRC"'","from":"orphan","to":"leaf"}}}' > "$TMP/mcp_dead.xml"
    has "$TMP/mcp_dead.xml" 'hint=' && ok "MCP path dead end carries a hint=" || no "MCP path dead end has no hint="
else
    echo "  SKIP  MCP parity (python3 unavailable)"
fi

echo "== G5 the default map stayed additive =="
"$BIN" "$SRC" --no-cache > "$TMP/def1.xml" 2>/dev/null
"$BIN" "$SRC" --no-cache > "$TMP/def2.xml" 2>/dev/null
cmp -s "$TMP/def1.xml" "$TMP/def2.xml" && ok "default map byte-identical run-to-run (det-gate)" \
                                       || no "default map is NOT deterministic"
# NOTE: the map header has carried its own shown= since long before this lane, so shown= alone is NOT a
# marker of contamination — check only the attributes this lane introduced.
grep -q 'capped=\|hits_capped=\|from_p=\|to_p=\|from_defs=\|to_defs=\|seam_pairs=' "$TMP/def1.xml" \
    && no "default map gained an r27-emitters attribute — G5 violated" \
    || ok "default map carries no r27-emitters attribute (flags stayed additive)"
# §P8 (2026-07-28) — REPINNED. What this line guards is that the default map is still the UNWRAPPED <r>
# document (no verb wrapper element around it), not that <r> has zero attributes. The root gained one
# attribute in the vocabulary pass — est_tokens=, the map's own size, previously reachable only inside
# an XML comment a conformant parser may discard. Matching '<r' followed by space-or-'>' keeps the
# wrapper check and stops re-breaking on every future root attribute.
grep -q '<r[ >]' "$TMP/def1.xml" && ok "default map still the bare, UNWRAPPED <r> root" || no "default map root changed"

# the hard G5 proof: the committed golden for test/fixture must still match byte-for-byte.
if [ -f "$ROOT/test/golden.xml" ]; then
    ( cd "$ROOT" && "$BIN" test/fixture --no-cache > "$TMP/gold.now" 2>/dev/null )
    cmp -s "$TMP/gold.now" "$ROOT/test/golden.xml" && ok "test/golden.xml still byte-identical (default output unchanged)" \
                                                  || no "test/golden.xml DIFFERS — the default map changed"
fi

# §P12.3: the "byte-identical to the (plain) default map" claim for --map-diff was FALSE (the map-diff
# header keeps changed= and an at= stamp). The corrected wording must not regress to the old absolute claim.
if grep -qE "byte-identical to the (plain )?default map" src/cli.h README.md; then
    no "P12.3 regression: the false byte-identical map-diff claim is back in cli.h or README"
else
    ok "P12.3: no absolute byte-identical map-diff claim in cli.h/README"
fi

[ "$fail" = "0" ] && { echo "ALL PASS"; exit 0; }
echo "FAILURES PRESENT"; exit 1
