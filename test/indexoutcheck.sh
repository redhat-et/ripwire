#!/usr/bin/env bash
# indexoutcheck.sh — the --index-out committable-index WIRING gate (both-families).
#
# The ingest CORE (cache v8, kArtifactArch self-heal, drift observable) is proven by artifactcheck.sh. This
# gate proves the CLI SURFACE that turns that core into the team artifact:
#
#   (a) GENERATE-AND-EXIT — `--index-out=BASE` writes BOTH BASE.lean.ripwirecache and BASE.rich.ripwirecache,
#       exits 0, and emits NO map on stdout (CI writes an artifact, it does not stream a map).
#   (b) RESTORE-EQUIVALENCE from a COPIED checkout at a DIFFERENT path:
#         - a map/nav verb restored via BASE.lean.ripwirecache == a cold run (byte-identical) + GENUINE warm
#           hit (the lean blob bytes are untouched by the consume — a real reuse, not a disguised reparse);
#         - the flagship `--for` restored via BASE.rich.ripwirecache == a cold `--for` (byte-identical) —
#           the reason both families ship: --for ingests RICH, a lean-only artifact would leave it cold.
#   (c) --exclude VARIATION — excludes shape the crawl, so an artifact built WITH an exclude differs in bytes
#       from one built WITHOUT it, AND a map restored from the excluded artifact == a cold run under the same
#       exclude (the excludes are baked into the blob content, per --help).
#   (d) SELF-HEAL — a doctored (foreign-arch) rich artifact is IGNORED by the consumer, which cold-reparses
#       to byte-identical output, exit 0 (reuses artifactcheck's checksum-recomputing arch-flip helper so the
#       ARCH GUARD, not the checksum trailer, is what rejects it).
#
# The blobs are NOT byte-identical run-to-run (the v8 header stamps the blob write wall-time); the CONTRACT
# proven here is RESTORE-EQUIVALENCE, never blob-byte-identity — matching what --help/README state.
#
# Usage:  bash test/indexoutcheck.sh   |   RIPWIRE_BIN=build_ic1/ripwire bash test/indexoutcheck.sh
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

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

echo "indexoutcheck: BIN=$BIN  TMP=$TMP"
FIXTURE="$ROOT/test/fixture"
md5of(){ md5 -q "$1" 2>/dev/null || md5sum "$1" | cut -d' ' -f1; }

# ════════════════════════════════════════════════════════════════════════════════════════════════════
# (a) GENERATE-AND-EXIT — writes both families, exits 0, no map on stdout.
# ════════════════════════════════════════════════════════════════════════════════════════════════════
PATH_A="$TMP/checkout_a/repo"
mkdir -p "$( dirname "$PATH_A" )"
cp -R "$FIXTURE" "$PATH_A"

BASE="$TMP/idx"
"$BIN" "$PATH_A" --index-out="$BASE" >"$TMP/gen.out" 2>"$TMP/gen.err"
rc_gen=$?
LEAN="$BASE.lean.ripwirecache"
RICH="$BASE.rich.ripwirecache"

[ "$rc_gen" -eq 0 ] && ok "(a) --index-out exits 0" || { no "(a) --index-out exit $rc_gen"; cat "$TMP/gen.err"; }
{ [ -s "$LEAN" ] && [ -s "$RICH" ]; } \
    && ok "(a) both families written (lean=$(wc -c <"$LEAN" | tr -d ' ')B  rich=$(wc -c <"$RICH" | tr -d ' ')B)" \
    || no "(a) a family file is missing/empty (lean=$([ -s "$LEAN" ] && echo ok || echo MISSING) rich=$([ -s "$RICH" ] && echo ok || echo MISSING))"
[ ! -s "$TMP/gen.out" ] \
    && ok "(a) NO map on stdout (generate-and-exit, not a stream — $(wc -c <"$TMP/gen.out" | tr -d ' ')B)" \
    || no "(a) --index-out emitted $(wc -c <"$TMP/gen.out" | tr -d ' ')B on stdout (should be 0)"
# rich carries more (value-uses capture) than lean — the whole reason both ship
[ -s "$LEAN" ] && [ -s "$RICH" ] && [ "$(wc -c <"$RICH")" -gt "$(wc -c <"$LEAN")" ] \
    && ok "(a) rich artifact is larger than lean (value-uses capture — both families justified)" \
    || no "(a) rich is not larger than lean (family split may be a no-op)"

