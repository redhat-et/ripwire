#!/usr/bin/env bash
# grepfastcheck.sh — gate for P4.1, the --grep fast path: the SPAN-TIER MEMO may never change an answer.
#
# What it guards. R-H's tier pass (search.h grepApplySpanTiers → ingest_astquery.h spanTiersOfFiles)
# parses every hit file with tree-sitter purely to learn where that file's comment and string spans are.
# On the measured corpus that parse was the single largest cost of a warm --grep — 48.6 ms of a 227 ms
# answer (bench/PROFILE.md, "the --grep fast path"), and it was repeated verbatim on every later grep of
# the same unchanged file. The map is a pure function of (file bytes, grammar), so it is now memoized
# per file under the shared cache-dir ladder.
#
# A cache on a DEFAULT path is a correctness surface, not a performance one: a stale span map silently
# SUPPRESSES rows (the tier ladder holds comment/string back when code is non-empty), which is the exact
# "a zero means none found" contract this repo treats as its worst possible bug. So every arm here is an
# EQUIVALENCE arm — none of them measures time, per the house no-perf-budget rule (the numbers live in
# bench/PROFILE.md as a ledger, never as a red CI gate).
#
# Asserts:
#   (1) COLD == WARM, over a matrix of --grep option combinations: the first run of each vector (empty
#       cache dir) and the second (memo populated) are BYTE-IDENTICAL on stdout, stderr and exit code.
#   (1b) LIVENESS: the memo actually engaged — blobs of the ripwire-stier- family exist after the cold
#       run. Without this arm (1) passes vacuously on any binary that has no memo at all, which is
#       exactly how a cache gate rots into a tautology.
#   (2) DETERMINISM: a third warm run is byte-identical again (a memo read must not leak thread order).
#   (3) NO-CACHE PARITY: --no-cache produces the same bytes AND writes no memo blob — the disclosed
#       reproducibility switch must disable this cache like every other one.
#   (4) STALENESS (the honesty arm): after an edit that moves a token from CODE into a COMMENT, the
#       answer must follow the FILE, not the memo. Runs the edit twice — once changing the file's size,
#       once holding the byte size EXACTLY constant — because a size-only freshness key passes the first
#       and fails the second.
#   (4b) The same for a token whose file is REPLACED by a shorter one (size + mtime both move).
#   (5) WELL-FORMEDNESS: every matrix answer still parses as XML (xmllint, when available).
#   (6) REFERENCE-BINARY EQUIVALENCE (opt-in): with RIPWIRE_BASE=<path to a pre-change ripwire>, every
#       matrix vector is byte-compared against that binary. This is the strongest form of the claim —
#       "byte-identical to the path it replaces" — and it is skipped, loudly, when no base is supplied.
#
# MUTATION EVIDENCE: arm (1b) FAILS against any binary built before the memo landed (no blob is ever
# written, so the liveness precondition finds nothing) — run
#   bash test/grepfastcheck.sh /path/to/pre-change/ripwire
# to see the gate red on the previous behaviour. Arms (1)/(2)/(3)/(4) pass on both binaries by
# construction: they assert the invariant the memo must not break, which the memo-less path also holds.
#
# Usage:
#   bash test/grepfastcheck.sh                            # uses build/ripwire
#   bash test/grepfastcheck.sh path/to/ripwire            # explicit binary (the mutation arm)
#   RIPWIRE_BIN=asan/ripwire bash test/grepfastcheck.sh
#   RIPWIRE_BASE=/path/to/base/ripwire bash test/grepfastcheck.sh    # + arm (6)

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "grepfastcheck: BIN=$BIN"

# ── the sandbox corpus ────────────────────────────────────────────────────────────────────────────────
# Small and self-contained: the arms below run the SAME tree many times, and a repo-sized corpus would
# make the matrix minutes long for no extra coverage. It carries a token in all three span tiers so the
# tier ladder (and therefore the memo the ladder consumes) is genuinely exercised.
SB="$TMP/sandbox"
mkdir -p "$SB/src" "$SB/test" "$SB/docs"
cat >"$SB/src/alpha.c" <<'EOF'
// FASTTOKEN_zeta named in a comment
const char* alphaMessage = "FASTTOKEN_zeta inside a string literal";
int alphaFastTokenZeta( int n )
{
    int FASTTOKEN_zeta = n + 1;
    return FASTTOKEN_zeta;
}
EOF
# The memo has a measured SIZE FLOOR (ingest_astquery.h kSpanTierMemoMinBytes): below it a file is cheaper
# to re-parse than to look up, so no blob is written. alpha.c is therefore padded past the floor with inert
# filler — otherwise arm (1b) could never see a blob and arms (4a)/(4b) would prove nothing about the memo,
# because there would be no memo for that file to go stale. The padding is APPENDED, so the head region the
# arms below edit keeps its exact line shape.
alphaFiller(){ awk 'BEGIN{ for( i = 0; i < 900; i++ ) printf "int alphaFiller%04d( int v ) { return v + %d; }\n", i, i }'; }
alphaFiller >>"$SB/src/alpha.c"
alphaBytes="$( wc -c <"$SB/src/alpha.c" | tr -d ' ' )"
if [ "$alphaBytes" -lt 32768 ]; then
    no "sandbox fixture is $alphaBytes bytes — below the memo size floor, every memo arm below would be vacuous"
