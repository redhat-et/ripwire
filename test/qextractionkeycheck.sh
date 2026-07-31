#!/usr/bin/env bash
# qextractionkeycheck.sh — r27 P0.2 gate: the quality cache blobs must be keyed on the EXTRACTION IDENTITY.
#
# THE BUG THIS PINS. A quality Snapshot's entire contents (canonIds, ccx/loc/nest/params, raw-body hashes,
# clone groups, the dead set, the public-API set) are functions of tree-sitter extraction — yet neither
# `kCacheVersion` nor `kParserVer` appeared in the qsnap/qbody blob header OR in the sha-keyed filename. It
# already fired: commit 28c7d32 bumped kParserVer 28 -> 30 for a `qualifierOf` fix that corrected 80 wrong
# canonical ids, WITHOUT bumping kQSnapCacheScheme. The ingest blob self-heals on its own header guard; the
# qsnap blob did not — it was simply re-served. Layered on the r26 origin split that is the dangerous part: a
# stale baseline holds the WRONG canonId, so the working tree's correct canonId is absent from the baseline,
# so a REAL regression classifies origin="new-symbol" and silently does not gate.
#
# It shipped because `test/qschemetripcheck.sh` hashed six quality.h functions and never looked at ingest.cpp.
# That blind spot is closed in two places: qschemetripcheck.sh now hashes the ingest-side constant lines too,
# and check (a) below asserts the two files agree EXACTLY. Bumping kParserVer without updating quality.h's
# mirror is now a hard suite failure, not a silent cache poisoning.
#
# Checks:
#   (a) MIRROR EQUALITY — quality.h's kIngestCacheVersionMirror/kIngestParserVerMirror equal ingest.cpp's
#       kCacheVersion/kParserVer. The one check that makes a cross-translation-unit mirror safe.
#   (b) FILENAME KEY — exclConfigHex folds BOTH the extraction identity and maxFileBytes into its key material
#       (source-text), so an old-extraction or differently-sized blob is never NAMED again. Correctness comes
#       from the key, not from purging blobs (owner decision, r27: disk is cheap, a purge is a one-shot).
#   (c) BLOB HEADER — serializeSnapshot writes both constants and deserializeSnapshot REJECTS on either
#       mismatch (source-text), so a blob reached by any other route is rejected rather than believed.
#   (d) HEADER BYTES — the qsnap blob on disk literally carries [magic][scheme][cacheVer][parserVer] with the
#       live constant values (behavioral, byte-level).
#   (e) RESTORE-EQUIVALENCE — a WARM --quality-delta run is byte-identical to a fully COLD one on a non-empty
#       regression set. The acceptance criterion for the whole fix: correctness must not depend on cache state.
#   (f) maxFileBytes KEY SEPARATION — a --max-file-size run keys a DISTINCT qsnap blob instead of warm-hitting
#       the default run's (quality.h threaded the ceiling into the HEAD ingest but keyed only on excludes).
#
# Uses its own temp repo + a private XDG_CACHE_HOME (TMPDIR unset), like qsnapcachecheck.sh. Needs git.
# Usage:  test/qextractionkeycheck.sh   |   CTXPACK_BIN=build/ctxpack test/qextractionkeycheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
QSRC="$ROOT/src/quality.h"
ISRC="$ROOT/src/ingest.cpp"
fail=0
ok(){ echo "  PASS  $1"; }
no(){ echo "  FAIL  $1"; fail=1; }

[ -x "$BIN" ]  || { echo "no ctxpack binary at $BIN — build first"; exit 2; }
[ -f "$QSRC" ] || { echo "no $QSRC — run from the repo"; exit 2; }
[ -f "$ISRC" ] || { echo "no $ISRC — run from the repo"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }

echo "qextractionkeycheck: BIN=$BIN"

# ── (a) the mirror must equal the real thing ───────────────────────────────────────────────────────────────
# Both sides are `constexpr std::uint32_t <name> = <n>;` possibly followed by a trailing comment.
constval(){ sed -n "s/^constexpr[ \t][^=]*[ \t]$2[ \t]*=[ \t]*\([0-9][0-9]*\).*/\1/p" "$1" | head -1; }
ING_CACHE="$( constval "$ISRC" kCacheVersion )"
ING_PARSER="$( constval "$ISRC" kParserVer )"
Q_CACHE="$( constval "$QSRC" kIngestCacheVersionMirror )"
Q_PARSER="$( constval "$QSRC" kIngestParserVerMirror )"

