#!/usr/bin/env bash
# g1configcheck.sh — millisecond-scale structural gate for sanitizer/fuzzer build contracts, for the nightly
# workflow that runs the ThreadSanitizer build against main (.github/workflows/nightly.yml), and for ci.yml's
# light-set-vs-full-matrix split (owner decision 2026-09-17 — the last section).

set -u

ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
CMAKE="$ROOT/CMakeLists.txt"
HARNESS="$ROOT/test/fuzz/fuzz_ingest.cpp"
RUNNER="$ROOT/test/fuzz/run.sh"
NIGHTLY="$ROOT/.github/workflows/nightly.yml"
CI="$ROOT/.github/workflows/ci.yml"
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
# M2-era note: `[unsigned-integer-overflow]` now opens THREE ignorelists — bash's scanner (fun:scan),
# the libstdc++ one, and the Windows-only MSVC STL <filesystem> one added under CMakeLists.txt's
# `if(WIN32)` block — so the SECTION count is 3, and every entry underneath is audited separately below
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
# opens its first. 3 + 8 = 11 `src:` occurrences under those two sections, plus below.
#
# WINDOWS FILESYSTEM SEAM (CMakeLists.txt's `if(WIN32)` block): MSVC STL _Is_drive_prefix performs a
# defined unsigned wrap; third-party header, Windows-only. ONE more `[unsigned-integer-overflow]`
# section (the bare header path, no function-name pattern — g1configcheck.sh bans `fun:*` outright, so
# a Windows-only exemption stays file-scoped like every other entry here) and ONE more `src:` occurrence.
# 11 + 1 = 12 `src:` occurrences, no more.
stringViewRuleCount="$( occurrences 'src:\*/bits/string_view\.tcc' )"
basicStringHeaderRuleCount="$( occurrences 'src:\*/bits/basic_string\.h' )"
basicStringTccRuleCount="$( occurrences 'src:\*/bits/basic_string\.tcc' )"
libstdcxxHeaderRuleCount="$(( stringViewRuleCount + basicStringHeaderRuleCount + basicStringTccRuleCount ))"
formatRuleCount="$( occurrences 'src:\*/include/c\\\\+\\\\+/\*/format' )"
printRuleCount="$( occurrences 'src:\*/include/c\\\\+\\\\+/\*/print' )"
formatPrintRuleCount="$(( formatRuleCount + printRuleCount ))"
signedTruncationSectionCount="$( occurrences '\[implicit-signed-integer-truncation\]' )"
filesystemRuleCount="$( occurrences 'src:\*/include/filesystem' )"
srcScopedRuleCount="$( occurrences 'src:' )"
if [ "$unsignedTruncationSectionCount" = 2 ] && [ "$balanceCount" = 1 ] \
    && [ "$functionSectionCount" = 1 ] && [ "$scannerCreateCount" = 1 ] \
    && [ "$unsignedDisableCount" = 2 ] && [ "$signedTruncationDisableCount" = 2 ] \
    && [ "$signChangeDisableCount" = 2 ] \
    && [ "$swiftSignSectionCount" = 2 ] && [ "$swiftWhitespaceCount" = 1 ] \
    && [ "$scannerUnsignedSectionCount" = 3 ] && [ "$bashScanCount" = 1 ] \
    && [ "$signedTruncationSectionCount" = 1 ] \
    && [ "$stringViewRuleCount" = 1 ] && [ "$basicStringHeaderRuleCount" = 1 ] && [ "$basicStringTccRuleCount" = 1 ] \
    && [ "$libstdcxxHeaderRuleCount" = 3 ] \
    && [ "$formatRuleCount" = 4 ] && [ "$printRuleCount" = 4 ] && [ "$formatPrintRuleCount" = 8 ] \
    && [ "$filesystemRuleCount" = 1 ] \
    && [ "$srcScopedRuleCount" = 12 ] \
    && ! grep -Eq 'fun:\*' "$CMAKE"; then
    ok "dependency policy is limited to audited Tree-sitter core, Swift/bash scanner, the 3 libstdc++ string seams, the 2 formatting seams (<format>/<print>, 4 checks each) and the 1 Windows-only MSVC STL <filesystem> seam"
else
    no "sanitizer exemption policy differs from the audited list (sections uint=$scannerUnsignedSectionCount, src:-scoped=$srcScopedRuleCount of which string_view.tcc=$stringViewRuleCount basic_string.h=$basicStringHeaderRuleCount basic_string.tcc=$basicStringTccRuleCount format=$formatRuleCount print=$printRuleCount filesystem=$filesystemRuleCount; sections sign-change=$swiftSignSectionCount signed-trunc=$signedTruncationSectionCount unsigned-trunc=$unsignedTruncationSectionCount)"
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
    if python3 - "$TMP/build/.cmake/api/v1/reply" "$CMAKE" <<'PY'
