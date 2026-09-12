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
#   (h) P1-1: the MRU root's SIBLING family is PINNED through a byte-budget sweep — the sweep takes another
#       root's blob instead, and says so once on stderr.
#   (i) P1-1: when the pinned set ALONE exceeds the budget it is kept anyway, said once on stderr.
#   (j) P1-1: a sweep that evicts nothing writes ZERO bytes to stderr (the disclosure is conditional).
#   (k) ONE ROOT KEY FOR EVERY FAMILY: prime lean/rich/qheadsnap/qsnap/qchurn against one root; every blob
#       name must carry the SAME 16-hex root field, qchurn included (P1-1's stated gap).
#   (l) that key is a property of the ROOT, not its SPELLING: a trailing slash and a symlinked path add no
#       new key.
#
# Sparse filler (truncate -s) keeps the ">2 GB" file logically oversized (what fs::file_size measures)
# without touching real disk, so the gate stays fast — which is also why arms (h)-(j) can exercise the REAL
# 2 GB budget rather than a test-only override. Does NOT edit regression.sh.
# Usage:  test/evictioncheck.sh   |   RIPWIRE_BIN=build_r2a1/ripwire test/evictioncheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ echo "  PASS  $1" || { fail=1; echo "  FAIL  could not write the PASS line for: $1"; }; return 0; }
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
if [ "$beforecount" -eq 5 ]; then ok "seed: 5 fake blobs in place (old/filler/fresh flat + old/fresh sharded)"; else no "seed setup wrong (count=$beforecount)"; fi
beforebytes="$( dirapparentbytes )"
[ "$beforebytes" -gt 2147483648 ] && ok "seed: dir already exceeds the 2 GB budget (~$beforebytes bytes)" \
    || no "seed: dir does not exceed budget yet (~$beforebytes bytes) — filler too small"

# Run pointed at the seeded dir via TMPDIR (the first rung of cacheDirLadder()) — no --cache/--no-cache,
# so ripwire takes its normal auto-cache path (defaultCachePath) and saveCache's hygiene hook fires for real.
env -u XDG_CACHE_HOME TMPDIR="$CACHEBASE" "$BIN" "$REPO" >"$TMP/run1.xml" 2>"$TMP/run1.err"
rc1=$?

if [ "$rc1" -eq 0 ]; then ok "run against the seeded dir exits 0"; else { no "run exited $rc1"; cat "$TMP/run1.err"; }; fi
if grep -q 'n="tiny"' "$TMP/run1.xml" 2>/dev/null; then ok "run output still correct (tiny present)"; else no "run output missing tiny()"; fi

if [ ! -e "$OLD" ]; then ok "OLD blob (flat, mtime > 30 days) swept"; else no "OLD flat blob survived — age sweep not working"; fi
if [ ! -e "$OLD_SH" ]; then ok "OLD blob (sharded, mtime > 30 days) swept"; else no "OLD sharded blob survived — age sweep does not reach the shard layout"; fi
if [ ! -e "$FILLER" ]; then ok "OVERSIZED filler swept once dir total exceeded 2 GB"; else no "oversized filler survived — size sweep not working"; fi
if [ -e "$FRESH" ]; then ok "FRESH small blob (flat) survives both passes"; else no "FRESH flat blob was wrongly swept"; fi
if [ -e "$FRESH_SH" ]; then ok "FRESH small blob (sharded) survives both passes"; else no "FRESH sharded blob was wrongly swept"; fi

aftercount="$( allblobs | wc -l | tr -d ' ' )"
# FRESH (both layouts) survive + exactly the real blob(s) this run just wrote/used remain (lean cache for the fixture repo).
[ "$aftercount" -ge 3 ] && ok "this run's own just-written cache blob survives alongside FRESH x2 ($aftercount file(s) remain)" \
    || no "this run's own cache blob is missing — keepPath not honored ($aftercount file(s) remain)"

ownblob="$( allblobs | grep -v -e "$FRESH" -e "$FRESH_SH" )"
if [ -n "$ownblob" ]; then ok "this run's own cache blob found: $( basename "$ownblob" )"; else no "could not locate this run's own cache blob at all"; fi
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

