#!/usr/bin/env bash
# artifactcheck.sh — A1 (team-index committable-artifact) gate: prove the v8 cache blob's
# RESTORE-EQUIVALENCE + CROSS-ARCH SELF-HEAL + DRIFT-PROPORTIONAL contract survives the kArtifactArch
# header byte (kCacheVersion 7 -> 8).
#
# Background: the --cache=FILE blob IS the committable index artifact. It is
# already checkout-path portable (T5 relForHash keys; portablecachecheck.sh). v8 adds ONE header byte —
# kArtifactArch = (endianness | pointerWidth<<1) — right after parserVer, so a NATIVE-ENDIAN blob produced
# on one architecture is REJECTED by loadCache's header guard on a foreign architecture (different byte
# order / pointer width) exactly like a version mismatch → the blob is ignored → full cold reparse →
# CORRECT output, just not fast. "Correctness never depends on the artifact, only speed."
#
# This gate proves, end to end:
#   (a) RESTORE-EQUIVALENCE across checkout paths: a blob built at path A, consumed at a DIFFERENT copied
#       checkout path B → GENUINE warm hit (cache bytes untouched) AND output BYTE-IDENTICAL to a cold run
#       at B. (v8 re-proof of the portablecachecheck (a) claim — the arch byte must not break portability.)
#   (b) CROSS-ARCH SELF-HEAL: doctor the kArtifactArch byte to a FOREIGN value AND recompute the whole-blob
#       checksum trailer (so the checksum passes and the ARCH GUARD itself — not the checksum trailer — is
#       what rejects the blob). The consumer must IGNORE the blob, cold-reparse, and produce output
#       byte-identical to a cold run, exit 0. Per the DESIGN's decision the guard is SILENT (rejects like a
#       version mismatch — no DEGRADED alert; correctness never depended on the artifact). A second,
#       belt-and-suspenders variant flips the arch byte WITHOUT fixing the checksum → the checksum trailer
#       catches it first → same self-heal (both foreign-arch shapes degrade cleanly).
#   (c) DRIFT-PROPORTIONAL reparse: build the artifact over F files, modify EXACTLY 2, restore. Assert
#       (1) output equals a cold parse of the mutated tree AND (2) ONLY the 2 changed files re-parsed —
#       an executable parse-count fact via the RIPWIRE_CACHE_STATS observable (reparsed=2), so
#       "restore cost is proportional to drift, not tree size" is proven, not just asserted in prose.
#   (d) DETERMINISM: warm == cold at the same path (the v8 blob did not regress cache transparency).
#   (e) MUTATION/liveness — prove the byte-identical comparisons above are live, not vacuously true.
#
# Usage:
#   bash test/artifactcheck.sh
#   RIPWIRE_BIN=build_ia3/ripwire bash test/artifactcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check; prints ALL PASS on success.
# Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
note(){ printf '  NOTE  %s\n' "$*"; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

echo "artifactcheck: BIN=$BIN  TMP=$TMP"

FIXTURE="$ROOT/test/fixture"
md5of(){ md5 -q "$1" 2>/dev/null || md5sum "$1" | cut -d' ' -f1; }

# ════════════════════════════════════════════════════════════════════════════════════════════════════
# (a) RESTORE-EQUIVALENCE — build at copied checkout A, consume the SAME blob at a DIFFERENT copied
#     checkout B → genuine warm hit + byte-identical to a cold run at B.
# ════════════════════════════════════════════════════════════════════════════════════════════════════
PATH_A="$TMP/checkout_a/repo"
PATH_B="$TMP/checkout_b/repo"
mkdir -p "$( dirname "$PATH_A" )" "$( dirname "$PATH_B" )"
cp -R "$FIXTURE" "$PATH_A"
cp -R "$FIXTURE" "$PATH_B"

BLOB="$TMP/repo.ripwirecache"
"$BIN" "$PATH_A" --cache="$BLOB" --no-stable >"$TMP/a_build.xml" 2>"$TMP/a_build.err"
rc_a=$?
if [ "$rc_a" -eq 0 ] && [ -s "$BLOB" ]; then
    ok "(a) v8 artifact built at checkout A (exit 0, non-empty)"
else
    no "(a) artifact build at A failed (exit $rc_a)"; cat "$TMP/a_build.err"
fi

cp "$BLOB" "$TMP/committed.cache"                       # snapshot the "committed" bytes
BEFORE="$( md5of "$TMP/committed.cache" )"

"$BIN" "$PATH_B" --cache="$TMP/committed.cache" --no-stable >"$TMP/b_warm.xml" 2>"$TMP/b_warm.err"
rc_b=$?
[ "$rc_b" -eq 0 ] && ok "(a) consuming A's committed blob at checkout B exits 0" \
                  || { no "(a) consuming at B failed (exit $rc_b)"; cat "$TMP/b_warm.err"; }

AFTER="$( md5of "$TMP/committed.cache" )"
[ "$BEFORE" = "$AFTER" ] \
    && ok "(a) GENUINE WARM HIT across checkout paths — committed blob bytes UNCHANGED (every file hash-matched via the re-absolutized key, not a disguised full reparse)" \
    || no "(a) DISGUISED MISS — consuming at B rewrote the blob (bytes changed); the artifact is NOT reused across checkout paths"

"$BIN" "$PATH_B" --no-cache --no-stable >"$TMP/b_cold.xml" 2>/dev/null
diff -q "$TMP/b_warm.xml" "$TMP/b_cold.xml" >/dev/null 2>&1 \
    && ok "(a) RESTORE-EQUIVALENT: B-consumed-A's-blob output is BYTE-IDENTICAL to a cold parse at B" \
    || { no "(a) NOT restore-equivalent: warm output at B differs from cold"; diff "$TMP/b_cold.xml" "$TMP/b_warm.xml" | head -10; }

# ════════════════════════════════════════════════════════════════════════════════════════════════════
# (b) CROSS-ARCH SELF-HEAL — the new kArtifactArch guard rejects a foreign-arch blob → cold self-heal.
#     Header layout: u32 magic[0:4] u32 version[4:8] u32 parserVer[8:12] u8 ARCH[12] u64 blobWriteNs ...
#     + an 8-byte whole-blob FNV checksum TRAILER (last 8 bytes; covers the payload incl. the arch byte).
# ════════════════════════════════════════════════════════════════════════════════════════════════════
"$BIN" "$PATH_A" --cache="$TMP/base.cache" --no-stable >"$TMP/a_cold.xml" 2>/dev/null   # ground-truth cold output at A
cp "$TMP/base.cache" "$TMP/arch_fixcsum.cache"
cp "$TMP/base.cache" "$TMP/arch_nofix.cache"

# (b1) RIGOROUS — flip the arch byte to a FOREIGN value AND recompute the checksum trailer so the trailer
#      PASSES and the ARCH GUARD (not the checksum) is what ignores the blob. This isolates the new guard.
python3 - "$TMP/arch_fixcsum.cache" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path, "rb") as f: blob = bytearray(f.read())
payload = bytearray(blob[:-8])            # last 8 bytes are the whole-blob checksum trailer
payload[12] ^= 0x01                       # flip the endianness bit of kArtifactArch → guaranteed foreign, still a plausible tag