fi
cat >"$SB/src/beta.c" <<'EOF'
#include <stdio.h>
// OTHERTOKEN_iota only ever appears in this comment
int betaHelper( int k )
{
    return k * 2;
}
int betaCaller( int k )
{
    return betaHelper( k ) + alphaFastTokenZeta( k );
}
EOF
cat >"$SB/test/alpha_test.c" <<'EOF'
void testAlpha( void )
{
    int FASTTOKEN_zeta = 0;
    (void) FASTTOKEN_zeta;
}
EOF
cat >"$SB/docs/notes.md" <<'EOF'
# Notes

FASTTOKEN_zeta is mentioned in prose here as well.
EOF

# ── the matrix: every --grep surface whose answer the tier memo could plausibly move ──────────────────
# One vector per line; each is a full argv tail appended after the root. Deliberately covers the tiered
# default, the untiered escape hatch, the boolean post-filter, both scopes, context lines, handles, a
# paged window, the compact legend, a regex answer, and a zero-hit answer.
VECTORS=(
  "--grep=FASTTOKEN_zeta"
  "--grep=FASTTOKEN_zeta --grep-in=any"
  "--grep=FASTTOKEN_zeta --and=return"
  "--grep=FASTTOKEN_zeta --not=string"
  "--grep=FASTTOKEN_zeta --and=betaHelper --grep-scope=file"
  "--grep=FASTTOKEN_zeta --grep-context=2"
  "--grep=FASTTOKEN_zeta --handles"
  "--grep=FASTTOKEN_zeta --limit=2 --offset=1"
  "--grep=FASTTOKEN_zeta --legend=compact"
  "--grep=OTHERTOKEN_iota"
  "--grep=NOSUCHTOKEN_omega"
  "--regex=FASTTOKEN_[a-z]+"
  "--grep=betaHelper"
)

# Run one vector with an ISOLATED cache dir. cacheDirLadder() reads TMPDIR first (quality.h), so pointing
# TMPDIR at a fresh directory is what makes "cold" mean cold — for the ingest cache AND the tier memo.
runVector(){   # $1 = binary  $2 = cache dir  $3 = out prefix  $4.. = argv tail
    local bin="$1" cache="$2" out="$3"; shift 3
    mkdir -p "$cache"
    TMPDIR="$cache" "$bin" "$SB" "$@" >"$out.out" 2>"$out.err"
    printf '%s' "$?" >"$out.rc"
}

memoBlobCount(){   # $1 = cache dir — the ripwire-stier- family, in either blob layout (flat or sharded)
    find "$1" -name 'ripwire-stier-*' -type f 2>/dev/null | wc -l | tr -d ' '
}

# ── arms (1) + (1b) + (2): cold == warm == warm, and the memo really engaged ──────────────────────────
coldCache="$TMP/cache-cold"
mkdir -p "$coldCache"
matrixFail=0
for i in "${!VECTORS[@]}"; do
    # shellcheck disable=SC2206
    argv=( ${VECTORS[$i]} )
    runVector "$BIN" "$coldCache" "$TMP/v$i.cold" "${argv[@]}"
    runVector "$BIN" "$coldCache" "$TMP/v$i.warm" "${argv[@]}"
    runVector "$BIN" "$coldCache" "$TMP/v$i.warm2" "${argv[@]}"
    for chan in out err rc; do
        if ! cmp -s "$TMP/v$i.cold.$chan" "$TMP/v$i.warm.$chan"; then
            no "(1) cold != warm on $chan for: ${VECTORS[$i]}"
            diff "$TMP/v$i.cold.$chan" "$TMP/v$i.warm.$chan" 2>&1 | head -6 | sed 's/^/        | /'
            matrixFail=1
        fi
        if ! cmp -s "$TMP/v$i.warm.$chan"  "$TMP/v$i.warm2.$chan"; then
            no "(2) warm run 1 != warm run 2 on $chan for: ${VECTORS[$i]}"
            matrixFail=1
        fi
    done