import json, pathlib, sys
reply = pathlib.Path(sys.argv[1])
index = json.loads(next(reply.glob('index-*.json')).read_text())
model = json.loads((reply / index['reply']['codemodel-v2']['jsonFile']).read_text())
expected = {'ripwire_fuzz_' + name for name in
            'cpp python go rust typescript tsx swift objc javascript bash java ruby json toml yaml csharp c php elixir lua dart kotlin gdscript clojure'.split()}
cmake_text = pathlib.Path(sys.argv[2]).read_text()
readers = cmake_text.split('set(RIPWIRE_FUZZ_READERS', 1)[1].split(')', 1)[0].split()
expected_readers = {'ripwire_fuzz_reader_' + name for name in readers}
assert len(readers) >= 16, readers
assert model['configurations']
for config in model['configurations']:
    targets = [json.loads((reply / t['jsonFile']).read_text()) for t in config['targets']]
    executables = {t['name'] for t in targets if t['type'] == 'EXECUTABLE'}
    actual = {n for n in executables if n.startswith('ripwire_fuzz_') and not n.startswith('ripwire_fuzz_reader_')}
    assert actual == expected, (actual, expected)
    actual_readers = {n for n in executables if n.startswith('ripwire_fuzz_reader_')}
    assert actual_readers == expected_readers, (actual_readers, expected_readers)
print(len(readers))
PY
    then
        ok "configured model contains all 24 grammar fuzz executables and one ripwire_fuzz_reader_<name> per RIPWIRE_FUZZ_READERS entry"
    else
        no "configured grammar or reader fuzz executable set differs from the grammar list / RIPWIRE_FUZZ_READERS"
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
if [ "$seedCount" = 24 ]; then ok "all 24 grammars have valid seeds"; else no "expected 24 grammar seeds, found $seedCount"; fi

# ── the nightly workflow: the TSan build runs against main once a day, and nothing about it can quietly widen ─────────
# ThreadSanitizer is not a per-PR leg (owner decision, 2026-09-17): it runs from .github/workflows/nightly.yml. These
# rows pin the properties that make that workflow trustworthy, each read off the file's own structure rather than
# retyped here:
#   triggers  a daily `schedule` cron, plus workflow_dispatch and a pull_request filtered to the workflow itself
#   skip      a `changed` job asks the Actions API for the last successful scheduled run's head_sha, and every heavy
#             job is gated on its `run` output (a future windows job included)
#   tsan      the tsan job configures -DRIPWIRE_TSAN=ON, halts on the first report, runs the planted-race positive
#             control, and sends every `bash test/...` gate through tsanrun.sh, which is what reads the report files
#   perms     top-level permissions are exactly `contents: read`, and the ONLY write anywhere is `issues: write`, held
#             by report-failure and report-green and nothing else in their blocks
#   report    report-failure runs on failure() and never for a pull_request; report-green only on a scheduled run
#   secrets   no `secrets.` reference other than GITHUB_TOKEN (the workflow itself uses github.token)
# Python without PyYAML (not on every CI leg): a line scanner over the indentation GitHub's own files use. Six mutated
# copies prove each row can fail, and that each mutation reds exactly its own row.
if [ ! -f "$NIGHTLY" ]; then
    no "nightly workflow missing: $NIGHTLY"
else
    NIGHTLYSCAN="$TMP/nightlyscan.py"
    cat > "$NIGHTLYSCAN" <<'PY'
import re, sys

def strip_comment(s):
    quote = None
    for i, ch in enumerate(s):
        if quote:
            if ch == quote:
                quote = None
        elif ch in "\"'":
            quote = ch
        elif ch == "#" and (i == 0 or s[i - 1].isspace()):
            return s[:i].rstrip()
    return s.rstrip()

def indent(s):
    return len(s) - len(s.lstrip(" "))

def children(lines, key_index):
    # the lines of a block key (everything more indented than the key, up to the next line at its indent or less)
    base = indent(lines[key_index])
    out = []
    for s in lines[key_index + 1:]:
        if strip_comment(s).strip() == "":
            continue
        if indent(s) <= base:
            break
        out.append(s)
    return out

def keyed(lines, level):
    # {key: (value, index)} for `key: value` lines at exactly this indent
    found = {}
    for i, s in enumerate(lines):
        t = strip_comment(s)
        m = re.match(r"^( *)([A-Za-z0-9_-]+):(?:\s+(.*))?$", t)
        if m and len(m.group(1)) == level and m.group(2) not in found:
            found[m.group(2)] = ((m.group(3) or "").strip(), i)
    return found

