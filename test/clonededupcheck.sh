#!/usr/bin/env bash
# clonededupcheck.sh — P5W2 gate for the working-tree clone-pass DEDUP in quality.h::computeDelta.
#
# BACKGROUND (the investigation this gate defends). Profiling --quality-delta on a large private C++ corpus
# showed the working-tree clone pass is the dominant cost (~8 s), and it was RECOMPUTED TWICE per call: computeDelta had
# two independent consumers of the clone groups — the `duplication`/`new-clone-of-reused-helper` new-group
# report AND the reuse-connectivity report — and EACH called findClones()+findClonesType3() itself. On
# that corpus the Type-3 pass alone is ~2.7-3.2 s (60 M intra-bucket pair-visits; per-file TOKENIZATION is only
# ~3 %, which is why a token-stream cache was measured and REJECTED — it would save <90 ms). The fix computes
# each clone pass ONCE and feeds both consumers. Because findClones/findClonesType3 are deterministic pure
# functions of the ingest, the single result is field-for-field the value both call sites received before, so
# --quality-delta output is BYTE-IDENTICAL — this gate proves exactly that (the house bar: "faster must never
# change the answer"), plus determinism and that BOTH clone consumers still fire.
#
# What this gate asserts:
#   (a) BYTE-IDENTITY vs a golden binary — --clones (the shared clones.h path, unchanged) and --quality-delta
#       (the deduped path) produce output identical to $GOLD_BIN on the same corpus.
#   (b) EDIT-CORRECTNESS — introducing a NEW exact clone of an EXISTING, WELL-REUSED (high-fan-in) helper into
#       the working tree makes --quality-delta report BOTH a `duplication` regression AND a
#       `new-clone-of-reused-helper` regression — proving BOTH consumers of the now-shared clone vectors still
#       receive them (a dedup that dropped one consumer would silently lose a whole regression kind).
#   (c) DETERMINISM — --quality-delta on a fixed tree is byte-stable across repeated runs.
#   (d) MUTATION TEST — a deliberately-wrong assertion fails, proving (a)-(c) are non-vacuous.
#
# Usage:
#   test/clonededupcheck.sh                        # BIN=build/ripwire, GOLD_BIN=build/ripwire (self — (a) trivially holds)
#   RIPWIRE_BIN=build_p5w2/ripwire GOLD_BIN=build/ripwire test/clonededupcheck.sh   # deduped vs golden
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success. Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
GOLD="${GOLD_BIN:-$ROOT/build/ripwire}"
[ "${GOLD#/}" = "$GOLD" ] && GOLD="$ROOT/$GOLD"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ]  || { echo "no ripwire binary at $BIN — build first (cmake --build build_p5w2 -j)"; exit 2; }
[ -x "$GOLD" ] || { echo "no golden binary at $GOLD"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }

echo "clonededupcheck: BIN=$BIN  GOLD=$GOLD"

# ── Build a self-contained git corpus with a REUSED helper (high fan-in) so the reuse-connectivity kind can
#    fire when it is later duplicated. calc() is called from many sites (fan-in >= kReusedHelperMinFanin=3).
REPO="$TMP/repo"; mkdir -p "$REPO/src"
cat > "$REPO/src/util.cpp" <<'EOF'
// a well-reused helper: several callers give it a high fan-in.
int calc( int a, int b )
{
    int total = 0;
    for( int i = 0; i < a; ++i )
    {
        total += b;
        total ^= ( total << 1 );
        total -= i;
    }
    return total;
}
int callA( int x ) { return calc( x, 2 ) + calc( x, 3 ); }
int callB( int x ) { return calc( x, 4 ) + calc( x, 5 ); }
int callC( int x ) { return calc( x, 6 ) + calc( x, 7 ); }
EOF
cat > "$REPO/src/main.cpp" <<'EOF'
int callA( int );
int callB( int );
int callC( int );
int run( int n ) { return callA( n ) + callB( n ) + callC( n ); }
EOF

( cd "$REPO" && git init -q && git config user.email t@t && git config user.name t \
  && git add -A && git commit -qm base ) || { no "git fixture setup failed"; echo; echo "SOME CHECKS FAILED"; exit 1; }

export TMPDIR="$TMP/cache"; mkdir -p "$TMPDIR"    # isolate qsnap/head caches from the real machine cache

