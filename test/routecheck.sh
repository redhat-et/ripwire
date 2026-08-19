#!/usr/bin/env bash
# routecheck.sh — the routing gate: a deterministic, confidence-gated query-shape ranker selector for --for.
#
#   test/routecheck.sh                        # uses build/ripwire on test/routefix
#   RIPWIRE_BIN=asan/ripwire test/routecheck.sh
#
# Routing is now the DEFAULT: --for (and --query) classify the query shape and pick the lens ranker
# (name-exact vs subtoken+body BM25) via a CONFIDENCE gate (lexical.h chooseForRanker) — name-exact only when
# the query NAMES a symbol (identifier syntax, or every content word is a symbol name), else subtoken+body.
# --no-route forces plain subtoken+body (the pre-default behavior). This gate asserts:
#   (a) SAFE FALLBACK — a CONCEPTUAL --for query defaults to subtoken+body; its RANKING is byte-identical to
#       the pre-routing golden captured via --no-route (the confidence gate does not over-fire on prose).
#   (b) identifier query — --for="buildGraph" (DEFAULT, no flag) routes to name-exact; the header says so.
#   (c) --no-route forces subtoken+body and matches the pre-flip capture byte-for-byte (golden neutrality
#       preserved for the opt-out path); its header carries NO 'routed:' note.
#   (d) determinism — two DEFAULT --route runs are byte-identical.
#   (e) --no-route WITHOUT --for/--query exits non-zero with a clear message.
#   (f) ANCHOR DISCLOSURE — a name-exact reason names WHERE each anchoring word was matched.
# The fixture is copied to a tmp dir OUTSIDE any git repo and scanned via a RELATIVE path, so the golden
# carries no churn/co-change attrs and no absolute paths — stable across machines and time.
# Exits non-zero on any failure.
#
# WHY (f) EXISTS. The name-exact route fires when every content word of the query names a symbol, and the
# header has always said so. What it never said is WHICH symbol, or where that symbol lives — and that is
# precisely the evidence a reader needs in order to distrust the route. The live case, and the reason this
# arm is here: a bash helper named json() inside test/nestprofilecheck.sh made "json escape" a 2-of-2
# whole-name query, flipped it to name-exact, and collapsed a downstream partition to zero (mcpw3fixcheck
# H4; fixed in e7ee64c by renaming the helper). The router behaved exactly as documented — the header was
# simply not informative enough for anyone to see it coming. lexical.h's own gate comment already admits the
# residual: a generic word that happens to equal some symbol name still routes. The honest answer to a
# documented-fragile rule is to publish its evidence, not to re-tune it on one anecdote.
#
# So a name-exact reason now carries, per anchoring word, the DEFINING FILE of the symbol it matched, how
# many further definitions of that name exist, or the literal `syntax` when the word routed on camelCase /
# snake_case shape and names no symbol at all. A one-use helper in test/ and a core symbol in src/ stop
# looking identical, and "routed on shape, matched nothing" stops looking like a symbol hit.
#
# DISCLOSURE ONLY. The routing DECISION is byte-for-byte unchanged — the same ranker for every query, only
# the reason string grows. (f3) pins that as a battery of hand-checked verdicts, so a later change to anchor
# collection that perturbs the decision goes red here instead of silently re-ranking every --for in the tool.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "routecheck: BIN=$BIN"

