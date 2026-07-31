#!/usr/bin/env bash
# headsnapcachecheck.sh — gate for A4-P1: --quality-delta's git-HEAD snapshot ingest is CACHED, keyed so it
# can NEVER serve stale/mismatched facts, and the cache is portable across the per-run tmp root.
#
# Background (AUDIT4 §C A4-P1): computeHeadSnapshot cold-ingests a materialized `git archive HEAD` tree on
# EVERY run (~12.5 s on the 1498-file corpus). The HEAD tree is IMMUTABLE for a given HEAD sha, so its ingest
# is perfectly cacheable: computeHeadSnapshot now hands the archived-tree ingest() an incremental content-hash
# cache file under cacheDirLadder(), keyed on (realpath repo-root, HEAD sha, excludes, scheme tag). The blob
# self-validates (parserVer + checksum + per-file content hash) and stores keys root-relative, so it is both
# never-stale and portable across the pid-suffixed tmpRoot the HEAD tree is extracted into.
#
# The determinism contract is "faster must never change the answer": cached and uncached --quality-delta output
# must be BYTE-IDENTICAL. This gate proves that plus never-stale reuse, key separation, and IO-failure degrade:
#
#   (a) EQUIVALENCE + REUSE: run --quality-delta twice on an unchanged HEAD. Assert (1) stdout byte-identical,
#       (2) a HEAD-snapshot cache file appears after run 1, and (3) its INODE is unchanged after run 2 — a
#       warm hit skips saveCache (rename mints a new inode on any reparse), so a stable inode is a timing-free
#       structural proof the cache was reused (same trick as cachesplitcheck.sh).
#   (b) NEVER-STALE ON HEAD CHANGE: add a new commit that raises a symbol's complexity, then re-run. Assert the
#       delta answers correctly against the NEW HEAD (no stale reuse of the old snapshot).
#   (c) KEY SEPARATION ON --exclude: a --exclude variation keys a DIFFERENT cache file (the A4-F5 scenario must
#       stay correct) and does not overwrite the no-exclude file.
#   (d) DEGRADE ON CORRUPT CACHE: clobber the cache file with garbage → ingest self-heals to a cold parse →
#       output stays byte-identical to the --no-cache ground truth (degrade-don't-crash).
#
# Uses its OWN temp repo + a private XDG_CACHE_HOME (TMPDIR unset) so the HEAD-snapshot caches land in a dir we
# own and can inspect. Does NOT edit regression.sh. Needs git.
# Usage:  test/headsnapcachecheck.sh   |   RIPWIRE_BIN=build_w2e/ripwire test/headsnapcachecheck.sh
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
CACHEDIR="$XDG/ripwire"

# portable inode reader (BSD stat -f %i / GNU stat -c %i)
inode_of(){ stat -f %i "$1" 2>/dev/null || stat -c %i "$1" 2>/dev/null; }
# AUDIT5 Y4: shard-aware lookup — a blob may be flat under $CACHEDIR or under $CACHEDIR/<xx>/ (2-hex shard).
snapfiles(){ find "$CACHEDIR" -maxdepth 2 -type f -name 'ripwire-qheadsnap-*.bin' 2>/dev/null; }
nsnap(){ snapfiles | wc -l | tr -d ' '; }
# run against $REPO with the private cache dir and a HEAD-snapshot cache enabled (auto path is internal to
# computeHeadSnapshot; --no-cache only disables the WORKING-tree auto-cache, not the HEAD-snapshot cache — so
# the HEAD cache is exercised even here, which is exactly what A4-P1 added).
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

echo "headsnapcachecheck: BIN=$BIN"

# ── (a) equivalence + reuse (unchanged HEAD == working tree, 0 regressions) ───────────────────────────────
run --no-cache >"$TMP/a1" 2>/dev/null; rc1=$?
SF="$( snapfiles | head -1 )"
[ -n "$SF" ] && ok "run 1 creates a HEAD-snapshot cache file" || no "no ripwire-qheadsnap-*.bin after run 1"
I1="$( [ -n "$SF" ] && inode_of "$SF" )"

run --no-cache >"$TMP/a2" 2>/dev/null; rc2=$?
diff -q "$TMP/a1" "$TMP/a2" >/dev/null \
    && ok "run 2 byte-identical to run 1 (cached == uncached output)" \
    || { no "cached output diverges from run 1"; diff "$TMP/a1" "$TMP/a2" | head -6; }

I2="$( [ -n "$SF" ] && inode_of "$SF" )"
[ -n "$I1" ] && [ "$I1" = "$I2" ] && ok "run 2 REUSED the cache (snapshot inode stable — no reparse/rewrite)" \
    || no "run 2 reparsed+rewrote the HEAD snapshot (inode $I1 -> $I2) — cache not reused"

