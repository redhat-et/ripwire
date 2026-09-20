#!/usr/bin/env bash
# qsnapproducercheck.sh — a cached HEAD Snapshot is served only to the build that computed it.
#
# THE BUG THIS PINS. --quality-delta caches its computed HEAD-side Snapshot (the "qsnap" blob), and that
# Snapshot's dead set is a function of CALL RESOLUTION: quality.h's isDeadCandidate reads g.inEdges, and the
# Python dispatch exemption reads the graph too. The blob's filename key folded the qsnap scheme, the
# extraction identity (kCacheVersion + kParserVer mirrors), the excludes, the file-size ceiling and the HEAD
# sha — nothing that moves when only resolution changes, and resolution-only changes bump none of those by
# rule (a resolver runs over cached ingest facts). So two builds that resolve calls differently, sharing one
# cache dir on one repo HEAD, served each other's dead set.
#
# MEASURED before the fix, two real builds of main a55b118e — as built, and with graph.h's
# keepStdQualifiedCandidates switched off (the std::-qualified call guard of d39554dd, a resolution-only
# change whose own commit message reasons "no graph or edge blob is cached") — on a two-file fixture where
# `std::launder( &v )` either binds an in-repo `Pool::launder` or does not:
#   * the guarded build, cold cache:                       regressions="0", exit 0
#   * the same build after the unguarded one warmed it:     regressions="1", a GATING dead-code row on the
#                                                           untouched Pool::launder, exit 2 (a phantom)
#   * the unguarded build, working tree deleting the only
#     call, cold:                                           the real gating dead-code row, exit 2
#   * the same run after the guarded build warmed it:       regressions="0", exit 0 (a real regression HIDDEN)
# One qsnap blob in the shared dir in both cases: one key for two answers.
#
# THE FIX. The qsnap and qbody keys, and the shared blob header, carry the PRODUCER IDENTITY — the SHA-256 of
# the build's own source content (every file under src/ and queries/), derived per build by
# cmake/source_identity.cmake. It is derived, not bumped by hand, on the record of this one cache: B10.1a's
# isDeadCandidate exemption (retired late, at scheme v3) and 28c7d32's kParserVer bump (r27 P0.2) each changed
# what a blob means without the bump that would have retired it, and none of the twelve scheme versions cites a
# resolution change — though d39554dd weighed the caches in its own commit message.
#
# Checks:
#   (A) KEY — qsnapExclHex and qbodyExclHex fold the producer identity (source text); headSnapExclHex does not
#       (the ingest blob holds extraction facts only and is keyed by the extraction identity, so a rebuild must
#       not throw it away).
#   (B) HEADER — serializeSnapshot writes the producer hash; deserializeSnapshot refuses a mismatch (source).
#   (C) DERIVATION — cmake/source_identity.cmake prints a 64-hex identity for this tree; a copy elsewhere
#       prints the SAME one (path-independent: gates run from scratch clones); the copy with one byte of
#       src/graph.h changed prints a DIFFERENT one (the mutation is asserted to have taken first).
#   (D) BINARY — the blob this binary writes carries fnv1a64( that identity ) in its producer slot, i.e. the
#       binary under test was built from this tree's sources and records it.
#   (E) REUSE — a second run over the binary's own blob hits it: inode unchanged, no corrupt-blob alert.
#   (F) PHANTOM, a matched pair differing in ONE thing. Every dead key is dropped from the HEAD blob (a resolver
#       that saw a caller for each) and the trailer re-summed:
#         F1 producer bytes kept    -> the forged set IS served: a dead-code row the cold run does not have.
#                                      The control — proof the forgery changes the answer when believed.
#         F2 producer bytes flipped -> refused: stdout byte-identical to a cold cache, the corrupt alert on
#                                      stderr. RED before the fix: the blob had no producer bytes to flip.
#   (G) HIDDEN, the same pair in the other direction. The working tree deletes useIt's only call (a real gating
#       dead-code regression); useIt's key is added to the HEAD blob's dead set (a resolver that never saw
#       that call), the key read from a blob of a scratch commit where useIt really is dead:
#         G1 producer bytes kept    -> served: the regression is hidden (control).
#         G2 producer bytes flipped -> refused: the regression is reported, exit == the cold run's.
#
# Uses its own temp repo and a private XDG_CACHE_HOME (TMPDIR unset), like qsnapcachecheck.sh. Needs git,
# cmake and python3. The blob is parsed by structure, not by fixed offsets: the header ends where the
# fnv1a64(HEAD sha) field sits, and a parse that does not land exactly on the trailer is a FAIL, never a guess.
# Usage:  test/qsnapproducercheck.sh   |   RIPWIRE_BIN=build/ripwire test/qsnapproducercheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/statcompat.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
QSRC="$ROOT/src/quality.h"
IDSCRIPT="$ROOT/cmake/source_identity.cmake"
CMAKE="${CMAKE:-cmake}"
fail=0
ok(){ echo "  PASS  $1" || { fail=1; echo "  FAIL  could not write the PASS line for: $1"; }; return 0; }
no(){ echo "  FAIL  $1"; fail=1; }

