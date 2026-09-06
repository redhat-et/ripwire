#!/usr/bin/env bash
# termmargincheck.sh — the CORPUS-STATISTICS TERM-MARGIN filter on the conceptual BM25 route
# (src/lexical.h, lexicalScoresTiered). The idea under test, from SIRA (arXiv 2605.06647): do not
# weight a query term by how RELEVANT it looks, weight it by whether it SEPARATES the target from
# corpus-level confusers. A term the corpus spends everywhere carries no separation, and the tf mass
# it hands out lifts whichever document recites it most — which is rarely the answer.
#
# WHAT IS AND IS NOT PORTED. SIRA's LLM vocabulary-enrichment step is OUT OF SCOPE and is not
# replicated: there is no runtime ML in this tool. What transfers is the corpus-statistics filter,
# which is pure IDF-margin arithmetic over the index ripwire already builds.
#
# THE DANGEROUS FAILURE MODE THIS GATE EXISTS FOR. A term-margin filter's characteristic bug is not
# "it dropped a term" — it is "it dropped the ONLY term that could reach the right symbol". A term
# can look worthless by corpus statistics and still be the single discriminating token in the query.
# Three separable ways that happens, one arm each, and each arm asserts the DECISION (the stderr
# trace) as well as the ranking, so it cannot pass by the mechanism being absent:
#   (b) sole anchor      — every present query term is corpus-saturating; suppressing them all zeroes
#                          the whole ranking. Suppression must be a no-op here.
#   (c) name carrier     — a term whose BODY mass is everywhere but which NAMES few symbols still
#                          separates, because the name field is ripwire's anchor field (×3).
#   (d) absent-term trap — an absent term has the HIGHEST idf of all (df = 0). An implementation that
#                          counts it as a surviving "good" term will happily drop the one real anchor
#                          beside it. The absent term must not license a suppression.
#
# FIXTURE (built in a temp dir; 16 symbols, term statistics chosen so each classification is forced):
#   svc/{alpha,beta,gamma,delta}.js  8 fns, names all carry "Handler"; docs recite handler/pipeline/cache
#   svc/slot.js                      evictHandlerSlot()  — the OFFENDER: saturated with "handler",
#                                    carries "evict" only in its name
#   ring/evict.js                    evictOldestEntry()  — the TARGET: the eviction code, zero "handler"
#   store/policy.js                  cacheReadThrough()  — carries "cache" (+ "pipeline"), nothing else
#   util/misc.js                     5 fns carrying no query term at all
#   ⇒ handler  df=9/16 nameDf=9  → separates on NEITHER field  → SUPPRESSED
#     pipeline df=9/16 nameDf=0  → separates on NEITHER field  → suppressible, but see (b)/(d)
#     cache    df=9/16 nameDf=1  → separates on the NAME field → KEPT
#     evict    df=2/16           → separates on the DOC field  → KEPT
#
# RED-FIRST PROOF (this gate was committed before the implementation existed). At 1f283e4a arms
# (a), (b), (c) and (d) all FAIL: (a) because RIPWIRE_TERMMARGIN=1 and =0 rank identically, and
# (b)/(c)/(d) because there is no `term-margin:` trace on stderr to read a decision out of.
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/termmargincheck.sh   (pargates.py passes no argument)
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d "${TMPDIR:-/tmp}/termmargin.XXXXXX" )"
trap 'rm -rf "$TMP"' EXIT
fail=0

# ── helpers, ALL defined before the first use (manifestcheck I1: bash resolves functions at run
#    time, so a call above its definition expands to nothing and its arm passes on empty strings) ──
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

