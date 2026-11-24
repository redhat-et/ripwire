#!/usr/bin/env bash
# tidyratchetcheck.sh — the clang-tidy ratchet holds in both of its halves, and each half can actually fail.
#
# WHY. .clang-tidy's broad report is advisory, so without a ratchet the baseline only ever grows: a nightly lists the
# NEW rows, someone appends them, and nothing says no. Two fences, both gating (0.7.1):
#   (a) ROW COUNT. .clang-tidy-ratchet.txt holds a ceiling per check, generated from .clang-tidy-baseline.txt by
#       scripts/tidyadvisory_diff.py --ratchet-update. A baseline with MORE rows of any check than its ceiling fails
#       (a check with no ceiling has ceiling 0), and so does one with FEWER: a fix lowers the ceiling in its own commit.
#       Pure file arithmetic, so it runs here on every leg.
#   (b) NEW HIGH-SIGNAL FINDING. scripts/tidycheck.sh --ratchet runs the high-signal set (its RATCHET list) over the
#       five CI TUs on every CI event and fails on any finding that is not already a baseline row; exception-escape,
#       too slow for every event, is gated the same way by ci.yml's nightly tidy-exception-escape job. That needs
#       clang-tidy 22 and the compile database, so the whole-tree runs are CI's; THIS gate proves the mechanism on
#       planted sources: a planted finding of two ratchet checks must fail it BY NAME and a near-miss twin must pass.
#
# Usage: test/tidyratchetcheck.sh        (no ripwire binary needed)

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
TMP="$( mktemp -d )"
trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
skip(){ printf '  SKIP  %s\n' "$*"; }
DIFF=( python3 "$ROOT/scripts/tidyadvisory_diff.py" )
BASE="$ROOT/.clang-tidy-baseline.txt"
CEIL="$ROOT/.clang-tidy-ratchet.txt"

echo "tidyratchetcheck: BIN=n/a (baseline arithmetic + planted sources)"

# ─── the diff script's own red/green arms (scope, gate, ratchet) ─────────────────────────────────────────────────
if "${DIFF[@]}" --selftest >"$TMP/self.log" 2>&1; then
    ok "tidyadvisory_diff.py --selftest ($( grep -c '  PASS' "$TMP/self.log" ) arms)"
else
    no "tidyadvisory_diff.py --selftest:"; grep 'FAIL' "$TMP/self.log" | sed 's/^/        /'
fi

# ─── (a) the committed baseline matches its committed ceilings ───────────────────────────────────────────────────
[ -f "$CEIL" ] || no "missing $CEIL"
if "${DIFF[@]}" --baseline "$BASE" --ratchet "$CEIL" >"$TMP/r.log" 2>&1; then
    ok "baseline matches .clang-tidy-ratchet.txt ($( sed -n 's/.*ratchet baseline=\([0-9]*\).*/\1/p' "$TMP/r.log" ) rows)"
else
    no "baseline does not match its ratchet:"; sed 's/^/        /' "$TMP/r.log"
fi
# planted: one more row of an existing check, one row of a check with no ceiling, one row fewer
cp "$BASE" "$TMP/grown.txt"
printf 'src/planted.h\tbugprone-exception-escape\tvoid planted() noexcept\n' >>"$TMP/grown.txt"
cp "$BASE" "$TMP/newcheck.txt"
printf 'src/planted.h\tbugprone-planted-check\tint planted;\n' >>"$TMP/newcheck.txt"
awk 'BEGIN{ d = 0 } !/^#/ && NF && !d { d = 1; next } { print }' "$BASE" >"$TMP/fewer.txt"
for pc in grown:GREW newcheck:GREW fewer:SHRANK; do
    p="${pc%%:*}"; word="${pc#*:}"
    if "${DIFF[@]}" --baseline "$TMP/$p.txt" --ratchet "$CEIL" >"$TMP/$p.log" 2>&1; then
        no "ratchet passed the planted '$p' baseline"
    elif grep -q "  $word " "$TMP/$p.log"; then
        ok "ratchet refuses the planted '$p' baseline ($word)"
    else
        no "ratchet refused '$p' but not as $word:"; sed 's/^/        /' "$TMP/$p.log"
    fi