# fixture copy: sources only (never the golden itself), relative path, outside any git repo
mkdir -p "$TMP/routefix"
cp "$ROOT"/test/routefix/*.cpp "$TMP/routefix/"
cd "$TMP"

CONCEPT="how does resolution work"

# ── (a) SAFE FALLBACK — a CONCEPTUAL --for query defaults to subtoken+body: its RANKING is byte-identical to
#    the pre-routing golden (captured from plain subtoken+body). The DEFAULT run only ADDS a "[routed:
#    subtoken+body …]" header note, so we compare the --no-route run (identical bytes) to the golden AND
#    assert the DEFAULT run's ranking body matches by stripping just the header comment. ──────────────────
# RE-PIN 2026-07-30 (CA4 fixup wave, §F1): est_tokens="696" -> "703", the ONLY bytes that moved (the document
# is 1757 B before and after; every ranking byte identical vs the pre-wave binary). Same cause as anchorcheck's
# re-pin, and the two together are what identify it: BOTH goldens moved by exactly +7, so this is the
# est_tokens attribute finally charging its own digit string (main.cpp:1938-1945), not the emitted-bytes
# change — a re-measurement would move by a content-dependent amount, not a constant.
# Arithmetic: 1757 B / 703 tok = 2.4993 (the old 696 gave 2.5244). This golden's PURPOSE is route-neutrality;
# the ranking it pins did not change.
# CORRECTED at 2026-07-30 by the w1fix2 verifier (finding G1) — the first re-pin comment claimed this moved UP
# while anchorcheck moved DOWN, and called that the signature of re-measurement. Both moved up. See traps 17-19.
# RE-PIN 2026-08-19 (R-E CORRECTION): same cause and same shape as anchorcheck's re-pin of the same date —
# root-relative p= drops the repeated "routefix/" prefix in favour of one root="routefix" on the <ctx>.
# Document 2879 -> 2850 B, est_tokens 1071 -> 1063. Route-neutrality, the property this golden exists for,
# is untouched: no row moved and no rank value moved.
# RE-PIN 2026-08-15 (harvest wave, V5 item 3): same cause as anchorcheck's re-pin of the same date — the
# --for legend clause "the signatures-only flag opts out" became "the signatures-only flag (no-bodies mode)
# opts out" (V5 lane, 6bd6c00). +17 B legend text + est_tokens self-measurement; ranking bytes identical.
"$BIN" routefix --no-cache --for="$CONCEPT" --no-route >"$TMP/concept_noroute.xml" 2>/dev/null
diff -q "$TMP/concept_noroute.xml" "$ROOT/test/routefix/golden_for.xml" >/dev/null \
    && ok "safe fallback: conceptual --for --no-route byte-identical to the pre-routing golden" \
    || no "conceptual --for --no-route drifted from test/routefix/golden_for.xml"
# the DEFAULT (routed) conceptual run must fall back to subtoken+body — same ranker, only a header note added.
"$BIN" routefix --no-cache --for="$CONCEPT" >"$TMP/concept_default.xml" 2>/dev/null
grep -q 'routed: subtoken+body' "$TMP/concept_default.xml" \
    && ok "safe fallback: conceptual --for DEFAULTS to subtoken+body (no over-fire to name-exact)" \
    || no "conceptual --for did not fall back to subtoken+body (router over-fired on prose)"

# ── (b) identifier query DEFAULTS to name-exact (routing is on with no flag) ───────────────────────────
"$BIN" routefix --no-cache --for="buildGraph" >"$TMP/ident.xml" 2>/dev/null
grep -q 'routed: name-exact' "$TMP/ident.xml" \
    && ok "identifier query 'buildGraph' DEFAULTS to name-exact BM25 (routing is on by default)" \
    || no "identifier query did not route to name-exact (header missing 'routed: name-exact')"

# A7: an identifier embedded in LONG issue/review prose is evidence, not the whole intent. The old
# any-camel/snake rule discarded every prose/body term and cratered corrected LocBench train retrieval.
"$BIN" routefix --no-cache --for="repair buildGraph when the serialized ranked map is empty after cache reload" >"$TMP/long_ident.xml" 2>/dev/null
grep -q 'routed: subtoken+body' "$TMP/long_ident.xml" \
    && ok "long issue prose with one identifier stays subtoken+body" \
    || no "one identifier over-fired name-exact on a long conceptual query"

# ── (c) --no-route forces subtoken+body and matches the pre-flip capture; header carries NO routed note ─
"$BIN" routefix --no-cache --for="buildGraph" --no-route >"$TMP/ident_noroute.xml" 2>/dev/null
{ ! grep -q 'routed:' "$TMP/ident_noroute.xml"; } \
    && ok "--no-route on an identifier query forces subtoken+body (no 'routed:' header note)" \
    || no "--no-route still emitted a 'routed:' note — the opt-out did not disable routing"

# ── (d) determinism — two DEFAULT --for runs byte-identical ────────────────────────────────────────────
"$BIN" routefix --no-cache --for="buildGraph" >"$TMP/r1" 2>/dev/null
"$BIN" routefix --no-cache --for="buildGraph" >"$TMP/r2" 2>/dev/null
diff -q "$TMP/r1" "$TMP/r2" >/dev/null && ok "determinism (DEFAULT --for byte-identical run-to-run)" \
                                       || no "non-deterministic --for output"

# ── well-formed XML on the routed bundle (rides the same seam) ────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/ident.xml" 2>/dev/null && ok "xml well-formed (DEFAULT --for)" || no "xml malformed (DEFAULT --for)"
    xmllint --noout "$TMP/concept_default.xml" 2>/dev/null && ok "xml well-formed (conceptual DEFAULT --for)" || no "xml malformed (conceptual DEFAULT --for)"
else
    ok "xml well-formed (xmllint absent — skipped)"
fi

# ── --query also routes by default (name-exact pick surfaces as a leading comment before the map) ───────
"$BIN" routefix --no-cache --query="buildGraph" >"$TMP/q.xml" 2>/dev/null
grep -q 'routed: name-exact' "$TMP/q.xml" \
    && ok "--query='buildGraph' DEFAULTS to name-exact (leading routed comment before the map)" \
    || no "--query identifier did not route to name-exact"
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/q.xml" 2>/dev/null && ok "xml well-formed (DEFAULT --query, routed comment)" || no "xml malformed (DEFAULT --query)"
fi

# ── (e) --no-route without --for/--query refuses loudly ────────────────────────────────────────────────
"$BIN" routefix --no-cache --no-route >/dev/null 2>"$TMP/err"
[ $? -ne 0 ] && grep -qi 'route' "$TMP/err" && ok "--no-route without --for/--query exits non-zero with a clear message" \
                                            || no "--no-route without --for/--query did not refuse loudly"

# ── (f) ANCHOR DISCLOSURE: a name-exact reason says WHERE each anchoring word matched ──────────────────
# The whole reason string, up to the closing bracket of the header note. Read back from the binary; never
# reconstructed from what the assertion expects.
reasonOf(){ "$BIN" "$@" --no-cache 2>/dev/null | grep -oE 'routed: [^]]*' | head -1; }
routeOf(){  reasonOf "$@" | grep -oE 'name-exact|subtoken\+body' | head -1; }

# (f1) the fixture's identifier query: buildGraph is defined once, in routefix/graph.cpp.
identReason="$( reasonOf routefix --for="buildGraph" )"
case "$identReason" in
    *'anchors: buildGraph(routefix/graph.cpp)'*)
        ok "(f1) the name-exact reason names the anchoring symbol's defining file: [$identReason]" ;;
    *)  no "(f1) the name-exact reason must carry 'anchors: buildGraph(routefix/graph.cpp)' — without the defining file a reader cannot tell a core symbol from a one-use test helper, which is the whole failure this arm records. Got: [$identReason]" ;;
esac

# (f2) a subtoken+body route has no anchoring symbol, so it must claim none. An 'anchors:' list on a route
# that was NOT decided by name evidence would be evidence invented after the fact.
conceptReason="$( reasonOf routefix --for="$CONCEPT" )"
case "$conceptReason" in
    *anchors:*) no "(f2) a subtoken+body route disclosed anchors — that route was not decided by any name match, so there is nothing to anchor: [$conceptReason]" ;;
    *)          ok "(f2) the subtoken+body reason carries no anchors (nothing anchored it)" ;;
esac

# (f3) ROUTE INVARIANCE. Hand-checked verdicts, pinned: disclosure must not move a single decision. Each
# line is "<expected route><TAB><query>"; the two-column form keeps queries with spaces intact.
cat >"$TMP/route.battery" <<'BATTERY'
name-exact	buildGraph
name-exact	buildIndex
name-exact	resolveCall
subtoken+body	how does resolution work
subtoken+body	repair buildGraph when the serialized ranked map is empty after cache reload
subtoken+body	the resolver resolves a call by arity
BATTERY
batteryBad=0
while IFS="$( printf '\t' )" read -r want q; do
    [ -n "${want:-}" ] || continue
    got="$( routeOf routefix --for="$q" )"
    if [ "$got" != "$want" ]; then
        no "(f3) '$q' routed '$got', pinned '$want' — anchor disclosure must not change a routing DECISION"
        batteryBad=1
    fi
done <"$TMP/route.battery"
[ "$batteryBad" -eq 0 ] && ok "(f3) every query in the battery routes exactly as pinned — disclosure changed the reason, not the decision"

# (f4) EVIDENCE QUALITY, the two cases that are not "one symbol, one file".
#   syntax  — a camelCase token that names NOTHING routes on SHAPE; saying so is the point of the arm, because
#             a reader who sees a file name assumes a symbol was found.
#   +N      — a name with several definitions: the anchor names one file and admits the others exist.
mkdir -p "$TMP/dupfix"
cat >"$TMP/dupfix/alpha.cpp" <<'SRC'
void sharedName( void )
{
    int a = 1;
}
SRC
cat >"$TMP/dupfix/beta.cpp" <<'SRC'
void sharedName( int k )
{
    int b = k;
}
SRC
synReason="$( reasonOf routefix --for="noSuchThingHere" )"
case "$synReason" in
    *'anchors: noSuchThingHere(syntax)'*)
        ok "(f4) a camelCase word that names no symbol is disclosed as (syntax), not as a match" ;;
    *)  no "(f4) 'noSuchThingHere' routes name-exact on SHAPE alone and matches no symbol; the reason must say so with (syntax) rather than leaving a reader to assume a symbol was found. Got: [$synReason]" ;;
esac
dupReason="$( reasonOf dupfix --for="sharedName" )"
case "$dupReason" in
    *'anchors: sharedName(dupfix/alpha.cpp+1)'*)
        ok "(f4) a name with two definitions discloses one file and the count of the rest (+1)" ;;
    *)  no "(f4) a name defined in two files must disclose 'sharedName(dupfix/alpha.cpp+1)' — an anchor that names one file and hides that others exist over-states the evidence. Got: [$dupReason]" ;;
esac

# (f5) the disclosure rides inside the EXISTING reason: the phrase downstream gates read must survive.
case "$identReason" in
    *'names a symbol (buildGraph)'*) ok "(f5) the pre-existing 'names a symbol (X)' phrasing is intact — the anchors were appended, not substituted" ;;
    *)                               no "(f5) the anchors replaced the existing reason phrasing; test/taskechocheck.sh reads 'names a symbol (…)' out of this same string: [$identReason]" ;;
esac

# ── (g) ANCHOR PLAUSIBILITY (LB-2): the all-words trigger at nWords>=2 additionally requires every
# plain anchoring word to be SPECIFIC — defined at most 3 times AND carried as a name-subtoken by at most
# max(8, symbols/128) symbol names. A 2-word query whose every word coincidentally equals SOME symbol's
# whole name ("split chunks" — a split() helper, a chunks() getter) used to hard-route name-exact, where a
# compound target (SplitChunksThing) scores a structural 0.0; the r7 probes measured the conceptual ranker
# recovering 5/6 of those. On an implausible anchor the router now DECLINES name-exact and falls through to
# subtoken+body, saying why. Single-word lookups and camelCase/snake syntax are exempt — those branches are
# the lane's measured recall mass and are pinned unchanged by (f3) and (g4).
# The trap corpus is built INLINE (dupfix pattern), never added to test/routefix/ — arm (a) pins the
# routefix golden byte-identical, and this arm must not force a golden re-pin.
mkdir -p "$TMP/commonfix"
cat >"$TMP/commonfix/splitters.cpp" <<'SRC'
// split — a one-use helper whose name is also this corpus's most common name-subtoken (10 carriers > cap 8).
void split()
{
    int cut = 0;
    (void)cut;
}
void splitHelper() {}
void splitBuffer() {}
void splitLine() {}
void splitPath() {}
void splitName() {}
void splitEdge() {}
void splitNode() {}
void splitToken() {}
SRC
cat >"$TMP/commonfix/chunks.cpp" <<'SRC'
// chunks — a getter whose whole name completes the 2-of-2 whole-name coincidence.
int chunks()
{
    return 3;
}

// SplitChunksThing — splits modules into shared chunks; the compound target only the subtoken+body
// (conceptual) ranker can surface, because name-exact scores a compound name 0.0 against "split chunks".
void SplitChunksThing()
{
    int sharedChunkCount = 0;
    (void)sharedChunkCount;
}
SRC

# (g1) the common-anchor query DECLINES name-exact: routes subtoken+body with a truthful reason that names
# the failing anchor and its carrier count — and carries neither of the name-exact-only literals.
declinedReason="$( reasonOf commonfix --for="split chunks" )"
declinedRoute="$( routeOf commonfix --for="split chunks" )"
if [ "$declinedRoute" = "subtoken+body" ]; then
    ok "(g1) 'split chunks' (2-of-2 whole-name coincidence, common anchor) declines name-exact → subtoken+body"
else
    no "(g1) 'split chunks' still routes '$declinedRoute' — an implausible anchor must decline name-exact. Got: [$declinedReason]"
fi
# NOTE the quotes around the anchor word arrive attribute-escaped (&apos;) — match on the words, not the quotes.
case "$declinedReason" in
    *"name-exact declined: anchor"*"split"*"name-carriers"*"defs"*)
        ok "(g1) the declined reason names the failing anchor and its carrier count: [$declinedReason]" ;;
    *)  no "(g1) the declined reason must say WHY (failing anchor + carrier count) — got: [$declinedReason]" ;;
esac
case "$declinedReason" in
    *"anchors:"*|*"names a symbol ("*)
        no "(g1) a declined (subtoken+body) reason carried a name-exact-only literal ('anchors:' / 'names a symbol (') — downstream gates parse those as name-exact markers: [$declinedReason]" ;;
    *)  ok "(g1) the declined reason carries neither 'anchors:' nor 'names a symbol ('" ;;
esac

# (g2) the decline is a RECOVERY, not a shrug: the conceptual ranking surfaces the compound target.
"$BIN" commonfix --no-cache --for="split chunks" >"$TMP/declined.xml" 2>/dev/null
grep -q 'SplitChunksThing' "$TMP/declined.xml" \
    && ok "(g2) the declined route's conceptual ranking surfaces the compound target SplitChunksThing" \
    || no "(g2) SplitChunksThing missing from the declined route's output — the fallthrough did not recover the compound target"

# (g3) a multi-word all-name query on RARE anchors still routes name-exact — lowercase-typed so the camel
# branch cannot mask a regression in the all-words branch. The deliberate multi-symbol lookup must survive.
rareRoute="$( routeOf routefix --for="buildgraph resolvecall" )"
[ "$rareRoute" = "name-exact" ] \
    && ok "(g3) 'buildgraph resolvecall' (rare anchors, all-words branch) still routes name-exact" \
    || no "(g3) rare-anchor multi-word lookup flipped to '$rareRoute' — the plausibility predicate over-fired"

# (g4) the nWords==1 exemption: a single word that IS the common name still routes name-exact (the pinned,
# measured single-word-lookup behavior; the crater was multi-word phrases, never this).
oneRoute="$( routeOf commonfix --for="split" )"
[ "$oneRoute" = "name-exact" ] \
    && ok "(g4) single-word 'split' still routes name-exact (nWords==1 exempt from plausibility)" \
    || no "(g4) single-word lookup flipped to '$oneRoute' — the exemption for nWords==1 broke"

# (g5) determinism + well-formedness on the declined route.
"$BIN" commonfix --no-cache --for="split chunks" >"$TMP/declined2.xml" 2>/dev/null
diff -q "$TMP/declined.xml" "$TMP/declined2.xml" >/dev/null \
    && ok "(g5) declined route deterministic (two runs byte-identical)" \
    || no "(g5) declined route non-deterministic"
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/declined.xml" 2>/dev/null && ok "(g5) xml well-formed (declined route)" || no "(g5) xml malformed (declined route)"
fi

# (g6) MUTATION arm — the declined-disclosure assertion must FAIL against a --no-route run of the same
# query (no routed: note at all there), proving the assertion is live and reads real output.
"$BIN" commonfix --no-cache --for="split chunks" --no-route >"$TMP/declined_noroute.xml" 2>/dev/null
GMUT="$( grep -q 'name-exact declined' "$TMP/declined_noroute.xml" && echo BAD || echo TRIPPED )"
[ "$GMUT" = "TRIPPED" ] && ok "(g6) mutation self-test (the declined assertion fails on the --no-route run, so it is live)" \
                        || no "(g6) mutation self-test broke — the declined assertion cannot fail"

# ── MUTATION self-test — the name-exact routing assertion must FAIL against the --no-route run ─────────
MUT="$( grep -q 'routed: name-exact' "$TMP/ident_noroute.xml" && echo BAD || echo TRIPPED )"
[ "$MUT" = "TRIPPED" ] && ok "mutation self-test (the routing assertion fails on the --no-route run, so it is live)" \
                       || no "mutation self-test broke — the routing assertion cannot fail"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
