#!/usr/bin/env bash
# cacheidentitycheck.sh — the INDEX-IDENTITY disclosure contract: ripwire must say, in a user-visible
# surface, which extraction identity this binary carries and whether the cache artifact a run would
# consume is usable BY THIS BINARY — and when it is not, WHICH guard refused it.
#
# THE DEFECT THIS GATE EXISTS FOR (measured on db6a416d, harvest-B lane R3).
# `src/ingest_cache.h`'s CacheFrame comment states the fusion in its own words: *"`ok == false` means
# 'there is no usable cache here' FOR EVERY REASON — absent, wrong shape, foreign version/parserVer/arch,
# torn, or a table that failed its checksum or its bounds."* Twelve distinct refusals collapse into one
# bool, and NONE of them reaches the user:
#   - `kCacheVersion` (15), `kParserVer` (77) and `kArtifactArch` are INTERNAL. `--doctor`, `--help` and the
#     map header name none of them, so there is no index-version contract a consumer can pin or compare —
#     the codanna half of harvest-B card C3.
#   - `ripwire DIR --cache=/does/not/exist` exits 0, prints NOTHING on either stream, and emits output
#     byte-identical to a run with a valid artifact. The `--index-out` -> `--cache=` CI workflow that
#     `--help` recommends therefore has no way to verify the artifact was used at all — the cocoindex half
#     ("only re-indexes changed files" as a CONTRACT rather than an implementation detail).
#   - the version/parserVer/arch refusals do speak, but only through DEGRADED_PATH_ALERT, which
#     `src/infra/Diagnostics.h` compiles to `do { } while (0)` under NDEBUG. Every binary `install.sh`
#     produces is `-DCMAKE_BUILD_TYPE=Release`, so on the binary users actually run the refusal is
#     COMPLETELY silent. `test/portablecachecheck.sh`'s own header already names this failure mode as the
#     thing that "defeats the entire point of a COMMITTED cache artifact" — it fixed the hit, not the
#     disclosure of the miss.
#
# WHAT THIS GATE DOES *NOT* RE-LITIGATE. `docs/EVALS.md` "card A3" REJECTED a freshness attribute on the
# CLI map root, with a measurement: the CLI re-crawls every invocation, warm output is asserted
# byte-identical to cold, so nothing varying with cache state may be emitted on stdout. Arm (F) below
# asserts that rejection is still in force. This gate is about a DIFFERENT question that A3 did not
# cover: not "does the index still describe the tree" (re-validated per invocation, per A3) but "can this
# binary read the artifact you handed it at all, and if not, which guard said no".
#
# FAMILY, NOT INSTANCE (lane-brief rule 4). The family is every refusal branch inside
# `openCacheFrame()`. Arm (C)'s first question is "which member is missing from this list?": it counts the
# refusal sites in the source and requires the reason vocabulary to cover each one, so a new guard added
# later without a reason label goes RED here rather than silently rejoining the fused bool.
#
# Usage:
#   bash test/cacheidentitycheck.sh
#   RIPWIRE_BIN=asan/ripwire bash test/cacheidentitycheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check; prints ALL PASS on success.
# Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required (blob doctoring)"; exit 2; }

echo "cacheidentitycheck: BIN=$BIN  TMP=$TMP"

CACHE_SRC="$ROOT/src/ingest_cache.h"
DOCTOR_SRC="$ROOT/src/verbs_doctor.h"
[ -f "$CACHE_SRC" ]  || { echo "missing $CACHE_SRC"; exit 2; }
[ -f "$DOCTOR_SRC" ] || { echo "missing $DOCTOR_SRC"; exit 2; }

# A private TMPDIR so the AUTO blob this gate reasons about is this gate's own, never the developer's
# warm per-user cache (which another ripwire process may rewrite mid-run).
export TMPDIR="$TMP/tmpdir"
mkdir -p "$TMPDIR"

FIXTURE="$TMP/tree"
mkdir -p "$FIXTURE"
printf 'int alphaaa( int x ) { return x + 1; }\nint caller( void ) { return alphaaa( 2 ); }\n' > "$FIXTURE/a.c"
printf 'int betaaaa( int x ) { return x + 2; }\n' > "$FIXTURE/b.c"

