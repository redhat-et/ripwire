#!/usr/bin/env bash
# bm25check.sh — RANKING-CORE gate for --query=TERMS (pure lexical BM25 retrieval, src/lexical.h). This is
# the "relatedness" ranking signal (as opposed to PageRank "importance" — see src/lexical.h's header note:
# the eval-at-scale showed the two must NOT be fused). Zero prior coverage before this gate.
#
# Fixture test/bm25fix/ has 3 files / 7 functions:
#   widget.cpp:  frobnicate_widget()  — the ONLY symbol whose name+doc contain "frobnicate"+"widget"
#                compute_tally()      — doc mentions the ubiquitous term "module"
#   gadget.cpp:  calibrate_gadget(), reset_gadget_errors() — docs mention "module", nothing re widget
#   common.cpp:  module_startup_log(), module_shutdown_log(), module_validate_handle() — "module" x3
#   → "module" appears in the doc-comment of ALL 7 symbols (ubiquitous / near-zero IDF);
#     "frobnicate"+"widget" appear only in frobnicate_widget()'s name+doc (maximally distinctive).
#
# House rule: float scores are NEVER asserted bit-exact — assert ORDER (first <s> emitted, since files and
# symbols are both bucketed rank-desc — see src/serialize.h) and coarse ratios via k= parsing, never
# string-equality on an absolute score.
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/bm25check.sh   |   RIPWIRE_BIN=asan/ripwire bash …
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/bm25fix"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
[ -d "$FIX" ] || { echo "no test/bm25fix dir — fixture missing"; exit 2; }
cd "$ROOT"

echo "bm25check: BIN=$BIN  CORPUS=test/bm25fix"

# run a --query (alarm-guarded so a hang fails loudly instead of blocking the gate)
q(){ perl -e 'alarm 15; exec @ARGV' "$BIN" "$FIX" --query="$1" --no-cache 2>/dev/null; }

# first <s ...> tag's n="..." attribute — the top-ranked symbol (files AND symbols are both bucketed
# rank-desc in serialize.h, so the first <s> in the whole doc is the global rank-1 symbol).
top_name(){ printf '%s' "$1" | grep -oE '<s [^>]*n="[^"]*"' | head -1 | grep -oE 'n="[^"]*"' | sed 's/n="//;s/"//'; }

# k="..." of the <s> whose n="NAME" — first match (a name can repeat across overloads in general, but not
# in this fixture).
k_of(){ printf '%s' "$1" | grep -oE '<s [^>]*n="'"$2"'"[^>]*k="[0-9.]+"' | head -1 | grep -oE 'k="[0-9.]+"' | sed 's/k="//;s/"//'; }

# ── #1: distinctive-term query ranks frobnicate_widget() FIRST ─────────────────────────────────────────
OUT_DISTINCT="$( q "frobnicate widget" )"
top1="$( top_name "$OUT_DISTINCT" )"
[ "$top1" = "frobnicate_widget" ] \
    && ok "distinctive query 'frobnicate widget' ranks frobnicate_widget() first (got: $top1)" \
    || no "distinctive query top should be frobnicate_widget, got: $top1"

# ── #2: a query matching nothing exits cleanly with an empty/near-empty (all-zero) result ──────────────
OUT_NOMATCH="$( q "zzznonexistenttermzzz" )"
NOMATCH_EC=$?
nonzero_k="$( printf '%s' "$OUT_NOMATCH" | grep -oE 'k="[0-9.]+"' | grep -vE 'k="0(\.0+)?"' | wc -l | tr -d ' ' )"
{ [ "$NOMATCH_EC" = 0 ] && [ "$nonzero_k" = 0 ]; } \
    && ok "no-match query exits cleanly (0) with an all-zero-score result (0 nonzero k=)" \
    || no "no-match query should exit 0 with all k=0.0000 (exit=$NOMATCH_EC, nonzero-k count=$nonzero_k)"

# ── #3: determinism — twice, byte-identical ─────────────────────────────────────────────────────────────
A="$( q "frobnicate widget" )"; B="$( q "frobnicate widget" )"
if [ "$A" = "$B" ]; then ok "determinism: --query byte-identical run-to-run"; else no "non-deterministic --query output"; fi

# ── #4: IDF sanity — a term in ALL 7 docs ("module") must not make frobnicate_widget() dominate the way
#    the distinctive query does; concretely: frobnicate_widget()'s own k= under the distinctive query must
#    be strictly greater than its k= under the ubiquitous-term query (its doc doesn't even CONTAIN
#    "module", so the ubiquitous query should score it 0, but assert via the numeric comparison per the
#    house rule rather than a string-equality on "0.0000"). ─────────────────────────────────────────────
OUT_UBIQ="$( q "module" )"
k_distinct="$( k_of "$OUT_DISTINCT" "frobnicate_widget" )"
k_ubiq="$( k_of "$OUT_UBIQ" "frobnicate_widget" )"
awk -v d="$k_distinct" -v u="$k_ubiq" 'BEGIN{ exit !(d > u + 0.01) }' \
    && ok "IDF sanity: frobnicate_widget() k under distinctive query ($k_distinct) > under ubiquitous 'module' query ($k_ubiq)" \
    || no "IDF sanity failed: distinctive k=$k_distinct not > ubiquitous k=$k_ubiq"

