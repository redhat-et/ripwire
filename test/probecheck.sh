#!/usr/bin/env bash
# probecheck.sh — ctxpack_probe (the Phase-1/2 PROOF binary) enum-table gate.
#
# WHY THIS EXISTS: src/tsprobe.cpp counted symbols into a hardcoded `std::array<int, 6>` indexed by
# `Lang` and a `std::array<int, 7>` indexed by `SymKind`, next to a 5-arm langName() switch. Both were
# written when Lang had five values. Lang has since grown to sixteen (…Markdown=7 … CSharp=14, C=15)
# and SymKind to eight, so:
#   - a corpus with ONE plain .c file wrote langCount[15] off the end of a 6-slot array — the probe
#     died (exit 139/138) on a corpus `./build/ctxpack` itself handles fine (H4 grammar survey);
#   - every language after the original five printed lang "?";
#   - markdown headings (SymKind::Section) printed under the "other" label, and SymKind::Other was
#     off the end of the printf entirely.
# The compile-time guard now lives in tsprobe.cpp (kLangName is static_asserted against the Lang
# enum's last value, and both counter arrays are sized from the enums). This gate is the RUNTIME half:
# it proves the probe survives, and NAMES, every language the ingest table actually indexes.
#
# FINDINGS from running the fixed binary (assertions below are pinned to observed behaviour):
#   - test/cfix (3 files, 9 symbols): exit 0, "defs by language:  cpp=1  c=8" — the `.h` prototype
#     stays Cpp-owned (the L3 split ccheck.sh documents), the two .c files are Lang::C.
#   - a one-file-per-language corpus (built in $TMP below) yields a def in ALL FIFTEEN named languages;
#     Lang::Unknown never appears, because ingest only opens files whose extension maps to a grammar.
#   - kinds on that corpus: fn=10 method=4 cls=3 struct=0 iface=0 var=0 sec=3 other=0 — `sec` is the
#     bucket the old printf mislabeled.
#
# Usage:
#   bash test/probecheck.sh
#   CTXPACK_BIN=build/ctxpack bash test/probecheck.sh     # probe is taken as ${CTXPACK_BIN}_probe
#   CTXPACK_BIN=asan/ctxpack  bash test/probecheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative CTXPACK_BIN
PROBE="${BIN}_probe"                                  # same build dir as the binary under test
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$PROBE" ] || { echo "no ctxpack_probe at $PROBE — build first (cmake --build build -j)"; exit 2; }
[ -d "$ROOT/test/cfix" ] || { echo "no fixture at $ROOT/test/cfix"; exit 2; }

cd "$ROOT"
echo "probecheck: PROBE=$PROBE"

# the two summary lines live directly under their headers — pull them out so the token assertions
# below cannot be satisfied by a symbol NAME further down the dump.
langline(){ awk '/^defs by language:/{ getline; print; exit }' "$1"; }
kindline(){ awk '/^symbols by kind:/{ getline; print; exit }' "$1"; }

# `c=8` must not be matched by `cs=…`/`cpp=…`: anchor each label on whitespace and require a count.
hastok(){ printf '%s' "$2" | grep -qE "[[:space:]]$1=[0-9]+"; }
haspos(){ printf '%s' "$2" | grep -qE "[[:space:]]$1=[1-9][0-9]*"; }

# 1) the crash repro — a corpus with plain .c files (Lang::C == 15, the highest enum value).
"$PROBE" test/cfix >"$TMP/c.out" 2>"$TMP/c.err"; rc=$?
if [ "$rc" = 0 ]; then ok "probe exits 0 on a plain-C corpus (test/cfix)"
else no "probe exited $rc on test/cfix (was 139/138: langCount[15] off a 6-slot array)"; fi

[ -s "$TMP/c.out" ] && ok "probe produced output on test/cfix" || no "probe produced NO output on test/cfix"

# 2) …and C is NAMED there, not printed as the unknown label.
CLINE="$( langline "$TMP/c.out" )"
haspos c "$CLINE" && ok "test/cfix defs by language names c ($CLINE )" || no "test/cfix: no c= count in [$CLINE ]"
haspos cpp "$CLINE" && ok "test/cfix names cpp (the .h prototype stays C++-owned, L3)" || no "test/cfix: no cpp= count in [$CLINE ]"