# The row every arm below reads. Kept as a function so a missing row fails LOUDLY (empty string) instead
# of silently matching an empty grep. Split on '<' (never on '/' or '>' — attribute VALUES here carry
# filesystem paths, and the legend carries both characters); escapeXml guarantees no '<' inside a value.
row(){ tr '<' '\n' < "$1" | grep '^c n="index-cache"' | head -1; }
attr(){ printf '%s' "$2" | grep -o " $1=\"[^\"]*\"" | head -1 | sed "s/^ $1=\"//; s/\"$//"; }
# The leading legend comment: everything before the <doctor root.
legend(){ sed 's/<doctor .*//' "$1" | head -c 20000; }

# ════════════════════════════════════════════════════════════════════════════════════════════════════
# (A) THE ROW EXISTS — --doctor carries an index-cache check at all, and doctor's own checks= denominator
#     counts it (a row that does not move the denominator is a row half the parsers will never see).
# ════════════════════════════════════════════════════════════════════════════════════════════════════
"$BIN" "$FIXTURE" --doctor > "$TMP/doc_auto.xml" 2> "$TMP/doc_auto.err"
R_AUTO="$( row "$TMP/doc_auto.xml" )"
if [ -n "$R_AUTO" ]; then
    ok "(A) --doctor emits <c n=\"index-cache\">"
else
    no "(A) --doctor emits NO index-cache row — the extraction identity that decides every artifact reuse has no user-visible surface"
fi

CHECKS="$( grep -o '<doctor checks="[0-9]*"' "$TMP/doc_auto.xml" | head -1 | grep -o '[0-9]*' )"
ROWS="$( grep -o '<c n="' "$TMP/doc_auto.xml" | wc -l | tr -d ' ' )"
if [ -n "$CHECKS" ] && [ "$CHECKS" = "$ROWS" ]; then
    ok "(A) checks=\"$CHECKS\" equals the emitted row count ($ROWS) — the new row is inside the denominator"
else
    no "(A) checks=\"${CHECKS:-?}\" disagrees with the emitted row count ($ROWS)"
fi

# ════════════════════════════════════════════════════════════════════════════════════════════════════
# (B) IDENTITY IS DERIVED, NOT PINNED — the emitted numbers must equal the SOURCE constants. Pinning
#     literals here would make the gate agree with a stale mirror; deriving makes a forgotten bump red.
# ════════════════════════════════════════════════════════════════════════════════════════════════════
SRC_CACHEVER="$( grep -o 'kCacheVersion *= *[0-9]*' "$CACHE_SRC" | head -1 | grep -o '[0-9]*$' )"
SRC_PARSERVER="$( grep -o 'kParserVer *= *[0-9]*' "$CACHE_SRC" | head -1 | grep -o '[0-9]*$' )"
# kArtifactArch = (big-endian ? 1 : 0) | (sizeof(void*) << 1) — computed the same way the header does.
SRC_ARCH="$( python3 -c 'import sys,struct;print((1 if sys.byteorder=="big" else 0) | (struct.calcsize("P") << 1))' )"

G_CACHEVER="$( attr cache_version "$R_AUTO" )"
G_LEAN="$(     attr parser_ver_lean "$R_AUTO" )"
G_RICH="$(     attr parser_ver_rich "$R_AUTO" )"
G_ARCH="$(     attr artifact_arch "$R_AUTO" )"

if [ -n "$SRC_CACHEVER" ] && [ "$G_CACHEVER" = "$SRC_CACHEVER" ]; then
    ok "(B) cache_version=\"$G_CACHEVER\" matches src/ingest_cache.h's kCacheVersion"
else
    no "(B) cache_version=\"${G_CACHEVER:-<absent>}\" != kCacheVersion (${SRC_CACHEVER:-?}) — the index-version contract is unstated or wrong"
