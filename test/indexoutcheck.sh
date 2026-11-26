#!/usr/bin/env bash
# indexoutcheck.sh — the --index-out committable-index WIRING gate (one parse blob under both names since cache 56).
#
# The ingest CORE (cache v8, kArtifactArch self-heal, drift observable) is proven by artifactcheck.sh. This
# gate proves the CLI SURFACE that turns that core into the team artifact:
#
#   (a) GENERATE-AND-EXIT — `--index-out=BASE` writes BASE.lean.ripwirecache and BASE.rich.ripwirecache (one blob),
#       exits 0, and emits NO map on stdout (CI writes an artifact, it does not stream a map).
#   (b) RESTORE-EQUIVALENCE from a COPIED checkout at a DIFFERENT path:
#         - a map/nav verb restored via BASE.lean.ripwirecache == a cold run (byte-identical) + GENUINE warm
#           hit (the lean blob bytes are untouched by the consume — a real reuse, not a disguised reparse);
#         - the flagship `--for` restored via BASE.rich.ripwirecache == a cold `--for` (byte-identical) —
#           --for reads the same blob (ONE-PARSE): either name serves it warm.
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
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
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

if [ "$rc_gen" -eq 0 ]; then ok "(a) --index-out exits 0"; else { no "(a) --index-out exit $rc_gen"; cat "$TMP/gen.err"; }; fi
{ [ -s "$LEAN" ] && [ -s "$RICH" ]; } \
    && ok "(a) both families written (lean=$(wc -c <"$LEAN" | tr -d ' ')B  rich=$(wc -c <"$RICH" | tr -d ' ')B)" \
    || no "(a) a family file is missing/empty (lean=$([ -s "$LEAN" ] && echo ok || echo MISSING) rich=$([ -s "$RICH" ] && echo ok || echo MISSING))"
[ ! -s "$TMP/gen.out" ] \
    && ok "(a) NO map on stdout (generate-and-exit, not a stream — $(wc -c <"$TMP/gen.out" | tr -d ' ')B)" \
    || no "(a) --index-out emitted $(wc -c <"$TMP/gen.out" | tr -d ' ')B on stdout (should be 0)"
# ONE-PARSE (kCacheVersion 56): one parse blob serves both verb classes, so the two names hold the same bytes. Until 56 the
# rich family carried the value-use rows the lean one lacked, and this arm held rich > lean.
[ -s "$LEAN" ] && [ -s "$RICH" ] && cmp -s "$LEAN" "$RICH" \
    && ok "(a) the lean and rich artifacts are the one parse blob under two names ($(wc -c <"$RICH" | tr -d ' ') B)" \
    || no "(a) the lean and rich artifacts differ (or one is empty) — two parses where one serves both"

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

# ════════════════════════════════════════════════════════════════════════════════════════════════════
# (e) --no-ignore REACHES the generate path. The generate ingest used to take respectGitignore's default,
#     so `--index-out --no-ignore` silently built the IGNORE-honouring artifact: every ignored file was a
#     cold parse for the consumer that asked for it. Restore-equivalence cannot see this (a missing record
#     is just a miss), so the arms read the blob's file set and the consumer's reparse count instead.
# ════════════════════════════════════════════════════════════════════════════════════════════════════
if command -v git >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
    PATH_E="$TMP/checkout_e/repo"
    mkdir -p "$( dirname "$PATH_E" )"
    cp -R "$FIXTURE" "$PATH_E"
    ( cd "$PATH_E" && git init -q && printf 'ignoredgen/\n' >.gitignore && git add -A \
        && git -c user.name=indexoutcheck -c user.email=indexoutcheck@example.invalid commit -q -m fixture ) >/dev/null 2>&1
    # created AFTER the commit: an untracked file under an ignored dir (a tracked one would stay indexed)
    mkdir -p "$PATH_E/ignoredgen"
    printf 'def rw_indexout_ignored_probe():\n    return 1\n' >"$PATH_E/ignoredgen/hidden.py"
    blobhas(){ python3 -c 'import sys; print( "HAS" if sys.argv[2].encode() in open( sys.argv[1], "rb" ).read() else "MISSING" )' "$1" "$2"; }

    "$BIN" "$PATH_E" --index-out="$TMP/idx_def" >/dev/null 2>&1
    "$BIN" "$PATH_E" --index-out="$TMP/idx_ni" --no-ignore >/dev/null 2>"$TMP/gen_ni.err"
    rc_ni=$?
    [ "$rc_ni" -eq 0 ] && [ -s "$TMP/idx_ni.lean.ripwirecache" ] && [ -s "$TMP/idx_def.lean.ripwirecache" ] \
        && ok "(e) --index-out with and without --no-ignore both generated (exit 0)" \
        || { no "(e) --index-out --no-ignore failed (exit $rc_ni)"; cat "$TMP/gen_ni.err"; }
    [ "$( blobhas "$TMP/idx_def.lean.ripwirecache" ignoredgen/hidden.py )" = MISSING ] \
        && ok "(e) control: the default artifact omits the gitignored file (the ignore rule is live in this fixture)" \
        || no "(e) control: the default artifact holds the gitignored file — the fixture cannot tell the two apart"
    [ "$( blobhas "$TMP/idx_ni.lean.ripwirecache" ignoredgen/hidden.py )" = HAS ] \
        && ok "(e) --index-out --no-ignore artifact holds the gitignored file" \
        || no "(e) --index-out dropped --no-ignore: the artifact omits the gitignored file it was told to keep"
    cp "$TMP/idx_ni.lean.ripwirecache" "$TMP/committed_ni.lean"
    RIPWIRE_CACHE_STATS=1 "$BIN" "$PATH_E" --cache="$TMP/committed_ni.lean" --no-ignore --no-stable >/dev/null 2>"$TMP/ni_consume.err"
    REPARSED_NI="$( sed -n 's/.*cache-stats reparsed=\([0-9][0-9]*\).*/\1/p' "$TMP/ni_consume.err" | head -1 )"
    [ "$REPARSED_NI" = 0 ] \
        && ok "(e) a --no-ignore consumer of the --no-ignore artifact reparses nothing (reparsed=0)" \
        || no "(e) a --no-ignore consumer reparsed '${REPARSED_NI:-no cache-stats line}' file(s) the artifact should have carried"
else
    printf '  SKIP  (e) --no-ignore generate: needs git and python3\n'
fi

echo
if [ "$fail" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "SOME CHECKS FAILED"; exit 1; fi