# run --for on the fixture with the arm at $1 (0|1), query $2, stdout to $3 and stderr to $4.
# --no-route pins the SUBTOKEN+BODY ranker (the only route the filter lives on); --no-cache and a
# private XDG_CACHE_HOME keep one arm from reading another's persisted stats.
runq(){
    local arm="$1" query="$2" out="$3" err="$4"
    env -u TMPDIR XDG_CACHE_HOME="$TMP/xdg" RIPWIRE_TERMMARGIN="$arm" RIPWIRE_TERMMARGIN_DEBUG=1 \
        perl -e 'alarm 30; exec @ARGV' "$BIN" "$TMP/corpus" --for="$query" \
        --format=candidates --no-route --no-cache >"$out" 2>"$err"
}
# name of the rank-1 candidate
top_name(){ tr '<' '\n' <"$1" | grep -E '^cand r="1" ' | head -1 | grep -oE ' n="[^"]*"' | head -1 | sed 's/ n="//;s/"//'; }
# s= of the candidate whose n= is $2 ("" when the name is absent from the export)
score_of(){ tr '<' '\n' <"$1" | grep -E "^cand .* n=\"$2\"" | head -1 | grep -oE '^cand r="[0-9]+" s="[0-9.eE+-]+"' | grep -oE 's="[0-9.eE+-]+"' | sed 's/s="//;s/"//'; }
# r= of the candidate whose n= is $2
rank_of(){ tr '<' '\n' <"$1" | grep -E "^cand .* n=\"$2\"" | head -1 | grep -oE '^cand r="[0-9]+"' | grep -oE '[0-9]+'; }
# how many candidates carry a strictly positive score
nonzero_scores(){ tr '<' '\n' <"$1" | grep -E '^cand ' | grep -oE ' s="[0-9.eE+-]+"' | grep -vcE ' s="0(\.0+)?"'; }
# strictly-greater float compare, house rule (never a string equality on a score)
gt(){ awk -v a="$1" -v b="$2" 'BEGIN{ exit !( a > b ) }'; }
# the term-margin trace line for term $2 in stderr file $1
trace_of(){ grep -E "^term-margin: \"$2\" " "$1" | head -1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "termmargincheck: BIN=$BIN"

# ── fixture ────────────────────────────────────────────────────────────────────────────────────────
mkdir -p "$TMP/corpus/svc" "$TMP/corpus/ring" "$TMP/corpus/store" "$TMP/corpus/util" "$TMP/xdg"
for f in alpha beta gamma delta; do
cat > "$TMP/corpus/svc/$f.js" <<EOF
// handler registration for the $f handler pipeline: the handler runs when a handler pipeline
// fires, and every cache in the $f pipeline keeps a cache entry for the handler cache pipeline.
function ${f}HandlerOne( ctx ) { return ctx.handler.run(); }
// the $f handler chain: each handler forwards to the next handler in the handler pipeline list,
// and the pipeline cache is asked before the handler cache pipeline touches the handler cache.
function ${f}HandlerTwo( ctx ) { return ctx.handler.next(); }
EOF
done
cat > "$TMP/corpus/svc/slot.js" <<'EOF'
// the handler slot table: a handler owns a handler slot, and a handler release hands the handler
// slot back so the next handler can claim a handler slot from the handler free list of handlers.
function evictHandlerSlot( h ) { return handlerSlots.release( h.handler ); }
EOF
cat > "$TMP/corpus/ring/evict.js" <<'EOF'
// evict the oldest entry from the ring buffer once the ring buffer has no room left for a
// newly written entry, choosing whichever entry the ring buffer wrote longest ago.
function evictOldestEntry( ring ) { return ring.dropOldest(); }
EOF
cat > "$TMP/corpus/store/policy.js" <<'EOF'
// read through the cache: the cache pipeline asks the backing store when the cache misses,
// then the cache pipeline writes what the store returned back into the cache pipeline.
function cacheReadThrough( key ) { return backing.read( key ); }
EOF
cat > "$TMP/corpus/util/misc.js" <<'EOF'
// convert a value into a printable form for the report writer
function formatValue( v ) { return String( v ); }
// clamp a number into the inclusive range given by lo and hi
function clampRange( v, lo, hi ) { return Math.min( hi, Math.max( lo, v ) ); }
// walk a tree depth first and yield each visited node once
function walkTree( node ) { return node.children.map( walkTree ); }
// merge two plain objects, right hand side wins on a key collision
function mergeObjects( a, b ) { return Object.assign( {}, a, b ); }
// parse a duration string such as 30s or 5m into milliseconds
function parseDuration( s ) { return Number( s ); }
EOF

# ── presence guard: the fixture must actually carry the population every arm below reasons about.
#    Without this, a fixture that silently stopped parsing would make every arm green-while-inert. ──
runq 0 "evict handler" "$TMP/probe.xml" "$TMP/probe.err"
probe_total="$( grep -oE '<candidates count="[0-9]+" total="[0-9]+"' "$TMP/probe.xml" | grep -oE 'total="[0-9]+"' | grep -oE '[0-9]+' )"
[ "${probe_total:-0}" = 16 ] \
    && ok "fixture indexes the 16 symbols every term statistic below is derived from" \
    || no "fixture should index 16 symbols, indexed ${probe_total:-none} — every arm below is measuring a different corpus"

# ── (a) THE DROP ARM — a term that separates on NEITHER field is suppressed, and the ranking moves ──
# "handler" is in 9 of 16 docs and names 9 of 16 symbols: it separates nothing. Its tf mass is what
# puts evictHandlerSlot (which carries "evict" only in its name) above evictOldestEntry (which IS the
# eviction code). Suppressing it must hand rank 1 back to the target and must zero every symbol whose
# ONLY query evidence was that term.
runq 1 "evict handler" "$TMP/a_on.xml"  "$TMP/a_on.err"
runq 0 "evict handler" "$TMP/a_off.xml" "$TMP/a_off.err"
a_on_top="$( top_name "$TMP/a_on.xml" )"
a_off_top="$( top_name "$TMP/a_off.xml" )"
[ "$a_on_top" = "evictOldestEntry" ] \
    && ok "(a) armed: 'evict handler' ranks the eviction code first (got: $a_on_top)" \
    || no "(a) armed: rank 1 should be evictOldestEntry, got: ${a_on_top:-none}"
[ "$a_off_top" = "evictHandlerSlot" ] \
    && ok "(a-ctl) disarmed: the saturating term still carries evictHandlerSlot to rank 1 (the filter, not ambient rank, does the work)" \
    || no "(a-ctl) disarmed: rank 1 should be evictHandlerSlot, got: ${a_off_top:-none} — fixture no longer proves the lever"
a_on_noise="$( score_of "$TMP/a_on.xml" alphaHandlerTwo )"
a_off_noise="$( score_of "$TMP/a_off.xml" alphaHandlerTwo )"
{ [ -n "$a_off_noise" ] && gt "$a_off_noise" 0; } \
    && ok "(a-ctl) disarmed: a boilerplate-only symbol scores on the saturating term alone (s=$a_off_noise)" \
    || no "(a-ctl) disarmed: alphaHandlerTwo should score > 0, got: ${a_off_noise:-none}"
{ [ -n "$a_on_noise" ] && ! gt "$a_on_noise" 0; } \
    && ok "(a) armed: a symbol whose only evidence was the suppressed term scores exactly 0 (s=$a_on_noise)" \
    || no "(a) armed: alphaHandlerTwo should score 0 once 'handler' is suppressed, got: ${a_on_noise:-none}"
a_trace="$( trace_of "$TMP/a_on.err" handler )"
case "$a_trace" in
    *SUPPRESSED* ) ok "(a) the decision is DISCLOSED, not silent: $a_trace" ;;
    *            ) no "(a) no 'term-margin: \"handler\" … SUPPRESSED' trace on stderr (got: ${a_trace:-nothing})" ;;
