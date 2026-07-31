#!/usr/bin/env bash
# qoriginoraclecheck.sh — r27 gate for the four ORIGIN-ORACLE suspicions raised against the r26 origin split
# (fbc527e). The origin axis decides which findings GATE, so every one of these is an exit-code correctness
# question, not a cosmetic one.
#
#   (A) `originOracleOk = !base.locBySym.empty()` CONFLATED "the sidecar is in the pre-Q1 format" with "HEAD
#       genuinely has no canonId symbols" (a README-only first commit, a docs/JSON-only HEAD, a root pointed at
#       a non-source subdirectory). In the second case the oracle is PERFECT — nothing existed, so every
#       finding is new — yet every finding was classified preexisting-worse and GATED, under an alert claiming
#       the baseline was in a stale pre-Q1 format. Wrong answer and wrong explanation.
#   (A2) `readBaseline` returned true for a 0-byte sidecar purely because the ifstream opened — so a truncated
#       or failed write became "a valid baseline in which nothing existed".
#   (B) `cloneGroupIsNew` walked its members without first asking whether the oracle was available at all, so
#       a group of key-0 (canonId-less) members classified new-symbol — one kind silently disarming the exit
#       code while every other kind failed CLOSED on the same missing oracle.
#   (C) "the reused helper is preexisting BY CONSTRUCTION" was asserted in the comments (and in fbc527e's
#       commit message) but never ENFORCED: kReusedHelperMinFanin=3 is trivially reached by brand-new code, so
#       an all-new blob duplicating ITSELF was reported under a kind whose entire meaning is eroded pre-existing
#       reuse.
#
# Checks:
#   (a) a HEAD with NO indexable source: findings classify origin="new-symbol", exit 0, and NO pre-Q1 alert.
#   (b) a 0-byte sidecar is treated as ABSENT (falls back to the git-HEAD auto-baseline) and gives the same
#       answer as having no sidecar at all.
#   (c) a genuine pre-Q1 sidecar (records but no `loc ` lines) still fails CLOSED: the alert fires and NO row
#       of ANY kind — the clone kinds included — carries origin="new-symbol".
#   (d) all-new code that duplicates itself with fan-in >= 3 is reported as `duplication` but NOT as
#       `new-clone-of-reused-helper`.
#   (e) a clone of a genuinely PREEXISTING high-fan-in helper IS still reported as new-clone-of-reused-helper
#       (the enforcement narrows the kind; it must not empty it).
#
# Own temp repos. Needs git. The DEGRADED alerts are compiled out under NDEBUG, so (c)'s alert sub-check is
# skipped when the binary is a Release build (this is the CI-builds-Release blind spot, logged in CLAUDE.md).
# Usage:  test/qoriginoraclecheck.sh   |   CTXPACK_BIN=build/ctxpack test/qoriginoraclecheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "  SKIP  qoriginoraclecheck (git not available)"; exit 0; }

WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
echo "qoriginoraclecheck: BIN=$BIN"

mkrepo(){ mkdir -p "$1" && ( cd "$1" && git init -q && git config user.email t@t && git config user.name t ); }
commit(){ ( cd "$1" && git add -A >/dev/null 2>&1 && git commit -qm "$2" >/dev/null 2>&1 ); }

# a big, complex, PUBLIC function — reliably produces complexity/verbosity/nesting/api-surface rows.
gnarly(){ cat <<'EOF'
int gnarly( int a, int b, int c ) {
    int r = 0;
    for( int i = 0; i < a; ++i ) {
        if( i % 2 == 0 ) { if( i > b ) { r += i; } else { r -= 1; } }
        else { for( int j = 0; j < b; ++j ) { if( j > c ) { r += j; } else { r--; } } }
        while( r > c && r > b ) { r = r - 1; if( r % 3 == 0 ) { r += 2; } else { r -= 2; } }
        if( r < 0 ) { if( a > b ) { r = a; } else { r = b; } }
        if( r > 1000 ) { for( int k = 0; k < c; ++k ) { r -= k; } }
    }
    return r;
}
EOF
}