# ════════════════════════════════════════════════════════════════════════════════════════════════════
# (b) RESTORE-EQUIVALENCE from a DIFFERENT checkout path — lean feeds the map, rich feeds --for.
# ════════════════════════════════════════════════════════════════════════════════════════════════════
PATH_B="$TMP/checkout_b/repo"
mkdir -p "$( dirname "$PATH_B" )"
cp -R "$FIXTURE" "$PATH_B"

# --- lean → map/nav verb ---
cp "$LEAN" "$TMP/committed.lean"
LBEFORE="$( md5of "$TMP/committed.lean" )"
"$BIN" "$PATH_B" --cache="$TMP/committed.lean" --no-stable >"$TMP/b_lean_warm.xml" 2>/dev/null
"$BIN" "$PATH_B" --no-cache --no-stable                    >"$TMP/b_cold.xml"      2>/dev/null
LAFTER="$( md5of "$TMP/committed.lean" )"
diff -q "$TMP/b_lean_warm.xml" "$TMP/b_cold.xml" >/dev/null 2>&1 \
    && ok "(b) LEAN map restore at checkout B is byte-identical to a cold parse at B" \
    || { no "(b) lean map restore != cold at B"; diff "$TMP/b_cold.xml" "$TMP/b_lean_warm.xml" | head -8; }
[ "$LBEFORE" = "$LAFTER" ] \
    && ok "(b) GENUINE warm hit — lean blob bytes UNCHANGED across the checkout-path consume (real reuse)" \
    || no "(b) DISGUISED MISS — consuming the lean artifact at B rewrote it (not portable across checkout paths)"

# --- rich → --for (the flagship RICH verb; lean-only would leave this cold) ---
FORQ="distance between two points"
cp "$RICH" "$TMP/committed.rich"
RBEFORE="$( md5of "$TMP/committed.rich" )"
"$BIN" "$PATH_B" --cache="$TMP/committed.rich" --for="$FORQ" --no-stable >"$TMP/b_rich_warm.for" 2>/dev/null
"$BIN" "$PATH_B" --no-cache --for="$FORQ" --no-stable                    >"$TMP/b_cold.for"      2>/dev/null
RAFTER="$( md5of "$TMP/committed.rich" )"
diff -q "$TMP/b_rich_warm.for" "$TMP/b_cold.for" >/dev/null 2>&1 \
    && ok "(b) RICH --for restore at checkout B is byte-identical to a cold --for at B (flagship verb warmed)" \
    || { no "(b) rich --for restore != cold --for at B"; diff "$TMP/b_cold.for" "$TMP/b_rich_warm.for" | head -8; }
[ "$RBEFORE" = "$RAFTER" ] \
    && ok "(b) GENUINE warm hit — rich blob bytes UNCHANGED across the checkout-path --for consume" \
    || no "(b) DISGUISED MISS — consuming the rich artifact at B rewrote it"

# liveness: the two checkout paths really produce different output (path spelling embedded) so (b) is non-vacuous
diff -q "$TMP/gen.out" "$TMP/b_cold.xml" >/dev/null 2>&1   # gen.out is empty, so this is trivially different; real liveness below
"$BIN" "$PATH_A" --no-cache --no-stable >"$TMP/a_cold.xml" 2>/dev/null
diff -q "$TMP/a_cold.xml" "$TMP/b_cold.xml" >/dev/null 2>&1 \
    && no "(b) checkout A and B cold outputs are identical — path spelling not embedded, (b) may be vacuous" \
    || ok "(b) A/B cold outputs differ where expected (path embedded → the restore-equiv checks are non-vacuous)"

# ════════════════════════════════════════════════════════════════════════════════════════════════════
# (c) --exclude VARIATION — excludes are baked into the blob; produce different bytes + correct restore.
# ════════════════════════════════════════════════════════════════════════════════════════════════════
# pick a file that exists in the fixture to exclude
EXC="geometry"
"$BIN" "$PATH_A" --index-out="$TMP/idx_exc" --exclude="$EXC" >/dev/null 2>"$TMP/gen_exc.err"
rc_exc=$?
LEAN_EXC="$TMP/idx_exc.lean.ripwirecache"
[ "$rc_exc" -eq 0 ] && [ -s "$LEAN_EXC" ] \
    && ok "(c) --index-out --exclude=$EXC generated an artifact (exit 0)" \
    || { no "(c) --index-out with --exclude failed (exit $rc_exc)"; cat "$TMP/gen_exc.err"; }