if [ "$rc_a" -eq 0 ]; then ok "concurrent run A exits 0"; else { no "concurrent run A exited $rc_a"; cat "$TMP/run2a.err"; }; fi
if [ "$rc_b" -eq 0 ]; then ok "concurrent run B exits 0"; else { no "concurrent run B exited $rc_b"; cat "$TMP/run2b.err"; }; fi
if grep -q 'n="tiny"' "$TMP/run2a.xml" 2>/dev/null; then ok "concurrent run A output well-formed (tiny present)"; else no "concurrent run A output malformed"; fi
if grep -q 'n="tiny"' "$TMP/run2b.xml" 2>/dev/null; then ok "concurrent run B output well-formed (tiny present)"; else no "concurrent run B output malformed"; fi
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/run2a.xml" 2>/dev/null; then ok "concurrent run A: xml well-formed"; else no "concurrent run A: xml malformed"; fi
    if xmllint --noout "$TMP/run2b.xml" 2>/dev/null; then ok "concurrent run B: xml well-formed"; else no "concurrent run B: xml malformed"; fi
fi
if [ ! -e "$OLD2" ]; then ok "concurrency: stale blob swept without either process crashing"; else no "concurrency: stale blob survived both sweeps"; fi
if [ ! -e "$FILLER2" ]; then ok "concurrency: oversized filler swept without either process crashing"; else no "concurrency: oversized filler survived both sweeps"; fi

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
# 2026-09-06 (stranger audit): the contract CHANGED. locks/ was "never reached" and one machine accumulated
# 45,765 lock files (one per path ever edited via the MCP edit verbs; the holder deliberately never unlinks).
# quality.h sweepStaleEditLocks now reclaims a lock that is (1) older than a day AND (2) not held — the
# flock(LOCK_EX|LOCK_NB) probe IS the liveness test. So the three cases below are the contract now: an
# ancient unheld lock goes; an ancient HELD lock stays (a peer's flock, held from a background python for
# the duration of the run); a fresh lock stays whatever its state.
HELDLOCK="$LOCKDIR/ripwire-edit-0000000000c0ffee.lock"
FRESHLOCK="$LOCKDIR/ripwire-edit-00000000f0e5f0e5.lock"

printf 'stale-old-cache-blob-dotcache' > "$OLDCACHE"
touch -t 202001010000 "$OLDCACHE"
printf 'ancient-advisory-lock-unheld' > "$OLDLOCK"
touch -t 202001010000 "$OLDLOCK"
printf 'ancient-advisory-lock-HELD' > "$HELDLOCK"
touch -t 202001010000 "$HELDLOCK"
printf 'fresh-advisory-lock' > "$FRESHLOCK"
python3 - "$HELDLOCK" <<'PYHOLD' &
import fcntl, sys, time
f = open( sys.argv[1], "r+" )
fcntl.flock( f, fcntl.LOCK_EX )
time.sleep( 120 )
PYHOLD
HOLDER=$!
sleep 1   # let the holder take the flock before the run's sweep probes it
sleep 1
printf 'fresh-small-cache-blob-dotcache' > "$FRESHCACHE"

env -u XDG_CACHE_HOME TMPDIR="$CACHEBASE2" "$BIN" "$REPO2" >"$TMP2/run.xml" 2>"$TMP2/run.err"
rc3=$?
if [ "$rc3" -eq 0 ]; then ok "Y5: run against the seeded .cache/locks dir exits 0"; else { no "Y5: run exited $rc3"; cat "$TMP2/run.err"; }; fi
if grep -q 'n="tiny3"' "$TMP2/run.xml" 2>/dev/null; then ok "Y5: run output correct (tiny3 present)"; else no "Y5: run output missing tiny3()"; fi

[ ! -e "$OLDCACHE" ]  && ok "(a) an old .cache file IS evicted by the family eviction (age pass reaches .cache too)" \
                       || no "(a) old .cache blob survived — the .cache arm of matches() is not being swept"
[ -e "$FRESHCACHE" ]  && ok "(b) a fresh .cache file is NOT evicted" \
                       || no "(b) fresh .cache blob was wrongly swept"