fi
if [ -n "$SRC_PARSERVER" ] && [ "$G_LEAN" = "$SRC_PARSERVER" ]; then
    ok "(B) parser_ver_lean=\"$G_LEAN\" matches kParserVer"
else
    no "(B) parser_ver_lean=\"${G_LEAN:-<absent>}\" != kParserVer (${SRC_PARSERVER:-?})"
fi
if [ -n "$SRC_PARSERVER" ] && [ "$G_RICH" = "$(( SRC_PARSERVER + 1 ))" ]; then
    ok "(B) parser_ver_rich=\"$G_RICH\" matches parserVerFor(true) = kParserVer + 1"
else
    no "(B) parser_ver_rich=\"${G_RICH:-<absent>}\" != kParserVer+1 ($(( SRC_PARSERVER + 1 )))"
fi
if [ "$G_ARCH" = "$SRC_ARCH" ]; then
    ok "(B) artifact_arch=\"$G_ARCH\" matches this host's (endianness | sizeof(void*)<<1)"
else
    no "(B) artifact_arch=\"${G_ARCH:-<absent>}\" != $SRC_ARCH"
fi

# ════════════════════════════════════════════════════════════════════════════════════════════════════
# (C) FAMILY COMPLETENESS — "which member is missing from this list?". Every refusal branch inside
#     openCacheFrame() must carry a reason label, and every label must be named in doctor's legend so a
#     reader can decode the value without the source. Counted from the SOURCE, never pinned.
# ════════════════════════════════════════════════════════════════════════════════════════════════════
FRAME_BODY="$TMP/openCacheFrame.txt"
awk '/^inline CacheFrame openCacheFrame\(/{f=1} f{print} f&&/^}$/{exit}' "$CACHE_SRC" > "$FRAME_BODY"
SITES="$( grep -c 'return frame;' "$FRAME_BODY" )"
LABELLED="$( grep -c 'frame.reason *= *CacheReject::' "$FRAME_BODY" )"
# The last `return frame;` is the SUCCESS return (frame.ok = true), so refusals = sites - 1.
REFUSALS=$(( SITES - 1 ))
if [ "$SITES" -ge 2 ] && [ "$LABELLED" -eq "$REFUSALS" ]; then
    ok "(C) every one of openCacheFrame()'s $REFUSALS refusal branches sets a CacheReject reason ($LABELLED labelled)"
else
    no "(C) openCacheFrame() has $REFUSALS refusal branches but only $LABELLED carry a CacheReject reason — a refusal is still collapsing into the fused bool"
fi

# The vocabulary as the ENUM declares it, vs the vocabulary the legend documents. Neither may exceed the
# other: an undocumented value is unreadable, a documented-but-unreachable value is a false promise.
ENUM_VALS="$( awk '/enum class CacheReject/{f=1} f{print} f&&/};/{exit}' "$CACHE_SRC" \
              | grep -o 'reason="[a-z-]*"' | sed 's/reason="//; s/"//' | sort -u )"
LEGEND_ALL="$( legend "$TMP/doc_auto.xml" )"
missing_doc=""
for v in $ENUM_VALS; do
    printf '%s' "$LEGEND_ALL" | grep -q "$v" || missing_doc="$missing_doc $v"
done
if [ -n "$ENUM_VALS" ] && [ -z "$missing_doc" ]; then
    ok "(C) every CacheReject value is named in doctor's legend ($( printf '%s' "$ENUM_VALS" | tr '\n' ' ' ))"
else
    no "(C) CacheReject values missing from doctor's legend:${missing_doc:- <no enum found in source>}"
fi

# ════════════════════════════════════════════════════════════════════════════════════════════════════
# (D) PER-REASON FIXTURES — each doctored artifact must be refused with the RIGHT name. A gate that only
#     asserted "unusable" would pass on a single fused reason and buy nothing over the bool it replaces.
# ════════════════════════════════════════════════════════════════════════════════════════════════════
"$BIN" "$FIXTURE" --index-out="$TMP/idx" >/dev/null 2>&1
GOOD="$TMP/idx.lean.ripwirecache"
RICH="$TMP/idx.rich.ripwirecache"
if [ -s "$GOOD" ] && [ -s "$RICH" ]; then
    ok "(D) --index-out produced both families to doctor"
