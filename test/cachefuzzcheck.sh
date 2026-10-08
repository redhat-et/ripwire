#!/usr/bin/env bash
# cachefuzzcheck.sh — standing loadCache / readQSnapBlob fuzz harness (-era open item).
#
# Contract under test: NO hostile/corrupt/truncated cache blob can crash, hang, over-read, or poison
# output. loadCache (src/ingest.cpp, --cache=FILE v8 blob) and the qsnap reader (readQSnapBlob +
# deserializeSnapshot, src/quality.h, --quality-delta's HEAD-Snapshot sidecar) must both DEGRADE to a
# clean cold parse / clean recompute on any malformed input — never a wrong answer, never a crash.
#
# Route: this drives the PUBLIC ingest() entry point via the CLI (--cache=FILE with a doctored file on
# disk) rather than calling loadCache directly from a standalone driver — the more honest end-to-end
# fuzz (the real attack surface is "an agent/CI hands ripwire a cache file it doesn't fully trust"),
# and it means this harness needed NO changes to src/ingest.h / src/ingest.cpp / src/quality.h.
#
# ── Part 1: v15 ingest-cache blob (loadCache) — DETERMINISTIC structured mutation table ────────────
# Blob layout (native-endian, no padding — mirrors ingest_cache.h saveCache/openCacheFrame/loadCache):
#   HEADER, 25 B:
#     [0:4)   u32 magic "CTPK"        [4:8)   u32 version (kCacheVersion)
#     [8:12)  u32 parserVer           [12]    u8  kArtifactArch (endian|pointerWidth<<1)
#     [13:21) u64 blobWriteNs         [21:25) u32 entryCount
#   RECORDS, [25, tableOffset), ascending pathHash:
#     u32 pathLen, pathBytes, u64 contentHash, u64 sizeBytes, u64 mtimeNs, u64 ctimeNs,
#     4x u32 FileHealth, [rich: u32 dictCount + dict], u32 defCount, [def records], ...
#   OFFSET TABLE, entryCount x 32 B at tableOffset:
#     u64 pathHash, u64 recOffset, u64 contentHash, u32 recLength, u32 recSum
#   TRAILER, last 24 B: u64 tableOffset, u32 entryCount, u32 reserved, u64 tableSum
#   tableSum covers HEADER || TABLE; each recSum covers exactly its own record.
# A python helper (mirroring that byte-exact layout) generates ~26 named byte-level mutations from one
# good baseline blob; bash then layers 5 more filesystem-shape mutations (dir/perm/symlink//dev/null)
# on top. Each mutation is applied via a FIXED table, not a random seed (determinism rule): re-running
# this script produces the exact same mutated bytes every time.
#
# WHY THE HELPER REBUILDS THE FRAME. A mutation that leaves a STALE frame stops at the very first
# guard, and every deeper guard it was written for then passes for the wrong reason — the "green while
# inert" failure CONTRIBUTING §2 names. So `with_recomputed_trailer` recomputes every record's recSum
# from the mutated bytes and rewrites a consistent trailer, which is what lets a huge def count, an
# absurd string length or a garbage record body actually REACH readFileRecord. The mutations that are
# deliberately about the frame itself (arch_byte_flip_stale, checksum_mismatch_deep_bitflip_stale,
# trailer_bytes_corrupted, table_offset_past_eof, trailer_entry_count_inflated) leave it stale on
# purpose, and each names which layer it is aimed at.
#
# Each mutation is run under the DEV binary and must: exit 0, and produce output BYTE-IDENTICAL to a
# `--no-cache` cold parse (the POISON check — a malformed cache must never silently change the answer,
# only ever cost the speed win). stderr must be bounded (no infinite alert spew). The full table is then
# re-run once under the ASan binary (asserting no sanitizer report fired).
#
# ── Part 2: qsnap blob (readQSnapBlob / deserializeSnapshot) — smaller mutation table ──────────────
# qsnapcachecheck.sh already gates ONE corrupt-blob case (magic replaced by garbage). This part extends
# coverage (truncation at every field boundary, scheme/sha mismatch, huge counts, checksum-valid
# garbage payload, filesystem-shape cases) without duplicating that existing check. Ground truth is a
# `--quality-delta --no-cache`-equivalent run with the qsnap blob deleted; every mutation must degrade
# to the SAME byte-identical output.
#
# ── Part 2's huge-count arms, and why they run under a bounded allocator ──────────────────────────────
# A checksum-valid qsnap blob whose vector count reads 0xFFFFFFFF used to reach `reserve` straight from the
# blob: 32 GiB for a u64 vector. Linux (no overcommit for that size) threw std::bad_alloc, which nothing on
# the CLI path catches — SIGABRT (134) on every run until the blob was evicted, reproduced on Ubuntu. The
# macOS allocator overcommits the reservation and never touches it, so a plain macOS run of the same blob
# exits 0 against the defect. The arms therefore run the huge-count mutations under a BOUND that turns the
# reservation into the failure a small host would see: `ulimit -v` for a plain Linux binary, and ASan's
# max_allocation_size_mb for an instrumented binary on any platform (the ASan sweep below carries it for
# every mutation). A plain macOS binary has no such bound, and the arm says so rather than passing blind.
# The layout offsets (magic 4, scheme 4, cacheVer 4, parserVer 4, producer 8, sha 8, then the ten field counts from
# byte 32) are the ones deserializeSnapshot reads; the map-count and sha arms used to write at 16 and 8,
# which a guard ahead of the one they were written for rejected first.
#
# ── Part 3: one out-of-range ENUM byte per field class in a checksum-valid ingest record (see its header below).
# ── Part 4: a span-tier memo (ripwire-stier-*) tier byte past SpanTier — a blob with no checksum at all.
# ── Part 5: qchurn blob (deserializeRawCommitStream) — the same huge-count rows for the churn memo ────────
#
# Usage:
#   bash test/cachefuzzcheck.sh
#   RIPWIRE_BIN=build/ripwire RIPWIRE_ASAN_BIN=asan/ripwire bash test/cachefuzzcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check; ALL PASS on success. Does not edit
# regression.sh (regression.sh wires this in itself, once, if git status was clean when this was built).

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
ASAN_BIN="${RIPWIRE_ASAN_BIN:-$ROOT/asan/ripwire}"
[ "${ASAN_BIN#/}" = "$ASAN_BIN" ] && ASAN_BIN="$ROOT/$ASAN_BIN"
FIXTURE="$ROOT/test/fixture"
TMP="$( mktemp -d )"; trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
note(){ printf '  NOTE  %s\n' "$*"; }
skip(){ printf '  SKIP  %s\n' "$*"; }   # an ABSENT PRECONDITION with a named reason — never a silent pass

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIXTURE" ] || { echo "no fixture at $FIXTURE"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }

echo "cachefuzzcheck: BIN=$BIN  ASAN_BIN=$ASAN_BIN  FIXTURE=$FIXTURE  TMP=$TMP"

# stderr sanity bound: a degrade path emits at most a small, fixed number of alert lines — never
# unbounded spew (e.g. one alert per corrupt record in a loop).
STDERR_LINE_CAP=200
STDERR_BYTE_CAP=20000
stderr_sane(){
    local f="$1" lines bytes
    lines="$( wc -l < "$f" | tr -d ' ' )"
    bytes="$( wc -c < "$f" | tr -d ' ' )"
    [ "$lines" -le "$STDERR_LINE_CAP" ] && [ "$bytes" -le "$STDERR_BYTE_CAP" ]
}

# The allocation bound the huge-count arms run under (header): which one `$1`'s build can take, or empty.
bound_mode_of(){
    if LC_ALL=C grep -q -a '__asan_init' "$1" 2>/dev/null; then echo asan
    elif [ "$( uname -s )" = "Linux" ]; then echo ulimit
    fi
}
# Run "$@" under bound mode $1. An address-space limit that cannot be set exits 97, so the caller reports a
# skip instead of a pass that ran unbounded.
bounded(){
    local mode="$1"; shift
    case "$mode" in
        asan)   ASAN_OPTIONS="${ASAN_OPTIONS:+$ASAN_OPTIONS:}max_allocation_size_mb=1024" "$@" ;;
        ulimit) ( ulimit -v 8388608 2>/dev/null || exit 97; "$@" ) ;;
        *)      "$@" ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# PART 1 — v8 ingest-cache blob (loadCache)
# ═══════════════════════════════════════════════════════════════════════════════════════════════════

# ground truth: a pure cold parse, cache-independent.
"$BIN" "$FIXTURE" --no-cache --no-stable >"$TMP/truth.xml" 2>/dev/null
[ -s "$TMP/truth.xml" ] || { echo "cold parse of fixture produced no output — cannot proceed"; exit 2; }

# a good, warm v8 cache blob — the mutation baseline.
GOOD="$TMP/good.cache"
"$BIN" "$FIXTURE" --cache="$GOOD" --no-stable >"$TMP/good_out.xml" 2>/dev/null
[ -s "$GOOD" ] || { echo "failed to build a baseline cache blob"; exit 2; }
diff -q "$TMP/truth.xml" "$TMP/good_out.xml" >/dev/null \
    && ok "sanity: cold build of the good cache produces the same output as --no-cache" \
    || { echo "baseline cache build already diverges from cold — cannot trust the harness"; exit 2; }

MUTDIR="$TMP/mutations"; mkdir -p "$MUTDIR"

# ── the byte-level mutation table (python — mirrors loadCache's exact layout; deterministic, no RNG
#    seed used for anything that affects correctness-relevant bytes; the one "garbage payload" mutation
#    uses a FIXED xorshift-style deterministic byte pattern, not a random seed) ─────────────────────────
python3 - "$GOOD" "$MUTDIR" <<'PYEOF'
import struct, sys

good_path, outdir = sys.argv[1], sys.argv[2]
with open(good_path, "rb") as f:
    good = bytearray(f.read())

def blob_checksum(data: bytes) -> int:
    # mirrors ingest.cpp blobChecksum(): 8-lane FNV-1a64 permutation over 8-byte strides.
    P = 1099511628211
    M = (1 << 64) - 1
    lane = [1469598103934665603, 1099511628211, 0x100000001b3, 0x9e3779b97f4a7c15,
            0xc2b2ae3d27d4eb4f, 0x165667b19e3779f9, 0xff51afd7ed558ccd, 0xc4ceb9fe1a85ec53]
    n = len(data); i = 0
    while i + 8 <= n:
        for k in range(8):
            lane[k] = ((lane[k] ^ data[i + k]) * P) & M
        i += 8
    k = 0
    while i < n:
        lane[k] = ((lane[k] ^ data[i]) * P) & M
        i += 1; k += 1
    h = 1469598103934665603
    for k in range(8):
        h = ((h ^ lane[k]) * P) & M
    return h