kill "$HOLDER" 2>/dev/null; wait "$HOLDER" 2>/dev/null
[ ! -e "$OLDLOCK" ]   && ok "(c1) an ancient UNHELD lock under locks/ is reclaimed by the sweep (2026-09-06 contract)" \
                       || no "(c1) ancient unheld lock survived — sweepStaleEditLocks did not reach locks/"
[ -e "$HELDLOCK" ]    && ok "(c2) an ancient HELD lock survives the sweep (flock probe is the liveness test)" \
                       || no "(c2) a HELD lock was removed — the sweep unlinked a live advisory lock"
[ -e "$FRESHLOCK" ]   && ok "(c3) a fresh lock survives the sweep (age bound)" \
                       || no "(c3) a fresh lock was removed — the age bound is not binding"
# (d) .bin behavior unchanged: already covered above by the pre-existing OLD/FILLER/FRESH .bin arms (both
# flat and sharded layouts), which this section's separate TMPDIR/CACHEDIR does not touch or interact with.

# ── (h)(i)(j) P1-1 (2026-09-10 audit) — the MRU ROOT'S OWN FAMILIES ARE PINNED DURING A BUDGET SWEEP ────
# THE DEFECT. One llvm-project root needs 1.76 GB of cache for its OWN two families (rich 1.19 GB + lean
# 0.57 GB) against a dir-wide 2 GB oldest-first sweep. Add anything else — a second corpus, or one
# --edit-check HEAD snapshot (0.52 GB on llvm) — and the sweep evicts the SIBLING FAMILY OF THE SAME ROOT,
# because evictOldCacheFamily only ever protected `keepPath` (the one blob being written). Measured, same
# argv, same session, same binary: `--grep=SmallVector` 20 s → 206 s, `--for=...` 19 s → 268 s, and the
# ping-pong is self-sustaining (each cold run's save evicts the other family again). Zero disclosure: all
# four .err files were 0 bytes. The 2 GB constant is a blow-up guard and is NOT lowered (owner rule
# `quality-first-caps-are-blowup-guards`); the eviction ORDER is what changes.
#
# THE CONTRACT UNDER TEST (quality.h: cacheBlobRootKey + evictOldCacheFamily's size pass):
#   (h) every blob of the MRU root — lean, rich, qheadsnap, qsnap, … — is PINNED for the duration of a
#       byte-budget sweep; the sweep takes OTHER roots first, oldest-first, exactly as before. Red-first:
#       against the pre-change binary the pinned sibling is the FIRST thing deleted (it is the oldest).
#   (i) if the pinned set ALONE still exceeds the budget, it is kept anyway (evicting it would force the
#       full re-parse this whole change exists to prevent) and ONE `ripwire: cache …` line says so. That
#       line is a plain stderr emit, never DEGRADED_PATH_ALERT: NDEBUG compiles the alert out and the
#       whole point is that a Release binary discloses this too.
#   (j) the disclosure is CONDITIONAL: a run whose sweep evicts nothing writes ZERO bytes to stderr.
# The PIN KEY is the 16-hex root field that every family's filename carries — defaultCachePath's
# `ripwire-<rootKey>-{lean,rich}.bin`, mcpCachePath's `ripwire-mcp-<rootKey>.cache` and shaKeyedCachePath's
# `ripwire-<family>-<rootKey>-<exclHex>-<shaHex>.bin` alike, so no plumbing is needed: the sweep reads it
# off `keepPath` itself. That all three really do SPELL it the same way is arms (k)/(l) below — when these
# arms were written they did not, and (h) was pinning only half the dir.
#
# The AGE pass is deliberately NOT pinned — a blob nobody has touched in 30 days is stale by the hygiene
# policy's own definition, and its eviction costs one cold parse rather than a self-sustaining ping-pong.
# Every arm below therefore seeds mtimes inside the 30-day window, so only the size pass can fire.
#
# Sparse fillers again (truncate -s), so these arms exercise the REAL 2 GB budget — no test-only override
# env var is introduced, and the constant under test is the shipped one.

