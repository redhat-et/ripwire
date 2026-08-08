#!/usr/bin/env bash
# expandmodecheck.sh — M6 (density audit 2026-08-08, lane D): cheapest-complete-answer serving for --expand.
#
#   test/expandmodecheck.sh                        # uses build/ripwire on test/expandmodefix
#   RIPWIRE_BIN=asan/ripwire test/expandmodecheck.sh
#
# WHY. A bare `--expand=SYM` always carried the full global ranked map: on a symbol in a SMALL file the
# bundle was 5.65x LARGER than the whole file it was summarizing (this repo: --expand=pageRankDouble
# 27,890 B vs src/pagerank.cpp 4,936 B — and still 1.08x the file at --top-k=0), while on a big file the
# same bundle saves ~26x over reading the file. Owner directive: ONE call does the smart thing, no
# "read the stderr note, re-run with --top-k=0" two-step. So --expand now compares, BEFORE emitting, the
# byte cost of the default bundle (map + bodies) against the whole file(s) the requested symbols live in,
# and serves the smaller, disclosing the choice deterministically on the <ctx> root:
#   mode="whole-file" reason="file NB < bundle MB"   — the file(s), CDATA-wrapped, symbol line anchors kept
#   mode="bundle"     reason="bundle MB <= file NB"  — today's map+bodies bundle, now labelled
# An EXPLICIT --top-k=N overrides auto-selection entirely (the agent asked for the map; N=0 is the lean
# bodies-only form) and keeps the legacy byte-shape: no mode= attribute at all.
# The lean (--top-k=0) form deliberately does NOT compete in auto-selection: it is a strict byte-subset of
# the bundle, so a three-way minimum could never serve the map and a bare --expand would silently lose its
# orientation value; lean stays what it has always been — the caller's explicit choice.
#
# Arms (all three of the audit's RED assertions):
#   (1) small-file symbol -> mode="whole-file", the full file in CDATA with the symbol's line anchor, and
#       total bytes <= file bytes + 700 B envelope slack;
#   (2) large-file symbol -> mode="bundle": the ranked map and <bodies> both still present;
#   (3) explicit --top-k=5 forces the map back with NO mode= attribute (override semantics), and explicit
#       --top-k=0 stays the undecorated lean form.
# Plus: xmllint well-formedness on every mode, determinism on the auto modes, and the disclosed byte
# comparison must agree with reality (whole-file total < the bundle total actually measured in arm 2's
# world). The fixture is copied to a tmp dir OUTSIDE any git repo and scanned via a RELATIVE path, so
# output carries no churn attrs and no absolute paths. Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN (build first)"; exit 1; }