def mapping(block, level):
    return {k: v for k, (v, _) in keyed(block, level).items()}

def scan(path):
    lines = open(path, encoding="utf-8").read().split("\n")
    rows = {}
    top = keyed(lines, 0)
    on = children(lines, top["on"][1]) if "on" in top else []
    onKeys = keyed(on, 2)
    cron = [s for s in on if re.match(r'^ {4}- cron: "[^"]+"', strip_comment(s))]
    cronOk = bool(cron) and all(len(re.search(r'"([^"]+)"', s).group(1).split()) == 5 for s in cron)
    prPaths = children(on, onKeys["pull_request"][1]) if "pull_request" in onKeys else []
    selfFiltered = any(strip_comment(s).strip() == "- .github/workflows/nightly.yml" for s in prPaths)
    rows["triggers"] = (cronOk and "workflow_dispatch" in onKeys and selfFiltered,
                        f"cron={len(cron)} valid={cronOk} dispatch={'workflow_dispatch' in onKeys} pr-self-filter={selfFiltered}")

    jobsBlock = children(lines, top["jobs"][1]) if "jobs" in top else []
    jobs = {}
    for name, (_, i) in keyed(jobsBlock, 2).items():
        jobs[name] = [jobsBlock[i]] + children(jobsBlock, i)
    def jobKeys(name):
        return keyed(jobs[name], 4)
    def jobText(name):
        return "\n".join(strip_comment(s) for s in jobs.get(name, []))

    reports = {"report-failure", "report-green"}
    changedText = jobText("changed")
    probe = all(t in changedText for t in ("actions/workflows/nightly.yml/runs", "event=schedule", "status=success",
                                            "head_sha", "run=false"))
    heavy = [n for n in jobs if n != "changed" and n not in reports]
    ungated = [n for n in heavy if "needs.changed.outputs.run == 'true'" not in jobKeys(n).get("if", ("", 0))[0]]
    rows["skip"] = (probe and bool(heavy) and not ungated, f"probe={probe} heavy={','.join(heavy) or '-'} ungated={','.join(ungated) or '-'}")

    tsanText = jobText("tsan")
    gateLines = [s for s in tsanText.split("\n") if "bash test/" in s]
    unwrapped = [s.strip() for s in gateLines if "tsanrun.sh" not in s]
    tsanOk = ("-DRIPWIRE_TSAN=ON" in tsanText and "halt_on_error=1" in tsanText and "control-race" in tsanText
              and bool(gateLines) and not unwrapped)
    rows["tsan"] = (tsanOk, f"gates={len(gateLines)} unwrapped={len(unwrapped)} configure={'-DRIPWIRE_TSAN=ON' in tsanText}")

    topPerms = mapping(children(lines, top["permissions"][1]), 2) if "permissions" in top and top["permissions"][0] == "" else None
    writes, blocks = set(), {}
    for name in jobs:
        k = jobKeys(name)
        if "permissions" in k:
            value, i = k["permissions"]
            block = mapping(children(jobs[name], i), 6) if value == "" else {"*": value}
            blocks[name] = block
            writes |= {(name, p) for p, v in block.items() if v in ("write", "write-all")}
    expected = {(n, "issues") for n in reports}
    permsOk = topPerms == {"contents": "read"} and writes == expected and all(blocks.get(n) == {"issues": "write"} for n in reports)
    rows["perms"] = (permsOk, f"top={topPerms} writes={sorted(writes)}")

    failIf = jobKeys("report-failure").get("if", ("", 0))[0] if "report-failure" in jobs else ""
    greenIf = jobKeys("report-green").get("if", ("", 0))[0] if "report-green" in jobs else ""
    reportOk = ("failure()" in failIf and "github.event_name != 'pull_request'" in failIf
                and "github.event_name == 'schedule'" in greenIf)
    rows["report"] = (reportOk, f"report-failure if=[{failIf}] report-green if=[{greenIf}]")

    # labelscope: this workflow's tracking issue is its OWN (nightly-tsan alongside the shared
    # nightly-failure), never ci.yml's (nightly-full-matrix) — the fix for a green run in one workflow
    # being able to close an issue the other opened while it was still red. The skip probe above must
    # read the SAME pair, or main could sit on an open ci.yml-only issue while nightly.yml's own checks
    # go on skipping past it.
    failText = jobText("report-failure")
    greenText = jobText("report-green")
    pairUses = failText.count('"$label,$ownLabel"')
    labelscopeOk = ("ownLabel=nightly-tsan" in failText and pairUses == 2 and "(TSan)" in failText
                     and "nightly-failure,nightly-tsan" in greenText
                     and "labels=nightly-failure,nightly-tsan" in changedText)
    rows["labelscope"] = (labelscopeOk,
                           f"ownLabel_decl={'ownLabel=nightly-tsan' in failText} pairUses={pairUses} "
                           f"title_ok={'(TSan)' in failText} green_ok={'nightly-failure,nightly-tsan' in greenText} "
                           f"probe_ok={'labels=nightly-failure,nightly-tsan' in changedText}")

    named = re.findall(r"\bsecrets\b(\.[A-Za-z_][A-Za-z0-9_]*)?", "\n".join(strip_comment(s) for s in lines))
    extra = sorted({n or "<bare>" for n in named if n != ".GITHUB_TOKEN"})
    rows["secrets"] = (not extra, f"other secrets={extra or '-'}")
    return rows

