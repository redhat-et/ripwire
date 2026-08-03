#!/usr/bin/env bash
# pagingsweepcheck.sh — §P8 contract gate: --limit/--offset must be HONORED, not accepted-and-ignored,
# and a verb that caps must SAY how many rows it printed.
#
# THE TWO BUGS THIS PINS ( "Contract-level", bullets 1 and 2):
#
#   1. --limit/--offset silently ignored. Before this gate, `--cochange --limit=3` emitted 30 rows, so a
#      paging loop over --cochange NEVER TERMINATED and never errored — it re-read the same first page
#      forever. Same for --owners/--clones/--doc-drift/--communities/--whereis/--grep. The fix HONORS
#      paging in all of them, using the exact six-attribute vocabulary --lint already emits
#      (shown= total= has_more= next_offset= offset= limit=), so one parser reads every paging verb.
#
#   2. Four verbs capped silently: --hotspots said ranked="185" and printed 40; --cochange pairs="363" → 30;
#      --whereis hits="2560" → 60; --clones said groups="36" type3="108" while printing 76 <group> rows —
#      NEITHER attribute was the row count. The fix adds shown= + capped="0|1" beside each verb's own total
#      (the shape --grep already used: hits= shown= capped=). The caps themselves STAY — they are sane
#      defaults, now raisable with the newly-honored --limit.
#
# THE THREE THIS ROUND CLOSES (the same §P8 work, found half-done by a cross-lane pass):
#
#   G1. TWO paging vocabularies coexisted. --callers/--callees/--tree (main.cpp) and --deps (serialize.h)
#       CUT their rows for --limit but disclosed only `offset= limit=` (the retired pageAttr() helper) —
#       no shown/capped/total/has_more/next_offset, so a paging loop over them could not TERMINATE either.
#       Meanwhile --impact and --uses ignored --limit outright (--impact printed a fixed 40 with a partial
#       shown=/capped= disclosure; --uses printed everything and said nothing). All six now speak
#       pageview.h's ONE vocabulary, and pageAttr() is deleted so a second one cannot come back.
#   G3. --match was missed while its sibling --grep got paging: `--match=… --limit=5` still emitted 100
#       rows under a bare shown=/capped=. It is windowed now, default cap unchanged.
#   G2. --limit/--offset stayed accept-and-ignore on the default map and ~15 other verbs. Rather than
#       paginate all of them, cli.h's validateModifierGuards now REFUSES the pair on a verb that does not
#       honor it (check (K)) — the honesty hole, closed the way every other silently-no-op modifier is.
#
# BYTE-NEUTRALITY, and its deliberate exceptions. Check (E) asserts the un-paginated opening tag of every
# touched verb carries no paging attrs, so a caller that never passes --limit sees the pre-§P8 shape. The
# EXCEPTIONS are bug 2's whole point: a verb that CAPS now discloses shown= and capped= on its ROOT ELEMENT
# even with no --limit, because a silent cap is exactly the bug being closed. Enumerated, so (I) can be read
# as a closed claim rather than a fuzzy one:
#
#   verb            un-paginated delta vs the pre-change binary
#   --hotspots      + shown= capped=          (round 1)
#   --cochange      + shown= capped=          (round 1)
#   --clones        + shown= capped=          (round 1)
#   --whereis       + shown= capped=          (round 1)
#   --grep          + shown= capped=          (round 1)
#   --doc-drift     + shown= capped=          (round 1)
#   --owners        (none — never capped)     (round 1)
#   --communities   − shown= capped=          THIS round, N4: the bare pair duplicated shown_modules=/
#                                             modules_capped= for the same listing. The noun-prefixed pair
#                                             is the one that survives (two listings coexist there), so the
#                                             bare one is DROPPED — the only subtractive change in the set.
#   --deps          + files= shown= capped=   THIS round: it caps at --pack-top-n (default 40) of 179 files
#                                             and never said so. files= is part of the delta because the
#                                             un-paginated tag was a BARE `<deps>` — the total only appeared
#                                             when paging was active, so shown="40" would have had nothing
#                                             to be capped AGAINST (rule 2 requires a total beside shown=).
#                                             <health files="785"> is a different number (every indexed
#                                             file, not just those with includes) and is NOT normalized.
# --deps  <health>/<f instab=>  (a SEPARATE fix
#                    content changed too         landing in the same session, unrelated to paging): <f
#                                             instab=> is now project-only Ce (was counting system/
#                                             third-party includes too), and <health>'s ccd/acd/nccd/shape
#                                             are now computed over dep_files= (dependency-capable files
#                                             only — a NEW attribute, alongside the unchanged files=), not
#                                             every indexed file. The `<health .../>` tag content and every
#                                             `instab="…"` VALUE are normalized below (strip()) — this is
#                                             the only entry in this table whose delta is NOT a paging
#                                             change; it exists so this check keeps testing paging
#                                             specifically instead of failing on unrelated, deliberate,
#                                             separately-gated content fixes (see depsprecisecheck.sh /
#                                             propcostcheck.sh for THEIR gates).
#   --match         (none — already spelled shown=/capped=; pageview emits the identical bytes)
#   --impact        (none — already spelled shown=/capped=; pageview emits the identical bytes)
#   --callers       (none — no display cap, so discloseCap=false keeps the tag byte-identical)
#   --callees       (none — same)
#   --tree          (none — same)
#   --uses          (none — same)
#
# §P15/§P16 residual: seven more verbs joined the honoring set — each already spelled its own shown=/capped=
# (or, for the never-capped ones, spelled nothing at all), so the delta table extends the same way:
#   --seams             (none — already spelled bare shown=/capped=; pageDisclosure emits the identical bytes)
#   --zoom              (none — no display cap, so discloseCap=false keeps the tag byte-identical)
#   --external-surface  (none — already spelled bare shown=/capped=; pageDisclosure emits the identical bytes)
#   --dead-code         (none — no display cap, so discloseCap=false keeps the tag byte-identical)
#   --mentions          (none — same)
#   --graph-query       (none — already spelled bare shown=/capped=; pageDisclosure emits the identical bytes)
#   --stray-content     (none — no display cap on the outer refs listing, so discloseCap=false keeps the tag
#                        byte-identical; its per-ref <file> children keep their own separate maxFiles cap)
#
# Everything outside that table must be byte-equal. Check (I) proves it literally when RIPWIRE_PREBIN points
# at a pre-change binary; it is SKIPPED otherwise, so the gate stays runnable in CI, where none exists.
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/pagingsweepcheck.sh
#         RIPWIRE_BIN=build/ripwire RIPWIRE_PREBIN=/tmp/ripwire.pre bash test/pagingsweepcheck.sh
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
PREBIN="${RIPWIRE_PREBIN:-}"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
cd "$ROOT"

