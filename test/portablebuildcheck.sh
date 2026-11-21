#!/usr/bin/env bash
# portablebuildcheck.sh — gate for L1 ( independence MUST-FIX #5): "Non-NATIVE build hardcodes
# -mcpu=apple-m1 -ffast-math — Linux/x86 fails out of the box".
#
# Exercises the REAL arch-flag-selection logic in cmake/PortableFlags.cmake — not a reimplementation —
# by include()-ing it into a tiny standalone CMakeLists.txt in a scratch dir. This is deliberately NOT a
# full `cmake -S . -B ...` configure of the real project: that would pay for all 15 FetchContent grammar
# clones just to inspect three compiler flags. PortableFlags.cmake only touches APPLE/CMAKE_SYSTEM_PROCESSOR
# and the two options, so a `project(x LANGUAGES NONE)` host is enough to drive it for real.
#
# Checks:
#   1) default (no flags) configure on THIS machine: if this machine really is Apple Silicon, the auto
#      -mcpu=apple-m1 branch must fire (proves auto-detect still gives Apple-Silicon devs today's behavior).
#   2) default configure + RIPWIRE_PRETEND_LINUX=ON (the test-only hook): must emit -O2 -ffast-math
#      -fno-finite-math-only and NOTHING Apple/host-specific (-mcpu=apple-m1 absent, -march=native absent).
#      This is the provable half of "Linux/x86-64/aarch64 must configure cleanly with no Apple flags" —
#      see the NOTE at the bottom for what this machine cannot prove.
#   3) RIPWIRE_NATIVE=ON: must emit -march=native (opt-in, unaffected by RIPWIRE_PRETEND_LINUX).
#   4) the real top-level CMakeLists.txt no longer hardcodes -mcpu=apple-m1 unconditionally (it must be
#      confined to the RIPWIRE_IS_APPLE_SILICON branch inside cmake/PortableFlags.cmake).
#   5) the real top-level CMakeLists.txt still routes through cmake/PortableFlags.cmake (didn't drift back
#      to an inline literal).
#   6) no ordered STL algorithm over std::string_view takes the default comparator in src/ — a line-local grep
#      (#6), a pass that resolves each container through its declaration (#6b), and a pass that resolves each
#      explicit LAMBDA comparator's parameter and member types (#6c, the shape #343/#344/#345 landed with),
#      each with planted controls.
#   7) no range-for in src/ reads through a temporary that only C++23 P2718 keeps alive (`for( x : makeRow().items() )`
#      SEGFAULTs on GCC 13/14), resolved through each callee's declaration, with planted controls.
#
# Usage: test/portablebuildcheck.sh
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
MODULE="$ROOT/cmake/PortableFlags.cmake"
CMAKE_TOP="$ROOT/CMakeLists.txt"
TMP="$( mktemp -d )"
trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

command -v cmake >/dev/null 2>&1 || { echo "no cmake on PATH"; exit 2; }
[ -f "$MODULE" ] || { echo "missing $MODULE"; exit 2; }

# Build a tiny standalone project dir that only includes PortableFlags.cmake and prints its result.
# $2, when given, overrides CMAKE_SYSTEM_PROCESSOR before the include — the only way this
# Apple-Silicon machine can drive the x86-64 branch of the real module (LANGUAGES NONE means no
# toolchain probe runs afterwards to overwrite it).
mk_probe(){
    local dir="$1"
    local proc="${2:-}"
    mkdir -p "$dir/src"
    {
        printf 'cmake_minimum_required(VERSION 3.24)\n'
        printf 'project(portableprobe LANGUAGES NONE)\n'
        [ -n "$proc" ] && printf 'set(CMAKE_SYSTEM_PROCESSOR %s)\n' "$proc"
        printf 'include("%s")\n' "$MODULE"
    } >"$dir/CMakeLists.txt"
}

# Configure the probe with the given extra -D args; echoes the RIPWIRE_ARCH_FLAGS line (without the
# 'RIPWIRE_ARCH_FLAGS:' prefix), or nothing if the configure failed outright.
run_probe(){
    local dir="$1"; shift
    local proc="${PROBE_PROC:-}"
    mk_probe "$dir" "$proc"
    local log="$dir/configure.log"
    if ! cmake -S "$dir" -B "$dir/build" "$@" >"$log" 2>&1; then
        printf 'CONFIGURE_FAILED\n'
        return
    fi
    grep -o 'RIPWIRE_ARCH_FLAGS:.*' "$log" | tail -1 | sed 's/^RIPWIRE_ARCH_FLAGS://'
}

echo "portablebuildcheck: BIN=n/a (CMake-configure-level gate, no ripwire binary needed)"

# ── #1: default configure on THIS machine — Apple Silicon devs keep today's behavior ───────────────────
hostFlags="$( run_probe "$TMP/host" )"
hostArch="$( uname -s ):$( uname -m )"
if [ "$( uname -s )" = "Darwin" ] && { [ "$( uname -m )" = "arm64" ] || [ "$( uname -m )" = "aarch64" ]; }; then
    if printf '%s' "$hostFlags" | grep -q -- '-mcpu=apple-m1'; then
        ok "default configure on real Apple Silicon ($hostArch) auto-applies -mcpu=apple-m1: '$hostFlags'"
    else
        no "default configure on real Apple Silicon ($hostArch) did NOT apply -mcpu=apple-m1: '$hostFlags'"
    fi
else
    skip_note="host is $hostArch, not Apple Silicon — auto-detect branch not exercised by #1 on this machine"
    printf '  SKIP  %s\n' "$skip_note"
fi

# ── #2: RIPWIRE_PRETEND_LINUX=ON — the provable portable-path check ────────────────────────────────────
linuxFlags="$( run_probe "$TMP/linux" -DRIPWIRE_PRETEND_LINUX=ON )"
if [ "$linuxFlags" = "CONFIGURE_FAILED" ]; then
    no "RIPWIRE_PRETEND_LINUX=ON configure failed outright: $(tail -5 "$TMP/linux/configure.log" 2>/dev/null)"
elif printf '%s' "$linuxFlags" | grep -q -- '-mcpu=apple-m1'; then
    no "RIPWIRE_PRETEND_LINUX=ON still emits -mcpu=apple-m1: '$linuxFlags'"
elif printf '%s' "$linuxFlags" | grep -q -- '-march=native'; then
    no "RIPWIRE_PRETEND_LINUX=ON still emits -march=native: '$linuxFlags'"
elif printf '%s' "$linuxFlags" | grep -q -- '-O2' && printf '%s' "$linuxFlags" | grep -q -- '-ffast-math' \
     && printf '%s' "$linuxFlags" | grep -q -- '-fno-finite-math-only'; then
    ok "RIPWIRE_PRETEND_LINUX=ON configures clean with NO Apple/host-specific flag: '$linuxFlags'"
else
    no "RIPWIRE_PRETEND_LINUX=ON flags missing expected portable baseline: '$linuxFlags'"
fi

# ── #2b: the x86-64 FLOOR — an x86-64 target MUST carry -march=x86-64-v3 ──────────────────────────────
# Not cosmetic: src/infra/strkern.h compiles its AVX2 mirror behind __AVX2__, which only this flag defines
# on a portable build. Drop the flag and every x86-64 binary silently falls back to the scalar twins —
# correct output, several times the CPU on every text-scanning verb, and nothing else in the tree notices.
# The owner's floor is v3 (AVX2 + BMI1/2 + FMA + LZCNT + MOVBE, the RHEL 10 level), never v4/AVX-512.
x86Flags="$( PROBE_PROC=x86_64 run_probe "$TMP/x86" -DRIPWIRE_PRETEND_LINUX=ON )"
if [ "$x86Flags" = "CONFIGURE_FAILED" ]; then
    no "#2b x86-64 probe configure failed outright: $(tail -5 "$TMP/x86/configure.log" 2>/dev/null)"
elif ! printf '%s' "$x86Flags" | grep -q -- '-march=x86-64-v3'; then
    no "#2b an x86-64 target did NOT get the -march=x86-64-v3 floor (strkern.h's AVX2 path would not compile): '$x86Flags'"
elif printf '%s' "$x86Flags" | grep -qE -- '-march=x86-64-v4|-mavx512'; then
    no "#2b x86-64 floor was raised to v4/AVX-512, which the owner decision excludes: '$x86Flags'"
elif printf '%s' "$x86Flags" | grep -q -- '-mcpu=apple-m1'; then
    no "#2b x86-64 target also emits -mcpu=apple-m1: '$x86Flags'"
else
    ok "#2b x86-64 target carries the v3 floor and nothing Apple-specific: '$x86Flags'"
fi

# ── #2c: the floor is x86-ONLY — an aarch64 Linux target must not be handed an x86 -march ─────────────
armFlags="$( PROBE_PROC=aarch64 run_probe "$TMP/arm" -DRIPWIRE_PRETEND_LINUX=ON )"
# The sentinel FIRST (CodeRabbit #127 / 3985249736): CONFIGURE_FAILED contains no '-march=x86' either, so
# without this arm a broken aarch64-specific CMake path reported PASS on this portability gate — the exact
# shape #2b above already guards against, missing on the one arm whose expectation is an ABSENCE.
if [ "$armFlags" = "CONFIGURE_FAILED" ]; then
    no "#2c aarch64 probe configure failed outright: $(tail -5 "$TMP/arm/configure.log" 2>/dev/null)"
elif printf '%s' "$armFlags" | grep -q -- '-march=x86'; then
    no "#2c an aarch64 target was handed an x86 architecture flag: '$armFlags'"
else
    ok "#2c aarch64 target stays generic (NEON is baseline there, no flag needed): '$armFlags'"
fi

# ── #2d-#2g: the TARGET architecture decides the floor, never the HOST ─────────────────────────────────
# release.yml built the macOS x86_64 binary ON an arm64 runner through 0.6.1, and a source build still can:
# `-DCMAKE_OSX_ARCHITECTURES=x86_64`. CMake derives CMAKE_SYSTEM_PROCESSOR from the RUNNING machine there (arm64 — CMakeDetermineSystem honours only
# CMAKE_APPLE_SILICON_PROCESSOR, never CMAKE_OSX_ARCHITECTURES), so a floor keyed on it handed every x86_64
# compile `-mcpu=apple-m1` and no -march at all. Clang >= 17 (AppleClang 16 — the Xcode 16.2 release.yml
# pinned from c7982037 through 0.6.1) rejects that outright: "unsupported option '-mcpu=' for target". Clang 16 (AppleClang
# 15, every release through v0.5.0) let it through, so the Intel-Mac binary could only ever have been the
# x86-64 BASELINE — strkern.h's scalar twins, below the owner's v3 floor, and nothing else in the tree notices.
# #2b cannot see this: it SETS CMAKE_SYSTEM_PROCESSOR=x86_64, which a real cross configure never does.
# Darwin-only: CMAKE_OSX_ARCHITECTURES is a no-op everywhere else, and the Linux legs build natively (#2b/#2c).
cat >"$TMP/ccverdict.py" <<'PY'
# Reads a real configure's compile_commands.json; prints PASS/FAIL lines, then DONE (absent DONE = no verdict).
import json, shlex, subprocess, sys
ccPath, srcPrefix = sys.argv[ 1 ], sys.argv[ 2 ]
def argv( e ):
    return list( e[ 'arguments' ] ) if 'arguments' in e else shlex.split( e[ 'command' ] )
def targetsX86( a ):
    return any( a[ i ] == '-arch' and i + 1 < len( a ) and a[ i + 1 ] == 'x86_64' for i in range( len( a ) ) )
try:
    entries = [ e for e in json.load( open( ccPath ) ) if e.get( 'file', '' ).startswith( srcPrefix ) ]
except Exception as exc:
    entries = None
    print( 'FAIL compile_commands.json unreadable: %s' % exc )
if entries is not None and not entries:
    print( 'FAIL compile_commands.json lists no src/ translation unit — nothing was checked' )
