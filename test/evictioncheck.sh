#!/usr/bin/env bash
# evictioncheck.sh — gate for A5 (cache-dir hygiene): the cache-ladder dir accumulates ripwire-* blobs
# (the main lean/rich parse-cache PLUS qsnap/qheadsnap) but only the qsnap/qheadsnap families ever
# evicted — the main family had NO evictor at all. --doctor measured ~11,914 blobs / 2.4 GB on a machine
# that runs ~20 parallel agent sessions across many repos.
#
# Policy under test (quality.h: evictOldCacheFamily generalized + sweepStaleCacheBlobsOnce; hooked from
# src/ingest.cpp's saveCache, right after the tmp->rename publish): at saveCache time, at most once per
# process, best-effort and silent — first delete any ripwire-* blob older than 30 days, THEN (only if the
# dir is still over budget) delete oldest-first until the dir total is under 2 GB. The blob this run just
# wrote/used is NEVER deleted by either pass.
#
# Y4 — BLOB-COUNT SHARDING: new blobs are written under a 2-hex-char shard subdir keyed on the
# blob's own filename hash (`resolveCacheBlobPath`/`blobShardHex`, quality.h); a pre-existing FLAT blob is
# still found and reused where it already sits (no migration step). evictOldCacheFamily now sweeps BOTH
# layouts. This gate seeds ONE of each family member in BOTH layouts (flat, the pre-Y4 shape; and inside a
# fixed shard dir, the new shape) to prove the sweep still finds+removes/keeps correctly across the mix, and
# confirms the run's OWN freshly-written blob lands in a shard dir (the new code path is really exercised,
# not just accidentally still flat).
#
# Checks (a private seeded TMPDIR so we own every byte the sweep can see):
#   (a) an OLD blob (mtime > 30 days, fixed past date) is swept by the age pass — in BOTH layouts.
#   (b) OVERSIZED filler — a single sparse blob that alone pushes the dir over 2 GB, with a mtime well
#       INSIDE the 30-day window (so only the size pass, not the age pass, can catch it) — is swept once
#       the dir total exceeds budget. This isolates the two mechanisms from each other.
#   (c) a FRESH, small blob (younger than the filler) survives both passes — in BOTH layouts.
#   (d) the blob THIS run itself just wrote (the real auto-cache for the seeded fixture repo) survives, AND
#       lands inside a shard subdir (not flat) — the Y4 write path is really exercised.
#   (e) the dir is back under budget after the sweep.
#   (f) concurrency smoke: two ripwire processes racing saveCache/eviction against the SAME seeded dir
#       (same fixture repo → same cache-file key) — neither crashes, both exit 0, both still emit
#       well-formed output. Matches the quality.h comment: loadCache self-heals a missing/torn file,
#       saveCache publishes via tmp-then-rename, and a double fs::remove of an already-gone file is a
#       benign ENOENT no-op — so two sweepers racing on the same stale blob is safe by construction.
#
# Sparse filler (truncate -s) keeps the ">2 GB" file logically oversized (what fs::file_size measures)
# without touching real disk, so the gate stays fast. Does NOT edit regression.sh.
# Usage:  test/evictioncheck.sh   |   RIPWIRE_BIN=build_r2a1/ripwire test/evictioncheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ echo "  PASS  $1"; }
no(){ echo "  FAIL  $1"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v truncate >/dev/null 2>&1 || { echo "truncate required (sparse-file filler)"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
CACHEBASE="$TMP/cachebase"; CACHEDIR="$CACHEBASE/ripwire"; mkdir -p "$CACHEDIR"
REPO="$TMP/repo"; mkdir -p "$REPO"

# apparent (logical) byte size of a file — what fs::file_size measures, NOT `du`'s block-usage view
# (a sparse file's disk usage is ~0 but its apparent size is what the sweep's byte budget compares against).
# L3 (Linux probe): portable stat reader(s). GNU coreutils and BSD/macOS disagree on both the flag and the
# format directives, and the `stat -f FMT ... || stat -c FMT ...` fallback this gate used is a TRAP. On GNU,
# `-f` means FILESYSTEM status and takes NO format argument, so FMT is parsed as a second FILE: measured on
# coreutils 9.11, `stat -f %i FILE` PRINTS a six-line filesystem block for FILE on stdout and exits 1. The
# `||` arm then appends the right number under six lines of junk -- so a string compare fails, a numeric
# compare dies with "integer expression expected", and a `|| echo MISSING` variant reports MISSING forever
# (a gate that then passes by comparing nothing to nothing). Detect the flavour ONCE, use one form.
if stat --version >/dev/null 2>&1; then apparentsize(){ stat -c %s "$1" 2>/dev/null || echo 0; }   # GNU coreutils
else                                    apparentsize(){ stat -f %z "$1" 2>/dev/null || echo 0; }   # BSD / macOS
fi
# Y4: shard-aware — every blob glob below now looks at both the flat top-level AND any 2-hex-char shard
# subdir (mindepth/maxdepth bound it to exactly the layouts the sweep itself understands; never an
# open-ended walk of a shared $TMPDIR).
allblobs(){ find "$CACHEDIR" -mindepth 1 -maxdepth 2 -name 'ripwire-*.bin' 2>/dev/null; }
dirapparentbytes(){
    local total=0 f sz
    while IFS= read -r f; do
        [ -e "$f" ] || continue
        sz="$( apparentsize "$f" )"
        total=$(( total + sz ))
    done < <( allblobs )
    echo "$total"
}

echo "evictioncheck: BIN=$BIN  CACHEDIR=$CACHEDIR"

# a tiny fixture so each run itself is fast; content only needs to parse cleanly.
printf 'int tiny( void )\n{\n    return 1;\n}\n' > "$REPO/f.cpp"

OLD="$CACHEDIR/ripwire-deadbeef0000aaaa-lean.bin"
FILLER="$CACHEDIR/ripwire-deadbeef0000bbbb-lean.bin"
FRESH="$CACHEDIR/ripwire-deadbeef0000cccc-lean.bin"
# Y4: a fixed shard dir seeded with its own old/fresh pair — proves the sweep reaches INTO the new layout,
# not just the flat legacy one, in the SAME run as the flat trio above (a realistic mixed-layout cache dir).
SHARDDIR="$CACHEDIR/7f"; mkdir -p "$SHARDDIR"
OLD_SH="$SHARDDIR/ripwire-deadbeef0000a1a1-lean.bin"
FRESH_SH="$SHARDDIR/ripwire-deadbeef0000c1c1-lean.bin"

# (a) an OLD blob — a fixed date far in the past, so it is always >30 days old regardless of when this
#     gate runs (no live date-arithmetic needed). Seeded in BOTH layouts.
printf 'stale-old-cache-blob' > "$OLD"
touch -t 202001010000 "$OLD"
printf 'stale-old-cache-blob-sharded' > "$OLD_SH"
touch -t 202001010000 "$OLD_SH"

# (b) OVERSIZED filler — a single sparse blob >2 GB on its own, mtime "now" (well inside the 30-day
#     window) so it can ONLY be swept by the size pass, never the age pass.
truncate -s 2600M "$FILLER"

sleep 1   # mtime-granularity separation: FRESH must sort newer than FILLER for the oldest-first size pass

# (c) a FRESH, small blob — must survive both passes. Seeded in BOTH layouts.
printf 'fresh-small-cache-blob' > "$FRESH"
printf 'fresh-small-cache-blob-sharded' > "$FRESH_SH"

beforecount="$( allblobs | wc -l | tr -d ' ' )"
[ "$beforecount" -eq 5 ] && ok "seed: 5 fake blobs in place (old/filler/fresh flat + old/fresh sharded)" || no "seed setup wrong (count=$beforecount)"
beforebytes="$( dirapparentbytes )"
[ "$beforebytes" -gt 2147483648 ] && ok "seed: dir already exceeds the 2 GB budget (~$beforebytes bytes)" \
    || no "seed: dir does not exceed budget yet (~$beforebytes bytes) — filler too small"

# Run pointed at the seeded dir via TMPDIR (the first rung of cacheDirLadder()) — no --cache/--no-cache,
# so ripwire takes its normal auto-cache path (defaultCachePath) and saveCache's hygiene hook fires for real.
env -u XDG_CACHE_HOME TMPDIR="$CACHEBASE" "$BIN" "$REPO" >"$TMP/run1.xml" 2>"$TMP/run1.err"
rc1=$?

[ "$rc1" -eq 0 ] && ok "run against the seeded dir exits 0" || { no "run exited $rc1"; cat "$TMP/run1.err"; }
grep -q 'n="tiny"' "$TMP/run1.xml" 2>/dev/null && ok "run output still correct (tiny present)" || no "run output missing tiny()"

[ ! -e "$OLD" ]     && ok "OLD blob (flat, mtime > 30 days) swept"                    || no "OLD flat blob survived — age sweep not working"
[ ! -e "$OLD_SH" ]  && ok "OLD blob (sharded, mtime > 30 days) swept"                 || no "OLD sharded blob survived — age sweep does not reach the shard layout"
[ ! -e "$FILLER" ]  && ok "OVERSIZED filler swept once dir total exceeded 2 GB"       || no "oversized filler survived — size sweep not working"
[ -e "$FRESH" ]     && ok "FRESH small blob (flat) survives both passes"              || no "FRESH flat blob was wrongly swept"
[ -e "$FRESH_SH" ]  && ok "FRESH small blob (sharded) survives both passes"           || no "FRESH sharded blob was wrongly swept"

aftercount="$( allblobs | wc -l | tr -d ' ' )"
# FRESH (both layouts) survive + exactly the real blob(s) this run just wrote/used remain (lean cache for the fixture repo).
[ "$aftercount" -ge 3 ] && ok "this run's own just-written cache blob survives alongside FRESH x2 ($aftercount file(s) remain)" \
    || no "this run's own cache blob is missing — keepPath not honored ($aftercount file(s) remain)"

ownblob="$( allblobs | grep -v -e "$FRESH" -e "$FRESH_SH" )"
[ -n "$ownblob" ] && ok "this run's own cache blob found: $( basename "$ownblob" )" || no "could not locate this run's own cache blob at all"
printf '%s' "$ownblob" | grep -qE '/[0-9a-f]{2}/ripwire-' \
    && ok "this run's own cache blob landed in a SHARD subdir (Y4 write path exercised, not just flat)" \
    || no "this run's own cache blob is still FLAT — resolveCacheBlobPath did not shard a fresh write ($ownblob)"

afterbytes="$( dirapparentbytes )"
[ "$afterbytes" -lt 2147483648 ] && ok "cache dir back under the 2 GB budget after the sweep (~$afterbytes bytes)" \
    || no "cache dir still over budget after the sweep (~$afterbytes bytes)"

# ── (f) concurrency smoke: reseed a stale + oversized blob, fire two ripwire processes at the SAME dir ────
# Win 2 (ingest.cpp) skips saveCache entirely on a no-change warm run — and the eviction sweep lives
# INSIDE saveCache — so the fixture must actually change here, or neither concurrent run would touch
# saveCache at all and this check would pass vacuously.
printf 'int tiny2( void )\n{\n    return 2;\n}\n' >> "$REPO/f.cpp"
OLD2="$CACHEDIR/ripwire-deadbeef0000dddd-lean.bin"
FILLER2="$CACHEDIR/ripwire-deadbeef0000eeee-lean.bin"
printf 'stale-old-cache-blob-2' > "$OLD2"; touch -t 202001010000 "$OLD2"
truncate -s 2600M "$FILLER2"

env -u XDG_CACHE_HOME TMPDIR="$CACHEBASE" "$BIN" "$REPO" >"$TMP/run2a.xml" 2>"$TMP/run2a.err" &
pid_a=$!
env -u XDG_CACHE_HOME TMPDIR="$CACHEBASE" "$BIN" "$REPO" >"$TMP/run2b.xml" 2>"$TMP/run2b.err" &
pid_b=$!
wait "$pid_a"; rc_a=$?
wait "$pid_b"; rc_b=$?

[ "$rc_a" -eq 0 ] && ok "concurrent run A exits 0" || { no "concurrent run A exited $rc_a"; cat "$TMP/run2a.err"; }
[ "$rc_b" -eq 0 ] && ok "concurrent run B exits 0" || { no "concurrent run B exited $rc_b"; cat "$TMP/run2b.err"; }
grep -q 'n="tiny"' "$TMP/run2a.xml" 2>/dev/null && ok "concurrent run A output well-formed (tiny present)" || no "concurrent run A output malformed"
grep -q 'n="tiny"' "$TMP/run2b.xml" 2>/dev/null && ok "concurrent run B output well-formed (tiny present)" || no "concurrent run B output malformed"
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/run2a.xml" 2>/dev/null && ok "concurrent run A: xml well-formed" || no "concurrent run A: xml malformed"
    xmllint --noout "$TMP/run2b.xml" 2>/dev/null && ok "concurrent run B: xml well-formed" || no "concurrent run B: xml malformed"
fi
[ ! -e "$OLD2" ]    && ok "concurrency: stale blob swept without either process crashing"   || no "concurrency: stale blob survived both sweeps"
[ ! -e "$FILLER2" ] && ok "concurrency: oversized filler swept without either process crashing" || no "concurrency: oversized filler survived both sweeps"

# ── (g) W1-V4 (2026-08-11): the ".cache" arm and the locks/ invariant, neither previously gated ──────────
# evictOldCacheFamily's `matches()` lambda (src/quality.h) accepts EITHER ".bin" OR ".cache" as a family
# member suffix — every arm above only ever seeded ".bin", so the ".cache" half of that OR was never
# exercised by any gate. Separately, advisory edit locks (src/mcpedit.h editLockPath) deliberately live
# under `cacheDirLadder()/locks/` specifically so the sweep's shard walk — which only recurses into
# EXACTLY-2-hex-char subdirectory names — never descends into them, and their ".lock" suffix would fail
# `matches()` even if it did; the comment there says outright "cache eviction never scans or removes a
# possibly-live advisory-lock inode." No prior gate asserted either fact — this section is the first to.
#
# A fresh, ISOLATED cache dir (own TMPDIR): the byte-budget arithmetic in the arms above only counts
# "ripwire-*.bin" (see allblobs()/dirapparentbytes()), so a .cache file would silently fall outside their
# accounting either way — cleaner to give this its own directory than reason about interference.
TMP2="$( mktemp -d )"; trap 'rm -rf "$TMP" "$TMP2"' EXIT
CACHEBASE2="$TMP2/cachebase"; CACHEDIR2="$CACHEBASE2/ripwire"; mkdir -p "$CACHEDIR2"
REPO2="$TMP2/repo"; mkdir -p "$REPO2"
printf 'int tiny3( void )\n{\n    return 3;\n}\n' > "$REPO2/f.cpp"

OLDCACHE="$CACHEDIR2/ripwire-deadbeef0000f1f1-lean.cache"
FRESHCACHE="$CACHEDIR2/ripwire-deadbeef0000f2f2-lean.cache"
LOCKDIR="$CACHEDIR2/locks"; mkdir -p "$LOCKDIR"
# real editLockPath() shape: "ripwire-edit-<16 hex>.lock" — same "ripwire-" prefix the family sweep
# matches on everywhere else, so if the locks/ protection ever weakened this is exactly what would go.
OLDLOCK="$LOCKDIR/ripwire-edit-00000000deadbeef.lock"

printf 'stale-old-cache-blob-dotcache' > "$OLDCACHE"
touch -t 202001010000 "$OLDCACHE"
printf 'ancient-advisory-lock-should-never-be-touched' > "$OLDLOCK"
touch -t 202001010000 "$OLDLOCK"
sleep 1
printf 'fresh-small-cache-blob-dotcache' > "$FRESHCACHE"

env -u XDG_CACHE_HOME TMPDIR="$CACHEBASE2" "$BIN" "$REPO2" >"$TMP2/run.xml" 2>"$TMP2/run.err"
rc3=$?
[ "$rc3" -eq 0 ] && ok "Y5: run against the seeded .cache/locks dir exits 0" || { no "Y5: run exited $rc3"; cat "$TMP2/run.err"; }
grep -q 'n="tiny3"' "$TMP2/run.xml" 2>/dev/null && ok "Y5: run output correct (tiny3 present)" || no "Y5: run output missing tiny3()"

[ ! -e "$OLDCACHE" ]  && ok "(a) an old .cache file IS evicted by the family eviction (age pass reaches .cache too)" \
                       || no "(a) old .cache blob survived — the .cache arm of matches() is not being swept"
[ -e "$FRESHCACHE" ]  && ok "(b) a fresh .cache file is NOT evicted" \
                       || no "(b) fresh .cache blob was wrongly swept"
[ -e "$OLDLOCK" ]     && ok "(c) an ancient file under locks/ is NEVER removed by eviction (locks subtree unreached)" \
                       || no "(c) ancient file under locks/ was REMOVED — eviction reached the advisory-lock subtree"
# (d) .bin behavior unchanged: already covered above by the pre-existing OLD/FILLER/FRESH .bin arms (both
# flat and sharded layouts), which this section's separate TMPDIR/CACHEDIR does not touch or interact with.

[ "$fail" -eq 0 ] && echo "evictioncheck: ALL PASS" || { echo "evictioncheck: SOME CHECKS FAILED"; exit 1; }