esac
a_evict_trace="$( trace_of "$TMP/a_on.err" evict )"
case "$a_evict_trace" in
    *"kept (doc-separates)"* ) ok "(a) the discriminating term survives, for a stated reason: $a_evict_trace" ;;
    *                        ) no "(a) 'evict' should be kept (doc-separates), got: ${a_evict_trace:-nothing}" ;;
esac

# ── (b) SOLE-ANCHOR GUARD — when every present term is saturating, suppress NOTHING ────────────────
# "pipeline" is in 9 of 16 docs and names nothing: by the corpus statistics alone it is exactly as
# worthless as "handler". It is also the only thing the query has. Dropping it returns an all-zero
# ranking — the catastrophic shape, and the one a filter that only looks at df walks straight into.
runq 1 "pipeline" "$TMP/b_on.xml"  "$TMP/b_on.err"
runq 0 "pipeline" "$TMP/b_off.xml" "$TMP/b_off.err"
b_nz="$( nonzero_scores "$TMP/b_on.xml" )"
[ "${b_nz:-0}" -ge 1 ] \
    && ok "(b) armed: the sole (saturating) anchor is not dropped — $b_nz symbols still score" \
    || no "(b) armed: suppressing the only present term zeroed the whole ranking ($b_nz nonzero scores)"
{ [ -n "$( top_name "$TMP/b_on.xml" )" ] && [ "$( top_name "$TMP/b_on.xml" )" = "$( top_name "$TMP/b_off.xml" )" ]; } \
    && ok "(b) armed: rank 1 is unchanged from the disarmed run ($( top_name "$TMP/b_on.xml" ))" \
    || no "(b) armed: rank 1 moved ($( top_name "$TMP/b_on.xml" ) vs $( top_name "$TMP/b_off.xml" )) — the guard did not hold the term"
