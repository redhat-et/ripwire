#!/usr/bin/env bash
# testgatepagecheck.sh — §A3a/§A3b/PC-2 gate .
#
# §A3a [BROKEN]: --test-gate's <u> untested-row list was a bare 25-row literal cap (situ.h kMaxUntestedRows)
# with NO shown=/capped= disclosure on the root, in either XML or JSON, and `--test-gate --limit=100`
# REFUSED with "every other verb emits a fixed report with no page to walk" — false: there were 41 more rows
# to walk. Fix: --test-gate joins the pageview.h paging vocabulary (kPagingHonoringVerbs / honorsPaging()),
# the root discloses shown=/capped= always and the full total=/has_more=/next_offset=/offset=/limit= block
# once --limit/--offset is explicit, and the JSON sibling mirrors the same keys. The <t> tests rows are
# untouched by this gate (they were never capped).
#
# §A3b [MISLEADING]: --situ's "[1] blast radius: N symbols across M files" section lists only 8 file rows
# (situ.h, bare `i < 8`) with no marker when M > 8. Fix: the header discloses the cap the same way --report's
# god-files section already does three lines of code away ("showing N of M") — exact wording per the
# decided fix shape: "... (showing 8; full list: --pr-context)".
#
# PC-2 [MISLEADING]: --help's hand-typed paging "HONORED by:" list (cli.h ~971) and the runtime refusal
# message's list (kPagingHonoringVerbs, cli.h ~1307) are two hand-maintained copies of the same set — they
# had already drifted once (missing --community) before this round added --test-gate to only one of them by
# hand. Closes the defect class (the §P6.7 pattern, test/emittertruthcheck.sh's --format reconciliation, one
# flag over): extract both lists from the LIVE binary and assert set-equality, so they can never fork again.
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/testgatepagecheck.sh   |   RIPWIRE_BIN=build_base/ripwire …
# Exits non-zero on any failure. Does NOT edit regression.sh (test/pargates.py auto-discovers *check.sh).

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "testgatepagecheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
attr(){ printf '%s' "$1" | grep -oE "$2=\"[0-9]+\"" | head -1 | grep -oE '[0-9]+'; }
# JSON numbers AND booleans — the union's kJsonPageSyntax spells capped/has_more as true/false (the gated
# JSON dialect), so normalize booleans to 1/0 for the arithmetic-style assertions below.
jattr(){ printf '%s' "$1" | grep -oE "\"$2\":(true|false|[0-9]+)" | head -1 | sed 's/.*://; s/true/1/; s/false/0/'; }
run(){ perl -e 'alarm 20; exec @ARGV' "$BIN" "$@" --no-cache 2>/dev/null; }
rc(){  perl -e 'alarm 20; exec @ARGV' "$BIN" "$@" --no-cache >/dev/null 2>&1; echo $?; }

# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
# §A3a fixture — a synthetic corpus with 30 untested offenders, well over the 25-row default page, built
# fresh so this gate never depends on the live ripwire repo's own (drifting) untested count. lib.cpp defines
# 30 leaf functions; caller.cpp defines 30 functions, each calling exactly one lib function — changing
# lib.cpp therefore blast-radiuses into exactly 30 non-test callers, none of which any test reaches.
# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
R="$TMP/repo"; mkdir -p "$R/src"
{
    i=0
    while [ "$i" -lt 30 ]; do
        printf 'int lib%d() { return %d; }\n' "$i" "$i"
        i=$(( i + 1 ))
    done
} > "$R/src/lib.cpp"
{
    i=0
    while [ "$i" -lt 30 ]; do
        printf 'int caller%d() { return lib%d(); }\n' "$i" "$i"
        i=$(( i + 1 ))
    done
} > "$R/src/caller.cpp"

