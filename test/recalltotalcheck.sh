#!/usr/bin/env bash
# recalltotalcheck.sh — §B2 gate: --recall's "K relevant of N docs" / total= must be the TRUE pre-cut
# relevant count (files with score > 0), not the post-top-k-cut count dressed up as if it were the true
# count. Pre-fix: recallTopFiles collected every scoring file, resized to a HARDCODED 8, and reported the
# POST-cut size as both the prose numerator and total=, with capped="0" always — a broad query on this repo
# ("the") measured 99 of 155 docs scoring > 0, 91 of them dropped with NO disclosure (--recall="the" said
# "8 relevant of 155 docs", capped=0). --top-k=N was also accept-and-ignore for --recall: --top-k=2,
# --top-k=20 and the unset default all produced byte-identical output, even though --help and the --limit
# refusal both already named --top-k as the flag that shapes it.
#
# Required (fixed) behavior:
#   - the prose numerator and total= report the TRUE relevant count (score > 0), independent of --top-k
#   - shown= is what THIS run actually emitted; capped= is the honest total-vs-shown gap
#   - --top-k=N is HONORED: it shapes how many docs get emitted; the DEFAULT (no --top-k) stays 8
#
# Independent derivation of the true count: a run with --top-k=9999 (far above anything this repo's docs
# corpus can match) cannot possibly be cut by --top-k, so its shown= IS the true relevant count by
# construction — the same invariant the fix must hold: total= must not move when --top-k changes. Cross-
# checking the small-k run's total= against the huge-k run's shown= is the independent means the round's
# prompt calls for; a raw byte-for-byte reimplementation of BM25 in bash is not practical, but this catches
# exactly the bug: the pre-fix binary reports total=8 no matter what --top-k is, so the two numbers a fixed
# binary must agree on (small-k total= vs huge-k shown=) simply never agree pre-fix.
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/recalltotalcheck.sh
#         RIPWIRE_BIN=build_base/ripwire bash test/recalltotalcheck.sh   # must FAIL (pre-fix binary, RED)
# Exits non-zero on any failure. Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "recalltotalcheck: BIN=$BIN  TARGET=$ROOT (self-scan, broad query \"the\")"

run(){ perl -e 'alarm 60; exec @ARGV' "$BIN" "$ROOT" --recall="the" --no-cache "$@" 2>/dev/null; }
header_of(){ printf '%s' "$1" | head -1; }
total_of(){ header_of "$1" | grep -oE ' total=[0-9]+' | grep -oE '[0-9]+'; }
shown_of(){ header_of "$1" | grep -oE ' shown=[0-9]+' | grep -oE '[0-9]+'; }
capped_of(){ header_of "$1" | grep -oE ' capped=[0-9]+' | grep -oE '[0-9]+$'; }
# each recalled doc opens its own separator line "━━ path ... ━━..." — an independent per-doc-block count
# straight from the payload, not from the header's own numeric field.
sep_count(){ printf '%s\n' "$1" | grep -c '^━━ '; }

# ── gather the four runs up front — every field a fail-loud number, never silently absent ─────────────
DEFAULT="$( run )";              DEFAULT_RC=$?
K2="$( run --top-k=2 )";         K2_RC=$?
K20="$( run --top-k=20 )";       K20_RC=$?
BIG="$( run --top-k=9999 )";     BIG_RC=$?

for pair in "DEFAULT:$DEFAULT_RC" "K2:$K2_RC" "K20:$K20_RC" "BIG:$BIG_RC"; do
    name="${pair%%:*}"; rc="${pair##*:}"
    [ "$rc" = 0 ] && ok "$name run: exit 0" || no "$name run: exit $rc (expected 0) — cannot evaluate further fields for $name"
done

DEFAULT_TOTAL="$( total_of "$DEFAULT" )";  DEFAULT_SHOWN="$( shown_of "$DEFAULT" )";  DEFAULT_CAPPED="$( capped_of "$DEFAULT" )"
K2_TOTAL="$( total_of "$K2" )";            K2_SHOWN="$( shown_of "$K2" )"
K20_TOTAL="$( total_of "$K20" )";          K20_SHOWN="$( shown_of "$K20" )"
BIG_TOTAL="$( total_of "$BIG" )";          BIG_SHOWN="$( shown_of "$BIG" )"

for pair in "DEFAULT_TOTAL:$DEFAULT_TOTAL" "DEFAULT_SHOWN:$DEFAULT_SHOWN" "DEFAULT_CAPPED:$DEFAULT_CAPPED" \
            "K2_TOTAL:$K2_TOTAL" "K2_SHOWN:$K2_SHOWN" "K20_TOTAL:$K20_TOTAL" "K20_SHOWN:$K20_SHOWN" \
            "BIG_TOTAL:$BIG_TOTAL" "BIG_SHOWN:$BIG_SHOWN"; do
    name="${pair%%:*}"; val="${pair#*:}"
    [ -n "$val" ] || no "$name: field missing from its header entirely (expected a number)"
done

# ── 1) independent derivation: a --top-k=9999 run cannot be cut by --top-k (no repo has that many relevant
#    docs), so its shown= IS the true relevant count. total= must equal it AT EVERY --top-k value — the
#    true count does not depend on how many docs get emitted.
if [ -n "$BIG_TOTAL" ] && [ -n "$BIG_SHOWN" ]; then
    [ "$BIG_TOTAL" = "$BIG_SHOWN" ] \
        && ok "--top-k=9999: total=$BIG_TOTAL == shown=$BIG_SHOWN (nothing left to cut at this k — the true count)" \
        || no "--top-k=9999: total=$BIG_TOTAL != shown=$BIG_SHOWN — even an uncapped run doesn't emit everything it counted"