if [ -z "$ING_CACHE" ] || [ -z "$ING_PARSER" ] || [ -z "$Q_CACHE" ] || [ -z "$Q_PARSER" ]; then
    no "could not read all four constants (ingest kCacheVersion='$ING_CACHE' kParserVer='$ING_PARSER'; quality mirror='$Q_CACHE'/'$Q_PARSER') — a declaration was renamed/reshaped"
else
    [ "$ING_CACHE" = "$Q_CACHE" ] \
        && ok "kIngestCacheVersionMirror ($Q_CACHE) == ingest.cpp kCacheVersion ($ING_CACHE)" \
        || no "MIRROR DRIFT: quality.h kIngestCacheVersionMirror=$Q_CACHE but ingest.cpp kCacheVersion=$ING_CACHE — update src/quality.h in the SAME diff (a stale qsnap blob would be re-served)"
    [ "$ING_PARSER" = "$Q_PARSER" ] \
        && ok "kIngestParserVerMirror ($Q_PARSER) == ingest.cpp kParserVer ($ING_PARSER)" \
        || no "MIRROR DRIFT: quality.h kIngestParserVerMirror=$Q_PARSER but ingest.cpp kParserVer=$ING_PARSER — update src/quality.h in the SAME diff (this is exactly the 28c7d32 failure)"
fi

# ── (b) the FILENAME key folds extraction identity + maxFileBytes ──────────────────────────────────────────
keymat="$( awk '/^inline std::string exclConfigHex\(/,/^}/' "$QSRC" )"
printf '%s' "$keymat" | grep -q 'extractionIdentityTag()' \
    && ok "exclConfigHex folds extractionIdentityTag() into the filename key" \
    || no "exclConfigHex does NOT fold the extraction identity — an old-parserVer blob is still NAMED and served"
printf '%s' "$keymat" | grep -q 'maxFileBytes' \
    && ok "exclConfigHex folds maxFileBytes into the filename key" \
    || no "exclConfigHex does NOT fold maxFileBytes — a default run and a --max-file-size run share one blob"
for fn in headSnapExclHex qsnapExclHex qbodyExclHex; do
    awk "/^inline std::string $fn\(/,/^}/" "$QSRC" | grep -q 'maxFileBytes' \
        && ok "$fn threads maxFileBytes through to the key" \
        || no "$fn drops maxFileBytes — its family keys ignore the file-size ceiling"
done

# ── (c) the BLOB HEADER carries and VERIFIES the extraction identity ───────────────────────────────────────
ser="$( awk '/^inline std::string serializeSnapshot\(/,/^}/' "$QSRC" )"
printf '%s' "$ser" | grep -q 'qsnapPut( buf, kIngestCacheVersionMirror )' \
 && printf '%s' "$ser" | grep -q 'qsnapPut( buf, kIngestParserVerMirror )' \
    && ok "serializeSnapshot writes both extraction-identity fields into the blob header" \
    || no "serializeSnapshot does not write the extraction identity into the blob header"
de="$( awk '/^inline bool deserializeSnapshot\(/,/^}/' "$QSRC" )"
printf '%s' "$de" | grep -q 'blobCacheVer  != kIngestCacheVersionMirror' \
 && printf '%s' "$de" | grep -q 'blobParserVer != kIngestParserVerMirror' \
    && ok "deserializeSnapshot REJECTS a blob whose extraction identity differs" \
    || no "deserializeSnapshot does not verify the blob's extraction identity — a foreign blob is believed"

# ── behavioral half: a temp repo with a real, non-vacuous regression ───────────────────────────────────────
REPO="$( mktemp -d )"; TMP="$( mktemp -d )"; trap 'rm -rf "$REPO" "$TMP"' EXIT
XDG="$TMP/xdg"; mkdir -p "$XDG"
CACHEDIR="$XDG/ctxpack"
qsnapfiles(){ find "$CACHEDIR" -maxdepth 2 -type f -name 'ctxpack-qsnap-*.bin' 2>/dev/null; }
nqsnap(){ qsnapfiles | wc -l | tr -d ' '; }
run(){ env -u TMPDIR XDG_CACHE_HOME="$XDG" "$BIN" "$REPO" --quality-delta "$@"; }