echo "pagingsweepcheck: BIN=$BIN  PREBIN=${PREBIN:-<none>}"

# PAGE_CORPUS lets one arm point at a corpus other than this checkout. The paging contract
# (limit windows, offset advances, has_more terminates) is a property of the CODE, not of the corpus, so
# an arm whose row supply this repo cannot guarantee is re-anchored onto a fixture built below rather
# than left to red on whichever clone happens to be short of rows. Defaults to $ROOT: every other arm is
# untouched.
run(){  "$BIN" "${PAGE_CORPUS:-$ROOT}" "$@" --cache="$( cacheFor "${PAGE_CORPUS:-$ROOT}" )" 2>/dev/null; }
cold(){ "$BIN" "${PAGE_CORPUS:-$ROOT}" "$@" --no-cache 2>/dev/null; }

# ── one primed cache per corpus, and why that is not a weakening ──────────────────────────────────────
# Every arm below invokes the binary five-to-eight times over a corpus that does not change for the
# gate's whole lifetime, and --no-cache made each of those invocations pay a full cold parse of the tree.
# What this gate asserts is the PAGING contract — row counts, the six-attribute vocabulary, seam
# continuity, termination, cap disclosure, refusal. None of that is a claim about parsing, and none of it
# is a claim about the cache: --cache transparency (a warm run's bytes == a cold run's bytes, on this same
# binary) is proven on its own, against its own corpora, by test/regression.sh sections 2 / 2b / 2c. So a
# primed cache cannot change WHAT an arm here proves; it only stops the arm from re-parsing the tree in
# order to prove it. If transparency ever breaks, section 2 goes red — this gate is not the place that
# claim lives, and it must not silently become a second, weaker copy of it.
# TWO places therefore stay COLD on purpose, and say so at their own site: page_verb's (G) determinism
# pair (a pair of runs restoring ONE cache file cannot observe a re-crawl+re-rank ordering defect), and
# section (I)'s differential against a SECOND binary, which must never read a cache this one wrote.
# cacheFor() keys on the corpus and primes on first use, so the in-gate fixture built below — and any
# PAGE_CORPUS override — gets its OWN file instead of silently reading $ROOT's.
cacheFor(){   # $1 = corpus dir → that corpus's cache path, primed once on first use
    local corpus="$1" c
    c="$TMP/corpus$( printf '%s' "$corpus" | cksum | tr -dc '0-9' ).cache"
    [ -s "$c" ] || "$BIN" "$corpus" --cache="$c" >/dev/null 2>&1
    printf '%s' "$c"
}
ROOTCACHE="$( cacheFor "$ROOT" )"   # the main corpus, primed up front — section (K) invokes $BIN directly

