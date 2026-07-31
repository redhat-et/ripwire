#!/usr/bin/env bash
# qsnapcachecheck.sh — gate for A4-P1 (round 2): --quality-delta's computed git-HEAD *Snapshot* is cached, so a
# warm run skips git archive + ingest + buildGraph + BOTH clone passes entirely (the ~2.4 s the ingest-only
# cache could not save). Determinism contract: "faster must never change the answer" — cached and uncached
# --quality-delta output must be BYTE-IDENTICAL.
#
# Background (AUDIT4 §G PARTIAL / A4-P1): computeHeadSnapshot already caches the HEAD *ingest*. The dominant
# remaining cost is everything computeSnapshot then does on the HEAD tree — above all findClones +
# findClonesType3 — all IMMUTABLE for a given (HEAD sha, excludes, scheme). This round serializes the computed
# Snapshot to a sidecar blob (ctxpack-qsnap-<repoHex>-<exclHex>-<sha>.bin) with a magic+scheme header, an
# embedded fnv(headSha), and an fnv1a64 checksum trailer; a warm hit deserializes it and RETURNS.
#
# Checks:
#   (a) EQUIVALENCE + REUSE: two identical --quality-delta runs → byte-identical stdout, a qsnap blob appears
#       after run 1, and its INODE is unchanged after run 2 (a hit re-reads the blob; a miss would rewrite → new
#       inode). The stable inode is a timing-free structural proof the heavy path was skipped.
#   (b) BLOB-CARRIES-FACTS EQUIVALENCE: delete the qsnap blob, run again → byte-identical to the cached run (the
#       restored Snapshot makes computeDelta produce identical output vs a freshly-computed one).
#   (c) NEVER-STALE ON HEAD CHANGE: a new commit that raises complexity → a FRESH snapshot, correct new answer
#       (a regression introduced in the fixture is reported identically cached vs uncached).
#   (d) KEY SEPARATION ON --exclude: a --exclude variant keys a DISTINCT qsnap blob (qualityexcludecheck stays
#       green; the A4-F5 scenario stays correct).
#   (e) DEGRADE ON CORRUPT BLOB: clobber the qsnap blob with garbage → an alert to stderr + output byte-identical
#       to the pristine-cache ground truth (corrupt-but-present → alert + recompute, never wrong/crash).
#
# Uses its OWN temp repo + a private XDG_CACHE_HOME (TMPDIR unset) so the qsnap blobs land in a dir we own and
# can inspect. Does NOT edit regression.sh. Needs git.
# Usage:  test/qsnapcachecheck.sh   |   CTXPACK_BIN=build_r2a1/ctxpack test/qsnapcachecheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ echo "  PASS  $1"; }
no(){ echo "  FAIL  $1"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }

REPO="$( mktemp -d )"; TMP="$( mktemp -d )"; trap 'rm -rf "$REPO" "$TMP"' EXIT
XDG="$TMP/xdg"; mkdir -p "$XDG"
CACHEDIR="$XDG/ctxpack"

inode_of(){ stat -f %i "$1" 2>/dev/null || stat -c %i "$1" 2>/dev/null; }
# AUDIT5 Y4: shard-aware lookup — a blob may be flat under $CACHEDIR or under $CACHEDIR/<xx>/ (2-hex shard).
qsnapfiles(){ find "$CACHEDIR" -maxdepth 2 -type f -name 'ctxpack-qsnap-*.bin' 2>/dev/null; }
nqsnap(){ qsnapfiles | wc -l | tr -d ' '; }
# --no-cache disables only the WORKING-tree auto-cache, never the HEAD-side qsnap cache — so the qsnap path is
# exercised here, which is exactly what this gate needs.
run(){ env -u TMPDIR XDG_CACHE_HOME="$XDG" "$BIN" "$REPO" --quality-delta "$@"; }

mkdir -p "$REPO/src" "$REPO/tests"
cat > "$REPO/src/lib.cpp" <<'EOF'
int helper( int x ) { int s = 0; for( int i = 0; i < x; ++i ) { s += i * 2; } return s; }
int mainThing( int y ) { int t = y; while( t > 1 ) { t = t - 1; } return t; }
EOF
cat > "$REPO/tests/test_lib.cpp" <<'EOF'
extern int helper( int x );
int runTest() { return helper( 5 ) + 1; }
EOF
git -C "$REPO" init -q; git -C "$REPO" config user.email x@y; git -C "$REPO" config user.name x
git -C "$REPO" add -A; git -C "$REPO" commit -qm init