elif entries:
    n   = len( entries )
    rel = lambda e: 'src/' + e[ 'file' ][ len( srcPrefix ): ]
    x86 = [ e for e in entries if targetsX86( argv( e ) ) ]
    v3  = [ e for e in entries if '-march=x86-64-v3' in argv( e ) ]
    m1  = [ e for e in entries if '-mcpu=apple-m1' in argv( e ) ]
    print( '%s %d of %d src/ compile lines target -arch x86_64 (the cross configure reached the compiler)' % ( 'PASS' if len( x86 ) == n else 'FAIL', len( x86 ), n ) )
    missing = [ rel( e ) for e in entries if '-march=x86-64-v3' not in argv( e ) ]
    print( '%s %d of %d src/ compile lines carry -march=x86-64-v3%s' % ( 'PASS' if not missing else 'FAIL', len( v3 ), n, ' (first without: %s)' % missing[ 0 ] if missing else '' ) )
    print( '%s %d of %d src/ compile lines carry -mcpu=apple-m1%s' % ( 'FAIL' if m1 else 'PASS', len( m1 ), n, ' (first: %s)' % rel( m1[ 0 ] ) if m1 else '' ) )
    # The macros the compiler DEFINES on one shipped TU's exact line (ingest.cpp includes strkern.h): the
    # flag list proves intent, only the preprocessor proves strkern.h's `#elif defined( __AVX2__ )` is taken.
    probe = next( ( e for e in entries if e[ 'file' ].endswith( '/src/ingest.cpp' ) ), entries[ 0 ] )
    line, skipNext = [], False
    for tok in argv( probe ):
        if skipNext:
            skipNext = False
        elif tok in ( '-o', '-MT', '-MF' ):
            skipNext = True
        elif tok not in ( '-c', '-MD', probe[ 'file' ] ):
            line.append( tok )
    r = subprocess.run( line + [ '-dM', '-E', '-x', 'c++', '/dev/null' ], cwd=probe.get( 'directory' ), capture_output=True, text=True )
    defs = { l.split()[ 1 ] for l in r.stdout.splitlines() if l.startswith( '#define ' ) and len( l.split() ) > 1 }
    if r.returncode != 0:
        print( 'FAIL the compiler REJECTED %s\'s exact x86_64 command line (rc=%d): %s' % ( rel( probe ), r.returncode, ( r.stderr.strip().splitlines() or [ '(no stderr)' ] )[ 0 ] ) )
    elif '__x86_64__' in defs and '__AVX2__' in defs:
        print( 'PASS %s\'s exact command line defines __x86_64__ and __AVX2__ — strkern.h compiles its AVX2 path' % rel( probe ) )
    else:
        print( 'FAIL %s\'s exact command line: __x86_64__=%s __AVX2__=%s — the shipped x86_64 binary would carry the SCALAR twins' % ( rel( probe ), '__x86_64__' in defs, '__AVX2__' in defs ) )
print( 'DONE' )
PY
if [ "$( uname -s )" = "Darwin" ]; then
    hostCpu="$( uname -m )"
    # #2d: module level, the host's own CMAKE_SYSTEM_PROCESSOR left alone — only the TARGET is named
    osxX86Flags="$( run_probe "$TMP/osx-x86" -DCMAKE_OSX_ARCHITECTURES=x86_64 )"
    if [ "$osxX86Flags" = "CONFIGURE_FAILED" ]; then
        no "#2d CMAKE_OSX_ARCHITECTURES=x86_64 probe configure failed outright: $(tail -5 "$TMP/osx-x86/configure.log" 2>/dev/null)"
    elif printf '%s' "$osxX86Flags" | grep -q -- '-mcpu=apple-m1'; then
        no "#2d an x86_64 target on a $hostCpu host was handed -mcpu=apple-m1 — the HOST chose the flags, not the target: '$osxX86Flags'"
    elif ! printf '%s' "$osxX86Flags" | grep -q -- '-march=x86-64-v3'; then
        no "#2d an x86_64 target on a $hostCpu host did NOT get the -march=x86-64-v3 floor: '$osxX86Flags'"
    else
        ok "#2d CMAKE_OSX_ARCHITECTURES=x86_64 on a $hostCpu host carries the v3 floor and nothing Apple-specific: '$osxX86Flags'"
    fi
    # #2e: the other direction — an arm64 target keeps its Apple Silicon tuning whatever the host is
    osxArmFlags="$( run_probe "$TMP/osx-arm" -DCMAKE_OSX_ARCHITECTURES=arm64 )"
    if [ "$osxArmFlags" = "CONFIGURE_FAILED" ]; then
        no "#2e CMAKE_OSX_ARCHITECTURES=arm64 probe configure failed outright: $(tail -5 "$TMP/osx-arm/configure.log" 2>/dev/null)"
    elif printf '%s' "$osxArmFlags" | grep -q -- '-march=x86'; then
        no "#2e an arm64 target on a $hostCpu host was handed an x86 architecture flag: '$osxArmFlags'"
    elif ! printf '%s' "$osxArmFlags" | grep -q -- '-mcpu=apple-m1'; then
        no "#2e an arm64 target on a $hostCpu host lost its Apple Silicon tuning: '$osxArmFlags'"
    else
        ok "#2e CMAKE_OSX_ARCHITECTURES=arm64 on a $hostCpu host keeps -mcpu=apple-m1: '$osxArmFlags'"
    fi
    # #2f: a universal tree cannot give one slice -march=x86-64-v3 and the other -mcpu=apple-m1 through one
    # add_compile_options(), and release.yml never builds one — the module must REFUSE it by name rather than
    # hand both slices one arch's flags (this same defect, on half the binary)
    fatFlags="$( run_probe "$TMP/osx-fat" '-DCMAKE_OSX_ARCHITECTURES=x86_64;arm64' )"
    if [ "$fatFlags" = "CONFIGURE_FAILED" ] && grep -q 'one architecture per build tree' "$TMP/osx-fat/configure.log"; then
        ok "#2f a universal CMAKE_OSX_ARCHITECTURES=x86_64;arm64 configure is refused by name, not given one slice's flags"
    elif [ "$fatFlags" = "CONFIGURE_FAILED" ]; then
        no "#2f the universal configure failed, but not with the refusal: $(tail -5 "$TMP/osx-fat/configure.log" 2>/dev/null)"
    else
        no "#2f a universal CMAKE_OSX_ARCHITECTURES=x86_64;arm64 configure was ACCEPTED with one flag set for both slices: '$fatFlags'"
    fi
    # #2g: the REAL project, exactly as release.yml configured its macos-x64 leg through 0.6.1 — every src/ compile line, and
    # the macros the compiler defines on one of them
    if ! cmake -S "$ROOT" -B "$TMP/real-x86" -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=x86_64 \
               -DCMAKE_EXPORT_COMPILE_COMMANDS=ON >"$TMP/real-x86.log" 2>&1; then
        no "#2g the real project's x86_64-target configure failed: $(tail -5 "$TMP/real-x86.log" 2>/dev/null)"
    else
        realVerdict="$( python3 "$TMP/ccverdict.py" "$TMP/real-x86/compile_commands.json" "$ROOT/src/" 2>&1 )"
        # a here-string, not a pipe: rows read in a pipeline subshell would print FAIL and leave fail=0
        while IFS= read -r row; do
            case "$row" in
                PASS\ *) ok "#2g ${row#PASS }" ;;
                FAIL\ *) no "#2g ${row#FAIL }" ;;
            esac
        done <<<"$realVerdict"
        printf '%s\n' "$realVerdict" | grep -q '^DONE$' \
            || no "#2g the compile_commands verdict never finished — no evidence either way: $( printf '%s' "$realVerdict" | tail -3 )"
    fi
else
    printf '  SKIP  #2d-#2g host is %s: CMAKE_OSX_ARCHITECTURES is Darwin-only (a no-op here); native Linux targets are #2b/#2c and the ubuntu CI legs\n' "$( uname -s )"
fi

# ── #2h retired with the release leg it held ──────────────────────────────────────────────────────────────────────
# #2h pinned release.yml's macos-x64 leg to the runner, Xcode and deployment target it was verified on, because that
# leg ran its x86-64-v3 binary under Rosetta 2. The leg left the matrix after 0.6.1, so there is no tuple to hold;
# test/releaseinstallcheck.sh (H7) now refuses a macOS x64 leg in release.yml, and re-adding one restores this arm
# from history (`git log -S relverdict -- test/portablebuildcheck.sh`) together with fresh evidence for its tuple.

# ── #2i: the macos-arm64 release leg ships the toolchain CI tests, at a pinned minimum macOS ───────────────────────────
# Three facts, held in step, text-level on any host:
#   * The leg's runner and Xcode are the exact pair its release was verified on, and ci.yml's macOS legs (the eight gate
#     shards and the sanitizer leg) run that same pair — TESTED == SHIPPED. Xcode 26.6 (17F113, Apple clang 21.0.0) is
#     there because ASSUME_NO_ALIAS's `__builtin_assume_separate_storage` reaches the loop vectorizer only from LLVM 18
#     (llvm/llvm-project#64666, fixed by #76770): Xcode 16.2's AppleClang 16, which built this leg through 0.6.1, is
#     LLVM 17 and keeps every runtime overlap check (test/noaliascheck.sh arm 6, LOOP_NOT_CONSUMED). A text check cannot
#     read a compiler version, so the pair is held exactly and moved deliberately, with noaliascheck's classification on
#     the new pair as the evidence. A half-done move is the other failure: an `ASAN_OPTIONS` or `DEVELOPER_DIR` condition
#     in ci.yml still naming the old runner silently turns leak detection on, or hands a leg the image's default Xcode.
#   * The minimum macOS is PINNED, a decision rather than a side effect of the runner. With no deployment target clang
#     takes the lower of the runner's macOS and the SDK default, which was 14.0 on macos-14 (otool on v0.6.1's
#     ripwire-0.6.1-macos-arm64: `minos 14.0`, `sdk 15.2`) and is 26.x on macos-26, so the runner move alone would have
#     dropped every macOS 14 and 15 user. 14.0 is also the std::print floor (src/infra/emit.h) and README's "Prebuilt
#     macOS floor"; quoted, because a bare 14.0 is a YAML number, not the string the otool minos check matches. ci.yml's
#     macOS legs build at the same target, since libc++ decides what it declares available by the deployment target.
#   * The pin reaches the binary and is read back off it: a step exports matrix.deployment_target as
#     MACOSX_DEPLOYMENT_TARGET before the first configure, and an otool minos step runs on build/ripwire after the PGO
#     binary is staged there and before Package tars it. The pin has ONE source: no -DCMAKE_OSX_DEPLOYMENT_TARGET,
#     -mmacosx-version-min or second MACOSX_DEPLOYMENT_TARGET anywhere in the leg or the build job's env and steps (a
#     `--cmake-extra -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0` on the pgobuild step would win over the export).
#   * Nothing fails silently. Every step that carries the pin runs on every macOS leg (`if:` absent or
#     `runner.os == 'macOS'`, never `matrix.deployment_target`, which skips a leg that lost the key), and each guard
#     that turns a lost pin into a red is present: the export's empty-target refusal, the exact string compare of
#     otool's minos, the toolchain record step (empty DEVELOPER_DIR, clang++ and llvm-profdata inside it) ahead of the
#     first build, and ci.yml's two CMakeCache.txt checks (the gate shards' front-end step, the asan macOS configure).
# Three mutated copies prove the verdict can fail, each by exactly its own row: release.yml without the minos step,
# release.yml whose pgobuild step overrides the target with -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0, and ci.yml whose sanitizer
# leg's ASAN_OPTIONS condition still names macos-14.
cat >"$TMP/armverdict.py" <<'PY'
import re, sys
relPath, ciPath = sys.argv[ 1 ], sys.argv[ 2 ]
rel, ci = open( relPath ).read(), open( ciPath ).read()
RUNNER, XCODE, MINOS = 'macos-26', '/Applications/Xcode_26.6.app/Contents/Developer', '14.0'
EXPECT = ( ( 'os',                RUNNER, False, 'the runner image that carries the pinned Xcode' ),
           ( 'developer_dir',     XCODE,  False, 'Apple clang 21.0.0 (LLVM 18+): the loop vectorizer reads the no-alias promise' ),
           ( 'deployment_target', MINOS,  True,  'the minimum macOS v0.6.1 shipped (otool minos 14.0)' ) )
def scalar( leg, key ):
    m = re.search( r"""^[ \t]*%s:[ \t]*("[^"\n]*"|'[^'\n]*'|[^\s#]+)""" % key, leg, re.M )
    if not m:
        return None, False
    raw    = m.group( 1 )
    quoted = len( raw ) >= 2 and raw[ 0 ] == raw[ -1 ] and raw[ 0 ] in '"\''
    return ( raw[ 1:-1 ] if quoted else raw ), quoted