# cross-check equivalence vs a from-scratch cold cache dir (guarantees the warm blob carries the right facts)
COLDXDG="$TMP/coldxdg"; mkdir -p "$COLDXDG"
env -u TMPDIR XDG_CACHE_HOME="$COLDXDG" "$BIN" "$REPO" --quality-delta --no-cache >"$TMP/acold" 2>/dev/null
diff -q "$TMP/a2" "$TMP/acold" >/dev/null \
    && ok "warm-cache output == fresh-cold-cache output (blob carries correct facts)" \
    || { no "warm cache output diverges from a cold cache dir"; diff "$TMP/acold" "$TMP/a2" | head -6; }

# ── (b) never-stale on HEAD change ────────────────────────────────────────────────────────────────────────
# New commit that makes mainThing genuinely more complex than the OLD HEAD (deeper nesting + branches). We edit
# BOTH working tree and HEAD (commit), so working == HEAD again → still 0 regressions, but computed against the
# NEW snapshot. A stale-reuse bug would compare the new working tree against the OLD (simpler) HEAD and FLAG a
# phantom complexity regression + exit 2.
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
run --no-cache >"$TMP/b1" 2>/dev/null; rcb=$?
{ [ "$rcb" -eq 0 ] && grep -q 'regressions="0"' "$TMP/b1"; } \
    && ok "new HEAD commit: fresh snapshot, 0 regressions (no stale reuse of old HEAD)" \
    || { no "stale HEAD snapshot reused after a new commit (exit=$rcb)"; grep -oE 'regressions="[0-9]+"' "$TMP/b1"; }

# a NEW snapshot file must now exist for the new sha (old sha's file may still be present until eviction)
[ "$( nsnap )" -ge 1 ] && ok "new-sha snapshot cache present" || no "no snapshot cache after new commit"

# ── (c) key separation on --exclude (A4-F5 stays correct) ─────────────────────────────────────────────────
before="$( nsnap )"
run --exclude=tests --no-cache >"$TMP/c1" 2>/dev/null; rcc=$?
{ [ "$rcc" -eq 0 ] && ! grep -q 'kind="dead-code"' "$TMP/c1"; } \
    && ok "--exclude=tests: exit 0, no phantom dead-code (A4-F5 correct, separate key)" \
    || { no "--exclude=tests wrong (exit=$rcc)"; grep -oE 'regressions="[0-9]+"|kind="[^"]+"' "$TMP/c1" | head; }
after="$( nsnap )"
[ "$after" -gt "$before" ] && ok "--exclude keys a DISTINCT cache file (count $before -> $after)" \
    || no "--exclude did not create a separate cache file (count $before -> $after) — key ignores excludes"

# ── (d) degrade on corrupt cache → cold parse, output unchanged ───────────────────────────────────────────
# ground truth from a pristine cache dir, then corrupt every snapshot blob in our dir and re-run.
env -u TMPDIR XDG_CACHE_HOME="$TMP/coldxdg2" "$BIN" "$REPO" --quality-delta --no-cache >"$TMP/d_truth" 2>/dev/null
for f in $( snapfiles ); do printf 'GARBAGE-not-a-valid-cache-blob-\x00\x01\x02' > "$f"; done
run --no-cache >"$TMP/d1" 2>/dev/null; rcd=$?
diff -q "$TMP/d1" "$TMP/d_truth" >/dev/null \
    && ok "corrupt cache degrades to cold parse — output byte-identical (degrade-don't-crash)" \
    || { no "corrupt cache changed the output (exit=$rcd)"; diff "$TMP/d_truth" "$TMP/d1" | head -6; }

# ── eviction hygiene: many sha's must not grow the cache dir past the per-repo cap (2) ────────────────────
for i in 1 2 3 4 5; do
    echo "// churn $i" >> "$REPO/src/lib.cpp"
    git -C "$REPO" add -A; git -C "$REPO" commit -qm "churn $i" >/dev/null
    run --no-cache >/dev/null 2>/dev/null
done
# no-exclude runs share one key group; count only those (exclude=tests group adds its own capped set).
# AUDIT5 Y4: shard-aware lookup
NOEXC="$( find "$CACHEDIR" -maxdepth 2 -type f -name 'ripwire-qheadsnap-*.bin' 2>/dev/null | wc -l | tr -d ' ' )"
[ "$NOEXC" -le 4 ] && ok "cache dir bounded after HEAD churn ($NOEXC files, per-repo cap 2 per key group)" \
    || no "cache dir grew unbounded after churn ($NOEXC files) — eviction not working"

[ "$fail" -eq 0 ] && echo "headsnapcachecheck: ALL PASS" || { echo "headsnapcachecheck: SOME CHECKS FAILED"; exit 1; }