[ -x "$BIN" ]  || { echo "no ripwire binary at $BIN — build first"; exit 2; }
[ -f "$QSRC" ] || { echo "no $QSRC — run from the repo"; exit 2; }
command -v git     >/dev/null 2>&1 || { echo "git required"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
command -v "$CMAKE" >/dev/null 2>&1 || { echo "cmake required (set CMAKE=)"; exit 2; }

echo "qsnapproducercheck: BIN=$BIN"

REPO="$( mktemp -d )"; TMP="$( mktemp -d )"; trap 'rm -rf "$REPO" "$TMP"' EXIT

# ── (A) the FILENAME key folds the producer identity — for the two families whose blobs it describes ─────────
fnbody(){ awk "/^inline std::string $1\\(/,/^}/" "$QSRC"; }
for fn in qsnapExclHex qbodyExclHex; do
    body="$( fnbody "$fn" )"
    if [ -z "$body" ]; then
        no "(A) no $fn in src/quality.h — the key builder was renamed; point this gate at it"
    elif printf '%s' "$body" | grep -q 'producerIdentity'; then
        ok "(A) $fn folds the producer identity into the filename key"
    else
        no "(A) $fn does NOT fold the producer identity — a blob another build computed is still NAMED and served"
    fi
done
body="$( fnbody headSnapExclHex )"
if [ -z "$body" ]; then
    no "(A) no headSnapExclHex in src/quality.h — cannot check the ingest family stays build-independent"
elif printf '%s' "$body" | grep -q 'producerIdentity'; then
    no "(A) headSnapExclHex folds the producer identity — every rebuild would discard the HEAD ingest (extraction facts only, keyed by kParserVer)"
else
    ok "(A) headSnapExclHex keeps the ingest family on the extraction identity alone"
fi

# ── (B) the BLOB HEADER carries and verifies it ────────────────────────────────────────────────────────────
ser="$( awk '/^inline std::string serializeSnapshot\(/,/^}/' "$QSRC" )"
printf '%s' "$ser" | grep -q 'qsnapPut( buf, producerIdentityHash() )' \
    && ok "(B) serializeSnapshot writes the producer hash into the blob header" \
    || no "(B) serializeSnapshot does not write the producer hash — a blob cannot say which build computed it"
de="$( awk '/^inline bool deserializeSnapshot\(/,/^}/' "$QSRC" )"
printf '%s' "$de" | grep -q 'blobProducer != producerIdentityHash()' \
    && ok "(B) deserializeSnapshot refuses a blob another build computed" \
    || no "(B) deserializeSnapshot does not verify the producer — a foreign blob is believed"

# ── (C) the identity is derived from source CONTENT, and only from it ──────────────────────────────────────
identity_of(){ "$CMAKE" -DRIPWIRE_SOURCE_DIR="$1" -P "$IDSCRIPT" 2>/dev/null | sed -n 's/^-- source_identity=\([0-9a-f]\{64\}\)$/\1/p'; }
ID_ROOT=""
if [ ! -f "$IDSCRIPT" ]; then
    no "(C) no cmake/source_identity.cmake — the build derives no producer identity"
else
    ID_ROOT="$( identity_of "$ROOT" )"
    if [ -z "$ID_ROOT" ]; then
        no "(C) cmake/source_identity.cmake printed no 64-hex source_identity= line for this tree"
    else
        ok "(C) this tree's source identity: ${ID_ROOT:0:16}…"
        mkdir -p "$TMP/copy"
        cp -R "$ROOT/src" "$ROOT/queries" "$TMP/copy/"
        ID_COPY="$( identity_of "$TMP/copy" )"
        [ -n "$ID_COPY" ] && [ "$ID_COPY" = "$ID_ROOT" ] \
            && ok "(C) an unchanged copy in another directory derives the SAME identity (path-independent)" \
            || no "(C) an unchanged copy derives '${ID_COPY:0:16}' not '${ID_ROOT:0:16}' — the identity depends on where the tree sits"
        printf '\n// one byte of resolver source moved\n' >>"$TMP/copy/src/graph.h"
        if cmp -s "$ROOT/src/graph.h" "$TMP/copy/src/graph.h"; then
            no "(C) the graph.h mutation did not take — the content-sensitivity arm would compare two identical trees"
        else
            ID_MUT="$( identity_of "$TMP/copy" )"
            [ -n "$ID_MUT" ] && [ "$ID_MUT" != "$ID_ROOT" ] \
                && ok "(C) one appended line in src/graph.h derives a DIFFERENT identity (${ID_MUT:0:16}…)" \
                || no "(C) a changed src/graph.h derives the same identity — a resolver change would keep the key"
        fi
    fi
fi

# ── fixture: `std::launder` binds an in-repo Pool::launder only for a resolver without the std:: guard ───────
XDG="$TMP/xdg"; mkdir -p "$XDG"
CACHEDIR="$XDG/ripwire"
run(){ env -u TMPDIR XDG_CACHE_HOME="$XDG" "$BIN" "$REPO" --quality-delta --legend=compact "$@"; }
coldrun(){ rm -rf "$TMP/cold"; mkdir -p "$TMP/cold"; env -u TMPDIR XDG_CACHE_HOME="$TMP/cold" "$BIN" "$REPO" --quality-delta --legend=compact "$@"; }

mkdir -p "$REPO/src"
cat > "$REPO/src/pool.cpp" <<'EOF'
struct Pool
{
    int launder( int x ) { int s = x; for( int i = 0; i < x; ++i ) { s += i; } return s; }
};
EOF
cat > "$REPO/src/use.cpp" <<'EOF'
#include <new>
int useIt( int v ) { return *std::launder( &v ) + 1; }
int main() { return useIt( 1 ); }
EOF
git -C "$REPO" init -q; git -C "$REPO" config user.email x@y; git -C "$REPO" config user.name x
git -C "$REPO" add -A; git -C "$REPO" commit -qm init
HEADSHA="$( git -C "$REPO" rev-parse HEAD )"

cat > "$TMP/blob.py" <<'PYEOF'
# blob.py — read and forge a qsnap blob by STRUCTURE (see the gate header). Exit 3 = cannot parse.
import struct, sys

M64 = (1 << 64) - 1
def fnv1a64(data):
    h = 14695981039346656037
    for c in data:
        h = ((h ^ c) * 1099511628211) & M64
    return h

def parse(path, sha):
    blob = open(path, "rb").read()
    if len(blob) < 32:
        print("blob too short: %d bytes" % len(blob)); sys.exit(3)
    body = bytearray(blob[:-8])
    if struct.unpack("<Q", blob[-8:])[0] != fnv1a64(body) or body[:4] != b"QSNP":
        print("bad magic or trailer"); sys.exit(3)
    shaField = struct.pack("<Q", fnv1a64(sha.encode()))
    shaAt = body.find(shaField, 16, 64)
    if shaAt < 16:
        print("fnv1a64(sha) not found in the header"); sys.exit(3)
    cur = shaAt + 8
    for recBytes in (12, 12, 12, 12, 12, 12, 16, 8):      # ccx loc nest params defs mask | bodyHash | cloneGroups
        n = struct.unpack_from("<I", body, cur)[0]; cur += 4 + n * recBytes
    deadAt = cur
    n = struct.unpack_from("<I", body, cur)[0]
    dead = [struct.unpack_from("<Q", body, cur + 4 + 8 * i)[0] for i in range(n)]
    cur += 4 + n * 8
    n = struct.unpack_from("<I", body, cur)[0]; cur += 4 + n * 8   # publicApi
    if cur != len(body):
        print("structure does not end on the trailer (%d != %d)" % (cur, len(body))); sys.exit(3)
    return body, shaAt, deadAt, dead

def main():
    cmd, path, sha = sys.argv[1], sys.argv[2], sys.argv[3]
    body, shaAt, deadAt, dead = parse(path, sha)
    if cmd == "producer":
        print(body[16:shaAt].hex())
    elif cmd == "dead":
        for k in dead:
            print("%016x" % k)
    elif cmd == "forge":
        out, mode, flip = sys.argv[4], sys.argv[5], sys.argv[6] == "flip"
        keys = [] if mode == "drop-all" else sorted(set(dead) | {int(x, 16) for x in mode.split(",")})
        rec = struct.pack("<I", len(keys)) + b"".join(struct.pack("<Q", k) for k in keys)
        newBody = body[:deadAt] + rec + body[deadAt + 4 + 8 * len(dead):]
        if flip:
            for i in range(16, shaAt):
                newBody[i] ^= 0xFF
        open(out, "wb").write(bytes(newBody) + struct.pack("<Q", fnv1a64(newBody)))
        print("producer_bytes_flipped=%d" % (shaAt - 16 if flip else 0))
main()
PYEOF
blobtool(){ python3 "$TMP/blob.py" "$@"; }
shakey(){ python3 -c 'import sys
h=14695981039346656037
for c in sys.argv[1].encode(): h=((h^c)*1099511628211)&((1<<64)-1)
print("%016x"%h)' "$1"; }
blob_for(){ find "$CACHEDIR" -maxdepth 2 -type f -name "ripwire-qsnap-*-$( shakey "$1" ).bin" 2>/dev/null | head -1; }

# ── (D) the blob records this tree's identity ──────────────────────────────────────────────────────────────
echo "// touch" >> "$REPO/src/use.cpp"                       # a working-tree change, HEAD untouched
run >"$TMP/warm1" 2>"$TMP/warm1.err"
QF="$( blob_for "$HEADSHA" )"
if [ -z "$QF" ]; then
    no "(D) no qsnap blob for HEAD after a --quality-delta run — every later arm would be vacuous"
    echo "qsnapproducercheck: SOME CHECKS FAILED"; exit 1
fi
PRODUCER="$( blobtool producer "$QF" "$HEADSHA" )"; prc=$?
if [ "$prc" -ne 0 ]; then
    no "(D) the qsnap blob does not parse by structure: $PRODUCER — update blob.py with the layout change"
    echo "qsnapproducercheck: SOME CHECKS FAILED"; exit 1
fi
if [ -z "$PRODUCER" ]; then
    no "(D) the qsnap blob header carries NO producer bytes — nothing tells one build's blob from another's"
elif [ -n "$ID_ROOT" ]; then
    WANT="$( python3 -c 'import sys,struct
h=14695981039346656037
for c in sys.argv[1].encode(): h=((h^c)*1099511628211)&((1<<64)-1)
print(struct.pack("<Q",h).hex())' "$ID_ROOT" )"
    [ "$PRODUCER" = "$WANT" ] \
        && ok "(D) the blob's producer slot is fnv1a64 of this tree's source identity" \
        || no "(D) producer slot $PRODUCER != fnv1a64(source identity) $WANT — was $BIN built from THIS tree? rebuild and re-run"
else
    no "(D) the blob carries producer bytes but (C) derived no identity to compare them with"
fi

# ── (E) the binary's own blob still hits ───────────────────────────────────────────────────────────────────
I1="$( inode_of "$QF" )"
run >"$TMP/warm2" 2>"$TMP/warm2.err"
I2="$( inode_of "$QF" )"
{ [ -n "$I1" ] && [ "$I1" = "$I2" ] && ! grep -q 'cache corrupt' "$TMP/warm2.err"; } \
    && ok "(E) a second run reuses the build's own blob (inode $I1 unchanged, no corrupt alert)" \
    || { no "(E) the build's own blob was not reused (inode $I1 -> $I2) — the producer check rejects what it wrote"; head -3 "$TMP/warm2.err"; }

# ── (F) PHANTOM: a dead set from a resolver that saw more callers ──────────────────────────────────────────
coldrun >"$TMP/f_cold" 2>/dev/null; rcf=$?
DEADN="$( blobtool dead "$QF" "$HEADSHA" | wc -l | tr -d ' ' )"
if [ "$DEADN" -lt 1 ]; then
    no "(F) HEAD's dead set is empty — dropping it forges nothing (fixture drifted: Pool::launder should be dead)"
else
    cp "$QF" "$TMP/orig.bin"
    blobtool forge "$TMP/orig.bin" "$HEADSHA" "$TMP/f1.bin" drop-all keep >/dev/null
    blobtool forge "$TMP/orig.bin" "$HEADSHA" "$TMP/f2.bin" drop-all flip >"$TMP/f2.note"
    cmp -s "$TMP/orig.bin" "$TMP/f1.bin" && no "(F) the dead-set forgery did not take — F1 would serve the original blob"

    cp "$TMP/f1.bin" "$QF"
    run >"$TMP/f1_out" 2>"$TMP/f1_err"; rc1=$?
    { ! grep -q 'kind="dead-code"' "$TMP/f_cold" && grep -q 'kind="dead-code"' "$TMP/f1_out"; } \
        && ok "(F1) control: the forged dead set, producer kept, IS served — a dead-code row the cold run lacks (exit $rcf -> $rc1)" \
        || no "(F1) control did not fire (cold exit $rcf, forged exit $rc1) — the forgery cannot show a stale set is harmful"

    cp "$TMP/f2.bin" "$QF"
    run >"$TMP/f2_out" 2>"$TMP/f2_err"; rc2=$?
    if cmp -s "$TMP/f1.bin" "$TMP/f2.bin"; then
        no "(F2) the forged blob has no producer bytes to flip ($(cat "$TMP/f2.note")) — another build's dead set is indistinguishable, and is served"
    else
        { diff -q "$TMP/f_cold" "$TMP/f2_out" >/dev/null && [ "$rc2" -eq "$rcf" ]; } \
            && ok "(F2) the same forgery from ANOTHER producer is refused — output byte-identical to a cold cache (exit $rc2)" \
            || { no "(F2) a blob from another producer changed the answer (exit cold=$rcf forged=$rc2)"; diff "$TMP/f_cold" "$TMP/f2_out" | head -4; }
        grep -q 'HEAD Snapshot cache corrupt' "$TMP/f2_err" \
            && ok "(F2) the refusal is disclosed on stderr" \
            || no "(F2) the refused blob left no alert on stderr"
    fi
fi

# ── (G) HIDDEN: a dead set from a resolver that missed a caller ────────────────────────────────────────────
# useIt's key, read from a real blob: a scratch commit where main no longer calls it, warmed, then undone.
git -C "$REPO" checkout -q -- src/use.cpp
cat > "$REPO/src/use.cpp" <<'EOF'
#include <new>
int useIt( int v ) { return *std::launder( &v ) + 1; }
int main() { return 1; }
EOF
git -C "$REPO" commit -qam "drop the call"
SCRATCHSHA="$( git -C "$REPO" rev-parse HEAD )"
run >/dev/null 2>&1
SF="$( blob_for "$SCRATCHSHA" )"
git -C "$REPO" reset -q --soft HEAD~1                        # HEAD back to init; the working tree keeps the deletion
rm -f "$QF"; run >/dev/null 2>&1; QF="$( blob_for "$HEADSHA" )"   # a fresh, valid HEAD blob to forge from
NEWKEYS=""
if [ -n "$SF" ] && [ -n "$QF" ]; then
    NEWKEYS="$( comm -13 <( blobtool dead "$QF" "$HEADSHA" | sort ) <( blobtool dead "$SF" "$SCRATCHSHA" | sort ) | paste -sd, - )"
fi
if [ -z "$NEWKEYS" ]; then
    no "(G) found no key dead at the scratch commit and alive at HEAD (scratch blob '${SF:+present}') — the hidden-direction forgery would be vacuous"
else
    coldrun >"$TMP/g_cold" 2>/dev/null; rcg=$?
    grep -q 'kind="dead-code"' "$TMP/g_cold" \
        && ok "(G) the working tree's deleted call is a real dead-code regression on a cold cache (exit $rcg)" \
        || no "(G) the cold run reports no dead-code regression — the hidden-direction arms would be vacuous"
    cp "$QF" "$TMP/gorig.bin"
    blobtool forge "$TMP/gorig.bin" "$HEADSHA" "$TMP/g1.bin" "$NEWKEYS" keep >/dev/null
    blobtool forge "$TMP/gorig.bin" "$HEADSHA" "$TMP/g2.bin" "$NEWKEYS" flip >/dev/null

    cp "$TMP/g1.bin" "$QF"
    run >"$TMP/g1_out" 2>/dev/null; rg1=$?
    { ! grep -q 'kind="dead-code"' "$TMP/g1_out" && [ "$rg1" -ne "$rcg" ]; } \
        && ok "(G1) control: the forged dead set, producer kept, IS served — the real regression disappears (exit $rcg -> $rg1)" \
        || no "(G1) control did not fire (cold exit $rcg, forged exit $rg1)"

    cp "$TMP/g2.bin" "$QF"
    run >"$TMP/g2_out" 2>/dev/null; rg2=$?
    { diff -q "$TMP/g_cold" "$TMP/g2_out" >/dev/null && [ "$rg2" -eq "$rcg" ]; } \
        && ok "(G2) the same forgery from ANOTHER producer is refused — the regression is reported, exit $rg2 as cold" \
        || { no "(G2) a blob from another producer hid a real regression (exit cold=$rcg forged=$rg2)"; diff "$TMP/g_cold" "$TMP/g2_out" | head -4; }
fi

[ "$fail" -eq 0 ] && echo "qsnapproducercheck: ALL PASS" || { echo "qsnapproducercheck: SOME CHECKS FAILED"; exit 1; }