# apparent bytes of every ripwire-*.bin under an arbitrary cache dir (the arms below each own a private
# one, so the file-scope allblobs()/dirapparentbytes() — which are bound to $CACHEDIR — do not apply).
dirbytesof(){
    local total=0 f sz
    while IFS= read -r f; do
        [ -e "$f" ] || continue
        sz="$( apparentsize "$f" )"
        total=$(( total + sz ))
    done < <( find "$1" -mindepth 1 -maxdepth 2 -name 'ripwire-*.bin' 2>/dev/null )
    echo "$total"
}

# ---- (h) two roots, the MRU root's sibling family is the OLDEST blob in the dir --------------------
TMP3="$( mktemp -d )"; trap 'rm -rf "$TMP" "$TMP2" "$TMP3"' EXIT
CB3="$TMP3/cachebase"; CD3="$CB3/ripwire"; mkdir -p "$CD3"
R3="$TMP3/repo"; mkdir -p "$R3"
printf 'int pinme( void )\n{\n    return 1;\n}\n' > "$R3/f.cpp"

env -u XDG_CACHE_HOME TMPDIR="$CB3" "$BIN" "$R3" >/dev/null 2>"$TMP3/prime.err"
# -name 'ripwire-*-lean.bin', not 'ripwire-*.bin' (CodeRabbit #127 / 3985249724): the sed below only
# matches the LEAN basename, and the priming run can leave a -rich.bin beside it. `head -1` over the wider
# glob then returns whichever the filesystem happens to list first, ROOTHEX3 keeps the whole basename, and
# the 16-hex check goes red for a directory-ordering reason. Arm (k) at the bottom of this file already
# uses the precise pattern for the same job.
OWN3="$( find "$CD3" -mindepth 1 -maxdepth 2 -name 'ripwire-*-lean.bin' 2>/dev/null | head -1 )"
ROOTHEX3="$( basename "${OWN3:-none}" | sed -E 's/^ripwire-([0-9a-f]{16})-lean\.bin$/\1/' )"
if printf '%s' "$ROOTHEX3" | grep -qE '^[0-9a-f]{16}$'; then
    ok "(h) primed: this root's lean blob names root key $ROOTHEX3"
else
    no "(h) could not read a 16-hex root key off the primed blob (own='$OWN3')"
fi

# the SIBLING family of the SAME root — seeded FLAT (the sweep must find it in either layout) and made
# the OLDEST blob in the dir, which is exactly what the pre-change oldest-first sweep deletes first.
SIB3="$CD3/ripwire-$ROOTHEX3-rich.bin"
truncate -s 1200M "$SIB3"
# …and the SAME root's MCP index blob. It is the one family whose name is nothing but a root key, and it
# is the only one that ends `.cache` rather than `-<something>.bin` — so quality.h::cacheBlobRootKey, which
# split on '-' alone, read its last field as `<rootKey>.cache` (22 bytes, not hex16) and returned an EMPTY
# key. An empty key pins nothing: the sweep kept this root's lean and rich blobs and evicted the MCP index
# of the very root it was serving, and the MCP server paid a full re-parse for it. Zero-size on purpose —
# survival is the question, not bytes (CodeRabbit #127 / 3985249706).
MCP3="$CD3/ripwire-mcp-$ROOTHEX3.cache"
: > "$MCP3"
sleep 1
# a DIFFERENT root's blob, newer and bigger — the one an oldest-first sweep would keep, and the one the
# fixed sweep must take instead.
OTHER3="$CD3/ripwire-00000000deadf00d-lean.bin"
truncate -s 1500M "$OTHER3"

b3="$( dirbytesof "$CD3" )"
[ "$b3" -gt 2147483648 ] && ok "(h) seed: dir exceeds the 2 GB budget (~$b3 bytes: 1200M sibling + 1500M other root)" \
    || no "(h) seed: dir does not exceed budget (~$b3 bytes) — fillers too small"

printf 'int pinme2( void )\n{\n    return 2;\n}\n' >> "$R3/f.cpp"   # Win-2: saveCache (and the sweep) only run when something changed
env -u XDG_CACHE_HOME TMPDIR="$CB3" "$BIN" "$R3" >"$TMP3/run.xml" 2>"$TMP3/run.err"
rc4=$?
if [ "$rc4" -eq 0 ]; then ok "(h) run exits 0"; else { no "(h) run exited $rc4"; cat "$TMP3/run.err"; }; fi
if grep -q 'n="pinme"' "$TMP3/run.xml" 2>/dev/null; then ok "(h) run output still correct (pinme present)"; else no "(h) run output missing pinme()"; fi

