#!/usr/bin/env bash
# qdtype3oncecheck.sh — QD-ENVOY-TIME cost bound: one `--quality-delta` call runs the Type-3 clone pass ONCE.
#
# THE DEFECT (Fable answer audit 2026-11-11, QD-ENVOY-TIME). On a tree whose tracked files match HEAD the
# identity basis (quality.h computeHeadBasis) takes the HEAD snapshot from the working tree's own ingest, and
# computeDelta then judges that SAME ingest. findClones, findClonesType3 and the construct re-parse are pure
# functions of it, yet each ran twice: envoy spent two thirds of a 123 s call in two identical Type-3 passes and
# timed out at 120 s. quality::TreePasses now computes them once per call and hands the value to every reader.
#
# THE ARMS (each reads the count off the RIPWIRE_STATS line `ripwire: quality-passes type3_runs=N type3_pairs=P`):
#   P   PREMISE — the fixture really holds a near-clone pair: type3_pairs >= 1 on every arm below, and the arm
#       FAILS on zero (a pass that found nothing proves nothing about how often it ran).
#   C1  CLEAN TREE (identity basis, head_basis="identity" on the root): type3_runs == 1. Red before the fix (2).
#   M1  MODIFIED TREE (archived-HEAD basis, no head_basis=): the first call ingests the archived HEAD as well,
#       so it may run the pass twice; the SECOND call is served the HEAD side from the qsnap cache and must
#       run it exactly once. The premise also requires the cache to have answered: if the second call still
#       runs it twice, the arm fails rather than excusing it.
#   D   DETERMINISM — two clean-tree calls are byte-identical (stdout + stderr + rc).
#
# Counts are deterministic: the pass is a pure function and the counter is incremented once per pass, whatever
# the thread count. Wall time is never asserted.
#
# Usage:  bash test/qdtype3oncecheck.sh [BIN]   |   RIPWIRE_BIN=build/ripwire bash test/qdtype3oncecheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }
echo "qdtype3oncecheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"; mkdir -p "$REPO/src" "$TMP/home" "$TMP/cache"
export HOME="$TMP/home" XDG_CACHE_HOME="$TMP/cache"

# Two near-copies (one statement differs, one renamed local) — a Type-3 pair, not an exact Type-1/2 group.
cat > "$REPO/src/near.c" <<'EOF'
int sum_positive( const int* values, int count, int limit )
{
    int total = 0;
    for( int i = 0; i < count; ++i )
    {
        if( values[i] > 0 && values[i] < limit )
        {
            total += values[i];
        }
        else if( values[i] == limit )
        {
            total += limit / 2;
        }
    }
    return total;
}

int sum_positive_scaled( const int* values, int count, int limit )
{
    int acc = 0;
    for( int i = 0; i < count; ++i )
    {
        if( values[i] > 0 && values[i] < limit )
        {
            acc += values[i] * 3;
        }
        else if( values[i] == limit )
        {
            acc += limit / 2;
        }
    }
    return acc;
}
EOF
cat > "$REPO/src/other.c" <<'EOF'
int other_helper( int x )
{
    return x + 1;
}
EOF
git -C "$REPO" init -q && git -C "$REPO" add -A \
  && git -C "$REPO" -c user.name=t -c user.email=t@t commit -qm seed || { echo "git fixture failed"; exit 2; }

