#!/usr/bin/env bash
# g1configcheck.sh — millisecond-scale structural gate for sanitizer/fuzzer build contracts.

set -u

ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
CMAKE="$ROOT/CMakeLists.txt"
HARNESS="$ROOT/test/fuzz/fuzz_ingest.cpp"
RUNNER="$ROOT/test/fuzz/run.sh"
fail=0

ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

for mode in ASAN TSAN FUZZ; do
    if grep -q "option(RIPWIRE_$mode" "$CMAKE"; then ok "RIPWIRE_$mode is explicitly declared"; else no "RIPWIRE_$mode option missing"; fi
done
if grep -q 'are mutually exclusive' "$CMAKE"; then ok "sanitizer modes are mutually exclusive"; else no "mutual-exclusion gate missing"; fi

# The G1 set is no longer one literal flag string: `integer` is a Clang-only UBSan group and GCC rejects
# the whole -fsanitize= option, so CMakeLists.txt declares the five checks as a LIST, filters it by
# compiler id, and joins it. Assert all four parts — the complete set, that the -fsanitize= string is
# built from that same list (not a second literal that could drift), that the ONLY subtraction is
# `integer` and only under GNU, and that the Clang-only exemptions ride the same finding.
grep -q 'set(RIPWIRE_G1_SANITIZER_CHECKS address undefined integer float-divide-by-zero float-cast-overflow)' "$CMAKE" \
    && ok "complete G1 sanitizer set declared" || no "complete G1 sanitizer set missing"
grep -q 'list(JOIN RIPWIRE_G1_SANITIZER_CHECKS "," ' "$CMAKE" \
    && grep -q 'set(RIPWIRE_G1_SANITIZERS "-fsanitize=${_ripwire_g1_check_list}")' "$CMAKE" \
    && ok "the -fsanitize= string is joined from that one list (no second literal to drift)" \
    || no "G1 -fsanitize= string is not derived from RIPWIRE_G1_SANITIZER_CHECKS"
removedCheckCount="$( grep -c 'list(REMOVE_ITEM RIPWIRE_G1_SANITIZER_CHECKS' "$CMAKE" )"
grep -q 'list(REMOVE_ITEM RIPWIRE_G1_SANITIZER_CHECKS integer)' "$CMAKE" \
    && [ "$removedCheckCount" -eq 1 ] \
    && grep -q 'if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")' "$CMAKE" \
    && ok "the ONLY G1 check dropped, and only under GCC, is the Clang-only 'integer' group" \
    || no "G1 check subtraction is not exactly {integer, under GNU} ($removedCheckCount REMOVE_ITEM line(s))"
grep -q 'if(RIPWIRE_HAS_CLANG_INTEGER_SANITIZER)' "$CMAKE" \
    && ok "the Clang-only -fno-sanitize= exemptions and ignorelists ride the same finding" \
    || no "Clang-only exemptions/ignorelists are not gated (gcc would reject them one level down)"
grep -q -- '-fno-sanitize-recover=all -fno-omit-frame-pointer -O2 -g' "$CMAKE" \
    && ok "G1 is fail-fast, framed, and O2" || no "G1 fail-fast/O2 contract missing"
grep -q 'tree-sitter.*${RIPWIRE_GRAMMAR_TARGETS}' "$CMAKE" \
    && ok "tree-sitter core and grammar target list are instrumented" || no "dependency instrumentation list missing"