mkdir -p "$REPO/src"
cat > "$REPO/src/lib.cpp" <<'EOF'
int helper( int x ) { int s = 0; for( int i = 0; i < x; ++i ) { s += i * 2; } return s; }
int mainThing( int y ) { int t = y; while( t > 1 ) { t = t - 1; } return t; }
EOF
git -C "$REPO" init -q; git -C "$REPO" config user.email x@y; git -C "$REPO" config user.name x
git -C "$REPO" add -A; git -C "$REPO" commit -qm init

# an uncommitted regression so the compared output is NOT the trivial empty report.
cat >> "$REPO/src/lib.cpp" <<'EOF'
int addedComplex( int a, int b, int c ) {
    int r = 0;
    for( int i = 0; i < a; ++i ) {
        if( i % 2 == 0 ) { if( i > b ) { r += i; } else { r -= 1; } }
        else { for( int j = 0; j < b; ++j ) { if( j > c ) { r += j; } else { r--; } } }
        while( r > c && r > b ) { r = r - 1; if( r % 3 == 0 ) { r += 2; } }
    }
    return r;
}
EOF

# ── (d) the blob's header bytes are [magic][scheme][cacheVer][parserVer], with the live values ─────────────
run >"$TMP/warm1" 2>/dev/null
QF="$( qsnapfiles | head -1 )"
if [ -z "$QF" ]; then
    no "no ctxpack-qsnap-*.bin blob written — cannot inspect the header"
else
    # od the first 16 bytes; fields are native-endian u32 (documented: same-machine blob, checksum otherwise).
    hdr="$( od -An -tu4 -j4 -N12 "$QF" | tr -s ' ' )"
    set -- $hdr
    B_SCHEME="${1:-}"; B_CACHE="${2:-}"; B_PARSER="${3:-}"
    magic="$( dd if="$QF" bs=1 count=4 2>/dev/null )"
    [ "$magic" = "QSNP" ] && ok "qsnap blob starts with the QSNP magic" || no "qsnap blob magic is '$magic', not QSNP"
    { [ "$B_CACHE" = "$ING_CACHE" ] && [ "$B_PARSER" = "$ING_PARSER" ]; } \
        && ok "qsnap blob header carries the live extraction identity (scheme=$B_SCHEME cacheVer=$B_CACHE parserVer=$B_PARSER)" \
        || no "qsnap blob header extraction identity is cacheVer=$B_CACHE parserVer=$B_PARSER, expected $ING_CACHE/$ING_PARSER"
fi

# ── (e) RESTORE-EQUIVALENCE: warm == fully cold, on a non-empty regression set ─────────────────────────────
run >"$TMP/warm2" 2>/dev/null; rcw=$?
env -u TMPDIR XDG_CACHE_HOME="$TMP/coldxdg" "$BIN" "$REPO" --quality-delta >"$TMP/cold" 2>/dev/null; rcc=$?
grep -q 'kind="complexity"' "$TMP/cold" \
    && ok "the fixture reports a real regression (comparison is non-vacuous)" \
    || no "fixture reported no regression — the equivalence check below would be vacuous"
{ diff -q "$TMP/warm2" "$TMP/cold" >/dev/null && [ "$rcw" -eq "$rcc" ]; } \
    && ok "RESTORE-EQUIVALENCE: warm run byte-identical to a fully cold run (exit $rcw == $rcc)" \
    || { no "warm run differs from a cold run (exit warm=$rcw cold=$rcc) — a cached Snapshot changed the answer"; diff "$TMP/cold" "$TMP/warm2" | head -8; }
diff -q "$TMP/warm1" "$TMP/warm2" >/dev/null \
    && ok "two warm runs are byte-identical (determinism law)" \
    || no "two warm runs differ — non-deterministic quality-delta"

# ── (f) maxFileBytes keys a DISTINCT blob ──────────────────────────────────────────────────────────────────
before="$( nqsnap )"
run --max-file-size=100M >"$TMP/big" 2>/dev/null
after="$( nqsnap )"
[ "$after" -gt "$before" ] \
    && ok "--max-file-size keys a DISTINCT qsnap blob (count $before -> $after)" \
    || no "--max-file-size warm-HIT the default run's blob (count $before -> $after) — the file-size ceiling is not in the key"

[ "$fail" -eq 0 ] && echo "qextractionkeycheck: ALL PASS" || { echo "qextractionkeycheck: SOME CHECKS FAILED"; exit 1; }