# 3) EVERY language the ingest table indexes: one trivial file per extension, one probe run. This is
#    the arm that fails the moment a language is appended to Lang without a kLangName row — the same
#    drift the static_assert in tsprobe.cpp catches at compile time, observed from outside.
ALL="$TMP/alllangs"; mkdir -p "$ALL"
printf 'int add_one( int x ) { return x + 1; }\nint add_two( int x ) { return add_one( x ) + 1; }\n' >"$ALL/a.c"
printf 'int cppFn() { return 1; }\n'                        >"$ALL/a.cpp"
printf 'def py_fn():\n    return 1\n'                       >"$ALL/a.py"
printf 'export function tsFn(): number { return 1; }\n'     >"$ALL/a.ts"
printf 'package main\n\nfunc goFn() int { return 1 }\n'     >"$ALL/a.go"
printf 'fn rust_fn() -> i32 { 1 }\n'                        >"$ALL/a.rs"
printf 'func swiftFn() -> Int { return 1 }\n'               >"$ALL/a.swift"
printf '@implementation Foo\n- (int)objcFn { return 1; }\n@end\n' >"$ALL/a.m"
printf 'function jsFn() { return 1; }\n'                    >"$ALL/a.js"
printf 'sh_fn() {\n  echo 1\n}\n'                           >"$ALL/a.sh"
printf 'class JavaCls { int javaFn() { return 1; } }\n'     >"$ALL/a.java"
printf 'def ruby_fn\n  1\nend\n'                            >"$ALL/a.rb"
printf 'class CsCls { int CsFn() { return 1; } }\n'         >"$ALL/a.cs"
printf '# Heading\n\nsome text\n'                           >"$ALL/a.md"
printf '{ "key": 1 }\n'                                     >"$ALL/a.json"

"$PROBE" "$ALL" >"$TMP/all.out" 2>"$TMP/all.err"; rc=$?
[ "$rc" = 0 ] && ok "probe exits 0 on the all-languages corpus" || no "probe exited $rc on the all-languages corpus"

ALINE="$( langline "$TMP/all.out" )"
missing=""
for _l in cpp py ts go rust swift objc md js sh java rb json cs c; do
    haspos "$_l" "$ALINE" || missing="$missing $_l"
done
[ -z "$missing" ] && ok "all 15 languages named with a positive def count" \
                  || no "languages missing from the probe's summary:$missing  [line:$ALINE ]"

# 4) no symbol may be bucketed under the unknown label — every ingested file has a grammar, so a "?"
#    here means a Lang value with no name (exactly what C/C#/Ruby/… printed before this fix). The
#    emptiness guard matters: without it a CRASHED probe satisfies "printed no ?" for free.
if [ -z "$ALINE" ]; then no "no language summary line at all (probe crashed or changed its format)"
elif printf '%s' "$ALINE" | grep -qF '?='; then no "probe printed the unknown language label: [$ALINE ]"
else ok "no unknown-language bucket (?=) on a fully-typed corpus"; fi

# 5) the SymKind half of the same bug: `sec` (markdown headings) had been printed under the "other"
#    label and SymKind::Other was off the end of the printf's argument list.
KLINE="$( kindline "$TMP/all.out" )"
haspos sec "$KLINE" && ok "kind summary names sec (markdown headings, own bucket)" || no "no sec= count in [$KLINE ]"
hastok other "$KLINE" && ok "kind summary reaches other (the last SymKind)" || no "no other= count in [$KLINE ]"

# 6) determinism — the probe reads the same deterministic ingest the main binary does. Two EMPTY files
#    also compare equal, so the non-empty guard is what keeps this arm honest on a crash.
"$PROBE" "$ALL" >"$TMP/all2.out" 2>/dev/null
if [ ! -s "$TMP/all.out" ] || [ ! -s "$TMP/all2.out" ]; then no "determinism arm: a run produced no output"
elif diff -q "$TMP/all.out" "$TMP/all2.out" >/dev/null; then ok "probe output is deterministic (two runs byte-identical)"
else no "probe output differs between runs"; diff "$TMP/all.out" "$TMP/all2.out" | head -4; fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