# ── (a) a HEAD with NO canonId symbols ─────────────────────────────────────────────────────────────────────
# A comment-only translation unit: the file IS indexed (so computeHeadSnapshot's own "HEAD ingested empty"
# degrade — which needs BOTH files and symbols empty — does not fire, and we reach computeDelta) but it
# defines zero canonId symbols, so the baseline Snapshot is WHOLLY empty. The oracle is available and says
# "nothing existed" — every finding is new. NB a markdown file does NOT work as a fixture here: headings
# become Section symbols and even a heading-free .md is enough to populate locBySym on some trees.
# MEASURED before/after on this exact fixture (r27):
#   pre-fix  exit 2, `<r kind="api-surface" ... surface="contract-change" gating="1"/>`  (a false gate)
#   post-fix exit 0, `<r kind="api-surface" ... origin="new-symbol" sev="minor"/>`
E="$WORK/emptyhead"; mkrepo "$E"
printf '// a translation unit with no symbols at all\n' > "$E/empty.cpp"
commit "$E" init
mkdir -p "$E/inc"
gnarly > "$E/inc/new.h"
OUT="$( cd "$E" && "$BIN" . --quality-delta --no-cache 2>"$WORK/e_err" )"; rce=$?
NROWS="$( printf '%s' "$OUT" | tr '<' '\n' | grep -c '^r kind=' )"
[ "$NROWS" -gt 0 ] && ok "empty-HEAD fixture reports $NROWS findings (non-vacuous)" \
                   || { no "empty-HEAD fixture reported nothing"; printf '%s\n' "$OUT" | head -c 400; }
NOTNEW="$( printf '%s' "$OUT" | tr '<' '\n' | grep '^r kind=' | grep -vc 'origin="new-symbol"' )"
{ [ "$rce" -eq 0 ] && [ "$NOTNEW" -eq 0 ]; } \
    && ok "HEAD with no indexable source: every finding is origin=\"new-symbol\", exit 0 (oracle is VALID, not missing)" \
    || { no "empty-HEAD misclassified: exit=$rce, $NOTNEW row(s) not new-symbol"; printf '%s' "$OUT" | tr '<' '\n' | grep '^r kind=' | grep -v 'origin="new-symbol"' | head -3; }
grep -q 'pre-Q1' "$WORK/e_err" \
    && { no "empty HEAD still alerts 'pre-Q1 format' — the wrong explanation for the right tree"; } \
    || ok "no false 'pre-Q1 format' alert on an empty HEAD"

# ── (b) a 0-byte sidecar is ABSENT, not 'an empty baseline' ────────────────────────────────────────────────
S="$WORK/zerosidecar"; mkrepo "$S"; mkdir -p "$S/inc"
printf 'int seed( int a );\n' > "$S/inc/api.h"
printf 'int seed( int a ) { return a + 1; }\n' > "$S/lib.cpp"
commit "$S" init
gnarly >> "$S/inc/api.h"
NOSIDE="$( cd "$S" && "$BIN" . --quality-delta --no-cache 2>/dev/null )"; rcn=$?
: > "$S/.ctxpack_quality_baseline"
ZERO="$( cd "$S" && "$BIN" . --quality-delta --no-cache 2>"$WORK/s_err" )"; rcz=$?
{ [ "$ZERO" = "$NOSIDE" ] && [ "$rcz" -eq "$rcn" ]; } \
    && ok "a 0-byte sidecar gives the SAME answer as no sidecar (treated as absent, exit $rcz)" \
    || { no "0-byte sidecar changed the answer (exit no-sidecar=$rcn zero=$rcz)"; printf '%s' "$ZERO" | tr '<' '\n' | grep '^quality-delta'; }
grep -q 'auto-comparing the working tree vs git HEAD' "$WORK/s_err" \
    && ok "the 0-byte sidecar falls back to the git-HEAD auto-baseline (stated on stderr)" \
    || { no "no git-HEAD fallback message for the 0-byte sidecar"; head -3 "$WORK/s_err"; }