# §B7.1 PIN UPDATE: the bare shown=/capped= this gate pinned described only the <u>
# listing while the report emits <t> rows too (26 rows on a default page under a single shown="25"). Per
# pageview.h rule 1 the report now spells one pair PER LISTING — shown_tests=/tests_capped= and
# shown_untested=/untested_capped= — and pageview.h rule 6's paging half attaches to the <u> listing alone.
# The arms below therefore read the NOUN-PREFIXED names; every quantity they assert is unchanged, and two
# new arms pin the two facts the rename exists to state (the <t> count is separate, and it is page-invariant).
# ── (a) default page: shown_untested="25" untested_capped="1"; root's own untested= is the true total (30) ──
A="$( run "$R" --test-gate=src/lib.cpp )"; AEC="$( rc "$R" --test-gate=src/lib.cpp )"
AROWS="$( printf '%s' "$A" | grep -o '<u ' | wc -l | tr -d ' ' )"
{ [ "$AEC" = 4 ] && [ "$( attr "$A" untested )" = 30 ] && [ "$( attr "$A" shown_untested )" = 25 ] && [ "$( attr "$A" untested_capped )" = 1 ] && [ "$AROWS" = 25 ]; } \
    && ok "(a) default page: untested=30 shown_untested=25 untested_capped=1, exactly 25 <u> rows emitted" \
    || no "(a) wrong (exit=$AEC untested=$( attr "$A" untested ) shown_untested=$( attr "$A" shown_untested ) untested_capped=$( attr "$A" untested_capped ) rows=$AROWS)"

# ── (a') --limit=100 no longer REFUSES and emits ALL 30 rows with capped="0" ────────────────────────────────
B="$( run "$R" --test-gate=src/lib.cpp --limit=100 )"; BEC="$( rc "$R" --test-gate=src/lib.cpp --limit=100 )"
BROWS="$( printf '%s' "$B" | grep -o '<u ' | wc -l | tr -d ' ' )"
{ [ "$BEC" = 4 ] && [ -n "$B" ] && [ "$( attr "$B" shown_untested )" = 30 ] && [ "$( attr "$B" untested_capped )" = 0 ] && [ "$( attr "$B" total )" = 30 ] && [ "$( attr "$B" has_more )" = 0 ] && [ "$BROWS" = 30 ]; } \
    && ok "(a') --limit=100: not refused, shown_untested=30 untested_capped=0 total=30 has_more=0, all 30 rows walked" \
    || no "(a') wrong (exit=$BEC empty=$( [ -z "$B" ] && echo y || echo n ) shown_untested=$( attr "$B" shown_untested ) untested_capped=$( attr "$B" untested_capped ) total=$( attr "$B" total ) has_more=$( attr "$B" has_more ) rows=$BROWS)"

# ── (b) row count == shown= at EVERY page, including a mid-listing --offset window ──────────────────────────
C="$( run "$R" --test-gate=src/lib.cpp --limit=12 --offset=12 )"
CROWS="$( printf '%s' "$C" | grep -o '<u ' | wc -l | tr -d ' ' )"
{ [ "$( attr "$C" shown_untested )" = 12 ] && [ "$CROWS" = 12 ] && [ "$( attr "$C" untested_capped )" = 1 ] && [ "$( attr "$C" has_more )" = 1 ] && [ "$( attr "$C" next_offset )" = 24 ]; } \
    && ok "(b) mid-listing page (--limit=12 --offset=12): shown_untested=12, 12 rows, has_more=1 next_offset=24" \
    || no "(b) wrong (shown_untested=$( attr "$C" shown_untested ) rows=$CROWS untested_capped=$( attr "$C" untested_capped ) has_more=$( attr "$C" has_more ) next_offset=$( attr "$C" next_offset ))"
LAST="$( run "$R" --test-gate=src/lib.cpp --limit=12 --offset=24 )"
LROWS="$( printf '%s' "$LAST" | grep -o '<u ' | wc -l | tr -d ' ' )"
{ [ "$( attr "$LAST" shown_untested )" = 6 ] && [ "$LROWS" = 6 ] && [ "$( attr "$LAST" has_more )" = 0 ]; } \
    && ok "(b') final page (--offset=24): shown_untested=6 (the remainder), has_more=0" \
    || no "(b') wrong (shown_untested=$( attr "$LAST" shown_untested ) rows=$LROWS has_more=$( attr "$LAST" has_more ))"