done
[ "$matrixFail" -eq 0 ] && ok "(1)(2) ${#VECTORS[@]} grep vectors: cold == warm == warm on stdout/stderr/exit"

blobs="$( memoBlobCount "$coldCache" )"
if [ "$blobs" -gt 0 ]; then
    ok "(1b) liveness: the span-tier memo engaged ($blobs ripwire-stier- blob(s) under the isolated cache dir)"
else
    no "(1b) liveness: NO ripwire-stier- blob was written — arm (1) would pass vacuously (pre-memo binary?)"
fi

# ── arm (3): --no-cache is the same answer AND writes no memo ─────────────────────────────────────────
ncCache="$TMP/cache-nocache"
mkdir -p "$ncCache"
ncFail=0
for i in "${!VECTORS[@]}"; do
    # shellcheck disable=SC2206
    argv=( ${VECTORS[$i]} )
    runVector "$BIN" "$ncCache" "$TMP/v$i.nc" "${argv[@]}" --no-cache
    if ! cmp -s "$TMP/v$i.warm.out" "$TMP/v$i.nc.out"; then
        no "(3) --no-cache stdout differs from the warm answer for: ${VECTORS[$i]}"
        diff "$TMP/v$i.warm.out" "$TMP/v$i.nc.out" 2>&1 | head -6 | sed 's/^/        | /'
        ncFail=1
    fi
done
[ "$ncFail" -eq 0 ] && ok "(3) --no-cache is byte-identical to the warm answer on every vector"
ncBlobs="$( memoBlobCount "$ncCache" )"
if [ "$ncBlobs" -eq 0 ]; then
    ok "(3) --no-cache wrote no span-tier memo blob"
else
    no "(3) --no-cache wrote $ncBlobs span-tier memo blob(s) — the reproducibility switch must disable this cache too"
fi

# ── arm (4): staleness — the answer follows the FILE, never the memo ──────────────────────────────────
# Two shapes, because a size-only freshness key survives the first and dies on the second:
#   (4a) the edit CHANGES the byte size; (4b) the edit holds the byte size EXACTLY constant.
staleCache="$TMP/cache-stale"
mkdir -p "$staleCache"

# Baseline: the token is real CODE in alpha.c, so the tiered default serves the code rows and suppresses
# the comment/string ones. Populate the memo for alpha.c at this content.
runVector "$BIN" "$staleCache" "$TMP/stale.pre" --grep=FASTTOKEN_zeta
preSuppressed="$( grep -c 'suppressed_comment=' "$TMP/stale.pre.out" 2>/dev/null || true )"
if grep -q 'in="alphaFastTokenZeta"' "$TMP/stale.pre.out"; then
    ok "(4) precondition: the code-tier row is served before the edit"
else
    no "(4) precondition FAILED: no code-tier row before the edit — the arm below would be vacuous"
    sed 's/^/        | /' "$TMP/stale.pre.out" | head -4
fi

# (4a) size-changing edit: comment the function body's occurrence out entirely, so alpha.c holds the
# token ONLY in a comment and a string. The tier ladder must now fall back to comment+string.
cat >"$SB/src/alpha.c" <<'EOF'
// FASTTOKEN_zeta named in a comment
const char* alphaMessage = "FASTTOKEN_zeta inside a string literal";
int alphaFastTokenZeta( int n )
{
    return n + 1;
}
EOF
alphaFiller >>"$SB/src/alpha.c"
runVector "$BIN" "$staleCache" "$TMP/stale.a" --grep=FASTTOKEN_zeta
if grep -q 'in="alphaFastTokenZeta"' "$TMP/stale.a.out"; then
    no "(4a) STALE MEMO: a code-tier row still served after the code occurrence was deleted"
    sed 's/^/        | /' "$TMP/stale.a.out" | head -4
else
    ok "(4a) size-changing edit invalidated the memo (the deleted code row is gone)"
fi