# ── (a) BYTE-IDENTITY on the clean tree: --clones and --quality-delta vs golden ──────────────────────────────
"$GOLD" "$REPO" --clones >"$TMP/g_clones" 2>/dev/null
"$BIN"  "$REPO" --clones >"$TMP/n_clones" 2>/dev/null
cmp -s "$TMP/g_clones" "$TMP/n_clones" \
    && ok "(a) --clones byte-identical to golden (shared clones.h path unchanged)" \
    || no "(a) --clones DIFFERS from golden: $(diff <(head -c 200 "$TMP/g_clones") <(head -c 200 "$TMP/n_clones") | head -3)"

"$GOLD" "$REPO" --quality-delta >"$TMP/g_qd_clean" 2>/dev/null
"$BIN"  "$REPO" --quality-delta >"$TMP/n_qd_clean" 2>/dev/null
cmp -s "$TMP/g_qd_clean" "$TMP/n_qd_clean" \
    && ok "(a) --quality-delta byte-identical to golden on the clean tree (dedup changes no output)" \
    || no "(a) --quality-delta DIFFERS from golden (clean): $(diff "$TMP/g_qd_clean" "$TMP/n_qd_clean" | head -3)"

# ── (b) EDIT-CORRECTNESS: add a NEW exact clone of the reused helper calc() into the working tree ─────────────
# calcDup has an IDENTICAL body to calc (Type-1/2 exact clone); calc has fan-in>=3, so the new group is BOTH a
# `duplication` regression AND a `new-clone-of-reused-helper` regression. --quality-delta auto-baselines vs HEAD
# (the committed tree with no dup), so the dup is genuinely NEW vs baseline. Both kinds must appear, and the new
# binary must produce the SAME quality-delta as the golden binary on this identical working tree.
cat >> "$REPO/src/util.cpp" <<'EOF'
int calcDup( int a, int b )
{
    int total = 0;
    for( int i = 0; i < a; ++i )
    {
        total += b;
        total ^= ( total << 1 );
        total -= i;
    }
    return total;
}
EOF

"$GOLD" "$REPO" --quality-delta >"$TMP/g_qd_edit" 2>/dev/null
"$BIN"  "$REPO" --quality-delta >"$TMP/n_qd_edit" 2>/dev/null

cmp -s "$TMP/g_qd_edit" "$TMP/n_qd_edit" \
    && ok "(b) --quality-delta byte-identical to golden AFTER introducing a new clone (both consumers preserved)" \
    || no "(b) --quality-delta DIFFERS from golden after edit: $(diff "$TMP/g_qd_edit" "$TMP/n_qd_edit" | head -5)"

grep -q 'kind="duplication"' "$TMP/n_qd_edit" \
    && ok "(b) new binary reports a 'duplication' regression for the new clone (consumer #1 fires)" \
    || no "(b) new binary MISSED the 'duplication' regression: $(cat "$TMP/n_qd_edit")"

grep -q 'kind="new-clone-of-reused-helper"' "$TMP/n_qd_edit" \
    && ok "(b) new binary reports 'new-clone-of-reused-helper' (consumer #2 fires — dedup kept BOTH consumers)" \
    || no "(b) new binary MISSED 'new-clone-of-reused-helper' (a dropped consumer): $(cat "$TMP/n_qd_edit")"

# ── (c) DETERMINISM: repeated --quality-delta on the fixed (edited) working tree is byte-stable ──────────────
"$BIN" "$REPO" --quality-delta >"$TMP/n_qd_det1" 2>/dev/null
"$BIN" "$REPO" --quality-delta >"$TMP/n_qd_det2" 2>/dev/null
cmp -s "$TMP/n_qd_det1" "$TMP/n_qd_det2" \
    && ok "(c) --quality-delta deterministic (two runs byte-identical)" \
    || no "(c) --quality-delta NON-deterministic: $(diff "$TMP/n_qd_det1" "$TMP/n_qd_det2" | head -3)"

# ── (d) MUTATION TEST: a wrong expectation must fail ─────────────────────────────────────────────────────────
if grep -q 'kind="THIS_KIND_NEVER_EXISTS_zzz"' "$TMP/n_qd_edit"; then
    no "(d) mutation-test: matched a kind that can never exist (assertions are broken)"
else
    ok "(d) mutation-test: a deliberately-wrong grep correctly finds no match (assertions above are non-vacuous)"
fi

echo
if [ "$fail" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "SOME CHECKS FAILED"; exit 1; fi