# run_qd TAG — one --quality-delta call; out/err/rc land in $TMP/TAG.{out,err,rc}
run_qd(){
    ( cd "$REPO" && RIPWIRE_STATS=1 "$BIN" . --quality-delta --legend=compact > "$TMP/$1.out" 2> "$TMP/$1.err" ); echo $? > "$TMP/$1.rc"
}
field(){ sed -n "s/.*ripwire: quality-passes .*$2=\([0-9][0-9]*\).*/\1/p" "$TMP/$1.err" | tail -1; }
check_arm(){   # TAG NAME
    local runs pairs; runs="$( field "$1" type3_runs )"; pairs="$( field "$1" type3_pairs )"
    if [ -z "$runs" ] || [ -z "$pairs" ]; then
        no "$2: no 'quality-passes' stats line on stderr (rc=$( cat "$TMP/$1.rc" ))"; sed 's/^/    /' "$TMP/$1.err" | head -5; return
    fi
    if [ "$pairs" -lt 1 ]; then no "$2: premise — the fixture's near-clone pair was not seen (type3_pairs=$pairs)"; return; fi
    ok "$2: premise — type3_pairs=$pairs (the near-clone pair is in the pass)"
    if [ "$runs" = 1 ]; then ok "$2: type3_runs=1"; else no "$2: type3_runs=$runs (want 1 — the Type-3 pass ran more than once on one call)"; fi
}

# ── C1: clean tree, identity basis ──────────────────────────────────────────────────────────────────────────
run_qd clean
if grep -q 'head_basis="identity"' "$TMP/clean.out"; then ok "C1: premise — head_basis=\"identity\" on the root"; else no "C1: premise — the clean tree did not take the identity basis"; fi
check_arm clean C1

# ── D: determinism, clean tree ──────────────────────────────────────────────────────────────────────────────
run_qd clean2
# RIPWIRE_STATS=1 also prints the MEM-STATS `[mem] phase=… cur_mib=… peak_mib=…` lines (#617). Those are a live heap reading: they
# differ between two identical calls by design, and the phase list depends on whether a cache save ran. So D compares stderr
# WITHOUT them. Premise: both calls must print at least one non-[mem] stats line, or the stderr compare would be vacuous.
nomem(){ grep -v '^\[mem\] ' "$TMP/$1.err" > "$TMP/$1.err.nomem" || true; }
nomem clean; nomem clean2
if [ ! -s "$TMP/clean.err.nomem" ] || [ ! -s "$TMP/clean2.err.nomem" ]; then
    no "D: premise — a clean-tree call printed no stats line outside [mem] (the stderr compare would be vacuous)"
elif cmp -s "$TMP/clean.out" "$TMP/clean2.out" && cmp -s "$TMP/clean.err.nomem" "$TMP/clean2.err.nomem" && cmp -s "$TMP/clean.rc" "$TMP/clean2.rc"; then
    ok "D: two clean-tree calls byte-identical (stdout + stderr outside [mem] + rc)"
else
    no "D: two clean-tree calls differ"
fi

# ── M1: one edited tracked file, archived-HEAD basis; the second call reads the HEAD side from the cache ────
printf 'int other_helper2( int y )\n{\n    return y * 2;\n}\n' >> "$REPO/src/other.c"
run_qd mod1
# each modified-tree call must answer (rc 0, a non-empty <qd> answer) before its output is read (CodeRabbit 4542253228): an
# empty mod1.out would pass the absence check below, and a failing mod2 that still printed its stats line would pass M1
modok(){ [ "$( cat "$TMP/$1.rc" )" = 0 ] && grep -q '<quality-delta' "$TMP/$1.out"; }
if ! modok mod1; then no "M1: the first modified-tree call exited $( cat "$TMP/mod1.rc" ) with $( wc -c < "$TMP/mod1.out" | tr -d ' ' ) B of answer (want rc 0 and a <quality-delta> answer)"
elif grep -q 'head_basis=' "$TMP/mod1.out"; then no "M1: premise — a modified tree still carried head_basis= (expected the archived basis)"; else ok "M1: premise — archived-HEAD basis (no head_basis=)"; fi
run_qd mod2
if modok mod2; then check_arm mod2 M1; else no "M1: the second modified-tree call exited $( cat "$TMP/mod2.rc" ) with $( wc -c < "$TMP/mod2.out" | tr -d ' ' ) B of answer (want rc 0 and a <quality-delta> answer)"; fi

if [ "$fail" -ne 0 ]; then echo "qdtype3oncecheck: FAIL"; exit 1; fi
echo "qdtype3oncecheck: OK"
exit 0
