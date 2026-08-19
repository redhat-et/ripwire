#!/usr/bin/env bash
# fillordercheck.sh — T3 gate: fill-aware auto important-last ordering.
#
# WHAT T3 CHANGED (Wave-T "T3"):
# --most-important-last already existed as an explicit flag. T3 auto-selects it (no flag needed) once
# the T1-calibrated est_tokens estimate says the DEFAULT map output is large enough that recency
# dominates (MEASURED: beyond ~50% fill of a nominal window, position effects favour the END; below
# that the U-curve holds and order is a wash) — kFillOrderThreshold in src/serialize.h, currently
# kNominalWindowTokens/2 = 16000 (32K nominal window, the smaller point in §2a's dose-response study).
#
# NOT SHIPPED here (T7 measured-and-declined, see src/serialize.h's T3 comment): bimodal emission
# (--eval structurally cannot score it) and Markdown-KV/table sub-encoding (measured +17% per-symbol,
# only ~7% win on a whole --metrics map at >=4 rows — marginal, format-contract risk). This gate does
# NOT test either — they are not part of what shipped.
#
# The contract:
#   (a) GOLDEN NEUTRAL: the DEFAULT small map (test/fixture, est_tokens=619 — §H7 re-pin, see #1) and src/ (~11-13K tokens,
#       well under the ~16K threshold) do NOT auto-flip — order=important-first, byte-identical to a
#       pre-T3 run. This is the hard requirement; T3 must be invisible until output is genuinely large.
#   (b) On a large output (src/ --top-k=100000, ~27K tokens > threshold), the DEFAULT run (no flag)
#       auto-flips to important-last and marks it OBSERVABLY: order="important-last(auto:fill)" —
#       distinct from the explicit-flag marker "important-last" (never a silent behaviour change).
#   (c) --no-auto-order opts out on the same large input — order stays important-first.
#   (d) An explicit --most-important-last / --stable always wins over the heuristic (no "(auto:fill)"
#       suffix leaks onto an explicit choice); auto-order never overrides stated user intent.
#   (e) The decision is a PURE function of est_tokens → deterministic, run-to-run byte-identical.
#   (f) xml well-formed under the auto-flipped path.
#   (g) MUTATION-TESTED: the auto-flip is a real reordering, not just a header string flip — the first
#       symbol under auto-flip must equal the LAST symbol under the un-flipped (--no-auto-order) run.
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/fillordercheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
cd "$ROOT"

echo "fillordercheck: BIN=$BIN"

order_of(){ "$BIN" "$@" --no-cache 2>/dev/null | grep -oE 'order="?[a-zA-Z_:().-]+"?' | head -1 | sed -E 's/order="?//; s/"?$//'; }
est_of(){   "$BIN" "$@" --no-cache 2>/dev/null | grep -oE 'est_tokens=[0-9]+' | grep -oE '[0-9]+'; }