[ -e "$SIB3" ] && ok "(h) the MRU root's SIBLING family survives a budget sweep (pinned) — P1-1's 206 s ping-pong" \
    || no "(h) the MRU root's sibling family was EVICTED — the sweep still takes the blob this root is about to need"
[ ! -e "$OTHER3" ] && ok "(h) the OTHER root's blob is what the sweep took instead" \
    || no "(h) the other root's blob survived — the sweep did not free the bytes it needed"
[ -e "$MCP3" ] && ok "(h) the MRU root's MCP index blob survives too — ripwire-mcp-<key>.cache reads as THIS root" \
    || no "(h) the MRU root's ripwire-mcp-<key>.cache was EVICTED — cacheBlobRootKey cannot read a '.'-terminated key field"

[ -s "$TMP3/run.err" ] && ok "(h) the eviction is DISCLOSED on stderr (was 0 bytes before this change)" \
    || no "(h) an eviction happened with ZERO disclosure — the honesty rule does not reach the cache layer"
grep -q '^ripwire: cache ' "$TMP3/run.err" 2>/dev/null && ok "(h) the disclosure uses the house 'ripwire: cache …' shape" \
    || { no "(h) no 'ripwire: cache …' line on stderr"; cat "$TMP3/run.err"; }
errlines3="$( wc -l < "$TMP3/run.err" | tr -d ' ' )"
[ "$errlines3" -eq 1 ] && ok "(h) exactly ONE disclosure line (not one per evicted blob)" \
    || no "(h) expected 1 stderr line, got $errlines3"

# ---- (i) the pinned set ALONE exceeds the budget → kept anyway, said once ---------------------------
TMP4="$( mktemp -d )"; trap 'rm -rf "$TMP" "$TMP2" "$TMP3" "$TMP4"' EXIT
CB4="$TMP4/cachebase"; CD4="$CB4/ripwire"; mkdir -p "$CD4"
R4="$TMP4/repo"; mkdir -p "$R4"
printf 'int solo( void )\n{\n    return 1;\n}\n' > "$R4/f.cpp"

env -u XDG_CACHE_HOME TMPDIR="$CB4" "$BIN" "$R4" >/dev/null 2>/dev/null
OWN4="$( find "$CD4" -mindepth 1 -maxdepth 2 -name 'ripwire-*.bin' 2>/dev/null | head -1 )"
ROOTHEX4="$( basename "${OWN4:-none}" | sed -E 's/^ripwire-([0-9a-f]{16})-lean\.bin$/\1/' )"
SIB4="$CD4/ripwire-$ROOTHEX4-rich.bin"
if printf '%s' "$ROOTHEX4" | grep -qE '^[0-9a-f]{16}$'; then
    truncate -s 2600M "$SIB4"   # this root's own sibling ALONE blows the 2 GB budget (llvm's rich blob is 1.19 GB; a second root doubles it)
    ok "(i) primed: root key $ROOTHEX4, sibling family seeded at 2600M (over budget on its own)"
else
    no "(i) could not read a 16-hex root key off the primed blob (own='$OWN4')"
fi

printf 'int solo2( void )\n{\n    return 2;\n}\n' >> "$R4/f.cpp"
env -u XDG_CACHE_HOME TMPDIR="$CB4" "$BIN" "$R4" >"$TMP4/run.xml" 2>"$TMP4/run.err"
rc5=$?
if [ "$rc5" -eq 0 ]; then ok "(i) run exits 0 even with the pinned set over budget"; else { no "(i) run exited $rc5"; cat "$TMP4/run.err"; }; fi
if grep -q 'n="solo"' "$TMP4/run.xml" 2>/dev/null; then ok "(i) run output still correct (solo present)"; else no "(i) run output missing solo()"; fi
[ -e "$SIB4" ] && ok "(i) the pinned set is KEPT even though it alone exceeds the budget" \
    || no "(i) the pinned set was evicted when nothing else could be freed — the ping-pong is back"