HDR      = 25   # header bytes: magic4 + ver4 + parserVer4 + arch1 + blobWriteNs8 + entryCount4
TRAILER  = 24   # trailer bytes: tableOffset8 + entryCount4 + reserved4 + tableSum8
ENTRY    = 32   # offset-table row: pathHash8 + recOffset8 + contentHash8 + recLength4 + recSum4

TABLE_OFF, TABLE_N = struct.unpack_from("<QI", good, len(good) - TRAILER)[0:2]
payload_len = len(good) - TRAILER   # everything before the trailer: records + offset table

def with_recomputed_trailer(payload: bytearray) -> bytes:
    """`payload` is records+table (everything before the trailer). Recompute every record's recSum from
    payload's CURRENT bytes and append a fresh, self-consistent v15 trailer — so a mutation reaches the
    guard it is aimed at instead of being stopped by a stale frame (see the WHY note in the header)."""
    b = bytearray(payload)
    for i in range(TABLE_N):
        off = TABLE_OFF + i * ENTRY
        if off + ENTRY > len(b):
            break
        rec_off = struct.unpack_from("<Q", b, off + 8)[0]
        rec_len = struct.unpack_from("<I", b, off + 24)[0]
        if rec_off + rec_len <= TABLE_OFF and rec_off + rec_len <= len(b):
            struct.pack_into("<I", b, off + 28, blob_checksum(bytes(b[rec_off:rec_off + rec_len])) & 0xFFFFFFFF)
    tbl = bytes(b[:HDR]) + bytes(b[TABLE_OFF:TABLE_OFF + TABLE_N * ENTRY])
    return bytes(b) + struct.pack("<QIIQ", TABLE_OFF, TABLE_N, 0, blob_checksum(tbl))

# ── locate the fixed-offset fields in the FIRST record (records start immediately after the header;
#    v15 writes them in ascending pathHash order, so record[0] is simply the lowest-hashing file) ────
path_len  = struct.unpack_from("<I", good, HDR)[0]
path_off  = HDR + 4
hash_off  = path_off + path_len
size_off  = hash_off + 8
mtime_off = size_off + 8
ctime_off = mtime_off + 8
nd_off    = ctime_off + 8 + 20   # past ctimeNs and the five FileHealth u32s (v20 added macroBlanked): the LEAN def-record count

mutations = {}

# -- truncation at various boundaries --
mutations["truncate_empty_within_header"]      = lambda b: bytes(b[:2])
mutations["truncate_before_arch_byte"]          = lambda b: bytes(b[:12])
mutations["truncate_before_filecount"]          = lambda b: bytes(b[:21])
mutations["truncate_mid_first_record"]          = lambda b: bytes(b[:size_off + 3])
mutations["truncate_trailer_partial"]           = lambda b: bytes(b[:-4])
mutations["truncate_one_byte_before_trailer"]   = lambda b: bytes(b[:payload_len - 1])

# -- header field corruption, checksum RECOMPUTED (isolates the deeper guard being tested) --
def mut_zero_magic(b):
    p = bytearray(b[:payload_len]); struct.pack_into("<I", p, 0, 0); return with_recomputed_trailer(p)
mutations["zero_magic_recomputed_checksum"] = mut_zero_magic

def mut_flip_magic_bit(b):
    p = bytearray(b[:payload_len]); p[0] ^= 0x01; return with_recomputed_trailer(p)
mutations["flip_magic_bit_recomputed_checksum"] = mut_flip_magic_bit

def mut_version_inc(b):
    p = bytearray(b[:payload_len]); v = struct.unpack_from("<I", p, 4)[0]; struct.pack_into("<I", p, 4, v + 1); return with_recomputed_trailer(p)
mutations["version_increment_recomputed_checksum"] = mut_version_inc

def mut_version_dec(b):
    p = bytearray(b[:payload_len]); v = struct.unpack_from("<I", p, 4)[0]; struct.pack_into("<I", p, 4, v - 1); return with_recomputed_trailer(p)
mutations["version_decrement_recomputed_checksum"] = mut_version_dec

def mut_version_zero(b):
    p = bytearray(b[:payload_len]); struct.pack_into("<I", p, 4, 0); return with_recomputed_trailer(p)
mutations["version_zero_recomputed_checksum"] = mut_version_zero

def mut_arch_flip_fixed(b):
    p = bytearray(b[:payload_len]); p[12] ^= 0x01; return with_recomputed_trailer(p)
mutations["arch_byte_flip_recomputed_checksum"] = mut_arch_flip_fixed

def mut_arch_flip_stale(b):
    p = bytearray(b); p[12] ^= 0x01        # the trailer's tableSum covers the header, so it is now stale
    return bytes(p)
mutations["arch_byte_flip_stale_checksum"] = mut_arch_flip_stale

# -- huge / overflow / negative record counts and length fields --
def mut_huge_filecount(b):
    p = bytearray(b[:payload_len]); struct.pack_into("<I", p, 21, 0xFFFFFFFE); return with_recomputed_trailer(p)
mutations["huge_file_count_recomputed_checksum"] = mut_huge_filecount

def mut_zero_filecount(b):
    p = bytearray(b[:payload_len]); struct.pack_into("<I", p, 21, 0); return with_recomputed_trailer(p)
mutations["zero_file_count_recomputed_checksum"] = mut_zero_filecount

def mut_huge_defcount(b):
    p = bytearray(b[:payload_len]); struct.pack_into("<I", p, nd_off, 0xFFFFFFF0); return with_recomputed_trailer(p)
mutations["huge_def_count_recomputed_checksum"] = mut_huge_defcount

def mut_overflow_size(b):
    p = bytearray(b[:payload_len]); struct.pack_into("<Q", p, size_off, 0xFFFFFFFFFFFFFFFF); return with_recomputed_trailer(p)
mutations["overflow_size_field_recomputed_checksum"] = mut_overflow_size

def mut_negative_size(b):
    p = bytearray(b[:payload_len]); struct.pack_into("<Q", p, size_off, 0x8000000000000000); return with_recomputed_trailer(p)
mutations["negative_size_field_recomputed_checksum"] = mut_negative_size

def mut_maxed_mtime(b):
    p = bytearray(b[:payload_len]); struct.pack_into("<Q", p, mtime_off, 0xFFFFFFFFFFFFFFFF); return with_recomputed_trailer(p)
mutations["maxed_mtime_field_recomputed_checksum"] = mut_maxed_mtime

def mut_string_len_exceeds(b):
    p = bytearray(b[:payload_len]); struct.pack_into("<I", p, HDR, 0x7FFFFFFF); return with_recomputed_trailer(p)
mutations["string_length_exceeds_blob_recomputed_checksum"] = mut_string_len_exceeds

def mut_string_len_wraparound(b):
    p = bytearray(b[:payload_len]); struct.pack_into("<I", p, HDR, 0xFFFFFFFF); return with_recomputed_trailer(p)
mutations["string_length_wraparound_recomputed_checksum"] = mut_string_len_wraparound

# -- checksum-valid-but-garbage-payload: corrupt a wide swath of the body with a FIXED (non-random)
#    deterministic byte pattern, then recompute the trailer over the corrupted body. --
def mut_garbage_payload(b):
    # the RECORD region only, with a rebuilt frame: every record digest matches, so each record is
    # actually handed to readFileRecord and every one of its guards is what has to refuse it.
    p = bytearray(b[:payload_len])
    x = 0x2545F4914F6CDD1D & 0xFF
    for i in range(min(HDR + 8, TABLE_OFF), TABLE_OFF):
        x = (x * 1103515245 + 12345) & 0xFF
        p[i] = x
    return with_recomputed_trailer(p)
mutations["checksum_valid_garbage_payload"] = mut_garbage_payload

def mut_garbage_table(b):
    # the OFFSET TABLE, trailer left stale: caught by tableSum, which is the guard that has to hold
    # before any record offset in it is believed.
    p = bytearray(b)
    x = 0x9E3779B9 & 0xFF
    for i in range(TABLE_OFF, TABLE_OFF + TABLE_N * ENTRY):
        x = (x * 1103515245 + 12345) & 0xFF
        p[i] = x
    return bytes(p)
mutations["garbage_offset_table_stale_checksum"] = mut_garbage_table

def mut_table_offset_past_eof(b):
    # the trailer says the table starts past the end of the file: the EXACT-FIT invariant refuses it.
    p = bytearray(b)
    struct.pack_into("<Q", p, len(p) - TRAILER, len(p) + 4096)
    return bytes(p)
mutations["table_offset_past_eof"] = mut_table_offset_past_eof

def mut_trailer_entry_count_inflated(b):
    # trailer entryCount disagrees with the header's AND with the file size — both cross-checks fire.
    p = bytearray(b)
    struct.pack_into("<I", p, len(p) - TRAILER + 8, TABLE_N + 1000)
    return bytes(p)
mutations["trailer_entry_count_inflated"] = mut_trailer_entry_count_inflated

def mut_record_offset_inside_table(b):
    # a table entry whose record range reaches into the table itself — refused by the per-entry bounds
    # check, not by any checksum (the frame is rebuilt so the digests all agree).
    p = bytearray(b[:payload_len])
    struct.pack_into("<Q", p, TABLE_OFF + 8, TABLE_OFF)
    struct.pack_into("<I", p, TABLE_OFF + 24, 64)
    return with_recomputed_trailer(p)
mutations["record_range_overlaps_table"] = mut_record_offset_inside_table

def mut_table_offset_near_u64_max(b):
    # a trailer naming a table offset one short of 2^64. The exact-fit check refused it, but through
    # `tableOffset + entries + trailer`, a sum that wraps — which the G1 sanitizer build's -fsanitize=integer aborts on.
    # Found by the reader fuzzer (test/fuzz/readers, reader ingestframe); the check is now written without the wrap.
    p = bytearray(b)
    struct.pack_into("<Q", p, len(p) - TRAILER, (1 << 64) - 1)
    return bytes(p)
mutations["table_offset_near_u64_max"] = mut_table_offset_near_u64_max

def mut_record_offset_near_u64_max(b):
    # a table entry whose record offset is 16 short of 2^64 with a 64-byte length: `recOffset + recLength` wrapped to 48,
    # which is below the table offset, so the per-entry bound ACCEPTED the entry. The frame is rebuilt so every digest
    # agrees; only a wrap-free bound can refuse it.
    p = bytearray(b[:payload_len])
    struct.pack_into("<Q", p, TABLE_OFF + 8, (1 << 64) - 16)
    struct.pack_into("<I", p, TABLE_OFF + 24, 64)
    return with_recomputed_trailer(p)
