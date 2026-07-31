#!/usr/bin/env bash
# qackorigincheck.sh — r27 P0.3 gate: a ZERO-MAGNITUDE ack must never become a permanent blank check.
#
# THE BUG THIS PINS. `applyAckRatchet` suppresses a finding when `now <= ackNow`. The api-surface tier-A push
# emits was=now=0 for BOTH shapes it can produce:
#   * origin="new-symbol"        — additive surface on brand-new code: sev=minor, NEVER gates;
#   * surface="contract-change"  — a symbol that already existed became part of the public contract: major, GATES.
# Both landed under the SAME (kind, key) ack identity, so `--quality-ack` sweeping up the harmless new-symbol
# rows (209 of this repo's own 402 committed ack lines were exactly that) meant the later, genuine
# private -> public flip on the same symbol hit `0 <= 0` and was suppressed FOREVER. `dead-code` (always now=0)
# has the identical shape. quality.h's own ack contract says "an ack accepts a finding AT its acked size, never
# a blank check" — this was the counterexample.
#
# THE FIX: a zero-magnitude finding acks on IDENTITY + ORIGIN. Its ack token carries `:new-symbol` or
# `:preexisting`, so the two rows are two different acks. Findings that HAVE a magnitude are untouched.
#
# MIGRATION (checked here too): a legacy bare token acked at magnitude 0 is read as the `:new-symbol` variant —
# that is what those rows overwhelmingly were, and the rows we cannot distinguish are re-surfaced rather than
# silently kept, i.e. fail-closed.
#
# Fixture mechanics. Tier-A "contract-change" needs a canonId that EXISTS in the baseline's per-symbol maps but
# is ABSENT from its public set. That is exactly the shape of a baseline written by an older binary with a
# narrower notion of "public", and it is reproduced deterministically here by stripping the `api ` lines out of
# a freshly-written .ripwire_quality_baseline sidecar. Nothing about the fix depends on the fixture's route to
# that state — only on the two rows sharing an identity, which they do.
#
# Checks:
#   (a) phase 1 — a new public symbol yields origin="new-symbol", sev=minor, and does NOT gate (exit 0).
#   (b) --quality-ack records it under an ORIGIN-QUALIFIED token (`api-surface:new-symbol`), not a bare kind.
#   (c) the ack still suppresses its OWN row on a re-run (the ratchet still works for the class it accepted).
#   (d) THE FIX — with that ack in place, the SAME symbol's contract-change row is still reported and GATES
#       (exit 2). Pre-fix this row was suppressed and the run exited 0.
#   (e) MIGRATION — a hand-written LEGACY bare `ack api-surface <key> 0` line suppresses the new-symbol row
#       (it is read as the :new-symbol variant) but does NOT suppress the contract-change row.
#   (f) a magnitude-bearing ack is untouched: its token stays bare and the ratchet still re-reports on worsening.
#
# Own temp repo, own private cache dir. Needs git.
# Usage:  test/qackorigincheck.sh   |   RIPWIRE_BIN=build/ripwire test/qackorigincheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ echo "  PASS  $1"; }
no(){ echo "  FAIL  $1"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }

REPO="$( mktemp -d )"; TMP="$( mktemp -d )"; trap 'rm -rf "$REPO" "$TMP"' EXIT
XDG="$TMP/xdg"; mkdir -p "$XDG"
run(){ env -u TMPDIR XDG_CACHE_HOME="$XDG" "$BIN" "$REPO" "$@"; }
ACKS="$REPO/.ripwire_quality_acks"
BASE="$REPO/.ripwire_quality_baseline"

echo "qackorigincheck: BIN=$BIN"

mkdir -p "$REPO/inc" "$REPO/src"
cat > "$REPO/inc/api.h" <<'EOF'
int stableOne( int a );
int stableTwo( int a, int b );
EOF
cat > "$REPO/src/lib.cpp" <<'EOF'
#include "../inc/api.h"
int stableOne( int a ) { return a + 1; }
int stableTwo( int a, int b ) { return a + b; }
EOF
git -C "$REPO" init -q; git -C "$REPO" config user.email x@y; git -C "$REPO" config user.name x
git -C "$REPO" add -A; git -C "$REPO" commit -qm init

# ── (a) phase 1: a brand-new public symbol → origin="new-symbol", minor, does not gate ────────────────────
cat >> "$REPO/inc/api.h" <<'EOF'
int freshExport( int a );
EOF
run --quality-delta >"$TMP/p1" 2>/dev/null; rc1=$?
{ [ "$rc1" -eq 0 ] && grep -q 'sym="[^"]*freshExport"[^/]*origin="new-symbol"' "$TMP/p1"; } \
    && ok "new public symbol reports origin=\"new-symbol\" and does not gate (exit 0)" \
    || { no "phase 1 unexpected (exit=$rc1)"; tr '<' '\n' < "$TMP/p1" | grep freshExport; }

# ── (b) --quality-ack writes an ORIGIN-QUALIFIED token ────────────────────────────────────────────────────
run --quality-delta --quality-ack="fixture: additive surface" >/dev/null 2>&1
if grep -q '^ack api-surface:new-symbol ' "$ACKS" 2>/dev/null; then
    ok "--quality-ack records the zero-magnitude row as 'api-surface:new-symbol' (origin-qualified identity)"
else
    no "ack file has no origin-qualified api-surface token — zero-magnitude acks still key on the bare kind"
    cat "$ACKS" 2>/dev/null | head -5
fi
AKEY="$( sed -n 's/^ack api-surface:new-symbol \([0-9a-f]*\) .*/\1/p' "$ACKS" | head -1 )"
[ -n "$AKEY" ] && ok "recovered the acked identity key ($AKEY) for the cross-origin check" \
                || no "could not recover the acked identity key — later checks are vacuous"