fi
if [ -n "$DEFAULT_TOTAL" ] && [ -n "$BIG_SHOWN" ]; then
    [ "$DEFAULT_TOTAL" = "$BIG_SHOWN" ] \
        && ok "independent check: default run's total=$DEFAULT_TOTAL == --top-k=9999's shown=$BIG_SHOWN (true relevant count, --top-k-independent)" \
        || no "independent check: default run's total=$DEFAULT_TOTAL != --top-k=9999's true count $BIG_SHOWN — total= moves with --top-k (the bug)"
fi
if [ -n "$K2_TOTAL" ] && [ -n "$DEFAULT_TOTAL" ]; then
    [ "$K2_TOTAL" = "$DEFAULT_TOTAL" ] \
        && ok "--top-k=2: total=$K2_TOTAL matches the default run's total=$DEFAULT_TOTAL (total= is --top-k-independent)" \
        || no "--top-k=2: total=$K2_TOTAL != default total=$DEFAULT_TOTAL — total= should not depend on --top-k"
fi
if [ -n "$K20_TOTAL" ] && [ -n "$DEFAULT_TOTAL" ]; then
    [ "$K20_TOTAL" = "$DEFAULT_TOTAL" ] \
        && ok "--top-k=20: total=$K20_TOTAL matches the default run's total=$DEFAULT_TOTAL (total= is --top-k-independent)" \
        || no "--top-k=20: total=$K20_TOTAL != default total=$DEFAULT_TOTAL — total= should not depend on --top-k"
fi

# ── 2) the minimum fallback the round's prompt also asks for: on this known-broad query, total > shown,
#    and the header's capped=1 (a real gap must be flagged, not hidden behind capped=0)
if [ -n "$DEFAULT_TOTAL" ] && [ -n "$DEFAULT_SHOWN" ]; then
    [ "$DEFAULT_TOTAL" -gt "$DEFAULT_SHOWN" ] \
        && ok "default run: total=$DEFAULT_TOTAL > shown=$DEFAULT_SHOWN (a broad query drops docs — must be disclosed)" \
        || no "default run: total=$DEFAULT_TOTAL not > shown=$DEFAULT_SHOWN — expected this query to be broader than the default cap"
    GAP=$(( DEFAULT_TOTAL - DEFAULT_SHOWN ))
    [ "$GAP" -gt 0 ] && ok "default run: total-shown=$GAP > 0 (the honest gap the prompt requires)" \
                     || no "default run: total-shown=$GAP not > 0"
fi
[ "$DEFAULT_CAPPED" = "1" ] \
    && ok "default run: capped=1 (a real gap is flagged, not hidden behind capped=0)" \
    || no "default run: capped=$DEFAULT_CAPPED (expected capped=1 for a query with total > shown)"

# ── 3) --top-k=N is HONORED: shapes how many docs actually get emitted ─────────────────────────────────
[ "$K2_SHOWN" = "2" ] \
    && ok "--top-k=2: shown=2" \
    || no "--top-k=2: shown=$K2_SHOWN (expected 2) — --top-k is not shaping the emitted count"
[ "$( sep_count "$K2" )" = "2" ] \
    && ok "--top-k=2: exactly 2 doc separator blocks actually printed (shown= matches the real payload)" \
    || no "--top-k=2: printed $( sep_count "$K2" ) doc blocks, header said shown=$K2_SHOWN (expected both = 2)"

if [ -n "$K20_SHOWN" ]; then
    [ "$K20_SHOWN" -gt 8 ] \
        && ok "--top-k=20: shown=$K20_SHOWN > 8 (more than the default cap got through)" \
        || no "--top-k=20: shown=$K20_SHOWN not > 8 — --top-k=20 did not raise the emitted count above the default"
fi
[ "$( sep_count "$K20" )" = "$K20_SHOWN" ] \
    && ok "--top-k=20: doc separator blocks printed ($( sep_count "$K20" )) match header shown=$K20_SHOWN" \
    || no "--top-k=20: printed $( sep_count "$K20" ) doc blocks, header said shown=$K20_SHOWN — disclosure inconsistent with the real payload"

# ── 4) the DEFAULT (no --top-k passed) still emits exactly 8 — no default behavior change ─────────────
[ "$DEFAULT_SHOWN" = "8" ] \
    && ok "default (no --top-k): shown=8 (default cap unchanged)" \
    || no "default (no --top-k): shown=$DEFAULT_SHOWN (expected 8 — the default must stay 8)"
[ "$( sep_count "$DEFAULT" )" = "8" ] \
    && ok "default (no --top-k): exactly 8 doc separator blocks printed" \
    || no "default (no --top-k): printed $( sep_count "$DEFAULT" ) doc blocks (expected 8)"

# ── 5) determinism ──────────────────────────────────────────────────────────────────────────────────
[ "$( run )" = "$DEFAULT" ] \
    && ok "default run deterministic (byte-identical run-to-run)" \
    || no "default run non-deterministic"
[ "$( run --top-k=2 )" = "$K2" ] \
    && ok "--top-k=2 deterministic (byte-identical run-to-run)" \
    || no "--top-k=2 non-deterministic"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
