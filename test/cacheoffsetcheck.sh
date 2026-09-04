#!/usr/bin/env bash
# cacheoffsetcheck.sh — gate for the OFFSET-TABLE cache blob (format v15), the registered RETRY of
# "The auto-cache key ignores --exclude" (docs/EVALS.md, bands (1)-(8)).
#
# Background. The first attempt at that registration folded the exclude set into the auto-cache
# FILENAME (one blob per exclude configuration). It met its own five bands and was reverted anyway:
# with a 158K-file root and >= 12 gate configurations, the cache directory's 2 GiB cap evicted the
# blob a running gate was about to reuse and the battery went 7 min -> 62 min. That key change is a
# registered NEGATIVE and must never come back; `cacheexclkeycheck` is retired with a tombstone in
# test/regression.sh.
#
# The retry keeps ONE superset blob per (root, lean|rich) — the key stays exclude-INDEPENDENT — and
# makes a subset configuration cheap by shape instead of by key:
#   * the blob carries a record OFFSET TABLE (pathHash -> offset, length, contentHash, recordSum),
#     so a run deserialises ONLY the records for the files it actually crawled;
#   * a save carries over, byte for byte, the records for files the blob holds but this run did not
#     crawl — so an --exclude run never truncates the shared blob to its own subset, and a superset
#     run extends it instead of replacing it;
#   * the trailer checksum covers the header + the whole offset table; each table entry carries its
#     own record checksum, so "the checksum covers the table plus the records actually read".
#
# This gate exercises the AUTO path (main.cpp::defaultCachePath), never an explicit --cache=PATH.
# XDG_CACHE_HOME is redirected (TMPDIR unset) so blobs land in a directory we own. The fixture is a
# small synthetic tree with an excludable `ext/` subdir, so the gate is fast — the wall-clock numbers
# behind band (2) and band (6) are a bench/PROFILE.md ledger row, never a red gate here.
#
# Checks (band numbers are docs/EVALS.md's):
#   (a) BAND (8): plain + --exclude + --max-file-size configurations leave exactly ONE lean auto-cache
#       blob per root (two per root counting rich). This is the non-regression against the reverted
#       per-configuration key.
#   (b) BAND (1): `.` -> `. --exclude=ext` -> `.` reparses 0 files on the third run.
#   (c) BAND (7), subset-does-not-truncate: `.` -> edit one KEPT file -> `. --exclude=ext` (dirty, so
#       it saves) -> `.`. The third run must reparse NOTHING — the subset run wrote the edited file's
#       fresh record into the SHARED blob. Before the offset-table carry-over this reparsed 60.
#   (d) BAND (7), superset-extends: `. --exclude=ext` -> `.` -> edit one EXT file -> `.` ->
#       `. --exclude=ext`. The excluded run at the end must reparse 0 — the superset run extended the
#       blob without invalidating the excluded configuration's records.
#   (e) BAND (2) mechanism, structural (no wall clock): on a warm --exclude run over a 72-file blob the
#       tool deserialises only the 12 records it crawled. RIPWIRE_CACHE_STATS reports
#       `cached_records=12 blob_entries=72`.
#   (f) BAND (3): warm output byte-identical to --no-cache for BOTH configurations; determinism x2.
#   (g) TORN TRAILER: chopping the blob's trailer must produce a disclosed full reparse (72) whose
#       output still equals --no-cache — never a partial/garbage load.
#   (h) CORRUPT TABLE: flipping a byte inside the offset table is caught by the trailer checksum —
#       same self-healing full reparse.
#   (i) v14 REJECTION: a blob whose header version is 14 must be rejected and rebuilt (full reparse,
#       correct output), never misread as v15.
#   (j) EVICTION: the blob stays inside the family `sweepStaleCacheBlobsOnce` evicts, and the running
#       configuration's own blob (keepPath) survives.
#
# Usage:
#   bash test/cacheoffsetcheck.sh
#   RIPWIRE_BIN=build/ripwire bash test/cacheoffsetcheck.sh
#   bash test/cacheoffsetcheck.sh path/to/ripwire
#
# Exits non-zero on any failure; prints PASS/FAIL per check; prints ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"
mkdir -p "$REPO/keep" "$REPO/ext"

echo "cacheoffsetcheck: BIN=$BIN  TMP=$TMP"

# ── fixture: 12 kept translation units + 60 in an excludable subtree ──────────────────────────────
i=1
while [ "$i" -le 12 ]; do
    printf 'int keep_%d( int a )\n{\n    return a + %d;\n}\n' "$i" "$i" > "$REPO/keep/k$i.cpp"
    i=$(( i + 1 ))
done
i=1
while [ "$i" -le 60 ]; do
    printf 'int vend_%d( int a )\n{\n    return a * %d;\n}\n' "$i" "$i" > "$REPO/ext/v$i.cpp"
    i=$(( i + 1 ))