unsignedTruncationSectionCount="$( grep -c '\[implicit-unsigned-integer-truncation\]' "$CMAKE" )"
balanceCount="$( grep -c 'fun:ts_parser__balance_subtree' "$CMAKE" )"
functionSectionCount="$( grep -c '\[function\]' "$CMAKE" )"
scannerCreateCount="$( grep -c 'fun:ts_parser__external_scanner_create' "$CMAKE" )"
unsignedDisableCount="$( grep -c -- '-fno-sanitize=unsigned-integer-overflow' "$CMAKE" )"
signedTruncationDisableCount="$( grep -c -- '-fno-sanitize=implicit-signed-integer-truncation' "$CMAKE" )"
signChangeDisableCount="$( grep -c -- '-fno-sanitize=implicit-integer-sign-change' "$CMAKE" )"
swiftSignSectionCount="$( grep -c '\[implicit-integer-sign-change\]' "$CMAKE" )"
swiftWhitespaceCount="$( grep -c 'fun:eat_whitespace' "$CMAKE" )"
bashScanCount="$( grep -c 'fun:scan' "$CMAKE" )"
# M2-era note: `[unsigned-integer-overflow]` now opens TWO ignorelists — bash's scanner (fun:scan) and
# the libstdc++ one — so the SECTION count is 2, and every entry underneath is audited separately below
# so that none can be added or dropped without moving this gate.
# …counted by OCCURRENCE, not by line: an ignorelist here is one CMake string holding several `\n`-joined
# entries, so `grep -c` (which counts matching LINES) reads a smuggled second entry on an existing line as
# zero new entries. Caught by this gate's own mutation control — the first version of this arm passed a
# planted `src:*/bits/basic_string.tcc`.
occurrences(){ grep -o -- "$1" "$CMAKE" | wc -l | tr -d ' '; }
scannerUnsignedSectionCount="$( occurrences '\[unsigned-integer-overflow\]' )"
# M1/N1: the file-scoped rules in the whole build — EXACTLY THREE, all libstdc++ headers carrying the same
# deliberate-wrap idiom, all under the one `[unsigned-integer-overflow]` section. Those loops wrap past zero
# by design (`for (++__size; __size-- > 0;)`, and `_S_compare`'s `__n1 - __n2` in size_type), which G1's
# Clang-only `integer` group flags and -fno-sanitize-recover=all turns into a hard abort. The first real
# Linux G1 run died at string_view.tcc:124 from rw::lowerExtensionOf (M1); the re-smoke then died at
# basic_string.h:490 (_S_compare, reached from a plain std::string operator<= in a sort comparator) and
# basic_string.tcc:689 (the find/rfind twin) — N1. libc++ has no such wrap, so macOS never saw any of them.
#
# This arm used to ban `src:` outright, because a file-scoped rule is the easy way to smuggle a whole
# directory out of the sanitizer. The ban is kept in spirit and tightened in practice: every `src:` entry is
# enumerated here by exact path and count, and an entry added, dropped or re-pathed reds this gate — which is
# the whole point of an audited list. The audited set, 2026-09-08 (the std::print floor):
#   the 3 libstdc++ STRING seams above, under [unsigned-integer-overflow] — unchanged; plus
#   the 2 libstdc++ FORMATTING seams, <format> and <print> (spelled c\+\+: LLVM before 18 reads the list as
#   a regex), each under FOUR checks — [unsigned-integer-overflow], [implicit-integer-sign-change],
#   [implicit-signed-integer-truncation], [implicit-unsigned-integer-truncation] — 8 rules. The first
#   std::print CI run died in format:3903 (libstdc++ 14's formatting scanner spelling npos as int -1 ->
#   size_t) under [implicit-integer-sign-change]; the emitter (src/infra/emit.h) routes every formatted
#   write through these two headers, so the exemption is what keeps the complete G1 stack running.
# Section counts move with it: [implicit-integer-sign-change] and [implicit-unsigned-integer-truncation]
# each open a second list (Swift/tree-sitter before, libstdc++ now); [implicit-signed-integer-truncation]
# opens its first. 3 + 8 = 11 `src:` occurrences, no more.
stringViewRuleCount="$( occurrences 'src:\*/bits/string_view\.tcc' )"
basicStringHeaderRuleCount="$( occurrences 'src:\*/bits/basic_string\.h' )"
basicStringTccRuleCount="$( occurrences 'src:\*/bits/basic_string\.tcc' )"
libstdcxxHeaderRuleCount="$(( stringViewRuleCount + basicStringHeaderRuleCount + basicStringTccRuleCount ))"
formatRuleCount="$( occurrences 'src:\*/include/c\\\\+\\\\+/\*/format' )"
printRuleCount="$( occurrences 'src:\*/include/c\\\\+\\\\+/\*/print' )"
formatPrintRuleCount="$(( formatRuleCount + printRuleCount ))"
signedTruncationSectionCount="$( occurrences '\[implicit-signed-integer-truncation\]' )"
srcScopedRuleCount="$( occurrences 'src:' )"
if [ "$unsignedTruncationSectionCount" = 2 ] && [ "$balanceCount" = 1 ] \
    && [ "$functionSectionCount" = 1 ] && [ "$scannerCreateCount" = 1 ] \
    && [ "$unsignedDisableCount" = 2 ] && [ "$signedTruncationDisableCount" = 2 ] \
    && [ "$signChangeDisableCount" = 2 ] \
    && [ "$swiftSignSectionCount" = 2 ] && [ "$swiftWhitespaceCount" = 1 ] \
    && [ "$scannerUnsignedSectionCount" = 2 ] && [ "$bashScanCount" = 1 ] \
    && [ "$signedTruncationSectionCount" = 1 ] \
    && [ "$stringViewRuleCount" = 1 ] && [ "$basicStringHeaderRuleCount" = 1 ] && [ "$basicStringTccRuleCount" = 1 ] \
    && [ "$libstdcxxHeaderRuleCount" = 3 ] \
    && [ "$formatRuleCount" = 4 ] && [ "$printRuleCount" = 4 ] && [ "$formatPrintRuleCount" = 8 ] \
    && [ "$srcScopedRuleCount" = 11 ] \
    && ! grep -Eq 'fun:\*' "$CMAKE"; then
    ok "dependency policy is limited to audited Tree-sitter core, Swift/bash scanner, the 3 libstdc++ string seams and the 2 formatting seams (<format>/<print>, 4 checks each)"
