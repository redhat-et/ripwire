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
# ── Part 1: v8 ingest-cache blob (loadCache) — DETERMINISTIC structured mutation table ─────────────
# Header layout (native-endian, no padding — mirrors ingest.cpp saveCache/loadCache):
#   [0:4)   u32 magic "CTPK"        [4:8)   u32 version (kCacheVersion=8)
#   [8:12)  u32 parserVer           [12]    u8  kArtifactArch (endian|pointerWidth<<1)
#   [13:21) u64 blobWriteNs         [21:25) u32 fileCount
#   file[0]: u32 pathLen, pathBytes, u64 hash, u64 sizeBytes, u64 mtimeNs, u32 defCount, [def records]...
#   ... trailer: last 8 bytes = blobChecksum (8-lane FNV-1a64) over everything before it.
# A python helper (mirroring loadCache's byte-exact layout) generates ~23 named byte-level mutations
# from one good baseline blob; bash then layers 5 more filesystem-shape mutations (dir/perm/symlink/
# /dev/null) on top — 28 total. Each mutation is applied via a FIXED table, not a random seed
# (determinism rule): re-running this script produces the exact same mutated bytes every time.
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
# Usage:
#   bash test/cachefuzzcheck.sh
#   RIPWIRE_BIN=build/ripwire RIPWIRE_ASAN_BIN=asan/ripwire bash test/cachefuzzcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check; ALL PASS on success. Does not edit
# regression.sh (regression.sh wires this in itself, once, if git status was clean when this was built).

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
ASAN_BIN="${RIPWIRE_ASAN_BIN:-$ROOT/asan/ripwire}"
[ "${ASAN_BIN#/}" = "$ASAN_BIN" ] && ASAN_BIN="$ROOT/$ASAN_BIN"
FIXTURE="$ROOT/test/fixture"
TMP="$( mktemp -d )"; trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
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

def with_recomputed_trailer(payload: bytearray) -> bytes:
    csum = blob_checksum(bytes(payload))
    return bytes(payload) + struct.pack("<Q", csum)

# ── locate the fixed-offset fields in file[0]'s record (header is a fixed 25 bytes: magic4+ver4+
#    parserVer4+arch1+blobWriteNs8+fileCount4) ──────────────────────────────────────────────────────
HDR = 25
path_len = struct.unpack_from("<I", good, HDR)[0]
path_off  = HDR + 4
hash_off  = path_off + path_len
size_off  = hash_off + 8
mtime_off = size_off + 8
nd_off    = mtime_off + 8   # file[0]'s def-record count (u32)
payload_len = len(good) - 8   # trailer is the last 8 bytes

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
    p = bytearray(b[:payload_len]); p[12] ^= 0x01
    stored = struct.unpack_from("<Q", b, payload_len)[0]      # leave the OLD (now-stale) checksum
    return bytes(p) + struct.pack("<Q", stored)
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
    p = bytearray(b[:payload_len])
    lo = min(HDR + 8, payload_len)
    hi = payload_len
    x = 0x2545F4914F6CDD1D & 0xFF
    for i in range(lo, hi):
        x = (x * 1103515245 + 12345) & 0xFF
        p[i] = x
    return with_recomputed_trailer(p)
mutations["checksum_valid_garbage_payload"] = mut_garbage_payload

# -- checksum mismatch only: a single deep bit flip, checksum left STALE (the shallowest guard alone) --
def mut_deep_bitflip_stale(b):
    p = bytearray(b[:payload_len])
    idx = min(HDR + 20, payload_len - 1)
    p[idx] ^= 0xFF
    stored = struct.unpack_from("<Q", b, payload_len)[0]
    return bytes(p) + struct.pack("<Q", stored)
mutations["checksum_mismatch_deep_bitflip_stale"] = mut_deep_bitflip_stale

# -- trailer itself corrupted, payload untouched (tests the trailer-verification path directly) --
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