done

# One phase = one private XDG_CACHE_HOME, so phases never inherit each other's blobs.
XDGN=0
newphase(){
    XDGN=$(( XDGN + 1 ))
    XDG="$TMP/xdg$XDGN"
    CACHEDIR="$XDG/ripwire"
    mkdir -p "$CACHEDIR"
}
# Y4: a blob may sit flat under $CACHEDIR or in a 2-hex-char shard subdir — look at both.
leanblobs(){ find "$CACHEDIR" -maxdepth 2 -type f -name 'ripwire-*-lean.bin' 2>/dev/null | sort; }
nleanblobs(){ leanblobs | wc -l | tr -d ' '; }

# run the tool against the fixture with the phase's private cache dir; stdout to $1, stderr to $TMP/err.
run(){ local out="$1"; shift; env -u TMPDIR XDG_CACHE_HOME="$XDG" RIPWIRE_CACHE_STATS=1 "$BIN" "$REPO" "$@" >"$out" 2>"$TMP/err"; }
# observables of the LAST run, straight off the tool's own RIPWIRE_CACHE_STATS line
reparsed(){ sed -n 's/.*cache-stats reparsed=\([0-9][0-9]*\) .*/\1/p' "$TMP/err" | head -1; }
cachedrecs(){ sed -n 's/.*cached_records=\([0-9][0-9]*\).*/\1/p' "$TMP/err" | head -1; }
blobentries(){ sed -n 's/.*blob_entries=\([0-9][0-9]*\).*/\1/p' "$TMP/err" | head -1; }

# ── (a) BAND (8): the blob count per root stays at ONE lean blob across configurations ─────────────
newphase
run "$TMP/a1.xml"
run "$TMP/a2.xml" --exclude=ext
run "$TMP/a3.xml" --max-file-size=2K
N="$( nleanblobs )"
[ "$N" = "1" ] && ok "band (8): three exclude/size configurations share ONE lean auto-cache blob" \
    || no "band (8) VIOLATED: expected 1 lean auto-cache blob across three configurations, found $N"

# ── (b) BAND (1): . -> . --exclude=ext -> .  (third run reparses 0) ────────────────────────────────
newphase
run "$TMP/b1.xml"                                    # cold: parses the whole tree
R1="$( reparsed )"
[ "$R1" = "72" ] && ok "cold plain run parses the whole fixture (reparsed=$R1)" \
    || no "cold plain run reparsed=$R1, expected 72 — fixture or stat gate changed"
run "$TMP/b2.xml" --exclude=ext                      # excluded run
run "$TMP/b3.xml"                                    # plain again
R3="$( reparsed )"
[ "$R3" = "0" ] && ok "band (1): . -> . --exclude=ext -> . reparses 0 files on the third run" \
    || no "band (1) VIOLATED: third run reparsed=$R3, expected 0"

# ── (c) BAND (7): a DIRTY subset run must not truncate the superset blob ───────────────────────────
newphase
run "$TMP/c1.xml"                                    # cold plain: the un-excluded set is cached
printf 'int keep_1( int a )\n{\n    return a + 101;\n}\n' > "$REPO/keep/k1.cpp"   # one genuine edit
run "$TMP/c2.xml" --exclude=ext                      # dirty excluded run — it saves
RC2="$( reparsed )"
[ "$RC2" = "1" ] && ok "the excluded run reparses only the edited file (reparsed=$RC2) — it IS dirty, so it saves" \
    || no "excluded run reparsed=$RC2, expected 1 — the fixture edit did not make it dirty"
run "$TMP/c3.xml"                                    # plain again: the ext/ records must have survived
RC3="$( reparsed )"
# 0, not 1: the excluded run wrote a FRESH record for the file it reparsed into the SHARED blob, so the
# plain run finds every one of the 72 files current. (Under the reverted per-configuration key this was
# 1 — each configuration kept its own blob and the plain one still held the stale k1. Under the v14
# single blob with no carry-over it was 60 — the excluded run had deleted the ext/ records outright.)
[ "$RC3" = "0" ] && ok "band (7): after a dirty --exclude run the next plain run reparses nothing (reparsed=$RC3)" \
    || no "band (7) VIOLATED: plain-after-dirty-excluded reparsed=$RC3, expected 0 — the subset run truncated the shared blob"

# ── (d) BAND (7), the other direction: a superset run EXTENDS the blob ─────────────────────────────
newphase
run "$TMP/d1.xml" --exclude=ext                      # cold excluded: only the 12 kept files land in the blob
RD1="$( reparsed )"
[ "$RD1" = "12" ] && ok "cold --exclude run parses only the kept subtree (reparsed=$RD1)" \
    || no "cold --exclude run reparsed=$RD1, expected 12"