# ── #1: GOLDEN NEUTRAL — test/fixture (est_tokens=785) stays important-first, no auto-flip ─────────────
# RE-PINNED 745 → 785 (R-E CORRECTION, 2026-08-19): the map legend gained the ONE clause that DEFINES
# root= — `r:root=crawl-root-every-p=-is-relative-to(...)`, in this legend's own key=meaning dialect. The
# 2026-08-17 landing added the attribute to <r> and defined it nowhere, which is what
# test/legendcoveragecheck.sh's arm (A) reported as `default-map | r@root` (plus eight sibling map verbs
# that share this legend); its baseline file may only be edited DOWNWARD, so the fix is the text. +101
# emitted bytes (1861 -> 1962 = wc -c test/golden.xml, re-pinned in the same commit) at the same
# language-weighted rate: 1962/785 = 2.4994 B/tok, inside the calibrated 2.36-2.59 band. Legend bytes
# only: no row, symbol or edge moved (still 6/14/5) and no rank VALUE moved; `important-first` unchanged.
# RE-PINNED 768 → 745 (R-E, 2026-08-17 harvest: root-relative paths for ALL verbs): the default map's
# per-row p= dropped the crawl root's OWN prefix repeated six times ("test/fixture/" on every <f p=…>,
# same F6 pattern G1 fixed for --grep) in favor of ONE root="test/fixture" attribute on <r> — fewer
# emitted bytes despite the map growing no new row/symbol/edge (still 6/14/5). -58 emitted bytes
# (1919 → 1861 = wc -c test/golden.xml, re-pinned in the same commit) at the same language-weighted
# rate: 1861/745 = 2.4980 B/tok, inside the calibrated 2.36-2.59 band. No row moved and no rank VALUE
# moved; `important-first` unchanged. The prior re-pins' reasoning below still stands verbatim.
# RE-PINNED 647 → 691 (markdown section tier, mdsectioncheck): the fixture's two .md files gained
# section hierarchy — "Why it exists"/"Symbols" now carry id= (path::Geometry Fixture::…) and the
# notes.md [[related]] wikilink edge moved from the file node to its enclosing section — +114 emitted
# bytes (1612 → 1726 = wc -c test/golden.xml, re-pinned in the same commit) at the same
# language-weighted rate. Same file/symbol/edge counts (6/14/5); ranks redistribute but
# `important-first` is unchanged. The prior re-pins' reasoning below still stands verbatim.
# RE-PINNED 691 → 768 (W2-F, PageRank convergence disclosure): the map gained the pr_iters= root attribute
# and the ~130-byte legend clause that DEFINES it (src/prconverge.h), +187 emitted bytes on this fixture
# (1732 → 1919 = wc -c test/golden.xml, re-pinned in the same commit) at the same language-weighted rate:
# 1919/768 = 2.4987 B/tok, inside the calibrated 2.36-2.59 band, and the rate is unmoved (1732/691 = 2.5065),
# which is the check that the growth is DOCUMENT bytes and not an estimator drift. No row moved and no rank
# VALUE moved — the change is plumbing and disclosure, proved by stripping the two new attributes and the new
# legend comment from the map and diffing against the pre-change binary (empty). `important-first` unchanged;
# the auto-flip threshold (16000) is >20x this number either way. The prior re-pins' reasoning stands verbatim.
# RE-PINNED 619 → 647 (macro-edges round): the v1 legend comment grew its t= vocabulary
# (|macro(#define;...)), +71 emitted bytes (1541 → 1612 = wc -c test/golden.xml, re-pinned in the same
# commit) at the same language-weighted rate; the fixture itself contains no macro, so no row moved and
# `important-first` is unchanged. The prior re-pin's reasoning below still stands verbatim.
# RE-PINNED 489 → 619 (§H7). REASON: est_tokens is no longer the byte MODEL's
# output — serialize() now measures the bytes the document actually emits and converts them at the model's
# language-weighted rate, because the model priced neither --metrics decoration nor an appended payload and
# therefore reported ONE number for five different documents. On the fixture that correction is +26.6%
# (489 → 619 over 1541 emitted bytes = 2.4895 B/tok, inside the calibrated 2.36-2.59 band; the old number
# implied 1541/489 = 3.1513 B/tok, i.e. the model was under-counting its own markup). The byte count is
# `wc -c test/golden.xml`, which #1b below asserts is byte-identical to this binary's output — CORRECTED from
# "1540" (CA4 verifier L3: an off-by-one in the ledger's arithmetic, not in the conclusion; both rates and the
# under-counting verdict re-derive unchanged from 1541). NOTHING about T3's contract moved:
# the auto-flip DECISION still keys off the pure model (mapEst.tokens) precisely because the emit ORDER has
# to be chosen before any byte exists, so #2-#7 below are unaffected and this arm's `important-first`
# expectation is unchanged. The threshold (16000) is >25x this number either way.
EFIX="$( est_of test/fixture )"
OFIX="$( order_of test/fixture )"
{ [ "$EFIX" = "785" ] && [ "$OFIX" = "important-first" ]; } \
    && ok "test/fixture (est_tokens=$EFIX) does NOT auto-flip — order=$OFIX (golden neutral)" \
    || no "test/fixture unexpectedly changed order or est_tokens (est=$EFIX order=$OFIX)"

# ── #1b: byte-identity against the committed golden ─────────────────────────────────────────────────────
if diff -q <( "$BIN" test/fixture --no-cache 2>/dev/null ) "$ROOT/test/golden.xml" >/dev/null 2>&1; then
    ok "test/fixture output byte-identical to test/golden.xml"
else
    no "test/fixture output DIFFERS from test/golden.xml — golden neutrality broken"
fi

# ── #2: GOLDEN NEUTRAL — src/ at its default top-k (well under threshold) does not auto-flip ────────────
ESRC="$( est_of src )"
OSRC="$( order_of src )"
{ [ -n "$ESRC" ] && [ "$ESRC" -lt 16000 ] 2>/dev/null && [ "$OSRC" = "important-first" ]; } \
    && ok "src/ default map (est_tokens=$ESRC, under threshold) does NOT auto-flip — order=$OSRC" \
    || no "src/ default map unexpectedly near/over threshold or flipped (est=$ESRC order=$OSRC)"