mutations["record_offset_near_u64_max"] = mut_record_offset_near_u64_max

# -- checksum mismatch only: a single deep bit flip, checksum left STALE (the shallowest guard alone) --
def mut_deep_bitflip_stale(b):
    # inside record[0], leaving BOTH digests stale: the table is untouched so tableSum still verifies,
    # and the flip must be caught by that record's own recSum instead (the per-record guard).
    p = bytearray(b)
    p[min(HDR + 20, TABLE_OFF - 1)] ^= 0xFF
    return bytes(p)
mutations["checksum_mismatch_deep_bitflip_stale"] = mut_deep_bitflip_stale

# -- trailer itself corrupted, payload untouched (hits tableSum directly) --
def mut_trailer_corrupted(b):
    p = bytearray(b)
    p[-1] ^= 0xFF
    return bytes(p)
mutations["trailer_bytes_corrupted"] = mut_trailer_corrupted

# -- empty file --
mutations["empty_file"] = lambda b: b""

names = []
for name, fn in mutations.items():
    data = fn(good)
    path = outdir + "/" + name + ".cache"
    with open(path, "wb") as f:
        f.write(data)
    names.append(name)

print("\n".join(sorted(names)))
PYEOF

MUT_NAMES=( $( ls "$MUTDIR" | sed 's/\.cache$//' | sort ) )
echo
echo "=== Part 1: v8 ingest-cache mutation table (${#MUT_NAMES[@]} byte-level + filesystem-shape cases) — DEV build ==="

run_one_dev(){
    local name="$1" cachefile="$2"
    local out="$TMP/dev_${name}.xml" err="$TMP/dev_${name}.err"
    "$BIN" "$FIXTURE" --cache="$cachefile" --no-stable >"$out" 2>"$err"
    local rc=$?
    if [ "$rc" -ge 128 ]; then
        no "[$name] CRASH — exit $rc (signal $(( rc - 128 )))"
        return
    fi
    if [ "$rc" -ne 0 ]; then
        no "[$name] nonzero exit ($rc) on a cache-only corruption — should degrade to exit 0"
        return
    fi
    if ! diff -q "$TMP/truth.xml" "$out" >/dev/null 2>&1; then
        no "[$name] OUTPUT POISONED by corrupt cache — differs from --no-cache ground truth"
        diff "$TMP/truth.xml" "$out" | head -4
        return
    fi
    if ! stderr_sane "$err"; then
        no "[$name] stderr not bounded ($(wc -l <"$err") lines / $(wc -c <"$err") bytes) — possible spew loop"
        return
    fi
    ok "[$name] exit 0, output byte-identical to cold, stderr bounded"
}

for name in "${MUT_NAMES[@]}"; do
    run_one_dev "$name" "$MUTDIR/$name.cache"
done

# ── filesystem-shape mutations (not byte content — the cache PATH itself is hostile) ────────────────
echo
echo "=== filesystem-shape cache-path mutations — DEV build ==="

# /dev/null-sized: point --cache directly at /dev/null (reads as empty; writes are discarded).
run_one_dev "devnull_cache_path" "/dev/null"

# a DIRECTORY sits at the cache path instead of a file. 2026-09-06 (stranger audit): this used to be "degrade to
# exit 0" — read as corrupt, write refused, a byte-identical map served — the fixed --cache=<nonexistent dir>
# bug's twin. --cache names a FILE; a directory is a usage error and is REFUSED (exit 1) naming the flag, the
# problem and an accepted form, same as the nonexistent-directory refusal beside it in main.cpp.
DIRPATH="$TMP/dir_as_cache"
mkdir -p "$DIRPATH"
"$BIN" "$FIXTURE" --cache="$DIRPATH" --no-stable >"$TMP/dev_dircache.xml" 2>"$TMP/dev_dircache.err"
rc_dir=$?
if [ "$rc_dir" -eq 1 ] && grep -q -- '--cache=.*is a directory' "$TMP/dev_dircache.err" && grep -q 'e\.g\. --cache=' "$TMP/dev_dircache.err"; then
    ok "[directory_at_cache_path] refused: exit 1, names --cache, the problem and an example path"
else
    no "[directory_at_cache_path] expected a refusal (exit 1 naming --cache); got exit $rc_dir, stderr: $(head -c 300 "$TMP/dev_dircache.err")"
fi
if [ ! -s "$TMP/dev_dircache.xml" ]; then
    ok "[directory_at_cache_path] no map served on the refusal"
else
    no "[directory_at_cache_path] a map was served alongside the refusal"
fi

# unreadable permissions on an otherwise-good cache file (skip cleanly if running as root, where
# chmod 000 does not actually block reads).
UNREAD="$TMP/unreadable.cache"
cp "$GOOD" "$UNREAD"
chmod 000 "$UNREAD"
if [ "$( id -u )" = "0" ]; then
    note "[unreadable_cache_permissions] running as root — chmod 000 does not block reads, skipping"
else
    run_one_dev "unreadable_cache_permissions" "$UNREAD"
fi
chmod 644 "$UNREAD"

# symlink to a VALID good cache — must still warm-hit correctly (not a corruption case, a sanity check
# that the harness's file-target mutations don't accidentally break the happy path).
SYMGOOD="$TMP/symlink_to_good.cache"
ln -sf "$GOOD" "$SYMGOOD"
run_one_dev "symlink_to_valid_cache" "$SYMGOOD"

# dangling symlink (target does not exist) — must degrade like a missing file.
SYMDANGLE="$TMP/symlink_dangling.cache"
ln -sf "$TMP/does_not_exist_$$" "$SYMDANGLE"
run_one_dev "symlink_dangling" "$SYMDANGLE"

# ── disclosure (2026-09-06 stranger audit): a Release binary keeps NO DISCLOSE, so every reject
#    above used to be byte-identical to a healthy run — a torn blob, an older binary's blob, a full disk: all
#    silent, every run. The map stays byte-identical (arms above); stderr now says what happened, once. The
#    ordinary cold-start miss stays silent, and a good cache says nothing (the controls). ──
echo
echo "=== disclosure: a rejected cache says so on stderr; a good or absent one does not ==="
# fresh mutants: every rejected cache Part 1 ran against was REWRITTEN as a good one by that very run (the
# self-heal this arm is about), so the files under $MUTDIR are healthy by now. Cut two new ones from $GOOD.
DISCDIR="$TMP/disclose"; mkdir -p "$DISCDIR"
# XOR the last byte, as Part 1's mut_trailer_corrupted does — never WRITE a constant: on the one CI leg
# (macos-14 Release, run 34090630725) where that byte already was 0xFF, a constant left the mutant equal to
# the good cache, nothing was rejected, and this arm reported "no disclosure" about a cache that was fine.
python3 - "$GOOD" "$DISCDIR/trailer_bytes_corrupted.cache" <<'PYMUT'
import sys
b = bytearray( open( sys.argv[1], "rb" ).read() )
b[-1] ^= 0xFF
open( sys.argv[2], "wb" ).write( bytes( b ) )
PYMUT
: >"$DISCDIR/empty_file.cache"
for dname in trailer_bytes_corrupted empty_file; do
    "$BIN" "$FIXTURE" --cache="$DISCDIR/$dname.cache" --no-stable >/dev/null 2>"$TMP/disc_$dname.err"
    if grep -q "ripwire: cache .*$dname.cache: [a-z-]* — not used" "$TMP/disc_$dname.err"; then
        ok "[disclose:$dname] stderr names the cache file and the reject reason"
    else
        no "[disclose:$dname] no disclosure on stderr for a rejected cache: $(head -c 200 "$TMP/disc_$dname.err")"
    fi
done
# A record offset near 2^64 is a CORRUPT FRAME, refused whole — not a table entry whose read fails later. The per-entry
# bound was `recOffset + recLength > tableOffset`; at recOffset = 2^64-16, recLength = 64 the sum wrapped to 48 and the
# entry was accepted (blob_entries=6, one "read failed mid-load" reparse). Its control is the non-wrapping twin already in
# the table, a record range reaching into the table, which both forms refuse. Cut fresh from $GOOD like the two above.
python3 - "$GOOD" "$DISCDIR" <<'PYWRAP'
import struct, sys
good, outdir = sys.argv[1], sys.argv[2]
b = open(good, "rb").read()
TABLE_OFF, N = struct.unpack_from("<QI", b, len(b) - 24)[0:2]
def blob_checksum(data):
    P, M = 1099511628211, (1 << 64) - 1
    lane = [1469598103934665603, 1099511628211, 0x100000001b3, 0x9e3779b97f4a7c15,
            0xc2b2ae3d27d4eb4f, 0x165667b19e3779f9, 0xff51afd7ed558ccd, 0xc4ceb9fe1a85ec53]
    k8 = len(data) - len(data) % 8
    for i in range(0, k8, 8):
        for k in range(8):
            lane[k] = ((lane[k] ^ data[i + k]) * P) & M
    for k, i in enumerate(range(k8, len(data))):
        lane[k] = ((lane[k] ^ data[i]) * P) & M
    h = 1469598103934665603
    for k in range(8):
        h = ((h ^ lane[k]) * P) & M
    return h
for name, off in (("record_offset_near_u64_max", (1 << 64) - 16), ("record_range_overlaps_table", TABLE_OFF)):
    p = bytearray(b[:len(b) - 24])
    struct.pack_into("<Q", p, TABLE_OFF + 8, off)
    struct.pack_into("<I", p, TABLE_OFF + 24, 64)
    tbl = bytes(p[:25]) + bytes(p[TABLE_OFF:TABLE_OFF + N * 32])
    open("%s/%s.cache" % (outdir, name), "wb").write(bytes(p) + struct.pack("<QIIQ", TABLE_OFF, N, 0, blob_checksum(tbl)))
PYWRAP
for dname in record_range_overlaps_table record_offset_near_u64_max; do
    RIPWIRE_CACHE_STATS=1 "$BIN" "$FIXTURE" --cache="$DISCDIR/$dname.cache" --no-stable >/dev/null 2>"$TMP/disc_$dname.err"
    if grep -q "ripwire: cache .*$dname.cache: corrupt-frame — not used" "$TMP/disc_$dname.err" && grep -q 'blob_entries=0' "$TMP/disc_$dname.err"; then
        ok "[disclose:$dname] refused whole as corrupt-frame (blob_entries=0), never read entry by entry"
    else
        no "[disclose:$dname] expected a corrupt-frame refusal with blob_entries=0, got: $( grep -E 'ripwire: cache|cache-stats' "$TMP/disc_$dname.err" | tr '\n' ' ' | cut -c1-220 )"
    fi