b_trace="$( trace_of "$TMP/b_on.err" pipeline )"
case "$b_trace" in
    *"kept (sole-anchor)"* ) ok "(b) the guard names itself in the trace: $b_trace" ;;
    *                      ) no "(b) 'pipeline' should be kept (sole-anchor), got: ${b_trace:-nothing}" ;;
esac

# ── (c) NAME-CARRIER GUARD — body mass everywhere, but it names few symbols ⇒ it still separates ───
# "cache" is in 9 of 16 docs (as much boilerplate as "handler") but NAMES exactly one symbol. The name
# field is ripwire's anchor field (×3), so a term that picks out one name out of sixteen separates
# even though its doc frequency says otherwise. "slot" (df 1) survives on its own, so the sole-anchor
# guard is NOT what is being tested here: only the name-field test can save "cache".
runq 1 "cache slot" "$TMP/c_on.xml" "$TMP/c_on.err"
c_score="$( score_of "$TMP/c_on.xml" cacheReadThrough )"
c_rank="$( rank_of "$TMP/c_on.xml" cacheReadThrough )"
{ [ -n "$c_score" ] && gt "$c_score" 0 && [ "${c_rank:-99}" -le 3 ]; } \
    && ok "(c) armed: the symbol reachable ONLY through the name-carrying term survives (r=$c_rank s=$c_score)" \
    || no "(c) armed: cacheReadThrough should still rank top-3 with a positive score, got r=${c_rank:-none} s=${c_score:-none}"
c_trace="$( trace_of "$TMP/c_on.err" cache )"
case "$c_trace" in
    *"kept (name-separates)"* ) ok "(c) the guard names itself in the trace: $c_trace" ;;
    *                         ) no "(c) 'cache' should be kept (name-separates), got: ${c_trace:-nothing}" ;;
esac
c_slot_trace="$( trace_of "$TMP/c_on.err" slot )"
case "$c_slot_trace" in
    *"kept (doc-separates)"* ) ok "(c-ctl) 'slot' survives on doc frequency, so (c) is NOT the sole-anchor guard in disguise" ;;
    *                        ) no "(c-ctl) 'slot' should be kept (doc-separates), got: ${c_slot_trace:-nothing} — (c) may be passing through the wrong guard" ;;
esac

