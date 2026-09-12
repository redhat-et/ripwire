#!/usr/bin/env bash
# emitescapecheck.sh — gate for the RUN-COPY rewrite of the three emit escapers: rw::escapeXml and
# rw::appendCdataSafe (src/serialize.h) and rw::jsonesc::escapeInto (src/infra/jsonesc.h).
#
# WHY A HARNESS AND NOT A GOLDEN DIFF. The rewrite is "find the next byte in the special set with
# strkern::findByteset, memcpy the clean run, handle that one byte with the SAME switch". Nothing in a
# golden map exercises the inputs that shape gets wrong — an escaper is only interesting on the bytes a
# repo does not normally contain. So the `escape:` TEST_CASEs of test/verify_strkern.cpp keep the
# ORIGINAL per-byte loops verbatim as `*Ref` and assert byte-identity over an adversarial corpus: every
# one of the 256 byte values; a special byte at EVERY offset of a filler run up to two 32-byte AVX2 blocks
# (the block-boundary sweep a SIMD run loop plus its scalar tail must survive); overlongs, surrogate
# halves, >U+10FFFF, truncated sequences, a lone continuation byte as the final byte of the buffer, a
# BOM; "]]>" at the start/middle/end and "]]]]>"; all eight escapeInto flag combinations; and 200k
# deterministic fuzz strings over an alphabet biased to the special set.
#
# The arms live in the SAME doctest target as the strkern kernel arms (CMake `ripwire_test_strkern`,
# 2026-09-10) because they test the same header from the other side: the escapers are findByteset's only
# shipped callers, and a set bug and a scan bug are indistinguishable from a diff. This gate selects them
# with doctest's own filter (`-tc=escape:*`); test/strkerncheck.sh runs the whole target, which is why
# the sanitized build lives there and this gate does not pay for a second copy of it.
#
# ARMS
#   (A) the target's escape: arms pass — the shipped escapers agree with the frozen per-byte references.
#   (B) CAN-GO-RED: the same target recompiled with -DEMITESCAPE_MUTATE_BYTESET=1, which adds a byteset
#       with '<' DROPPED. That build asserts the mutant DISAGREES with the reference. A comparison that
#       could not see a missing set member would report zero differences and this arm would fail — which
#       is the point: it proves arm (A) is looking at what it claims to.
#   (C) END TO END: a fixture tree (in a temp dir, NEVER inside the repo — see the
#       "gate fixture is the live repo" trap) whose doc-comment carries every byte value 0x01..0xFF
#       except '\n'. The map of that tree must pipe clean through `xmllint --noout` (G4), and the
#       --json map of the same tree must be accepted by python3's json parser. Both surfaces are the
#       ones the rewritten escapers write, so a set bug that produced a raw '<' or a broken UTF-8
#       sequence turns this red without any reference to compare against.
#
# Usage:  bash test/emitescapecheck.sh                (binary from RIPWIRE_BIN, else ./build/ripwire)
#         CXX=clang++ bash test/emitescapecheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
CXX="${CXX:-c++}"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

. "$ROOT/scripts/cxxstd.sh"
CXXSTD="$( ripwire_cxx_std_flag "$CXX" )"
SRC="$ROOT/test/verify_strkern.cpp"
WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT

echo "emitescapecheck: CXX=$CXX  BIN=$BIN  target=ripwire_test_strkern -tc=escape:*"

# doctest's own tally line is the arm count. LEGACY_ESCAPE_ARMS is what the standalone
# test/emitescape_harness.cpp carried before it became TEST_CASEs (2026-09-10); the gate prints both so a
# lost arm is arithmetic, not a feeling.
LEGACY_ESCAPE_ARMS=4
read_counts()   # $1 = log; sets CASES, ASSERTS, ASSERTS_FAIL
{
    CASES="$(   sed -n 's/^\[doctest\] test cases: *\([0-9][0-9]*\) .*/\1/p' "$1" | tail -1 )"
    ASSERTS="$( sed -n 's/^\[doctest\] assertions: *\([0-9][0-9]*\) .*/\1/p' "$1" | tail -1 )"
    ASSERTS_FAIL="$( sed -n 's/.*| *\([0-9][0-9]*\) failed |$/\1/p'            "$1" | tail -1 )"
    : "${CASES:=0}" "${ASSERTS:=0}" "${ASSERTS_FAIL:=1}"
}

# ── (A) the shipped escapers vs the frozen per-byte references, through the CMake target ──────────────
# FETCHCONTENT_FULLY_DISCONNECTED=ON because every dependency is vendored: a gate must not reach the
# network. No -DRIPWIRE_ASAN=ON here — test/strkerncheck.sh builds this same TU under the complete G1
# stack and runs every one of its test cases, so a second sanitized copy would re-prove that at the price
# of another build.
if ! cmake -S "$ROOT" -B "$WORK/cmb" -DRIPWIRE_TESTS=ON -DFETCHCONTENT_FULLY_DISCONNECTED=ON \
        > "$WORK/cfg.log" 2>&1; then
    no "cmake configure (-DRIPWIRE_TESTS=ON) failed"; tail -20 "$WORK/cfg.log" | sed 's/^/    /'
elif ! cmake --build "$WORK/cmb" --target ripwire_test_strkern -j 2 > "$WORK/build.log" 2>&1; then
    no "ripwire_test_strkern failed to build"; tail -30 "$WORK/build.log" | sed 's/^/    /'