done
"$BIN" "$FIXTURE" --cache="$GOOD" --no-stable >/dev/null 2>"$TMP/disc_good.err"
if grep -q 'ripwire: cache' "$TMP/disc_good.err"; then
    no "[disclose:control] a GOOD cache produced a cache notice: $(head -c 200 "$TMP/disc_good.err")"
else
    ok "[disclose:control] a good cache is silent"
fi
"$BIN" "$FIXTURE" --cache="$TMP/absent_$$.cache" --no-stable >/dev/null 2>"$TMP/disc_absent.err"
if grep -q 'ripwire: cache' "$TMP/disc_absent.err"; then
    no "[disclose:control] an ABSENT cache (the ordinary cold start) produced a notice: $(head -c 200 "$TMP/disc_absent.err")"
else
    ok "[disclose:control] an absent cache (cold start) is silent"
fi
rm -f "$TMP/absent_$$.cache"
if [ "$( id -u )" = "0" ]; then
    note "[disclose:unwritable] running as root — chmod 500 does not block writes, skipping"
else
    RODIR="$TMP/ro_cache_dir"; mkdir -p "$RODIR"; chmod 500 "$RODIR"
    "$BIN" "$FIXTURE" --cache="$RODIR/c.cache" --no-stable >"$TMP/disc_ro.xml" 2>"$TMP/disc_ro.err"
    rc_ro=$?
    chmod 700 "$RODIR"
    if [ "$rc_ro" -eq 0 ] && grep -q 'ripwire: cache .*cannot write' "$TMP/disc_ro.err" && diff -q "$TMP/truth.xml" "$TMP/disc_ro.xml" >/dev/null 2>&1; then
        ok "[disclose:unwritable] an unwritable cache dir: map served (exit 0, ground truth), stderr says it cannot write"
    else
        no "[disclose:unwritable] expected exit 0 + a 'cannot write' notice; got exit $rc_ro, stderr: $(head -c 200 "$TMP/disc_ro.err")"
    fi
fi

echo
echo "=== Part 1: same mutation table — ASan build ==="
if [ -x "$ASAN_BIN" ]; then
    asan_fail=0
    run_one_asan(){
        local name="$1" cachefile="$2"
        local out="$TMP/asan_${name}.xml" err="$TMP/asan_${name}.err"
        ASAN_OPTIONS="halt_on_error=1:abort_on_error=0" \
        UBSAN_OPTIONS="halt_on_error=1:print_stacktrace=1" \
            "$ASAN_BIN" "$FIXTURE" --cache="$cachefile" --no-stable >"$out" 2>"$err"
        local rc=$?
        if grep -qiE 'AddressSanitizer|UndefinedBehaviorSanitizer|runtime error:|heap-buffer-overflow|stack-buffer-overflow|SEGV|ERROR: ' "$err"; then
            no "[asan:$name] SANITIZER REPORT fired"; sed -n '1,15p' "$err"
            asan_fail=1
            return
        fi
        if [ "$rc" -ge 128 ]; then
            no "[asan:$name] CRASH — exit $rc"; asan_fail=1; return
        fi
        ok "[asan:$name] no sanitizer report (exit $rc)"
    }
    for name in "${MUT_NAMES[@]}"; do
        run_one_asan "$name" "$MUTDIR/$name.cache"
    done
    run_one_asan "devnull_cache_path" "/dev/null"
    run_one_asan "directory_at_cache_path" "$DIRPATH"
    run_one_asan "symlink_to_valid_cache" "$SYMGOOD"
    run_one_asan "symlink_dangling" "$SYMDANGLE"
    [ "$asan_fail" -eq 0 ] && ok "ASan sweep: no sanitizer report across the whole mutation table" \
                           || no "ASan sweep: at least one sanitizer report fired (see above)"
else
    # ABSENT PRECONDITION, not a defect. The CI `release` jobs configure ONE build dir (build/) and never
    # -DRIPWIRE_ASAN=ON, so $ASAN_BIN cannot exist there — a hard FAIL made both release legs red for a
    # sanitizer sweep they were never asked to run (PR #1, run 30732976779: "absorb gate
    # (cachefuzzcheck.sh failed)" on macos-14 AND ubuntu-24.04, with this as the only failing line).
    # It stays PRESENCE-GUARDED: hand it an ASan binary and every arm above still runs and still asserts.
    # The sweep itself is not lost — ci.yml's `asan` job runs this gate with RIPWIRE_ASAN_BIN set.
    skip "ASan sweep — no ASan binary supplied at $ASAN_BIN (the ASan sweeps run in CI's asan job; locally: cmake -S . -B asan -DRIPWIRE_ASAN=ON && cmake --build asan -j)"
fi

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# PART 2 — qsnap blob (readQSnapBlob / deserializeSnapshot) — extends qsnapcachecheck.sh's coverage,
# does not duplicate its magic-garbage case.
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== Part 2: qsnap blob mutation table (--quality-delta) — DEV build ==="

command -v git >/dev/null 2>&1 || { echo "git required for Part 2 — skipping"; }
if command -v git >/dev/null 2>&1; then
QREPO="$TMP/qrepo"; mkdir -p "$QREPO/src"
cat > "$QREPO/src/lib.cpp" <<'EOF'
int helper( int x ) { int s = 0; for( int i = 0; i < x; ++i ) { s += i * 2; } return s; }
int mainThing( int y ) { int t = y; while( t > 1 ) { t = t - 1; } return t; }
EOF
printf '// qsnap-fuzz dirty marker (see qrun below)\n' > "$QREPO/src/marker.cpp"   # comment-only, tracked: no symbols
git -C "$QREPO" init -q; git -C "$QREPO" config user.email x@y; git -C "$QREPO" config user.name x
git -C "$QREPO" add -A; git -C "$QREPO" commit -qm init >/dev/null

QXDG="$TMP/qxdg"; mkdir -p "$QXDG"
QCACHEDIR="$QXDG/ripwire"
# #228 part 1 — the IDENTITY BASIS (src/quality.h): a working tree that already IS HEAD is compared with
# ITSELF and never materializes a HEAD tree, so it never reads or writes a qsnap blob. This part fuzzes the
# qsnap READER, so it needs a tree that reaches it: the marker is a comment-only line appended to a
# comment-only TRACKED file, which makes `git diff HEAD` non-empty and adds no symbol, no row, no output byte.
qrun(){ printf '// dirty marker\n' >> "$QREPO/src/marker.cpp"; env -u TMPDIR XDG_CACHE_HOME="$QXDG" "$BIN" "$QREPO" --quality-delta "$@"; }
# Y4: shard-aware lookup — a blob may be flat under $QCACHEDIR or under $QCACHEDIR/<xx>/ (2-hex shard).
qsnapfiles(){ find "$QCACHEDIR" -maxdepth 2 -type f -name 'ripwire-qsnap-*.bin' 2>/dev/null; }

qrun --no-cache >"$TMP/q_truth" 2>/dev/null
QBLOB="$( qsnapfiles | head -1 )"
if [ -z "$QBLOB" ]; then
    no "Part 2: no qsnap blob produced — cannot proceed with qsnap mutation table"
else
    ok "Part 2: baseline qsnap blob produced ($QBLOB)"
    cp "$QBLOB" "$TMP/q_good.bin"

    QHEAD="$( git -C "$QREPO" rev-parse --verify HEAD 2>/dev/null )"
    python3 - "$TMP/q_good.bin" "$MUTDIR" "$QHEAD" <<'PYEOF' || no "Part 2: the qsnap header layout this table mutates no longer matches the blob (see the line above) — the offset rows would be refused by an earlier guard and prove nothing"
import struct, sys

good_path, outdir, head_sha = sys.argv[1], sys.argv[2], sys.argv[3]
with open(good_path, "rb") as f:
    good = bytearray(f.read())

def fnv1a64(data: bytes) -> int:
    h = 14695981039346656037
    M = (1 << 64) - 1
    for c in data:
        h = ((h ^ c) * 1099511628211) & M
    return h

body_len = len(good) - 8   # trailer = last 8 bytes

def with_recomputed_trailer(body: bytearray) -> bytes:
    return bytes(body) + struct.pack("<Q", fnv1a64(bytes(body)))