# ── (d) ABSENT-TERM TRAP — df = 0 is the HIGHEST idf in BM25, and must not license a suppression ───
# A term the corpus never contains scores log((S+0.5)/0.5 + 1) — larger than any real term's idf. An
# implementation that asks "does a higher-idf term survive?" without excluding absent terms concludes
# that the typo beside the anchor is the good term, drops the anchor, and returns nothing.
runq 1 "pipeline zzznotinthecorpuszzz" "$TMP/d_on.xml" "$TMP/d_on.err"
d_nz="$( nonzero_scores "$TMP/d_on.xml" )"
[ "${d_nz:-0}" -ge 1 ] \
    && ok "(d) armed: a nonsense term beside the sole anchor does not license dropping it — $d_nz symbols still score" \
    || no "(d) armed: the absent term counted as a survivor and the real anchor was dropped ($d_nz nonzero scores)"
d_abs_trace="$( trace_of "$TMP/d_on.err" zzznotinthecorpuszzz )"
case "$d_abs_trace" in
    *absent* ) ok "(d) the absent term is classified as absent, not as evidence: $d_abs_trace" ;;
    *        ) no "(d) 'zzznotinthecorpuszzz' should be classified absent, got: ${d_abs_trace:-nothing}" ;;
esac
d_anchor_trace="$( trace_of "$TMP/d_on.err" pipeline )"
case "$d_anchor_trace" in
    *"kept (sole-anchor)"* ) ok "(d) the real anchor is still the sole anchor: $d_anchor_trace" ;;
    *                      ) no "(d) 'pipeline' should be kept (sole-anchor) with an absent term beside it, got: ${d_anchor_trace:-nothing}" ;;
esac

# ── (e) G5 — the flagless default is untouched ─────────────────────────────────────────────────────
env -u TMPDIR XDG_CACHE_HOME="$TMP/xdg" "$BIN" "$TMP/corpus" --for="evict handler" \
    --format=candidates --no-route --no-cache >"$TMP/e_unset.xml" 2>/dev/null
cmp -s "$TMP/e_unset.xml" "$TMP/a_off.xml" \
    && ok "(e) additive: an unset RIPWIRE_TERMMARGIN is byte-identical to RIPWIRE_TERMMARGIN=0" \
    || no "(e) additive: the default run changed when the arm exists but is not requested"
cmp -s "$TMP/a_on.xml" "$TMP/a_off.xml" \
    && no "(e) the armed and disarmed runs are byte-identical — the arm is inert, so every arm above is measuring nothing" \
    || ok "(e) armed and disarmed runs differ, so the arm is live"

# ── (f) determinism + scan/persisted-stats parity, with the arm ON ─────────────────────────────────
runq 1 "evict handler" "$TMP/f_1.xml" "$TMP/f_1.err"
runq 1 "evict handler" "$TMP/f_2.xml" "$TMP/f_2.err"
cmp -s "$TMP/f_1.xml" "$TMP/f_2.xml" \
    && ok "(f) determinism: armed output byte-identical run to run" \
    || no "(f) determinism: armed output differs between two identical runs"
env -u TMPDIR XDG_CACHE_HOME="$TMP/xdgw" RIPWIRE_TERMMARGIN=1 "$BIN" "$TMP/corpus" --for="evict handler" \
    --format=candidates --no-route >"$TMP/f_cold.xml" 2>/dev/null
env -u TMPDIR XDG_CACHE_HOME="$TMP/xdgw" RIPWIRE_TERMMARGIN=1 "$BIN" "$TMP/corpus" --for="evict handler" \
    --format=candidates --no-route >"$TMP/f_warm.xml" 2>/dev/null
cmp -s "$TMP/f_warm.xml" "$TMP/f_1.xml" \
    && ok "(f) parity: the persisted-stats branch and the scan branch agree byte-for-byte with the arm on" \
    || no "(f) parity: warm (persisted-stats) and --no-cache (scan) diverge with the arm on"

# ── (g) G4 — still well-formed XML with the arm on ─────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/a_on.xml" 2>/dev/null && ok "(g) xml well-formed with the arm on" || no "(g) xml malformed with the arm on"
else
    printf '  SKIP  (g) xml well-formed (no xmllint)\n'
fi

[ "$fail" = 0 ] && echo "termmargincheck: ALL PASS" || echo "termmargincheck: FAILURES ABOVE"
exit $fail