run "$TMP/d2.xml"                                    # plain: extends the blob with the 60 ext/ files
RD2="$( reparsed )"
[ "$RD2" = "60" ] && ok "the plain run parses only what the blob lacked (reparsed=$RD2) — the subset's records were reused" \
    || no "plain-after-excluded reparsed=$RD2, expected 60"
printf 'int vend_1( int a )\n{\n    return a * 101;\n}\n' > "$REPO/ext/v1.cpp"   # edit inside the excluded subtree
run "$TMP/d3.xml"                                    # plain: dirty, rewrites
RD3="$( reparsed )"
[ "$RD3" = "1" ] && ok "the dirty plain run reparses only the edited ext/ file (reparsed=$RD3)" \
    || no "dirty plain run reparsed=$RD3, expected 1"
run "$TMP/d4.xml" --exclude=ext                      # excluded: its own records must be intact
RD4="$( reparsed )"
[ "$RD4" = "0" ] && ok "band (7): a superset run extends the blob without invalidating the subset's records (reparsed=$RD4)" \
    || no "band (7) VIOLATED: --exclude-after-plain reparsed=$RD4, expected 0"

# ── (e) BAND (2) mechanism: a subset run deserialises only its own records ─────────────────────────
newphase
run "$TMP/e0.xml"                                    # cold plain: 72 records in the blob
run "$TMP/e1.xml" --exclude=ext                      # warm subset run over the superset blob
CR="$( cachedrecs )"; BE="$( blobentries )"
[ "$BE" = "72" ] && ok "the shared blob holds all 72 files (blob_entries=$BE)" \
    || no "blob_entries=${BE:-<absent>}, expected 72 — the offset table is missing or not reported"
[ "$CR" = "12" ] && ok "band (2): the warm --exclude run deserialises only its own 12 records (cached_records=$CR)" \
    || no "band (2) VIOLATED: cached_records=${CR:-<absent>}, expected 12 — the subset run deserialises the whole superset"
run "$TMP/e2.xml"                                    # warm plain run: reads the whole table
CR2="$( cachedrecs )"
[ "$CR2" = "72" ] && ok "the warm plain run deserialises all 72 records (cached_records=$CR2)" \
    || no "warm plain run cached_records=${CR2:-<absent>}, expected 72"

# ── (f) BAND (3): warm == --no-cache for BOTH configurations, and determinism x2 ───────────────────
newphase
run "$TMP/f_plain_cold.xml"
run "$TMP/f_plain_warm1.xml"
run "$TMP/f_plain_warm2.xml"
run "$TMP/f_excl_cold.xml" --exclude=ext
run "$TMP/f_excl_warm1.xml" --exclude=ext
run "$TMP/f_excl_warm2.xml" --exclude=ext
env -u TMPDIR XDG_CACHE_HOME="$XDG" "$BIN" "$REPO" --no-cache              > "$TMP/f_plain_nocache.xml" 2>/dev/null
env -u TMPDIR XDG_CACHE_HOME="$XDG" "$BIN" "$REPO" --no-cache --exclude=ext > "$TMP/f_excl_nocache.xml" 2>/dev/null

cmp -s "$TMP/f_plain_cold.xml" "$TMP/f_plain_warm1.xml" \
    && ok "band (3): cold == warm for the plain configuration" \
    || no "band (3) VIOLATED: cold and warm plain output differ"
cmp -s "$TMP/f_plain_warm1.xml" "$TMP/f_plain_nocache.xml" \
    && ok "band (3): warm plain output is byte-identical to --no-cache" \
    || no "band (3) VIOLATED: warm plain output differs from --no-cache"
cmp -s "$TMP/f_excl_warm1.xml" "$TMP/f_excl_nocache.xml" \
    && ok "band (3): warm --exclude output is byte-identical to --no-cache" \
    || no "band (3) VIOLATED: warm --exclude output differs from --no-cache"
cmp -s "$TMP/f_plain_warm1.xml" "$TMP/f_plain_warm2.xml" \
    && ok "band (3): plain warm run is deterministic (x2 byte-identical)" \
    || no "band (3) VIOLATED: two warm plain runs differ"
cmp -s "$TMP/f_excl_warm1.xml" "$TMP/f_excl_warm2.xml" \
    && ok "band (3): --exclude warm run is deterministic (x2 byte-identical)" \
    || no "band (3) VIOLATED: two warm --exclude runs differ"

# ── (g) TORN TRAILER: a chopped blob self-heals into a full reparse, never a partial load ──────────
newphase
run "$TMP/g1.xml"
BLOB="$( leanblobs | head -1 )"
[ -n "$BLOB" ] && ok "torn-write setup: the cold run wrote an auto-cache blob" \
    || no "torn-write setup: no auto-cache blob written"