elif RIPWIRE_ROOT="$ROOT" "$WORK/cmb/ripwire_test_strkern" -tc="escape:*" > "$WORK/plain.out" 2>&1; then
    read_counts "$WORK/plain.out"
    if [ "$ASSERTS" -lt "$LEGACY_ESCAPE_ARMS" ]; then
        no "only $ASSERTS escape: assertions ran; the harness this replaced carried $LEGACY_ESCAPE_ARMS — an arm was lost"
    else
        ok "escapers byte-identical to the frozen per-byte references over the adversarial corpus ($CASES test cases / $ASSERTS assertions; was $LEGACY_ESCAPE_ARMS standalone arms)"
    fi
    grep -E '^\[doctest\] (test cases|assertions):' "$WORK/plain.out" | sed 's/^/    /'
else
    no "the escape: arms reported a mismatch"; sed 's/^/    /' "$WORK/plain.out" | head -30
fi

# ── (B) can-go-red: a byteset with '<' dropped must be VISIBLE to the comparison ───────────────────────
# A compile flag, not a build type: a second CMake configure to pass one -D would cost a configure to say
# nothing extra, so this arm compiles the same source directly the way the pre-doctest gate did.
if "$CXX" "$CXXSTD" -O2 -g -Wall -Wextra -DEMITESCAPE_MUTATE_BYTESET=1 \
        -I"$ROOT/src/infra" -I"$ROOT/third_party" -I"$ROOT/src" -I"$ROOT/third_party/deps/doctest" \
        -DRIPWIRE_TEST_ROOT="\"$ROOT\"" \
        "$SRC" "$ROOT/src/infra/diagnostics.cpp" -o "$WORK/mut" 2> "$WORK/cc.log"; then
    if RIPWIRE_ROOT="$ROOT" "$WORK/mut" -tc="escape:*" > "$WORK/mut.out" 2>&1; then
        ok "MUT arm: a byteset missing '<' is detected (the comparison can go red)"
        grep -n 'MUT:' "$WORK/mut.out" | sed 's/^/    /'
    else
        no "MUT arm did not detect a byteset missing '<' — arm (A) proves nothing"
        sed 's/^/    /' "$WORK/mut.out" | head -20
    fi
else
    no "MUT arm failed to compile"; sed 's/^/    /' "$WORK/cc.log" | head -20
fi

# ── (C) end to end: every byte value through a real map, XML and JSON ─────────────────────────────────
[ -x "$BIN" ] || { no "binary not found: $BIN"; echo "emitescapecheck: FAIL"; exit 2; }

FIX="$WORK/fixture"
mkdir -p "$FIX"
python3 - "$FIX" <<'PY'
import os, sys
d = sys.argv[1]
# every byte 0x01..0xFF except '\n' (0x0A), which would end the line comment, on ONE doc-comment line;
# 0x00 is left out on purpose — an ingest that classifies a NUL-bearing file as binary would skip the
# file and the arm would prove nothing. NUL's escape path is covered by the harness instead.
soup = bytes( b for b in range( 1, 256 ) if b != 0x0A )
body = b"// bytesoup: " + soup + b"\n// ]]> and <![CDATA[ and & < > \" ' inside a comment\n" \
       b"void fixtureAlpha( int n ) { (void)n; }\n" \
       b"/** every byte again in a block comment: " + soup + b" */\n" \
       b"int fixtureBeta( int n ) { return fixtureAlpha2( n ); }\n" \
       b"int fixtureAlpha2( int n ) { return n; }\n"
open( os.path.join( d, "soup.cpp" ), "wb" ).write( body )
open( os.path.join( d, "plain.cpp" ), "wb" ).write( b"int plainOne( int n ) { return n + 1; }\n" )
PY

# The FLAGLESS map carries no doc-comment and no body, so it would prove nothing about the escapers.
# --for puts the doc-comment through escapeXml (entities + &#9;/&#13; + the invalid-UTF-8 '?' scrub) and
# --expand puts the whole file through appendCdataSafe (including the "]]>" split); their --json twins
# put the same bytes through jsonesc::escapeInto. All four surfaces are checked.
run_arm()   # $1=label  $2=validator(xml|json)  $3...=ripwire args
{
    local label="$1" kind="$2"; shift 2
    if ! "$BIN" "$FIX" "$@" > "$WORK/out.$kind" 2>"$WORK/err.$kind"; then
        no "ripwire failed on the every-byte fixture ($label)"; sed 's/^/    /' "$WORK/err.$kind" | head -10; return
    fi
    if ! LC_ALL=C grep -q 'bytesoup' "$WORK/out.$kind"; then
        no "$label: the byte soup never reached the output — this arm proves nothing"; return
    fi
    if [ "$kind" = xml ]; then
        if xmllint --noout "$WORK/out.$kind" 2>"$WORK/xmllint.err"; then
            ok "$label: well-formed XML over every byte value (G4)"
        else
            no "$label: xmllint rejected the map"; sed 's/^/    /' "$WORK/xmllint.err" | head -10
        fi
    else
        if python3 -c 'import json,sys; json.load(open(sys.argv[1],encoding="utf-8"))' "$WORK/out.$kind"; then
            ok "$label: parses as JSON (valid UTF-8, valid escapes) over every byte value"
        else
            no "$label: output is not parseable JSON"
        fi
    fi
}

run_arm "--for (escapeXml)"          xml  --for="bytesoup fixture"
run_arm "--expand (appendCdataSafe)" xml  --expand=fixtureAlpha
run_arm "--for --json (escapeInto)"  json --for="bytesoup fixture" --json
run_arm "--pack-task --json (bodies)" json --pack-task="bytesoup fixture" --json

if [ "$fail" -eq 0 ]; then
    echo "emitescapecheck: ALL PASS"; exit 0
else
    echo "emitescapecheck: FAIL"; exit 2
fi
