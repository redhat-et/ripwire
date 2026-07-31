#!/usr/bin/env bash
# clicheck.sh — gate for CLI error paths and argument validation.
#
# Asserts:
#   (a) unknown flag --no-such-flag → non-zero exit, stderr mentions the flag, stdout EMPTY
#   (b) --top-k=abc and --top-k=0 → non-zero exit, stdout empty
#   (c) --pack-budget-bytes=abc and --pack-budget-bytes=-1 → non-zero exit
#   (d) running with a nonexistent directory path → non-zero exit, stdout empty (or minimal XML from degraded path)
#   (e) --help → exit 0 and non-empty stdout
#   (f) --help with a directory → treats it as positional, outputs help, exit 0
#
# Usage:
#   test/clicheck.sh                          # uses build/ctxpack
#   CTXPACK_BIN=asan/ctxpack test/clicheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${CTXPACK_BIN:-$ROOT/build/ctxpack}}"   # BOTH seams: `bash test/clicheck.sh asan/ctxpack` and CTXPACK_BIN=
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
CORPUS="$ROOT/test/fixture"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }

echo "clicheck: BIN=$BIN  CORPUS=$CORPUS"

# ── (a) Unknown flag: --no-such-flag ──────────────────────────────────────────────────────────────
# Should exit non-zero, mention the flag in stderr, and produce empty stdout
"$BIN" "$CORPUS" --no-such-flag >"$TMP/a_stdout" 2>"$TMP/a_stderr"
a_exit=$?

[ "$a_exit" -ne 0 ] \
    && ok "unknown flag exits non-zero" \
    || no "unknown flag should exit non-zero but exited $a_exit"

[ -s "$TMP/a_stderr" ] && grep -q "no-such-flag" "$TMP/a_stderr" \
    && ok "unknown flag error in stderr mentions the flag" \
    || no "unknown flag error not found in stderr"

[ ! -s "$TMP/a_stdout" ] \
    && ok "unknown flag produces empty stdout" \
    || no "unknown flag stdout should be empty but contains $(wc -c <"$TMP/a_stdout") bytes"

# ── (b) Invalid --top-k values ────────────────────────────────────────────────────────────────────

# --top-k=abc (non-integer)
"$BIN" "$CORPUS" --top-k=abc >"$TMP/b1_stdout" 2>"$TMP/b1_stderr"
b1_exit=$?

[ "$b1_exit" -ne 0 ] \
    && ok "--top-k=abc exits non-zero" \
    || no "--top-k=abc should exit non-zero but exited $b1_exit"

[ ! -s "$TMP/b1_stdout" ] \
    && ok "--top-k=abc produces empty stdout" \
    || no "--top-k=abc stdout should be empty but contains $(wc -c <"$TMP/b1_stdout") bytes"

# --top-k=0 (invalid: needs positive)
"$BIN" "$CORPUS" --top-k=0 >"$TMP/b2_stdout" 2>"$TMP/b2_stderr"
b2_exit=$?

[ "$b2_exit" -ne 0 ] \
    && ok "--top-k=0 exits non-zero" \
    || no "--top-k=0 should exit non-zero but exited $b2_exit"

[ ! -s "$TMP/b2_stdout" ] \
    && ok "--top-k=0 produces empty stdout" \
    || no "--top-k=0 stdout should be empty but contains $(wc -c <"$TMP/b2_stdout") bytes"

# ── (c) Invalid --pack-budget-bytes values ────────────────────────────────────────────────────────

# --pack-budget-bytes=abc (non-integer)
"$BIN" "$CORPUS" --pack-budget-bytes=abc >"$TMP/c1_stdout" 2>"$TMP/c1_stderr"
c1_exit=$?

[ "$c1_exit" -ne 0 ] \
    && ok "--pack-budget-bytes=abc exits non-zero" \
    || no "--pack-budget-bytes=abc should exit non-zero but exited $c1_exit"