for label, path in zip(sys.argv[1::2], sys.argv[2::2]):
    for row, (good, detail) in scan(path).items():
        print(f"{label}\t{row}\t{'ok' if good else 'bad'}\t{detail}")
PY
    NIGHTLYMUT="$TMP/nightlymut.py"
    cat > "$NIGHTLYMUT" <<'PY'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
out = sys.argv[2]
# row -> (anchor, replacement); every anchor must occur exactly once, or the control refuses instead of passing inert
mutations = {
    "triggers": ('    - cron: "17 7 * * *"   # 07:17 UTC daily\n', ""),
    "skip":     ("    needs: changed\n    if: needs.changed.outputs.run == 'true'\n", "    needs: changed\n"),
    "tsan":     ('"$RUNNER_TEMP/tsanrun.sh" det-gate bash test/det-gate.sh', "bash test/det-gate.sh"),
    "perms":    ("    permissions:\n      contents: read\n    outputs:\n",
                 "    permissions:\n      contents: read\n      issues: write\n    outputs:\n"),
    "report":   ("if: failure() && github.event_name != 'pull_request' && ", "if: failure() && "),
    "secrets":  ("          GH_TOKEN: ${{ github.token }}\n          EVENT: ${{ github.event_name }}\n",
                 "          GH_TOKEN: ${{ secrets.NIGHTLY_PAT }}\n          EVENT: ${{ github.event_name }}\n"),
    # Regressing report-green to the bare shared label is exactly the bug the two-label split fixes: it
    # would let a green TSan night close ci.yml's still-red full-matrix issue (or vice versa).
    "labelscope": ("gh issue list --repo \"$REPO\" --label nightly-failure,nightly-tsan --state open --json number --jq '.[].number'",
                   "gh issue list --repo \"$REPO\" --label nightly-failure --state open --json number --jq '.[].number'"),
}
for row, (anchor, replacement) in mutations.items():
    count = src.count(anchor)
    if count != 1:
        print(f"{row}\tanchor occurs {count} times")
        continue
    open(f"{out}/nightly-mut-{row}.yml", "w", encoding="utf-8").write(src.replace(anchor, replacement))
    print(f"{row}\twritten")
PY
    nightlyRows=( triggers skip tsan perms report secrets labelscope )
    mutLog="$( python3 "$NIGHTLYMUT" "$NIGHTLY" "$TMP" 2>&1 )" || no "nightly mutation writer crashed: $mutLog"
    scanArgs=( real "$NIGHTLY" )
    for row in "${nightlyRows[@]}"; do
        if [ -f "$TMP/nightly-mut-$row.yml" ]; then scanArgs+=( "mut-$row" "$TMP/nightly-mut-$row.yml" ); fi
    done
    if ! python3 "$NIGHTLYSCAN" "${scanArgs[@]}" >"$TMP/nightlyscan.tsv" 2>"$TMP/nightlyscan.err"; then
        no "nightly workflow scanner crashed: $( head -n 3 "$TMP/nightlyscan.err" | tr '\n' ' ' )"
    fi
    for row in "${nightlyRows[@]}"; do
        line="$( awk -F'\t' -v r="$row" '$1 == "real" && $2 == r' "$TMP/nightlyscan.tsv" )"
        verdict="$( printf '%s' "$line" | cut -f3 )"; detail="$( printf '%s' "$line" | cut -f4- )"
        if [ "$verdict" = ok ]; then
            ok "nightly.yml [$row] holds ($detail)"
        else
            no "nightly.yml [$row] does not hold (${detail:-the scanner printed no row})"
        fi
    done
    for row in "${nightlyRows[@]}"; do
        mut="$TMP/nightly-mut-$row.yml"
        if [ ! -f "$mut" ]; then
            no "nightly mutation [$row] was not written: $( printf '%s\n' "$mutLog" | awk -F'\t' -v r="$row" '$1 == r { print $2 }' )"
        elif cmp -s "$NIGHTLY" "$mut"; then
            no "nightly mutation [$row] did not take — the copy is byte-identical to nightly.yml, nothing was checked"
        else
            badRows="$( awk -F'\t' -v m="mut-$row" '$1 == m && $3 == "bad" { print $2 }' "$TMP/nightlyscan.tsv" | paste -sd, - )"
            if [ "$badRows" = "$row" ]; then
                ok "nightly mutation [$row] reds exactly its own row"
            else
                no "nightly mutation [$row] red rows are [${badRows:-none}], expected exactly [$row]"
            fi
        fi
    done