# ── (c) the ack still suppresses its own row ──────────────────────────────────────────────────────────────
ACKED_FILE="$TMP/acks_qualified"; cp "$ACKS" "$ACKED_FILE"
run --quality-delta >"$TMP/p1b" 2>/dev/null; rc1b=$?
{ [ "$rc1b" -eq 0 ] && ! grep -q 'freshExport' "$TMP/p1b" && grep -q 'acked="[1-9]' "$TMP/p1b"; } \
    && ok "the ack still suppresses its OWN new-symbol row, honestly (acked=N)" \
    || { no "the ack no longer suppresses the row it was taken against"; tr '<' '\n' < "$TMP/p1b" | grep -E 'quality-delta |freshExport'; }

# ── (e1) MIGRATION, keep half: a LEGACY bare zero-magnitude ack still suppresses the class it was recorded
#         for. Checked HERE, while the tree is still in the phase-1 (new-symbol) shape.
if [ -n "$AKEY" ]; then
    printf '# legacy pre-r27 ack file\nack api-surface %s 0 legacy bare token\n' "$AKEY" > "$ACKS"
    run --quality-delta >"$TMP/p1c" 2>/dev/null
    grep -q 'freshExport' "$TMP/p1c" \
        && { no "legacy bare ack stopped suppressing the new-symbol row it was recorded for"; tr '<' '\n' < "$TMP/p1c" | grep freshExport | head -2; } \
        || ok "a LEGACY bare ack still suppresses the new-symbol row it was recorded for (migration preserves meaning)"
fi
cp "$ACKED_FILE" "$ACKS"

# ── (d) THE FIX: the same symbol's CONTRACT-CHANGE row is not blank-checked by that ack ────────────────────
# Commit the header (so freshExport exists at the baseline), pin a sidecar baseline, then strip its `api `
# records — freshExport is now present in the per-symbol maps but absent from the public set, which is the
# tier-A contract-change shape. Same canonId ⇒ same identity key as the ack taken in (b).
git -C "$REPO" add -A; git -C "$REPO" commit -qm "export freshExport" >/dev/null
run --quality-baseline >/dev/null 2>&1
[ -s "$BASE" ] && ok "pinned a baseline sidecar for the contract-change phase" || no "no baseline sidecar written"
grep -v '^api ' "$BASE" > "$TMP/base_noapi" && cp "$TMP/base_noapi" "$BASE"

run --quality-delta >"$TMP/p2" 2>/dev/null; rc2=$?
CCROW="$( tr '<' '\n' < "$TMP/p2" | grep 'freshExport' | grep 'contract-change' )"
if [ -n "$CCROW" ] && [ "$rc2" -eq 2 ]; then
    ok "the SAME symbol's contract-change row survives the new-symbol ack and GATES (exit 2)"
else
    no "contract-change row suppressed or non-gating (exit=$rc2) — the zero-magnitude blank check is back"
    tr '<' '\n' < "$TMP/p2" | grep -E 'quality-delta |freshExport' | head -4
fi
printf '%s' "$CCROW" | grep -q 'gating="1"' \
    && ok "the surviving contract-change row is marked gating=\"1\"" \
    || no "the gating row carries no gating=\"1\" marker"

# ── (e2) MIGRATION, fail-closed half: the same LEGACY line must NOT reach the contract-change row ─────────
if [ -n "$AKEY" ]; then
    printf '# legacy pre-r27 ack file\nack api-surface %s 0 legacy bare token\n' "$AKEY" > "$ACKS"
    run --quality-delta >"$TMP/p3" 2>/dev/null; rc3=$?
    { [ "$rc3" -eq 2 ] && tr '<' '\n' < "$TMP/p3" | grep 'freshExport' | grep -q 'contract-change'; } \
        && ok "a LEGACY bare zero-magnitude ack does NOT suppress the contract-change row (fail-closed migration)" \
        || { no "legacy bare ack still blank-checks the contract-change row (exit=$rc3)"; tr '<' '\n' < "$TMP/p3" | grep freshExport | head -3; }
fi

# ── (f) magnitude-bearing acks are untouched (bare token, ratchet still re-reports on worsening) ──────────
git -C "$REPO" checkout -q -- .
rm -f "$BASE" "$ACKS"
cat >> "$REPO/src/lib.cpp" <<'EOF'
int knotty( int a, int b, int c ) {
    int r = 0;
    for( int i = 0; i < a; ++i ) {
        if( i % 2 == 0 ) { if( i > b ) { r += i; } else { r -= 1; } }
        else { for( int j = 0; j < b; ++j ) { if( j > c ) { r += j; } else { r--; } } }
        while( r > c && r > b ) { r = r - 1; if( r % 3 == 0 ) { r += 2; } }
    }
    return r;
}
EOF
run --quality-delta --quality-ack="fixture: accepted complexity" >/dev/null 2>&1
if grep -q '^ack complexity [0-9a-f]* [1-9]' "$ACKS" 2>/dev/null; then
    ok "a magnitude-bearing finding still acks under its BARE kind (unchanged shape)"
else
    grep -q '^ack complexity:' "$ACKS" 2>/dev/null \
        && no "a magnitude-bearing finding was origin-qualified — the split must be zero-magnitude only" \
        || no "no complexity ack recorded — fixture vacuous"
    head -5 "$ACKS" 2>/dev/null
fi

[ "$fail" -eq 0 ] && echo "qackorigincheck: ALL PASS" || { echo "qackorigincheck: SOME CHECKS FAILED"; exit 1; }