# also: the ubiquitous query must not crash and must still produce a well-formed, non-empty ranking over
# all 7 symbols (a common term dominating everything equally is a degrade, not a crash).
ubiq_syms="$( printf '%s' "$OUT_UBIQ" | grep -oE '<s ' | wc -l | tr -d ' ' )"
[ "$ubiq_syms" = 7 ] \
    && ok "ubiquitous-term query doesn't crash / drop symbols (7 symbols present)" \
    || no "ubiquitous-term query should still emit all 7 symbols, got $ubiq_syms"

# ── xml well-formed ──────────────────────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    if q "frobnicate widget" | xmllint --noout - 2>/dev/null; then ok "xml well-formed"; else no "xml malformed"; fi
else
    printf '  SKIP  xml well-formed (no xmllint)\n'
fi

# ── #5 CALLEE-FIELD-ONCE: a call SITE puts its callee name in the caller's document once, however many
#    candidates the resolver split it over (src/lexical.h calleeEdgeTimes). Generated at test time, so no
#    whole-repo run sees it. Pairs whose texts tokenize identically and differ ONLY in how the resolver bound
#    the call must score identically under a query only their names carry ("caller"):
#      alpha_caller  obj.ping()                — one site split over the 5 `ping` impls (5 edges)
#      bravo_caller  obj.pong()                — one site, one `pong` (1 edge)
#      charlie_caller obj.ping(); other.ping() — two sites, the same 5 edges: counts TWO, not 5, not 1
#      delta_caller  obj.pong(); other.pang()  — two sites, two unique callees (2 edges)
#    Main counted one name per edge, so alpha's and charlie's documents carried 5 `ping`s and scored below
#    their twins. ─────────────────────────────────────────────────────────────────────────────────────────
CF="$( mktemp -d "${TMPDIR:-/tmp}/bm25callee.XXXXXX" )"
trap 'rm -rf "$CF"' EXIT
{
    for n in 1 2 3 4 5; do printf 'class A%s:\n    def ping(self):\n        return %s\n' "$n" "$n"; done
    printf 'class B1:\n    def pong(self):\n        return 6\n'
    printf 'class B2:\n    def pang(self):\n        return 7\n'
    printf 'def alpha_caller(obj):\n    return obj.ping()\n'
    printf 'def bravo_caller(obj):\n    return obj.pong()\n'
    printf 'def charlie_caller(obj, other):\n    obj.ping()\n    return other.ping()\n'
    printf 'def delta_caller(obj, other):\n    obj.pong()\n    return other.pang()\n'
} > "$CF/m.py"
cf(){ perl -e 'alarm 15; exec @ARGV' "$BIN" "$CF" --no-cache "$@" 2>/dev/null; }
callee_count(){ cf --callees="$1" | grep -oE '<callees [^>]*count="[0-9]+"' | grep -oE 'count="[0-9]+"' | grep -oE '[0-9]+'; }
# premise: the split really is 5 candidates and the twins really are unique, else the equalities below are vacuous
pa="$( callee_count alpha_caller )"; pb="$( callee_count bravo_caller )"; pc="$( callee_count charlie_caller )"; pd="$( callee_count delta_caller )"
{ [ "$pa" = 5 ] && [ "$pb" = 1 ] && [ "$pc" = 5 ] && [ "$pd" = 2 ]; } \
    && ok "callee-field premise: alpha/charlie split over 5 ping candidates, bravo 1 callee, delta 2 (got $pa/$pb/$pc/$pd)" \
    || no "callee-field premise: expected callees 5/1/5/2, got '$pa'/'$pb'/'$pc'/'$pd' — the arms below would test nothing"
OUT_CF="$( cf --query=caller )"
ka="$( k_of "$OUT_CF" alpha_caller )"; kb="$( k_of "$OUT_CF" bravo_caller )"
kc="$( k_of "$OUT_CF" charlie_caller )"; kd="$( k_of "$OUT_CF" delta_caller )"
{ [ -n "$ka" ] && [ "$ka" = "$kb" ]; } \
    && ok "callee-field once: a site split over 5 candidates scores like its 1-candidate twin (alpha k=$ka, bravo k=$kb)" \
    || no "callee-field once: alpha_caller k='$ka' != bravo_caller k='$kb' — the split site's callee name counted per candidate"
{ [ -n "$kc" ] && [ "$kc" = "$kd" ]; } \
    && ok "callee-field per site: two sites over the same 5 candidates count two names (charlie k=$kc, delta k=$kd)" \
    || no "callee-field per site: charlie_caller k='$kc' != delta_caller k='$kd' — two split sites must count twice, not 5 times or once"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