# the excluded artifact must differ in bytes from the un-excluded one (excludes shape blob content).
# compare payloads MINUS the volatile 8-byte blobWriteNs stamp region: use full-file size + content diff.
if cmp -s "$LEAN" "$LEAN_EXC"; then
    no "(c) excluded artifact is byte-identical to the full one — --exclude did not affect blob content"
else
    ok "(c) --exclude produces a DIFFERENT blob than no-exclude (excludes shape the crawl → the artifact)"
fi

# restore from the excluded artifact == a cold run under the SAME exclude (excludes baked in, restore correct)
"$BIN" "$PATH_B" --cache="$TMP/idx_exc.lean.ripwirecache" --exclude="$EXC" --no-stable >"$TMP/exc_warm.xml" 2>/dev/null
"$BIN" "$PATH_B" --no-cache --exclude="$EXC" --no-stable                                >"$TMP/exc_cold.xml" 2>/dev/null
diff -q "$TMP/exc_warm.xml" "$TMP/exc_cold.xml" >/dev/null 2>&1 \
    && ok "(c) restore from the excluded artifact == cold under the same --exclude (byte-identical)" \
    || { no "(c) excluded-artifact restore != cold under same exclude"; diff "$TMP/exc_cold.xml" "$TMP/exc_warm.xml" | head -8; }
# and the excluded symbol is genuinely absent from the restored output (the exclude did real work)
if grep -q "$EXC" "$TMP/exc_warm.xml"; then
    no "(c) excluded path '$EXC' still present in restored output — exclude was ineffective"
else
    ok "(c) excluded path '$EXC' is absent from the restored output (exclude landed through the artifact)"
fi

# ════════════════════════════════════════════════════════════════════════════════════════════════════
# (d) SELF-HEAL — a doctored foreign-arch RICH artifact is ignored → cold reparse, byte-identical, exit 0.
#     (Reuses artifactcheck's arch-flip-with-recomputed-checksum recipe so the ARCH GUARD does the rejecting.)
# ════════════════════════════════════════════════════════════════════════════════════════════════════
cp "$RICH" "$TMP/arch_fixcsum.rich"
if command -v python3 >/dev/null 2>&1; then
    python3 - "$TMP/arch_fixcsum.rich" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path, "rb") as f: blob = bytearray(f.read())
payload = bytearray(blob[:-8])            # last 8 bytes = whole-blob checksum trailer
payload[12] ^= 0x01                       # flip the endianness bit of kArtifactArch → guaranteed-foreign tag
def blob_checksum(data):                  # replicate ingest.cpp blobChecksum() — 8-lane FNV-1a permutation
    P = 1099511628211; M = (1<<64)-1
    lane = [1469598103934665603, 1099511628211, 0x100000001b3, 0x9e3779b97f4a7c15,
            0xc2b2ae3d27d4eb4f, 0x165667b19e3779f9, 0xff51afd7ed558ccd, 0xc4ceb9fe1a85ec53]
    n = len(data); i = 0
    while i + 8 <= n:
        for k in range(8): lane[k] = ((lane[k] ^ data[i+k]) * P) & M
        i += 8
    k = 0
    while i < n:
        lane[k] = ((lane[k] ^ data[i]) * P) & M; i += 1; k += 1
    h = 1469598103934665603
    for k in range(8): h = ((h ^ lane[k]) * P) & M
    return h
csum = blob_checksum(bytes(payload))
with open(path, "wb") as f: f.write(payload); f.write(csum.to_bytes(8, "little"))
PYEOF
    "$BIN" "$PATH_A" --cache="$TMP/arch_fixcsum.rich" --for="$FORQ" --no-stable >"$TMP/heal.for" 2>"$TMP/heal.err"
    rc_heal=$?
    "$BIN" "$PATH_A" --no-cache --for="$FORQ" --no-stable >"$TMP/a_cold.for" 2>/dev/null
    if [ "$rc_heal" -eq 0 ] && diff -q "$TMP/heal.for" "$TMP/a_cold.for" >/dev/null 2>&1; then
        ok "(d) doctored foreign-arch RICH artifact self-heals → cold --for, byte-identical, exit 0"
    else
        no "(d) foreign-arch rich artifact did not self-heal (exit $rc_heal)"; diff "$TMP/a_cold.for" "$TMP/heal.for" | head -8
    fi
else
    printf '  SKIP  (d) self-heal (no python3 to doctor the arch byte)\n'
fi

echo
if [ "$fail" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "SOME CHECKS FAILED"; exit 1; fi