grep -q '^ripwire: cache ' "$TMP4/run.err" 2>/dev/null && ok "(i) the over-budget pinned set is said once on stderr" \
    || { no "(i) the pinned set exceeded the budget with no disclosure"; cat "$TMP4/run.err"; }
errlines4="$( wc -l < "$TMP4/run.err" | tr -d ' ' )"
if [ "$errlines4" -eq 1 ]; then ok "(i) exactly ONE stderr line"; else no "(i) expected 1 stderr line, got $errlines4"; fi

# ---- (j) nothing evicted → ZERO stderr bytes -------------------------------------------------------
# The disclosure must be conditional, or every warm run in every gate that compares stderr grows a line.
TMP5="$( mktemp -d )"; trap 'rm -rf "$TMP" "$TMP2" "$TMP3" "$TMP4" "$TMP5"' EXIT
CB5="$TMP5/cachebase"; CD5="$CB5/ripwire"; mkdir -p "$CD5"
R5="$TMP5/repo"; mkdir -p "$R5"
printf 'int quiet( void )\n{\n    return 1;\n}\n' > "$R5/f.cpp"
env -u XDG_CACHE_HOME TMPDIR="$CB5" "$BIN" "$R5" >/dev/null 2>/dev/null
printf 'int quiet2( void )\n{\n    return 2;\n}\n' >> "$R5/f.cpp"
env -u XDG_CACHE_HOME TMPDIR="$CB5" "$BIN" "$R5" >"$TMP5/run.xml" 2>"$TMP5/run.err"
rc6=$?
if [ "$rc6" -eq 0 ]; then ok "(j) run exits 0"; else no "(j) run exited $rc6"; fi
[ ! -s "$TMP5/run.err" ] && ok "(j) a sweep that evicts nothing writes ZERO bytes to stderr" \
    || { no "(j) stderr is not empty on a no-eviction run — the disclosure is unconditional"; cat "$TMP5/run.err"; }

# ---- (k)(l) ONE ROOT KEY FOR EVERY CACHE FAMILY -----------------------------------------------------
#
# THE DEFECT (2026-09-10, the follow-up to P1-1's stated gap). The pin in (h) is only as wide as the set of
# blobs that SPELL the root the same way, and two spellings shipped. Both builders hash realpath(root) with
# FNV-1a, but with DIFFERENT offset bases:
#   main.cpp::defaultCachePath        seeded 1469598103934665603   (17 digits — a truncated basis)
#   quality.h::cacheRootKeyHex        seeded 14695981039346656037  (the real FNV-1a 64 basis)
# so ONE root produced TWO key families, always, on every corpus. Measured on llvm-project: lean/rich carried
# 4280d3ca01d82374 while qchurn carried 6b73c58ba5897c7a. Reproduced on a four-file fixture in one command:
# `ripwire-844a155665d606eb-{lean,rich}.bin` beside `ripwire-qchurn-526f2ad625b9f069--….bin`. Consequence:
# the byte-budget pin covers lean+rich and leaves qheadsnap/qsnap/qbody/qhist/qms/qchurn/stier unpinned — a
# git-metadata family that grew large under the divergent spelling is still evicted out from under the very
# root that is writing.
#
#   (k) prime EVERY family a normal session writes (default map, --for, --edit-check, --quality-delta,
#       --cochange) against ONE root, then read the 16-hex root field off every blob name by the SAME rule
#       cacheBlobRootKey uses (the first '-'-delimited field that is exactly 16 hex digits). There must be
#       EXACTLY ONE distinct value, and a qchurn blob must be among the blobs carrying it. Red-first: the
#       pre-change binary yields two.
#   (l) the key is a property of the ROOT, not of its SPELLING: the same tree addressed with a trailing
#       slash and through a symlink must not add a single new key (realpath-normalized before hashing).
#
# git is required for the qchurn/qheadsnap/qsnap families to exist at all; without it those verbs degrade to
# the uncached walk and write no blob, so the arm would compare one family against itself and pass blind.
if ! command -v git >/dev/null 2>&1; then
    no "(k)(l) git is required to prime the qchurn/qheadsnap/qsnap families — cannot run"
else