echo "qsnapcachecheck: BIN=$BIN"

# ── (a) equivalence + reuse (unchanged HEAD == working tree, 0 regressions) ────────────────────────────────
run --no-cache >"$TMP/a1" 2>/dev/null; rc1=$?
QF="$( qsnapfiles | head -1 )"
[ -n "$QF" ] && ok "run 1 creates a qsnap Snapshot cache file" || no "no ctxpack-qsnap-*.bin after run 1"
I1="$( [ -n "$QF" ] && inode_of "$QF" )"

run --no-cache >"$TMP/a2" 2>/dev/null; rc2=$?
diff -q "$TMP/a1" "$TMP/a2" >/dev/null \
    && ok "run 2 byte-identical to run 1 (cached == uncached output)" \
    || { no "cached output diverges from run 1"; diff "$TMP/a1" "$TMP/a2" | head -6; }

I2="$( [ -n "$QF" ] && inode_of "$QF" )"
[ -n "$I1" ] && [ "$I1" = "$I2" ] && ok "run 2 REUSED the qsnap blob (inode stable — heavy path skipped)" \
    || no "run 2 rewrote the qsnap blob (inode $I1 -> $I2) — cache not reused"

# ── (b) blob-carries-facts equivalence: delete the blob, recompute, must match the cached run byte-for-byte ─
rm -f $( qsnapfiles )
run --no-cache >"$TMP/b1" 2>/dev/null
diff -q "$TMP/a2" "$TMP/b1" >/dev/null \
    && ok "deleted-blob recompute == cached output (restored Snapshot ≡ fresh Snapshot)" \
    || { no "recompute after blob delete diverges from cached run"; diff "$TMP/a2" "$TMP/b1" | head -6; }

# ── (c) never-stale on HEAD change + a real, correctly-reported regression ─────────────────────────────────
# Working tree stays == HEAD (both edited + committed), but mainThing grows genuinely more complex than the OLD
# HEAD. A stale qsnap-reuse bug would compare the new working tree against the OLD (simpler) cached Snapshot and
# FLAG a phantom complexity regression + exit 2. Correct: fresh snapshot → still 0 regressions.
cat > "$REPO/src/lib.cpp" <<'EOF'
int helper( int x ) { int s = 0; for( int i = 0; i < x; ++i ) { s += i * 2; } return s; }
int mainThing( int y ) {
    int t = y;
    for( int i = 0; i < y; ++i ) {
        if( i % 2 == 0 ) { if( t > i ) { t -= i; } else { t += 1; } }
        else { while( t > 1 && t > i ) { t = t - 1; } }
    }
    return t;
}
EOF
git -C "$REPO" add -A; git -C "$REPO" commit -qm "grow mainThing" >/dev/null
run --no-cache >"$TMP/c1" 2>/dev/null; rcc=$?
{ [ "$rcc" -eq 0 ] && grep -q 'regressions="0"' "$TMP/c1"; } \
    && ok "new HEAD commit: fresh qsnap Snapshot, 0 regressions (no stale reuse of old HEAD)" \
    || { no "stale qsnap Snapshot reused after a new commit (exit=$rcc)"; grep -oE 'regressions="[0-9]+"' "$TMP/c1"; }

# Now introduce a REAL regression in the WORKING TREE only (uncommitted): a brand-new large, complex function.
# It must be reported identically whether the HEAD Snapshot came from cache (warm run) or was recomputed
# (deleted-blob run) — equivalence under a non-empty regression set.
cat >> "$REPO/src/lib.cpp" <<'EOF'
int addedComplex( int a, int b, int c ) {
    int r = 0;
    for( int i = 0; i < a; ++i ) {
        if( i % 2 == 0 ) { if( i > b ) { r += i; } else { r -= 1; } }
        else { for( int j = 0; j < b; ++j ) { if( j > c ) { r += j; } else { r--; } } }
        while( r > c && r > b ) { r = r - 1; if( r % 3 == 0 ) { r += 2; } }
    }
    return r;
}
EOF
run --no-cache >"$TMP/c_warm" 2>/dev/null; rcw=$?     # HEAD Snapshot served from the qsnap cache
rm -f $( qsnapfiles )
run --no-cache >"$TMP/c_cold" 2>/dev/null; rccold=$?  # HEAD Snapshot recomputed from scratch
diff -q "$TMP/c_warm" "$TMP/c_cold" >/dev/null \
    && ok "introduced regression reported byte-identically cached vs uncached" \
    || { no "regression report differs cached vs uncached (exit warm=$rcw cold=$rccold)"; diff "$TMP/c_warm" "$TMP/c_cold" | head -8; }