done

# ─── (b) the high-signal set, on planted sources, through the same diff the CI step uses ─────────────────────────
# ratchet-nightly is the per-event list plus exception-escape (gated by the nightly tidy-exception-escape job): the plant covers both.
RATCHET="$( "$ROOT/scripts/tidycheck.sh" --list | sed -n 's/^ratchet-nightly: //p' )"
[ -n "$RATCHET" ] || no "scripts/tidycheck.sh --list printed no ratchet-nightly: line"
case ",$RATCHET," in *,bugprone-unchecked-optional-access,*) ;; *) no "the per-event ratchet lost bugprone-unchecked-optional-access" ;; esac
BREW="${HOMEBREW_PREFIX:-/opt/homebrew}"
CT=""
for c in "${CLANG_TIDY:-}" "$( command -v clang-tidy-22 2>/dev/null )" "$BREW/opt/llvm@22/bin/clang-tidy"; do
    [ -n "$c" ] && [ -x "$c" ] && "$c" --version 2>/dev/null | grep -q 'version 22\.' && { CT="$c"; break; }
done
if [ -z "$CT" ] || [ -z "$RATCHET" ]; then
    skip "clang-tidy 22 not found: the planted half of (b) is not proved here (CI's style job runs it)"
else
    extra=()
    if [ "$( uname -s )" = "Darwin" ] && command -v xcrun >/dev/null 2>&1; then
        extra=( "-isysroot$( xcrun --show-sdk-path )" )
    fi
    cat >"$TMP/plant.cpp" <<'EOF'
#include <optional>
#include <stdexcept>
int unchecked( std::optional<int> o ) { return *o; }                       // bugprone-unchecked-optional-access
void escapes( int x ) noexcept { if( x ) { throw std::runtime_error( "x" ); } }   // bugprone-exception-escape
EOF
    cat >"$TMP/twin.cpp" <<'EOF'
#include <optional>
int checked( std::optional<int> o ) { return o ? *o : 0; }
void contained( int x ) noexcept { (void)x; }
EOF
    printf '# empty baseline: every finding on a planted file is NEW\n' >"$TMP/empty-base.txt"
    for p in plant twin; do
        "$CT" --quiet --checks="-*,$RATCHET" "$TMP/$p.cpp" -- -std=c++23 "${extra[@]+"${extra[@]}"}" >"$TMP/$p.report" 2>&1
        echo "$?" >"$TMP/$p.rc"
        "${DIFF[@]}" --report "$TMP/$p.report" --rc "$TMP/$p.rc" --root "$TMP" --baseline "$TMP/empty-base.txt" \
            --scope "$RATCHET" --gate >"$TMP/$p.log" 2>&1
        echo "$?" >"$TMP/$p.gate"
    done
    g="$( cat "$TMP/plant.gate" )"
    if [ "$g" = 1 ] && grep -q 'bugprone-unchecked-optional-access' "$TMP/plant.log" && grep -q 'bugprone-exception-escape' "$TMP/plant.log"; then
        ok "the ratchet gate FAILS the planted unchecked-optional-access and exception-escape findings, by name"
    else
        no "the ratchet gate did not refuse the plant by name (gate exit $g):"; sed 's/^/        /' "$TMP/plant.log" | head -12
    fi
    g="$( cat "$TMP/twin.gate" )"
    if [ "$g" = 0 ]; then
        ok "the ratchet gate PASSES the near-miss twin (checked optional, contained noexcept)"
    else
        no "the ratchet gate refused the near-miss twin (gate exit $g):"; sed 's/^/        /' "$TMP/twin.log" | head -12
    fi
fi

[ "$fail" = 0 ] && printf 'ALL PASS\n' || printf 'FAILURES ABOVE\n'
exit "$fail"