# ── the in-gate paging fixture ────────────────────────────────────────────────────────────────────────
# TWO of these arms — --mentions and --stray-content — need a corpus-SHAPE this repo does not supply on
# a fresh clone, which is every clone but the author's and therefore every CI leg:
#
#   --mentions=main       needs >= 6 doc rows for page_verb's (C) seam check (page[0:3]+[3:6] == [0:6])
#                         and >= 4 for has_more="1" on --limit=3. The published repo has exactly 3 docs
#                         naming `main`, so (B) and (C) red — on a gate about paging, over a fact about
#                         how many READMEs mention a symbol.
#   --stray-content       lists refs holding divergent work. A fresh clone has one branch and nothing
#                         stray, so it emits ZERO rows and five arms red. Worse, CI checks out SHALLOW
#                         by default, and this verb's own header says a shallow clone makes EVERY ref
#                         unanalysable ("v=unknown ... the fix is to deepen the clone") — so even a repo
#                         with real stray branches could not assert here.
#
# So both are re-anchored onto one throwaway fixture built from scratch here: 8 markdown docs naming one
# symbol, and 8 branches each authoring lines HEAD does not have. It carries its own full history, so it
# asserts identically on a fresh clone, a shallow CI checkout, and the author's machine. Every other arm
# still runs against $ROOT. Both verbs also still meet the live corpus in section (K)'s honoring-set loop.
PAGEFIX="$TMP/pagefix"
mkPagingFixture(){
    mkdir -p "$PAGEFIX/src" "$PAGEFIX/docs" || return 1
    printf 'int renderWidget( int n ){ return n; }\nint layoutWidget( int n ){ return renderWidget( n ) + 1; }\n' > "$PAGEFIX/src/widget.cpp"
    local i
    for i in 1 2 3 4 5 6 7 8; do
        printf '# Note %d\n\nThe `renderWidget` entry point is described here (note %d).\n' "$i" "$i" > "$PAGEFIX/docs/note$i.md"
    done
    (
        cd "$PAGEFIX" || exit 1
        git init -q . || exit 1
        git config user.email paging@example.invalid
        git config user.name  paging-fixture
        git config commit.gpgsign false
        git add -A && git commit -qm "fixture base" || exit 1
        local home; home="$( git rev-parse --abbrev-ref HEAD )"   # init.defaultBranch varies by host
        local b
        for b in 1 2 3 4 5 6 7 8; do
            git checkout -q -b "stray$b" || exit 1
            printf 'int strayFn%d(){ return %d; }\n' "$b" "$b" > "src/stray$b.cpp"
            git add -A && git commit -qm "stray work $b" || exit 1
            git checkout -q "$home" || exit 1
        done
        # advance the home line so the 8 branches are genuinely divergent, not fast-forwardable
        printf 'int liveFn(){ return 0; }\n' > src/live.cpp
        git add -A && git commit -qm "live work" || exit 1
    ) >/dev/null 2>&1
}
mkPagingFixture || { echo "pagingsweepcheck: could not build the paging fixture (git unusable?)"; exit 2; }

# ── (A)-(G): the paging contract, one verb at a time ─────────────────────────────────────────────────
# $1 = label, $2 = row-element ERE (an item = one emitted result row), $3.. = verb args.
# SHOWNATTR (env, default "shown") names the attribute carrying rule 1's row count: a report with SEVERAL
# independent listings spells it noun-prefixed (--communities' shown_modules=), and the bare pair is then
# NOT emitted — see pageview.h, THE TRUNCATION VOCABULARY, rules 1+6.
page_verb(){
    local label="$1" rowpat="$2"; shift 2
    local shownattr="${SHOWNATTR:-shown}"
    local plain p0 p3 p6 pend n0 n3

    # (E) un-paginated run leaks no paging attribute (byte-neutral posture; see the header's exception).
    plain="$( run "$@" )"
    if printf '%s' "$plain" | head -c 4000 | grep -qE 'has_more="|next_offset="|(^|[[:space:]])offset="'; then
        no "$label: un-paginated run leaked paging attrs (must stay pre-P8 byte-shape)"
    else
        ok "$label: un-paginated run carries no paging attrs"
    fi

    # (A) --limit=3 emits EXACTLY 3 rows. This is the bug: before the fix it emitted the full capped list.
    p0="$( run "$@" --limit=3 --offset=0 )"
    n0="$( printf '%s' "$p0" | grep -oE "$rowpat" | wc -l | tr -d ' ' )"
    [ "$n0" = 3 ] && ok "$label: --limit=3 emits exactly 3 rows" || no "$label: --limit=3 emitted $n0 rows (expected 3) — accepted-and-ignored?"

    # (B) the six-attribute vocabulary, spelled as --lint spells it, plus capped=.
    printf '%s' "$p0" | grep -q 'has_more="1"'   && ok "$label: has_more=\"1\" on a partial page"     || no "$label: missing has_more=\"1\""
    printf '%s' "$p0" | grep -q 'next_offset="3"' && ok "$label: next_offset=\"3\" advances the loop"  || no "$label: missing next_offset=\"3\""
    printf '%s' "$p0" | grep -q 'offset="0" limit="3"' && ok "$label: offset=/limit= echoed"          || no "$label: missing offset=\"0\" limit=\"3\""
    printf '%s' "$p0" | grep -q "$shownattr=\"3\"" && ok "$label: $shownattr=\"3\" == rows emitted"    || no "$label: missing $shownattr=\"3\""
    printf '%s' "$p0" | grep -qE 'total="[0-9]+"' && ok "$label: total= present"                      || no "$label: missing total="

    # (C) --offset ADVANCES: page[0:3] + page[3:6] == page[0:6], no row dropped or duplicated at the seam.
    p3="$( run "$@" --limit=3 --offset=3 )"
    n3="$( printf '%s' "$p3" | grep -oE "$rowpat" | wc -l | tr -d ' ' )"
    p6="$( run "$@" --limit=6 --offset=0 )"
    # rowpat is a prefix, so compare the FULL row text instead — extract whole elements for a real diff.
    { printf '%s' "$p0" | grep -oE "${rowpat}[^>]*>"; printf '%s' "$p3" | grep -oE "${rowpat}[^>]*>"; } > "$TMP/seam"
    printf '%s' "$p6" | grep -oE "${rowpat}[^>]*>" > "$TMP/full6"
    if [ "$n3" = 3 ] && diff -q "$TMP/seam" "$TMP/full6" >/dev/null; then
        ok "$label: --offset advances — page[0:3]+[3:6] == page[0:6], no dup/drop"
    else
        no "$label: --offset did NOT advance (page2 rows=$n3, seam mismatch) — the non-terminating-loop bug"
        diff "$TMP/seam" "$TMP/full6" | head -4
    fi

    # (D) TERMINATION: offset past the end → 0 rows, has_more="0", exit 0. This is what ends a paging loop.
    pend="$( run "$@" --limit=5 --offset=999999 )"; local ec=$?
    local nend; nend="$( printf '%s' "$pend" | grep -oE "$rowpat" | wc -l | tr -d ' ' )"
    if [ "$ec" = 0 ] && [ "$nend" = 0 ] && printf '%s' "$pend" | grep -q 'has_more="0"'; then
        ok "$label: offset past the end → 0 rows, has_more=\"0\", exit 0 (loop terminates)"
    else
        no "$label: offset-past-end mishandled (exit=$ec rows=$nend) — a paging loop would not terminate"
    fi

    # (G) a paged page is deterministic and well-formed. This pair stays on cold() — see the priming site.
    # The claim is that a full re-crawl + re-rank lands on the SAME window twice (the astQuery tie-order
    # defect the --match arms below are deliberately shaped to flap on); two runs restoring one already-
    # primed cache would agree by construction and could not observe it.
    local d1 d2; d1="$( cold "$@" --limit=3 --offset=3 )"; d2="$( cold "$@" --limit=3 --offset=3 )"
    [ "$d1" = "$d2" ] && ok "$label: paged page deterministic" || no "$label: paged page NOT deterministic"
    if command -v xmllint >/dev/null 2>&1; then
        printf '%s' "$p3" | xmllint --noout - 2>/dev/null && ok "$label: xml well-formed under paging" || no "$label: xml MALFORMED under paging"
    fi
}