else
    no "sanitizer exemption policy differs from the audited list (sections uint=$scannerUnsignedSectionCount, src:-scoped=$srcScopedRuleCount of which string_view.tcc=$stringViewRuleCount basic_string.h=$basicStringHeaderRuleCount basic_string.tcc=$basicStringTccRuleCount format=$formatRuleCount print=$printRuleCount; sections sign-change=$swiftSignSectionCount signed-trunc=$signedTruncationSectionCount unsigned-trunc=$unsignedTruncationSectionCount)"
fi
# MUTATION CONTROL (live, not the historical note above): plant a twelfth `src:` entry in a COPY of the file
# and re-run the identical occurrence extraction over it — the audited count must move. A control over an
# unmutated copy would pass and prove nothing, so the copy is asserted to differ first.
mutCmake="$( mktemp -t g1config_mut.XXXXXX )"
awk '{ print } /src:\*\/bits\/basic_string\.tcc/ { print "  \"src:*/bits/planted_seam.h\\n\"" }' "$CMAKE" > "$mutCmake"
if cmp -s "$CMAKE" "$mutCmake"; then
    no "audited-list mutation control did not take — the planted src: entry is absent from the copy"
elif [ "$( grep -o -- 'src:' "$mutCmake" | wc -l | tr -d ' ' )" = "$srcScopedRuleCount" ]; then
    no "audited-list mutation control is inert — a planted src: entry left the occurrence count at $srcScopedRuleCount"
else
    ok "audited-list mutation control — a planted src: entry moves the count ($srcScopedRuleCount -> $( grep -o -- 'src:' "$mutCmake" | wc -l | tr -d ' ' ))"
fi
rm -f "$mutCmake"

