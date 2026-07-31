#!/usr/bin/env bash
# regexbombcheck.sh — A4-F10 gate: a catastrophic-backtracking --regex pattern must degrade (skip the file,
# keep going), never std::terminate the whole run.
#
# src/search.h:755 only wrapped regex CONSTRUCTION in try/catch; std::sregex_iterator/regex_search can
# throw regex_error (error_complexity/error_space) MID-MATCH on a pathological pattern over a pathological
# file — construction succeeds (the pattern itself is fine), the blowup is in the matching. Apple libc++
# (this repo's toolchain) throws regex_error fast on classic catastrophic-backtracking shapes like
# `(a+)+b` over a long run of 'a' with no trailing 'b' (verified directly against std::regex before writing
# this gate — it throws in well under a second, no external timeout tool needed).
#
# test/regexbombfix/ has:
#   bomb.md     — a long line of 4000 'a's, no 'b' — the catastrophic-backtracking bait for `(a+)+b`.
#                 (.md, not .txt — ctxpack only ingests files with a recognized extension into ing.files,
#                 and grep only scans ingested files; .md has no tree-sitter grammar but its raw bytes are
#                 still stored for grep, which is all this fixture needs.)
#   normal.cpp  — two ordinary EASY (a+)+b matches ("aab", "aaab"), to prove the bomb file's degrade does
#                 NOT take the rest of the candidate set down with it.
#
# Checks: (1) exit 0 (not a crash/signal death), (2) well-formed XML output, (3) the normal file's matches
# still come through (the bomb file's failure is isolated), (4) deterministic (two runs byte-identical).
#
# Usage: CTXPACK_BIN=build/ctxpack bash test/regexbombcheck.sh
# Exits non-zero on any failure. Does NOT touch regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
CORPUS="$ROOT/test/regexbombfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$CORPUS" ] || { echo "no test/regexbombfix dir — fixture missing"; exit 2; }

echo "regexbombcheck: BIN=$BIN  CORPUS=test/regexbombfix"

# ── (1)/(2) the pathological pattern over the bomb file must not crash and must yield well-formed XML ────
"$BIN" "$CORPUS" --regex='(a+)+b' --no-prefilter --no-cache >"$TMP/out.xml" 2>"$TMP/out.err"
rc=$?
if [ "$rc" -ge 128 ]; then
    no "CRASHED (signal death, exit $rc — likely std::terminate from an uncaught regex_error)"
elif [ "$rc" -ne 0 ]; then
    no "unexpected nonzero exit ($rc)"
else
    ok "exit 0 (no crash on the catastrophic-backtracking pattern)"
fi

if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/out.xml" 2>/dev/null && ok "well-formed XML despite the bomb file" \
        || { no "malformed XML"; cat "$TMP/out.xml"; }
else
    printf '  SKIP  xmllint (not installed)\n'
fi

# ── (3) isolation: normal.cpp's easy matches still land (bomb.md's failure didn't take down the run) ─────
grep -q 'normal.cpp' "$TMP/out.xml" \
    && ok "normal.cpp's matches still present (bomb file's failure is isolated, not run-wide)" \
    || { no "normal.cpp matches missing — the whole run was affected by the bomb file"; cat "$TMP/out.xml"; }

# ── (4) determinism — two runs byte-identical (the degrade path is a pure function of the input) ─────────
"$BIN" "$CORPUS" --regex='(a+)+b' --no-prefilter --no-cache >"$TMP/d1" 2>/dev/null
"$BIN" "$CORPUS" --regex='(a+)+b' --no-prefilter --no-cache >"$TMP/d2" 2>/dev/null
diff -q "$TMP/d1" "$TMP/d2" >/dev/null && ok "deterministic (two runs byte-identical)" || no "non-deterministic"

# ── (5) informational: was the degrade actually exercised (regex_error thrown + caught)? Soft check only —
#     DEGRADED_PATH_ALERT compiles to nothing in a release/NDEBUG build, so its ABSENCE is not a failure;
#     its presence just confirms the exact code path fired in a debug-flavored build. ─────────────────────
if grep -qi 'regex' "$TMP/out.err"; then
    ok "informational: degrade path fired (stderr alert present) — $(grep -i regex "$TMP/out.err" | head -1)"
else
    printf '  INFO  no degrade-path stderr alert (expected in a release/NDEBUG build — DEGRADED_PATH_ALERT is a no-op there)\n'
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
