#!/usr/bin/env bash
# namingconsistencycheck.sh — gate for `--naming-consistency` (§9.2 TIER A convention normalization,
# src/namingconsistency.h). Hand-controlled fixture at test/namingconsistencyfix/ so every number below is
# asserted EXACTLY, not eyeballed:
#   consistent.cpp — 27 camelCase + 2 snake_case + 1 mixed (do_snakeMix) + 1 single-token (run) +
#                    1 digit-boundary-only (md5sum, no case signal at all)
#   small.py       — 5 camelCase functions: under the 20-vote sample floor
#   split.rs       — 10 camelCase + 10 snake_case: an even split, over the sample floor but under the
#                    90% agreement floor
#
#   test/namingconsistencycheck.sh   |   RIPWIRE_BIN=asan/ripwire test/namingconsistencycheck.sh
#
# Exit 0 = ALL PASS, non-zero = SOME FAILED.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/namingconsistencyfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIX" ] || { echo "no fixture dir at $FIX"; exit 2; }

echo "namingconsistencycheck: BIN=$BIN  FIX=$FIX"

OUT="$( "$BIN" "$FIX" --naming-consistency --no-cache 2>"$TMP/err" )"; rc=$?

# ── 1) runs clean and exit code is always 0 (a lens, never a gate) ─────────────────────────────────────
[ $rc -eq 0 ] && ok "runs clean, exit 0" || { no "exit code $rc (want 0 — this verb never gates)"; cat "$TMP/err"; }

# ── 2) deterministic: two runs byte-identical ───────────────────────────────────────────────────────────
OUT2="$( "$BIN" "$FIX" --naming-consistency --no-cache 2>/dev/null )"
[ "$OUT" = "$OUT2" ] && ok "two runs are byte-identical" || no "two runs differ — determinism broken"

# ── 3) well-formed XML ──────────────────────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$OUT" | xmllint --noout - 2>"$TMP/xmlerr" \
        && ok "well-formed XML" \
        || { no "xmllint rejected the output"; cat "$TMP/xmlerr"; }
else
    echo "  SKIP  xmllint not installed"
fi

# ── 4) header counts: 3 groups, 55 styled candidates, 1 decided, 3 flagged ─────────────────────────────
echo "$OUT" | grep -q '<naming-consistency groups="3" candidates="55" decided="1" flagged="3"' \
    && ok "header: groups=3 candidates=55 decided=1 flagged=3" \
    || no "header counts wrong: $( echo "$OUT" | grep -oE '<naming-consistency[^>]*>' )"

# ── 5) cpp/fn DECIDES camel at 27/29 ────────────────────────────────────────────────────────────────────
echo "$OUT" | grep -q '<g lang="cpp" kind="fn" style="camel" agree="27" total="29"/>' \
    && ok "cpp/fn group: style=camel agree=27 total=29" \
    || no "cpp/fn group wrong: $( echo "$OUT" | grep -oE '<g lang="cpp"[^/]*/>' )"

# ── 6) py/fn is UNAVAILABLE, insufficient-sample (5 < the 20 floor) ────────────────────────────────────
echo "$OUT" | grep -q '<g lang="py" kind="fn" style="UNAVAILABLE" why="insufficient-sample" total="5"/>' \
    && ok "py/fn group: UNAVAILABLE why=insufficient-sample total=5" \
    || no "py/fn group wrong: $( echo "$OUT" | grep -oE '<g lang="py"[^/]*/>' )"

# ── 7) rs/fn is UNAVAILABLE, no-clear-convention (10/20 = 50%, under the 90% floor, sample floor cleared) ─
echo "$OUT" | grep -q '<g lang="rs" kind="fn" style="UNAVAILABLE" why="no-clear-convention" total="20"/>' \
    && ok "rs/fn group: UNAVAILABLE why=no-clear-convention total=20" \
    || no "rs/fn group wrong: $( echo "$OUT" | grep -oE '<g lang="rs"[^/]*/>' )"