# ── (a-json) the JSON sibling mirrors the same keys (row count == the "shown" key at every page too) ────────
AJ="$( run "$R" --test-gate=src/lib.cpp --json )"
AJROWS="$( printf '%s' "$AJ" | grep -o '"sym"' | wc -l | tr -d ' ' )"
{ [ "$( jattr "$AJ" untested )" = 30 ] && [ "$( jattr "$AJ" shown_untested )" = 25 ] && [ "$( jattr "$AJ" untested_capped )" = 1 ] && [ "$AJROWS" = 25 ]; } \
    && ok "(a-json) default page: untested=30 shown_untested=25 untested_capped=1, 25 rows in untested_blast_radius" \
    || no "(a-json) wrong (untested=$( jattr "$AJ" untested ) shown_untested=$( jattr "$AJ" shown_untested ) untested_capped=$( jattr "$AJ" untested_capped ) rows=$AJROWS)"
BJ="$( run "$R" --test-gate=src/lib.cpp --json --limit=100 )"
BJROWS="$( printf '%s' "$BJ" | grep -o '"sym"' | wc -l | tr -d ' ' )"
{ [ "$( jattr "$BJ" shown_untested )" = 30 ] && [ "$( jattr "$BJ" untested_capped )" = 0 ] && [ "$( jattr "$BJ" total )" = 30 ] && [ "$( jattr "$BJ" has_more )" = 0 ] && [ "$BJROWS" = 30 ]; } \
    && ok "(a-json') --limit=100: shown_untested=30 untested_capped=0 total=30 has_more=0, all 30 rows" \
    || no "(a-json') wrong (shown_untested=$( jattr "$BJ" shown_untested ) untested_capped=$( jattr "$BJ" untested_capped ) total=$( jattr "$BJ" total ) has_more=$( jattr "$BJ" has_more ) rows=$BJROWS)"

# ── xml/json well-formed ──────────────────────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    xok=1
    for X in "$A" "$B" "$C" "$LAST"; do printf '%s' "$X" | xmllint --noout - 2>/dev/null || xok=0; done
    [ "$xok" = 1 ] && ok "xml well-formed (all paged variants)" || no "xml malformed on a paged variant"
else
    printf '  SKIP  xml well-formed (no xmllint)\n'
fi
if command -v python3 >/dev/null 2>&1; then
    jok=1
    for J in "$AJ" "$BJ"; do printf '%s' "$J" | python3 -c 'import sys,json; json.load(sys.stdin)' 2>/dev/null || jok=0; done
    [ "$jok" = 1 ] && ok "json well-formed (both paged variants)" || no "json malformed on a paged variant"
else
    printf '  SKIP  json well-formed (no python3)\n'
fi

# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
# §A3b — --situ's blast-radius header discloses its 8-row cap once files > 8. Reuses this binary's own repo
# checkout as the corpus (self.h-heavy files reliably blast-radius past 8 files here) rather than growing a
# second synthetic fixture just for a file-fanout count.
# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
# §B3 knock-on GAP: "full list: --pr-context" was FALSE — pr-context's own per-file
# <impact> list is capped too (at 20, now disclosed via shown=/capped=), so it never printed a full list
# either. Reworded to name what pr-context actually gives; this pin follows the new wording — asserting the
# "(showing 8" cap-disclosure MEANING, not the old false referral text.
S="$( run "$ROOT" --situ=src/model.h )"
# §B12.1 PIN UPDATE: "(showing 8" carried no UNIT and no remainder, so the disclosure did not say what 8
# counted. The pin now asserts the two MEANING halves — the count is qualified by its unit AND by the total
# it is 8 of — instead of the old bare literal.
printf '%s' "$S" | grep -qE 'across [0-9]+ files transitively depend on these changes \(showing 8 of [0-9]+ files; --pr-context' \
    && ok "(c) --situ discloses the 8-row cap with its UNIT and remainder (\"showing 8 of N files\")" \
    || no "(c) --situ's blast-radius header does not disclose the cap: $( printf '%s' "$S" | sed -n '2p' )"