mkdir -p "$TMP/fix"
cp "$ROOT"/test/expandmodefix/*.c "$TMP/fix/"
cd "$TMP"
fileBytes="$( wc -c <"$TMP/fix/small.c" | tr -d ' ' )"

# ── (1) small-file symbol: the whole file is the cheapest complete answer ─────────────────────────────
"$BIN" fix --expand=smallProbe --no-cache >"$TMP/small.xml" 2>/dev/null
grep -q 'mode="whole-file"' "$TMP/small.xml" \
    && ok "(1) small-file --expand serves mode=\"whole-file\"" \
    || no "(1) small-file --expand did not serve mode=\"whole-file\" (the 5.65x-over-file bundle again)"
grep -q 'reason="file [0-9]*B &lt; bundle [0-9]*B"' "$TMP/small.xml" \
    && ok "(1) the choice is disclosed as reason=\"file NB &lt; bundle MB\" (escaped '<' — a raw one is ill-formed in an attribute)" \
    || no "(1) no deterministic reason= disclosure on the whole-file form"
grep -q 'CDATA' "$TMP/small.xml" \
    && ok "(1) whole-file body is CDATA-wrapped (G4 well-formedness)" \
    || no "(1) whole-file form carries no CDATA section"
grep -q 'smallProbe:' "$TMP/small.xml" \
    && ok "(1) the symbol's line anchor survives (sym name:line)" \
    || no "(1) whole-file form lost the symbol's line anchor"
total="$( wc -c <"$TMP/small.xml" | tr -d ' ' )"
if [ "$total" -le $(( fileBytes + 700 )) ]; then
    ok "(1) total $total B <= file $fileBytes B + 700 B envelope slack"
else
    no "(1) whole-file form costs $total B against a $fileBytes B file — envelope slack blown"
fi
if grep -q '<r ' "$TMP/small.xml"; then
    no "(1) the ranked map still rides along in whole-file mode"
else
    ok "(1) no ranked map in whole-file mode"
fi

# ── (2) large-file symbol: the bundle stays the cheapest complete answer ──────────────────────────────
"$BIN" fix --expand=bigProbe007 --no-cache >"$TMP/big.xml" 2>/dev/null
grep -q 'mode="bundle"' "$TMP/big.xml" \
    && ok "(2) large-file --expand keeps mode=\"bundle\"" \
    || no "(2) large-file --expand lost the bundle mode"
grep -q '<r ' "$TMP/big.xml" \
    && ok "(2) the ranked map is present in bundle mode" \
    || no "(2) bundle mode lost the ranked map"
grep -q '<bodies' "$TMP/big.xml" \
    && ok "(2) the <bodies> payload is present in bundle mode" \
    || no "(2) bundle mode lost the <bodies> payload"
grep -q 'reason="bundle [0-9]*B &lt;= file [0-9]*B"' "$TMP/big.xml" \
    && ok "(2) bundle mode discloses the comparison it won" \
    || no "(2) bundle mode carries no reason= disclosure"

# ── the disclosed comparison agrees with reality ──────────────────────────────────────────────────────
bundleTotal="$( wc -c <"$TMP/big.xml" | tr -d ' ' )"
if [ "$total" -lt "$bundleTotal" ]; then
    ok "(1v2) whole-file total ($total B) < bundle total ($bundleTotal B) on this fixture — the choice saved bytes"
else
    no "(1v2) whole-file mode ($total B) did not beat the bundle ($bundleTotal B)"
fi

# ── (3) explicit --top-k overrides auto-selection, legacy byte-shape ──────────────────────────────────
"$BIN" fix --expand=smallProbe --top-k=5 --no-cache >"$TMP/topk5.xml" 2>/dev/null
grep -q '<r ' "$TMP/topk5.xml" \
    && ok "(3) --top-k=5 forces the map back" \
    || no "(3) --top-k=5 did not restore the ranked map"
if grep -q 'mode="' "$TMP/topk5.xml"; then
    no "(3) explicit --top-k=5 still carries a mode= attribute — override must keep the legacy shape"
else
    ok "(3) explicit --top-k=5 output is undecorated (no mode= attribute)"
fi
"$BIN" fix --expand=smallProbe --top-k=0 --no-cache >"$TMP/topk0.xml" 2>/dev/null
if grep -q '<r \|mode="' "$TMP/topk0.xml"; then
    no "(3) explicit --top-k=0 must stay the undecorated lean form (no map, no mode=)"
else
    ok "(3) explicit --top-k=0 stays the undecorated lean form"
fi

# ── (3b) a RANGE slice is an explicit narrowing: serving the whole file would invert the ask ──────────
"$BIN" fix --expand=smallProbe:2-3 --no-cache >"$TMP/range.xml" 2>/dev/null
if grep -q 'mode="' "$TMP/range.xml"; then
    no "(3b) a ranged --expand=SYM:2-3 must keep the legacy shape (no mode= auto-selection)"
else
    ok "(3b) a ranged --expand=SYM:2-3 keeps the legacy shape (slice contract untouched)"
fi
grep -q 'lines="' "$TMP/range.xml" \
    && ok "(3b) the slice marker (lines=) survives" \
    || no "(3b) the ranged request lost its lines= slice marker"

# ── well-formedness + determinism ─────────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    for f in small big topk5 topk0; do
        xmllint --noout "$TMP/$f.xml" 2>/dev/null && ok "(G4) $f.xml well-formed" || no "(G4) $f.xml fails xmllint"
    done
fi
"$BIN" fix --expand=smallProbe --no-cache >"$TMP/small2.xml" 2>/dev/null
diff -q "$TMP/small.xml" "$TMP/small2.xml" >/dev/null \
    && ok "(det) whole-file mode byte-identical twice" \
    || no "(det) whole-file mode differs across two runs"
"$BIN" fix --expand=bigProbe007 --no-cache >"$TMP/big2.xml" 2>/dev/null
diff -q "$TMP/big.xml" "$TMP/big2.xml" >/dev/null \
    && ok "(det) bundle mode byte-identical twice" \
    || no "(det) bundle mode differs across two runs"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