else
    no "(D) --index-out produced no artifact — cannot run the per-reason fixtures"
fi

doctor_reason(){                     # $1 = artifact path -> the lean verdict for it
    "$BIN" "$FIXTURE" --cache="$1" --doctor > "$TMP/d.xml" 2>/dev/null
    attr lean "$( row "$TMP/d.xml" )"
}
expect(){                            # $1 = label  $2 = artifact  $3 = expected reason
    got="$( doctor_reason "$2" )"
    if [ "$got" = "$3" ]; then
        ok "(D) $1 -> lean=\"$3\""
    else
        no "(D) $1 -> lean=\"${got:-<absent>}\", expected \"$3\""
    fi
}

cp "$GOOD" "$TMP/f_ok.bin"
expect "a valid same-binary lean artifact" "$TMP/f_ok.bin" "ok"
expect "a path with no file at it"         "$TMP/nothing_here.bin" "absent"
mkdir -p "$TMP/f_dir.bin"
expect "a directory"                       "$TMP/f_dir.bin" "not-regular"
head -c 8 "$GOOD" > "$TMP/f_short.bin"
expect "a file too short to hold a frame"  "$TMP/f_short.bin" "truncated"
cp "$FIXTURE/a.c" "$TMP/f_notcache.bin"
expect "some other file entirely"          "$TMP/f_notcache.bin" "not-a-cache"