echo "--- (A)-(G) paging contract ---"
page_verb "cochange"    '<pair '      --cochange
page_verb "owners"      '<f p='       --owners --detail=1
page_verb "clones"      '<group '     --clones
page_verb "doc-drift"   '<doc p='     --doc-drift
SHOWNATTR=shown_modules \
page_verb "communities" '<community ' --communities
page_verb "whereis"     '<hit '       --whereis=rankGraph
page_verb "grep"        '<hit '       --grep=NodeId
page_verb "hotspots"    '<f p='       --hotspots

# ── G1/G3: the six verbs the cross-lane pass found still on the OLD vocabulary (or on none at all) ────
# --deps' row element is <f p=…>, a spelling it shares with <godfiles>/<cycles> preamble rows — the ERE
# pins the paged row by its own `includes=` attribute so the un-paginated preamble can never be counted.
#
# --match's query is (call_expression), a NESTING kind, deliberately: such a kind produces several
# captures at one (file, startByte) — `f(x).count()` yields both the outer and inner call_expression —
# and astQuery's tie order used to be non-total (no endByte tie-break), so two runs differed in the <m>
# BODY text and page[0:3]+page[3:6] could disagree with page[0:6] when a tie straddled the seam. That
# ordering defect is FIXED (astQuery now sorts file, startByte, endByte, tag — see ingest.cpp), and
# det-gate.sh pins it; these arms use the nesting kind ON PURPOSE so a regression makes (G) flap here.
# Section (I)'s differential arm is the one exception — see the note there.
page_verb "callers"     '<s t='                     --callers=escapeXml
page_verb "callees"     '<s t='                     --callees=runUses
page_verb "tree"        '<file p='                  --tree
page_verb "deps"        '<f p="[^"]*" includes='    --deps
page_verb "match"       '<m p='                     '--match=(call_expression) @c'
page_verb "impact"      '<s t='                     --impact=escapeXml
page_verb "uses"        '<u role='                  --uses=escapeXml

# ── §P15/§P16: seven more verbs, each with a real deterministic row model ───────────────────────────────
# --seams' row is the seam-PAIR listing (<seam from= to= ...>), not its nested <edge> children (a second,
# independent, still-capped-at-5 listing per row — rowpat pins the SPACE after "<seam" so it cannot match
# the plural root tag "<seams ...>").
page_verb "seams"           '<seam '        --seams
# --external-surface / --graph-query are flat listings with row counts comfortably above 6 in this repo
# (the corpus page_verb's seam-continuity check (C) needs), so they stay anchored to $ROOT.
page_verb "external-surface" '<x n='         --external-surface
page_verb "graph-query"      '<s t='         --graph-query='name("main")'
# --mentions / --stray-content run against the in-gate fixture instead — see mkPagingFixture() above for
# why this checkout cannot supply their rows on a fresh clone or a shallow CI checkout. The CONTRACT
# asserted is identical; only the corpus that supplies the rows changes.
PAGE_CORPUS="$PAGEFIX" page_verb "mentions"      '<doc p='    --mentions=renderWidget
PAGE_CORPUS="$PAGEFIX" page_verb "stray-content" '<ref name=' --stray-content