# ── 8) the exact 3 flagged rows, with MECHANICALLY correct propose= values ─────────────────────────────
echo "$OUT" | grep -q 'n="do_snake_one" lang="cpp" kind="fn" style="snake" propose="doSnakeOne"' \
    && ok "flags do_snake_one, proposes doSnakeOne" || no "do_snake_one row missing or wrong"
echo "$OUT" | grep -q 'n="do_snake_two" lang="cpp" kind="fn" style="snake" propose="doSnakeTwo"' \
    && ok "flags do_snake_two, proposes doSnakeTwo" || no "do_snake_two row missing or wrong"
echo "$OUT" | grep -q 'n="do_snakeMix" lang="cpp" kind="fn" style="mixed" propose="doSnakeMix"' \
    && ok "flags do_snakeMix as style=mixed, proposes doSnakeMix" || no "do_snakeMix row missing or wrong"

# ── 9) no-signal names never appear as a flagged row (nothing to normalize) ────────────────────────────
if echo "$OUT" | grep -qE 'n="run"|n="md5sum"'; then
    no "a no-signal name (run/md5sum) was flagged — it should never vote or be flagged"
else
    ok "single-token (run) and digit-only (md5sum) names are silently excluded, not flagged"
fi

# ── 10) paging: --limit=1 windows correctly, --offset finds the 3rd (last) flagged row ─────────────────
P1="$( "$BIN" "$FIX" --naming-consistency --no-cache --limit=1 2>/dev/null )"
echo "$P1" | grep -q 'shown="1" capped="1" total="3" has_more="1" next_offset="1"' \
    && ok "--limit=1 pages correctly (shown=1 total=3 has_more=1)" \
    || no "--limit=1 header wrong: $( echo "$P1" | grep -oE '<naming-consistency[^>]*>' )"
P3="$( "$BIN" "$FIX" --naming-consistency --no-cache --limit=1 --offset=2 2>/dev/null )"
echo "$P3" | grep -q 'n="do_snakeMix"' \
    && ok "--offset=2 lands on the 3rd flagged row (do_snakeMix)" \
    || no "--offset=2 did not return do_snakeMix: $P3"

# ── 11) metric CAN fail: mutating the fixture toward an even split flips the group to UNAVAILABLE ──────
# Copy the fixture, rename 10 more camel functions to snake_case so cpp/fn goes from 27/29 (93%) to
# 17/29 (59%) — still over the sample floor, now under the agreement floor. If the verdict does not move,
# the "dominant style" is not actually being computed from the corpus.
MUT="$TMP/mut"
mkdir -p "$MUT"
cp "$FIX"/*.cpp "$FIX"/*.py "$FIX"/*.rs "$MUT"/ 2>/dev/null
python3 - "$MUT/consistent.cpp" <<'PYEOF'
import re, sys
path = sys.argv[1]
with open(path) as f:
    text = f.read()
words = ["Alpha","Beta","Gamma","Delta","Epsilon","Zeta","Eta","Theta","Iota","Kappa"]
for w in words:
    text = text.replace(f"compute{w}()", f"compute_{w.lower()}()")
with open(path, "w") as f:
    f.write(text)
PYEOF
MOUT="$( "$BIN" "$MUT" --naming-consistency --no-cache 2>/dev/null )"
echo "$MOUT" | grep -q '<g lang="cpp" kind="fn" style="UNAVAILABLE" why="no-clear-convention" total="29"/>' \
    && ok "mutation: flipping 10/27 camel names to snake_case flips cpp/fn to UNAVAILABLE (17/29 = 59% < 90%)" \
    || no "mutation did not flip the verdict — the metric may be hardcoded: $( echo "$MOUT" | grep -oE '<g lang="cpp" kind="fn"[^/]*/>' )"

[ "$fail" -eq 0 ] && echo "namingconsistencycheck: ALL PASS" || echo "namingconsistencycheck: FAILURES"
exit $fail