def shown( value, quoted ):
    return '(absent)' if value is None else ( '"%s"' % value if quoted else value )
build  = rel.split( '\n  build:', 1 )[ 1 ].split( '\n  smoke-rhel:', 1 )[ 0 ] if '\n  build:' in rel else ''
matrix = build.split( 'include:', 1 )[ 1 ].split( '\n    runs-on:', 1 )[ 0 ] if 'include:' in build else ''
legs   = [ leg for leg in re.split( r'\n\s*- name: ', matrix )[ 1: ] if scalar( leg, 'asset_os' )[ 0 ] == 'macos' and scalar( leg, 'asset_arch' )[ 0 ] == 'arm64' ]
if len( legs ) != 1:
    print( 'FAIL expected exactly one release.yml build leg with asset_os macos and asset_arch arm64, found %d — nothing was checked' % len( legs ) )
else:
    leg  = legs[ 0 ]
    name = leg.split( '\n', 1 )[ 0 ].strip()
    for key, want, mustQuote, why in EXPECT:
        got, quoted = scalar( leg, key )
        if got == want and ( quoted or not mustQuote ):
            print( 'PASS leg %s %s: %s, %s' % ( name, key, shown( want, mustQuote ), why ) )
        else:
            print( 'FAIL leg %s %s: %s%s, but the verified tuple is %s — %s; moving it edits release.yml, ci.yml and #2i\'s tuple together, deliberately'
                   % ( name, key, shown( got, quoted ), ' (a bare YAML number)' if got == want else '', shown( want, mustQuote ), why ) )
    # The steps of the build job, in order. A step runs on this leg only when its `if:` is absent or `runner.os == 'macOS'`;
    # `if: ${{ matrix.deployment_target }}` is refused, because it silently skips a macOS leg that lost the key.
    steps = re.split( r'\n      - ', build.split( '\n    steps:', 1 )[ 1 ] if '\n    steps:' in build else '' )[ 1: ]
    def stepIf( step ):
        m = re.search( r'^[ \t]*if:[ \t]*(.+)$', step, re.M )
        return m.group( 1 ).strip() if m else ''
    def firstStep( pred ):
        return next( ( i for i, s in enumerate( steps ) if pred( s ) ), -1 )
    fires     = lambda s: stepIf( s ) in ( '', "runner.os == 'macOS'" )
    exportAt  = firstStep( lambda s: 'MACOSX_DEPLOYMENT_TARGET=${{ matrix.deployment_target }}' in s and '$GITHUB_ENV' in s and fires( s ) )
    buildAt   = firstStep( lambda s: 'cmake -S' in s or 'scripts/pgobuild.sh' in s )
    stagedAt  = firstStep( lambda s: 'cp build_pgo/ripwire build/ripwire' in s )
    minosAt   = firstStep( lambda s: 'otool -l build/ripwire' in s and '${{ matrix.deployment_target }}' in s and fires( s ) )
    packageAt = firstStep( lambda s: s.startswith( 'name: Package' ) )
    recordAt  = firstStep( lambda s: 'xcrun --find' in s and 'llvm-profdata' in s and 'clang++' in s and fires( s ) )
    emptyTargetGuard = r"""if \[ -z '\$\{\{ matrix\.deployment_target \}\}' \]; then[ \t]*\n[^\n]*>&2[ \t]*\n[ \t]*exit 1\b"""
    exactMinos       = r"""if \[ -z "\$minos" \] \|\| \[ "\$minos" != '\$\{\{ matrix\.deployment_target \}\}' \]; then[ \t]*\n[^\n]*>&2[ \t]*\n[ \t]*exit 1\b"""
    emptyDevDirGuard = r"""if \[ -z "\$DEVELOPER_DIR" \]; then[ \t]*\n[^\n]*>&2[ \t]*\n[ \t]*exit 1\b"""
    physicalDevDir   = r"""devDir="\$\( cd "\$DEVELOPER_DIR" && pwd -P \)" \|\| \{[^\n]*exit 1; \}"""
    outsidePrefix    = r"""case "\$path" in[ \t]*\n[ \t]*"\$devDir"/\*\)[ \t]*;;[ \t]*\n[ \t]*\*\)[^\n]*>&2;[ \t]*exit 1[ \t]*;;"""
    if exportAt < 0:
        print( 'FAIL leg %s: no step that runs on every macOS leg exports matrix.deployment_target as MACOSX_DEPLOYMENT_TARGET — the key pins nothing; the runner\'s macOS sets the minimum' % name )
    elif buildAt < 0 or exportAt > buildAt:
        print( 'FAIL leg %s: the MACOSX_DEPLOYMENT_TARGET export (step %d) does not precede the first configure (step %d)' % ( name, exportAt, buildAt ) )
    elif not re.search( emptyTargetGuard, steps[ exportAt ] ):
        print( 'FAIL leg %s: the export step (step %d) has no empty-deployment_target refusal (`if [ -z \'${{ matrix.deployment_target }}\' ]` ... `exit 1`) — a leg that lost the key would export an empty pin' % ( name, exportAt ) )
    else:
        print( 'PASS leg %s: step %d exports deployment_target as MACOSX_DEPLOYMENT_TARGET before the first configure (step %d), and refuses an empty one' % ( name, exportAt, buildAt ) )
    # One source for the pin: the leg and every part of the job after the matrix (env, steps), comment lines excluded.
    jobRest   = build.split( '\n    runs-on:', 1 )[ 1 ] if '\n    runs-on:' in build else ''
    scanned   = '\n'.join( l for l in ( leg + '\n' + jobRest ).split( '\n' ) if not l.lstrip().startswith( '#' ) )
    overrides = re.findall( r'-DCMAKE_OSX_DEPLOYMENT_TARGET=\S*|-mmacosx-version-min=\S*', scanned )
    overrides += [ m.group( 0 ).strip() for m in re.finditer( r'[^\n]*\bMACOSX_DEPLOYMENT_TARGET\b[^\n]*', scanned )
                   if 'MACOSX_DEPLOYMENT_TARGET=${{ matrix.deployment_target }}" >> "$GITHUB_ENV"' not in m.group( 0 ) ]
    if not jobRest:
        print( 'FAIL leg %s: the build job has no runs-on/steps section to scan for a deployment-target override — nothing was checked' % name )
    elif overrides:
        print( 'FAIL leg %s: a second deployment-target source in the leg or the build job overrides the exported %s: %s' % ( name, MINOS, overrides[ 0 ] ) )
    else:
        print( 'PASS leg %s: matrix.deployment_target is the only deployment-target source in the leg and the build job (no -D, -mmacosx-version-min or other MACOSX_DEPLOYMENT_TARGET)' % name )
    if minosAt < 0:
        print( 'FAIL leg %s: no step that runs on every macOS leg reads the minimum macOS back off build/ripwire (otool -l build/ripwire against ${{ matrix.deployment_target }}) — the pin is trusted, not checked' % name )
    elif not ( stagedAt >= 0 and packageAt >= 0 and stagedAt < minosAt < packageAt ):
        print( 'FAIL leg %s: the otool minos step (step %d) is not between the PGO staging (step %d) and Package (step %d) — it reads a binary other than the one shipped' % ( name, minosAt, stagedAt, packageAt ) )
    elif not re.search( exactMinos, steps[ minosAt ] ):
        print( 'FAIL leg %s: the otool minos step (step %d) is not the exact, fail-closed compare (`[ -z "$minos" ] || [ "$minos" != \'${{ matrix.deployment_target }}\' ]` ... `exit 1`)' % ( name, minosAt ) )
    else:
        print( 'PASS leg %s: step %d compares otool\'s minos off build/ripwire exactly with the pin, after the PGO binary is staged (step %d) and before Package (step %d)' % ( name, minosAt, stagedAt, packageAt ) )
    if recordAt < 0:
        print( 'FAIL leg %s: no step that runs on every macOS leg records clang++ and llvm-profdata through xcrun --find — PGO toolchain skew goes unchecked' % name )
    elif buildAt < 0 or recordAt > buildAt:
        print( 'FAIL leg %s: the toolchain record step (step %d) does not precede the first build (step %d)' % ( name, recordAt, buildAt ) )
    elif not ( re.search( emptyDevDirGuard, steps[ recordAt ] ) and re.search( outsidePrefix, steps[ recordAt ] ) and re.search( physicalDevDir, steps[ recordAt ] ) ):
        print( 'FAIL leg %s: the toolchain record step (step %d) lacks a fail-closed guard (empty DEVELOPER_DIR refusal, pwd -P, or the outside-DEVELOPER_DIR `exit 1`)' % ( name, recordAt ) )
    else:
        print( 'PASS leg %s: step %d, before the first build, fails on an empty DEVELOPER_DIR and on clang++ or llvm-profdata outside it' % ( name, recordAt ) )
    wired = re.search( r'^[ \t]*DEVELOPER_DIR:[ \t]*\$\{\{[ \t]*matrix\.developer_dir\b', build, re.M )
    print( 'PASS leg %s: the job env hands developer_dir to the toolchain as DEVELOPER_DIR' % name if wired else
           'FAIL leg %s: nothing exports matrix.developer_dir as DEVELOPER_DIR — the image\'s default Xcode, not the pinned one, builds the release' % name )
# ci.yml: every macOS runner label, every condition on one, every Xcode path and every deployment target is the release's.
ciRunners = ( re.findall( r'\b(?:os|runs-on):[ \t]*\[?[ \t]*(macos-[\w.-]+)', ci ) + re.findall( r',[ \t]*(macos-[\w.-]+)[ \t]*\]', ci ) )
ciConds   = re.findall( r"matrix\.os[ \t]*==[ \t]*'(macos-[^']*)'", ci )
ciXcodes  = re.findall( r'(/Applications/Xcode[^\'"\s]*/Contents/Developer)', ci )
ciDevDirs = re.findall( r'^[ \t]*DEVELOPER_DIR:.*$', ci, re.M )
ciTargets = re.findall( r'^[ \t]*MACOSX_DEPLOYMENT_TARGET:[ \t]*(.*)$', ci, re.M )
for what, found in ( ( 'runs-on label', ciRunners ), ( 'matrix.os condition', ciConds ) ):
    wrong = sorted( set( v for v in found if v != RUNNER ) )
    if not found:
        print( 'FAIL ci.yml: no macOS %s found — the extractor read nothing, or the macOS legs left CI' % what )
    elif wrong:
        print( 'FAIL ci.yml: %d of %d macOS %ss name %s, not the release runner %s — a leg tests another toolchain, or a condition no longer matches its leg'
               % ( sum( 1 for v in found if v != RUNNER ), len( found ), what, ', '.join( wrong ), RUNNER ) )
    else:
        print( 'PASS ci.yml: all %d macOS %ss name the release runner %s' % ( len( found ), what, RUNNER ) )
wrongX = sorted( set( x for x in ciXcodes if x != XCODE ) )
if not ciDevDirs or len( ciXcodes ) != len( ciDevDirs ) or wrongX:
    print( 'FAIL ci.yml: %d DEVELOPER_DIR line(s) name %d Xcode path(s) (%s), not exactly one %s each' % ( len( ciDevDirs ), len( ciXcodes ), ', '.join( sorted( set( ciXcodes ) ) ) or 'none', XCODE ) )
else:
    print( 'PASS ci.yml: all %d DEVELOPER_DIR lines name the release Xcode %s' % ( len( ciDevDirs ), XCODE ) )
wantTarget = "${{ matrix.os == '%s' && '%s' || '' }}" % ( RUNNER, MINOS )
if len( ciTargets ) != len( ciDevDirs ) or any( t.strip() != wantTarget for t in ciTargets ):
    print( 'FAIL ci.yml: %d MACOSX_DEPLOYMENT_TARGET line(s) beside %d DEVELOPER_DIR line(s); each macOS job env must set exactly %s (found: %s)'
           % ( len( ciTargets ), len( ciDevDirs ), wantTarget, '; '.join( t.strip() for t in ciTargets ) or 'none' ) )
else:
    print( 'PASS ci.yml: every job env that pins the Xcode also builds at MACOSX_DEPLOYMENT_TARGET %s, the release minimum' % MINOS )