fi

# ── ci.yml: the light-set-vs-full-matrix split (owner decision, 2026-09-17 — CI was the bottleneck) ────────
# These rows pin the properties that make the split trustworthy:
#   push          a push to main is light: the `plan` job's decide script sets full=false for it
#   trainmember   a pull_request carrying the `train-member` label is light
#   otherpr       a pull_request WITHOUT that label stays full
#   dispatch      workflow_dispatch stays full (the owner requires it on the exact commit before a tag)
#   schedule      the new nightly `schedule` trigger stays full
#   triggers      pull_request adds labeled/unlabeled to the default types, workflow_dispatch is declared,
#                 and schedule carries a valid 5-field cron distinct from nightly.yml's 07:17
#   heavygate     fallback-emitter/rhel/asan each gate on `plan`'s `full` output, and `release`'s matrix is
#                 `plan`'s computed `release_matrix` output rather than a second hand-typed full list
#   reportperms   top-level permissions are exactly `contents: read`, and the ONLY write anywhere is
#                 `issues: write`, held by report-failure and report-green and nothing else in their blocks
#   reportscope   report-failure/report-green only act on the scheduled full-matrix run against main
# push/trainmember/otherpr/dispatch/schedule are not read off the text — they EXTRACT the plan job's one
# `run: |` step (the real bash GitHub would run) and EXECUTE it under synthetic EVENT/REF/PR_LABELS, then
# check the `full=` and `release_matrix=` lines it writes to a stand-in $GITHUB_OUTPUT. A regex guess at what
# the case statement does would trust the same bug it is meant to catch; running it does not.
if [ ! -f "$CI" ]; then
    no "ci workflow missing: $CI"
else
    CISCAN="$TMP/ciscan.py"
    cat > "$CISCAN" <<'PY'
import re, sys, json, os, subprocess, tempfile

def strip_comment(s):
    quote = None
    for i, ch in enumerate(s):
        if quote:
            if ch == quote:
                quote = None
        elif ch in "\"'":
            quote = ch
        elif ch == "#" and (i == 0 or s[i - 1].isspace()):
            return s[:i].rstrip()
    return s.rstrip()

def indent(s):
    return len(s) - len(s.lstrip(" "))

def children(lines, key_index):
    base = indent(lines[key_index])
    out = []
    for s in lines[key_index + 1:]:
        if strip_comment(s).strip() == "":
            continue
        if indent(s) <= base:
            break
        out.append(s)
    return out

def keyed(lines, level):
    found = {}
    for i, s in enumerate(lines):
        t = strip_comment(s)
        m = re.match(r"^( *)([A-Za-z0-9_-]+):(?:\s+(.*))?$", t)
        if m and len(m.group(1)) == level and m.group(2) not in found:
            found[m.group(2)] = ((m.group(3) or "").strip(), i)
    return found

def mapping(block, level):
    return {k: v for k, (v, _) in keyed(block, level).items()}

def extract_run_block(block_lines, run_index):
    # Dedents a YAML `|` block scalar's content by its OWN first line's indent, not a hardcoded column —
    # this is what makes the extractor survive re-indentation elsewhere in the file.
    base_indent = indent(block_lines[run_index])
    content_indent = None
    out = []
    for s in block_lines[run_index + 1:]:
        if s.strip() == "":
            out.append("")
            continue
        i = indent(s)
        if content_indent is None:
            if i <= base_indent:
                break
            content_indent = i
        if i < content_indent:
            break
        out.append(s[content_indent:])
    return "\n".join(out)

# name: (event, ref, PR_LABELS json, expected full=, expected release_matrix leg count)
SCENARIOS = {
    "push":        ("push", "refs/heads/main", "[]", "false", 4),
    "trainmember": ("pull_request", "refs/pull/1/merge", '["train-member"]', "false", 4),
    "otherpr":     ("pull_request", "refs/pull/2/merge", '["other"]', "true", 24),
    "dispatch":    ("workflow_dispatch", "refs/heads/main", "[]", "true", 24),
    "schedule":    ("schedule", "refs/heads/main", "[]", "true", 24),
}