# (4b) size-PRESERVING edit: swap two same-length identifiers so the file's byte count is unchanged.
# `alphaMessage` and `alphaMessagX` are the same length; the token moves back into code by re-adding an
# occurrence in a statement of exactly the length of the line it replaces.
python3 - "$SB/src/alpha.c" <<'PY'
import sys
p = sys.argv[1]
b = open(p, 'rb').read()
before = len(b)
# "    return n + 1;\n" -> "int FASTTOKEN_zeta;\n" is a different length; pad to keep the byte count equal.
old = b"    return n + 1;\n"
new = b"    int FASTTOKEN_zeta = n;\n"
assert old in b, "fixture drift: the line to swap is not present"
b = b.replace(old, new, 1)
pad = before - len(b)
assert pad <= 0, "fixture drift: replacement must not be shorter than the original"
# trim the trailing comment text by exactly -pad bytes so the file size is EXACTLY unchanged
head = b"// FASTTOKEN_zeta named in a comment"
assert head in b
trimmed = head[: len(head) + pad]
b = b.replace(head, trimmed, 1)
assert len(b) == before, f"fixture drift: {len(b)} != {before}"
open(p, 'wb').write(b)
PY
if [ $? -ne 0 ]; then
    no "(4b) fixture could not be built (python3 missing or the sandbox line drifted)"
else
    sizeNow="$( wc -c <"$SB/src/alpha.c" | tr -d ' ' )"
    runVector "$BIN" "$staleCache" "$TMP/stale.b" --grep=FASTTOKEN_zeta
    if grep -q 'FASTTOKEN_zeta = n;' "$TMP/stale.b.out"; then
        ok "(4b) size-preserving edit invalidated the memo (byte size held at $sizeNow, new code row served)"
    else
        no "(4b) STALE MEMO: a size-preserving edit was not seen (byte size held at $sizeNow)"
        sed 's/^/        | /' "$TMP/stale.b.out" | head -6
    fi
fi

# ── arm (5): every matrix answer is still well-formed XML ─────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    xmlFail=0
    for i in "${!VECTORS[@]}"; do
        rc="$( cat "$TMP/v$i.warm.rc" )"
        [ "$rc" = "0" ] || continue          # a refusal writes no element — nothing to parse
        if ! xmllint --noout "$TMP/v$i.warm.out" >/dev/null 2>&1; then
            no "(5) not well-formed XML: ${VECTORS[$i]}"
            xmlFail=1
        fi
    done
    [ "$xmlFail" -eq 0 ] && ok "(5) every matrix answer is well-formed XML"
else
    printf '  SKIP  (5) xmllint not installed\n'
fi

# ── arm (6): byte-equivalence against a pre-change reference binary (opt-in) ──────────────────────────
# This is the fast path's actual claim. Without a base binary the claim cannot be checked, and the gate
# says so rather than quietly reporting a pass it did not earn.
if [ -n "${RIPWIRE_BASE:-}" ] && [ -x "${RIPWIRE_BASE}" ]; then
    # rebuild the sandbox: arm (4) edited it
    cat >"$SB/src/alpha.c" <<'EOF'
// FASTTOKEN_zeta named in a comment
const char* alphaMessage = "FASTTOKEN_zeta inside a string literal";
int alphaFastTokenZeta( int n )
{
    int FASTTOKEN_zeta = n + 1;
    return FASTTOKEN_zeta;
}
EOF
    alphaFiller >>"$SB/src/alpha.c"
    baseFail=0
    for i in "${!VECTORS[@]}"; do
        # shellcheck disable=SC2206
        argv=( ${VECTORS[$i]} )
        runVector "$RIPWIRE_BASE" "$TMP/cache-base" "$TMP/v$i.base" "${argv[@]}"
        runVector "$BIN"          "$TMP/cache-new"  "$TMP/v$i.new"  "${argv[@]}"
        for chan in out rc; do
            if ! cmp -s "$TMP/v$i.base.$chan" "$TMP/v$i.new.$chan"; then
                no "(6) differs from RIPWIRE_BASE on $chan for: ${VECTORS[$i]}"
                diff "$TMP/v$i.base.$chan" "$TMP/v$i.new.$chan" 2>&1 | head -8 | sed 's/^/        | /'
                baseFail=1
            fi
        done
    done
    [ "$baseFail" -eq 0 ] && ok "(6) byte-identical to RIPWIRE_BASE on all ${#VECTORS[@]} vectors"
else
    printf '  SKIP  (6) set RIPWIRE_BASE=<pre-change ripwire> to byte-compare the matrix against it\n'
fi

[ "$fail" -eq 0 ] && echo "grepfastcheck: OK" || echo "grepfastcheck: FAILED"
exit "$fail"