# The fail-loudly guard on each macOS leg: an empty pin, or a CMake cache that did not receive it, exits 1.
cacheGuard  = r'if \[ -z "\$DEVELOPER_DIR" \] \|\| \[ -z "\$MACOSX_DEPLOYMENT_TARGET" \][ \t]*\\[ \t]*\n[ \t]*\|\| ! grep -qx "CMAKE_OSX_DEPLOYMENT_TARGET:STRING=\$MACOSX_DEPLOYMENT_TARGET" (\w+)/CMakeCache\.txt; then[ \t]*\n[^\n]*>&2[ \t]*\n[ \t]*exit 1\b'
guardTrees  = sorted( m.group( 1 ) for m in re.finditer( cacheGuard, ci ) )
if guardTrees != [ 'asan', 'build' ]:
    print( 'FAIL ci.yml: the CMakeCache.txt pin guards found are for %s, not exactly one each for build/ (the gate shards) and asan/ (the sanitizer leg) — a macOS leg that lost its pin builds silently' % ( guardTrees or 'no tree' ) )
else:
    print( 'PASS ci.yml: build/ and asan/ each fail when DEVELOPER_DIR or MACOSX_DEPLOYMENT_TARGET is empty or CMakeCache.txt lacks the pinned target' )
print( 'DONE' )
PY
armVerdict="$( python3 "$TMP/armverdict.py" "$ROOT/.github/workflows/release.yml" "$ROOT/.github/workflows/ci.yml" 2>&1 )"
while IFS= read -r row; do
    case "$row" in
        PASS\ *) ok "#2i ${row#PASS }" ;;
        FAIL\ *) no "#2i ${row#FAIL }" ;;
    esac
done <<<"$armVerdict"
printf '%s\n' "$armVerdict" | grep -q '^DONE$' \
    || no "#2i the release.yml/ci.yml verdict never finished — no evidence either way: $( printf '%s' "$armVerdict" | tail -3 )"
# The controls: each mutation must be WRITTEN, must TAKE (the copy differs), and must turn exactly its own row red — one
# FAIL line, the one named. A writer that crashed, a copy that did not change, a verdict that crashed or refused for some
# other reason: each is its own FAIL naming what happened, never a PASS and never the "not refused" row.
if ! python3 - "$ROOT/.github/workflows/release.yml" "$TMP/rel-nominos.yml" "$ROOT/.github/workflows/ci.yml" "$TMP/ci-oldasan.yml" \
        >"$TMP/mutate.log" 2>&1 <<'PY'
import re, sys
rel, relOut, ci, ciOut = sys.argv[ 1: ]
text = open( rel ).read()
open( relOut, 'w' ).write( re.sub( r'\n      - name: [^\n]*\n(?:(?!\n      - )[\s\S])*?otool -l build/ripwire[\s\S]*?(?=\n\n|\n      - )', '', text, count=1 ) )
text = open( ci ).read()
open( ciOut, 'w' ).write( re.sub( r"(ASAN_OPTIONS:[^\n]*matrix\.os[ \t]*==[ \t]*')macos-[^']*'", r"\1macos-14'", text, count=1 ) )
text = open( rel ).read()
open( relOut.replace( 'rel-nominos', 'rel-stepoverride' ), 'w' ).write(
    re.sub( r'(scripts/pgobuild\.sh --cmake-extra -DCMAKE_BUILD_TYPE=Release)', r'\1 --cmake-extra -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0', text, count=1 ) )
PY
then
    no "#2i control: the mutation writer failed, so neither control ran: $( tail -3 "$TMP/mutate.log" )"
else
    # armControl LABEL ORIGINAL MUTANT RELEASE_ARG CI_ARG EXPECTED_FAIL_REGEX
    armControl(){
        local label="$1" orig="$2" mutant="$3" relArg="$4" ciArg="$5" want="$6" out fails
        if [ ! -s "$mutant" ]; then
            no "#2i control ($label): the mutated copy $mutant was not written — nothing was checked"
            return 0
        fi
        if cmp -s "$orig" "$mutant"; then
            no "#2i control ($label): the mutation did not take — the copy is byte-identical to $( basename "$orig" ), nothing was checked"
            return 0
        fi
        out="$( python3 "$TMP/armverdict.py" "$relArg" "$ciArg" 2>&1 )"
        fails="$( printf '%s\n' "$out" | grep -c '^FAIL ' )"
        if ! printf '%s\n' "$out" | grep -q '^DONE$'; then
            no "#2i control ($label): the verdict never finished on the mutant — no evidence either way: $( printf '%s' "$out" | tail -3 )"
        elif [ "$fails" -eq 1 ] && printf '%s\n' "$out" | grep -qE "$want"; then
            ok "#2i control ($label): refused by name, and by that row alone"
        else
            no "#2i control ($label): expected exactly one FAIL matching '$want', got $fails: $( printf '%s\n' "$out" | grep '^FAIL ' | head -3 | tr '\n' ';' )"
        fi
        return 0
    }
    armControl "release.yml without the otool minos step" "$ROOT/.github/workflows/release.yml" "$TMP/rel-nominos.yml" \
               "$TMP/rel-nominos.yml" "$ROOT/.github/workflows/ci.yml" '^FAIL leg .*no step that runs on every macOS leg reads the minimum macOS back off build/ripwire'
    armControl "ci.yml ASAN_OPTIONS condition back on macos-14" "$ROOT/.github/workflows/ci.yml" "$TMP/ci-oldasan.yml" \
               "$ROOT/.github/workflows/release.yml" "$TMP/ci-oldasan.yml" '^FAIL ci\.yml: .*matrix\.os conditions name macos-14'
    armControl "pgobuild step overrides the target with -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0" "$ROOT/.github/workflows/release.yml" \
               "$TMP/rel-stepoverride.yml" "$TMP/rel-stepoverride.yml" "$ROOT/.github/workflows/ci.yml" \
               '^FAIL leg .*second deployment-target source.*-DCMAKE_OSX_DEPLOYMENT_TARGET=15\.0'
fi

# ── #3: RIPWIRE_NATIVE=ON stays opt-in and unaffected by the pretend-Linux hook ─────────────────────────
nativeFlags="$( run_probe "$TMP/native" -DRIPWIRE_NATIVE=ON -DRIPWIRE_PRETEND_LINUX=ON )"
if printf '%s' "$nativeFlags" | grep -q -- '-march=native'; then
    ok "RIPWIRE_NATIVE=ON emits -march=native regardless of RIPWIRE_PRETEND_LINUX: '$nativeFlags'"
else
    no "RIPWIRE_NATIVE=ON did not emit -march=native: '$nativeFlags'"
fi
if printf '%s' "$nativeFlags" | grep -q -- '-mcpu=apple-m1'; then
    no "RIPWIRE_NATIVE=ON unexpectedly also emits -mcpu=apple-m1: '$nativeFlags'"
else
    ok "RIPWIRE_NATIVE=ON does not also emit -mcpu=apple-m1"
fi

# ── #4/#5: the REAL top-level CMakeLists.txt routes through the module, no reintroduced literal ─────────
if grep -Eq '^\s*add_compile_options\(-O2 -mcpu=apple-m1' "$CMAKE_TOP"; then
    no "CMakeLists.txt still hardcodes -mcpu=apple-m1 unconditionally"
else
    ok "CMakeLists.txt no longer hardcodes -mcpu=apple-m1 unconditionally"
fi
if grep -q 'include(cmake/PortableFlags.cmake)' "$CMAKE_TOP" && grep -q 'add_compile_options(\${RIPWIRE_ARCH_FLAGS})' "$CMAKE_TOP"; then
    ok "CMakeLists.txt routes the optimization profile through cmake/PortableFlags.cmake"
else
    no "CMakeLists.txt does not route through cmake/PortableFlags.cmake"
fi

# ── #6: no ORDERED STL algorithm over std::string_view with the DEFAULT comparator, anywhere in src/ ──
# WHY THIS IS A PORTABILITY RULE AND NOT A STYLE ONE. libstdc++'s string_view three-way compare computes
# `n1 - n2` on size_type and lets it wrap (bits/string_view.h, _S_compare). That wrap is well-defined C++,
# but the G1 sanitizer stack runs -fsanitize=integer, which reports it, and -fno-sanitize-recover=all turns
# the report into an abort. libc++ (every macOS leg, including the macOS ASan leg) computes the same answer
# without the subtraction and never reports. So `std::binary_search( first, last, sv )` is green on this
# machine, green on the macOS sanitizer leg, and aborts EVERY ranked run on the Linux sanitizer leg.
# That is exactly what happened at 69a17f9: the external-name veto's two table lookups took main red with
# `unsigned integer overflow: 3 - 17` inside std::binary_search, on a repository whose own macOS battery
# and macOS ASan leg were both clean. The rule is therefore mechanical: pass an explicit byte-comparator.
SVBAD="$( grep -rnE '(binary_search|lower_bound|upper_bound|equal_range)\(' "$ROOT/src" 2>/dev/null \
          | grep -vE '^\s*[0-9]+:\s*//' \
          | grep -E 'kPythonBuiltinNames|kCFamilyStdNames|string_view' \
          | grep -vE 'nameLess|svLess|, *\[' || true )"
if [ -z "$SVBAD" ]; then
    ok "#6 no ordered STL search over string_view relies on libstdc++'s wrapping three-way compare"
else
    no "#6 ordered STL search over string_view with the DEFAULT comparator — aborts the Linux G1 leg (pass an explicit byte-comparator):"
    printf '%s\n' "$SVBAD" | sed 's/^/        /'
fi

# ── #6b: the same rule, resolved through each container's DECLARATION — the half the grep above cannot see ──
# #6 is line-local and type-blind: it fires only when `string_view` is spelled on the call line, and it never
# looked at std::sort at all. PR #135's extent detector sorted a std::vector<std::string_view> MEMBER declared
# 67 lines up and binary-searched a std::span<const std::string_view> PARAMETER (src/extentsuspect.h); neither
# call line names the type. #6 stayed green, both macOS legs stayed green, and on the Linux G1 leg every ingest
# of a C++ tree with two same-file class names that prefix one another aborted INSIDE ingest — before any verb
# ran, so even --pack-task's refusal arms died rc=134 with empty stderr (CI run 34583440115; the report,
# `unsigned integer overflow: 8 - 13` at libstdc++ string_view:576, came from resetExtentScratch's std::sort).
# The pass: every ordered algorithm called at its DEFAULT arity (no comparator argument) → the container its first
# argument ranges over (`x.begin()`, `std::begin( x )`, a ranges:: argument) → the NEAREST PRECEDING declaration
# of that name in the same file (a member access skips parameter-shaped ones). string_view anywhere in that
# declaration's template arguments (vector, span, array, a pair element) or a C array of string_view is a finding.
# static_assert calls are exempt: constant evaluation runs no sanitizer. A ranges call at the ambiguous
# iterator arity whose LAST argument is comparator-shaped (a lambda, a bare or qualified name) is the
# (range, comp) overload and is skipped here — a safe `ranges::sort( v, svLess )` must not be accused as
# a default-comparator call; #6c owns the lambda form. Disclosed floor: a BARE output-iterator name at
# that arity reads as a comparator, so a TWO_RANGE iterator form ending in a bare `out` escapes the
# default-comparator check. Stated blind spots — zero findings means
# "none found", not "none exists": a container declared in ANOTHER file, an `auto`-typed container, and a
# comparator lambda that itself applies `<` to string_views. The two control scans run on planted input every
# time, so a scanner that goes quiet fails this arm instead of passing it.
SVSCAN="$TMP/svorder.py"
cat > "$SVSCAN" <<'PY'
import bisect
import os
import re
import sys

# ordered algorithm -> its classic (iterator-pair) arity WITHOUT a comparator argument
ALGS = {
    'sort': 2, 'stable_sort': 2, 'partial_sort': 3, 'nth_element': 3, 'is_sorted': 2, 'is_sorted_until': 2,
    'min_element': 2, 'max_element': 2, 'minmax_element': 2, 'binary_search': 3, 'lower_bound': 3,
    'upper_bound': 3, 'equal_range': 3, 'inplace_merge': 3, 'includes': 4, 'lexicographical_compare': 4,
    'merge': 5, 'set_union': 5, 'set_intersection': 5, 'set_difference': 5, 'set_symmetric_difference': 5,
}
TWO_RANGE = {'includes', 'lexicographical_compare', 'merge', 'set_union', 'set_intersection', 'set_difference',
             'set_symmetric_difference'}