muts = {}
muts["qsnap_truncate_before_magic_done"] = lambda b: bytes(b[:2])
muts["qsnap_truncate_before_scheme"]      = lambda b: bytes(b[:4])
muts["qsnap_truncate_before_sha"]         = lambda b: bytes(b[:8])
muts["qsnap_truncate_mid_body"]           = lambda b: bytes(b[: max(20, body_len // 2)])
muts["qsnap_truncate_trailer_partial"]    = lambda b: bytes(b[:-4])
muts["qsnap_empty_file"]                  = lambda b: b""

def mut_wrong_magic(b):
    p = bytearray(b[:body_len]); p[0:4] = b"XXXX"; return with_recomputed_trailer(p)
muts["qsnap_wrong_magic_recomputed_checksum"] = mut_wrong_magic

def mut_wrong_scheme(b):
    p = bytearray(b[:body_len]); v = struct.unpack_from("<I", p, 4)[0]; struct.pack_into("<I", p, 4, v + 1); return with_recomputed_trailer(p)
muts["qsnap_wrong_scheme_recomputed_checksum"] = mut_wrong_scheme

# The offset rows below are only worth anything if they write where deserializeSnapshot READS — a row that lands in
# a field an earlier guard checks is refused by that guard and passes while proving nothing (the stale-offset
# defect these rows were rewritten for). So the layout is VERIFIED on the good blob before any row is built: the
# u64 at QSNAP_SHA_OFF must be fnv1a64(HEAD sha), the field the reader checks last before the counts. A header
# that grows a field moves the sha and fails here loudly, instead of silently re-aiming every row.
QSNAP_SHA_OFF    = 24   # magic(4) + scheme(4) + cacheVer(4) + parserVer(4) + producer(8): the producer identity (qsnapproducercheck)
QSNAP_COUNTS_OFF = QSNAP_SHA_OFF + 8   # the first of the ten field counts (7 maps, then 3 u64 vectors)
if len(good) < QSNAP_COUNTS_OFF + 8 or struct.unpack_from("<Q", good, QSNAP_SHA_OFF)[0] != fnv1a64(head_sha.encode()):
    print("qsnap layout: the u64 at offset %d is not fnv1a64(HEAD sha %s)" % (QSNAP_SHA_OFF, head_sha or "<none>"))
    sys.exit(3)

def mut_wrong_sha(b):
    p = bytearray(b[:body_len]); struct.pack_into("<Q", p, QSNAP_SHA_OFF, 0xDEADBEEFDEADBEEF & ((1<<64)-1)); return with_recomputed_trailer(p)
muts["qsnap_wrong_sha_recomputed_checksum"] = mut_wrong_sha

def mut_huge_map_count(b):
    p = bytearray(b[:body_len])
    struct.pack_into("<I", p, QSNAP_COUNTS_OFF, 0xFFFFFFF0)   # ccxBySym's count
    return with_recomputed_trailer(p)
muts["qsnap_huge_map_count_recomputed_checksum"] = mut_huge_map_count

# The three VECTOR counts (cloneGroups, dead, publicApi): the maps ahead of them read as empty, and the
# target count claims 0xFFFFFFFF u64 records in a body with none left. Each is its own row so a guard on one
# vector cannot hide a missing guard on another.
def huge_vec_count(field):
    def mut(b):
        p = bytearray(b[:QSNAP_COUNTS_OFF])
        for _ in range(7 + field):
            p += struct.pack("<I", 0)
        p += struct.pack("<I", 0xFFFFFFFF)
        return with_recomputed_trailer(p)
    return mut
for field, name in enumerate(("clonegroups", "dead", "publicapi")):
    muts["qsnap_huge_vec_count_" + name + "_recomputed_checksum"] = huge_vec_count(field)

def mut_garbage_body(b):
    p = bytearray(b[:body_len])
    x = 17
    for i in range(16, body_len):
        x = (x * 1103515245 + 12345) & 0xFF
        p[i] = x
    return with_recomputed_trailer(p)
muts["qsnap_checksum_valid_garbage_payload"] = mut_garbage_body

def mut_deep_bitflip_stale(b):
    p = bytearray(b[:body_len])
    idx = min(24, body_len - 1)
    p[idx] ^= 0xFF
    stored = struct.unpack_from("<Q", b, body_len)[0]
    return bytes(p) + struct.pack("<Q", stored)
muts["qsnap_deep_bitflip_stale_checksum"] = mut_deep_bitflip_stale

def mut_trailer_corrupted(b):
    p = bytearray(b)
    p[-1] ^= 0xFF
    return bytes(p)
muts["qsnap_trailer_bytes_corrupted"] = mut_trailer_corrupted

names = []
for name, fn in muts.items():
    data = fn(good)
    path = outdir + "/" + name + ".bin"
    with open(path, "wb") as f:
        f.write(data)
    names.append(name)
print("\n".join(sorted(names)))
PYEOF

    QMUT_NAMES=( $( ls "$MUTDIR"/qsnap_*.bin 2>/dev/null | xargs -n1 basename | sed 's/\.bin$//' | sort ) )
    for name in ${QMUT_NAMES[@]+"${QMUT_NAMES[@]}"}; do
        cp "$MUTDIR/$name.bin" "$QBLOB"
        out="$TMP/q_${name}.out"; err="$TMP/q_${name}.err"
        qrun >"$out" 2>"$err"; rc=$?
        if [ "$rc" -ge 128 ]; then
            no "[$name] CRASH — exit $rc"
        elif ! diff -q "$TMP/q_truth" "$out" >/dev/null 2>&1; then
            no "[$name] OUTPUT POISONED by corrupt qsnap blob — differs from ground truth"
            diff "$TMP/q_truth" "$out" | head -4
        elif ! stderr_sane "$err"; then
            no "[$name] qsnap stderr not bounded — possible spew"
        else
            ok "[$name] exit 0, output byte-identical to ground truth, stderr bounded"
        fi
        cp "$TMP/q_good.bin" "$QBLOB"   # restore for the next mutation
    done

    # The huge VECTOR counts once more, under a bound (see the header): red on a reader that reserves from the
    # count, green on one that measures the count against the bytes left first.
    QHUGE_NAMES=( $( ls "$MUTDIR"/qsnap_huge_vec_count_*.bin 2>/dev/null | xargs -n1 basename | sed 's/\.bin$//' | sort ) )
    [ "${#QHUGE_NAMES[@]}" -eq 3 ] && ok "huge vector-count rows generated (${#QHUGE_NAMES[@]})" \
                                   || no "expected 3 huge vector-count rows, generated ${#QHUGE_NAMES[@]}"
    QBOUND="$( bound_mode_of "$BIN" )"
    [ -n "$QBOUND" ] || note "huge vector counts: no allocation bound for a plain $( uname -s ) binary — its allocator overcommits the reservation, so only the ASan sweep below or a Linux run can turn these rows red"
    if [ -n "$QBOUND" ]; then
        for name in ${QHUGE_NAMES[@]+"${QHUGE_NAMES[@]}"}; do
            cp "$MUTDIR/$name.bin" "$QBLOB"
            out="$TMP/qb_${name}.out"; err="$TMP/qb_${name}.err"
            bounded "$QBOUND" qrun >"$out" 2>"$err"; rc=$?
            if [ "$rc" -eq 97 ]; then
                skip "[bounded:$QBOUND:$name] the address-space limit could not be set here"
            elif [ "$rc" -ne 0 ] || grep -qiE 'AddressSanitizer|bad_alloc|terminate called' "$err"; then
                no "[bounded:$QBOUND:$name] exit $rc — the count reached an allocation before any byte-count check"; sed -n '1,6p' "$err"
            elif ! diff -q "$TMP/q_truth" "$out" >/dev/null 2>&1; then
                no "[bounded:$QBOUND:$name] OUTPUT POISONED under the bound"
            elif ! grep -q 'HEAD Snapshot cache corrupt' "$err"; then
                no "[bounded:$QBOUND:$name] exit 0 but the blob was not disclosed as corrupt"
            else
                ok "[bounded:$QBOUND:$name] exit 0, byte-identical, disclosed as a corrupt cache"
            fi
            cp "$TMP/q_good.bin" "$QBLOB"
        done
    fi

    # filesystem-shape: directory at the qsnap blob path.
    rm -f "$QBLOB"; mkdir -p "$QBLOB"
    out="$TMP/q_dir.out"; err="$TMP/q_dir.err"
    qrun >"$out" 2>"$err"; rc=$?
    if [ "$rc" -ge 128 ]; then
        no "[qsnap_directory_at_path] CRASH — exit $rc"
    elif ! diff -q "$TMP/q_truth" "$out" >/dev/null 2>&1; then
        no "[qsnap_directory_at_path] OUTPUT POISONED"
        diff "$TMP/q_truth" "$out" | head -4
    else
        ok "[qsnap_directory_at_path] exit 0, output byte-identical to ground truth"
    fi
    rm -rf "$QBLOB"

    if [ -x "$ASAN_BIN" ]; then
        echo
        echo "=== Part 2: qsnap mutation table — ASan build ==="
        asanq_fail=0
        # PRESENCE GUARD — the ASan binary must READ the blob these rows mutate. The qsnap filename folds the
        # PRODUCER IDENTITY (the build's source hash, quality.h producerIdentity), so an ASan binary built from
        # different sources than $BIN looks up a different key, misses, recomputes cold, and every row below
        # passes without ever opening its mutant. Measured on integration/train-1: a qsnapCountFits->true stub
        # in the ASan build left all three huge vector-count rows green here while the qchurn rows (not
        # producer-keyed) went red. A corrupt blob at $QBLOB must make that binary say so on stderr.
        cp "$MUTDIR/qsnap_wrong_magic_recomputed_checksum.bin" "$QBLOB"
        env -u TMPDIR XDG_CACHE_HOME="$QXDG" "$ASAN_BIN" "$QREPO" --quality-delta >/dev/null 2>"$TMP/qasan_guard.err"
        cp "$TMP/q_good.bin" "$QBLOB"
        if grep -q 'HEAD Snapshot cache corrupt' "$TMP/qasan_guard.err"; then
            ok "qsnap ASan sweep reads the blob its rows mutate (a corrupt blob at that path is disclosed by $( basename "$ASAN_BIN" ))"
        else
            no "qsnap ASan sweep: $ASAN_BIN never read the blob at the mutated path — it keys a different qsnap blob (built from different sources than $BIN?), so every row below would pass unread. Rebuild both from one tree."
            asanq_fail=1
            QMUT_NAMES=()
        fi
        for name in ${QMUT_NAMES[@]+"${QMUT_NAMES[@]}"}; do
            cp "$MUTDIR/$name.bin" "$QBLOB" 2>/dev/null || { mkdir -p "$( dirname "$QBLOB" )"; cp "$MUTDIR/$name.bin" "$QBLOB"; }
            err="$TMP/qasan_${name}.err"
            # max_allocation_size_mb: the bound the huge-count rows need to go red on an overcommitting host (header).
            ASAN_OPTIONS="halt_on_error=1:abort_on_error=0:max_allocation_size_mb=1024" env -u TMPDIR XDG_CACHE_HOME="$QXDG" "$ASAN_BIN" "$QREPO" --quality-delta >/dev/null 2>"$err"
            rc=$?
            if grep -qiE 'AddressSanitizer|UndefinedBehaviorSanitizer|runtime error:|heap-buffer-overflow|stack-buffer-overflow|SEGV|ERROR: ' "$err" || [ "$rc" -ge 128 ]; then
                no "[asan:$name] SANITIZER REPORT / crash (exit $rc)"; sed -n '1,10p' "$err"
                asanq_fail=1
            else
                ok "[asan:$name] no sanitizer report (exit $rc)"
            fi
            cp "$TMP/q_good.bin" "$QBLOB"
        done
        if [ "$asanq_fail" -eq 0 ]; then ok "qsnap ASan sweep: no sanitizer report"; else no "qsnap ASan sweep: sanitizer report fired"; fi
    else
        # same absent precondition as Part 1's sweep — but this arm used to vanish in SILENCE, which reads
        # identically to "ran and passed" in a log. Name the reason instead.
        skip "qsnap ASan sweep — no ASan binary supplied at $ASAN_BIN (see Part 1's skip)"
    fi
fi
fi

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# PART 3 — an out-of-range ENUM BYTE inside a checksum-VALID ingest-cache record
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# The readers build enums straight from cache bytes (readDef's SymKind/Lang, readRef's Lang/RecvKind/RefRole,
# readBind's Lang/LocalBindKind, readFfi's BindKind, readRouteDef/readRouteUse's HttpMethod). An enum with a
# fixed underlying type holds any u8, so nothing fails AT the cast; the damage is downstream, where a value
# past the last enumerator is served as a wrong answer or reaches UB (clones.h shifts a mask by the Lang).
#
# WHY THESE ARMS CAN FAIL, and are not stopped by an earlier guard: Part 1's garbage payload never isolates
# one enum byte, and a stale digest would be refused by recSum before any enum is read. Each mutant here
# changes exactly ONE enum byte and then rebuilds every recSum and the tableSum, so the ONLY thing that can
# refuse it is a range check at the enum read. The walker below mirrors readFileRecord field by field and
# asserts it lands on each record's exact end — a layout it no longer understands is a FAIL, never a guess.
#
# Per field class, three runs against the SAME byte:
#   (a) value = the enumerator COUNT (first invalid) and 255: exit 0, stdout byte-identical to --no-cache,
#       and RIPWIRE_CACHE_STATS cached_records = N-1 — exactly the one record carrying the byte was refused
#       (that file reparses) while the rest of the blob stood.
#   (c) value = a DIFFERENT in-range enumerator: cached_records = N — the record is ACCEPTED, which proves
#       the (a) refusal came from the enum range and not from a digest the mutation failed to rebuild.
#   (b) the (a) mutants under the ASan/UBSan binary with --clones (the verb that reaches clones.h's
#       Lang-indexed shift): no sanitizer report AND cached_records = N-1, and the (c) mutants under the same
#       binary: cached_records = N. That is the LIVENESS half — a sanitizer-clean run over a cache the ASan binary
#       never loaded (a key mismatch, an earlier refusal) would otherwise pass while proving nothing.
# The enumerator counts are DERIVED from src/model.h, not written here, so appending an enumerator without
# moving its k*Count constant turns (c)'s last-enumerator control red instead of going unnoticed.
#
# The same three runs cover the 16-BIT FIELDS the writer stores in a u32 slot (readDef's ppAlt and params,
# readRef's argCount — hazardpatterncheck.sh rule D). `std::uint16_t( r.u32() )` kept the low bits of 0x10000
# and believed a 0: (a) values 0x10000 and 0xFFFFFFFF must refuse that record, (c) 0xFFFF must be accepted.
echo
echo "=== Part 3: out-of-range enum byte in a checksum-valid ingest-cache record — DEV build ==="
EFX="$TMP/enumfx"; mkdir -p "$EFX/ffi" "$EFX/routes"
cp -R "$FIXTURE/." "$EFX/"
cp -R "$ROOT/test/ffifix/." "$EFX/ffi/"            # BindKind (pybind11, extern "C", ctypes handle)
cp -R "$ROOT/test/routeedgefix/." "$EFX/routes/"   # HttpMethod on both route records
EDIR="$TMP/enum"; mkdir -p "$EDIR"
"$BIN" "$EFX" --no-cache --no-stable >"$EDIR/truth.xml" 2>/dev/null
"$BIN" "$EFX" --cache="$EDIR/good.cache" --no-stable >/dev/null 2>&1
if [ ! -s "$EDIR/truth.xml" ] || [ ! -s "$EDIR/good.cache" ]; then
    no "Part 3: could not build the ground truth or the baseline cache for the enum fixture — every arm below would be vacuous"
else
cachedRecords(){ grep -oE 'cached_records=[0-9]+' "$1" | head -1 | cut -d= -f2; }
cp "$EDIR/good.cache" "$EDIR/run.cache"
RIPWIRE_CACHE_STATS=1 "$BIN" "$EFX" --cache="$EDIR/run.cache" --no-stable >"$EDIR/good_warm.xml" 2>"$EDIR/good_warm.err"
GOOD_RECORDS="$( cachedRecords "$EDIR/good_warm.err" )"
if [ -n "$GOOD_RECORDS" ] && [ "$GOOD_RECORDS" -gt 0 ] && cmp -s "$EDIR/truth.xml" "$EDIR/good_warm.xml"; then
    ok "Part 3 baseline: the unmodified cache is used whole (cached_records=$GOOD_RECORDS) and serves the --no-cache answer"
else
    no "Part 3 baseline: the unmodified cache did not warm-hit cleanly (cached_records='${GOOD_RECORDS:-none}') — the arms below cannot conclude"
    GOOD_RECORDS=""
fi

python3 - "$ROOT/src/model.h" "$EDIR/good.cache" "$EDIR" >"$EDIR/plan.tsv" 2>"$EDIR/plan.err" <<'PYEOF'
import re, struct, sys

model_path, good_path, outdir = sys.argv[1], sys.argv[2], sys.argv[3]
# comments stripped FIRST: an enumerator's own comment may spell a brace (LocalBindKind's "spans {0,0}"), and a
# brace match run over the raw text stops there and under-counts the enum
src = re.sub(r"//[^\n]*", "", open(model_path, encoding="utf-8").read())

def enumerator_count(name):
    m = re.search(r"enum\s+class\s+" + name + r"\s*:\s*std::uint8_t\s*\{(.*?)\}\s*;", src, re.S)
    if not m:
        raise SystemExit(f"enum {name} not found in model.h")
    names = [t.strip() for t in m.group(1).split(",") if t.strip()]
    if not names or any(not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", t) for t in names):
        raise SystemExit(f"enum {name}: unexpected enumerator list {names}")
    return len(names)

ENUM_OF = { "def.kind": "SymKind", "def.lang": "Lang", "ref.lang": "Lang", "ref.recv": "RecvKind", "ref.role": "RefRole",
            "bind.lang": "Lang", "bind.kind": "LocalBindKind", "ffi.kind": "BindKind",
            "routedef.method": "HttpMethod", "routeuse.method": "HttpMethod" }
count = { e: enumerator_count(e) for e in set(ENUM_OF.values()) }

blob = bytearray(open(good_path, "rb").read())
HDR, TRAILER, ENTRY = 25, 24, 32
table_off, n = struct.unpack_from("<QI", blob, len(blob) - TRAILER)[0:2]
sites = {}
for i in range(n):
    e = table_off + i * ENTRY
    rec_off = struct.unpack_from("<Q", blob, e + 8)[0]
    rec_len = struct.unpack_from("<I", blob, e + 24)[0]
    p = rec_off
    def u8():
        global p; v = blob[p]; p += 1; return v
    def u32():
        global p; v = struct.unpack_from("<I", blob, p)[0]; p += 4; return v
    def skip(k):
        global p; p += k
    def s():
        global p; ln = u32(); p += ln
    def site(cls):
        sites.setdefault(cls, (p, blob[p])); skip(1)
    def site32(cls, rel):                                                 # a u32 slot `rel` bytes ahead; p does not move
        sites.setdefault(cls, (p + rel, struct.unpack_from("<I", blob, p + rel)[0]))
    s(); skip(4 * 8 + 5 * 4)                                              # path, hash/size/mtime/ctime, FileHealth
    for _ in range(u32()):                                                # defs (LEAN family: no subtoken rows)
        site32("def.ppAlt", 9 * 4); site32("def.params", 13 * 4)
        skip(14 * 4 + 6 + 2 * 4); site("def.kind"); site("def.lang"); s(); s(); skip(8)   # #150: +1 u8 (scopeRootsStd); cache v26: +2 u32 (fnScopeStart/End) before kind
    for _ in range(u32()):                                                # refs
        skip(4); site("ref.lang"); s(); skip(2); s(); site("ref.recv"); s(); skip(1); s(); s(); site("ref.role"); site32("ref.argCount", 4); skip(12); s(); s(); s(); s(); skip(1)   # line, argCount, argCountKnown, viaArrow, #150's qualifierRootsStd, FE-A's memberCall u8 + memberRoot str, FE-B's memberPath + memberCtor + memberVia strs, memberFactory u8
    for _ in range(u32()):                                                # includes
        skip(3 + 4 + 1); s()
    for _ in range(u32()):                                                # binds
        skip(4); site("bind.lang"); site("bind.kind"); skip(1 + 8); s(); s(); s()   # isFromAssignment, spanStart/End
    for _ in range(u32()):                                                # FFI aliases
        site("ffi.kind"); skip(1); s(); s(); s()
    for _ in range(u32()):                                                # route defs
        skip(4); site("routedef.method"); s(); s()
    for _ in range(u32()):                                                # route uses
        skip(8); site("routeuse.method"); s()
    for _ in range(u32()):                                                # const-opens
        skip(9); s()
    if p != rec_off + rec_len:
        raise SystemExit(f"walker desynchronised from the record layout at entry {i}: ended at {p}, record ends at {rec_off + rec_len}")

def blob_checksum(data):
    P, M = 1099511628211, (1 << 64) - 1
    lane = [1469598103934665603, 1099511628211, 0x100000001b3, 0x9e3779b97f4a7c15,
            0xc2b2ae3d27d4eb4f, 0x165667b19e3779f9, 0xff51afd7ed558ccd, 0xc4ceb9fe1a85ec53]
    k8 = len(data) - len(data) % 8
    for i in range(0, k8, 8):
        for k in range(8):
            lane[k] = ((lane[k] ^ data[i + k]) * P) & M
    for k, i in enumerate(range(k8, len(data))):
        lane[k] = ((lane[k] ^ data[i]) * P) & M
    h = 1469598103934665603
    for k in range(8):
        h = ((h ^ lane[k]) * P) & M
    return h

def rebuilt_with(off, value, width=1):
    b = bytearray(blob)
    if width == 1:
        b[off] = value
    else:
        struct.pack_into("<I", b, off, value)
    for i in range(n):
        e = table_off + i * ENTRY
        ro = struct.unpack_from("<Q", b, e + 8)[0]; rl = struct.unpack_from("<I", b, e + 24)[0]
        struct.pack_into("<I", b, e + 28, blob_checksum(bytes(b[ro:ro + rl])) & 0xFFFFFFFF)
    struct.pack_into("<Q", b, len(b) - 8, blob_checksum(bytes(b[:HDR]) + bytes(b[table_off:table_off + n * ENTRY])))
    return bytes(b)

for cls, enum in ENUM_OF.items():
    if cls not in sites:
        print(f"{cls}\t{enum}\tABSENT\t-\t-\t-")
        continue
    off, orig = sites[cls]
    c = count[enum]
    control = c - 1 if orig != c - 1 else 0
    for tag, value in (("count", c), ("255", 255), ("inrange", control)):
        data = rebuilt_with(off, value)
        path = f"{outdir}/{cls}.{tag}.cache"
        open(path, "wb").write(data)
        print(f"{cls}\t{enum}\t{tag}\t{value}\t{orig}\t{c}")
for cls in ("def.ppAlt", "def.params", "ref.argCount"):
    if cls not in sites:
        print(f"{cls}\tu16\tABSENT\t-\t-\t-")
        continue
    off, orig = sites[cls]
    for tag, value in (("wide", 0x10000), ("allones", 0xFFFFFFFF), ("inrange", 0xFFFF)):
        open(f"{outdir}/{cls}.{tag}.cache", "wb").write(rebuilt_with(off, value, 4))
        print(f"{cls}\tu16\t{tag}\t{value}\t{orig}\t65536")
PYEOF
planRc=$?
if [ "$planRc" -ne 0 ]; then
    no "Part 3: the mutation planner refused ($( head -c 300 "$EDIR/plan.err" )) — no arm below can run"
elif [ -n "$GOOD_RECORDS" ]; then
    expectRefused=$(( GOOD_RECORDS - 1 ))
    while IFS="$( printf '\t' )" read -r cls enum tag value orig enumCount; do
        if [ "$tag" = "ABSENT" ]; then
            no "[enum:$cls] the fixture produced no $enum byte for this field class — its arms would be vacuous"
            continue
        fi
        mutant="$EDIR/$cls.$tag.cache"
        if [ "$enum" = "u16" ]; then what="16-bit field stored wider than 16 bits"; else what="$enum byte past the last enumerator (count $enumCount)"; fi
        if cmp -s "$mutant" "$EDIR/good.cache"; then
            no "[enum:$cls=$value] the mutation did not take (mutant equals the good cache)"
            continue
        fi
        cp "$mutant" "$EDIR/run.cache"   # a run that refuses a record REWRITES the blob, so every run gets a fresh copy
        RIPWIRE_CACHE_STATS=1 "$BIN" "$EFX" --cache="$EDIR/run.cache" --no-stable >"$EDIR/out.xml" 2>"$EDIR/out.err"
        rc=$?
        records="$( cachedRecords "$EDIR/out.err" )"
        if [ "$tag" = "inrange" ]; then
            if [ "$rc" -eq 0 ] && [ "$records" = "$GOOD_RECORDS" ]; then
                ok "[enum:$cls control] in-range $enum value $value (was $orig): record accepted, cached_records=$records of $GOOD_RECORDS — the arms reach the field read"
            else
                no "[enum:$cls control] in-range $enum value $value (the largest value that fits, or 0) was REFUSED or crashed: exit $rc, cached_records=${records:-none} of $GOOD_RECORDS — a stale bound, or a digest the mutation did not rebuild"
            fi
            continue
        fi
        if [ "$rc" -ge 128 ]; then
            no "[enum:$cls=$value] CRASH — exit $rc on a $what"
        elif [ "$rc" -ne 0 ]; then
            no "[enum:$cls=$value] nonzero exit ($rc) — an out-of-range cache byte must degrade, not fail the run"
        elif [ "$records" != "$expectRefused" ]; then
            no "[enum:$cls=$value] $what was ACCEPTED: cached_records=${records:-none}, expected $expectRefused of $GOOD_RECORDS"
        elif ! cmp -s "$EDIR/truth.xml" "$EDIR/out.xml"; then
            no "[enum:$cls=$value] record refused but the output still differs from --no-cache"
            diff "$EDIR/truth.xml" "$EDIR/out.xml" | head -4
        else
            ok "[enum:$cls=$value] $what: that record refused (cached_records=$records of $GOOD_RECORDS), output byte-identical to --no-cache"
        fi
    done <"$EDIR/plan.tsv"

    if [ -x "$ASAN_BIN" ]; then
        echo
        echo "=== Part 3: enum mutants — ASan build, --clones; cached_records proves each doctored cache was loaded ==="
        enumAsanFail=0
        while IFS="$( printf '\t' )" read -r cls enum tag value orig enumCount; do
            if [ "$tag" = "ABSENT" ]; then
                continue   # already a FAIL row in the dev loop above
            fi
            name="$cls.$tag"
            if [ "$tag" = "inrange" ]; then
                expectRecords="$GOOD_RECORDS"
            else
                expectRecords="$expectRefused"
            fi
            cp "$EDIR/$name.cache" "$EDIR/asan_run.cache"
            RIPWIRE_CACHE_STATS=1 ASAN_OPTIONS="halt_on_error=1:abort_on_error=0" UBSAN_OPTIONS="halt_on_error=1:print_stacktrace=1" \
                "$ASAN_BIN" "$EFX" --cache="$EDIR/asan_run.cache" --clones --no-stable >/dev/null 2>"$EDIR/asan.err"
            rc=$?
            records="$( cachedRecords "$EDIR/asan.err" )"
            if grep -qiE 'AddressSanitizer|UndefinedBehaviorSanitizer|runtime error:|SEGV' "$EDIR/asan.err" || [ "$rc" -ge 128 ]; then
                no "[asan:enum:$name] sanitizer report / crash (exit $rc): $( grep -m1 -E 'runtime error:|ERROR: AddressSanitizer' "$EDIR/asan.err" | sed -E 's#.*/src/#src/#' | cut -c1-160 )"
                enumAsanFail=1
            elif [ "$records" != "$expectRecords" ]; then
                no "[asan:enum:$name] LIVENESS: the ASan binary read cached_records=${records:-none}, expected $expectRecords of $GOOD_RECORDS — it did not load the doctored cache as the dev binary did, so a clean run here proves nothing"
                enumAsanFail=1
            else
                ok "[asan:enum:$name] no sanitizer report (exit $rc), and the doctored cache was loaded: cached_records=$records of $GOOD_RECORDS"
            fi
        done <"$EDIR/plan.tsv"
        if [ "$enumAsanFail" -eq 0 ]; then
            ok "Part 3 ASan sweep: no sanitizer report across the enum mutants, each one loaded (refused record N-1, in-range control N)"
        else
            no "Part 3 ASan sweep: a sanitizer report fired or a mutant was never loaded (see above)"
        fi
    else
        skip "Part 3 ASan sweep — no ASan binary supplied at $ASAN_BIN (see Part 1's skip)"
    fi
fi
fi

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# PART 4 — the span-tier memo (ripwire-stier-*, ingest_astquery.h spanTierMemoLoad): a tier byte past SpanTier
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# The memo is a raw blob with NO checksum: magic, version, the file's stat triple, its path, then three parallel
# arrays — startByte[], endByte[], tier[] (one u8 per span). --grep's tier pass counts hits per tier into a
# three-element array indexed by that byte (search.h grepApplySpanTiers), so a tier byte of 3 or more written
# anywhere in the cache directory used to be an out-of-bounds WRITE on the stack.
#   (a) tier byte = the SpanTier count and 255: exit 0, stdout byte-identical to --no-cache (memo refused).
#   (b) the same two mutants under the ASan/UBSan binary: no sanitizer report, output byte-identical to
#       --no-cache; and the (c) mutant under that binary must CHANGE the answer — the liveness proof that the ASan
#       binary reads the memo at all, without which a clean (b) could be a memo it never opened.
#   (c) CONTROL: the same byte set to an in-range tier that CHANGES the answer (a comment span re-labelled
#       Code): stdout DIFFERS from --no-cache — the memo was read and believed, so (a) is refused at the tier
#       byte and not by an earlier stat or path guard.
echo
echo "=== Part 4: span-tier memo with a tier byte past SpanTier — DEV build ==="
SDIR="$TMP/stier"; SSB="$SDIR/sandbox"; SCACHE="$SDIR/cache"
mkdir -p "$SSB/src" "$SCACHE"
{
    printf '// FASTTOKEN_zeta named in a comment\n'
    printf 'const char* alphaMessage = "FASTTOKEN_zeta inside a string literal";\n'
    printf 'int alphaFastTokenZeta( int n )\n{\n    int FASTTOKEN_zeta = n + 1;\n    return FASTTOKEN_zeta;\n}\n'
    # past kSpanTierMemoMinBytes (32 KiB): below it no memo is written and every arm here would be vacuous
    awk 'BEGIN{ for( i = 0; i < 900; i++ ) printf "int alphaFiller%04d( int v ) { return v + %d; }\n", i, i }'
} >"$SSB/src/alpha.c"
touch -t 202001010000 "$SSB/src/alpha.c"   # well before any blob this gate writes, so the memo's racy rule admits it
stierRun(){   # $1 = binary, $2 = out prefix, $3.. = extra argv
    local bin="$1" out="$2"; shift 2
    TMPDIR="$SCACHE" "$bin" "$SSB" --grep=FASTTOKEN_zeta "$@" >"$out.out" 2>"$out.err"
    printf '%s' "$?" >"$out.rc"
}
stierRun "$BIN" "$SDIR/truth" --no-cache
stierRun "$BIN" "$SDIR/populate"
STIER_BLOB="$( find "$SCACHE" -name 'ripwire-stier-*' -type f 2>/dev/null | head -1 )"
STIER_COUNT="$( sed -nE 's/^enum class SpanTier : std::uint8_t \{(.*)\};.*/\1/p' "$ROOT/src/ingest.h" | tr ',' '\n' | grep -cE '[A-Za-z]' )"
if [ -z "$STIER_BLOB" ] || [ "${STIER_COUNT:-0}" -lt 2 ]; then
    no "Part 4: no span-tier memo blob was written (blob='${STIER_BLOB:-none}') or SpanTier was not found in src/ingest.h (count='${STIER_COUNT:-none}') — every arm below would be vacuous"
elif ! cmp -s "$SDIR/truth.out" "$SDIR/populate.out"; then
    no "Part 4: the memo-populating run already differs from --no-cache — the arms below cannot conclude"
else
    cp "$STIER_BLOB" "$SDIR/good.bin"
    python3 - "$SDIR/good.bin" "$SDIR" "$STIER_COUNT" >"$SDIR/plan.txt" 2>"$SDIR/plan.err" <<'PYEOF'
import struct, sys
good, outdir, count = sys.argv[1], sys.argv[2], int(sys.argv[3])
b = bytearray(open(good, "rb").read())
if b[0:4] != struct.pack("<I", 0x53544d31):
    raise SystemExit("not an STM1 blob")
p = 8 + 3 * 8
p += 4 + struct.unpack_from("<I", b, p)[0]                     # recorded path
spans = struct.unpack_from("<I", b, p)[0]; p += 4
tier0 = p + 8 * spans                                           # startByte[], endByte[], then tier[]
if spans == 0 or tier0 + spans != len(b):
    raise SystemExit(f"layout mismatch: spans={spans} tier[] at {tier0}, blob is {len(b)} bytes")
target = next((tier0 + i for i in range(spans) if b[tier0 + i] != 0), None)   # a non-Code span, re-labelled by the control
if target is None:
    raise SystemExit("no comment/string span in the memo")
for tag, value in (("count", count), ("255", 255), ("inrange", 0)):
    m = bytearray(b); m[target] = value
    open(f"{outdir}/{tag}.bin", "wb").write(bytes(m))
    print(tag, value, b[target])
PYEOF
    if [ $? -ne 0 ]; then
        no "Part 4: the memo mutation planner refused ($( head -c 200 "$SDIR/plan.err" ))"
    else
        for tag in count 255 inrange; do
            if cmp -s "$SDIR/$tag.bin" "$SDIR/good.bin"; then
                no "[stier:$tag] the mutation did not take"
                continue
            fi
            cp "$SDIR/$tag.bin" "$STIER_BLOB"
            stierRun "$BIN" "$SDIR/$tag"
            rc="$( cat "$SDIR/$tag.rc" )"
            if [ "$tag" = "inrange" ]; then
                if [ "$rc" = "0" ] && ! cmp -s "$SDIR/truth.out" "$SDIR/$tag.out"; then
                    ok "[stier control] an in-range tier edit changes the answer — the memo is read and believed, so the arms below reach the tier byte"
                else
                    no "[stier control] an in-range tier edit did not reach the answer (exit $rc) — the memo was refused before the tier byte, so the out-of-range arms prove nothing"
                fi
            elif [ "$rc" -ge 128 ] 2>/dev/null; then
                no "[stier:$tag] CRASH — exit $rc on a memo tier byte past SpanTier"
            elif [ "$rc" != "0" ] || ! cmp -s "$SDIR/truth.out" "$SDIR/$tag.out"; then
                no "[stier:$tag] a memo tier byte past SpanTier was served: exit $rc, output differs from --no-cache"
            else
                ok "[stier:$tag] a memo tier byte past SpanTier ($tag): memo refused, output byte-identical to --no-cache"
            fi
        done
        if [ -x "$ASAN_BIN" ]; then
            stierAsanFail=0
            for asanTag in inrange count 255; do
                cp "$SDIR/$asanTag.bin" "$STIER_BLOB"   # the ASan runs' own memo copy: a refusal rewrites the blob
                ASAN_OPTIONS="halt_on_error=1:abort_on_error=0" UBSAN_OPTIONS="halt_on_error=1:print_stacktrace=1" \
                    stierRun "$ASAN_BIN" "$SDIR/asan_$asanTag"
                rc="$( cat "$SDIR/asan_$asanTag.rc" )"
                if grep -qiE 'AddressSanitizer|UndefinedBehaviorSanitizer|runtime error:|SEGV' "$SDIR/asan_$asanTag.err" || [ "$rc" -ge 128 ]; then
                    no "[asan:stier:$asanTag] sanitizer report / crash (exit $rc): $( grep -m1 -E 'runtime error:|ERROR: AddressSanitizer' "$SDIR/asan_$asanTag.err" | sed -E 's#.*/src/#src/#' | cut -c1-160 )"
                    stierAsanFail=1
                elif [ "$asanTag" = "inrange" ]; then
                    if [ "$rc" = "0" ] && ! cmp -s "$SDIR/truth.out" "$SDIR/asan_$asanTag.out"; then
                        ok "[asan:stier control] the ASan binary read and believed the in-range memo edit (the answer changed), so its out-of-range runs load the memo too"
                    else
                        no "[asan:stier control] LIVENESS: the in-range memo edit did not change the ASan binary's answer (exit $rc) — it never read the memo, so its clean runs prove nothing"
                        stierAsanFail=1
                    fi
                elif [ "$rc" != "0" ] || ! cmp -s "$SDIR/truth.out" "$SDIR/asan_$asanTag.out"; then
                    no "[asan:stier:$asanTag] a memo tier byte past SpanTier was served under ASan: exit $rc, output differs from --no-cache"
                    stierAsanFail=1
                else
                    ok "[asan:stier:$asanTag] no sanitizer report (exit $rc), memo refused, output byte-identical to --no-cache"
                fi
            done
            if [ "$stierAsanFail" -ne 0 ]; then
                no "Part 4 ASan sweep: a sanitizer report fired, a tier byte was served, or the memo was never read (see above)"
            fi
        else
            skip "Part 4 ASan sweep — no ASan binary supplied at $ASAN_BIN (see Part 1's skip)"
        fi
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# PART 5 — qchurn blob (deserializeRawCommitStream) — the co-change/churn history memo behind --for
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# Same reader family as Part 2 (readQSnapBlob + qsnapGet), a different layout: magic "QCHN"(4), scheme(4),
# fnv(key)(8), then a u32 commit count, and per commit an i64 epoch and a u32 path count ahead of its
# length-prefixed paths. Both counts used to size a reserve before any byte of the records was read: 2^32-1
# commits is ~128 GiB and 2^32-1 paths ~96 GiB, and Linux answered either with an uncaught std::bad_alloc
# (SIGABRT on every --for until the blob was evicted). A rejected blob is a SILENT miss by this memo's contract
# (a stale key is the ordinary case), so the proof that the reader refused it rather than trusting it is that
# the recompute rewrote the blob byte-identical to the good one.
echo
echo "=== Part 5: qchurn blob huge counts (--for) ==="
if command -v git >/dev/null 2>&1 && [ -n "${QREPO:-}" ] && [ -d "$QREPO" ]; then
    crun(){ env -u TMPDIR XDG_CACHE_HOME="$QXDG" "$@" "$QREPO" --for=helper; }
    crun "$BIN" >"$TMP/c_truth" 2>/dev/null                 # cold: walks git log, writes the blob
    CBLOB="$( find "$QCACHEDIR" -maxdepth 2 -type f -name 'ripwire-qchurn-*.bin' 2>/dev/null | head -1 )"
    if [ -z "$CBLOB" ]; then
        no "Part 5: no qchurn blob produced — cannot proceed with the qchurn rows"
    else
        cp "$CBLOB" "$TMP/c_good.bin"
        crun "$BIN" >"$TMP/c_warm" 2>/dev/null
        diff -q "$TMP/c_truth" "$TMP/c_warm" >/dev/null && ok "Part 5: the warm qchurn run is byte-identical to the cold one" \
                                                         || no "Part 5: the warm qchurn run already differs from the cold one — the harness cannot judge a mutation"
        python3 - "$TMP/c_good.bin" "$MUTDIR" <<'PYEOF3' || no "Part 5: the qchurn layout the rows mutate no longer matches the blob (see the line above) — they would prove nothing"
import struct, sys
good = open(sys.argv[1], "rb").read()
def fnv1a64(data):
    h = 14695981039346656037
    for c in data:
        h = ((h ^ c) * 1099511628211) & ((1 << 64) - 1)
    return h
QCHURN_COUNT_OFF = 16   # magic(4) + scheme(4) + fnv(key)(8): the key check must pass for the count to be read at all
# Verify the layout on the good blob before aiming a row at it: walking commits and paths from QCHURN_COUNT_OFF must
# land exactly on the trailer. A header that grew a field would make that walk miss, and the rows would then be
# refused by an earlier guard while passing — so a miss fails the arm instead.
off = QCHURN_COUNT_OFF
try:
    (n_commits,) = struct.unpack_from("<I", good, off); off += 4
    for _ in range(n_commits):
        off += 8
        (n_paths,) = struct.unpack_from("<I", good, off); off += 4
        for _ in range(n_paths):
            (length,) = struct.unpack_from("<I", good, off); off += 4 + length
except struct.error:
    off = -1
if off != len(good) - 8:
    print("qchurn layout: walking the good blob from offset %d does not land on its trailer" % QCHURN_COUNT_OFF)
    sys.exit(3)
header = good[:QCHURN_COUNT_OFF]
rows = {
    "qchurn_huge_commit_count": header + struct.pack("<I", 0xFFFFFFFF),
    "qchurn_huge_path_count":   header + struct.pack("<I", 1) + struct.pack("<q", 0) + struct.pack("<I", 0xFFFFFFFF),
}
for name, body in rows.items():
    open(sys.argv[2] + "/" + name + ".bin", "wb").write(body + struct.pack("<Q", fnv1a64(body)))
PYEOF3
        CBOUND="$( bound_mode_of "$BIN" )"
        [ -n "$CBOUND" ] || note "qchurn huge counts: no allocation bound for a plain $( uname -s ) binary — its allocator overcommits the reservation, so only the ASan leg or a Linux run can turn these rows red"
        judge_qchurn(){   # $1 = row label, $2 = rc, $3 = out, $4 = err
            if [ "$2" -eq 97 ]; then
                skip "[$1] the address-space limit could not be set here"
            elif [ "$2" -ne 0 ] || grep -qiE 'AddressSanitizer|bad_alloc|terminate called' "$4"; then
                no "[$1] exit $2 — a qchurn count reached an allocation before any byte-count check"; sed -n '1,6p' "$4"
            elif ! diff -q "$TMP/c_truth" "$3" >/dev/null 2>&1; then
                no "[$1] OUTPUT POISONED by the corrupt qchurn blob"
            elif ! cmp -s "$TMP/c_good.bin" "$CBLOB"; then
                no "[$1] exit 0, but the blob on disk is not the recomputed one — the reader did not reject it"
            else
                ok "[$1] exit 0, byte-identical, and the recompute rewrote the rejected blob"
            fi
        }
        # The unbounded row is a CORRECTNESS row: it proves the blob is refused and rewritten, and it is named so,
        # because on an overcommitting allocator it cannot see the allocation. Only the bounded and ASan legs can.
        for name in qchurn_huge_commit_count qchurn_huge_path_count; do
            [ -f "$MUTDIR/$name.bin" ] || { no "[$name] no mutant was built — nothing to judge"; continue; }
            cp "$MUTDIR/$name.bin" "$CBLOB"
            crun "$BIN" >"$TMP/c_$name.out" 2>"$TMP/c_$name.err"; rc=$?
            judge_qchurn "correctness:$name" "$rc" "$TMP/c_$name.out" "$TMP/c_$name.err"
            if [ -n "$CBOUND" ]; then
                cp "$MUTDIR/$name.bin" "$CBLOB"
                bounded "$CBOUND" crun "$BIN" >"$TMP/cb_$name.out" 2>"$TMP/cb_$name.err"; rc=$?
                judge_qchurn "bounded:$CBOUND:$name" "$rc" "$TMP/cb_$name.out" "$TMP/cb_$name.err"
            fi
            if [ -x "$ASAN_BIN" ] && [ "$ASAN_BIN" != "$BIN" ]; then
                cp "$MUTDIR/$name.bin" "$CBLOB"
                bounded asan crun "$ASAN_BIN" >"$TMP/ca_$name.out" 2>"$TMP/ca_$name.err"; rc=$?
                judge_qchurn "asan:$name" "$rc" "$TMP/ca_$name.out" "$TMP/ca_$name.err"
            elif [ "$CBOUND" != "asan" ]; then
                skip "[asan:$name] no separate sanitizer binary at ${ASAN_BIN:-<unset>} — the instrumented leg did not run"
            fi
            cp "$TMP/c_good.bin" "$CBLOB"
        done
    fi
else
    skip "Part 5: needs git and Part 2's scratch repository"
fi

# ─── Summary ──────────────────────────────────────────────────────────────────
echo
if [ "$fail" -eq 0 ]; then
    echo "cachefuzzcheck: ALL PASS"
    exit 0
else
    echo "cachefuzzcheck: SOME CHECKS FAILED"
    exit 1
fi