# ── #3: a genuinely LARGE output (src/ --top-k=100000, no cap) crosses the ~16000 threshold and the
#    DEFAULT run (no flag) auto-flips, marked OBSERVABLY as important-last(auto:fill) ──────────────────
EBIG="$( est_of src --top-k=100000 )"
OBIG="$( order_of src --top-k=100000 )"
{ [ -n "$EBIG" ] && [ "$EBIG" -gt 16000 ] 2>/dev/null; } \
    && ok "src/ --top-k=100000 crosses the fill threshold (est_tokens=$EBIG > 16000)" \
    || no "src/ --top-k=100000 did not cross the threshold (est_tokens=$EBIG) — cannot exercise the auto-flip; corpus grew/shrank"
[ "$OBIG" = "important-last(auto:fill)" ] \
    && ok "large default map auto-flips, observably marked: order=$OBIG" \
    || no "large default map did not auto-flip as expected (order=$OBIG)"

# ── #4: --no-auto-order opts OUT on the same large input ─────────────────────────────────────────────────
ONOOPT="$( order_of src --top-k=100000 --no-auto-order )"
[ "$ONOOPT" = "important-first" ] \
    && ok "--no-auto-order opts out on the large input — order=$ONOOPT" \
    || no "--no-auto-order failed to suppress the auto-flip (order=$ONOOPT)"

# ── #5: explicit flags always win over the heuristic — no auto marker leaks onto an explicit choice ─────
OEXPLICIT_BIG="$( order_of src --top-k=100000 --most-important-last )"
[ "$OEXPLICIT_BIG" = "important-last" ] \
    && ok "explicit --most-important-last on the large input reports plain important-last (no auto suffix)" \
    || no "explicit --most-important-last mislabeled on a large input (order=$OEXPLICIT_BIG)"

OSTABLE_BIG="$( order_of src --top-k=100000 --stable )"
[ "$OSTABLE_BIG" = "stable" ] \
    && ok "--stable takes precedence over the auto-flip on a large input — order=$OSTABLE_BIG" \
    || no "--stable did not take precedence on a large input (order=$OSTABLE_BIG)"

OEXPLICIT_SMALL="$( order_of test/fixture --most-important-last )"
[ "$OEXPLICIT_SMALL" = "important-last" ] \
    && ok "explicit --most-important-last on the SMALL fixture still honoured, unaffected by T3" \
    || no "explicit --most-important-last on the small fixture broken (order=$OEXPLICIT_SMALL)"

# ── #6: determinism — the auto-flipped large output is byte-identical run-to-run ─────────────────────────
D1="$( "$BIN" src --top-k=100000 --no-cache 2>/dev/null )"
D2="$( "$BIN" src --top-k=100000 --no-cache 2>/dev/null )"
[ "$D1" = "$D2" ] \
    && ok "auto-flipped large map is deterministic (byte-identical run-to-run)" \
    || no "auto-flipped large map is NON-deterministic run-to-run"

# ── #7: xml well-formed under the auto-flipped path ───────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$D1" | xmllint --noout - 2>/dev/null \
        && ok "xml well-formed under the auto-flipped path" \
        || no "xml malformed under the auto-flipped path"
else
    printf '  SKIP  xml well-formed (no xmllint)\n'
fi

# ── #8: MUTATION-TEST-style check — the flip is a REAL reordering, not just a header relabel. The first
#    <s> emitted under auto-flip must equal the LAST <s> emitted under the un-flipped (--no-auto-order)
#    run on the identical input, proving the auto path actually reverses emit order. A broken
#    implementation that only rewrites the order= string (without reordering) would fail this. ───────────
FIRST_AUTO="$( "$BIN" src --top-k=100000 --no-cache 2>/dev/null              | grep -oE '<s [^>]*' | head -1 )"
LAST_PLAIN="$( "$BIN" src --top-k=100000 --no-auto-order --no-cache 2>/dev/null | grep -oE '<s [^>]*' | tail -1 )"
{ [ -n "$FIRST_AUTO" ] && [ "$FIRST_AUTO" = "$LAST_PLAIN" ]; } \
    && ok "self-mutation check: auto-flip is a REAL reorder (first-under-auto == last-under-plain)" \
    || no "self-mutation check FAILED: auto-flip did not actually reorder symbols (first-auto='$FIRST_AUTO' last-plain='$LAST_PLAIN')"

# ── #9: the symbol SET is unchanged by the flip — same multiset of <s> elements, only order differs ─────
SET_AUTO="$( "$BIN" src --top-k=100000 --no-cache 2>/dev/null              | grep -oE '<s [^>]*' | sort )"
SET_PLAIN="$( "$BIN" src --top-k=100000 --no-auto-order --no-cache 2>/dev/null | grep -oE '<s [^>]*' | sort )"
[ "$SET_AUTO" = "$SET_PLAIN" ] \
    && ok "auto-flip changes ORDER only — identical symbol set to the un-flipped run" \
    || no "auto-flip changed the symbol SET, not just order (regression)"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