NOT_A_TYPE = {'return', 'co_return', 'co_yield', 'throw', 'case', 'else', 'delete', 'new', 'sizeof', 'alignof',
              'typename', 'goto', 'using', 'operator', 'do', 'not', 'and', 'or', 'template', 'class', 'struct'}
# sortutil::sortUnique( range[, less] ) sorts the way ranges::sort( range[, less] ) does, so it is read as one
CALL = re.compile(r'\b(?:std::(ranges::)?(' + '|'.join(ALGS) + r')|(?:rw::)?sortutil::(sortUnique))\s*\(')
# comments and literal contents are blanked (newlines kept, so offsets and lines stay true); a pp-number is matched
# first so a digit separator (1'000) is never read as a character literal
TOKEN = re.compile(r'//[^\n]*|/\*.*?\*/'
                   r'|(?<![\w])(?:u8|u|U|L)?R"(?P<delim>[^()\\\s]{0,16})\(.*?\)(?P=delim)"'
                   r"|(?<![\w])\d[\w']*"
                   r'|"(?:[^"\\\n]|\\.)*"'
                   r"|'(?:[^'\\\n]|\\.)*'", re.S)


def blank(text):
    """Replace comments and string/char literal CONTENTS with spaces, newlines and offsets preserved."""
    return TOKEN.sub(lambda m: m.group(0) if m.group(0)[0].isdigit() else re.sub(r'[^\n]', ' ', m.group(0)), text)


def split_args(text, open_index):
    """Top-level comma-separated argument texts of the call whose '(' is at open_index, or None."""
    depth, args, start = 0, [], open_index + 1
    for i in range(open_index, len(text)):
        c = text[i]
        if c in '([{':
            depth += 1
        elif c in ')]}':
            depth -= 1
            if depth == 0:
                args.append(text[start:i])
                return args
        elif c == ',' and depth == 1:
            args.append(text[start:i])
            start = i + 1
    return None


def container_of(arg):
    """(identifier, is_member_access) of the container the first argument ranges over, or None."""
    for pattern in (r'(\w+)\s*(?:\.|->)\s*c?r?(?:begin|end|data)\s*\(\s*\)',
                    r'std::(?:ranges::)?c?r?(?:begin|end|data)\s*\(\s*((?:\w+\s*(?:\.|->|::)\s*)*)(\w+)\s*\)',
                    r'^\s*((?:\w+\s*(?:\.|->)\s*)*)(\w+)\s*$'):
        m = re.search(pattern, arg)
        if not m:
            continue
        if m.lastindex == 1:
            before = arg[:m.start(1)].rstrip()
            return m.group(1), before.endswith('.') or before.endswith('->')
        return m.group(2), bool(m.group(1).strip())
    return None


def type_before(text, pos):
    """The type spelled right before a declarator at `pos`, or None when `pos` is not in declarator position."""
    i = pos - 1
    while i >= 0 and (text[i].isspace() or text[i] in '&*'):
        i -= 1
    if i >= 4 and text[i - 4:i + 1] == 'const' and (i < 5 or not (text[i - 5].isalnum() or text[i - 5] == '_')):
        i -= 5
        while i >= 0 and (text[i].isspace() or text[i] in '&*'):
            i -= 1
    end = i + 1
    if i >= 0 and text[i] == '>':
        if i >= 1 and text[i - 1] == '-':
            return None
        depth = 0
        while i >= 0:
            if text[i] == '>':
                depth += 1
            elif text[i] == '<':
                depth -= 1
                if depth == 0:
                    break
            elif text[i] in ';{}':
                return None
            i -= 1
        i -= 1
        while i >= 0 and text[i].isspace():
            i -= 1
    j = i
    while j >= 0 and (text[j].isalnum() or text[j] in '_:'):
        j -= 1
    head = text[j + 1:i + 1]
    if not head or head[0].isdigit() or head.endswith(':') or head.split('::')[-1] in NOT_A_TYPE:
        return None
    return re.sub(r'\s+', ' ', text[j + 1:end])


def comparator_shaped(seg):
    """True when a trailing argument reads as a comparator (lambda, bare or qualified name, function
    object) rather than an iterator end — the shapes this gate sees spell begin/end/next/prev."""
    s = seg.strip()
    if s.startswith('['):
        return True
    if re.search(r'\b(?:begin|end|next|prev|cbegin|cend|rbegin|rend)\s*\(', s) or re.search(r'\.\s*(?:begin|end)\s*\(', s):
        return False
    return bool(re.fullmatch(r'[\w:]+', s)) or re.search(r'[Ll]ess|[Gg]reater|[Cc]ompare', s)


def declarations(text, ident, cache):
    """Cached (position, spelled type, next char) rows of every declarator of `ident` in the file."""
    if ident not in cache:
        rows = []
        for m in re.finditer(r'\b' + re.escape(ident) + r'\s*([;={(,)\[])', text):
            spelled = type_before(text, m.start())
            if spelled is not None:
                rows.append((m.start(), spelled, m.group(1)))
        cache[ident] = rows
    return cache[ident]


def is_string_view_ordered(spelled, next_char):
    """True when a declaration of this shape orders string_views by default (container/element or C array)."""
    if re.search(r'<.*\bstring_view\b', spelled):
        return True   # a container (or pair/tuple element) of string_view: its operator< is the wrapping one
    return next_char == '[' and re.search(r'\bstring_view$', spelled) is not None   # a C array of string_view


def scan_file(path, rel):
    """Every default-comparator ordered algorithm over a string_view container declared in this file."""
    with open(path, encoding='utf-8', errors='replace') as fh:
        text = blank(fh.read())
    cache, findings = {}, []
    line_starts = [0] + [m.end() for m in re.finditer('\n', text)]
    for m in CALL.finditer(text):
        is_ranges, alg = m.group(1) is not None or m.group(3) is not None, m.group(2) or 'sort'
        args = split_args(text, m.end() - 1)
        if args is None:
            continue
        defaults = {ALGS[alg]}
        if is_ranges:
            defaults.add(ALGS[alg] - (2 if alg in TWO_RANGE else 1))
        if len(args) not in defaults:
            continue   # an explicit comparator (or projection) is passed
        if is_ranges and len(args) == ALGS[alg] and comparator_shaped(args[-1]):
            continue   # (range, comparator), not (first, last): #6c's lambda pass owns the explicit case —
            # counting it as a default-comparator call would accuse a safe `ranges::sort( v, svLess )`
        statement_start = max(text.rfind(';', 0, m.start()), text.rfind('{', 0, m.start()), text.rfind('}', 0, m.start()))
        if 'static_assert' in text[statement_start + 1:m.start()]:
            continue   # constant evaluation: no sanitizer runs there
        container = container_of(args[0])
        if container is None:
            continue
        ident, is_member = container
        rows = [r for r in declarations(text, ident, cache) if r[0] < m.start() and (not is_member or r[2] in ';={')]
        if not rows or not is_string_view_ordered(rows[-1][1], rows[-1][2]):
            continue
        line = bisect.bisect_right(line_starts, m.start())
        decl_line = bisect.bisect_right(line_starts, rows[-1][0])
        findings.append(f'{rel}:{line}: {m.group(0)[:-1].rstrip()} over `{ident}` '
                        f'(declared line {decl_line}: {rows[-1][1]}) with the default comparator')
    return findings


root = sys.argv[1].rstrip('/')
paths = []
for dirpath, dirnames, names in os.walk(root):
    dirnames.sort()
    for name in sorted(names):
        if name.endswith(('.h', '.hpp', '.hh', '.cpp', '.cc', '.cxx', '.inc', '.ipp')):
            paths.append(os.path.join(dirpath, name))
for path in paths:
    for finding in scan_file(path, os.path.relpath(path, os.path.dirname(root))):
        print(finding)
PY
if ! command -v python3 >/dev/null 2>&1; then
    no "#6b needs python3 on PATH to resolve declarations"
else
    mkdir -p "$TMP/svctl/planted" "$TMP/svctl/clean"
    # every line marked PLANT must be found, and nothing else: the #135 shapes plus the other element spellings
    cat > "$TMP/svctl/planted/planted.h" <<'EOF'
inline constexpr int kBig = 1'000'000;
inline constexpr const char* kRaw = R"x(a "quoted" ) paren)x";
struct Scratch
{
    std::vector<std::string_view> names;
};
inline bool has( std::span<const std::string_view> names, std::string_view s )
{
    return std::binary_search( names.begin(), names.end(), s );   // PLANT
}
inline void reset( Scratch& scratch )
{
    std::sort( scratch.names.begin(),   // PLANT
               scratch.names.end() );
}
inline void pairs()
{
    std::vector<std::pair<std::string_view, int>> rows;
    std::sort( rows.begin(), rows.end() );   // PLANT
}
inline void carr()
{
    std::string_view table[ 3 ] = { "b", "a", "ab" };
    std::sort( std::begin( table ), std::end( table ) );   // PLANT
}
inline void ranges( std::vector<std::string_view>& v )
{
    std::ranges::sort( v );   // PLANT
}
inline void helper( std::vector<std::string_view>& v )
{
    rw::sortutil::sortUnique( v );   // PLANT
}
EOF
    # none of these may be found: byte comparators, a std::string collision, constant evaluation,
    # ranges::sort( range, svLess ) — the (range, comp) overload, #6c's case — and text that only spells a call
    cat > "$TMP/svctl/clean/clean.h" <<'EOF'
inline constexpr const char* kRaw = R"x(std::sort( names.begin(), names.end() ) ")x";
struct Scratch2
{
    std::vector<std::string_view> names;
};
inline void reset2( Scratch2& scratch )
{
    std::sort( scratch.names.begin(), scratch.names.end(), rw::sortutil::svLess );
    rw::sortutil::sortUnique( scratch.names, rw::sortutil::svLess );
}
inline bool has2( std::span<const std::string_view> names, std::string_view s )
{
    return std::binary_search( names.begin(), names.end(), s, rw::sortutil::svLess );
}
inline void collision()
{
    std::vector<std::string> names;
    std::sort( names.begin(), names.end() );
}
constexpr std::string_view kTable[] = { "a", "ab", "b" };
static_assert( std::is_sorted( std::begin( kTable ), std::end( kTable ) ) );
// std::sort( names.begin(), names.end() );  a comment is not a call
inline const char* help = "std::sort( names.begin(), names.end() )";
inline void sortChars()
{
    std::string_view chars = "cba";
    std::string buf( chars );
    std::sort( buf.begin(), buf.end() );
}
inline void rangesSvLess3( std::vector<std::string_view>& names )
{
    std::ranges::sort( names, rw::sortutil::svLess );
}
EOF
    wantPlanted="$( grep -n 'PLANT' "$TMP/svctl/planted/planted.h" | cut -d: -f1 | sed 's#^#planted/planted.h:#' )"
    gotPlanted="$( python3 "$SVSCAN" "$TMP/svctl/planted" | cut -d: -f1,2 )"
    if [ -n "$wantPlanted" ] && [ "$gotPlanted" = "$wantPlanted" ]; then
        ok "#6b control: the declaration pass finds exactly the $( printf '%s\n' "$wantPlanted" | wc -l | tr -d ' ' ) planted calls (member, span parameter, pair element, C array, ranges::, sortutil::sortUnique)"
    else
        no "#6b control: planted default-comparator calls not found exactly — want [$( printf '%s ' $wantPlanted )] got [$( printf '%s ' $gotPlanted )]"
    fi
    gotClean="$( python3 "$SVSCAN" "$TMP/svctl/clean" )"; cleanRc=$?
    if [ "$cleanRc" -eq 0 ] && [ -z "$gotClean" ]; then
        ok "#6b control: byte comparators, a std::string collision, static_assert, ranges::sort( range, svLess ) and call-shaped text are not findings"
    else
        no "#6b control: the clean input produced findings (rc=$cleanRc):"
        printf '%s\n' "$gotClean" | sed 's/^/        /'
    fi
    SVDECL="$( python3 "$SVSCAN" "$ROOT/src" )"; svRc=$?
    if [ "$svRc" -ne 0 ]; then
        no "#6b the declaration pass itself failed on src/ (rc=$svRc) — a crashed scan is not a clean one"
    elif [ -z "$SVDECL" ]; then
        ok "#6b no ordered STL algorithm over a string_view container takes the default comparator (resolved through its declaration)"
    else
        no "#6b ordered STL algorithm over a string_view container with the DEFAULT comparator — aborts the Linux G1 leg (pass rw::sortutil::svLess):"
        printf '%s\n' "$SVDECL" | sed 's/^/        /'
    fi
