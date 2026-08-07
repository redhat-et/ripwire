#!/usr/bin/env bash
# optremarkscheck.sh — the optimization-remarks toolchain: parser correctness, the build-tree contract,
# and the two optimization builds the remarks triage produced (RIPWIRE_LTO, RIPWIRE_PGO).
#
# Three things here can fail SILENTLY, and every one would fail in the direction that looks like good
# news — which is why each gets a real configure or a real parse rather than a comment:
#
#   1. THE TRIAGE PARSER. scripts/optremarks.py hand-reads clang's opt-record YAML (no PyYAML — this
#      repo ships zero runtime dependencies and the records reach ~800 MB, which a general parser is
#      far too slow for). If a clang release nudges the format, the parser does not crash: it returns
#      FEWER remarks, and an empty triage reads as "nothing to fix". That is the green-while-inert
#      failure CONTRIBUTING.md §2 names. So the gate asserts EXACT counts against a committed fixture
#      that contains the two shapes a naive line reader gets wrong — a DebugLoc flow mapping WRAPPED
#      onto a continuation line, and an Args-nested DebugLoc whose `Line:` key sits at the same
#      indentation a record-level key would.
#   2. THE BUILD-TREE CONTRACT. -DRIPWIRE_OPT_REMARKS=ON in build/ would leave ~1 GB of opt-record
#      beside the binary every gate and every bench number in this repo is measured against. CMakeLists
#      refuses that by name; this gate runs the real configure and asserts the refusal, plus the
#      matching acceptance in a differently-named tree (without which the refusal could be a blanket
#      failure and still "pass").
#   3. RIPWIRE_PGO=use WITH NO PROFILE. -fprofile-use pointed at a file that is not there compiles
#      clean and produces an ordinary binary; the next person benchmarks it and reports that PGO
#      bought nothing. CMakeLists refuses at configure time, and that refusal is gated below.
#
# Usage:  bash test/optremarkscheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
FIX="$ROOT/test/optremarksfix"
TRIAGE="$ROOT/scripts/optremarks.py"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