def run_decide(script_text, event, ref, labels_json):
    with tempfile.TemporaryDirectory() as td:
        out_path = os.path.join(td, "gh_output")
        open(out_path, "w", encoding="utf-8").close()
        env = dict(os.environ)
        env.update({"EVENT": event, "REF": ref, "PR_LABELS": labels_json, "GITHUB_OUTPUT": out_path})
        try:
            proc = subprocess.run(["bash", "-c", script_text], env=env, capture_output=True, text=True, timeout=10)
        except Exception as e:
            return 1, {}, "", str(e)
        outputs = {}
        for line in open(out_path, encoding="utf-8"):
            if "=" in line:
                k, _, v = line.rstrip("\n").partition("=")
                outputs[k] = v
        return proc.returncode, outputs, proc.stdout, proc.stderr

def scan(path):
    lines = open(path, encoding="utf-8").read().split("\n")
    rows = {}
    top = keyed(lines, 0)

    on = children(lines, top["on"][1]) if "on" in top else []
    onKeys = keyed(on, 2)
    prBlock = children(on, onKeys["pull_request"][1]) if "pull_request" in onKeys else []
    prKeys = keyed(prBlock, 4)
    typesLine = prKeys.get("types", ("", 0))[0]
    hasLabelTypes = "labeled" in typesLine and "unlabeled" in typesLine
    cron = [s for s in on if re.match(r'^ {4}- cron: "[^"]+"', strip_comment(s))]
    cronTimes = [re.search(r'"([^"]+)"', s).group(1) for s in cron]
    cronOk = bool(cronTimes) and all(len(t.split()) == 5 for t in cronTimes)
    distinctFromNightly = cronOk and all(t != "17 7 * * *" for t in cronTimes)
    rows["triggers"] = (hasLabelTypes and "workflow_dispatch" in onKeys and cronOk and distinctFromNightly,
                         f"types=[{typesLine}] dispatch={'workflow_dispatch' in onKeys} cron={cronTimes}")

    jobsBlock = children(lines, top["jobs"][1]) if "jobs" in top else []
    jobs = {}
    for name, (_, i) in keyed(jobsBlock, 2).items():
        jobs[name] = [jobsBlock[i]] + children(jobsBlock, i)
    def jobKeys(name):
        return keyed(jobs[name], 4)
    def jobText(name):
        return "\n".join(strip_comment(s) for s in jobs.get(name, []))

    gated = [n for n in ("fallback-emitter", "rhel", "asan") if "needs.plan.outputs.full == 'true'" in jobText(n)]
    releaseMatrixOk = "fromJSON(needs.plan.outputs.release_matrix)" in jobText("release")
    rows["heavygate"] = (len(gated) == 3 and releaseMatrixOk, f"gated={gated} releaseMatrixOk={releaseMatrixOk}")

    topPerms = mapping(children(lines, top["permissions"][1]), 2) if "permissions" in top and top["permissions"][0] == "" else None
    writes, blocks = set(), {}
    for name in jobs:
        k = jobKeys(name)
        if "permissions" in k:
            value, i = k["permissions"]
            block = mapping(children(jobs[name], i), 6) if value == "" else {"*": value}
            blocks[name] = block
            writes |= {(name, p) for p, v in block.items() if v in ("write", "write-all")}
    reportJobs = {"report-failure", "report-green"}
    expected = {(n, "issues") for n in reportJobs}
    permsOk = topPerms == {"contents": "read"} and writes == expected and all(blocks.get(n) == {"issues": "write"} for n in reportJobs)
    rows["reportperms"] = (permsOk, f"top={topPerms} writes={sorted(writes)}")

    failIf = jobKeys("report-failure").get("if", ("", 0))[0] if "report-failure" in jobs else ""
    greenIf = jobKeys("report-green").get("if", ("", 0))[0] if "report-green" in jobs else ""
    reportScopeOk = ("failure()" in failIf and "schedule" in failIf and "refs/heads/main" in failIf
                      and "success()" in greenIf and "schedule" in greenIf and "refs/heads/main" in greenIf)
    rows["reportscope"] = (reportScopeOk, f"report-failure if=[{failIf}] report-green if=[{greenIf}]")

    # labelscope: this workflow's tracking issue is its OWN (nightly-full-matrix alongside the shared
    # nightly-failure), never nightly.yml's (nightly-tsan) — a green run here must not be able to close an
    # issue the TSan nightly opened while TSan is still red, and the reverse.
    failText = jobText("report-failure")
    greenText = jobText("report-green")
    pairUses = failText.count('"$label,$ownLabel"')
    labelscopeOk = ("ownLabel=nightly-full-matrix" in failText and pairUses == 2 and "(full matrix)" in failText
                     and "nightly-failure,nightly-full-matrix" in greenText)
    rows["labelscope"] = (labelscopeOk,
                           f"ownLabel_decl={'ownLabel=nightly-full-matrix' in failText} pairUses={pairUses} "
                           f"title_ok={'(full matrix)' in failText} green_ok={'nightly-failure,nightly-full-matrix' in greenText}")

    planLines = jobs.get("plan", [])
    run_idx = next((i for i, s in enumerate(planLines) if re.match(r'^\s*run: \|\s*$', s)), None)
    script_text = extract_run_block(planLines, run_idx) if run_idx is not None else None
    for name, (event, ref, labels, expectedFull, expectedCount) in SCENARIOS.items():
        if script_text is None:
            rows[name] = (False, "could not extract the plan job's decide script (no 'run: |' step found)")
            continue
        rc, outputs, _out, err = run_decide(script_text, event, ref, labels)
        full = outputs.get("full")
        matrixRaw = outputs.get("release_matrix")
        count = None
        countOk = False
        if matrixRaw is not None:
            try:
                count = len(json.loads(matrixRaw)["include"])
                countOk = count == expectedCount
            except Exception:
                countOk = False
        ok = rc == 0 and full == expectedFull and countOk
        detail = f"rc={rc} full={full} (want {expectedFull}) matrix_legs={count} (want {expectedCount})"
        if rc != 0:
            detail += f" stderr={err.strip()[:200]}"
        rows[name] = (ok, detail)
    return rows