S2="$( run "$R" --situ=src/lib.cpp )"
printf '%s' "$S2" | grep -qE 'across (0|[1-8]) files transitively depend on these changes$' \
    && ok "(c') --situ omits the cap note when files <= 8 (byte-neutral small case)" \
    || no "(c') small-fanout situ unexpectedly carries the cap note: $( printf '%s' "$S2" | sed -n '2p' )"

# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
# PC-2 — --help's hand-typed "HONORED by:" list and the runtime refusal message's list (kPagingHonoringVerbs)
# must name the SAME set. Extract both from the LIVE binary (not a hardcoded copy of either) and diff them.
# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
HELPTEXT="$( "$BIN" --help 2>&1 | tr '\n' ' ' )"
HELPLIST="$( printf '%s' "$HELPTEXT" | sed -E 's/.*HONORED by: //; s/ Emit at most N rows.*//' )"
[ -n "$HELPLIST" ] && ok "PC-2: --help's HONORED-by list extracted" || no "PC-2: could not find --help's HONORED-by list"

REFUSEMSG="$( "$BIN" "$R" --pr-context --limit=1 2>&1 )"
REFUSELIST="$( printf '%s' "$REFUSEMSG" | sed -E 's/.*honored only by: //; s/\. The default map.*//' )"
[ -n "$REFUSELIST" ] && ok "PC-2: the runtime refusal message's honored-set list extracted" || no "PC-2: could not find the runtime refusal's honored-set list (msg: $REFUSEMSG)"

helptoks="$( printf '%s' "$HELPLIST" | grep -oE -- '--[A-Za-z][A-Za-z/-]*' | sort -u )"
runtoks="$(  printf '%s' "$REFUSELIST" | grep -oE -- '--[A-Za-z][A-Za-z/-]*' | sort -u )"
[ -n "$helptoks" ] && ok "PC-2: --help list has $( printf '%s\n' "$helptoks" | wc -l | tr -d ' ' ) verb tokens" || no "PC-2: --help list yielded zero verb tokens"
[ -n "$runtoks" ]  && ok "PC-2: runtime list has $( printf '%s\n' "$runtoks" | wc -l | tr -d ' ' ) verb tokens"  || no "PC-2: runtime list yielded zero verb tokens"

DIFF="$( diff <( printf '%s\n' "$helptoks" ) <( printf '%s\n' "$runtoks" ) )"
[ -z "$DIFF" ] \
    && ok "PC-2: --help's HONORED-by list and kPagingHonoringVerbs (runtime) are set-EQUAL" \
    || no "PC-2: the two paging-honored lists DISAGREE:
$DIFF"

# every token the runtime list names must also be spelled in --help (the direction that drifted: --community)
for v in $runtoks; do
    printf '%s\n' "$helptoks" | grep -qxF -- "$v" \
        && : \
        || no "PC-2: runtime honors $v but --help's HONORED-by list omits it"
done
ok "PC-2: every runtime-honored verb is named in --help's HONORED-by list"

# --test-gate itself must be a member of both (the item this round actually migrated)
printf '%s\n' "$runtoks" | grep -qxF -- '--test-gate' && ok "PC-2: --test-gate is in the runtime honored set" || no "PC-2: --test-gate missing from the runtime honored set"
printf '%s\n' "$helptoks" | grep -qxF -- '--test-gate' && ok "PC-2: --test-gate is in --help's HONORED-by list" || no "PC-2: --test-gate missing from --help's HONORED-by list"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