grep -q 'kind="complexity"' "$TMP/c_warm" \
    && ok "the introduced complexity regression is actually reported (non-vacuous)" \
    || no "introduced regression not reported — fixture is vacuous"

# ── (d) key separation on --exclude (A4-F5 stays correct, distinct qsnap key) ──────────────────────────────
# revert to the clean committed tree (working == HEAD) so the exclude scenario is the untouched-tree A4-F5 case.
git -C "$REPO" checkout -q -- src/lib.cpp
before="$( nqsnap )"
run --exclude=tests --no-cache >"$TMP/d1" 2>/dev/null; rcd=$?
{ [ "$rcd" -eq 0 ] && ! grep -q 'kind="dead-code"' "$TMP/d1"; } \
    && ok "--exclude=tests: exit 0, no phantom dead-code (A4-F5 correct, separate qsnap key)" \
    || { no "--exclude=tests wrong (exit=$rcd)"; grep -oE 'regressions="[0-9]+"|kind="[^"]+"' "$TMP/d1" | head; }
after="$( nqsnap )"
[ "$after" -gt "$before" ] && ok "--exclude keys a DISTINCT qsnap blob (count $before -> $after)" \
    || no "--exclude did not create a separate qsnap blob (count $before -> $after) — key ignores excludes"

# ── (e) degrade on corrupt qsnap blob → alert on stderr + correct output ───────────────────────────────────
# ground truth from a pristine private cache dir, then corrupt every qsnap blob in our dir and re-run.
env -u TMPDIR XDG_CACHE_HOME="$TMP/coldxdg" "$BIN" "$REPO" --quality-delta --no-cache >"$TMP/e_truth" 2>/dev/null
for f in $( qsnapfiles ); do printf 'QSNP\xff\xff\xff\xffGARBAGE-not-a-valid-snapshot-blob\x00\x01\x02' > "$f"; done
run --no-cache >"$TMP/e1" 2>"$TMP/e_err"; rce=$?
diff -q "$TMP/e1" "$TMP/e_truth" >/dev/null \
    && ok "corrupt qsnap blob degrades to recompute — output byte-identical (degrade-don't-crash)" \
    || { no "corrupt qsnap blob changed the output (exit=$rce)"; diff "$TMP/e_truth" "$TMP/e1" | head -6; }
grep -qi 'Snapshot cache corrupt' "$TMP/e_err" \
    && ok "corrupt qsnap blob emits a DEGRADED alert to stderr" \
    || { no "no corrupt-blob alert on stderr"; head -3 "$TMP/e_err"; }

# ── eviction hygiene: many sha's must not grow the qsnap family past the per-(repo,excl) cap (2) ───────────
for i in 1 2 3 4 5; do
    echo "// churn $i" >> "$REPO/src/lib.cpp"
    git -C "$REPO" add -A; git -C "$REPO" commit -qm "churn $i" >/dev/null
    run --no-cache >/dev/null 2>/dev/null
done
# count the no-exclude qsnap family only (the --exclude=tests run above seeded its own capped family).
NOEXC="$( qsnapfiles | wc -l | tr -d ' ' )"
[ "$NOEXC" -le 4 ] && ok "qsnap dir bounded after HEAD churn ($NOEXC files, cap 2 per key group)" \
    || no "qsnap dir grew unbounded after churn ($NOEXC files) — eviction not working"

[ "$fail" -eq 0 ] && echo "qsnapcachecheck: ALL PASS" || { echo "qsnapcachecheck: SOME CHECKS FAILED"; exit 1; }
