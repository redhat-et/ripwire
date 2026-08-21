#!/usr/bin/env bash
# ackonlycheck.sh — --ack-only=SUBSTR must ack a SUBSET, and refuse when it matches nothing.
#
# Why this flag exists: --quality-ack accepted THE WHOLE REPORT or nothing. To accept one deliberate
# contract change you had to accept every finding on screen — which is how a per-finding ratchet quietly
# becomes a rubber stamp, the exact failure the origin split was built to stop. Acking by KIND is not
# precise enough either: "api-surface" also covers the never-gating new-symbol rows, so on this repo's own
# round it would have swept in 59 findings to accept 8. Matching the FACET (contract-change) is what makes
# a narrow, honest ack expressible.
#
# The gate runs on a synthetic repo so it never depends on ripwire's own current debt.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN"; exit 2; }

echo "ackonlycheck: BIN=$BIN"

R="$TMP/repo"; mkdir -p "$R"
cd "$R"; git init -q .; git config user.email t@t; git config user.name t

# baseline: two public functions with a small arity, plus a function we will make more complex
cat > lib.h <<'EOF'
#pragma once
inline int alpha( int a ) { return a; }
inline int beta( int a ) { return a + 1; }
inline int gamma_fn( int a )
{
    int t = 0;
    for( int i = 0; i < a; ++i ) { if( i % 2 == 0 ) t += i; else t -= i; }
    return t;
}
EOF
git add lib.h; git commit -qm base
"$BIN" . --quality-baseline >/dev/null 2>&1
[ -f .ripwire_quality_baseline ] && ok "baseline snapshot written" || { no "no baseline written"; echo "ALL FAIL"; exit 1; }

# the change: alpha and beta each gain a parameter (api-surface contract-change on a PREEXISTING symbol),
# and gamma_fn gets markedly more complex (a complexity regression, a DIFFERENT kind).
cat > lib.h <<'EOF'
#pragma once
inline int alpha( int a, int b ) { return a + b; }
inline int beta( int a, int b ) { return a + b + 1; }
inline int gamma_fn( int a )
{
    int t = 0;
    for( int i = 0; i < a; ++i )
    {
        if( i % 2 == 0 )      { if( i % 3 == 0 ) t += i * 2; else t += i; }
        else if( i % 5 == 0 ) { if( i % 7 == 0 ) t -= i * 2; else t -= i; }
        else if( i % 11 == 0 ){ t += 1; }
        else                  { if( i > 100 ) t -= 1; else t += 3; }
    }
    return t;
}
EOF

"$BIN" . --quality-delta >"$TMP/before.xml" 2>/dev/null
TOTAL="$( grep -oE '<r ' "$TMP/before.xml" | wc -l | tr -d ' ' )"
[ "$TOTAL" -ge 2 ] && ok "fixture produced $TOTAL findings of >1 kind to select among" || no "fixture produced too few findings ($TOTAL)"

# 0) --ack-only WITHOUT --quality-ack must refuse loudly, not silently print the ordinary default map
#    (§P1, 2026-07-28 output audit: this was the exact rubber-stamp failure the flag exists to prevent —
#    a typo'd narrowing, or an invocation the operator believes narrowed something, quietly acking nothing
#    and exiting 0). Runs on the real repo root, not the synthetic fixture — the guard fires pre-scan.
"$BIN" . --ack-only=gating >"$TMP/noack.out" 2>"$TMP/noack.err"
rc=$?
[ $rc -eq 1 ] && ok "--ack-only without --quality-ack refuses (exit 1)" || no "--ack-only without --quality-ack exited $rc (expected 1)"
[ ! -s "$TMP/noack.out" ] && ok "…and prints nothing to stdout (no silent default map)" || no "…but printed $( wc -c <"$TMP/noack.out" ) bytes to stdout"
grep -q -- '--quality-ack' "$TMP/noack.err" && grep -q -- '--ack-only' "$TMP/noack.err" \
    && ok "…and the message names both flags" || no "…without naming both flags: $( cat "$TMP/noack.err" )"

# 1) a pattern matching NOTHING must refuse loudly and write nothing, never silently ack everything.
cp .ripwire_quality_acks "$TMP/acks.pre" 2>/dev/null || : > "$TMP/acks.pre"
"$BIN" . --quality-delta --ack-only=zzz-no-such-finding --quality-ack="probe" >/dev/null 2>"$TMP/none.err"
rc=$?
[ $rc -eq 1 ] && ok "--ack-only matching nothing exits 1" || no "--ack-only matching nothing exited $rc (expected 1)"
grep -q 'matched none' "$TMP/none.err" && ok "…and says so on stderr" || no "…with no explanatory stderr"
if [ -f .ripwire_quality_acks ]; then
    cmp -s .ripwire_quality_acks "$TMP/acks.pre" && ok "…and wrote nothing" || no "…but MODIFIED the ack file"
else ok "…and wrote nothing (no ack file)"; fi

# 2) the narrow ack: only the api-surface contract-changes, leaving the complexity finding gating.
"$BIN" . --quality-delta --ack-only=contract-change --quality-ack="deliberate arity change" >/dev/null 2>"$TMP/narrow.err"
grep -qE 'acknowledged [0-9]+ of [0-9]+ finding' "$TMP/narrow.err" \
    && ok "narrow ack reports acked-of-total, not just a count" \
    || { no "narrow ack did not report the subset shape"; cat "$TMP/narrow.err"; }
grep -q 'left UNACKED' "$TMP/narrow.err" && ok "…and names how many it deliberately left alone" || no "…without naming what it left"

"$BIN" . --quality-delta >"$TMP/after.xml" 2>/dev/null
rc=$?
GA="$( grep -oE 'gating="[0-9]+"' "$TMP/after.xml" | grep -oE '[0-9]+' | head -1 )"
GB="$( grep -oE 'gating="[0-9]+"' "$TMP/before.xml" | grep -oE '[0-9]+' | head -1 )"
[ "${GA:-0}" -lt "${GB:-0}" ] && ok "gating dropped after the narrow ack ($GB -> $GA)" || no "gating did not drop ($GB -> $GA)"
[ "${GA:-0}" -gt 0 ] \
    && ok "a finding of ANOTHER kind still gates — the ack was a subset, not a blanket" \
    || no "the narrow ack silenced everything (gating=0) — that is the rubber stamp this flag exists to avoid"
[ $rc -eq 2 ] && ok "exit is still 2 while an unacked major preexisting finding remains" || no "exit was $rc (expected 2)"

# 3) the acked kind really is gone from the gating set.
grep -oE '<r [^>]*gating="1"[^>]*/>' "$TMP/after.xml" | grep -q 'contract-change' \
    && no "an acked contract-change is still marked gating" \
    || ok "no acked contract-change remains in the gating set"

# 4) 'gating' pseudo-token selects exactly what would exit 2.
"$BIN" . --quality-delta --ack-only=gating --quality-ack="accept the rest" >/dev/null 2>&1
"$BIN" . --quality-delta >"$TMP/all.xml" 2>/dev/null
rc=$?
[ $rc -eq 0 ] && ok "--ack-only=gating clears the gate (exit 0)" || no "--ack-only=gating left exit $rc"
grep -q 'gating="0"' "$TMP/all.xml" && ok "…and the header agrees (gating=\"0\")" || no "…but the header still counts gating findings"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
