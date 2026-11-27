#!/usr/bin/env bash
# nocacheevictcheck.sh — a --no-cache run never deletes another root's cache blob.
#
# The defect (2026-11-26, seen on zed): `--no-cache` printed "over its 2048 MiB budget — evicted 19 blob(s) of other
# roots". --no-cache turns off the working-tree parse cache, but a verb that materializes a commit tree still hands that
# tree's ingest the qheadsnap/qms cache (the HEAD-side families are written under --no-cache on purpose: see
# test/qsnapcachecheck.sh and test/headsnapcachecheck.sh). That ingest's saveCache ran the dir-wide hygiene sweep
# (quality.h sweepStaleCacheBlobsOnce): the 30-day age pass and the 2 GiB byte-budget pass over EVERY root's blobs. So a
# gate or an agent that asked for no cache turned other projects' warm caches cold.
#
# The contract this gate pins: a --no-cache process runs no dir-wide sweep, so every blob of another root is left where it
# was — same file list, same inode, same size, same mtime, same leading bytes. A normal cached run still sweeps by age and
# by budget (the control twin of every arm), so the fix cannot pass by disabling hygiene.
#
# Arms (each on a freshly seeded cache dir: four other-root blobs of 700 MiB each, past the 2 GiB budget, plus one other-
# root blob aged past 30 days):
#   N1..N4  --no-cache  --edit-check=f | --quality-delta | --merge-scout=HEAD~1 | --dmm — the other-root set is unchanged
#           and stderr carries no eviction line. Red on base: each of these reaches a qheadsnap/qms saveCache.
#   N5      --no-cache with no verb — the same (green on base too: the main ingest writes nothing under --no-cache).
#   C1..C2  the cached twins (plain map, --edit-check=f): the sweep still runs — the aged blob is gone, at least one budget
#           blob is gone, and the eviction notice is on stderr.
#
# FINGERPRINT, and why it is byte-for-byte: each seeded blob is 64 KiB of distinct random bytes followed by a sparse hole
# (truncate -s), so reading 2.8 GiB of zeros per arm is not needed. The sweep's only write is fs::remove; a blob it did not
# remove keeps its inode, and a same-inode file whose size, mtime and non-hole bytes all match is the same bytes.
# Sparse fillers also keep the REAL 2 GiB budget in play — there is no test-only budget knob.
# Usage:  test/nocacheevictcheck.sh   |   RIPWIRE_BIN=build/ripwire test/nocacheevictcheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
. "$ROOT/test/lib/statcompat.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ echo "  PASS  $1" || { fail=1; echo "  FAIL  could not write the PASS line for: $1"; }; return 0; }
no(){ echo "  FAIL  $1"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v truncate >/dev/null 2>&1 || { echo "truncate required (sparse-file filler)"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
TMPD="$TMP/tmpdir"; CACHEDIR="$TMPD/ripwire"; HOMED="$TMP/home"; mkdir -p "$HOMED"
REPO="$TMP/repo"; mkdir -p "$REPO"

# ── fixture repo: two commits and a dirty working tree, so --quality-delta / --edit-check take the archived-HEAD path ──
g(){ git -C "$REPO" -c user.name=gate -c user.email=gate@example.invalid -c commit.gpgsign=false "$@"; }
g init -q
printf 'int f( int x ) { return x + 1; }\nint g( int x ) { return f( x ) * 2; }\n' > "$REPO/a.c"
g add a.c; g commit -qm one
printf 'int h( int x ) { return x - 1; }\n' > "$REPO/b.c"
g add b.c; g commit -qm two
printf 'int f( int x, int y ) { if( x > y ) { return x; } return y + 1; }\nint g( int x ) { return f( x, 2 ) * 2; }\n' > "$REPO/a.c"

# ── seeding ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
# Other roots' names: 16 hex root keys no real root of this fixture can hash to. Two flat (the pre-Y4 layout), two in a
# shard dir (the current layout), one aged blob flat. mtimes are fixed and in the past, inside the 30-day window for the
# budget blobs, outside it for the aged one.
OTHERS="ripwire-aaaa000000000001-lean.bin ripwire-aaaa000000000002-rich.bin ab/ripwire-aaaa000000000003-lean.bin ab/ripwire-aaaa000000000004-rich.bin"
AGED="ripwire-aaaa0000000000a9-lean.bin"
seed(){
    rm -rf "$CACHEDIR"; mkdir -p "$CACHEDIR/ab"; chmod 700 "$CACHEDIR"
    local rel recent
    recent="$( date -v-1d +%Y%m%d%H%M 2>/dev/null || date -d '1 day ago' +%Y%m%d%H%M )"
    for rel in $OTHERS; do
        head -c 65536 /dev/urandom > "$CACHEDIR/$rel"
        truncate -s 700M "$CACHEDIR/$rel"
        touch -t "$recent" "$CACHEDIR/$rel"
    done
    head -c 65536 /dev/urandom > "$CACHEDIR/$AGED"
    touch -t 202001010000 "$CACHEDIR/$AGED"
}
# one line per seeded other-root blob that exists: relpath, inode, size, mtime, digest of the non-hole bytes
fingerprint(){
    local rel f
    for rel in $OTHERS $AGED; do
        f="$CACHEDIR/$rel"
        [ -e "$f" ] || continue
        printf '%s %s %s %s\n' "$rel" "$( inode_mtime_of "$f" )" "$( size_of "$f" )" "$( head -c 65536 "$f" | cksum )"
    done
}
run(){ env -u XDG_CACHE_HOME HOME="$HOMED" TMPDIR="$TMPD" "$BIN" "$REPO" "$@" >"$TMP/out" 2>"$TMP/err"; }

# ── N1..N5: --no-cache leaves every other root's blob in place ───────────────────────────────────────────────────────────
nocache_arm(){
    local name="$1"; shift
    seed
    fingerprint > "$TMP/before"
    run --no-cache "$@"; local rc=$?
    fingerprint > "$TMP/after"
    if [ "$rc" -ne 0 ] && [ "$rc" -ne 2 ]; then no "$name: exit $rc (stderr: $( head -c 300 "$TMP/err" ))"; return; fi
    if cmp -s "$TMP/before" "$TMP/after"; then
        ok "$name: all $( wc -l < "$TMP/before" | tr -d ' ' ) other-root blobs unchanged (list, inode, size, mtime, bytes)"
    else
        no "$name: other-root blobs changed — before/after: $( diff "$TMP/before" "$TMP/after" | grep '^[<>]' | cut -c1-80 | tr '\n' '|' )"
    fi
    if grep -q 'evicted' "$TMP/err"; then no "$name: stderr reports an eviction: $( grep 'evicted' "$TMP/err" | head -1 | cut -c1-160 )"
    else ok "$name: no eviction line on stderr"; fi
}
nocache_arm "N1 --no-cache --edit-check=f"      --edit-check=f
nocache_arm "N2 --no-cache --quality-delta"     --quality-delta
nocache_arm "N3 --no-cache --merge-scout=HEAD~1" --merge-scout=HEAD~1
nocache_arm "N4 --no-cache --dmm"               --dmm
nocache_arm "N5 --no-cache (map)"

# ── C1..C2: a normal cached run still sweeps (no regression of the hygiene the sweep exists for) ────────────────────────
cached_arm(){
    local name="$1"; shift
    seed
    run "$@"; local rc=$?
    if [ "$rc" -ne 0 ] && [ "$rc" -ne 2 ]; then no "$name: exit $rc (stderr: $( head -c 300 "$TMP/err" ))"; return; fi
    if [ -e "$CACHEDIR/$AGED" ]; then no "$name: the 30-day age pass left the aged other-root blob"; else ok "$name: age pass removed the aged blob"; fi
    local left=0 rel
    for rel in $OTHERS; do [ -e "$CACHEDIR/$rel" ] && left=$(( left + 1 )); done
    if [ "$left" -lt 4 ]; then ok "$name: budget pass evicted $(( 4 - left )) of 4 other-root blobs"; else no "$name: budget pass evicted none of 4 (2.8 GiB over a 2 GiB budget)"; fi
    if grep -q 'over its 2048 MiB budget — evicted' "$TMP/err"; then ok "$name: eviction notice on stderr"; else no "$name: no eviction notice (stderr: $( head -c 300 "$TMP/err" ))"; fi
}
cached_arm "C1 cached map"
cached_arm "C2 cached --edit-check=f" --edit-check=f

echo
if [ "$fail" -eq 0 ]; then echo "ALL CHECKS PASSED"; exit 0; fi
echo "SOME CHECKS FAILED"; exit 1
