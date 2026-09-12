#!/usr/bin/env bash
# noaliascheck.sh — VERIFY_NO_ALIAS (src/infra/Diagnostics.h §6) is a DEBUG CHECK and a RELEASE OPTIMIZER FACT.
#
# THE DEFICIENCY THIS GATE EXISTS FOR (measured 2026-09-12, Apple clang 21, arm64 and x86-64). The macro
# used to be `VERIFY_TEXT( &a != &b, … )`, which -DNDEBUG lowers to `__builtin_assume( &a != &b )`. LLVM
# keeps that assume in the IR and alias analysis never reads it: codegen was BYTE-IDENTICAL to having no
# macro at all, while the header said "the no-alias contract that __restrict would assert". The
# replacement adds `__builtin_assume_separate_storage( &a, &b )` (clang 17+), which BasicAA does consume;
# codegen then matches `__restrict__` on the parameters exactly (`out=a; out+=b; out+=a;` arm64 10 -> 6).
#
# ARMS. Every optimizer arm compiles its OWN probe with the system compiler at -O2 -DNDEBUG, because the dev
# build (no build type) never defines NDEBUG and the release expansion is otherwise only ever exercised by
# CI's Release flavour:
#   1  debug catches:  VERIFY_NO_ALIAS3( out, a, b ) with distinct objects exits 0; `acc( x, y, x )` traps and
#                      stderr names BOTH expressions ('out' and 'b').
#   2  release optimizes: the function's IR carries "separate_storage" and NO reload of `a` after the store
#                      to `out`; the objdump instruction count sits in a band BELOW the plain function.
#   3  NEGATIVE CONTROL: the same body under the OLD definition, inlined in the probe as OLD_NO_ALIAS, must
#                      still carry the reload and NO "separate_storage". Arms 2 and 3 must DISAGREE — if
#                      they ever agree the gate examined one population twice and fails itself.
#   4  the macOS trap: zero bare `__restrict` in src/ CODE (comments and string literals stripped: on
#                      macOS <sys/cdefs.h> #defines `__restrict` to nothing in C++, so only `__restrict__`
#                      survives). Positive control: a temp file with a bare qualifier the SAME scan catches.
#   5  GCC shape:      with `__has_builtin` forced to 0 (and __clang__ undefined) the -DNDEBUG header must
#                      still compile, expanding to the `( (void)0 )` fallback and never to the builtin; the
#                      natural expansion on a builtin-capable compiler must contain the builtin (contrast).
#                      Release flavour only, and a probe with no library headers: libc++ itself spells
#                      `__has_builtin( __remove_reference_t )` and refuses to compile with the macro forced
#                      to 0, and the debug header includes <atomic>. The debug fallback is compiled for real
#                      by arms 1 and 7 whenever $CXX is a compiler without the builtin (the gcc CI legs).
#   6  buffer form:    VERIFY_NO_ALIAS_BUF( dst, src ) on two std::vector<uint32_t> makes the release
#                      `dst[i] += src[i]*3` loop SHORTER than plain; VERIFY_NO_ALIAS on the same two OBJECTS
#                      must NOT (the header separation says nothing about the heap buffers) — the buffer
#                      form's negative control.
#   7  buffer debug:   two EMPTY vectors pass (the promise over two null data() is vacuous); the same vector
#                      twice traps naming both expressions ('dst' and 'src').
#
#   8  NEGATIVE CONTROL for the probe itself: the arm-2 probe compiled with `-mllvm -basic-aa-separate-storage=false`
#                      MUST bring the reload back and land at plain's instruction count. On LLVM 18+ (every dev
#                      machine here) forcing the option off is the only way to exercise the LLVM 17 path locally,
#                      and it shows the arm-2 measurement is able to fail.
#
# THE OPTIMIZER HALF IS A SEPARATE SWITCH (found 2026-09-12 by CI job "release (macos-14, plain, appleclang, shard
# 4/4)" on PR #200: arm 7 and the IR-bundle row green, arms 2, 2/3 and 6 red). The front end has emitted the
# "separate_storage" bundle since clang 17, but BasicAA reads it only when its `basic-aa-separate-storage` option is
# on — llvm/lib/Analysis/BasicAliasAnalysis.cpp has `cl::init(false)` in LLVM 17 and `cl::init(true)` from 18. Xcode
# 16.2's AppleClang 16 is LLVM 17: it accepts the builtin, emits the bundle, and generates the same code as no promise
# at all. CMakeLists.txt therefore passes `-mllvm -basic-aa-separate-storage` to our targets whenever the compiler
# accepts it. So `__has_builtin` is NOT the capability probe here — the real slice is. The arm-2 probe is compiled
# three ways at -O2 -DNDEBUG (default, `=true`, `=false`) and the compiler is CLASSIFIED by whether accBuiltin —
# the builtin called DIRECTLY, so the verdict is about the compiler and not about the header on disk — reloads `a`
# after the store:
#     CONSUMED_DEFAULT    default has no reload (LLVM 18+)
#     CONSUMED_WITH_FLAG  default reloads, `=true` does not (LLVM 17 / AppleClang 16 — the CMake flag is load-bearing)
#     NOT_CONSUMED        both reload — the optimizer cannot be made to read the bundle
#     NO_BUILTIN          no __builtin_assume_separate_storage (GCC, clang < 17)
# Arms 2, 3 and 6 then compile with exactly the option CMake adds, and CMake's own cached probe result
# (RIPWIRE_CXX_HAS_BASIC_AA_SEPARATE_STORAGE in build/CMakeCache.txt, or $RIPWIRE_CMAKE_CACHE) must AGREE with this
# gate's — a disagreement is a FAIL, because the gate exists to measure what build/ripwire was built with; for the
# same reason $CXX defaults to the cache's CMAKE_CXX_COMPILER, not to whatever `c++` is on PATH. On NO_BUILTIN and
# NOT_CONSUMED arms 2, 3, 6 and 8 are reported as WARN (skipped, naming the compiler), never as PASS: the gcc CI
# legs run arms 1, 4, 5, 7; the clang legs run all eight.
# Counts are BANDS, never exact numbers — an LLVM release moves them by one or two.
#
# Usage:  bash test/noaliascheck.sh            (compiles with c++/clang++; objdump = llvm-objdump or GNU)
#         CXX=clang++ OBJDUMP=llvm-objdump bash test/noaliascheck.sh
# Exit:   0 = clean · 1 = an arm failed · 2 = a prerequisite is missing

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
# The build tree whose binary this gate must measure: its CMakeCache.txt names the front end and holds CMake's
# probe result. RIPWIRE_CMAKE_CACHE points at another tree's cache; CXX in the environment still wins.
CACHE="${RIPWIRE_CMAKE_CACHE:-$ROOT/build/CMakeCache.txt}"
cacheVar(){ [ -f "$CACHE" ] && sed -n "s/^$1:[A-Z]*=//p" "$CACHE" | head -1; return 0; }
CXX="${CXX:-$( cacheVar CMAKE_CXX_COMPILER )}"; CXX="${CXX:-c++}"
OBJDUMP="${OBJDUMP:-objdump}"
HDR="$ROOT/src/infra/Diagnostics.h"
WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
warn(){ printf '  WARN  %s\n' "$*"; }