# TWO families carry a 16-hex field that is NOT a root key and must be read as unowned: `ripwire-docmd-`
# is content-addressed (the document's bytes) and `ripwire-stier-` is file-addressed (one span-tier memo
# per source file above 32 KiB — an llvm --for leaves ~30 of them). quality.h names them in
# `kNonRootKeyedBlobPrefixes`; this list is the shell mirror, and the arm below FAILS if the two disagree,
# so a family added later with a non-root 16-hex field cannot quietly join the pin.
NONROOT_PREFIXES='ripwire-docmd- ripwire-stier-'

# the root field, by cacheBlobRootKey's own rule: FIRST '-'-delimited field of the basename that is
# exactly 16 hex digits, EXCEPT for the non-root-keyed families above. Prints nothing when there is none.
blobrootkey(){
    local b p
    b="$( basename "$1" )"
    for p in $NONROOT_PREFIXES; do
        case "$b" in "$p"*) return 0;; esac
    done
    printf '%s' "$b" | sed -E 's/\.(bin|cache)$//' | awk -F- '{ for( i = 1; i <= NF; ++i ) if( $i ~ /^[0-9a-f]{16}$/ ) { print $i; exit } }'
}
# every distinct root key present under a cache dir, sorted+uniqued
allrootkeys(){
    local f
    while IFS= read -r f; do
        blobrootkey "$f"
    done < <( find "$1" -mindepth 1 -maxdepth 2 -type f -name 'ripwire-*' 2>/dev/null ) | sort -u
}
# prime every family a normal session writes, against root spelling $2, cache base $1
primeallfamilies(){
    local cb="$1" rt="$2"
    env -u XDG_CACHE_HOME TMPDIR="$cb" "$BIN" "$rt"                            >/dev/null 2>&1
    env -u XDG_CACHE_HOME TMPDIR="$cb" "$BIN" "$rt" --for="how does pinme work" >/dev/null 2>&1
    env -u XDG_CACHE_HOME TMPDIR="$cb" "$BIN" "$rt" --edit-check=pinme          >/dev/null 2>&1
    env -u XDG_CACHE_HOME TMPDIR="$cb" "$BIN" "$rt" --quality-delta             >/dev/null 2>&1
    env -u XDG_CACHE_HOME TMPDIR="$cb" "$BIN" "$rt" --cochange=f.cpp            >/dev/null 2>&1
}

# the two lists must name the SAME families, or this arm reads a key the binary does not.
SRC_NONROOT="$( sed -n 's/^inline constexpr std::string_view kNonRootKeyedBlobPrefixes\[\] = {\(.*\)};$/\1/p' "$ROOT/src/quality.h" \
                | tr ',' '\n' | sed -E 's/[^"]*"([^"]*)".*/\1/' | grep . | sort | tr '\n' ' ' )"
WANT_NONROOT="$( printf '%s\n' $NONROOT_PREFIXES | sort | tr '\n' ' ' )"
[ -n "$SRC_NONROOT" ] && [ "$SRC_NONROOT" = "$WANT_NONROOT" ] \
    && ok "(k) the non-root-keyed family list matches quality.h::kNonRootKeyedBlobPrefixes ($WANT_NONROOT)" \
    || no "(k) family-list drift: quality.h says '$SRC_NONROOT', this gate reads '$WANT_NONROOT'"

TMP6="$( mktemp -d )"; trap 'rm -rf "$TMP" "$TMP2" "$TMP3" "$TMP4" "$TMP5" "$TMP6"' EXIT
CB6="$TMP6/cachebase"; CD6="$CB6/ripwire"; mkdir -p "$CD6"
R6="$TMP6/repo"; mkdir -p "$R6"
cat > "$R6/f.cpp" <<'EOF_K'
int pinme( void )
{
    return 1;
}
int other( void )
{
    return pinme() + 1;
}
EOF_K
( cd "$R6" && git init -q . && git add -A && git -c user.email=g@g -c user.name=g commit -qm init ) >/dev/null 2>&1

primeallfamilies "$CB6" "$R6"