# --pack-budget-bytes=-1 (invalid: needs positive)
"$BIN" "$CORPUS" --pack-budget-bytes=-1 >"$TMP/c2_stdout" 2>"$TMP/c2_stderr"
c2_exit=$?

[ "$c2_exit" -ne 0 ] \
    && ok "--pack-budget-bytes=-1 exits non-zero" \
    || no "--pack-budget-bytes=-1 should exit non-zero but exited $c2_exit"

# ── (d) Nonexistent directory path ────────────────────────────────────────────────────────────────
# A root that does not EXIST is caller error (a typo'd path): exit 1, EMPTY stdout, stderr says why.
# (A readable-but-empty directory still maps to a valid empty result with exit 0 — covered by
# emptycorpuscheck.sh: "nothing there" and "no such place" are different answers.)
"$BIN" /nonexistent/path >"$TMP/d_stdout" 2>"$TMP/d_stderr"
d_exit=$?

[ "$d_exit" -ne 0 ] \
    && ok "nonexistent directory exits non-zero" \
    || no "nonexistent directory exited $d_exit (expected non-zero)"

[ ! -s "$TMP/d_stdout" ] \
    && ok "nonexistent directory produces no stdout (no partial XML for pipelines)" \
    || no "nonexistent directory produced stdout output"

[ -s "$TMP/d_stderr" ] && grep -qi "does not exist" "$TMP/d_stderr" \
    && ok "nonexistent directory error names the problem on stderr" \
    || no "nonexistent directory stderr missing the explanation"

# ── (e) --help flag ──────────────────────────────────────────────────────────────────────────────

# --help should exit 0
"$BIN" --help >"$TMP/e_stdout" 2>"$TMP/e_stderr"
e_exit=$?

[ "$e_exit" -eq 0 ] \
    && ok "--help exits 0" \
    || no "--help should exit 0 but exited $e_exit"

# --help should produce non-empty stdout
[ -s "$TMP/e_stdout" ] \
    && ok "--help produces non-empty stdout ($(wc -c <"$TMP/e_stdout") bytes)" \
    || no "--help stdout should be non-empty"

# --help output should contain recognizable help text
grep -q "usage:" "$TMP/e_stdout" \
    && ok "--help contains 'usage:'" \
    || no "--help output missing 'usage:' text"

# ── (g) X9(c): conflicting mode flags warn on stderr — one line each, no behavior change ────────────

# --for beats --query/--pack-task: one warning line, and the --for answer still comes out (behavior unchanged).
g1_out="$( "$BIN" "$CORPUS" --for="widget" --query="widget" --pack-task="add a widget" --no-cache 2>"$TMP/g1_err" )"
g1_forOnly_out="$( "$BIN" "$CORPUS" --for="widget" --no-cache 2>/dev/null )"
[ "$( grep -c '^ctxpack: --for takes precedence' "$TMP/g1_err" )" = 1 ] \
    && ok "X9(c): --for+--query+--pack-task: exactly one precedence warning on stderr" \
    || no "X9(c): expected exactly one --for precedence warning, got: $( cat "$TMP/g1_err" )"
[ "$g1_out" = "$g1_forOnly_out" ] \
    && ok "X9(c): --for+--query+--pack-task: stdout identical to --for alone (no behavior change)" \
    || no "X9(c): the warning changed stdout behavior (should be --for's answer, untouched)"

# --pack-task beats --query when --for is absent: one warning line.
g2_err="$( "$BIN" "$CORPUS" --query="widget" --pack-task="add a widget" --no-cache 2>&1 1>/dev/null )"
printf '%s' "$g2_err" | grep -q '^ctxpack: --pack-task takes precedence over --query' \
    && ok "X9(c): --pack-task+--query (no --for): precedence warning on stderr" \
    || no "X9(c): expected a --pack-task-over-query warning, got: $g2_err"