# §CI-P3: ask THIS front end how it spells C++23 (scripts/cxxstd.sh — AppleClang 15 rejects -std=c++23).
. "$ROOT/scripts/cxxstd.sh"
CXXSTD="$( ripwire_cxx_std_flag "$CXX" )"
INC=( -I"$ROOT/src/infra" )
# the -U__clang__ / -D__has_builtin overrides in arm 5 legitimately redefine builtin macros
QUIET=( -Wno-macro-redefined -Wno-builtin-macro-redefined )

[ -f "$HDR" ] || { echo "no $HDR"; exit 2; }
command -v "$CXX" >/dev/null 2>&1 || { echo "no C++ compiler at $CXX"; exit 2; }
command -v "$OBJDUMP" >/dev/null 2>&1 || { echo "no objdump at $OBJDUMP"; exit 2; }
grep -q 'define VERIFY_NO_ALIAS' "$HDR" || { echo "  FAIL  presence guard: $HDR defines no VERIFY_NO_ALIAS"; exit 1; }

echo "noaliascheck: CXX=$CXX OBJDUMP=$OBJDUMP"

# ── does THIS compiler have the builtin? decides which arms can fire; reported, never assumed ─────────────────
printf '#if __has_builtin(__builtin_assume_separate_storage)\n#error HAS_SEPARATE_STORAGE\n#endif\nint main(){}\n' > "$WORK/hb.cpp"
if "$CXX" "$CXXSTD" -fsyntax-only "$WORK/hb.cpp" 2>&1 | grep -q 'HAS_SEPARATE_STORAGE'; then HAS_BUILTIN=1; else HAS_BUILTIN=0; fi
echo "  info  __builtin_assume_separate_storage available: $HAS_BUILTIN"