command -v python3 >/dev/null || { echo "python3 required"; exit 2; }
command -v cmake   >/dev/null || { echo "cmake required"; exit 2; }
[ -f "$TRIAGE" ] || { echo "missing $TRIAGE"; exit 2; }
[ -f "$FIX/sample.opt.yaml" ] || { echo "missing $FIX/sample.opt.yaml"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
echo "optremarkscheck: ROOT=$ROOT"

# ── presence guards: the fixture must actually CONTAIN the shapes the assertions below are about ────
grep -q "^ *Line: 459, Column: 98 }" "$FIX/sample.opt.yaml" \
    && ok "fixture carries a WRAPPED DebugLoc (the continuation-line shape)" \
    || no "fixture lost its wrapped DebugLoc — the wrap assertions below would prove nothing"
grep -q "^ *DebugLoc: *{ File: 'src/ingest.cpp', Line: 4931" "$FIX/sample.opt.yaml" \
    && ok "fixture carries an Args-NESTED DebugLoc at a different line than its record" \
    || no "fixture lost its nested Args DebugLoc — the mis-attribution assertion would prove nothing"
grep -q "third_party/deps/tree-sitter" "$FIX/sample.opt.yaml" \
    && ok "fixture carries a third_party record for the drop assertion" \
    || no "fixture lost its third_party record"

# ── (1) the parser: exact counts, exact site, exact filtering ───────────────────────────────────────
SUM="$TMP/summary.txt"
python3 "$TRIAGE" --build-dir "$FIX" --top 20 >"$SUM" 2>"$TMP/summary.err" || no "triage exited non-zero"
grep -q '6 remarks total, 2 in first-party sources' "$SUM" \
    && ok "parser reads 6 records and keeps exactly the 2 first-party ones" \
    || { no "parser count drifted — clang's opt-record shape may have changed"; sed -n '1,3p' "$SUM"; }

SITES="$TMP/sites.txt"
python3 "$TRIAGE" --build-dir "$FIX" --sites 20 --width 200 >"$SITES" 2>&1
grep -q '^src/ingest.cpp:4984 ' "$SITES" \
    && ok "record-level DebugLoc wins over the Args-nested one (4984, not 4931)" \
    || no "site line mis-attributed — the nested Args DebugLoc leaked into the record"
grep -q '^src/ingest.cpp:4931 ' "$SITES" && no "parser reported the NESTED DebugLoc line as a site" \
    || ok "the nested Args DebugLoc produced no phantom site"
grep -q 'ts_node_start_byte will not be inlined into' "$SITES" \
    && ok "Args are reassembled into clang's own message text" \
    || no "message reassembly broke (quote unescaping or Args ordering)"
grep -q 'third_party' "$SITES" && no "third_party remark survived the default filter" \
    || ok "third_party/ and toolchain-header remarks are dropped by default"
grep -q '^:0 ' "$SITES" && no "a remark with no DebugLoc was reported as a site" \
    || ok "a remark with no DebugLoc is dropped (it cannot be triaged to a site)"

python3 "$TRIAGE" --build-dir "$FIX" --keep-foreign --sites 20 >"$TMP/foreign.txt" 2>&1
[ "$( grep -c 'distinct sites shown of 6 matching' "$TMP/foreign.txt" )" = "1" ] \
    && ok "--keep-foreign restores all 6 records (the filter is a filter, not a parse failure)" \
    || no "--keep-foreign did not return the full record set"

python3 "$TRIAGE" --build-dir "$FIX" --hot --sites 20 >"$TMP/hot.txt" 2>&1
grep -q 'src/ingest.cpp:4984' "$TMP/hot.txt" && grep -q 'src/lexical.h:517' "$TMP/hot.txt" \
    && ok "--hot keeps the hot-set files it names" \
    || no "--hot dropped a file listed in HOT_FILES"

python3 "$TRIAGE" --build-dir "$TMP/no-such-tree" >"$TMP/empty.out" 2>"$TMP/empty.err"; emptyRc=$?
[ "$emptyRc" -eq 2 ] && grep -q 'configure with -DRIPWIRE_OPT_REMARKS=ON' "$TMP/empty.err" \
    && ok "an empty tree exits 2 with instructions, never 0 with an empty triage" \
    || no "a missing/unbuilt tree did not fail loudly (rc=$emptyRc)"

# ── (2) the build-tree contract: refused in build/ and asan/, accepted elsewhere ────────────────────
grep -q '^option(RIPWIRE_OPT_REMARKS .* OFF)$' "$ROOT/CMakeLists.txt" \
    && ok "RIPWIRE_OPT_REMARKS is a declared option() defaulting OFF (so --flags can see it)" \
    || no "RIPWIRE_OPT_REMARKS is not a declared option() defaulting OFF"
# LTO's default TRACKS THE BUILD TYPE — off for the plain dev configure (fast edit loop), on for
# Release (the binary someone actually uses). These arms assert the BEHAVIOUR of four configures
# rather than the source text of one line: grepping for `option(... ON)` would have passed on a
# CMakeLists that declared the option and then ignored it, and it breaks on any refactor that keeps
# the contract. Four cases, because a default nobody can override is not a default.
cmake -S "$ROOT" -B "$TMP/build_devdefault" >"$TMP/devdefault.log" 2>&1; devRc=$?
[ "$devRc" -eq 0 ] && grep -q 'RIPWIRE_LTO: OFF' "$TMP/devdefault.log" \
    && ok "plain configure defaults LTO OFF (the dev tree keeps the 34s link, not the 89s one)" \
    || { no "plain configure did not default RIPWIRE_LTO OFF (rc=$devRc)"; tail -5 "$TMP/devdefault.log"; }
cmake -S "$ROOT" -B "$TMP/build_rel" -DCMAKE_BUILD_TYPE=Release >"$TMP/rel.log" 2>&1; relRc=$?
[ "$relRc" -eq 0 ] && grep -q 'RIPWIRE_LTO: ON' "$TMP/rel.log" \
    && ok "-DCMAKE_BUILD_TYPE=Release implies LTO ON (the shipped build is the fast one)" \
    || { no "Release did not imply RIPWIRE_LTO ON (rc=$relRc)"; tail -5 "$TMP/rel.log"; }
cmake -S "$ROOT" -B "$TMP/build_devlto" -DRIPWIRE_LTO=ON >"$TMP/devlto.log" 2>&1; devLtoRc=$?
[ "$devLtoRc" -eq 0 ] && grep -q 'RIPWIRE_LTO: ON' "$TMP/devlto.log" \
    && ok "-DRIPWIRE_LTO=ON overrides the dev default (LTO WITH VERIFY live is buildable — the leg that catches an LTO miscompile)" \
    || { no "-DRIPWIRE_LTO=ON did not override the dev default (rc=$devLtoRc)"; tail -5 "$TMP/devlto.log"; }
cmake -S "$ROOT" -B "$TMP/build_nolto" -DCMAKE_BUILD_TYPE=Release -DRIPWIRE_LTO=OFF >"$TMP/nolto.log" 2>&1; noLtoRc=$?
[ "$noLtoRc" -eq 0 ] && ! grep -q 'RIPWIRE_LTO: ON' "$TMP/nolto.log" \
    && ok "-DRIPWIRE_LTO=OFF overrides Release too (the escape hatch works in both directions)" \
    || { no "-DRIPWIRE_LTO=OFF did not override Release (rc=$noLtoRc)"; tail -5 "$TMP/nolto.log"; }
grep -q 'RIPWIRE_OPT_REMARKS requires Clang' "$ROOT/CMakeLists.txt" \
    && ok "a non-Clang configure is refused rather than silently producing no remarks" \
    || no "the non-Clang guard is gone (GCC would configure clean and emit nothing)"
for flag in -gline-tables-only -fsave-optimization-record; do
    grep -q -- "$flag" "$ROOT/CMakeLists.txt" && ok "remarks build passes $flag" || no "remarks build lost $flag"
done

# ── WHICH FRONT END? Both RIPWIRE_OPT_REMARKS and RIPWIRE_PGO are Clang-only by construction (-Rpass=/
# -fsave-optimization-record; .profdata/llvm-profdata), and CMakeLists FATAL_ERRORs on anything else —
# deliberately, since a silent no-op there hands back an empty triage or an un-optimized "PGO" binary.
# Every arm below that expects a SUCCESSFUL configure therefore asserts a Clang-only outcome. CI's
# release job runs ubuntu-24.04 on GCC on purpose ("a second front end over the same tree", ci.yml), so
# on that leg those arms were asserting the impossible: run 31145553507 red on both ubuntu legs, green on
# both macOS ones, for no defect at all.
#
# Read the front end off the configure already done above rather than guessing from $CXX — CMake's own
# choice is the one CMakeLists sees. Then: if it is not Clang, PIN clang for the Clang-only arms when the
# box has one (the same remedy ci.yml's asan job applies for G1's Clang-only sanitizers), and if it does
# not, SKIP those arms with the reason named — but first assert the refusal itself, which is the honest
# behaviour a GCC box is owed and which nothing tested until now.
CXXID="$( sed -nE 's/^set\(CMAKE_CXX_COMPILER_ID "([^"]*)".*/\1/p' "$TMP"/build_devdefault/CMakeFiles/*/CMakeCXXCompiler.cmake 2>/dev/null | head -1 )"
CLANGONLY_SKIP=""
CLANGPIN=""
if printf '%s' "$CXXID" | grep -q 'Clang'; then
    ok "front end: the default configure is $CXXID — the Clang-only arms below run natively"
else
    # The refusal is the contract on this front end. Gate it, on a tree name that is NOT build/, so a
    # pass cannot be the build/-name refusal firing first and masking a missing compiler guard.
    cmake -S "$ROOT" -B "$TMP/build_gccrefuse" -DRIPWIRE_OPT_REMARKS=ON >"$TMP/gccrefuse.log" 2>&1; gccRefuseRc=$?
    [ "$gccRefuseRc" -ne 0 ] && grep -q 'RIPWIRE_OPT_REMARKS requires Clang' "$TMP/gccrefuse.log" \
        && ok "front end: $CXXID is REFUSED by name for remarks (never a silent empty triage)" \
        || { no "front end: $CXXID configured remarks clean (rc=$gccRefuseRc) — an empty opt-record would read as 'nothing to fix'"; tail -5 "$TMP/gccrefuse.log"; }
    cmake -S "$ROOT" -B "$TMP/build_gccpgorefuse" -DRIPWIRE_PGO=generate >"$TMP/gccpgorefuse.log" 2>&1; gccPgoRc=$?
    [ "$gccPgoRc" -ne 0 ] && grep -q 'RIPWIRE_PGO requires Clang' "$TMP/gccpgorefuse.log" \
        && ok "front end: $CXXID is REFUSED by name for PGO (GCC's .gcda flavour would half-work and mislead)" \
        || { no "front end: $CXXID configured PGO clean (rc=$gccPgoRc) — the .profdata paths would half-work"; tail -5 "$TMP/gccpgorefuse.log"; }
    if command -v clang++ >/dev/null 2>&1 && command -v clang >/dev/null 2>&1; then
        CLANGPIN="1"
        ok "front end: default is $CXXID, so the Clang-only arms below are pinned to the box's clang++ (coverage kept, not skipped)"
    else
        CLANGONLY_SKIP="the default front end is $CXXID and no clang++ is on PATH; -Rpass=/-fsave-optimization-record and .profdata are Clang-only spellings, so a successful configure is not expressible here. CI's macos-14 legs (AppleClang) run these arms."
    fi
fi
# cmake_cc <args...> — configure with the Clang-only arms' toolchain, whatever that turned out to be.
cmake_cc()
{
    if [ -n "$CLANGPIN" ]; then
        CC=clang CXX=clang++ cmake "$@"
    else
        cmake "$@"
    fi
}
skip(){ printf '  SKIP  %s\n' "$*"; }

# The build/-name refusal is ALSO Clang-only to observe: CMakeLists checks the compiler first, so on a
# GCC-only box this configure dies on "requires Clang" and never reaches the name check — a pass here
# would be the wrong refusal firing.
mkdir -p "$TMP/build"
if [ -n "$CLANGONLY_SKIP" ]; then
    skip "-DRIPWIRE_OPT_REMARKS=ON refused in a tree named build/ — $CLANGONLY_SKIP"
else
    cmake_cc -S "$ROOT" -B "$TMP/build" -DRIPWIRE_OPT_REMARKS=ON >"$TMP/refuse.log" 2>&1; refuseRc=$?
    [ "$refuseRc" -ne 0 ] && grep -q 'must not be enabled in build/' "$TMP/refuse.log" \
        && ok "-DRIPWIRE_OPT_REMARKS=ON is refused in a tree named build/" \
        || { no "a tree named build/ accepted the remarks flags (rc=$refuseRc)"; tail -5 "$TMP/refuse.log"; }
fi

if [ -n "$CLANGONLY_SKIP" ]; then
    skip "-DRIPWIRE_OPT_REMARKS=ON accepted in a separately named tree — $CLANGONLY_SKIP"
else
    cmake_cc -S "$ROOT" -B "$TMP/build_remarks" -DRIPWIRE_OPT_REMARKS=ON >"$TMP/accept.log" 2>&1; acceptRc=$?
    [ "$acceptRc" -eq 0 ] && grep -q 'RIPWIRE_OPT_REMARKS: ON' "$TMP/accept.log" \
        && ok "-DRIPWIRE_OPT_REMARKS=ON configures in a separately named tree (refusal is by NAME, not blanket)" \
        || { no "the remarks configure failed everywhere (rc=$acceptRc) — the refusal above proves nothing"; tail -5 "$TMP/accept.log"; }
fi

grep -q 'CMAKE_BUILD_TYPE' "$ROOT/scripts/optremarks.sh" \
    && no "scripts/optremarks.sh mentions CMAKE_BUILD_TYPE — a Release remarks tree blinds the degrade-path gates" \
    || ok "the remarks driver passes no build type (NDEBUG would compile DEGRADED_PATH_ALERT out)"

# ── (3) the two optimization builds the remarks pass produced: same build-tree contract, fail-loud ──
# RIPWIRE_PGO's failure mode is the sharpest in this file: -fprofile-use pointed at a missing profile
# compiles CLEAN and yields an ordinary binary, which the next person benchmarks as "PGO bought
# nothing". The configure-time existence check is the only thing standing between that and a published
# number, so it is gated here rather than trusted.
# The build/-name refusal is checked FIRST in CMakeLists only after the compiler guard, so on a non-Clang
# front end this arm would pass on the wrong message. cmake_cc keeps it reading the refusal it names.
cmake_cc -S "$ROOT" -B "$TMP/build" -DRIPWIRE_PGO=generate >"$TMP/pgorefuse.log" 2>&1; pgoRefuseRc=$?
[ "$pgoRefuseRc" -ne 0 ] && grep -q 'RIPWIRE_PGO must not be enabled in build/' "$TMP/pgorefuse.log" \
    && ok "-DRIPWIRE_PGO is refused in a tree named build/ (a PGO'd build/ripwire moves every recorded number)" \
    || { no "a tree named build/ accepted PGO (rc=$pgoRefuseRc)"; tail -5 "$TMP/pgorefuse.log"; }

if [ -n "$CLANGONLY_SKIP" ]; then
    skip "the three RIPWIRE_PGO phase arms (missing .profdata / bogus phase / generate+LTO) — $CLANGONLY_SKIP"
else
    cmake_cc -S "$ROOT" -B "$TMP/build_pgo" -DRIPWIRE_PGO=use -DRIPWIRE_PGO_PROFILE="$TMP/no-such.profdata" >"$TMP/pgomissing.log" 2>&1; pgoMissRc=$?
    [ "$pgoMissRc" -ne 0 ] && grep -q 'RIPWIRE_PGO=use needs' "$TMP/pgomissing.log" \
        && ok "RIPWIRE_PGO=use with a missing .profdata FAILS the configure (never a silent no-op binary)" \
        || { no "a missing profile configured clean — PGO would silently do nothing (rc=$pgoMissRc)"; tail -5 "$TMP/pgomissing.log"; }

    cmake_cc -S "$ROOT" -B "$TMP/build_pgo2" -DRIPWIRE_PGO=bogus >"$TMP/pgobogus.log" 2>&1; pgoBogusRc=$?
    [ "$pgoBogusRc" -ne 0 ] && grep -q "must be 'generate' or 'use'" "$TMP/pgobogus.log" \
        && ok "an unrecognised RIPWIRE_PGO phase is refused, not ignored" \
        || no "RIPWIRE_PGO accepted a phase name it does not implement (rc=$pgoBogusRc)"

    cmake_cc -S "$ROOT" -B "$TMP/build_pgogen" -DRIPWIRE_LTO=ON -DRIPWIRE_PGO=generate >"$TMP/pgogen.log" 2>&1; pgoGenRc=$?
    [ "$pgoGenRc" -eq 0 ] && grep -q 'RIPWIRE_PGO: generate' "$TMP/pgogen.log" && grep -q 'RIPWIRE_LTO: ON' "$TMP/pgogen.log" \
        && ok "-DRIPWIRE_PGO=generate configures alongside LTO in a separately named tree (refusals are by NAME)" \
        || { no "the instrumented configure failed everywhere (rc=$pgoGenRc) — the refusals above prove nothing"; tail -5 "$TMP/pgogen.log"; }
fi

grep -q 'raw.*-gt 0\|-gt 0 .*raw' "$ROOT/scripts/pgobuild.sh" \
    && ok "pgobuild.sh fails when training produced zero .profraw (an empty merge is a silent no-op)" \
    || no "pgobuild.sh does not check that training actually wrote counters"
# Asked of git itself, not of .gitignore's text: the tree names are covered by a `build*/` GLOB, and a
# grep for the literal names would fail on a correctly-ignoring repo.
if command -v git >/dev/null && git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    ignored=1
    for d in build_remarks build_pgo build_pgogen build_lto; do
        git -C "$ROOT" check-ignore -q "$d/x" || ignored=0
    done
    [ "$ignored" -eq 1 ] \
        && ok "every generated build tree is gitignored (a ~1 GB opt-record must not be committable by accident)" \
        || no "one of build_remarks/ build_pgo/ build_pgogen/ build_lto/ is NOT gitignored"
else
    echo "  SKIP  gitignore coverage (not a git checkout)"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "FAILURES ABOVE"; exit 1; }