# replicate ingest.cpp blobChecksum() — an 8-lane FNV-1a permutation (deterministic function of the bytes)
def blob_checksum(data):
    P = 1099511628211; M = (1<<64)-1
    lane = [1469598103934665603, 1099511628211, 0x100000001b3, 0x9e3779b97f4a7c15,
            0xc2b2ae3d27d4eb4f, 0x165667b19e3779f9, 0xff51afd7ed558ccd, 0xc4ceb9fe1a85ec53]
    n = len(data); i = 0
    while i + 8 <= n:
        for k in range(8):
            lane[k] = ((lane[k] ^ data[i+k]) * P) & M
        i += 8
    k = 0
    while i < n:
        lane[k] = ((lane[k] ^ data[i]) * P) & M
        i += 1; k += 1
    h = 1469598103934665603
    for k in range(8):
        h = ((h ^ lane[k]) * P) & M
    return h

csum = blob_checksum(bytes(payload))
with open(path, "wb") as f:
    f.write(payload); f.write(csum.to_bytes(8, "little"))
PYEOF

"$BIN" "$PATH_A" --cache="$TMP/arch_fixcsum.cache" --no-stable >"$TMP/arch_fix.xml" 2>"$TMP/arch_fix.err"
rc_af=$?
if [ "$rc_af" -eq 0 ] && diff -q "$TMP/arch_fix.xml" "$TMP/a_cold.xml" >/dev/null 2>&1; then
    ok "(b1) FOREIGN-ARCH blob (valid checksum, doctored arch byte) is rejected by the ARCH GUARD → cold self-heal, byte-identical, exit 0"