patch_u32(){ python3 -c "
import struct,sys,shutil
shutil.copyfile(sys.argv[1], sys.argv[2])
b=bytearray(open(sys.argv[2],'rb').read())
b[int(sys.argv[3]):int(sys.argv[3])+4]=struct.pack('<I', int(sys.argv[4]))
open(sys.argv[2],'wb').write(bytes(b))
" "$1" "$2" "$3" "$4"; }

patch_u32 "$GOOD" "$TMP/f_ver.bin" 4 $(( SRC_CACHEVER - 1 ))
expect "a blob of an older kCacheVersion" "$TMP/f_ver.bin" "format-version"

patch_u32 "$GOOD" "$TMP/f_parser.bin" 8 $(( SRC_PARSERVER - 3 ))
expect "a blob of an older kParserVer"    "$TMP/f_parser.bin" "parser-version"

python3 -c "
import sys,shutil
shutil.copyfile(sys.argv[1], sys.argv[2])
b=bytearray(open(sys.argv[2],'rb').read()); b[12]=(b[12]^1)   # flip the endianness bit
open(sys.argv[2],'wb').write(bytes(b))
" "$GOOD" "$TMP/f_arch.bin"
expect "a foreign-arch blob" "$TMP/f_arch.bin" "artifact-arch"

python3 -c "
import sys,shutil
shutil.copyfile(sys.argv[1], sys.argv[2])
b=bytearray(open(sys.argv[2],'rb').read()); b[-1]^=0xFF       # damage the trailer's tableSum
open(sys.argv[2],'wb').write(bytes(b))
" "$GOOD" "$TMP/f_sum.bin"
expect "a damaged header+table checksum" "$TMP/f_sum.bin" "checksum"

# The LEAN/RICH split, which is the trap src/ingest_cache.h's own comment warns about: a team that
# commits only one family gets no warm hit on the verbs served by the other. One row must say so.
"$BIN" "$FIXTURE" --cache="$RICH" --doctor > "$TMP/d_rich.xml" 2>/dev/null
RR="$( row "$TMP/d_rich.xml" )"
if [ "$( attr lean "$RR" )" = "parser-version" ] && [ "$( attr rich "$RR" )" = "ok" ]; then
    ok "(D) a RICH-only artifact reads lean=\"parser-version\" rich=\"ok\" — the family mismatch is named, not fused"
else
    no "(D) a RICH-only artifact reads lean=\"$( attr lean "$RR" )\" rich=\"$( attr rich "$RR" )\", expected parser-version / ok"
fi

# ════════════════════════════════════════════════════════════════════════════════════════════════════
# (E) ok= AND THE EXIT CODE — a self-healing miss on the AUTO blob is normal and must never fail doctor
#     (a first run on a cold machine has no blob). An artifact the USER NAMED and this binary cannot read
#     is a stated expectation that was not met: that, and only that, is ok="0".
# ════════════════════════════════════════════════════════════════════════════════════════════════════
"$BIN" "$FIXTURE" --cache="$TMP/nothing_here.bin" --doctor > "$TMP/d_named.xml" 2>/dev/null
if [ "$( attr ok "$( row "$TMP/d_named.xml" )" )" = "0" ]; then
    ok "(E) an explicitly named artifact this binary cannot read is ok=\"0\""
else
    no "(E) an explicitly named unreadable artifact is not ok=\"0\" — the user's --cache= expectation fails silently"
fi
if [ "$( attr ok "$( row "$TMP/d_named.xml" )" )" = "0" ] && [ "$( attr source "$( row "$TMP/d_named.xml" )" )" = "cache-flag" ]; then
    ok "(E) source=\"cache-flag\" distinguishes the named artifact from the auto blob"
else
    no "(E) source= does not say the artifact was explicitly named"
fi

# A cold auto blob (this gate's private TMPDIR was empty at (A)) must NOT fail doctor.
rm -rf "$TMPDIR"; mkdir -p "$TMPDIR"
"$BIN" "$FIXTURE" --doctor > "$TMP/d_cold.xml" 2>/dev/null
if [ "$( attr ok "$( row "$TMP/d_cold.xml" )" )" = "1" ]; then
    ok "(E) a cold machine with no auto blob keeps ok=\"1\" (a self-healing miss is not sickness)"
else
    no "(E) a cold auto blob makes doctor fail — a first run on any machine would report sick"
fi

# --no-cache is neither fresh nor stale: it is the third state, and must be named, never collapsed.
"$BIN" "$FIXTURE" --no-cache --doctor > "$TMP/d_off.xml" 2>/dev/null
RO="$( row "$TMP/d_off.xml" )"
if [ "$( attr source "$RO" )" = "disabled" ] && [ "$( attr lean "$RO" )" = "disabled" ]; then
    ok "(E) --no-cache reads source=\"disabled\" lean=\"disabled\" — no artifact was consulted, and the row says so rather than claiming ok or absent"
else
    no "(E) --no-cache reads source=\"$( attr source "$RO" )\" lean=\"$( attr lean "$RO" )\" — the 'no verdict possible' state is collapsed into a verdict"
fi

# Multi-root: a workspace consumes ONE blob PER ROOT, so a single lean=/rich= verdict could only ever be
# root[0]'s presented as the workspace's. --doctor REFUSES a multi-root workspace outright, which is what
# makes the row safe to emit unqualified — pinned here, because the day that refusal is relaxed this row
# silently starts under-reporting and nothing else in the tree would notice.
"$BIN" "$FIXTURE" "$ROOT/test/fixture" --doctor > "$TMP/d_multi.xml" 2> "$TMP/d_multi.err"
if ! grep -q 'n="index-cache"' "$TMP/d_multi.xml" && grep -qi 'single-root' "$TMP/d_multi.err"; then
    ok "(E) --doctor refuses a multi-root workspace, so no per-root verdict can be reported as the workspace's"
else
    no "(E) --doctor answered a multi-root workspace — the index-cache row now reports root[0]'s artifact as if it covered N roots"
fi

# ════════════════════════════════════════════════════════════════════════════════════════════════════
# (F) THE card-A3 REJECTION STAYS IN FORCE — nothing about cache state may reach stdout's map. Warm
#     output is asserted byte-identical to cold (docs/ARCHITECTURE.md §2), so an identity attribute on
#     the map root is illegal however useful it would be on --doctor.
# ════════════════════════════════════════════════════════════════════════════════════════════════════
"$BIN" "$FIXTURE" --no-cache > "$TMP/m_cold.xml" 2>/dev/null
"$BIN" "$FIXTURE"            > "$TMP/m_warm1.xml" 2>/dev/null
"$BIN" "$FIXTURE"            > "$TMP/m_warm2.xml" 2>/dev/null
if diff -q "$TMP/m_cold.xml" "$TMP/m_warm1.xml" >/dev/null 2>&1 && diff -q "$TMP/m_warm1.xml" "$TMP/m_warm2.xml" >/dev/null 2>&1; then
    ok "(F) cold == warm == warm byte-identical — the disclosure did not leak cache state into the map"
else
    no "(F) cold/warm map bytes diverged — cache state reached stdout"
fi
if grep -o '<r [^>]*>' "$TMP/m_warm1.xml" | head -1 | grep -qE 'cache_version|parser_ver|artifact_arch|usable='; then
    no "(F) the map root grew an identity attribute — docs/EVALS.md card A3 REJECTED exactly that, with a measurement"
else
    ok "(F) the map root carries no cache/identity attribute (card A3's rejection still holds)"
fi

# ════════════════════════════════════════════════════════════════════════════════════════════════════
# (G) VOLATILITY IS DECLARED — the row reads live per-user disk state that any concurrent ripwire process
#     may rewrite. It must name its own live fields the way cache-dir does, so a determinism comparison
#     strips the named attributes and never the row (test/lib/doctorvolatile.sh reads this).
# ════════════════════════════════════════════════════════════════════════════════════════════════════
VOL="$( attr volatile "$R_AUTO" )"
if printf '%s' "$VOL" | grep -q 'lean' && printf '%s' "$VOL" | grep -q 'rich'; then
    ok "(G) the row declares volatile=\"$VOL\""
else
    no "(G) the row declares volatile=\"${VOL:-<absent>}\" — its live-state fields are not named"
fi

# ════════════════════════════════════════════════════════════════════════════════════════════════════
# (H) MUTATION CONTROL — prove (D) is live, not vacuously true, by showing the SAME assertion machinery
#     reports a DIFFERENT reason for a different mutation of the same artifact.
# ════════════════════════════════════════════════════════════════════════════════════════════════════
r1="$( doctor_reason "$TMP/f_ver.bin" )"
r2="$( doctor_reason "$TMP/f_notcache.bin" )"
r3="$( doctor_reason "$TMP/f_ok.bin" )"
if [ -n "$r1" ] && [ "$r1" != "$r2" ] && [ "$r2" != "$r3" ] && [ "$r1" != "$r3" ]; then
    ok "(H) three mutations of the same path yield three distinct reasons ($r1 / $r2 / $r3) — the assertions discriminate"
else
    no "(H) mutations do not discriminate ($r1 / $r2 / $r3) — (D) may be passing vacuously"
fi

# ════════════════════════════════════════════════════════════════════════════════════════════════════
# (I) G4 WELL-FORMEDNESS — the legend that documents the vocabulary is an XML COMMENT, and an XML comment
#     may not contain a double hyphen. Naming eleven reason values next to flag spellings is exactly the
#     text most likely to reintroduce one, on every shape the row takes (this arm caught it once already).
# ════════════════════════════════════════════════════════════════════════════════════════════════════
if command -v xmllint >/dev/null 2>&1; then
    xml_fail=0
    for a in "$TMP/doc_auto.xml" "$TMP/d_named.xml" "$TMP/d_off.xml" "$TMP/d_cold.xml" "$TMP/d_rich.xml"; do
        xmllint --noout "$a" >/dev/null 2>&1 || { xml_fail=1; echo "      (bad: $a)"; }
    done
    if [ "$xml_fail" -eq 0 ]; then
        ok "(I) every --doctor shape (auto / cache-flag / disabled / cold / rich) is well-formed XML"
    else
        no "(I) a --doctor shape is not well-formed XML — most likely a double hyphen inside the legend comment"
    fi
else
    ok "(I) xmllint unavailable — well-formedness arm skipped"
fi

echo
if [ "$fail" -eq 0 ]; then echo "cacheidentitycheck: ALL PASS"; else echo "cacheidentitycheck: FAILURES"; fi
exit "$fail"