# The MCP index family, seeded by hand: `ripwire wrap` is not something this gate can drive, but the family
# exists (mcpindex.h::mcpCachePath → quality::rootKeyedCachePath( root, "ripwire-mcp-", ".cache" )) and it is
# the one whose key field is terminated by '.' rather than '-'. Without it in the dir the key-agreement arm
# below never asked the question that #127/3985249706 answered.
MCPKEY6="$( find "$CD6" -mindepth 1 -maxdepth 2 -type f -name 'ripwire-*-lean.bin' 2>/dev/null | head -1 )"
MCPKEY6="$( basename "${MCPKEY6:-none}" | sed -E 's/^ripwire-([0-9a-f]{16})-lean\.bin$/\1/' )"
if printf '%s' "$MCPKEY6" | grep -qE '^[0-9a-f]{16}$'; then
    : > "$CD6/ripwire-mcp-$MCPKEY6.cache"
    ok "(k) the MCP index family is present (ripwire-mcp-$MCPKEY6.cache) — the '.'-terminated key field"
else
    no "(k) could not derive this root's key from its lean blob, so the MCP family could not be seeded"
fi

blobs6="$( find "$CD6" -mindepth 1 -maxdepth 2 -type f -name 'ripwire-*' 2>/dev/null | wc -l | tr -d ' ' )"
[ "$blobs6" -ge 4 ] && ok "(k) primed $blobs6 cache blobs across the families one session writes" \
    || no "(k) only $blobs6 blob(s) written — the families under test were never primed"

find "$CD6" -mindepth 1 -maxdepth 2 -type f -name 'ripwire-qchurn-*' 2>/dev/null | grep -q . \
    && ok "(k) the qchurn family is present (the family P1-1 named as unpinned)" \
    || no "(k) no qchurn blob was written — --cochange did not memoize, arm proves nothing"

keys6="$( allrootkeys "$CD6" )"
nkeys6="$( printf '%s\n' "$keys6" | grep -c . )"
if [ "$nkeys6" -eq 1 ]; then
    ok "(k) ONE root key for every family: $keys6"
else
    no "(k) $nkeys6 distinct root keys for ONE root — a family outside the winning key is unpinnable:"
    find "$CD6" -mindepth 1 -maxdepth 2 -type f -name 'ripwire-*' 2>/dev/null | while IFS= read -r f; do
        printf '          %s  key=%s\n' "$( basename "$f" )" "$( blobrootkey "$f" )"
    done
fi

# the qchurn blob must carry the SAME key as the main parse cache, by name — the specific gap P1-1 stated.
lean6="$( find "$CD6" -mindepth 1 -maxdepth 2 -type f -name 'ripwire-*-lean.bin' 2>/dev/null | head -1 )"
churn6="$( find "$CD6" -mindepth 1 -maxdepth 2 -type f -name 'ripwire-qchurn-*' 2>/dev/null | head -1 )"
if [ -n "$lean6" ] && [ -n "$churn6" ]; then
    kl6="$( blobrootkey "$lean6" )"; kc6="$( blobrootkey "$churn6" )"
    [ -n "$kl6" ] && [ "$kl6" = "$kc6" ] && ok "(k) qchurn carries the main parse cache's root key ($kl6)" \
        || no "(k) qchurn key '$kc6' != lean key '$kl6' — the pin cannot reach it"
else
    no "(k) missing a lean or a qchurn blob to compare (lean='$lean6' churn='$churn6')"
fi

# ---- (l) trailing slash and a symlinked spelling of the SAME tree add no new key --------------------
ln -s "$R6" "$TMP6/link"
primeallfamilies "$CB6" "$R6/"
primeallfamilies "$CB6" "$TMP6/link"
keysl="$( allrootkeys "$CD6" )"
nkeysl="$( printf '%s\n' "$keysl" | grep -c . )"
[ "$nkeysl" -eq 1 ] && ok "(l) trailing-slash and symlinked spellings of one root keep ONE key ($keysl)" \
    || { no "(l) $nkeysl distinct root keys after re-priming through '\$R/' and a symlink — the key follows the SPELLING, not the tree:"; printf '          %s\n' $keysl; }

fi


[ "$fail" -eq 0 ] && echo "evictioncheck: ALL PASS" || { echo "evictioncheck: SOME CHECKS FAILED"; exit 1; }