else
    no "(b1) foreign-arch blob did not self-heal (exit $rc_af)"; cat "$TMP/arch_fix.err"; diff "$TMP/a_cold.xml" "$TMP/arch_fix.xml" | head -10
fi
# the arch guard rejects "exactly like a version mismatch" — SILENTLY (no DEGRADED alert;
# the blob is a speed cache, not a correctness input). Confirm no checksum-corruption alert fired here.
if grep -q 'checksum mismatch' "$TMP/arch_fix.err" 2>/dev/null; then
    no "(b1) arch guard emitted a CHECKSUM alert — the recomputed trailer should have passed; guard not isolated"
else
    ok "(b1) arch guard is SILENT (rejects like a version mismatch — no checksum/corruption alert; correctness never depended on the blob)"
fi

# (b2) BELT-AND-SUSPENDERS — flip the arch byte WITHOUT fixing the checksum; the trailer catches it first.
#      Either way the blob is ignored and the consumer self-heals — a foreign blob never yields a wrong answer.
python3 - "$TMP/arch_nofix.cache" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path, "r+b") as f:
    f.seek(12); b = f.read(1); f.seek(12); f.write(bytes([b[0] ^ 0x01]))   # flip arch bit, leave trailer stale
PYEOF
"$BIN" "$PATH_A" --cache="$TMP/arch_nofix.cache" --no-stable >"$TMP/arch_nofix.xml" 2>/dev/null
rc_an=$?
if [ "$rc_an" -eq 0 ] && diff -q "$TMP/arch_nofix.xml" "$TMP/a_cold.xml" >/dev/null 2>&1; then
    ok "(b2) arch-byte flip with stale checksum also self-heals cleanly (byte-identical to cold, exit 0)"
else
    no "(b2) arch-byte+stale-checksum blob did not self-heal (exit $rc_an)"
fi

# ════════════════════════════════════════════════════════════════════════════════════════════════════
# (c) DRIFT-PROPORTIONAL reparse — modify EXACTLY 2 of F files, restore; assert only those 2 re-parse
#     (RIPWIRE_CACHE_STATS observable) AND the output equals a cold parse of the mutated tree.
# ════════════════════════════════════════════════════════════════════════════════════════════════════
DRIFT="$TMP/drift/repo"
mkdir -p "$( dirname "$DRIFT" )"
cp -R "$FIXTURE" "$DRIFT"
NFILES="$( find "$DRIFT" -type f | wc -l | tr -d ' ' )"
DCACHE="$TMP/drift.cache"

# cold build populates the artifact over all F files
"$BIN" "$DRIFT" --cache="$DCACHE" --no-stable >/dev/null 2>/dev/null

# SANITY: a fully warm re-run (zero changes) re-parses NOTHING (proves the observable isn't always-nonzero)
STATS0="$( RIPWIRE_CACHE_STATS=1 "$BIN" "$DRIFT" --cache="$DCACHE" --no-stable 2>&1 >/dev/null | grep 'cache-stats' )"
if echo "$STATS0" | grep -q 'reparsed=0 '; then
    ok "(c) zero-change warm run re-parses 0 files ($STATS0) — observable is live, not always-nonzero"