# ── (c) a genuine pre-Q1 sidecar still fails CLOSED, for every kind ────────────────────────────────────────
( cd "$S" && git checkout -q -- . ) ; rm -f "$S/.ctxpack_quality_baseline"
( cd "$S" && "$BIN" . --quality-baseline --no-cache >/dev/null 2>&1 )
grep -v '^loc ' "$S/.ctxpack_quality_baseline" > "$WORK/preq1" && cp "$WORK/preq1" "$S/.ctxpack_quality_baseline"
gnarly >> "$S/inc/api.h"
cat >> "$S/lib.cpp" <<'EOF'
int copyA( int a ) { int q = 0; for( int i = 0; i < a; ++i ) { q += i * 7; } return q; }
int copyB( int a ) { int q = 0; for( int i = 0; i < a; ++i ) { q += i * 7; } return q; }
EOF
PQ="$( cd "$S" && "$BIN" . --quality-delta --no-cache 2>"$WORK/pq_err" )"; rcp=$?
PQNEW="$( printf '%s' "$PQ" | tr '<' '\n' | grep '^r kind=' | grep -c 'origin="new-symbol"' )"
{ [ "$PQNEW" -eq 0 ] && [ "$rcp" -eq 2 ]; } \
    && ok "pre-Q1 sidecar: NO row of any kind (clone kinds included) claims origin=\"new-symbol\" — fail-closed, exit 2" \
    || { no "pre-Q1 sidecar leaked $PQNEW new-symbol row(s) (exit=$rcp) — a kind disarmed the gate"; printf '%s' "$PQ" | tr '<' '\n' | grep 'origin="new-symbol"' | head -3; }
if "$BIN" --version 2>/dev/null >/dev/null && grep -q 'pre-Q1' "$WORK/pq_err"; then
    ok "pre-Q1 sidecar emits the degrade alert"
else
    echo "  SKIP  pre-Q1 degrade alert not observed (DEGRADED_PATH_ALERT is compiled out under NDEBUG)"
fi

# ── (d) all-new self-duplication with fan-in >= 3 is NOT 'new-clone-of-reused-helper' ──────────────────────
N="$WORK/allnew"; mkrepo "$N"
printf 'int anchor( int a ) { return a; }\n' > "$N/base.cpp"
commit "$N" init
cat > "$N/fresh.cpp" <<'EOF'
int freshHelper( int a ) { int q = 0; for( int i = 0; i < a; ++i ) { q += i * 11; } return q; }
int freshTwin( int a )   { int q = 0; for( int i = 0; i < a; ++i ) { q += i * 11; } return q; }
int useOne( int a )   { return freshHelper( a ) + 1; }
int useTwo( int a )   { return freshHelper( a ) + 2; }
int useThree( int a ) { return freshHelper( a ) + 3; }
int useFour( int a )  { return freshHelper( a ) + 4; }
EOF
AN="$( cd "$N" && "$BIN" . --quality-delta --no-cache 2>/dev/null )"
printf '%s' "$AN" | grep -q 'kind="duplication"' \
    && ok "all-new self-duplication IS reported as duplication (nothing lost)" \
    || { no "all-new duplication not reported at all — fixture vacuous"; printf '%s' "$AN" | tr '<' '\n' | grep '^r kind='; }
printf '%s' "$AN" | grep -q 'kind="new-clone-of-reused-helper"' \
    && { no "all-new code reported as new-clone-of-reused-helper — the 'reused helper is preexisting' claim is still unenforced"; printf '%s' "$AN" | tr '<' '\n' | grep 'reused-helper'; } \
    || ok "all-new self-duplication is NOT new-clone-of-reused-helper (claim now enforced)"

# ── (e) a clone of a genuinely PREEXISTING reused helper is still reported ─────────────────────────────────
P="$WORK/preexist"; mkrepo "$P"
cat > "$P/base.cpp" <<'EOF'
int sharedHelper( int a ) { int q = 0; for( int i = 0; i < a; ++i ) { q += i * 13; } return q; }
int callA( int a ) { return sharedHelper( a ) + 1; }
int callB( int a ) { return sharedHelper( a ) + 2; }
int callC( int a ) { return sharedHelper( a ) + 3; }
int callD( int a ) { return sharedHelper( a ) + 4; }
EOF
commit "$P" init
cat > "$P/copy.cpp" <<'EOF'
int reinvented( int a ) { int q = 0; for( int i = 0; i < a; ++i ) { q += i * 13; } return q; }
EOF
PE="$( cd "$P" && "$BIN" . --quality-delta --no-cache 2>/dev/null )"
printf '%s' "$PE" | grep -q 'kind="new-clone-of-reused-helper"' \
    && ok "a new clone of a PREEXISTING reused helper is still reported (the kind is narrowed, not emptied)" \
    || { no "the reuse-decline kind no longer fires on its own headline case"; printf '%s' "$PE" | tr '<' '\n' | grep '^r kind='; }

[ "$fail" -eq 0 ] && echo "qoriginoraclecheck: ALL PASS" || { echo "qoriginoraclecheck: SOME CHECKS FAILED"; exit 1; }