# --zoom is a NESTED hierarchy — every level emits a <module level="L" ...> element, so a bare '<module '
# pattern would count every descendant too, not just the top-level row list --limit/--offset actually
# windows. Every TOP-level module carries the SAME level number (the recursion always starts at topL and
# only ever recurses to STRICTLY LOWER levels), so pinning that one level value isolates exactly the paged
# row list. Read it from a preliminary plain run rather than hardcoding it — the hierarchy depth is a
# property of the corpus (Louvain contraction), not a constant.
ZOOM_TOPLEVEL="$( run --zoom | grep -oE '<zoom levels="[0-9]+"' | grep -oE '[0-9]+' )"
ZOOM_TOPLEVEL=$(( ZOOM_TOPLEVEL - 1 ))
page_verb "zoom" "<module level=\"${ZOOM_TOPLEVEL}\" id=" --zoom

# --dead-code's candidate count in THIS repo is small (single digits) — below the 6 rows page_verb's (C)
# continuity check assumes (page[0:3]+page[3:6] vs page[0:6]). Its own dedicated, count-adaptive check:
echo "--- dead-code (small-N paging; see comment above) ---"
DC_PLAIN="$( run --dead-code )"
DC_TOTAL="$( printf '%s' "$DC_PLAIN" | grep -oE 'dead-code count="[0-9]+"' | grep -oE '[0-9]+' | head -1 )"
if printf '%s' "$DC_PLAIN" | grep -qE 'has_more="|next_offset="|(^|[[:space:]])offset="'; then
    no "dead-code: un-paginated run leaked paging attrs"
else
    ok "dead-code: un-paginated run carries no paging attrs"
fi
DC_P0="$( run --dead-code --limit=2 --offset=0 )"
DC_N0="$( printf '%s' "$DC_P0" | grep -oE '<d n=' | wc -l | tr -d ' ' )"
[ "$DC_N0" = 2 ] && ok "dead-code: --limit=2 emits exactly 2 rows" || no "dead-code: --limit=2 emitted $DC_N0 rows (expected 2)"
printf '%s' "$DC_P0" | grep -q "total=\"$DC_TOTAL\"" && ok "dead-code: total=\"$DC_TOTAL\" present" || no "dead-code: missing total=\"$DC_TOTAL\""
DC_END="$( run --dead-code --limit=2 --offset=999999 )"; DC_EC=$?
DC_NEND="$( printf '%s' "$DC_END" | grep -oE '<d n=' | wc -l | tr -d ' ' )"
if [ "$DC_EC" = 0 ] && [ "$DC_NEND" = 0 ] && printf '%s' "$DC_END" | grep -q 'has_more="0"'; then
    ok "dead-code: offset past the end -> 0 rows, has_more=\"0\", exit 0"
else
    no "dead-code: offset-past-end mishandled (exit=$DC_EC rows=$DC_NEND)"
fi
# page[0:2] + page[2:4] must equal the concatenation of every candidate (bounded continuity, whatever N is).
DC_P2="$( run --dead-code --limit=2 --offset=2 )"
{ printf '%s' "$DC_P0" | grep -oE '<d n=[^/]*/>'; printf '%s' "$DC_P2" | grep -oE '<d n=[^/]*/>'; } > "$TMP/dc_seam"
printf '%s' "$DC_PLAIN" | grep -oE '<d n=[^/]*/>' > "$TMP/dc_full"
diff -q "$TMP/dc_seam" "$TMP/dc_full" >/dev/null \
    && ok "dead-code: --offset advances — page[0:2]+[2:4] == the un-paginated full listing" \
    || no "dead-code: --offset did NOT advance (seam mismatch)"