for label, path in zip(sys.argv[1::2], sys.argv[2::2]):
    for row, (good, detail) in scan(path).items():
        print(f"{label}\t{row}\t{'ok' if good else 'bad'}\t{detail}")
PY
    CIMUT="$TMP/cimut.py"
    cat > "$CIMUT" <<'PY'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
out = sys.argv[2]
# row -> (anchor, replacement); every anchor must occur exactly once, or the control refuses instead of passing inert
mutations = {
    "push": ('              if [ "$REF" = refs/heads/main ]; then\n                full=false\n              fi',
             '              if [ "$REF" = refs/heads/main ]; then\n                full=true\n              fi'),
    "trainmember": ("if jq -e 'index(\"train-member\") != null' <<<\"$PR_LABELS\" >/dev/null; then",
                     "if jq -e 'index(\"no-such-label\") != null' <<<\"$PR_LABELS\" >/dev/null; then"),
    "otherpr": ("        run: |\n          full=true\n          case", "        run: |\n          full=false\n          case"),
    "dispatch": ("            workflow_dispatch|schedule)\n              full=true\n              ;;",
                 "            workflow_dispatch)\n              full=false\n              ;;\n            schedule)\n              full=true\n              ;;"),
    "schedule": ("            workflow_dispatch|schedule)\n              full=true\n              ;;",
                 "            workflow_dispatch)\n              full=true\n              ;;\n            schedule)\n              full=false\n              ;;"),
    "triggers": ("    types: [opened, synchronize, reopened, labeled, unlabeled]",
                 "    types: [opened, synchronize, reopened]"),
    "heavygate": ("  fallback-emitter:\n    needs: plan\n    if: needs.plan.outputs.full == 'true'   # not part of the light set — see the header comment\n",
                   "  fallback-emitter:\n    needs: plan\n"),
    "reportperms": ("permissions:\n  contents: read   # least privilege at the top; only report-failure/report-green below widen, and only for themselves\n",
                     "permissions:\n  contents: read   # least privilege at the top; only report-failure/report-green below widen, and only for themselves\n  issues: write\n"),
    "reportscope": ("    if: failure() && github.event_name == 'schedule' && github.ref == 'refs/heads/main'",
                     "    if: failure() && github.ref == 'refs/heads/main'"),
    # Regressing report-green to the bare shared label is exactly the bug the two-label split fixes: it
    # would let a green full-matrix night close nightly.yml's still-red TSan issue (or vice versa).
    "labelscope": ("gh issue list --repo \"$REPO\" --label nightly-failure,nightly-full-matrix --state open --json number --jq '.[].number'",
                   "gh issue list --repo \"$REPO\" --label nightly-failure --state open --json number --jq '.[].number'"),
}
for row, (anchor, replacement) in mutations.items():
    count = src.count(anchor)
    if count != 1:
        print(f"{row}\tanchor occurs {count} times")
        continue
    open(f"{out}/ci-mut-{row}.yml", "w", encoding="utf-8").write(src.replace(anchor, replacement))
    print(f"{row}\twritten")
