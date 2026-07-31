#!/usr/bin/env bash
# g1configcheck.sh — millisecond-scale structural gate for sanitizer/fuzzer build contracts.

set -u

ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
CMAKE="$ROOT/CMakeLists.txt"
HARNESS="$ROOT/test/fuzz/fuzz_ingest.cpp"
RUNNER="$ROOT/test/fuzz/run.sh"
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

for mode in ASAN TSAN FUZZ; do
    grep -q "option(CTXPACK_$mode" "$CMAKE" && ok "CTXPACK_$mode is explicitly declared" || no "CTXPACK_$mode option missing"
done
grep -q 'are mutually exclusive' "$CMAKE" && ok "sanitizer modes are mutually exclusive" || no "mutual-exclusion gate missing"

grep -q -- '-fsanitize=address,undefined,integer,float-divide-by-zero,float-cast-overflow' "$CMAKE" \
    && ok "complete G1 sanitizer set declared" || no "complete G1 sanitizer set missing"
grep -q -- '-fno-sanitize-recover=all -fno-omit-frame-pointer -O2 -g' "$CMAKE" \
    && ok "G1 is fail-fast, framed, and O2" || no "G1 fail-fast/O2 contract missing"
grep -q 'tree-sitter.*${CTXPACK_GRAMMAR_TARGETS}' "$CMAKE" \
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
scannerUnsignedSectionCount="$( grep -c '\[unsigned-integer-overflow\]' "$CMAKE" )"
bashScanCount="$( grep -c 'fun:scan' "$CMAKE" )"
if [ "$unsignedTruncationSectionCount" = 1 ] && [ "$balanceCount" = 1 ] \
    && [ "$functionSectionCount" = 1 ] && [ "$scannerCreateCount" = 1 ] \
    && [ "$unsignedDisableCount" = 2 ] && [ "$signedTruncationDisableCount" = 2 ] \
    && [ "$signChangeDisableCount" = 2 ] \
    && [ "$swiftSignSectionCount" = 1 ] && [ "$swiftWhitespaceCount" = 1 ] \
    && [ "$scannerUnsignedSectionCount" = 1 ] && [ "$bashScanCount" = 1 ] \
    && ! grep -Eq '(src:|fun:\*)' "$CMAKE"; then
    ok "dependency policy is limited to audited Tree-sitter core and Swift scanner conversion seams"
else
    no "tree-sitter sanitizer policy differs from the audited core-only rules"
fi

grep -q 'set(_ctxpack_asan_options "detect_leaks=0' "$CMAKE" \
    && grep -q 'set(_ctxpack_asan_options "detect_leaks=1' "$CMAKE" \
    && grep -q 'LSAN_OPTIONS=suppressions=' "$CMAKE" \
    && ok "Darwin limitation and non-Darwin leak gate are explicit" || no "platform leak runtime policy missing"
if grep -q -- '-fsanitize=leak' "$CMAKE"; then no "unsupported standalone Darwin leak sanitizer declared"; else ok "no unsupported standalone leak flag"; fi

grep -q 'check_cxx_source_compiles' "$CMAKE" && grep -q 'LLVMFuzzerTestOneInput' "$CMAKE" \
    && grep -q 'same upstream LLVM installation' "$CMAKE" \
    && ok "libFuzzer availability uses a real link probe with remediation" || no "libFuzzer link probe/remediation missing"

fuzzTargetCount="$( grep -c '^  add_ctxpack_fuzzer(' "$CMAKE" )"
[ "$fuzzTargetCount" = 15 ] && ok "15 grammar fuzz targets declared" || no "expected 15 grammar fuzz targets, found $fuzzTargetCount"
grep -q 'EXCLUDE_FROM_ALL' "$CMAKE" && ok "fuzz targets excluded from normal builds" || no "fuzz targets can enter normal builds"

grep -q 'LLVMFuzzerTestOneInput' "$HARNESS" && grep -q 'ts_parser_parse_string' "$HARNESS" \
    && grep -q 'ts_node_child(' "$HARNESS" && grep -q 'ts_node_named_child(' "$HARNESS" \
    && ok "shared harness parses arbitrary bytes and iteratively walks ASTs" || no "shared AST fuzz harness incomplete"
grep -q 'max_total_time=' "$RUNNER" && grep -q 'max_len=65536' "$RUNNER" && grep -q 'CTXPACK_FUZZ_JOBS:-4' "$RUNNER" \
    && grep -q 'DETECT_LEAKS=0' "$RUNNER" && grep -q 'DETECT_LEAKS=1' "$RUNNER" \
    && ok "fuzz runner is time-, input-, and concurrency-bounded" || no "bounded fuzz runner contract missing"

seedCount="$( find "$ROOT/test/fuzz/seeds" -mindepth 2 -maxdepth 2 -name valid | wc -l | tr -d ' ' )"
[ "$seedCount" = 15 ] && ok "all 15 grammars have valid seeds" || no "expected 15 grammar seeds, found $seedCount"

[ "$fail" = 0 ] && printf 'ALL PASS\n' || printf 'FAILURES ABOVE\n'
exit "$fail"