if [ -n "$BLOB" ]; then
    SZ="$( wc -c < "$BLOB" | tr -d ' ' )"
    dd if="$BLOB" of="$BLOB.chop" bs=1 count=$(( SZ - 12 )) 2>/dev/null
    mv "$BLOB.chop" "$BLOB"
    run "$TMP/g2.xml"
    RG="$( reparsed )"
    [ "$RG" = "72" ] && ok "torn trailer: the truncated blob is rejected and the tree fully reparses (reparsed=$RG)" \
        || no "torn trailer: reparsed=$RG, expected 72 — a chopped blob was partially trusted"
    cmp -s "$TMP/g2.xml" "$TMP/f_plain_nocache.xml" \
        && ok "torn trailer: the rebuilt run's output equals --no-cache (no garbage survived the load)" \
        || no "torn trailer: output after a truncated blob differs from --no-cache"
fi

# ── (h) CORRUPT TABLE: a flipped byte inside the offset table is caught by the trailer checksum ────
newphase
run "$TMP/h1.xml"
BLOB="$( leanblobs | head -1 )"
if [ -n "$BLOB" ]; then
    SZ="$( wc -c < "$BLOB" | tr -d ' ' )"
    # the offset table sits immediately before the 24-byte trailer; poke a byte well inside it
    OFF=$(( SZ - 64 ))
    printf '\xa5' | dd of="$BLOB" bs=1 seek="$OFF" count=1 conv=notrunc 2>/dev/null
    run "$TMP/h2.xml"
    RH="$( reparsed )"
    [ "$RH" = "72" ] && ok "corrupt offset table: caught by the trailer checksum, full reparse (reparsed=$RH)" \
        || no "corrupt offset table: reparsed=$RH, expected 72 — a corrupt table was trusted"
    cmp -s "$TMP/h2.xml" "$TMP/f_plain_nocache.xml" \
        && ok "corrupt offset table: the rebuilt run's output equals --no-cache" \
        || no "corrupt offset table: output differs from --no-cache"
fi

# ── (i) v14 REJECTION: an old-format blob is rejected and rebuilt, never misread ───────────────────
newphase
run "$TMP/i1.xml"
BLOB="$( leanblobs | head -1 )"
if [ -n "$BLOB" ]; then
    printf '\x0e\x00\x00\x00' | dd of="$BLOB" bs=1 seek=4 count=4 conv=notrunc 2>/dev/null   # version u32 := 14
    run "$TMP/i2.xml"
    RI="$( reparsed )"
    [ "$RI" = "72" ] && ok "v14 blob: rejected by the version guard and rebuilt (reparsed=$RI)" \
        || no "v14 blob: reparsed=$RI, expected 72 — an old-format blob was not rejected"
    cmp -s "$TMP/i2.xml" "$TMP/f_plain_nocache.xml" \
        && ok "v14 blob: the rebuilt run's output equals --no-cache" \
        || no "v14 blob: output after a v14 blob differs from --no-cache"
    run "$TMP/i3.xml"
    RI3="$( reparsed )"
    [ "$RI3" = "0" ] && ok "v14 blob: the rebuilt v15 blob is warm on the next run (reparsed=$RI3)" \
        || no "v14 blob: the rebuild did not produce a warm-hitting blob (reparsed=$RI3, expected 0)"
fi

# ── (j) EVICTION: the blob stays inside the swept "ripwire-" family ────────────────────────────────
newphase
run "$TMP/j1.xml" --exclude=ext
MINE="$( leanblobs | head -1 )"
[ -n "$MINE" ] && ok "eviction setup: the --exclude run wrote an auto-cache blob ($( basename "${MINE:-none}" ))" \
    || no "eviction setup: no auto-cache blob written by the --exclude run"
if [ -n "$MINE" ]; then
    # a FOREIGN root's blob (same family, different root hash), back-dated past the 30-day cutoff
    FOREIGN="$( dirname "$MINE" )/ripwire-00000000deadbeef-lean.bin"
    cp "$MINE" "$FOREIGN"
    touch -t 202001010000 "$FOREIGN"
    printf 'int keep_new( int a )\n{\n    return a - 1;\n}\n' > "$REPO/keep/knew.cpp"   # make the next run dirty
    run "$TMP/j2.xml"
    [ ! -e "$FOREIGN" ] && ok "eviction: a >30-day-old blob of the same family is swept — the v15 shape is still inside it" \
        || no "eviction: the stale blob survived — the v15 blob shape fell outside the swept ripwire-* family"
    [ -e "$MINE" ] && ok "eviction: the running configuration's own blob survives the sweep (keepPath honored)" \
        || no "eviction: the running configuration's own blob was swept"
    rm -f "$REPO/keep/knew.cpp"
fi

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILURES above"; exit 1; }