fi

# ── #6c: no LAMBDA COMPARATOR of an ordered STL algorithm orders string_view operands with operator< ──
# #6 and #6b both stop at the call's SHAPE: #6 excludes every call that passes a comparator at all, and
# #6b resolves only the CONTAINER of default-comparator calls. A lambda that is explicit but itself says
# `return a < b;` over string_view operands walks through both arms straight into libstdc++'s
# string_view::_S_compare — the `n1 - n2` wrap G1 aborts on. The top-level <string_view> header carrying
# _S_compare is NOT in CMakeLists' libstdc++ ignorelist (that covers bits/basic_string.h and
# bits/string_view.tcc), which is how #343 (pathInIgnoreSet), #344 (situ's lexical-sibling index) and
# #345 (finalizeNamedIdents) landed green on main while the Linux G1 self-run and --situ aborted.
# This pass resolves the lambda's operand types two ways: DECLARED string_view parameters (by value, by
# const reference, by pointer), and struct members declared std::string_view (the struct map is built
# brace-balanced from every file under the scanned root, so a brace-initialized field counts and a
# member defined in model.h resolves at its use in renamemine.h). A named comparator variable
# (`const auto byPath = []( … ){ … };` passed to five sorts) resolves through its definition. Safe calls
# (svLess, nameLess, memcmp) are blanked per CALL, not per lambda — a MIXED comparator that routes one
# key through svLess and orders another with raw operator< is still a finding — and every relational
# operator is judged inside its own ternary branch/statement, so a numeric tie-break beside svLess calls
# (finalizeNamedIdents' shape) is not. `std::ranges::sort( range, comp )` — ambiguous with (first, last)
# by arity alone — is classified by its last argument's shape, so #6b's default-comparator pass never
# accuses a safe `ranges::sort( v, svLess )` and this pass owns the lambda form.
# FLOOR, disclosed: `const auto&` parameters, std::pair .first/.second members, locals aliasing a
# container element (`const Symbol& x = ing.symbols[a];`), and a PROJECTION lambda of a
# (range, comp, projection) call — scanned only as a comparator candidate, never resolved as a
# projection — are NOT resolved; the clean control pins the auto-parameter floor so it cannot widen
# silently. Hand-rolled memcmp comparators (ingest.h's extLess) are clean by contract:
# memcmp-then-length never subtracts.
SVLC="$TMP/svlambda.py"
cat > "$SVLC" <<'PY'
import bisect
import os
import re
import sys

ALGS = {
    'sort': 2, 'stable_sort': 2, 'partial_sort': 3, 'nth_element': 3, 'is_sorted': 2, 'is_sorted_until': 2,
    'min_element': 2, 'max_element': 2, 'minmax_element': 2, 'binary_search': 3, 'lower_bound': 3,
    'upper_bound': 3, 'equal_range': 3, 'inplace_merge': 3, 'includes': 4, 'lexicographical_compare': 4,
    'merge': 5, 'set_union': 5, 'set_intersection': 5, 'set_difference': 5, 'set_symmetric_difference': 5,
}
TWO_RANGE = {'includes', 'lexicographical_compare', 'merge', 'set_union', 'set_intersection', 'set_difference',
             'set_symmetric_difference'}
# sortutil::sortUnique( range[, less] ) sorts the way ranges::sort( range[, less] ) does, so it is read as one
CALL = re.compile(r'\b(?:std::(ranges::)?(' + '|'.join(ALGS) + r')|(?:rw::)?sortutil::(sortUnique))\s*\(')
TOKEN = re.compile(r'//[^\n]*|/\*.*?\*/'
                   r'|(?<![\w])(?:u8|u|U|L)?R"(?P<delim>[^()\\\s]{0,16})\(.*?\)(?P=delim)"'
                   r"|(?<![\w])\d[\w']*"
                   r'|"(?:[^"\\\n]|\\.)*"'
                   r"|'(?:[^'\\\n]|\\.)*'", re.S)
STRUCT_HEAD = re.compile(r'\bstruct\s+(\w+)[^{;]*\{')
SV_FIELD = re.compile(r'(?:std::)?string_view\s+(\w+)\s*(?:\{[^{}]*\})?\s*[;=]')
SV_PARAM = re.compile(r'(?:std::)?string_view\s+(\w+)')
REF_PARAM = re.compile(r'(?:const\s+)?(\w+)\s*(?:const\s*)?[&*]\s*(\w+)')
REL = re.compile(r'(?<![<>=!-])<(?![<=])|(?<![<>=-])>(?![>=])')
SAFE_CALL = re.compile(r'\b(?:svLess|nameLess|memcmp)\s*\(')
NOT_MEMBER = r'(?!\s*(?:\.|->))'   # `a.size() < b.size()` orders numbers, not the string_views themselves


def blank(text):
    """Replace comments and string/char literal CONTENTS with spaces, newlines and offsets preserved."""
    return TOKEN.sub(lambda m: m.group(0) if m.group(0)[0].isdigit() else re.sub(r'[^\n]', ' ', m.group(0)), text)


def comparator_shaped(seg):
    """True when a trailing argument reads as a comparator (lambda, bare or qualified name, function
    object) rather than an iterator end — the shapes this gate sees spell begin/end/next/prev."""
    s = seg.strip()
    if s.startswith('['):
        return True
    if re.search(r'\b(?:begin|end|next|prev|cbegin|cend|rbegin|rend)\s*\(', s) or re.search(r'\.\s*(?:begin|end)\s*\(', s):
        return False
    return bool(re.fullmatch(r'[\w:]+', s)) or re.search(r'[Ll]ess|[Gg]reater|[Cc]ompare', s)


def split_args_off(text, open_index):
    """Top-level comma-separated argument (start, end) spans of the call whose '(' is at open_index."""
    depth, args, start = 0, [], open_index + 1
    for i in range(open_index, len(text)):
        c = text[i]
        if c in '([{':
            depth += 1
        elif c in ')]}':
            depth -= 1
            if depth == 0:
                args.append((start, i))
                return args
        elif c == ',' and depth == 1:
            args.append((start, i))
            start = i + 1
    return None


def match_paren(text, open_index):
    """Index of the ')' balancing the '(' at open_index, or -1."""
    depth = 0
    for i in range(open_index, len(text)):
        if text[i] == '(':
            depth += 1
        elif text[i] == ')':
            depth -= 1
            if depth == 0:
                return i
    return -1


def brace_body(text, open_pos):
    """Text between the '{' at open_pos and its balanced '}' (nested braces included), or None."""
    depth = 0
    for i in range(open_pos, len(text)):
        if text[i] == '{':
            depth += 1
        elif text[i] == '}':
            depth -= 1
            if depth == 0:
                return text[open_pos + 1:i]
    return None


def lambda_at(text, pos):
    """pos points at the lambda's '['. Returns (params, body, pos) or None."""
    close_bracket = text.find(']', pos)
    if close_bracket < 0:
        return None
    p_open = text.find('(', close_bracket)
    if p_open < 0:
        return None
    p_close = match_paren(text, p_open)
    if p_close < 0:
        return None
    brace = text.find('{', p_close)
    if brace < 0 or brace - p_close > 40:      # only noexcept/mutable/-> may sit between
        return None
    body = brace_body(text, brace)
    if body is None:
        return None
    return text[p_open + 1:p_close], body, pos


def sv_operands(params, localmap, structmap):
    """Regexes matching every operand of this lambda that is known to be a string_view.

    A struct declared in the SCANNED FILE wins over the whole-root map: two files may each declare a
    `struct Cand` over a different member type (mcpedit.h's std::string n beside didyoumean.h's
    std::string_view n), and merging them would accuse the std::string one — basic_string's _S_compare
    is in CMakeLists' ignorelist, string_view's is not. Every pattern carries the NOT_MEMBER lookahead:
    an operand immediately followed by `.member` is not the string_view itself (`a.size()` is a number).
    Reference parameters resolve two ways: a `const std::string_view&` parameter IS a string_view
    operand; a `const T&` parameter contributes T's string_view members as `param.member` patterns."""
    pats = []
    for m in SV_PARAM.finditer(params):
        pats.append(re.compile(r'\b' + re.escape(m.group(1)) + NOT_MEMBER))
    for m in REF_PARAM.finditer(params):
        typ, pname = m.group(1), m.group(2)
        if re.fullmatch(r'(?:std::)?string_view', typ):
            pats.append(re.compile(r'\b' + re.escape(pname) + NOT_MEMBER))   # SV_PARAM matches by-value only
            continue
        fields = localmap[typ] if typ in localmap else structmap.get(typ, ())
        for field in fields:
            pats.append(re.compile(r'\b' + re.escape(pname) + r'\s*(?:\.|->)\s*' + re.escape(field) + r'\b' + NOT_MEMBER))
    return pats


def blank_safe_calls(body):
    """Every svLess/nameLess/memcmp call replaced with spaces, offsets and newlines kept.

    Those comparators are safe by contract (memcmp-then-length never subtracts), but only the CALL is:
    a mixed comparator that routes one key through svLess and orders ANOTHER string_view with raw
    operator< is a finding the old whole-lambda exemption hid. Blanking keeps the safe call's operands
    out of the scan while every relational operator outside it still faces the operand patterns."""
    out = list(body)
    for m in SAFE_CALL.finditer(body):
        close = match_paren(body, m.end() - 1)
        if close < 0:
            continue
        for i in range(m.start(), close + 1):
            if out[i] != '\n':
                out[i] = ' '
    return ''.join(out)


def branch_window(red, pos):
    """(lo, hi) of the ternary branch / statement around pos: cut at `;`, braces, `?` and a single `:`
    (`::` stays whole), so a numeric tie-break in one branch never sees the string_view operands a
    sibling branch names — the false report a fixed ±60-character proximity window produced."""
    def cut(i):
        if red[i] in ';{}?':
            return True
        return red[i] == ':' and (i + 1 >= len(red) or red[i + 1] != ':') and (i == 0 or red[i - 1] != ':')
    lo = 0
    for i in range(pos - 1, -1, -1):
        if cut(i):
            lo = i + 1
            break
    hi = len(red)
    for i in range(pos, len(red)):
        if cut(i):
            hi = i
            break
    return lo, hi


def orders_sv(body, pats):
    """True when the lambda orders known string_view operands with a relational operator directly:
    safe-comparator calls blanked first, each operator judged inside its own branch/statement."""
    red = blank_safe_calls(body)
    for m in REL.finditer(red):
        lo, hi = branch_window(red, m.start())
        window = red[lo:hi]
        for p in pats:
            if p.search(window):
                return True
    return False


def scan_file(text, path, rel, structmap, localmap):
    """Every ordered-algorithm comparator lambda in this file that orders string_views with operator<."""
    line_starts = [0] + [m.end() for m in re.finditer('\n', text)]
    findings = {}

    def line_of(pos):
        """1-based line number of a byte offset."""
        return bisect.bisect_right(line_starts, pos)

    def analyze(params, body, bracket_pos, alg, is_ranges):
        """File a finding when this lambda's declared operands are string_views and it orders them raw."""
        pats = sv_operands(params, localmap, structmap)
        if pats and orders_sv(body, pats):
            findings[line_of(bracket_pos)] = (
                f'{rel}:{line_of(bracket_pos)}: std::{"ranges::" if is_ranges else ""}{alg} comparator lambda '
                f'orders string_view operands with operator< (libstdc++ string_view::_S_compare wraps; '
                f'pass rw::sortutil::svLess)')

    named = {}
    for m in re.finditer(r'\bauto\s+(\w+)\s*=\s*(?=\[)', text):
        lam = lambda_at(text, text.find('[', m.end() - 1))
        if lam:
            named[m.group(1)] = lam

    for m in CALL.finditer(text):
        is_ranges, alg = m.group(1) is not None or m.group(3) is not None, m.group(2) or 'sort'
        args = split_args_off(text, m.end() - 1)
        if args is None:
            continue
        defaults = {ALGS[alg]}
        if is_ranges:
            defaults.add(ALGS[alg] - (2 if alg in TWO_RANGE else 1))
        cand = []
        if len(args) == max(defaults) + 1:
            cand = [len(args) - 1]
            if is_ranges and len(args) >= 3:
                cand.append(len(args) - 2)      # (range, comp, projection): the comparator is second-to-last
        elif (is_ranges and len(args) == ALGS[alg] and len(args) >= 2
              and comparator_shaped(text[args[-1][0]:args[-1][1]])):
            cand = [len(args) - 1]              # (range, comp), not (first, last) — decided by the last
        if not cand:                            # argument's shape; the default comparator stays #6b's
            continue
        statement_start = max(text.rfind(';', 0, m.start()), text.rfind('{', 0, m.start()),
                              text.rfind('}', 0, m.start()))
        if 'static_assert' in text[statement_start + 1:m.start()]:
            continue                            # constant evaluation: no sanitizer runs there
        for idx in cand:
            start, end = args[idx]
            seg = text[start:end]
            if seg.lstrip().startswith('['):
                lam = lambda_at(text, text.find('[', start))
                if lam:
                    analyze(*lam, alg=alg, is_ranges=is_ranges)
            else:
                nm = seg.strip()
                if re.fullmatch(r'\w+', nm) and nm in named:
                    params, body, pos = named[nm]
                    analyze(params, body, pos, alg, is_ranges)
    return [findings[k] for k in sorted(findings)]