# a DIRECTORY sits at the cache path instead of a file.
DIRPATH="$TMP/dir_as_cache"
mkdir -p "$DIRPATH"
run_one_dev "directory_at_cache_path" "$DIRPATH"

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
git -C "$QREPO" init -q; git -C "$QREPO" config user.email x@y; git -C "$QREPO" config user.name x
git -C "$QREPO" add -A; git -C "$QREPO" commit -qm init >/dev/null

QXDG="$TMP/qxdg"; mkdir -p "$QXDG"
QCACHEDIR="$QXDG/ripwire"
qrun(){ env -u TMPDIR XDG_CACHE_HOME="$QXDG" "$BIN" "$QREPO" --quality-delta "$@"; }
# Y4: shard-aware lookup — a blob may be flat under $QCACHEDIR or under $QCACHEDIR/<xx>/ (2-hex shard).
qsnapfiles(){ find "$QCACHEDIR" -maxdepth 2 -type f -name 'ripwire-qsnap-*.bin' 2>/dev/null; }

qrun --no-cache >"$TMP/q_truth" 2>/dev/null
QBLOB="$( qsnapfiles | head -1 )"
if [ -z "$QBLOB" ]; then
    no "Part 2: no qsnap blob produced — cannot proceed with qsnap mutation table"
else
    ok "Part 2: baseline qsnap blob produced ($QBLOB)"
    cp "$QBLOB" "$TMP/q_good.bin"

    python3 - "$TMP/q_good.bin" "$MUTDIR" <<'PYEOF'
import struct, sys

good_path, outdir = sys.argv[1], sys.argv[2]
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

def mut_wrong_sha(b):
    p = bytearray(b[:body_len]); struct.pack_into("<Q", p, 8, 0xDEADBEEFDEADBEEF & ((1<<64)-1)); return with_recomputed_trailer(p)
muts["qsnap_wrong_sha_recomputed_checksum"] = mut_wrong_sha

def mut_huge_map_count(b):
    p = bytearray(b[:body_len])
    off = 16   # first field-map count (ccxBySym), right after magic(4)+scheme(4)+sha(8)
    if off + 4 <= len(p):
        struct.pack_into("<I", p, off, 0xFFFFFFF0)
    return with_recomputed_trailer(p)
muts["qsnap_huge_map_count_recomputed_checksum"] = mut_huge_map_count

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
    for name in "${QMUT_NAMES[@]}"; do
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
        for name in "${QMUT_NAMES[@]}"; do
            cp "$MUTDIR/$name.bin" "$QBLOB" 2>/dev/null || { mkdir -p "$( dirname "$QBLOB" )"; cp "$MUTDIR/$name.bin" "$QBLOB"; }
            err="$TMP/qasan_${name}.err"
            ASAN_OPTIONS="halt_on_error=1:abort_on_error=0" env -u TMPDIR XDG_CACHE_HOME="$QXDG" "$ASAN_BIN" "$QREPO" --quality-delta >/dev/null 2>"$err"
            rc=$?
            if grep -qiE 'AddressSanitizer|UndefinedBehaviorSanitizer|runtime error:|heap-buffer-overflow|stack-buffer-overflow|SEGV|ERROR: ' "$err" || [ "$rc" -ge 128 ]; then
                no "[asan:$name] SANITIZER REPORT / crash (exit $rc)"; sed -n '1,10p' "$err"
                asanq_fail=1
            else
                ok "[asan:$name] no sanitizer report (exit $rc)"
            fi
            cp "$TMP/q_good.bin" "$QBLOB"
        done
        [ "$asanq_fail" -eq 0 ] && ok "qsnap ASan sweep: no sanitizer report" || no "qsnap ASan sweep: sanitizer report fired"
    else
        # same absent precondition as Part 1's sweep — but this arm used to vanish in SILENCE, which reads
        # identically to "ran and passed" in a log. Name the reason instead.
        skip "qsnap ASan sweep — no ASan binary supplied at $ASAN_BIN (see Part 1's skip)"
    fi
fi
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