PY
    ciRows=( push trainmember otherpr dispatch schedule triggers heavygate reportperms reportscope labelscope )
    mutLog="$( python3 "$CIMUT" "$CI" "$TMP" 2>&1 )" || no "ci mutation writer crashed: $mutLog"
    scanArgs=( real "$CI" )
    for row in "${ciRows[@]}"; do
        if [ -f "$TMP/ci-mut-$row.yml" ]; then scanArgs+=( "mut-$row" "$TMP/ci-mut-$row.yml" ); fi
    done
    if ! python3 "$CISCAN" "${scanArgs[@]}" >"$TMP/ciscan.tsv" 2>"$TMP/ciscan.err"; then
        no "ci workflow scanner crashed: $( head -n 3 "$TMP/ciscan.err" | tr '\n' ' ' )"
    fi
    for row in "${ciRows[@]}"; do
        line="$( awk -F'\t' -v r="$row" '$1 == "real" && $2 == r' "$TMP/ciscan.tsv" )"
        verdict="$( printf '%s' "$line" | cut -f3 )"; detail="$( printf '%s' "$line" | cut -f4- )"
        if [ "$verdict" = ok ]; then
            ok "ci.yml [$row] holds ($detail)"
        else
            no "ci.yml [$row] does not hold (${detail:-the scanner printed no row})"
        fi
    done
    for row in "${ciRows[@]}"; do
        mut="$TMP/ci-mut-$row.yml"
        if [ ! -f "$mut" ]; then
            no "ci mutation [$row] was not written: $( printf '%s\n' "$mutLog" | awk -F'\t' -v r="$row" '$1 == r { print $2 }' )"
        elif cmp -s "$CI" "$mut"; then
            no "ci mutation [$row] did not take — the copy is byte-identical to ci.yml, nothing was checked"
        else
            badRows="$( awk -F'\t' -v m="mut-$row" '$1 == m && $3 == "bad" { print $2 }' "$TMP/ciscan.tsv" | paste -sd, - )"
            if [ "$badRows" = "$row" ]; then
                ok "ci mutation [$row] reds exactly its own row"
            else
                no "ci mutation [$row] red rows are [${badRows:-none}], expected exactly [$row]"
            fi
        fi
    done
fi

# Reader fuzzers (test/fuzz/readers/): ripwire's own parsers of bytes it did not create. The reader list lives ONCE in
# CMakeLists.txt; every entry must have a harness function, committed seeds, and the runner must read the same list.
READERS_DIR="$ROOT/test/fuzz/readers"
readerList="$( sed -n '/set(RIPWIRE_FUZZ_READERS/,/)/p' "$CMAKE" | tr -d '()' | sed 's/setRIPWIRE_FUZZ_READERS//' | tr -s ' \n' ' ' )"
readerCount=0; readerMissing=""
for reader in $readerList; do
    readerCount=$(( readerCount + 1 ))
    grep -qE "^int $reader\( const std::uint8_t\* data, std::size_t size \)" "$READERS_DIR"/readers_*.cpp || readerMissing="$readerMissing harness:$reader"
    [ -n "$( ls -A "$READERS_DIR/seeds/$reader" 2>/dev/null )" ] || readerMissing="$readerMissing seeds:$reader"
done
if [ "$readerCount" -ge 16 ] && [ -z "$readerMissing" ]; then
    ok "every one of the $readerCount RIPWIRE_FUZZ_READERS has a harness entry point and committed seeds"
else
    no "reader fuzzers incomplete ($readerCount listed):$readerMissing"
fi
grep -q 'LLVMFuzzerTestOneInput' "$READERS_DIR/fuzz_reader.cpp" && grep -q 'RIPWIRE_FUZZ_READER' "$READERS_DIR/fuzz_reader.cpp" \
    && ok "the reader entry TU dispatches to one compile-selected reader" || no "reader entry TU (fuzz_reader.cpp) incomplete"
grep -q 'set(RIPWIRE_FUZZ_READERS' "$READERS_DIR/run.sh" && grep -q 'executed 0 inputs' "$READERS_DIR/run.sh" \
    && grep -q 'max_total_time=' "$READERS_DIR/run.sh" && grep -q 'nice -n 10' "$READERS_DIR/run.sh" \
    && ok "reader runner reads the CMake list, refuses a 0-input replay, and fuzzes time-boxed and niced" \
    || no "reader runner (test/fuzz/readers/run.sh) contract missing"
[ "$fail" = 0 ] && printf 'ALL PASS\n' || printf 'FAILURES ABOVE\n'
exit "$fail"