root = sys.argv[1].rstrip('/')
paths = []
for dirpath, dirnames, names in os.walk(root):
    dirnames.sort()
    for name in sorted(names):
        if name.endswith(('.h', '.hpp', '.hh', '.cpp', '.cc', '.cxx', '.inc', '.ipp')):
            paths.append(os.path.join(dirpath, name))
texts = {}
structmap = {}
localmaps = {}
for path in paths:
    with open(path, encoding='utf-8', errors='replace') as fh:
        text = blank(fh.read())
    texts[path] = text
    localmap = {}
    for m in STRUCT_HEAD.finditer(text):
        body = brace_body(text, m.end() - 1)   # balanced: a brace-initialized field (`name{}`) no longer
        if body is None:                       # hides the whole struct body from the member map
            continue
        fields = structmap.setdefault(m.group(1), set())
        local = localmap.setdefault(m.group(1), set())
        for fm in SV_FIELD.finditer(body):
            fields.add(fm.group(1))
            local.add(fm.group(1))
    localmaps[path] = localmap
for path in paths:
    for finding in scan_file(texts[path], path, os.path.relpath(path, os.path.dirname(root)), structmap,
                             localmaps[path]):
        print(finding)
PY
if ! command -v python3 >/dev/null 2>&1; then
    no "#6c needs python3 on PATH to resolve lambda parameter types"
else
    mkdir -p "$TMP/svlctl/planted" "$TMP/svlctl/clean"
    # every line marked PLANT must be found, and nothing else: the four shapes #343/#344/#345 landed with,
    # plus the four the review round added (a brace-initialized member, const string_view& parameters, a
    # mixed svLess/raw comparator, and the ranges (range, comp) overload)
    cat > "$TMP/svlctl/planted/planted.h" <<'EOF'
struct Row6c
{
    std::string_view dir;
    std::string_view path;
};
struct Sym6c { std::string_view name; };
inline bool search6c( const std::vector<std::string>& sorted, std::string_view rel )
{
    return std::binary_search( sorted.begin(), sorted.end(), rel,
        []( std::string_view a, std::string_view b ) noexcept { return a < b; } );   // PLANT
}
inline void sort6c( std::vector<Row6c>& rows )
{
    std::sort( rows.begin(), rows.end(), []( const Row6c& a, const Row6c& b ) noexcept   // PLANT
               { return a.dir != b.dir ? a.dir < b.dir : a.path < b.path; } );
}
inline bool lower6c( const std::vector<Row6c>& rows, std::string_view dir )
{
    return std::lower_bound( rows.begin(), rows.end(), dir,
        []( const Row6c& row, std::string_view d ) noexcept { return row.dir < d; } ) != rows.end();   // PLANT
}
inline void named6c( std::vector<Sym6c*>& v, const std::string& n )
{
    const auto byName = []( const Sym6c* s, const std::string& x ) { return s->name < x; };   // PLANT
    std::lower_bound( v.begin(), v.end(), n, byName );
}
struct Brace6c { std::string_view dir{}; };
inline void braceInit6c( std::vector<Brace6c>& rows )
{
    std::sort( rows.begin(), rows.end(),
        []( const Brace6c& a, const Brace6c& b ) { return a.dir < b.dir; } );   // PLANT
}
inline bool searchRef6c( const std::vector<std::string>& sorted, std::string_view rel )
{
    return std::binary_search( sorted.begin(), sorted.end(), rel,
        []( const std::string_view& a, const std::string_view& b ) { return a < b; } );   // PLANT
}
struct Mixed6c { std::string_view name; std::string_view qual; std::size_t pos; };
inline void mixed6c( std::vector<Mixed6c>& v )
{
    std::sort( v.begin(), v.end(), []( const Mixed6c& a, const Mixed6c& b )   // PLANT
               { if( a.name != b.name ) return rw::sortutil::svLess( a.name, b.name );
                 return a.qual < b.qual; } );
}
inline void rangesLambda6c( std::vector<std::string_view>& v )
{
    std::ranges::sort( v, []( std::string_view a, std::string_view b ) { return a < b; } );   // PLANT
}
inline void helperLambda6c( std::vector<std::string_view>& v )
{
    rw::sortutil::sortUnique( v, []( std::string_view a, std::string_view b ) { return a < b; } );   // PLANT
}
EOF
    # none of these may be found: svLess, numeric and std::string members, a hand-rolled memcmp comparator,
    # constant evaluation, numeric tie-breaks beside svLess calls (both the ternary-chain and the
    # multi-statement shape), ranges::sort( range, svLess ), and the auto-parameter floor the arm discloses
    cat > "$TMP/svlctl/clean/clean.h" <<'EOF'
struct Row6cClean { std::string_view dir; std::size_t n = 0; };
struct Num6c { std::size_t count = 0; };
struct Str6c { std::string path; };
inline void viaSvLess( std::vector<Row6cClean>& rows )
{
    std::sort( rows.begin(), rows.end(), []( const Row6cClean& a, const Row6cClean& b ) noexcept
               { return rw::sortutil::svLess( a.dir, b.dir ); } );
}
inline void numeric( std::vector<Num6c>& v )
{
    std::sort( v.begin(), v.end(), []( const Num6c& a, const Num6c& b ) { return a.count < b.count; } );
}
inline void strings( std::vector<Str6c>& v )
{
    std::sort( v.begin(), v.end(), []( const Str6c& a, const Str6c& b ) { return a.path < b.path; } );
}
inline void handRolled( const std::vector<std::string>& v, std::string_view s )
{
    std::binary_search( v.begin(), v.end(), s, []( std::string_view a, std::string_view b ) noexcept
        { const std::size_t n = a.size() < b.size() ? a.size() : b.size();
          const int c = n == 0 ? 0 : std::memcmp( a.data(), b.data(), n );
          return c != 0 ? c < 0 : a.size() < b.size(); } );
}
constexpr std::string_view kT6c[] = { "a", "b" };
static_assert( std::is_sorted( std::begin( kT6c ), std::end( kT6c ),
               []( std::string_view a, std::string_view b ) { return a < b; } ) );
inline void autoFloor( std::vector<std::pair<std::string_view, int>>& v )
{
    std::sort( v.begin(), v.end(), []( const auto& a, const auto& b ) { return a.first < b.first; } );
}
struct Tie6c { std::string_view name; std::string_view qual; std::size_t pos = 0; };
inline void tieBreak6c( std::vector<Tie6c>& v )
{
    std::sort( v.begin(), v.end(), []( const Tie6c& a, const Tie6c& b )
               { return a.name != b.name ? rw::sortutil::svLess( a.name, b.name )
                                        : a.qual != b.qual ? rw::sortutil::svLess( a.qual, b.qual )
                                                           : a.pos < b.pos; } );
}
inline void stmtScoped6c( std::vector<Tie6c>& v )
{
    std::sort( v.begin(), v.end(), []( const Tie6c& a, const Tie6c& b )
               { if( !rw::sortutil::svLess( a.name, b.name ) && !rw::sortutil::svLess( b.name, a.name ) )
                     return a.pos < b.pos;
                 return rw::sortutil::svLess( a.name, b.name ); } );
}
inline void rangesSvLess6c( std::vector<std::string_view>& v )
{
    std::ranges::sort( v, rw::sortutil::svLess );
}
EOF
    wantPlanted="$( grep -n 'PLANT' "$TMP/svlctl/planted/planted.h" | cut -d: -f1 | sed 's#^#planted/planted.h:#' )"
    gotPlanted="$( python3 "$SVLC" "$TMP/svlctl/planted" | cut -d: -f1,2 )"
    if [ -n "$wantPlanted" ] && [ "$gotPlanted" = "$wantPlanted" ]; then
        ok "#6c control: the lambda pass finds exactly the $( printf '%s\n' "$wantPlanted" | wc -l | tr -d ' ' ) planted comparator lambdas (sv parameters by value and const reference, sv struct members incl. brace-initialized, lower_bound against an sv probe, a named comparator variable, a mixed svLess/raw comparator, ranges (range, comp), sortUnique (range, comp))"
    else
        no "#6c control: planted comparator lambdas not found exactly — want [$( printf '%s ' $wantPlanted )] got [$( printf '%s ' $gotPlanted )]"
    fi
    gotClean="$( python3 "$SVLC" "$TMP/svlctl/clean" )"; cleanRc=$?
    if [ "$cleanRc" -eq 0 ] && [ -z "$gotClean" ]; then
        ok "#6c control: svLess, numeric and std::string members, a memcmp comparator, constant evaluation, numeric tie-breaks beside svLess calls, ranges::sort( range, svLess ) and the auto-parameter floor are not findings"
    else
        no "#6c control: the clean input produced findings (rc=$cleanRc):"
        printf '%s\n' "$gotClean" | sed 's/^/        /'
    fi
    SVLAMB="$( python3 "$SVLC" "$ROOT/src" )"; svlRc=$?
    if [ "$svlRc" -ne 0 ]; then
        no "#6c the lambda pass itself failed on src/ (rc=$svlRc) — a crashed scan is not a clean one"
    elif [ -z "$SVLAMB" ]; then
        ok "#6c no ordered STL algorithm's comparator lambda orders string_view operands with operator<"
    else
        no "#6c comparator lambda orders string_view with operator< — aborts the Linux G1 leg (pass rw::sortutil::svLess):"
        printf '%s\n' "$SVLAMB" | sed 's/^/        /'
    fi
fi

# ── #7: no range-for reads through a temporary that only C++23 P2718 keeps alive ─────────────────────────────────────
# WHY THIS IS A PORTABILITY RULE. `for( x : makeRow().items() )` binds the loop's hidden range reference to what
# items() returns — a reference INTO the Row temporary — and before C++23 P2718 that temporary dies at the end of the
# range-init, so the loop walks freed storage. Clang ≥ 19 and GCC ≥ 15 implement P2718 and the loop is correct; GCC 14
# does not, and the same source SEGFAULTs there at every -O (tmp/lifetime-demo/c_rangefor.cpp, 2026-10-18). Source
# builds support GCC 13+ (CONTRIBUTING.md, compiler floor), so the code never relies on P2718: name the temporary first
# (`const Row row = makeRow(); for( x : row.items() )`). GCC 13/14's -Wdangling-reference (now -Werror in the GCC
# fence) refuses the reference-returning shape, but only on those compilers; this pass holds it on every host.
# The pass: every range-for's range expression (comments and literals blanked) → each `CALL( … )` or `T{ … }` whose
# result has a METHOD called on it or is subscripted, directly or through a data-member path (`makeRow().items()`,
# `makeBox().sub.items()`, `makeRow().cells[ 0 ]`) → the line-leading declarations of CALL in the scanned tree: a
# finding unless every one returns a reference or a pointer. Not findings: `for( x : f() )` (the by-value result IS the
# range and is extended in every standard), `for( x : local.items() )`, `for( x : makeRow().cells )` (a temporary's
# DATA member is extended in every standard), a method on a std::string_view / std::span temporary (it returns into
# the viewed data), and std's reference accessors (front/back/at/value/…) on a member chain. A callee the tree does
# not declare is a finding: unknown is not safe. Stated blind spots — zero findings means "none found", not "none
# exists": a by-value result whose ELEMENTS view a temporary argument (`for( v : split( std::string( s ) ) )`), `->`
# through a temporary smart pointer, and an overloaded callee whose overloads disagree are not modelled; nor is a
# reference-returning callee that takes the temporary as an ARGUMENT (`for( v : std::get<0>( makeTup() ) )`,
# `for( v : pass( makeVec() ) )`) — no method is called on the temporary, so the pass reads 0. That shape is held
# only by GCC 13/14's -Wdangling-reference, i.e. the gcc-14 CI leg under the GCC fence's -Werror=dangling-reference,
# not on every host (graph.h's `fqnAncestors( std::string( head ) )` is this shape, safe only because it returns
# into a memo keyed by a copy). The
# 2026-10-18 clang-query audit (cxxForRangeStmt whose range-init has a MaterializeTemporaryExpr under a call) found
# 20 such range-fors over the 10 owned TUs, all safe; this text pass finds 0 of the C shape in src/.
RFSCAN="$TMP/rangefor.py"
cat > "$RFSCAN" <<'PY'
import os
import re
import sys