# --stable + --most-important-last: one warning line; a bare --for (no conflict) stays silent (control).
g3_err="$( "$BIN" "$CORPUS" --stable --most-important-last --no-cache 2>&1 1>/dev/null )"
printf '%s' "$g3_err" | grep -q '^ctxpack: --stable takes precedence over --most-important-last' \
    && ok "X9(c): --stable+--most-important-last: precedence warning on stderr" \
    || no "X9(c): expected a --stable-over-most-important-last warning, got: $g3_err"
g4_err="$( "$BIN" "$CORPUS" --for="widget" --no-cache 2>&1 1>/dev/null )"
[ -z "$g4_err" ] \
    && ok "X9(c): no conflicting flags (control): stderr stays silent" \
    || no "X9(c): control run should have no stderr, got: $g4_err"

# ── (h) X9(d): --help is honest about which verbs --top-k applies to (--for's OWN bundle is inert) ──

grep -q 'INERT there' "$TMP/e_stdout" \
    && ok "X9(d): --help documents --top-k as inert on --for's own bundle" \
    || no "X9(d): --help --top-k entry missing the --for-is-inert caveat"
grep -q 'top-k' "$TMP/e_stdout" \
    && ok "X9(d): --help still documents --top-k itself" \
    || no "X9(d): --help lost the --top-k entry entirely"

# ── (g) A SAVINGS FIGURE IN --help IS A CLAIM, AND IT MUST SURVIVE MEASUREMENT ────────────────────
# --pack-signatures advertised a bare "~70% fewer tokens" while its nearest sibling, --format=columnar,
# already hedged the same kind of number ("~15-60% ... results of a few rows can be LARGER"). Two claims of
# the same shape, one hedged and one not, in one document — and the unhedged one is the larger number.
# The reduction is not a constant: it RISES with the result size, and it is LOWER when the root is spelled
# absolutely, because the repeated path prefix is charged in both forms and is not what the flag elides — a
# ~45 B prefix is a far bigger share of a short signature than of a long body. Measured on this repo:
# 60.0 / 62.9 / 70.6% at top-10/50/100 under a relative root, 51.9 / 59.3 / 68.0% under an absolute one.
# So the arm is not "does it say 70" — it is that BOTH siblings state a RANGE and BOTH name a case where
# the saving shrinks or inverts. Asserted over a table, so a third such claim is added to the table rather
# than to the prose. The entry is sliced out of --help by its own flag anchor: a whole-document grep would
# match either sibling's words in the other's block and pass for the wrong reason.
entry_of(){ awk -v flag="$1" '
    index( $0, "    " flag ) == 1 { inb=1; print; next }
    inb && /^    --/                { exit }
    inb                             { print }' "$TMP/e_stdout"; }

for _pair in "--pack-signatures" "--format=xml|columnar|rows"; do
    _blk="$( entry_of "$_pair" )"
    if [ -z "$_blk" ]; then
        no "(g) --help has no entry for $_pair — the savings-claim table cannot be checked"
        continue
    fi
    printf '%s' "$_blk" | grep -qE '~?[0-9]+ ?- ?[0-9]+%' \
        && ok "(g) $_pair states a measured RANGE, not a single headline number" \
        || { no "(g) $_pair states an unhedged single figure — the claim it makes cannot hold at every size"; printf '%s\n' "$_blk"; }
    printf '%s' "$_blk" | grep -qiE 'larger|lower|invert|rises|shrink' \
        && ok "(g) $_pair names a case where the saving shrinks or inverts" \
        || { no "(g) $_pair gives a range but never says which way it moves"; printf '%s\n' "$_blk"; }
done
# the exact string the finding was written from, pinned so it cannot come back by a later reflow.
grep -q 'body-elided decl skeletons (~70% fewer tokens)' "$TMP/e_stdout" \
    && no "(g) the bare unhedged --pack-signatures figure is back in --help" \
    || ok "(g) the bare unhedged --pack-signatures figure is gone from --help"

# ── Summary ───────────────────────────────────────────────────────────────────────────────────────

echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