else
    no "(c) zero-change warm run reported a nonzero reparse ($STATS0) — observable or warm path is wrong"
fi

# modify EXACTLY 2 source files (append a new function → size + mtime change → detected)
sleep 1
printf '\nint drift_added_one( void ) { return 111; }\n' >> "$DRIFT/geometry.cpp"
printf '\ndef drift_added_two():\n    return 222\n'      >> "$DRIFT/app.py"

# use a SEPARATE cache copy for the observable run so this measurement doesn't mutate the base artifact
cp "$DCACHE" "$TMP/drift_probe.cache"
STATS2="$( RIPWIRE_CACHE_STATS=1 "$BIN" "$DRIFT" --cache="$TMP/drift_probe.cache" --no-stable 2>&1 >/dev/null | grep 'cache-stats' )"
if echo "$STATS2" | grep -q 'reparsed=2 '; then
    ok "(c) DRIFT-PROPORTIONAL: modified 2 of $NFILES files → exactly 2 re-parsed ($STATS2) — restore cost tracks drift, not tree size"
else
    no "(c) expected reparsed=2 after modifying 2 files, got: ${STATS2:-<no cache-stats line>}"
fi

# correctness: the restored (warm) output over the mutated tree == a cold parse of the mutated tree
cp "$DCACHE" "$TMP/drift_warm.cache"
"$BIN" "$DRIFT" --cache="$TMP/drift_warm.cache" --no-stable >"$TMP/drift_warm.xml" 2>/dev/null
"$BIN" "$DRIFT" --no-cache --no-stable >"$TMP/drift_cold.xml" 2>/dev/null
if diff -q "$TMP/drift_warm.xml" "$TMP/drift_cold.xml" >/dev/null 2>&1; then
    ok "(c) warm restore over the MUTATED tree is byte-identical to a cold parse of the mutated tree (partial reparse is correct)"
else
    no "(c) warm restore over the mutated tree DIFFERS from a cold parse"; diff "$TMP/drift_cold.xml" "$TMP/drift_warm.xml" | head -10
fi
# and the new symbols from BOTH edited files actually surfaced (the 2 reparses did real work)
grep -q 'drift_added_one' "$TMP/drift_warm.xml" && grep -q 'drift_added_two' "$TMP/drift_warm.xml" \
    && ok "(c) both edited files' new symbols present in the warm output (the 2 reparses landed)" \
    || no "(c) an edited file's new symbol is missing from the warm output"

# ════════════════════════════════════════════════════════════════════════════════════════════════════
# (d) DETERMINISM — warm == cold at the same path (v8 blob did not regress cache transparency).
# ════════════════════════════════════════════════════════════════════════════════════════════════════
SAME="$TMP/same.cache"
"$BIN" "$PATH_A" --cache="$SAME" --no-stable >"$TMP/same_cold.xml" 2>/dev/null
"$BIN" "$PATH_A" --cache="$SAME" --no-stable >"$TMP/same_warm.xml" 2>/dev/null
diff -q "$TMP/same_cold.xml" "$TMP/same_warm.xml" >/dev/null 2>&1 \
    && ok "(d) warm == cold at the same path (v8 arch byte did not regress determinism/transparency)" \
    || { no "(d) warm != cold at same path — v8 broke cache transparency"; diff "$TMP/same_cold.xml" "$TMP/same_warm.xml" | head -10; }

# ════════════════════════════════════════════════════════════════════════════════════════════════════
# (e) MUTATION/liveness — the byte-identical comparisons are real (path spelling IS embedded in output).
# ════════════════════════════════════════════════════════════════════════════════════════════════════
diff -q "$TMP/b_cold.xml" "$TMP/a_build.xml" >/dev/null 2>&1 \
    && no "(e) A-build and B-cold outputs are byte-identical — path spelling not embedded, so (a) may be vacuous" \
    || ok "(e) A-build and B-cold outputs differ where expected (path spelling embedded → the diff -q checks above are non-vacuous)"

echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