# instruction count of ONE function in an object file. --no-show-raw-insn keeps GNU objdump from wrapping
# long x86 encodings onto continuation lines that also start with an address. The probes open with an anchor
# function so no real function sits on the section's local label (`<ltmp0>` on Mach-O), and the symbol may
# carry a leading underscore (Mach-O) or not (ELF).
insnCount(){ "$OBJDUMP" -d --no-show-raw-insn "$1" | awk -v want="$2" '
    /^[0-9a-f]+ </ { inside = ( $0 ~ ("<_?" want ">:") ) }
    inside && /^[[:space:]]*[0-9a-f]+:/ { n++ }
    END { print n + 0 }'; }
# the IR block of ONE function: `define … @NAME(` through the closing brace
irBlock(){ awk -v want="$2" '/^define / { inside = index( $0, "@" want "(" ) > 0 } inside { print } /^}/ { inside = 0 }' "$1"; }
# 1 if the block loads from %a AFTER a store to %out (the reload the assumption is supposed to remove), else 0
reloadAfterStore(){ awk '/store .*ptr %out/ { stored = 1 } stored && /load .*ptr %a,/ { hit = 1 } END { print hit + 0 }'; }

# ── the scalar probe: header macro (accNew), the OLD definition inlined (accOld), no macro (accPlain) ────────
cat > "$WORK/probe.cpp" <<'EOF'
#include <cstdint>
#include <cstdio>
#include <cstring>
#include "Diagnostics.h"

// The definition this tree shipped before 2026-09-12, inlined verbatim as the NEGATIVE CONTROL: in release it
// is a bare __builtin_assume( &a != &b ), which alias analysis never reads.
#define OLD_NO_ALIAS( a, b )                                                                                   \
    VERIFY_TEXT( static_cast<const void*>( &( a ) ) != static_cast<const void*>( &( b ) ),                     \
                 "aliasing violation: '" #a "' and '" #b "' are the same object" )
#define OLD_NO_ALIAS3( a, b, c ) do { OLD_NO_ALIAS( a, b ); OLD_NO_ALIAS( a, c ); OLD_NO_ALIAS( b, c ); } while( 0 )

extern "C" void noalias_probe_anchor() {}   // keeps the first real function off the section's local label

extern "C" __attribute__(( noinline )) void accNew( uint32_t& out, const uint32_t& a, const uint32_t& b )
{
    VERIFY_NO_ALIAS3( out, a, b );
    out = a; out += b; out += a;
}
extern "C" __attribute__(( noinline )) void accOld( uint32_t& out, const uint32_t& a, const uint32_t& b )
{
    OLD_NO_ALIAS3( out, a, b );
    out = a; out += b; out += a;
}
extern "C" __attribute__(( noinline )) void accPlain( uint32_t& out, const uint32_t& a, const uint32_t& b )
{
    out = a; out += b; out += a;
}
// The builtin called DIRECTLY, no header macro in the way: what the classification probe measures, so that it
// classifies the COMPILER and not whichever Diagnostics.h happens to be on disk (the old header must red arm 2,
// not turn the compiler into NOT_CONSUMED).
extern "C" __attribute__(( noinline )) void accBuiltin( uint32_t& out, const uint32_t& a, const uint32_t& b )
{
#if defined(__has_builtin)
#if __has_builtin(__builtin_assume_separate_storage)
    __builtin_assume_separate_storage( &out, &a ); __builtin_assume_separate_storage( &out, &b ); __builtin_assume_separate_storage( &a, &b );
#endif
#endif
    out = a; out += b; out += a;
}

int main( int argc, char** argv )
{
    uint32_t x = 3u, y = 5u, z = 7u;
    if( argc > 1 && std::strcmp( argv[ 1 ], "alias" ) == 0 ) { accNew( x, y, x ); }
    else { accNew( x, y, z ); }
    std::printf( "%u\n", x );
    return x == 5u + 7u + 5u ? 0 : 3;
}
EOF

# ── does THIS compiler's OPTIMIZER consume the bundle? the real slice, three ways — see the header ───────────
# SEP_OPT is byte-for-byte the option CMakeLists.txt attaches to our targets; SEP_ON / SEP_OFF are its explicit
# forms for the classification and the arm-8 control. On a compiler that rejects -mllvm none of them compiles.
SEP_OPT=( -mllvm -basic-aa-separate-storage ); SEP_ON=( -mllvm -basic-aa-separate-storage=true ); SEP_OFF=( -mllvm -basic-aa-separate-storage=false )
CXXID="$( "$CXX" --version 2>/dev/null | head -1 )"
# acceptance is probed on a TU that compiles CLEAN without the option (hb.cpp above deliberately does not: its
# #error is the __has_builtin tell), and asserted so, or an unrelated compile error would read as "rejected"
printf 'int main() { return 0; }\n' > "$WORK/flag.cpp"
"$CXX" "$CXXSTD" -O2 -c "$WORK/flag.cpp" -o "$WORK/flag.o" 2>/dev/null || no "probe: the acceptance TU does not compile even WITHOUT the option — the acceptance probe cannot say anything"
FLAG_ACCEPTED=0
if "$CXX" "$CXXSTD" -O2 "${SEP_OPT[@]}" -c "$WORK/flag.cpp" -o "$WORK/flag.o" 2>/dev/null; then FLAG_ACCEPTED=1; fi
# 0/1: does accBuiltin (the builtin called directly — the compiler, not the header, is what is classified) reload a
# after the store when the probe is compiled with the given extra flags?
probeReload(){ "$CXX" "$CXXSTD" -O2 -DNDEBUG -fno-discard-value-names "${INC[@]}" "$@" -S -emit-llvm "$WORK/probe.cpp" -o "$WORK/cls.ll" 2>/dev/null \
    && irBlock "$WORK/cls.ll" accBuiltin | reloadAfterStore; }
CLASS=NO_BUILTIN; rDefault=-; rOn=-; rOff=-
if [ "$HAS_BUILTIN" = 1 ]; then
    rDefault="$( probeReload )"; rDefault="${rDefault:--}"
    if [ "$FLAG_ACCEPTED" = 1 ]; then rOn="$( probeReload "${SEP_ON[@]}" )"; rOff="$( probeReload "${SEP_OFF[@]}" )"; rOn="${rOn:--}"; rOff="${rOff:--}"; fi
    if [ "$rDefault" = 0 ]; then CLASS=CONSUMED_DEFAULT
    elif [ "$rDefault" = 1 ] && [ "$rOn" = 0 ]; then CLASS=CONSUMED_WITH_FLAG
    else CLASS=NOT_CONSUMED; fi
fi
echo "  info  compiler: $CXXID"
echo "  info  optimizer consumes \"separate_storage\": $CLASS (accBuiltin reload after store — default: $rDefault, =true: $rOn, =false: $rOff; -mllvm -basic-aa-separate-storage accepted: $FLAG_ACCEPTED)"
# the option arms 2, 3 and 6 compile with: exactly what CMake adds when the compiler accepts it, nothing otherwise
OPTFLAGS=(); if [ "$FLAG_ACCEPTED" = 1 ]; then OPTFLAGS=( "${SEP_OPT[@]}" ); fi
RELEASE_ARMS=0; case "$CLASS" in CONSUMED_DEFAULT|CONSUMED_WITH_FLAG) RELEASE_ARMS=1;; esac
# CMake's cached probe must agree with this one, or the gate is measuring a different toolchain than the binary
if [ -f "$CACHE" ]; then
    if grep -q '^RIPWIRE_CXX_HAS_BASIC_AA_SEPARATE_STORAGE:' "$CACHE"; then
        cmakeAccepted=0; [ "$( cacheVar RIPWIRE_CXX_HAS_BASIC_AA_SEPARATE_STORAGE )" = 1 ] && cmakeAccepted=1
        if [ "$cmakeAccepted" = "$FLAG_ACCEPTED" ]; then ok "probe: CMake's cached probe agrees (RIPWIRE_CXX_HAS_BASIC_AA_SEPARATE_STORAGE=$cmakeAccepted, CMAKE_CXX_COMPILER=$( cacheVar CMAKE_CXX_COMPILER ); gate CXX=$CXX)"
        else no "probe: CMake's cached probe DISAGREES — cache says accepted=$cmakeAccepted (CMAKE_CXX_COMPILER=$( cacheVar CMAKE_CXX_COMPILER )), this gate says $FLAG_ACCEPTED (CXX=$CXX); the gate is not measuring what the binary was built with"; fi
    else
        no "probe: $CACHE has no RIPWIRE_CXX_HAS_BASIC_AA_SEPARATE_STORAGE row — a configure older than the probe; reconfigure (cmake -S . -B build)"
    fi
else
    warn "probe: no $CACHE — CMake's side of the probe is unchecked (configure build/, or set RIPWIRE_CMAKE_CACHE)"
fi

# ── arm 1: debug catches ─────────────────────────────────────────────────────────────────────────────────────
if "$CXX" "$CXXSTD" -O1 -g -Wall -Wextra "${INC[@]}" "$WORK/probe.cpp" "$ROOT/src/infra/diagnostics.cpp" -o "$WORK/probe_dbg" 2> "$WORK/cc1.log"; then
    ok "arm 1: debug probe compiled against $HDR"
else
    no "arm 1: debug probe failed to compile"; sed 's/^/    /' "$WORK/cc1.log"
fi
if [ -x "$WORK/probe_dbg" ]; then
    "$WORK/probe_dbg" > "$WORK/d1.out" 2> "$WORK/d1.err"; rc=$?
    if [ "$rc" = 0 ] && grep -q '^17$' "$WORK/d1.out"; then ok "arm 1: distinct objects -> exit 0, out = 17"
    else no "arm 1: distinct objects: rc=$rc out=$( cat "$WORK/d1.out" )"; sed 's/^/    /' "$WORK/d1.err" | head -8; fi
    # the two-command subshell (no exec optimisation) keeps bash's own "Trace/BPT trap" job message off the
    # gate's output; the probe's stderr is the file
    ( "$WORK/probe_dbg" alias > "$WORK/d2.out" 2> "$WORK/d2.err"; exit $? ) 2>/dev/null; rc=$?
    if [ "$rc" != 0 ]; then ok "arm 1: acc( x, y, x ) traps in debug (rc=$rc)"
    else no "arm 1: acc( x, y, x ) exited 0 in debug — VERIFY_NO_ALIAS3 did not fire"; fi
    if grep -q "'out' and 'b' are the same object" "$WORK/d2.err"; then ok "arm 1: stderr names both expressions ('out' and 'b')"
    else no "arm 1: stderr does not name 'out' and 'b'"; sed 's/^/    /' "$WORK/d2.err" | head -8; fi
fi

# ── arms 2 + 3: release IR and codegen, header macro vs the OLD definition ───────────────────────────────────
if [ "$RELEASE_ARMS" = 1 ]; then
    if "$CXX" "$CXXSTD" -O2 -DNDEBUG -fno-discard-value-names "${INC[@]}" ${OPTFLAGS[@]+"${OPTFLAGS[@]}"} -S -emit-llvm "$WORK/probe.cpp" -o "$WORK/probe.ll" 2> "$WORK/cc2.log" \
       && "$CXX" "$CXXSTD" -O2 -DNDEBUG "${INC[@]}" ${OPTFLAGS[@]+"${OPTFLAGS[@]}"} -c "$WORK/probe.cpp" -o "$WORK/probe.o" 2>> "$WORK/cc2.log"; then
        ok "arm 2: release probe compiled (-O2 -DNDEBUG${OPTFLAGS[@]+ ${OPTFLAGS[*]}}, IR + object)"
        irBlock "$WORK/probe.ll" accNew   > "$WORK/new.ll"
        irBlock "$WORK/probe.ll" accOld   > "$WORK/old.ll"
        irBlock "$WORK/probe.ll" accPlain > "$WORK/plain.ll"
        # presence guard: every block was actually extracted (an empty block would make every grep below vacuous)
        for f in new old plain; do
            grep -q '^define ' "$WORK/$f.ll" || no "arm 2: could not extract the IR block of acc${f} (wrong artifact)"
        done
        newLoadsA="$( grep -c 'load i32, ptr %a,' "$WORK/new.ll" )"; oldLoadsA="$( grep -c 'load i32, ptr %a,' "$WORK/old.ll" )"
        newReload="$( reloadAfterStore < "$WORK/new.ll" )";      oldReload="$( reloadAfterStore < "$WORK/old.ll" )"
        # arm 2
        if grep -q '"separate_storage"' "$WORK/new.ll"; then ok "arm 2: accNew IR carries the \"separate_storage\" assume bundle"
        else no "arm 2: accNew IR has no \"separate_storage\" bundle — the macro is not an optimizer fact"; fi
        if [ "$newReload" = 0 ] && [ "$newLoadsA" = 1 ]; then ok "arm 2: accNew loads a ONCE, no reload after the store to out (loads of a: $newLoadsA)"
        else no "arm 2: accNew still reloads a after the store to out (loads of a: $newLoadsA, reload=$newReload)"; fi
        # arm 3, the negative control
        if ! grep -q '"separate_storage"' "$WORK/old.ll"; then ok "arm 3: accOld (old definition) IR carries no \"separate_storage\""
        else no "arm 3: accOld carries \"separate_storage\" — the control is not the old definition"; fi
        if [ "$oldReload" = 1 ] && [ "$oldLoadsA" = 2 ]; then ok "arm 3: accOld still reloads a after the store (loads of a: $oldLoadsA) — the old assume was inert"
        else no "arm 3: accOld does not show the reload (loads of a: $oldLoadsA, reload=$oldReload) — the control lost its defect"; fi
        if [ "$newReload" != "$oldReload" ]; then ok "arm 2/3: contrast — the two populations DISAGREE (new reload=$newReload, old reload=$oldReload)"
        else no "arm 2/3: NO CONTRAST — arms 2 and 3 agree (reload=$newReload); the gate examined one population twice"; fi
        # objdump bands
        cNew="$( insnCount "$WORK/probe.o" accNew )"; cOld="$( insnCount "$WORK/probe.o" accOld )"; cPlain="$( insnCount "$WORK/probe.o" accPlain )"
        echo "  info  release instructions: accPlain=$cPlain accOld=$cOld accNew=$cNew (measured 2026-09-12: arm64 10/10/6, x86-64 11/11/9)"
        if [ "$cPlain" -ge 6 ] && [ "$cPlain" -le 16 ]; then ok "arm 2: accPlain instruction count $cPlain in band [6,16]"
        else no "arm 2: accPlain instruction count $cPlain outside band [6,16] — count the wrong function?"; fi
        if [ "$cNew" -ge 3 ] && [ "$cNew" -le $(( cPlain - 2 )) ]; then ok "arm 2: accNew $cNew instructions, at least 2 below plain ($cPlain)"
        else no "arm 2: accNew $cNew instructions is not at least 2 below plain ($cPlain) — the assumption bought nothing"; fi
        if [ "$cOld" -ge $(( cPlain - 1 )) ]; then ok "arm 3: accOld $cOld instructions, no better than plain ($cPlain)"
        else no "arm 3: accOld $cOld instructions beats plain ($cPlain) — the old definition is not inert on this compiler; re-examine the control"; fi
    else
        no "arm 2: release probe failed to compile"; sed 's/^/    /' "$WORK/cc2.log"
    fi
elif [ "$CLASS" = NOT_CONSUMED ]; then
    warn "arms 2 and 3 skipped: NOT_CONSUMED — $CXXID has the builtin but its optimizer never reads the bundle (reload: default $rDefault, =true $rOn); the codegen rows cannot pass here and are not claimed"
else
    warn "arms 2 and 3 skipped: $CXX has no __builtin_assume_separate_storage (needs clang 17+); the debug and shape arms still run"
fi

# ── arm 4: zero bare __restrict in src/ CODE, with a positive control ────────────────────────────────────────
# Comments and string literals are stripped first (the §6 comment explains the trap by naming it, and
# src/layout.h lists the token in a keyword table); `__restrict__` is neutralised BEFORE the match, so a line
# carrying both spellings cannot hide the bare one behind a `grep -v`.
bareRestrict(){ grep -rnE '__restrict' --include='*.h' --include='*.hpp' --include='*.cpp' --include='*.cc' --include='*.c' --include='*.mm' --include='*.cu' --include='*.cuh' "$1" \
    | sed -E 's/"([^"\\]|\\.)*"//g; s#//.*$##; s#/\*[^*]*\*/##g; s/__restrict__/RESTRICT_OK/g' \
    | grep -E '__restrict([^A-Za-z0-9_]|$)'; }
mkdir -p "$WORK/pos" "$WORK/neg"
printf 'void f( int* __restrict p, const int* __restrict__ q );\n' > "$WORK/pos/bare.cpp"
printf '// the macOS trap: __restrict is #defined away\nstatic const char* kw[] = { "__restrict" };\nvoid g( int* __restrict__ p );\n' > "$WORK/neg/clean.cpp"
grep -q '__restrict p' "$WORK/pos/bare.cpp" || no "arm 4: positive-control fixture did not take"
if bareRestrict "$WORK/pos" > "$WORK/pos.hits" && grep -q 'bare.cpp:1:' "$WORK/pos.hits"; then ok "arm 4: positive control — the scan catches a bare __restrict beside a __restrict__"
else no "arm 4: positive control — the scan MISSED a bare __restrict (arm 4 cannot fail)"; fi
if bareRestrict "$WORK/neg" > "$WORK/neg.hits"; then no "arm 4: filter control — a comment / string literal / __restrict__ counted as bare:"; sed 's/^/    /' "$WORK/neg.hits"
else ok "arm 4: filter control — comment, string literal and __restrict__ are not bare"; fi
if bareRestrict "$ROOT/src" > "$WORK/src.hits"; then no "arm 4: bare __restrict in src/ code (macOS <sys/cdefs.h> deletes it in C++; spell it __restrict__):"; sed 's/^/    /' "$WORK/src.hits"
else ok "arm 4: zero bare __restrict in src/ code"; fi

# ── arm 5: the GCC shape — no builtin, the ( (void)0 ) fallback, still compiles ──────────────────────────────
# No library header but <cstdint> (which Diagnostics.h pulls anyway): the buffer form only needs a `.data()`.
cat > "$WORK/shape.cpp" <<'EOF'
#include <cstdint>
#include "Diagnostics.h"
struct Buf { uint32_t* p; uint32_t* data() const { return p; } };
void shapeScalar( uint32_t& p, uint32_t& q, uint32_t& r ) { VERIFY_NO_ALIAS( p, q ); VERIFY_NO_ALIAS3( p, q, r ); }
void shapeBuf( Buf& d, Buf& s ) { VERIFY_NO_ALIAS_BUF( d, s ); }
EOF
GCCSHAPE=( -U__clang__ -D__GNUC__=13 '-D__has_builtin(x)=0' "${QUIET[@]}" )
if "$CXX" "$CXXSTD" -fsyntax-only -DNDEBUG "${GCCSHAPE[@]}" "${INC[@]}" "$WORK/shape.cpp" 2> "$WORK/cc5.log"; then ok "arm 5: header compiles with __has_builtin forced 0 and __clang__ undefined (-DNDEBUG)"
else no "arm 5: header does not compile under the GCC shape (-DNDEBUG)"; sed 's/^/    /' "$WORK/cc5.log" | grep -E 'error' | head -8; fi
# The probe functions are the LAST thing in the TU, so "from shapeScalar to end of file" is exactly their
# expansion — clang's release VERIFY_TEXT carries _Pragma lines, which -E prints on lines of their own, so a
# per-line grep on the function name would see only the first line of each.
"$CXX" "$CXXSTD" -E -DNDEBUG "${GCCSHAPE[@]}" "${INC[@]}" "$WORK/shape.cpp" 2>/dev/null | sed -n '/shapeScalar/,$p' > "$WORK/shape.pp"
grep -q 'shapeScalar' "$WORK/shape.pp" || no "arm 5: preprocessed output lost the probe functions (wrong artifact)"
if grep -q '(void)0' "$WORK/shape.pp" && ! grep -q '__builtin_assume_separate_storage' "$WORK/shape.pp"; then ok "arm 5: GCC shape expands to the ( (void)0 ) fallback, never to the builtin"
else no "arm 5: GCC shape did not expand to the ( (void)0 ) fallback"; sed 's/^/    /' "$WORK/shape.pp" | cut -c1-200 | head -4; fi
if [ "$HAS_BUILTIN" = 1 ]; then
    "$CXX" "$CXXSTD" -E -DNDEBUG "${INC[@]}" "$WORK/shape.cpp" 2>/dev/null | sed -n '/shapeScalar/,$p' > "$WORK/shape_nat.pp"
    if grep -q '__builtin_assume_separate_storage' "$WORK/shape_nat.pp"; then ok "arm 5: contrast — the natural expansion on this compiler DOES use the builtin"
    else no "arm 5: NO CONTRAST — the natural expansion never reaches the builtin either; the fallback arm proves nothing"; fi
fi

# ── the buffer probe: VERIFY_NO_ALIAS_BUF (axpyBuf) vs VERIFY_NO_ALIAS on the objects (axpyObj) vs plain ──────
cat > "$WORK/bufprobe.cpp" <<'EOF'
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <vector>
#include "Diagnostics.h"

extern "C" void noalias_buf_anchor() {}

extern "C" __attribute__(( noinline )) void axpyPlain( std::vector<uint32_t>& dst, const std::vector<uint32_t>& src )
{
    for( std::size_t i = 0; i < dst.size(); ++i ) { dst[ i ] += src[ i ] * 3u; }
}
extern "C" __attribute__(( noinline )) void axpyObj( std::vector<uint32_t>& dst, const std::vector<uint32_t>& src )
{
    VERIFY_NO_ALIAS( dst, src );
    for( std::size_t i = 0; i < dst.size(); ++i ) { dst[ i ] += src[ i ] * 3u; }
}
extern "C" __attribute__(( noinline )) void axpyBuf( std::vector<uint32_t>& dst, const std::vector<uint32_t>& src )
{
    VERIFY_NO_ALIAS_BUF( dst, src );
    for( std::size_t i = 0; i < dst.size(); ++i ) { dst[ i ] += src[ i ] * 3u; }
}

int main( int argc, char** argv )
{
    if( argc > 1 && std::strcmp( argv[ 1 ], "same" ) == 0 )
    {
        std::vector<uint32_t> v( 4, 1u );
        axpyBuf( v, v );
        std::printf( "%u\n", v[ 0 ] );
        return 0;
    }
    std::vector<uint32_t> d, s;   // both empty: data() is null on both, the promise is vacuous
    axpyBuf( d, s );
    std::vector<uint32_t> d2( 8, 1u ), s2( 8, 2u );
    axpyBuf( d2, s2 );
    std::printf( "%u\n", d2[ 7 ] );
    return d2[ 7 ] == 7u && d.empty() ? 0 : 3;
}
EOF

# ── arm 6: the buffer form shortens the release loop; the object form must not ──────────────────────────────
if [ "$RELEASE_ARMS" = 1 ]; then
    if "$CXX" "$CXXSTD" -O2 -DNDEBUG "${INC[@]}" ${OPTFLAGS[@]+"${OPTFLAGS[@]}"} -c "$WORK/bufprobe.cpp" -o "$WORK/bufprobe.o" 2> "$WORK/cc6.log"; then
        ok "arm 6: buffer probe compiled (-O2 -DNDEBUG${OPTFLAGS[@]+ ${OPTFLAGS[*]}})"
        bPlain="$( insnCount "$WORK/bufprobe.o" axpyPlain )"; bObj="$( insnCount "$WORK/bufprobe.o" axpyObj )"; bBuf="$( insnCount "$WORK/bufprobe.o" axpyBuf )"
        echo "  info  release instructions: axpyPlain=$bPlain axpyObj=$bObj axpyBuf=$bBuf (measured 2026-09-12: arm64 65/65/61, x86-64 65/65/41)"
        if [ "$bPlain" -ge 20 ] && [ "$bPlain" -le 160 ]; then ok "arm 6: axpyPlain instruction count $bPlain in band [20,160]"
        else no "arm 6: axpyPlain instruction count $bPlain outside band [20,160] — count the wrong function?"; fi
        if [ "$bBuf" -ge 8 ] && [ "$bBuf" -le $(( bPlain - 2 )) ]; then ok "arm 6: VERIFY_NO_ALIAS_BUF loop $bBuf instructions, at least 2 below plain ($bPlain)"
        else no "arm 6: VERIFY_NO_ALIAS_BUF loop $bBuf instructions is not below plain ($bPlain) — the buffer promise bought nothing"; fi
        if [ "$bObj" -ge $(( bPlain - 1 )) ]; then ok "arm 6: negative control — VERIFY_NO_ALIAS on the two OBJECTS leaves the loop at $bObj (plain $bPlain)"
        else no "arm 6: negative control lost — the object form ALSO shortened the loop ($bObj vs plain $bPlain); the buffer form is no longer the discriminating one"; fi
    else
        no "arm 6: buffer probe failed to compile"; sed 's/^/    /' "$WORK/cc6.log"
    fi
elif [ "$CLASS" = NOT_CONSUMED ]; then
    warn "arm 6 skipped: NOT_CONSUMED on $CXXID — the buffer promise cannot be shown to buy anything here"
else
    warn "arm 6 skipped: $CXX has no __builtin_assume_separate_storage"
fi

# ── arm 7: buffer form in debug — empty vectors pass, the same vector twice traps naming both ───────────────
if "$CXX" "$CXXSTD" -O1 -g -Wall -Wextra "${INC[@]}" "$WORK/bufprobe.cpp" "$ROOT/src/infra/diagnostics.cpp" -o "$WORK/buf_dbg" 2> "$WORK/cc7.log"; then
    ok "arm 7: debug buffer probe compiled"
    "$WORK/buf_dbg" > "$WORK/b1.out" 2> "$WORK/b1.err"; rc=$?
    if [ "$rc" = 0 ] && grep -q '^7$' "$WORK/b1.out"; then ok "arm 7: two empty vectors, then two distinct ones -> exit 0, d2[7] = 7"
    else no "arm 7: distinct / empty vectors: rc=$rc out=$( cat "$WORK/b1.out" )"; sed 's/^/    /' "$WORK/b1.err" | head -8; fi
    ( "$WORK/buf_dbg" same > "$WORK/b2.out" 2> "$WORK/b2.err"; exit $? ) 2>/dev/null; rc=$?
    if [ "$rc" != 0 ]; then ok "arm 7: axpyBuf( v, v ) traps in debug (rc=$rc)"
    else no "arm 7: axpyBuf( v, v ) exited 0 in debug — VERIFY_NO_ALIAS_BUF did not fire"; fi
    if grep -q "'dst' and 'src' are the same container" "$WORK/b2.err"; then ok "arm 7: stderr names both expressions ('dst' and 'src')"
    else no "arm 7: stderr does not name 'dst' and 'src'"; sed 's/^/    /' "$WORK/b2.err" | head -8; fi
else
    no "arm 7: debug buffer probe failed to compile"; sed 's/^/    /' "$WORK/cc7.log" | head -12
fi

# ── arm 8: NEGATIVE CONTROL for the probe — the analysis forced OFF must bring the reload back ──────────────
# `-mllvm -basic-aa-separate-storage=false` puts an LLVM 18+ compiler in exactly the state AppleClang 16 / LLVM 17 is
# in before CMake adds the option, so on every dev machine here it is the only way to exercise that path locally.
# Same probe, same extraction, one flag flipped: if the reload does NOT come back, arm 2 was never able to fail.
if [ "$RELEASE_ARMS" = 1 ] && [ "$FLAG_ACCEPTED" = 1 ]; then
    if "$CXX" "$CXXSTD" -O2 -DNDEBUG -fno-discard-value-names "${INC[@]}" "${SEP_OFF[@]}" -S -emit-llvm "$WORK/probe.cpp" -o "$WORK/off.ll" 2> "$WORK/cc8.log" \
       && "$CXX" "$CXXSTD" -O2 -DNDEBUG "${INC[@]}" "${SEP_OFF[@]}" -c "$WORK/probe.cpp" -o "$WORK/off.o" 2>> "$WORK/cc8.log"; then
        ok "arm 8: release probe compiled with ${SEP_OFF[*]}"
        irBlock "$WORK/off.ll" accNew > "$WORK/off_new.ll"; irBlock "$WORK/off.ll" accBuiltin > "$WORK/off_builtin.ll"
        for f in off_new off_builtin; do grep -q '^define ' "$WORK/$f.ll" || no "arm 8: could not extract the IR block for $f (wrong artifact)"; done
        offLoadsA="$( grep -c 'load i32, ptr %a,' "$WORK/off_new.ll" )"; offReload="$( reloadAfterStore < "$WORK/off_new.ll" )"
        if grep -q '"separate_storage"' "$WORK/off_builtin.ll"; then ok "arm 8: the front end still emits the \"separate_storage\" bundle with the analysis off (the flag flips the reader, not the writer)"
        else no "arm 8: the bundle vanished with the analysis off — the flag changed the front end, not just BasicAA"; fi
        if [ "$offReload" = 1 ] && [ "$offLoadsA" = 2 ]; then ok "arm 8: with the analysis off accNew reloads a after the store (loads of a: $offLoadsA) — the arm-2 measurement can fail"
        else no "arm 8: with the analysis off accNew still shows no reload (loads of a: $offLoadsA, reload=$offReload) — the probe cannot distinguish consumed from ignored"; fi
        cOffNew="$( insnCount "$WORK/off.o" accNew )"; cOffPlain="$( insnCount "$WORK/off.o" accPlain )"
        echo "  info  release instructions with the analysis off: accPlain=$cOffPlain accNew=$cOffNew (measured 2026-09-12 Apple clang 21 arm64: 9/9)"
        if [ "$cOffNew" -ge $(( cOffPlain - 1 )) ]; then ok "arm 8: accNew $cOffNew instructions, no better than plain ($cOffPlain) with the analysis off — what the LLVM 17 leg saw"
        else no "arm 8: accNew $cOffNew instructions still beats plain ($cOffPlain) with the analysis off — the option did not take"; fi
        if [ -n "${newReload:-}" ] && [ "$newReload" != "$offReload" ]; then ok "arm 2/8: contrast — on and off DISAGREE (on reload=$newReload, off reload=$offReload)"
        else no "arm 2/8: NO CONTRAST — arm 2 (reload=${newReload:-unset}) and arm 8 (reload=$offReload) agree; the flag is not what separates them"; fi
    else
        no "arm 8: release probe failed to compile with ${SEP_OFF[*]}"; sed 's/^/    /' "$WORK/cc8.log"
    fi
elif [ "$CLASS" = NOT_CONSUMED ]; then
    warn "arm 8 skipped: NOT_CONSUMED on $CXXID — there is no consumed state to contrast against"
else
    warn "arm 8 skipped: $CXX has no __builtin_assume_separate_storage or rejects -mllvm (accepted: $FLAG_ACCEPTED)"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "FAILURES ABOVE"; exit 1; }
