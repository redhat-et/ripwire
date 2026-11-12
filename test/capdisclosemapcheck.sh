#!/usr/bin/env bash
# test/capdisclosemapcheck.sh — CAP-DISCLOSE-LINT (B43): every answer-path cap constant says how the answer discloses it.
#
# WHY. Two CodeRabbit findings in one week were the same shape: a cap that silently shortened an answer. #614
# (4542271958): kImportSpecDepth stopped the import walk at 12 statements and the answer read as complete; the fix set
# capped=1 through atDepthCap. #613 (4540061421): kReaderCallerReaders walked 3 reader owners and dropped the rest
# unsaid; the fix counted them into readers_more=. CLAUDE.md non-negotiable 3 ("every truncation is disclosed") had no
# gate, so each cap was audited by a reviewer or not at all. test/capdisclosurecheck.sh is the behavioural sibling: it
# crosses three specific caps with a fixture and reads the answer. This gate is the static census over all of them.
#
# THE MAP. test/capdisclose.map names, per constant, the identifier that discloses it (sink:), a static_assert'd legend
# sentence (legend), not-a-cut (none:) or a baselined audit item (pending:). test/lib/capdisclose.py is the matcher and
# documents the scope and the classes. Checked both ways: a new answer-path cap with no row FAILS; a stale row FAILS; a
# sink: whose identifier some cap site's FUNCTION never mentions FAILS with file:line. Function scope, not a line window:
# a ±N-line window passed both red revisions above (the disclosure flag lived 50+ lines from the compare, the red code
# had other "shown" text nearby), and the function is where the cap and its disclosure have to meet.
#
# ARMS
#   (P0) premise: the real tree has >= 20 in-scope caps and every class is represented — FAIL on a blind scan (0 caps).
#   (P1) planted: an unmapped cap FAILS; a sink row PASSES when its function names the sink; the SAME sink one function
#        away (the #614 red shape) FAILS; a stale row FAILS; an absent awaits: row and a pending: row are INFO only.
#   (R)  the real tree against test/capdisclose.map: no FAIL row.
# usage: test/capdisclosemapcheck.sh [BIN]   (BIN is accepted for the regression.sh calling convention and not used:
#        this is a source scan, under a second.)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
LIB="$ROOT/test/lib/capdisclose.py"
MAP="$ROOT/test/capdisclose.map"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
command -v python3 >/dev/null 2>&1 || { echo "  FAIL  python3 is required"; echo "SOME CHECKS FAILED"; exit 1; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

echo "== capdisclosemapcheck: answer-path caps name their disclosure =="

# ── (R) + (P0): the real tree ─────────────────────────────────────────────────────────────────────────────────────────
python3 -I "$LIB" "$ROOT" "$MAP" >"$TMP/real.out" 2>&1; rrc=$?
sum="$( grep '^SUMMARY' "$TMP/real.out" | tail -1 )"
n_scope="$( printf '%s' "$sum" | sed -n 's/.*in_scope=\([0-9]*\).*/\1/p' )"
n_sink="$( printf '%s' "$sum" | sed -n 's/.* sinks=\([0-9]*\).*/\1/p' )"
n_leg="$( printf '%s' "$sum" | sed -n 's/.* legend=\([0-9]*\).*/\1/p' )"
n_pend="$( printf '%s' "$sum" | sed -n 's/.* pending=\([0-9]*\).*/\1/p' )"
if [ -z "$sum" ]; then
    no "(P0) the matcher printed no SUMMARY (rc=$rrc): $( tail -2 "$TMP/real.out" | tr '\n' ' ' )"
elif [ "${n_scope:-0}" -lt 20 ] || [ "${n_sink:-0}" -lt 1 ] || [ "${n_leg:-0}" -lt 1 ]; then
    no "(P0) the scan looks blind: ${sum#SUMMARY } (expected >= 20 in-scope caps, >= 1 sink and >= 1 legend row)"
else
    ok "(P0) the scan is live: ${sum#SUMMARY }"
fi
if [ "$rrc" = 0 ] && ! grep -q '^FAIL' "$TMP/real.out"; then
    ok "(R) every in-scope cap has a row and every sink is named in its cap sites' functions ($n_pend baselined as pending:, listed below)"
else
    no "(R) rc=$rrc — fix each row below, or add the missing one to test/capdisclose.map:"
    grep '^FAIL' "$TMP/real.out" | head -20 | sed 's/^/        /'
fi
grep '^INFO' "$TMP/real.out" | cut -c1-200 | sed 's/^/  /'

# ── (P1): planted fixtures ────────────────────────────────────────────────────────────────────────────────────────────
F="$TMP/fx"; mkdir -p "$F/src"
cat >"$F/src/forfx.h" <<'EOF'
inline constexpr std::size_t kFxRows = 8;
inline constexpr std::size_t kFxDepth = 12;
inline constexpr std::size_t kFxWalk = 3;
inline constexpr std::size_t kFxPend = 4;
inline void rows( Out& out, const Rows& rs )
{
    std::size_t shown = 0, capped = 0;
    for( const auto& r : rs ) { if( shown >= kFxRows ) { capped = 1; break; } ++shown; }
    out.attr( "capped", capped );
}
inline void walkDisclose( Out& out ) { const bool atDepthCap = true; out.attr( "capped", atDepthCap ); }
inline void walk( const States& st )
{
    for( const auto& s : st ) { if( s.depth >= kFxDepth ) { continue; } }
}
inline void readers( const Rs& rs ) { for( std::size_t r = 0; r < rs.size() && r < kFxWalk; ++r ) { } }
inline void pend( const Rs& rs ) { for( std::size_t r = 0; r < rs.size() && r < kFxPend; ++r ) { } }
EOF
fx(){ printf '%b' "$1" >"$TMP/fx.map"; python3 -I "$LIB" "$F" "$TMP/fx.map" >"$TMP/fx.out" 2>&1; echo $?; }
base='kFxRows\tsink:capped\nkFxDepth\tsink:atDepthCap\nkFxWalk\tsink:readersMore\nkFxPend\tpending:#1 planted\n'
r="$( fx "kFxRows\tsink:capped\nkFxPend\tpending:#1 planted\n" )"
if [ "$r" = 1 ] && grep -q '^FAIL kFxDepth .*no row' "$TMP/fx.out" && grep -q '^FAIL kFxWalk .*no row' "$TMP/fx.out"; then
    ok "(P1a) a cap with no row FAILS by name (kFxDepth, kFxWalk)"
else no "(P1a) an unmapped cap did not FAIL (rc=$r): $( grep -E '^(FAIL|SUMMARY)' "$TMP/fx.out" | tr '\n' ' ' )"; fi
r="$( fx "$base" )"
if grep -q '^PASS kFxRows: all 1 cap site' "$TMP/fx.out"; then ok "(P1b) a sink named in the cap site's function PASSES (kFxRows / capped)"
else no "(P1b) kFxRows did not PASS: $( grep kFxRows "$TMP/fx.out" | tr '\n' ' ' )"; fi
if [ "$r" = 1 ] && grep -q '^FAIL kFxDepth: 1 of 1 cap site(s) sit in a function that never mentions atDepthCap: src/forfx.h:14' "$TMP/fx.out"; then
    ok "(P1c) the #614 red shape FAILS with file:line: atDepthCap is set one function away from the compare"
else no "(P1c) the one-function-away sink did not FAIL at src/forfx.h:14 (rc=$r): $( grep kFxDepth "$TMP/fx.out" | tr '\n' ' ' )"; fi
if grep -q '^FAIL kFxWalk: .*never mentions readersMore' "$TMP/fx.out"; then ok "(P1d) the #613 red shape FAILS: the reader walk stops at kFxWalk and counts nothing"
else no "(P1d) the #613 red shape did not FAIL: $( grep kFxWalk "$TMP/fx.out" | tr '\n' ' ' )"; fi
r="$( fx "${base}kFxGone\tsink:capped\n" )"
if grep -q '^FAIL stale row kFxGone' "$TMP/fx.out"; then ok "(P1e) a stale row FAILS"
else no "(P1e) a stale row did not FAIL: $( grep kFxGone "$TMP/fx.out" | tr '\n' ' ' )"; fi
r="$( fx "kFxRows\tsink:capped\nkFxDepth\tpending:#2 planted\nkFxWalk\tlegend\nkFxPend\tpending:#1 planted\nkFxLane\tsink:x\tawaits:#9\n" )"
if grep -q '^INFO kFxLane awaits #9' "$TMP/fx.out" && grep -q '^INFO kFxPend pending' "$TMP/fx.out" && ! grep -q '^FAIL kFx\(Lane\|Pend\|Depth\)' "$TMP/fx.out" \
    && grep -q '^FAIL kFxWalk: classified legend, but no static_assert' "$TMP/fx.out"; then
    ok "(P1f) awaits: and pending: rows are INFO only; a legend row with no static_assert FAILS"
else no "(P1f) awaits/pending/legend classes misbehaved: $( grep -E '^(FAIL|INFO)' "$TMP/fx.out" | tr '\n' ' ' )"; fi

if [ "$fail" = 0 ]; then
    echo "ALL PASS"
else
    echo "SOME CHECKS FAILED"
fi
exit "$fail"