# ── (H): silent caps now disclose shown= beside their own total, with no --limit at all ───────────────
echo "--- (H) cap disclosure on the un-paginated run ---"
disclose(){   # $1=label $2=root-element $3=row-pattern $4..=verb args
    local label="$1" el="$2" rowpat="$3"; shift 3
    local out root rows shown
    out="$( run "$@" )"
    root="$( printf '%s' "$out" | grep -oE "<${el}[^>]*>" | head -1 )"
    rows="$( printf '%s' "$out" | grep -oE "$rowpat" | wc -l | tr -d ' ' )"
    shown="$( printf '%s' "$root" | sed -nE 's/.* shown="([0-9]+)".*/\1/p' )"
    if [ -z "$shown" ]; then
        no "$label: root has no shown= — total-vs-emitted does not reconcile ($root)"
    elif [ "$shown" != "$rows" ]; then
        no "$label: shown=\"$shown\" but $rows rows follow"
    else
        ok "$label: shown=\"$shown\" == the $rows rows that follow"
    fi
    printf '%s' "$root" | grep -qE 'capped="[01]"' && ok "$label: capped=\"0|1\" present" || no "$label: no capped= flag"
}
disclose "hotspots" "hotspots" '<f p='   --hotspots
disclose "cochange" "cochange" '<pair '  --cochange
disclose "whereis"  "whereis"  '<hit '   --whereis=rankGraph
disclose "grep"     "grep"     '<hit '   --grep=NodeId
# (d) --clones: the root said groups="36" type3="108" and printed 76 <group> rows. shown= must be 76.
disclose "clones"   "clones"   '<group ' --clones
# --deps capped at --pack-top-n (default 40) of 179 including files and said nothing (G1, this round).
disclose "deps"     "deps"     '<f p="[^"]*" includes=' --deps
disclose "match"    "match"    '<m p='  '--match=(call_expression) @c'
disclose "impact"   "impact"   '<s t='  --impact=escapeXml
# §P15/§P16: --seams/--external-surface/--graph-query already spelled bare shown=/capped= before joining the
# honoring set (pageDisclosure's discloseCap=true reproduces the identical bytes) — --zoom/--dead-code/
# --mentions/--stray-content never capped by default (discloseCap=false), so they carry no shown= here at
# all and are correctly absent from this section, same as --callers/--callees/--tree/--uses/--owners above.
disclose "seams"             "seams"             '<seam '   --seams
disclose "external-surface"  "external-surface"  '<x n='    --external-surface
disclose "graph-query"       "query"             '<s t='    --graph-query='name("main")'

# ── (J) the §P10.3 40-row --impact cap is RAISABLE now, which is the point of honoring --limit ────────
# Before this round --impact ignored --limit entirely: `--limit=200` still printed 40 of a 100+ blast
# radius, so "is it safe to change X?" had a hard ceiling no flag could lift.
echo "--- (J) --impact's historic 40-row cap is raisable with --limit ---"
IMP_DEFAULT="$( run --impact=escapeXml | grep -oE '<s t=' | wc -l | tr -d ' ' )"
IMP_RAISED="$(  run --impact=escapeXml --limit=200 | grep -oE '<s t=' | wc -l | tr -d ' ' )"
[ "$IMP_DEFAULT" = 40 ] && ok "--impact: no-flag default still caps at 40 rows" \
                        || no "--impact: default cap changed ($IMP_DEFAULT rows, expected 40)"
{ [ -n "$IMP_RAISED" ] && [ "$IMP_RAISED" -gt 40 ] 2>/dev/null; } \
    && ok "--impact --limit=200: emits $IMP_RAISED rows (> the historic 40 cap)" \
    || no "--impact --limit=200: emitted $IMP_RAISED rows — the 40-row cap is still not raisable"
IMP_TOTAL="$( run --impact=escapeXml --limit=200 | grep -oE 'reaches="[0-9]+"' | head -1 | tr -dc 0-9 )"
{ [ -n "$IMP_TOTAL" ] && [ "$IMP_RAISED" = "$IMP_TOTAL" ]; } \
    && ok "--impact --limit=200: shows the WHOLE reaches=$IMP_TOTAL radius (limit above the total)" \
    || no "--impact --limit=200: $IMP_RAISED rows vs reaches=$IMP_TOTAL — the window is not the full set"

# ── (K) G2: --limit/--offset REFUSED on a verb that does not honor them (the honesty hole) ────────────
# Paging ~15 more report verbs was not the answer; the answer is that accept-and-ignore must stop. The
# default map's remedy is a DIFFERENT flag (--top-k), so the message must name it rather than the list.
echo "--- (K) --limit/--offset refused where they are not honored ---"
refuses(){   # $1=label $2=expected stderr substring $3..=argv after ROOT
    local label="$1" want="$2"; shift 2
    "$BIN" "$ROOT" "$@" --cache="$ROOTCACHE" >"$TMP/k.out" 2>"$TMP/k.err" </dev/null; local rc=$?
    if [ "$rc" = 0 ]; then
        no "$label: exited 0 — --limit was accepted and silently ignored"
    elif grep -qF -- "$want" "$TMP/k.err"; then
        ok "$label: refused (exit $rc), message names \"$want\""
    else
        no "$label: refused (exit $rc) with the WRONG message: $( head -1 "$TMP/k.err" )"
    fi
}
refuses "default map --limit=3"  "--top-k"   --limit=3
refuses "default map --offset=3" "--top-k"   --offset=3
refuses "--report --limit=3"     "--callers" --report --limit=3
refuses "--for --limit=3"        "--callers" --for=rank --limit=3
refuses "--metrics --limit=3"    "--callers" --metrics --limit=3
refuses "--expand --limit=3"     "--callers" --expand=rankGraph --limit=3
# §P15/§P16: --zoom joined the honoring set but --zoom --mermaid did NOT — it is a fixed-shape diagram, same
# reasoning as plain --mermaid, so the combination must still refuse (not silently ignore --limit either).
refuses "--zoom --mermaid --limit=3" "--callers" --zoom --mermaid --limit=3
# --stray-content's own sub-verbs (--plan, --abi) route to emitters that do not window anything either.
refuses "--stray-content --plan --limit=3" "--callers" --stray-content --plan --limit=3
refuses "--stray-content --abi --limit=3"  "--callers" --stray-content --abi --limit=3