grep -q 'set(_ripwire_asan_options "detect_leaks=0' "$CMAKE" \
    && grep -q 'set(_ripwire_asan_options "detect_leaks=1' "$CMAKE" \
    && grep -q 'LSAN_OPTIONS=suppressions=' "$CMAKE" \
    && ok "Darwin limitation and non-Darwin leak gate are explicit" || no "platform leak runtime policy missing"
if grep -q -- '-fsanitize=leak' "$CMAKE"; then no "unsupported standalone Darwin leak sanitizer declared"; else ok "no unsupported standalone leak flag"; fi

grep -q 'check_cxx_source_compiles' "$CMAKE" && grep -q 'LLVMFuzzerTestOneInput' "$CMAKE" \
    && grep -q 'same upstream LLVM installation' "$CMAKE" \
    && ok "libFuzzer availability uses a real link probe with remediation" || no "libFuzzer link probe/remediation missing"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/build/.cmake/api/v1/query"
touch "$TMP/build/.cmake/api/v1/query/codemodel-v2"
if cmake -S "$ROOT" -B "$TMP/build" -DRIPWIRE_FUZZ=ON >"$TMP/configure.log" 2>&1; then
    if python3 - "$TMP/build/.cmake/api/v1/reply" <<'PY'
import json, pathlib, sys
reply = pathlib.Path(sys.argv[1])
index = json.loads(next(reply.glob('index-*.json')).read_text())
model = json.loads((reply / index['reply']['codemodel-v2']['jsonFile']).read_text())
expected = {'ripwire_fuzz_' + name for name in
            'cpp python go rust typescript tsx swift objc javascript bash java ruby json toml yaml csharp c php elixir lua dart kotlin'.split()}
assert model['configurations']
for config in model['configurations']:
    targets = [json.loads((reply / t['jsonFile']).read_text()) for t in config['targets']]
    actual = {t['name'] for t in targets if t['type'] == 'EXECUTABLE' and t['name'].startswith('ripwire_fuzz_')}
    assert actual == expected, (actual, expected)
PY
    then
        ok "configured model contains all 22 grammar fuzz executables"
    else
        no "configured grammar fuzz executable set differs"
    fi
elif grep -Eq 'RIPWIRE_FUZZ requires (Clang|a Clang toolchain)' "$TMP/configure.log"; then
    printf '  SKIP  configured fuzz targets require a Clang toolchain with libFuzzer\n'
else
    cat "$TMP/configure.log"
    no "fuzzer CMake configuration failed"
fi
if grep -q 'EXCLUDE_FROM_ALL' "$CMAKE"; then ok "fuzz targets excluded from normal builds"; else no "fuzz targets can enter normal builds"; fi

grep -q 'LLVMFuzzerTestOneInput' "$HARNESS" && grep -q 'ts_parser_parse_string' "$HARNESS" \
    && grep -q 'ts_node_child(' "$HARNESS" && grep -q 'ts_node_named_child(' "$HARNESS" \
    && ok "shared harness parses arbitrary bytes and iteratively walks ASTs" || no "shared AST fuzz harness incomplete"
grep -q 'max_total_time=' "$RUNNER" && grep -q 'max_len=65536' "$RUNNER" && grep -q 'RIPWIRE_FUZZ_JOBS:-4' "$RUNNER" \
    && grep -q 'DETECT_LEAKS=0' "$RUNNER" && grep -q 'DETECT_LEAKS=1' "$RUNNER" \
    && ok "fuzz runner is time-, input-, and concurrency-bounded" || no "bounded fuzz runner contract missing"

seedCount="$( find "$ROOT/test/fuzz/seeds" -mindepth 2 -maxdepth 2 -name valid | wc -l | tr -d ' ' )"
if [ "$seedCount" = 22 ]; then ok "all 22 grammars have valid seeds"; else no "expected 22 grammar seeds, found $seedCount"; fi

[ "$fail" = 0 ] && printf 'ALL PASS\n' || printf 'FAILURES ABOVE\n'
exit "$fail"