# comments and literal contents are blanked (newlines kept, so offsets and lines stay true); a pp-number is matched
# first so a digit separator (1'000) is never read as a character literal
TOKEN = re.compile(r'//[^\n]*|/\*.*?\*/'
                   r'|(?<![\w])(?:u8|u|U|L)?R"(?P<delim>[^()\\\s]{0,16})\(.*?\)(?P=delim)"'
                   r"|(?<![\w])\d[\w']*"
                   r'|"(?:[^"\\\n]|\\.)*"'
                   r"|'(?:[^'\\\n]|\\.)*'", re.S)
FOR = re.compile(r'\bfor\s*\(')
# a method called on a VIEW temporary returns into the viewed data, never into the view object itself
VIEW_TYPES = {'string_view', 'span', 'basic_string_view'}
# standard accessors that return a reference (or pointer) into the object they are called on
REF_STD = {'front', 'back', 'at', 'top', 'value', 'first', 'second', 'get', 'data', 'operator'}
KEYWORDS = {'if', 'for', 'while', 'switch', 'return', 'sizeof', 'decltype', 'alignof', 'static_cast', 'const_cast',
            'reinterpret_cast', 'dynamic_cast', 'noexcept', 'requires', 'catch'}
NOT_DECL = {'return', 'else', 'new', 'delete', 'co_return', 'case', 'goto', 'throw', 'co_yield'}
SPEC = re.compile(r'^(?:(?:inline|static|constexpr|consteval|virtual|friend|explicit|extern|\[\[[^\]]*\]\])\s+)*')


def blank(text):
    """Replace comments and string/char literal CONTENTS with spaces, newlines and offsets preserved."""
    return TOKEN.sub(lambda m: m.group(0) if m.group(0)[0].isdigit() else re.sub(r'[^\n]', ' ', m.group(0)), text)


def close_of(text, i):
    """Index of the bracket that closes the one at i, or -1."""
    depth = 0
    for j in range(i, len(text)):
        c = text[j]
        if c in '([{':
            depth += 1
        elif c in ')]}':
            depth -= 1
            if depth == 0:
                return j
    return -1


def range_expr(text, open_index):
    """(start, end) of a range-for's range expression, or None for a classic for( ;; )."""
    end = close_of(text, open_index)
    if end < 0:
        return None
    depth = 0
    for j in range(open_index + 1, end):
        c = text[j]
        if c in '([{':
            depth += 1
        elif c in ')]}':
            depth -= 1
        elif depth == 0 and c == ';':
            return None
        elif depth == 0 and c == ':' and text[j - 1] != ':' and text[j + 1] != ':':
            return j + 1, end
    return None


def returns_of(texts, name, memo):
    """The return types the line-leading declarations of `name` spell (`RET NAME(` / `RET Cls::NAME(`), each ending
    in '&' or '*' when the declaration returns a reference or a pointer. [] when the tree declares none."""
    if name not in memo:
        pat = re.compile(r'(?m)^[ \t]*(?:template\s*<[^\n]*>\s*)?([^\n;{}()=,.]*?[\w>])([ \t*&]+)(?:\w+::)*'
                         + re.escape(name) + r'\s*\(')
        rets = []
        for text in texts:
            for m in pat.finditer(text):
                ret = SPEC.sub('', m.group(1).strip())
                words = ret.split()
                if not words or words[0] in NOT_DECL or words[-1] in KEYWORDS or words[-1] in NOT_DECL:
                    continue
                marks = m.group(2).replace(' ', '').replace('\t', '')
                rets.append(ret + marks)
        memo[name] = rets
    return memo[name]


def findings(expr, texts, memo):
    """Each `CALL( … ).method(` in a range expression whose CALL is not known to return a reference or a pointer:
    the temporary it returns dies at the end of the range-init before C++23 (P2718), while the loop reads through it."""
    out = []
    for m in re.finditer(r'[)}]', expr):
        # a data-member path may come first: `makeRow().sub.items()` reads through the temporary just the same,
        # and so does a subscript (`makeRow().cells[ 0 ]` calls vector::operator[] on it)
        mm = re.match(r'\s*(?:\.\s*\w+\s*)*(?:\.\s*(?:template\s+)?(\w+)\s*(?:<[^()]*>)?\s*\(|(\[))', expr[m.end():])
        if not mm:
            continue
        depth, k = 0, m.start()
        while k >= 0:
            c = expr[k]
            if c in ')]}':
                depth += 1
            elif c in '([{':
                depth -= 1
                if depth == 0:
                    break
            k -= 1
        if k < 0:
            continue
        head = expr[:k].rstrip()
        hm = re.search(r'(\w+)\s*(?:<[^()]*>)?$', head)
        if not hm:
            continue                     # a parenthesised expression or a lambda, not a call
        callee = hm.group(1)
        if callee in KEYWORDS or callee in VIEW_TYPES:
            continue
        rets = returns_of(texts, callee, memo)
        if rets and all(r.endswith(('&', '*')) for r in rets):
            continue
        member = head[:hm.start()].rstrip().endswith(('.', '->'))
        if not rets and member and callee in REF_STD:
            continue
        out.append((callee, mm.group(1) or 'operator[]', 'returns by value' if rets else 'has no declaration in the tree'))
    return out


def scan(paths, texts, memo):
    rows = []
    for path in paths:
        text = blank(open(path, encoding='utf-8', errors='replace').read())
        for m in FOR.finditer(text):
            r = range_expr(text, m.end() - 1)
            if not r:
                continue
            for callee, method, why in findings(text[r[0]:r[1]], texts, memo):
                line = text.count('\n', 0, m.start()) + 1
                rows.append('%s:%d: range-for over %s( … ).%s( … ) — %s %s' % (path, line, callee, method, callee, why))
    return rows


if __name__ == '__main__':
    files = []
    for root in sys.argv[1:]:
        for d, _, fs in os.walk(root):
            files += [os.path.join(d, f) for f in fs if f.endswith(('.h', '.hpp', '.inl', '.cpp'))]
    files.sort()
    texts = [blank(open(p, encoding='utf-8', errors='replace').read()) for p in files]
    for row in scan(files, texts, {}):
        print(row)
PY
mkdir -p "$TMP/rfctl/planted" "$TMP/rfctl/clean"
cat > "$TMP/rfctl/planted/planted.h" <<'CPP'
#include <string>
#include <vector>
struct Row { std::vector<std::string> cells; const std::vector<std::string>& items() const { return cells; } };
struct Box { Row sub; };
Row makeRow();
Box makeBox();
inline int planted()
{
    int n = 0;
    for( const std::string& c : makeRow().items() ) { n += int( c.size() ); }      // PLANT
    for( const std::string& c : makeBox().sub.items() ) { n += int( c.size() ); }  // PLANT
    for( const char ch : makeRow().cells[ 0 ] ) { n += ch; }                       // PLANT
    for( const std::string& c : unknownFactory( 1 ).items() ) { n += int( c.size() ); }  // PLANT
    return n;
}
CPP
cat > "$TMP/rfctl/clean/clean.h" <<'CPP'
#include <map>
#include <string>
#include <string_view>
#include <vector>
struct Row { std::vector<std::string> cells; const std::vector<std::string>& items() const { return cells; } };
Row makeRow();
Row& rowRef();
const Row* rowPtr();
std::vector<std::string> makeList();
inline int clean( const std::map<int, std::vector<int>>& m, std::string_view line )
{
    int n = 0;
    for( const std::string& c : makeList() ) { n += int( c.size() ); }              // by-value container: extended
    const Row localVar = makeRow();
    for( const std::string& c : localVar.items() ) { n += int( c.size() ); }        // a named local
    for( const std::string& c : makeRow().cells ) { n += int( c.size() ); }         // a temporary's data member: extended
    for( const std::string& c : rowRef().items() ) { n += int( c.size() ); }        // the callee returns a reference
    for( const std::string& c : rowPtr()->items() ) { n += int( c.size() ); }       // ... or a pointer
    for( const char ch : std::string_view( line ).substr( 1 ) ) { n += ch; }        // a view temporary
    for( const int v : m.find( 1 )->second ) { n += v; }                            // an iterator into a live map
    for( const std::string& c : localVar.cells.front().size() > 0 ? localVar.cells : makeList() ) { n += int( c.size() ); }
    // for( const std::string& c : makeRow().items() )   — a comment is not code
    const char* s = "for( const std::string& c : makeRow().items() )";             // nor is a literal
    for( int i = 0; i < 3; ++i ) { n += i + int( s[ 0 ] ); }                        // a classic for
    return n;
}
CPP
wantRf="$( grep -n 'PLANT' "$TMP/rfctl/planted/planted.h" | cut -d: -f1 | sed 's#^#planted.h:#' )"
gotRf="$( python3 "$RFSCAN" "$TMP/rfctl/planted" | sed 's#^.*/planted/##' | cut -d: -f1,2 )"
if [ -n "$wantRf" ] && [ "$wantRf" = "$gotRf" ]; then
    ok "#7 control: the range-for pass finds exactly the 4 planted shapes (method, member path + method, subscript, undeclared callee)"
else
    no "#7 control: planted range-for-over-temporary shapes not found exactly — want [$( printf '%s ' $wantRf )] got [$( printf '%s ' $gotRf )]"
fi
cleanRf="$( python3 "$RFSCAN" "$TMP/rfctl/clean" 2>&1 )"; cleanRfRc=$?
if [ "$cleanRfRc" -eq 0 ] && [ -z "$cleanRf" ]; then
    ok "#7 control: f(), local.items(), a temporary's data member, ref/ptr callees, views, iterators, comments, literals are not findings"
else
    no "#7 control: the near-miss input produced findings (rc=$cleanRfRc):"; printf '%s\n' "$cleanRf" | sed 's/^/        /'
fi
RFTREE="$( python3 "$RFSCAN" "$ROOT/src" 2>&1 )"; rfRc=$?
if [ "$rfRc" -ne 0 ]; then
    no "#7 the range-for pass itself failed on src/ (rc=$rfRc) — a crashed scan is not a clean one"; printf '%s\n' "$RFTREE" | tail -3 | sed 's/^/        /'
elif [ -z "$RFTREE" ]; then
    ok "#7 no range-for in src/ reads through a temporary only C++23 P2718 keeps alive (GCC 13/14 build safely)"
else
    no "#7 range-for over a temporary's member — SEGFAULTs on GCC 13/14 (name the temporary first):"
    printf '%s\n' "$RFTREE" | sed "s#^$ROOT/##; s/^/        /"
fi

# NOTE (what this gate can prove vs what only Linux CI can prove): this machine is Apple-Silicon macOS, so
# it can prove the FLAG-SELECTION LOGIC never emits an Apple-specific flag once RIPWIRE_IS_APPLE_SILICON is
# false (checks #2/#3 above, via the RIPWIRE_PRETEND_LINUX hook), and that the real CMakeLists.txt wires
# that logic in (checks #4/#5). It CANNOT prove that clang/gcc on actual Linux/x86-64 hardware accepts the
# resulting flags and links a working binary, nor exercise CMAKE_SYSTEM_PROCESSOR values this host never
# reports (e.g. "x86_64"). That end-to-end proof is exactly what .github/workflows/ci.yml's ubuntu-24.04
# matrix leg provides; this gate is the local, sub-second proxy that catches a regression before it ever
# reaches CI.

[ "$fail" = 0 ] && printf 'ALL PASS\n' || printf 'FAILURES ABOVE\n'
exit "$fail"