# and the honoring set really honors: every verb the message names must exit 0 under --limit=3.
for v in --lint --hotspots --callers=escapeXml --callees=runUses --tree --deps --cochange --owners \
         --clones --doc-drift --communities --whereis=rankGraph --grep=NodeId --impact=escapeXml --uses=escapeXml \
         --seams --zoom --external-surface --dead-code --mentions=main --stray-content; do
    if "$BIN" "$ROOT" $v --limit=3 --cache="$ROOTCACHE" >/dev/null 2>"$TMP/k2.err"; then
        ok "honoring set: $v --limit=3 exits 0"
    else
        no "honoring set: $v --limit=3 was REFUSED — the guard's list disagrees with the code ($( head -1 "$TMP/k2.err" ))"
    fi
done
if "$BIN" "$ROOT" --match='(call_expression) @c' --limit=3 --cache="$ROOTCACHE" >/dev/null 2>"$TMP/k3.err"; then
    ok "honoring set: --match --limit=3 exits 0"
else
    no "honoring set: --match --limit=3 was REFUSED ($( head -1 "$TMP/k3.err" ))"
fi
# --graph-query's expr carries quotes/parens, so it rides the same standalone-quoted shape as --match above.
if "$BIN" "$ROOT" --graph-query='name("main")' --limit=3 --cache="$ROOTCACHE" >/dev/null 2>"$TMP/k3b.err"; then
    ok "honoring set: --graph-query --limit=3 exits 0"
else
    no "honoring set: --graph-query --limit=3 was REFUSED ($( head -1 "$TMP/k3b.err" ))"
fi
# --detail=1 --owners --limit=N is a LEGAL composition (--detail restores the full listing, --limit windows it).
"$BIN" "$ROOT" --owners --detail=1 --limit=3 --cache="$ROOTCACHE" >/dev/null 2>"$TMP/k4.err" \
    && ok "--owners --detail=1 --limit=3 stays legal" \
    || no "--owners --detail=1 --limit=3 was refused ($( head -1 "$TMP/k4.err" ))"
# INVERTED this arm. --batch used to be exempt from the guard on the reasoning that
# it "answers its own sub-queries", but the exemption did not do what that implies: the outer --limit reached
# NO sub-query, so `--batch=F --limit=3` exited 0 with the payload unchanged — accept-and-ignore, the exact
# class this whole gate exists to keep extinct, sitting inside the gate's own exception list. A batch
# sub-query that wants a page spells it on its own line in the batch FILE. --mcp keeps its exemption (there
# the per-request arguments are a real channel); --batch now refuses like every other non-honoring verb.
printf 'callers:escapeXml\n' > "$TMP/batch.txt"
if "$BIN" "$ROOT" --batch="$TMP/batch.txt" --limit=3 --cache="$ROOTCACHE" >/dev/null 2>"$TMP/k5.err"; then
    no "--batch --limit=3 was ACCEPTED and ignored (exit 0, payload unchanged) — §A5a"
else
    grep -q 'honored only by' "$TMP/k5.err" \
        && ok "--batch --limit=3 refuses with the standard honoring-set text (§A5a)" \
        || no "--batch --limit=3 failed for the wrong reason ($( head -1 "$TMP/k5.err" ))"
fi
# the control: plain --batch, no paging flags, is untouched.
"$BIN" "$ROOT" --batch="$TMP/batch.txt" --cache="$ROOTCACHE" >/dev/null 2>"$TMP/k5b.err" \
    && ok "--batch without --limit still exits 0 (the refusal is scoped to the ignored flags)" \
    || no "--batch without --limit broke ($( head -1 "$TMP/k5b.err" ))"

# ── (I): un-paginated output identical to the PRE-CHANGE binary except the root disclosure attrs ──────
echo "--- (I) un-paginated byte-identity vs the pre-change binary (except root disclosure attrs) ---"
if [ -n "$PREBIN" ] && [ -x "$PREBIN" ]; then
    # EVERY invocation in this section stays --no-cache — see the priming site. Both sides here are a
    # DIFFERENT binary from each other, and a cache is an artifact of the binary that wrote it: letting
    # $PREBIN read (or rewrite) $BIN's cache would make the differential a statement about two cache
    # formats rather than about two outputs. Cold on both sides is the only honest comparison.
    # Two normalizations, and only two: drop the newly-added root attrs, and drop the <!-- --> header
    # comments (which grew one sentence each, documenting exactly those attrs — the tool self-documents, so
    # a new attribute necessarily edits its own header). Everything that remains is the DATA, and it must be
    # byte-equal to the pre-change binary's.
    # The bare ` shown= capped=` pair is stripped from BOTH sides, which is exactly what makes the two
    # DIRECTIONS of the table above one rule: --deps GAINED the pair, --communities LOST it (N4 — it
    # duplicated shown_modules=/modules_capped= for the same listing), and the surviving noun-prefixed
    # attributes are NOT stripped, so a regression that dropped those would still be caught here.
    # The third normalization is deliberately NARROW — `<deps files="N"` only, never a bare files="N" — so
    # <health files="785"> (a different total, in the same document) still has to match byte-for-byte.
    # A fourth and fifth normalization (§P9.2/§P9.4, unrelated to paging — see the --deps table row above):
    # the WHOLE <health .../> tag is collapsed (its ccd=/acd=/nccd=/shape= values changed and it gained
    # dep_files=) and every `instab="…"` VALUE is blanked (project-only Ce now, was raw #include count) —
    # deliberately narrow to those two spots so a regression ELSEWHERE in --deps' output is still caught.
    strip(){ sed -E -e 's/ shown="[0-9]+" capped="[01]"//g' -e 's/<deps files="[0-9]+"/<deps/' -e 's/<!--[^>]*-->//g' \
                     -e 's/<health[^>]*\/>/<health\/>/' -e 's/instab="[0-9.]+"/instab="X"/g'; }
    for v in "--clones" "--communities" "--doc-drift" "--grep=NodeId" "--hotspots" "--cochange" "--whereis=rankGraph" "--owners" \
             "--callers=escapeXml" "--callees=runUses" "--tree" "--deps" "--impact=escapeXml" "--uses=escapeXml"; do
        "$BIN"    "$ROOT" $v --no-cache 2>/dev/null | strip > "$TMP/new"
        "$PREBIN" "$ROOT" $v --no-cache 2>/dev/null | strip > "$TMP/old"
        if diff -q "$TMP/old" "$TMP/new" >/dev/null; then
            ok "$v: un-paginated data byte-identical modulo root disclosure attrs"
        else
            no "$v: un-paginated output CHANGED beyond the root disclosure attrs"
            diff "$TMP/old" "$TMP/new" | head -4 | cut -c1-200
        fi
    done
    # --match separately: its query carries a space, so it cannot ride the unquoted `for v` expansion.
    # This ONE arm stays (string_literal) — a non-nesting kind — while the paging arms above use
    # (call_expression): the PRE-change binary's tie order over a nesting kind was NONDETERMINISTIC (the
    # very defect the endByte tie-break fixed), so a differential against it can only hold on a kind
    # whose capture order was already total. Do not "align" this with the arms above.
    "$BIN"    "$ROOT" --match='(string_literal) @s' --no-cache 2>/dev/null | strip > "$TMP/new"
    "$PREBIN" "$ROOT" --match='(string_literal) @s' --no-cache 2>/dev/null | strip > "$TMP/old"
    diff -q "$TMP/old" "$TMP/new" >/dev/null \
        && ok "--match: un-paginated data byte-identical modulo root disclosure attrs" \
        || no "--match: un-paginated output CHANGED beyond the root disclosure attrs"

    # §P15/§P16's seven: none of them changed their un-paginated byte shape at all (see the extended table
    # above), so no strip() normalization is needed — a bare diff must hold.
    for v in "--seams" "--zoom" "--external-surface" "--dead-code" "--mentions=main" "--stray-content"; do
        "$BIN"    "$ROOT" $v --no-cache 2>/dev/null > "$TMP/new"
        "$PREBIN" "$ROOT" $v --no-cache 2>/dev/null > "$TMP/old"
        if diff -q "$TMP/old" "$TMP/new" >/dev/null; then
            ok "$v: un-paginated output byte-identical to the pre-change binary"
        else
            no "$v: un-paginated output CHANGED vs the pre-change binary"
            diff "$TMP/old" "$TMP/new" | head -4 | cut -c1-200
        fi
    done
    "$BIN"    "$ROOT" --graph-query='name("main")' --no-cache 2>/dev/null > "$TMP/new"
    "$PREBIN" "$ROOT" --graph-query='name("main")' --no-cache 2>/dev/null > "$TMP/old"
    diff -q "$TMP/old" "$TMP/new" >/dev/null \
        && ok "--graph-query: un-paginated output byte-identical to the pre-change binary" \
        || no "--graph-query: un-paginated output CHANGED vs the pre-change binary"
else
    echo "  SKIP  (I) — set RIPWIRE_PREBIN=/path/to/pre-change/ripwire to run the literal identity diff"
fi

# ── (J) §A10.1: the verbs with a genuine BARE-RUN default cap (hotspots=40, cochange=30, whereis=60,
# grep/match=100, impact=40, seams=20 — cli.h's own --limit=N/--offset=M list) must name the raise flag
# in their FIRST-SCREEN legend, not only once --limit is already passed (has_more=/next_offset= — and so
# the existence of --limit at all — used to appear ONLY on a --limit run, never on the bare one).
for spec in "hotspots:--hotspots" "cochange:--cochange" "whereis:--whereis=main" "grep:--grep=main" \
            "match:--match=(function_definition)" "impact:--impact=main" "seams:--seams"; do
    label="${spec%%:*}"; args="${spec#*:}"
    OUT="$( run $args )"
    printf '%s' "$OUT" | grep -q 'raise the default cap with limit=N' \
        && ok "$label: bare-run legend names the raise flag (§A10.1)" \
        || no "$label: bare-run legend still silent about --limit"
done

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
